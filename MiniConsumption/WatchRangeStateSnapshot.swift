import Foundation
#if canImport(WatchConnectivity)
import WatchConnectivity
#endif

struct WatchRangeStateSnapshot: Codable, Equatable {
    let batteryPercent: Double
    let roadTypeProfile: RoadTypeProfile
    let temperatureC: Double
    let activeVehicleProfileID: String?
    let availableVehicleProfiles: [VehicleProfile]?
    let vehicleProfileName: String
    let vehicleProfileKind: VehicleProfileDefinitionKind?
    let referenceConsumptionKWhPer100Km: Double?
    let usableBatteryKWh: Double
    let wltpRangeKm: Double
    let peakDCChargingKW: Double
    let batteryDegradationPercent: Int
    let motorwaySpeed: Double
    let roadSurface: RoadSurface
    let windCondition: WindCondition
    let airConditioningMode: AirConditioningMode
    let selectedTyreSet: TyreSet
    let summerTyreClass: RollingResistanceClass
    let winterTyreClass: RollingResistanceClass
    let useContinuousCalibration: Bool
    let displayUnitsRawValue: String?
    let temperatureUnitsRawValue: String?
}

enum WatchRangeStateSnapshotStore {
    static let appGroupID = "group.com.ontographist.rangepilot"
    static let storageKey = "watchRangeState.v1"
    static let lastSuccessfulPhoneSyncStorageKey = "watchRangeStateLastPhoneSync.v1"
    private static let snapshotPayloadKey = "watchRangeStateSnapshotData"
    private static let snapshotRequestKey = "requestWatchRangeStateSnapshot"
    private static let staleSyncInterval: TimeInterval = 60 * 60

    #if canImport(WatchConnectivity)
    private static let syncCoordinator = WatchRangeStateSnapshotSyncCoordinator()
    #endif

    static func load() -> WatchRangeStateSnapshot? {
        startSync()

        guard let defaults = UserDefaults(suiteName: appGroupID),
              let data = defaults.data(forKey: storageKey) else {
            return nil
        }

        return try? JSONDecoder().decode(WatchRangeStateSnapshot.self, from: data)
    }

    static func loadLatest(completion: @escaping (WatchRangeStateSnapshot?) -> Void) {
        startSync()

        #if os(watchOS) && canImport(WatchConnectivity)
        guard WCSession.isSupported(), WCSession.default.isReachable else {
            completion(load())
            return
        }

        WCSession.default.sendMessage([snapshotRequestKey: true]) { reply in
            guard let data = reply[snapshotPayloadKey] as? Data,
                  let snapshot = persistSnapshotData(data) else {
                completion(load())
                return
            }

            completion(snapshot)
        } errorHandler: { _ in
            completion(load())
        }
        #else
        completion(load())
        #endif
    }

    static func loadLatestFromPhone(completion: @escaping (WatchRangeStateSnapshot?) -> Void) {
        startSync()

        #if os(watchOS) && canImport(WatchConnectivity)
        guard WCSession.isSupported(), WCSession.default.isReachable else {
            completion(nil)
            return
        }

        WCSession.default.sendMessage([snapshotRequestKey: true]) { reply in
            guard let data = reply[snapshotPayloadKey] as? Data,
                  let snapshot = persistSnapshotData(data, markPhoneSync: true) else {
                completion(nil)
                return
            }

            completion(snapshot)
        } errorHandler: { _ in
            completion(nil)
        }
        #else
        completion(load())
        #endif
    }

    static func needsStartupRefresh(now: Date = Date()) -> Bool {
        #if os(watchOS)
        guard let defaults = UserDefaults(suiteName: appGroupID) else {
            return true
        }

        let lastSyncTime = defaults.double(forKey: lastSuccessfulPhoneSyncStorageKey)
        guard lastSyncTime > 0 else {
            return true
        }

        return now.timeIntervalSince1970 - lastSyncTime > staleSyncInterval
        #else
        return false
        #endif
    }

    static func startSync() {
        #if canImport(WatchConnectivity)
        guard WCSession.isSupported() else {
            return
        }

        syncCoordinator.activateIfNeeded()
        #endif
    }

    #if !os(watchOS)
    static func save(_ snapshot: WatchRangeStateSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else {
            return
        }

        persistSnapshotData(data)
        sendSnapshotData(data)
    }
    #endif

    @discardableResult
    private static func persistSnapshotData(
        _ data: Data,
        markPhoneSync: Bool = false
    ) -> WatchRangeStateSnapshot? {
        guard let defaults = UserDefaults(suiteName: appGroupID),
              let snapshot = try? JSONDecoder().decode(WatchRangeStateSnapshot.self, from: data) else {
            return nil
        }

        defaults.set(data, forKey: storageKey)
        #if os(watchOS)
        if markPhoneSync {
            defaults.set(Date().timeIntervalSince1970, forKey: lastSuccessfulPhoneSyncStorageKey)
        }
        #endif
        return snapshot
    }

    #if !os(watchOS) && canImport(WatchConnectivity)
    private static func sendSnapshotData(_ data: Data) {
        startSync()

        guard WCSession.isSupported() else {
            return
        }

        do {
            try WCSession.default.updateApplicationContext([snapshotPayloadKey: data])
        } catch {
            WCSession.default.transferUserInfo([snapshotPayloadKey: data])
        }
    }
    #endif

    #if canImport(WatchConnectivity)
    private final class WatchRangeStateSnapshotSyncCoordinator: NSObject, WCSessionDelegate {
        private var isActivated = false

        func activateIfNeeded() {
            guard isActivated == false,
                  WCSession.isSupported() else {
                return
            }

            isActivated = true
            WCSession.default.delegate = self
            WCSession.default.activate()
        }

        func session(
            _ session: WCSession,
            activationDidCompleteWith activationState: WCSessionActivationState,
            error: Error?
        ) {}

        func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
            persistSnapshot(from: applicationContext)
        }

        func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
            persistSnapshot(from: userInfo)
        }

        func session(
            _ session: WCSession,
            didReceiveMessage message: [String: Any],
            replyHandler: @escaping ([String: Any]) -> Void
        ) {
            #if !os(watchOS)
            guard message[snapshotRequestKey] as? Bool == true,
                  let defaults = UserDefaults(suiteName: appGroupID),
                  let data = defaults.data(forKey: storageKey) else {
                replyHandler([:])
                return
            }

            replyHandler([snapshotPayloadKey: data])
            #else
            replyHandler([:])
            #endif
        }

        #if os(iOS)
        func sessionDidBecomeInactive(_ session: WCSession) {}

        func sessionDidDeactivate(_ session: WCSession) {
            session.activate()
        }
        #endif

        private func persistSnapshot(from payload: [String: Any]) {
            guard let data = payload[snapshotPayloadKey] as? Data else {
                return
            }

            persistSnapshotData(data, markPhoneSync: true)
        }
    }
    #endif
}
