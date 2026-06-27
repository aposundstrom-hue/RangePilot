import SwiftUI

struct PaywallView: View {
    @ObservedObject var entitlementManager: EntitlementManager
    @State private var activationCode = ""
    @State private var activationMessage: String?
    @State private var activationSucceeded = false
    @State private var isShowingActivationCodeAlert = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 24)

            VStack(spacing: 12) {
                Text("RangePilot")
                    .font(.largeTitle.bold())

                Text("Your 14-day free trial has ended.")
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)

                Text("Unlock RangePilot with a one-time purchase.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Text("No subscription.")
                    .font(.body.weight(.semibold))
            }

            VStack(spacing: 16) {
                Button {
                    Task {
                        await entitlementManager.purchaseUnlock()
                    }
                } label: {
                    if entitlementManager.isPurchasing {
                        ProgressView()
                            .tint(.white)
                            .frame(maxWidth: .infinity)
                    } else {
                        Text(purchaseButtonTitle)
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(entitlementManager.unlockProduct == nil || entitlementManager.isPurchasing)

                HStack(spacing: 10) {
                    Button {
                        Task {
                            await entitlementManager.restorePurchases()
                        }
                    } label: {
                        Text(entitlementManager.isRestoring ? "Restoring..." : "Restore Purchases")
                    }
                    .font(.footnote.weight(.medium))
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .disabled(entitlementManager.isRestoring)

                    Text("|")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.tertiary)

                    Button("I have a code") {
                        isShowingActivationCodeAlert = true
                    }
                    .font(.footnote.weight(.medium))
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }

            if entitlementManager.isLoadingProducts {
                ProgressView("Loading purchase options...")
                    .font(.footnote)
            }

            if let errorMessage = entitlementManager.errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            Spacer(minLength: 32)

            if let activationMessage {
                Text(activationMessage)
                    .font(.footnote)
                    .foregroundStyle(activationSucceeded ? .green : .red)
                    .multilineTextAlignment(.center)
            }

            Spacer(minLength: 64)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
        .alert("Activation code", isPresented: $isShowingActivationCodeAlert) {
            TextField("Enter code", text: $activationCode)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()

            Button("Activate") {
                redeemActivationCode()
            }
            .disabled(activationCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            Button("Cancel", role: .cancel) {}
        }
        .task {
            await entitlementManager.refresh()
        }
    }

    private var purchaseButtonTitle: String {
        if let price = entitlementManager.unlockPriceText {
            return "Unlock for \(price)"
        }

        return "Unlock Unavailable"
    }

    private func redeemActivationCode() {
        let didRedeem = entitlementManager.redeemActivationCode(activationCode)
        activationSucceeded = didRedeem
        activationMessage = didRedeem ? "Activation code redeemed." : "Invalid activation code."

        if didRedeem {
            activationCode = ""
        }
    }
}
