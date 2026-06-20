import Foundation

struct MiniConsumptionSettingsSnapshot {
    private static let averageChargingSpeedOverridesStorageKey = "averageChargingSpeedKWByVehicleProfile.v1"

    let referenceConsumption: Double
    let tripDistance: Double
    let temperature: Double
    let airConditioningMode: AirConditioningMode
    let roadTypeProfile: RoadTypeProfile
    let motorwaySpeed: Double
    let roadSurface: RoadSurface
    let windCondition: WindCondition
    let planningMode: PlanningMode
    let currentBatteryPercent: Double
    let selectedTyreSet: TyreSet
    let summerTyreClass: RollingResistanceClass
    let winterTyreClass: RollingResistanceClass
    let rollingResistanceClass: RollingResistanceClass
    let useContinuousCalibration: Bool
    let batteryDegradationPercent: Int
    let activeForecastUsableBatteryKWh: Double
    let activeForecastUsesCustomVehicleProfile: Bool
    let arrivalBatteryTargetPercent: Double
    let normalMinimumChargingPercent: Double
    let normalFastChargeTargetPercent: Double
    let averageChargingSpeedKW: Double
    let tripChargingSetupMinutes: Double
    let displayUnits: DisplayUnits
    let temperatureUnits: TemperatureUnits
    let outcomes: [TripOutcome]

    var normalChargingWindow: ChargingWindow {
        ChargingWindow(
            minimumPercent: normalMinimumChargingPercent,
            targetPercent: normalFastChargeTargetPercent
        )
    }

    var tripPlanningChargingWindow: ChargingWindow {
        normalChargingWindow
    }

    var effectiveUsableBatteryKWh: Double {
        MiniConsumptionCalculator.effectiveUsableBatteryKWh(degradationPercent: batteryDegradationPercent)
    }

    var chargingTaperStartSOC: Double {
        MiniConsumptionCalculator.chargingTaperStartSOC(degradationPercent: batteryDegradationPercent)
    }

    var effectiveReferenceConsumption: Double {
        let calibrationCorrection = ContinuousCalibrationSummary(outcomes: outcomes, vehicleProfileKind: .mini)
            .correction(
                for: CalibrationPredictionContext(
                    roadTypeProfile: roadTypeProfile,
                    tyreSet: selectedTyreSet
                )
            )
        if useContinuousCalibration, calibrationCorrection.canApply {
            return MiniConsumptionCalculator.continuousCalibrationBaseReferenceConsumptionKWhPer100Km
                * calibrationCorrection.totalFactor
                * MiniConsumptionCalculator.calibrationSafetyMultiplier
        }

        return referenceConsumption
    }

    var activeRollingResistanceClass: RollingResistanceClass {
        selectedTyreSet == .summer ? summerTyreClass : winterTyreClass
    }

    static func load(defaults: UserDefaults = .standard) -> Self {
        let batteryDegradationPercent = defaults.int(
            forKey: "batteryDegradationPercent",
            defaultValue: MiniConsumptionDefaults.batteryDegradationPercent
        )
        let summerTyreClass = defaults.tyreClass(
            forKey: "summerTyreClass",
            defaultValue: MiniConsumptionDefaults.summerTyreClass
        )
        let winterTyreClass = defaults.tyreClass(
            forKey: "winterTyreClass",
            defaultValue: MiniConsumptionDefaults.winterTyreClass
        )
        let activeVehicleProfile = resolvedActiveVehicleProfile(
            defaults: defaults,
            batteryDegradationPercent: batteryDegradationPercent,
            summerTyreClass: summerTyreClass,
            winterTyreClass: winterTyreClass
        )
        let averageChargingSpeedKW = resolvedAverageChargingSpeedKW(
            defaults: defaults,
            for: activeVehicleProfile
        )

        return Self(
            referenceConsumption: defaults.double(forKey: "referenceConsumption", defaultValue: defaultReferenceConsumptionKWhPer100Km),
            tripDistance: defaults.double(forKey: "tripDistance", defaultValue: MiniConsumptionDefaults.tripDistanceKm),
            temperature: defaults.double(forKey: "temperature", defaultValue: MiniConsumptionDefaults.temperatureC),
            airConditioningMode: defaults.rawRepresentable(forKey: "airConditioningMode", defaultValue: MiniConsumptionDefaults.airConditioningMode),
            roadTypeProfile: defaults.rawRepresentable(forKey: "roadTypeProfile", defaultValue: MiniConsumptionDefaults.roadTypeProfile),
            motorwaySpeed: defaults.double(forKey: "motorwaySpeed", defaultValue: MiniConsumptionDefaults.motorwaySpeedKmh),
            roadSurface: defaults.rawRepresentable(forKey: "roadSurface", defaultValue: MiniConsumptionDefaults.roadSurface),
            windCondition: defaults.rawRepresentable(forKey: "windCondition", defaultValue: MiniConsumptionDefaults.windCondition),
            planningMode: defaults.rawRepresentable(forKey: "planningMode", defaultValue: MiniConsumptionDefaults.planningMode),
            currentBatteryPercent: defaults.double(forKey: "currentBatteryPercent", defaultValue: MiniConsumptionDefaults.currentBatteryPercent),
            selectedTyreSet: defaults.selectedTyreSet(),
            summerTyreClass: summerTyreClass,
            winterTyreClass: winterTyreClass,
            rollingResistanceClass: defaults.activeTyreClass(),
            useContinuousCalibration: defaults.bool(forKey: "useContinuousCalibration", defaultValue: MiniConsumptionDefaults.useContinuousCalibration),
            batteryDegradationPercent: batteryDegradationPercent,
            activeForecastUsableBatteryKWh: activeVehicleProfile.usableBatteryKWh,
            activeForecastUsesCustomVehicleProfile: activeVehicleProfile.kind == .custom,
            arrivalBatteryTargetPercent: defaults.double(forKey: "arrivalBatteryTargetPercent", defaultValue: ChargingWindow.defaultArrivalBatteryTargetPercent),
            normalMinimumChargingPercent: defaults.double(forKey: "normalMinimumChargingPercent", defaultValue: ChargingWindow.defaultMinimumPercent),
            normalFastChargeTargetPercent: defaults.double(forKey: "normalFastChargeTargetPercent", defaultValue: ChargingWindow.defaultTargetPercent),
            averageChargingSpeedKW: averageChargingSpeedKW,
            tripChargingSetupMinutes: defaults.double(forKey: "tripChargingSetupMinutes", defaultValue: defaultTripChargingSetupMinutes),
            displayUnits: defaults.rawRepresentable(forKey: "displayUnits", defaultValue: .metric),
            temperatureUnits: defaults.rawRepresentable(forKey: "temperatureUnits", defaultValue: .celsius),
            outcomes: TripOutcomeStore.load()
        )
    }

    private static func resolvedActiveVehicleProfile(
        defaults: UserDefaults,
        batteryDegradationPercent: Int,
        summerTyreClass: RollingResistanceClass,
        winterTyreClass: RollingResistanceClass
    ) -> VehicleProfile {
        let input = VehicleProfileResolverInput(
            experimentalCustomVehicleProfileEnabled: false,
            experimentalUsableBatteryCapacityKWh: VehicleProfileResolver.defaultCustomUsableBatteryCapacityKWh,
            experimentalOfficialWLTPRangeKm: VehicleProfileResolver.defaultCustomWLTPRangeKm,
            experimentalMaximumDCChargingSpeedKW: VehicleProfileResolver.defaultCustomPeakDCChargingKW,
            batteryDegradationPercent: batteryDegradationPercent,
            summerTyreClass: summerTyreClass,
            winterTyreClass: winterTyreClass
        )

        return VehicleProfileResolver.activeProfile(
            for: input,
            customProfiles: VehicleProfileStore.loadCustomProfiles(defaults: defaults),
            selectedProfileID: VehicleProfileStore.selectedProfileID(defaults: defaults)
        )
        .profile
    }

    private static func resolvedAverageChargingSpeedKW(
        defaults: UserDefaults,
        for profile: VehicleProfile
    ) -> Double {
        let defaultValue = MiniConsumptionCalculator.defaultAverageChargingSpeedKW(for: profile)
        let bounds = MiniConsumptionCalculator.averageChargingSpeedBoundsKW(for: profile)
        let value: Double

        if profile.kind == .custom {
            value = averageChargingSpeedOverridesByProfileID(defaults: defaults)[profile.id] ?? defaultValue
        } else {
            value = defaults.double(forKey: "averageChargingSpeedKW", defaultValue: defaultValue)
        }

        guard value.isFinite else {
            return clampedAverageChargingSpeedKW(defaultValue, in: bounds)
        }

        return clampedAverageChargingSpeedKW(value, in: bounds)
    }

    private static func averageChargingSpeedOverridesByProfileID(defaults: UserDefaults) -> [String: Double] {
        guard let data = defaults.data(forKey: averageChargingSpeedOverridesStorageKey),
              data.isEmpty == false,
              let overrides = try? JSONDecoder().decode([String: Double].self, from: data) else {
            return [:]
        }

        return overrides
    }

    private static func clampedAverageChargingSpeedKW(
        _ value: Double,
        in bounds: ClosedRange<Double>
    ) -> Double {
        min(max(value, bounds.lowerBound), bounds.upperBound)
    }

    func forecast(
        distance: Double,
        temperature: Double,
        roadTypeProfile: RoadTypeProfile,
        planningMode: PlanningMode,
        applyDistanceAdjustment: Bool = true
    ) -> ForecastResult {
        let calibrationCorrection = ContinuousCalibrationSummary(outcomes: outcomes, vehicleProfileKind: .mini)
            .correction(
                for: CalibrationPredictionContext(
                    roadTypeProfile: roadTypeProfile,
                    tyreSet: selectedTyreSet
                )
            )
        let ruleBasedForecast = MiniConsumptionCalculator.calculateForecast(
            referenceConsumption: calibratedForecastReferenceConsumption(for: calibrationCorrection),
            distance: distance,
            temperature: temperature,
            roadTypeProfile: roadTypeProfile,
            motorwaySpeed: motorwaySpeed,
            roadSurface: roadSurface,
            windCondition: windCondition,
            planningMode: planningMode,
            rollingResistanceClass: activeRollingResistanceClass,
            airConditioningMode: airConditioningMode,
            applyDistanceAdjustment: applyDistanceAdjustment,
            usesCustomVehicleProfile: activeForecastUsesCustomVehicleProfile,
            usableBatteryKWh: activeForecastUsableBatteryKWh
        )

        guard useContinuousCalibration else {
            return ruleBasedForecast
        }

        return ruleBasedForecast.applyingCalibrationFactor(calibrationCorrection.totalFactor)
    }

    func forecast(
        distance: Double,
        temperature: Double,
        roadTypeProfile: RoadTypeProfile,
        motorwaySpeed: Double,
        roadSurface: RoadSurface,
        windCondition: WindCondition,
        planningMode: PlanningMode,
        applyDistanceAdjustment: Bool = true
    ) -> ForecastResult {
        let calibrationCorrection = ContinuousCalibrationSummary(outcomes: outcomes, vehicleProfileKind: .mini)
            .correction(
                for: CalibrationPredictionContext(
                    roadTypeProfile: roadTypeProfile,
                    tyreSet: selectedTyreSet
                )
            )
        let ruleBasedForecast = MiniConsumptionCalculator.calculateForecast(
            referenceConsumption: calibratedForecastReferenceConsumption(for: calibrationCorrection),
            distance: distance,
            temperature: temperature,
            roadTypeProfile: roadTypeProfile,
            motorwaySpeed: motorwaySpeed,
            roadSurface: roadSurface,
            windCondition: windCondition,
            planningMode: planningMode,
            rollingResistanceClass: activeRollingResistanceClass,
            airConditioningMode: airConditioningMode,
            applyDistanceAdjustment: applyDistanceAdjustment,
            usesCustomVehicleProfile: activeForecastUsesCustomVehicleProfile,
            usableBatteryKWh: activeForecastUsableBatteryKWh
        )

        guard useContinuousCalibration else {
            return ruleBasedForecast
        }

        return ruleBasedForecast.applyingCalibrationFactor(calibrationCorrection.totalFactor)
    }

    private func calibratedForecastReferenceConsumption(for correction: CalibrationCorrection) -> Double {
        guard useContinuousCalibration, correction.canApply else {
            return referenceConsumption
        }

        return MiniConsumptionCalculator.continuousCalibrationBaseReferenceConsumptionKWhPer100Km
            * MiniConsumptionCalculator.calibrationSafetyMultiplier
    }
}

extension UserDefaults {
    func double(forKey key: String, defaultValue: Double) -> Double {
        object(forKey: key) as? Double ?? defaultValue
    }

    func bool(forKey key: String, defaultValue: Bool) -> Bool {
        object(forKey: key) as? Bool ?? defaultValue
    }

    func int(forKey key: String, defaultValue: Int) -> Int {
        object(forKey: key) as? Int ?? defaultValue
    }

    func rawRepresentable<Value>(forKey key: String, defaultValue: Value) -> Value where Value: RawRepresentable, Value.RawValue == String {
        guard let rawValue = string(forKey: key), let value = Value(rawValue: rawValue) else {
            return defaultValue
        }

        return value
    }

    func selectedTyreSet() -> TyreSet {
        if let tyreSet = rawRepresentableIfPresent(TyreSet.self, forKey: "selectedTyreSet") {
            return tyreSet
        }

        return bool(forKey: "winterTyres", defaultValue: false) ? .winter : MiniConsumptionDefaults.selectedTyreSet
    }

    func tyreClass(forKey key: String, defaultValue: RollingResistanceClass) -> RollingResistanceClass {
        rawRepresentableIfPresent(RollingResistanceClass.self, forKey: key)
            ?? rawRepresentable(forKey: "rollingResistanceClass", defaultValue: defaultValue)
    }

    func activeTyreClass() -> RollingResistanceClass {
        selectedTyreSet() == .summer
            ? tyreClass(forKey: "summerTyreClass", defaultValue: MiniConsumptionDefaults.summerTyreClass)
            : tyreClass(forKey: "winterTyreClass", defaultValue: MiniConsumptionDefaults.winterTyreClass)
    }

    private func rawRepresentableIfPresent<Value>(_ type: Value.Type, forKey key: String) -> Value? where Value: RawRepresentable, Value.RawValue == String {
        guard let rawValue = string(forKey: key) else {
            return nil
        }

        return Value(rawValue: rawValue)
    }
}
