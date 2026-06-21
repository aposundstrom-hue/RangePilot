//
//  RangePilotApp.swift
//  MiniConsumption
//
//  Created by Andreas Sundström on 2026-05-18.
//

import SwiftUI

@main
struct RangePilotApp: App {
    @StateObject private var entitlementManager = EntitlementManager()

    init() {
        MiniConsumptionInitialSetup.performIfNeeded()
        WatchRangeStateSnapshotStore.startSync()
    }

    var body: some Scene {
        WindowGroup {
            switch entitlementManager.accessState {
            case .unlocked, .trialActive:
                ContentView()
            case .trialExpired:
                if entitlementManager.hasCheckedPurchasedUnlock {
                    PaywallView(entitlementManager: entitlementManager)
                } else {
                    ProgressView()
                }
            }
        }
    }
}
