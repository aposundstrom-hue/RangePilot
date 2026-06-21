import SwiftUI

struct PaywallView: View {
    @ObservedObject var entitlementManager: EntitlementManager
    @State private var activationCode = ""
    @State private var activationMessage: String?
    @State private var activationSucceeded = false

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

            VStack(alignment: .leading, spacing: 8) {
                Text("Activation code")
                    .font(.headline)

                HStack(spacing: 8) {
                    TextField("Activation code", text: $activationCode)
                        .textFieldStyle(.roundedBorder)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .onSubmit {
                            redeemActivationCode()
                        }

                    Button("Redeem") {
                        redeemActivationCode()
                    }
                    .disabled(activationCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                if let activationMessage {
                    Text(activationMessage)
                        .font(.footnote)
                        .foregroundStyle(activationSucceeded ? .green : .red)
                }
            }
            .frame(maxWidth: 360)

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

    private func redeemActivationCode() {
        let didRedeem = entitlementManager.redeemActivationCode(activationCode)
        activationSucceeded = didRedeem
        activationMessage = didRedeem ? "Activation code redeemed." : "Invalid activation code."

        if didRedeem {
            activationCode = ""
        }
    }
}
