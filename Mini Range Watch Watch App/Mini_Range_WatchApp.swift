//
//  Mini_Range_WatchApp.swift
//  Mini Range Watch Watch App
//
//  Created by Andreas Sundström on 2026-06-07.
//

import SwiftUI

@main
struct Mini_Range_Watch_Watch_AppApp: App {
    init() {
        WatchRangeStateSnapshotStore.startSync()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
