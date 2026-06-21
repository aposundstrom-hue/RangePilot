import Foundation
import Combine
import StoreKit

enum AppAccessState: Equatable {
    case unlocked
    case trialActive(daysRemaining: Int)
    case trialExpired
}

private enum EntitlementError: Error {
    case failedVerification
}

@MainActor
final class EntitlementManager: ObservableObject {
    nonisolated static let unlockProductID = "com.ontographist.rangepilot.unlock"

    private static let firstFreemiumVersion = "1.2"
    private static let firstLaunchDateKey = "miniRangeTrialFirstLaunchDate"
    private static let manualUnlockKey = "hasManualActivation"
    private static let trialLengthDays = 14
    // Manual activation codes for reviewer/support use.
    // Intentionally offline and not intended as a general licensing system.
    private static let activationCodes: Set<String> = [
        "RP-7K4M-X92Q",
        "RP-T8FD-3P7L",
        "RP-M6RX-W4KC",
        "RP-Q9VN-2JHT",
        "RP-B3LW-8FDM"
    ]

    @Published private(set) var unlockProduct: Product?
    @Published private(set) var isUnlocked = false
    @Published private(set) var hasLegacyUnlock = false
    @Published private(set) var hasManualActivation = false
    @Published private(set) var accessState: AppAccessState
    @Published private(set) var hasCheckedPurchasedUnlock = false
    @Published private(set) var isLoadingProducts = false
    @Published private(set) var isPurchasing = false
    @Published private(set) var isRestoring = false
    @Published var errorMessage: String?

    private let defaults: UserDefaults
    private let productIDs: Set<String>
    private let calendar: Calendar
    private var transactionUpdatesTask: Task<Void, Never>?

    init(
        defaults: UserDefaults = .standard,
        productIDs: Set<String> = [unlockProductID],
        calendar: Calendar = .current
    ) {
        self.defaults = defaults
        self.productIDs = productIDs
        self.calendar = calendar

        let firstLaunchDate = Self.firstLaunchDate(defaults: defaults)
        let hasManualActivation = defaults.bool(forKey: Self.manualUnlockKey)
        self.hasManualActivation = hasManualActivation
        isUnlocked = hasManualActivation
        let initialAccessState = Self.accessState(
            firstLaunchDate: firstLaunchDate,
            isUnlocked: hasManualActivation,
            calendar: calendar
        )
        accessState = initialAccessState

        transactionUpdatesTask = listenForTransactionUpdates()

        Task {
            await refresh()
        }
    }

    deinit {
        transactionUpdatesTask?.cancel()
    }

    var unlockPriceText: String? {
        unlockProduct?.displayPrice
    }

    func refresh() async {
        await refreshPurchasedUnlock()
        await loadProducts()
    }

    func loadProducts() async {
        isLoadingProducts = true
        defer { isLoadingProducts = false }

        do {
            let products = try await Product.products(for: Array(productIDs))
            unlockProduct = products.first { $0.id == Self.unlockProductID }

            if unlockProduct == nil {
                errorMessage = "RangePilot unlock is currently unavailable. Please try again later."
            } else if errorMessage == "RangePilot unlock is currently unavailable. Please try again later." {
                errorMessage = nil
            }
        } catch {
            unlockProduct = nil
            errorMessage = "Could not load RangePilot unlock. Please check your connection and try again."
        }
    }

    func purchaseUnlock() async {
        errorMessage = nil

        guard let unlockProduct else {
            errorMessage = "RangePilot unlock is currently unavailable. Please try again later."
            await loadProducts()
            return
        }

        isPurchasing = true
        defer { isPurchasing = false }

        do {
            let result = try await unlockProduct.purchase()

            switch result {
            case .success(let verificationResult):
                let transaction = try verifiedTransaction(from: verificationResult)
                await transaction.finish()
                await refreshPurchasedUnlock()
            case .pending:
                errorMessage = "Purchase is pending approval."
            case .userCancelled:
                break
            @unknown default:
                errorMessage = "Purchase could not be completed. Please try again."
            }
        } catch StoreKitError.userCancelled {
            return
        } catch {
            errorMessage = "Purchase failed. Please try again."
        }
    }

    func restorePurchases() async {
        errorMessage = nil
        isRestoring = true
        defer { isRestoring = false }

        do {
            try await AppStore.sync()
            await refreshPurchasedUnlock()

            if isUnlocked == false {
                errorMessage = "No RangePilot unlock purchase was found for this Apple ID."
            }
        } catch {
            errorMessage = "Restore failed. Please try again."
        }
    }

    func redeemActivationCode(_ code: String) -> Bool {
        let normalizedCode = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard Self.activationCodes.contains(normalizedCode) else {
            return false
        }

        defaults.set(true, forKey: Self.manualUnlockKey)
        hasManualActivation = true
        isUnlocked = true
        updateAccessState()
        return true
    }

    private func listenForTransactionUpdates() -> Task<Void, Never> {
        Task { [weak self] in
            for await update in Transaction.updates {
                guard let self else { return }

                do {
                    let transaction = try self.verifiedTransaction(from: update)
                    await transaction.finish()
                    await self.refreshPurchasedUnlock()
                } catch {
                    await MainActor.run {
                        self.errorMessage = "Could not verify a purchase update."
                    }
                }
            }
        }
    }

    private func refreshPurchasedUnlock() async {
        let hasLegacyUnlock = await hasLegacyOriginalAppVersionUnlock()
        var hasPurchasedUnlock = false

        for await entitlement in Transaction.currentEntitlements {
            guard let transaction = try? verifiedTransaction(from: entitlement),
                  transaction.productID == Self.unlockProductID,
                  transaction.revocationDate == nil else {
                continue
            }

            hasPurchasedUnlock = true
            break
        }

        self.hasLegacyUnlock = hasLegacyUnlock
        hasManualActivation = defaults.bool(forKey: Self.manualUnlockKey)
        isUnlocked = hasLegacyUnlock || hasPurchasedUnlock || hasManualActivation
        hasCheckedPurchasedUnlock = true
        updateAccessState()
    }

    private func updateAccessState() {
        let resolvedAccessState = Self.accessState(
            firstLaunchDate: Self.firstLaunchDate(defaults: defaults),
            isUnlocked: isUnlocked,
            calendar: calendar
        )

        accessState = resolvedAccessState
    }

    private func verifiedTransaction(
        from result: VerificationResult<Transaction>
    ) throws -> Transaction {
        switch result {
        case .verified(let transaction):
            return transaction
        case .unverified:
            throw EntitlementError.failedVerification
        }
    }

    private func verifiedAppTransaction(
        from result: VerificationResult<AppTransaction>
    ) throws -> AppTransaction {
        switch result {
        case .verified(let appTransaction):
            return appTransaction
        case .unverified:
            throw EntitlementError.failedVerification
        }
    }

    private func hasLegacyOriginalAppVersionUnlock() async -> Bool {
        do {
            let appTransaction = try verifiedAppTransaction(from: try await AppTransaction.shared)
            return Self.isLegacyUnlockedOriginalAppVersion(appTransaction.originalAppVersion)
        } catch {
            return false
        }
    }

    private static func isLegacyUnlockedOriginalAppVersion(_ originalAppVersion: String) -> Bool {
        compareVersion(originalAppVersion, isEarlierThan: firstFreemiumVersion)
    }

    private static func compareVersion(_ version: String, isEarlierThan otherVersion: String) -> Bool {
        let lhsComponents = numericVersionComponents(from: version)
        let rhsComponents = numericVersionComponents(from: otherVersion)
        let componentCount = max(lhsComponents.count, rhsComponents.count)

        for index in 0..<componentCount {
            let lhsValue = index < lhsComponents.count ? lhsComponents[index] : 0
            let rhsValue = index < rhsComponents.count ? rhsComponents[index] : 0

            if lhsValue < rhsValue {
                return true
            }

            if lhsValue > rhsValue {
                return false
            }
        }

        return false
    }

    private static func numericVersionComponents(from version: String) -> [Int] {
        version
            .split(separator: ".")
            .map { Int($0) ?? 0 }
    }

    private static func firstLaunchDate(defaults: UserDefaults) -> Date {
        if let date = defaults.object(forKey: firstLaunchDateKey) as? Date {
            return date
        }

        let date = Date()
        defaults.set(date, forKey: firstLaunchDateKey)
        return date
    }

    private static func accessState(
        firstLaunchDate: Date,
        isUnlocked: Bool,
        calendar: Calendar
    ) -> AppAccessState {
        guard isUnlocked == false else {
            return .unlocked
        }

        guard let trialEndDate = calendar.date(
            byAdding: .day,
            value: trialLengthDays,
            to: firstLaunchDate
        ) else {
            return .trialExpired
        }

        let remainingSeconds = trialEndDate.timeIntervalSinceNow
        guard remainingSeconds > 0 else {
            return .trialExpired
        }

        let daysRemaining = max(1, Int(ceil(remainingSeconds / 86_400)))
        return .trialActive(daysRemaining: daysRemaining)
    }
}
