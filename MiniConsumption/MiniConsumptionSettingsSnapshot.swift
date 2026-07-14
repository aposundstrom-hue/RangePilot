import Foundation

struct MiniConsumptionSettingsSnapshot {
    let referenceConsumption: Double
    let defaultReferenceConsumption: Double
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
    let trailerTowModeEnabled: Bool
    let trailerWeightKg: Double
    let boxyTrailerEnabled: Bool
    let roofBoxMode: RoofBoxMode
    let batteryDegradationPercent: Int
    let activeForecastUsableBatteryKWh: Double
    let activeForecastUsesCustomVehicleProfile: Bool
    let activeVehicleProfile: VehicleProfile
    let resolvedChargingTaperStartSOC: Double
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
        activeForecastUsableBatteryKWh
    }

    var chargingTaperStartSOC: Double {
        resolvedChargingTaperStartSOC
    }

    var effectiveReferenceConsumption: Double {
        let calibrationCorrection = ContinuousCalibrationSummary(
            outcomes: outcomes,
            vehicleProfile: activeVehicleProfile
        )
            .correction(
                for: CalibrationPredictionContext(
                    roadTypeProfile: roadTypeProfile,
                    tyreSet: selectedTyreSet,
                    trailerTowModeEnabled: trailerTowModeEnabled
                )
            )
        return ReferenceConsumptionResolver.effectiveReference(
            profileDefault: defaultReferenceConsumption,
            manualReference: referenceConsumption,
            automaticCalibrationFactor: useContinuousCalibration && calibrationCorrection.canApply
                ? calibrationCorrection.totalFactor
                : nil
        )
    }

    var activeRollingResistanceClass: RollingResistanceClass {
        selectedTyreSet == .summer ? summerTyreClass : winterTyreClass
    }

    static func load(defaults: UserDefaults = .standard) -> Self {
        let effectiveProfile = EffectiveVehicleProfileSettingsResolver.resolve(defaults: defaults)
        let activeVehicleProfile = effectiveProfile.profile

        return Self(
            referenceConsumption: effectiveProfile.manualReferenceConsumption,
            defaultReferenceConsumption: effectiveProfile.defaultReferenceConsumption,
            tripDistance: defaults.double(forKey: "tripDistance", defaultValue: MiniConsumptionDefaults.tripDistanceKm),
            temperature: defaults.double(forKey: "temperature", defaultValue: MiniConsumptionDefaults.temperatureC),
            airConditioningMode: effectiveProfile.airConditioningMode,
            roadTypeProfile: defaults.rawRepresentable(forKey: "roadTypeProfile", defaultValue: MiniConsumptionDefaults.roadTypeProfile),
            motorwaySpeed: effectiveProfile.motorwaySpeed,
            roadSurface: defaults.rawRepresentable(forKey: "roadSurface", defaultValue: MiniConsumptionDefaults.roadSurface),
            windCondition: defaults.rawRepresentable(forKey: "windCondition", defaultValue: MiniConsumptionDefaults.windCondition),
            planningMode: defaults.rawRepresentable(forKey: "planningMode", defaultValue: MiniConsumptionDefaults.planningMode),
            currentBatteryPercent: defaults.double(forKey: "currentBatteryPercent", defaultValue: MiniConsumptionDefaults.currentBatteryPercent),
            selectedTyreSet: effectiveProfile.selectedTyreSet,
            summerTyreClass: effectiveProfile.summerTyreClass,
            winterTyreClass: effectiveProfile.winterTyreClass,
            rollingResistanceClass: effectiveProfile.activeRollingResistanceClass,
            useContinuousCalibration: effectiveProfile.useContinuousCalibration,
            trailerTowModeEnabled: defaults.bool(forKey: "trailerTowModeEnabled", defaultValue: false),
            trailerWeightKg: MiniConsumptionDefaults.normalizedTrailerWeightKg(
                defaults.double(forKey: "trailerWeightKg", defaultValue: MiniConsumptionDefaults.trailerWeightKg)
            ),
            boxyTrailerEnabled: defaults.bool(forKey: "boxyTrailerEnabled", defaultValue: false),
            roofBoxMode: defaults.rawRepresentable(forKey: "roofBoxMode", defaultValue: .off),
            batteryDegradationPercent: activeVehicleProfile.batteryDegradationPercent,
            activeForecastUsableBatteryKWh: activeVehicleProfile.usableBatteryKWh,
            activeForecastUsesCustomVehicleProfile: activeVehicleProfile.kind == .custom,
            activeVehicleProfile: activeVehicleProfile,
            resolvedChargingTaperStartSOC: effectiveProfile.chargingTaperStartSOC,
            arrivalBatteryTargetPercent: defaults.double(forKey: "arrivalBatteryTargetPercent", defaultValue: ChargingWindow.defaultArrivalBatteryTargetPercent),
            normalMinimumChargingPercent: effectiveProfile.normalMinimumChargingPercent,
            normalFastChargeTargetPercent: effectiveProfile.normalFastChargeTargetPercent,
            averageChargingSpeedKW: effectiveProfile.averageChargingSpeedKW,
            tripChargingSetupMinutes: defaults.double(forKey: "tripChargingSetupMinutes", defaultValue: defaultTripChargingSetupMinutes),
            displayUnits: defaults.rawRepresentable(forKey: "displayUnits", defaultValue: .metric),
            temperatureUnits: defaults.rawRepresentable(forKey: "temperatureUnits", defaultValue: .celsius),
            outcomes: TripOutcomeStore.load()
        )
    }

    func forecast(
        distance: Double,
        temperature: Double,
        roadTypeProfile: RoadTypeProfile,
        planningMode: PlanningMode,
        applyDistanceAdjustment: Bool = true
    ) -> ForecastResult {
        let calibrationCorrection = ContinuousCalibrationSummary(
            outcomes: outcomes,
            vehicleProfile: activeVehicleProfile
        )
            .correction(
                for: CalibrationPredictionContext(
                    roadTypeProfile: roadTypeProfile,
                    tyreSet: selectedTyreSet,
                    trailerTowModeEnabled: trailerTowModeEnabled
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

        return scenarioEquipment.applying(
            to: ruleBasedForecast,
            roadTypeProfile: roadTypeProfile,
            motorwaySpeed: motorwaySpeed,
            calibrationFactor: useContinuousCalibration ? calibrationCorrection.totalFactor : nil
        )
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
        let calibrationCorrection = ContinuousCalibrationSummary(
            outcomes: outcomes,
            vehicleProfile: activeVehicleProfile
        )
            .correction(
                for: CalibrationPredictionContext(
                    roadTypeProfile: roadTypeProfile,
                    tyreSet: selectedTyreSet,
                    trailerTowModeEnabled: trailerTowModeEnabled
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

        return scenarioEquipment.applying(
            to: ruleBasedForecast,
            roadTypeProfile: roadTypeProfile,
            motorwaySpeed: motorwaySpeed,
            calibrationFactor: useContinuousCalibration ? calibrationCorrection.totalFactor : nil
        )
    }

    private func calibratedForecastReferenceConsumption(for correction: CalibrationCorrection) -> Double {
        ReferenceConsumptionResolver.forecastBaseline(
            profileDefault: defaultReferenceConsumption,
            manualReference: referenceConsumption,
            automaticCalibrationCanApply: useContinuousCalibration && correction.canApply
        )
    }

    private var scenarioEquipment: ScenarioEquipmentSettings {
        ScenarioEquipmentSettings(
            trailerTowModeEnabled: trailerTowModeEnabled,
            trailerWeightKg: trailerWeightKg,
            boxyTrailerEnabled: boxyTrailerEnabled,
            roofBoxMode: roofBoxMode
        )
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
