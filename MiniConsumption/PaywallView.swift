import SwiftUI

struct PaywallView: View {
    @ObservedObject var entitlementManager: EntitlementManager

    var body: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 24)

            VStack(spacing: 12) {
                Text("Mini Range")
                    .font(.largeTitle.bold())

                Text("Your 14-day free trial has ended.")
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)

                Text("Unlock Mini Range with a one-time purchase.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Text("No subscription.")
                    .font(.body.weight(.semibold))
            }

            VStack(spacing: 12) {
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

                Button {
                    Task {
                        await entitlementManager.restorePurchases()
                    }
                } label: {
                    if entitlementManager.isRestoring {
                        ProgressView()
                    } else {
                        Text("Restore Purchases")
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(entitlementManager.isRestoring)
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

            Spacer(minLength: 64)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
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
}
