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
    let effectiveReferenceConsumptionKWhPer100Km: Double?
    let automaticCalibrationFactor: Double?
    let usableBatteryKWh: Double
    let effectiveUsableBatteryKWh: Double?
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
    let trailerTowModeEnabled: Bool
    let trailerWeightKg: Double
    let boxyTrailerEnabled: Bool
    let roofBoxMode: RoofBoxMode
    let displayUnitsRawValue: String?
    let temperatureUnitsRawValue: String?

    init(
        batteryPercent: Double,
        roadTypeProfile: RoadTypeProfile,
        temperatureC: Double,
        activeVehicleProfileID: String?,
        availableVehicleProfiles: [VehicleProfile]?,
        vehicleProfileName: String,
        vehicleProfileKind: VehicleProfileDefinitionKind?,
        referenceConsumptionKWhPer100Km: Double?,
        effectiveReferenceConsumptionKWhPer100Km: Double?,
        automaticCalibrationFactor: Double?,
        usableBatteryKWh: Double,
        effectiveUsableBatteryKWh: Double?,
        wltpRangeKm: Double,
        peakDCChargingKW: Double,
        batteryDegradationPercent: Int,
        motorwaySpeed: Double,
        roadSurface: RoadSurface,
        windCondition: WindCondition,
        airConditioningMode: AirConditioningMode,
        selectedTyreSet: TyreSet,
        summerTyreClass: RollingResistanceClass,
        winterTyreClass: RollingResistanceClass,
        useContinuousCalibration: Bool,
        trailerTowModeEnabled: Bool,
        trailerWeightKg: Double,
        boxyTrailerEnabled: Bool,
        roofBoxMode: RoofBoxMode,
        displayUnitsRawValue: String?,
        temperatureUnitsRawValue: String?
    ) {
        self.batteryPercent = batteryPercent
        self.roadTypeProfile = roadTypeProfile
        self.temperatureC = temperatureC
        self.activeVehicleProfileID = activeVehicleProfileID
        self.availableVehicleProfiles = availableVehicleProfiles
        self.vehicleProfileName = vehicleProfileName
        self.vehicleProfileKind = vehicleProfileKind
        self.referenceConsumptionKWhPer100Km = referenceConsumptionKWhPer100Km
        self.effectiveReferenceConsumptionKWhPer100Km = effectiveReferenceConsumptionKWhPer100Km
        self.automaticCalibrationFactor = automaticCalibrationFactor
        self.usableBatteryKWh = usableBatteryKWh
        self.effectiveUsableBatteryKWh = effectiveUsableBatteryKWh
        self.wltpRangeKm = wltpRangeKm
        self.peakDCChargingKW = peakDCChargingKW
        self.batteryDegradationPercent = batteryDegradationPercent
        self.motorwaySpeed = motorwaySpeed
        self.roadSurface = roadSurface
        self.windCondition = windCondition
        self.airConditioningMode = airConditioningMode
        self.selectedTyreSet = selectedTyreSet
        self.summerTyreClass = summerTyreClass
        self.winterTyreClass = winterTyreClass
        self.useContinuousCalibration = useContinuousCalibration
        self.trailerTowModeEnabled = trailerTowModeEnabled
        self.trailerWeightKg = MiniConsumptionDefaults.normalizedTrailerWeightKg(trailerWeightKg)
        self.boxyTrailerEnabled = boxyTrailerEnabled
        self.roofBoxMode = roofBoxMode
        self.displayUnitsRawValue = displayUnitsRawValue
        self.temperatureUnitsRawValue = temperatureUnitsRawValue
    }

    private enum CodingKeys: String, CodingKey {
        case batteryPercent, roadTypeProfile, temperatureC, activeVehicleProfileID
        case availableVehicleProfiles, vehicleProfileName, vehicleProfileKind
        case referenceConsumptionKWhPer100Km, effectiveReferenceConsumptionKWhPer100Km, automaticCalibrationFactor
        case usableBatteryKWh, effectiveUsableBatteryKWh, wltpRangeKm, peakDCChargingKW, batteryDegradationPercent
        case motorwaySpeed, roadSurface, windCondition, airConditioningMode
        case selectedTyreSet, summerTyreClass, winterTyreClass, useContinuousCalibration
        case trailerTowModeEnabled, trailerWeightKg, boxyTrailerEnabled, roofBoxMode
        case displayUnitsRawValue, temperatureUnitsRawValue
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            batteryPercent: try container.decode(Double.self, forKey: .batteryPercent),
            roadTypeProfile: try container.decode(RoadTypeProfile.self, forKey: .roadTypeProfile),
            temperatureC: try container.decode(Double.self, forKey: .temperatureC),
            activeVehicleProfileID: try container.decodeIfPresent(String.self, forKey: .activeVehicleProfileID),
            availableVehicleProfiles: try container.decodeIfPresent([VehicleProfile].self, forKey: .availableVehicleProfiles),
            vehicleProfileName: try container.decode(String.self, forKey: .vehicleProfileName),
            vehicleProfileKind: try container.decodeIfPresent(VehicleProfileDefinitionKind.self, forKey: .vehicleProfileKind),
            referenceConsumptionKWhPer100Km: try container.decodeIfPresent(Double.self, forKey: .referenceConsumptionKWhPer100Km),
            effectiveReferenceConsumptionKWhPer100Km: try container.decodeIfPresent(Double.self, forKey: .effectiveReferenceConsumptionKWhPer100Km),
            automaticCalibrationFactor: try container.decodeIfPresent(Double.self, forKey: .automaticCalibrationFactor),
            usableBatteryKWh: try container.decode(Double.self, forKey: .usableBatteryKWh),
            effectiveUsableBatteryKWh: try container.decodeIfPresent(Double.self, forKey: .effectiveUsableBatteryKWh),
            wltpRangeKm: try container.decode(Double.self, forKey: .wltpRangeKm),
            peakDCChargingKW: try container.decode(Double.self, forKey: .peakDCChargingKW),
            batteryDegradationPercent: try container.decode(Int.self, forKey: .batteryDegradationPercent),
            motorwaySpeed: try container.decode(Double.self, forKey: .motorwaySpeed),
            roadSurface: try container.decode(RoadSurface.self, forKey: .roadSurface),
            windCondition: try container.decode(WindCondition.self, forKey: .windCondition),
            airConditioningMode: try container.decode(AirConditioningMode.self, forKey: .airConditioningMode),
            selectedTyreSet: (try? container.decode(TyreSet.self, forKey: .selectedTyreSet))
                ?? MiniConsumptionDefaults.selectedTyreSet,
            summerTyreClass: (try? container.decode(RollingResistanceClass.self, forKey: .summerTyreClass))
                ?? MiniConsumptionDefaults.summerTyreClass,
            winterTyreClass: (try? container.decode(RollingResistanceClass.self, forKey: .winterTyreClass))
                ?? MiniConsumptionDefaults.winterTyreClass,
            useContinuousCalibration: try container.decodeIfPresent(Bool.self, forKey: .useContinuousCalibration) ?? MiniConsumptionDefaults.useContinuousCalibration,
            trailerTowModeEnabled: try container.decodeIfPresent(Bool.self, forKey: .trailerTowModeEnabled) ?? false,
            trailerWeightKg: try container.decodeIfPresent(Double.self, forKey: .trailerWeightKg) ?? MiniConsumptionDefaults.trailerWeightKg,
            boxyTrailerEnabled: try container.decodeIfPresent(Bool.self, forKey: .boxyTrailerEnabled) ?? false,
            roofBoxMode: try container.decodeIfPresent(RoofBoxMode.self, forKey: .roofBoxMode) ?? .off,
            displayUnitsRawValue: try container.decodeIfPresent(String.self, forKey: .displayUnitsRawValue),
            temperatureUnitsRawValue: try container.decodeIfPresent(String.self, forKey: .temperatureUnitsRawValue)
        )
    }
}

enum WatchRangeStateSnapshotStore {
    static let appGroupID = "group.com.ontographist.MiniConsumption"
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
