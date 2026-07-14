import Foundation

enum VehicleProfileDefinitionKind: String, Codable {
    case builtInMini
    case custom
}

struct VehicleProfile: Codable, Equatable, Identifiable {
    let id: String
    var displayName: String
    var kind: VehicleProfileDefinitionKind
    var usableBatteryKWh: Double
    var wltpRangeKm: Double
    var peakDCChargingKW: Double
    var batteryDegradationPercent: Int
    var summerTyreClass: RollingResistanceClass
    var winterTyreClass: RollingResistanceClass
    var createdAt: Date?
    var updatedAt: Date?

    var effectiveUsableBatteryKWh: Double {
        MiniConsumptionCalculator.effectiveUsableBatteryKWh(
            originalUsableBatteryKWh: usableBatteryKWh,
            degradationPercent: batteryDegradationPercent
        )
    }

    init(
        id: String,
        displayName: String,
        kind: VehicleProfileDefinitionKind,
        usableBatteryKWh: Double,
        wltpRangeKm: Double,
        peakDCChargingKW: Double,
        batteryDegradationPercent: Int,
        summerTyreClass: RollingResistanceClass,
        winterTyreClass: RollingResistanceClass,
        createdAt: Date?,
        updatedAt: Date?
    ) {
        self.id = id
        self.displayName = displayName
        self.kind = kind
        self.usableBatteryKWh = usableBatteryKWh
        self.wltpRangeKm = wltpRangeKm
        self.peakDCChargingKW = peakDCChargingKW
        self.batteryDegradationPercent = MiniConsumptionCalculator.normalizedBatteryDegradationPercent(
            batteryDegradationPercent
        )
        self.summerTyreClass = summerTyreClass
        self.winterTyreClass = winterTyreClass
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case displayName
        case legacyName = "name"
        case kind
        case usableBatteryKWh
        case wltpRangeKm
        case peakDCChargingKW
        case batteryDegradationPercent
        case summerTyreClass
        case winterTyreClass
        case createdAt
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(String.self, forKey: .id)
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
            ?? container.decodeIfPresent(String.self, forKey: .legacyName)
            ?? ""
        kind = try container.decode(VehicleProfileDefinitionKind.self, forKey: .kind)
        usableBatteryKWh = try container.decode(Double.self, forKey: .usableBatteryKWh)
        wltpRangeKm = try container.decode(Double.self, forKey: .wltpRangeKm)
        peakDCChargingKW = try container.decode(Double.self, forKey: .peakDCChargingKW)
        batteryDegradationPercent = MiniConsumptionCalculator.normalizedBatteryDegradationPercent(
            try container.decodeIfPresent(Int.self, forKey: .batteryDegradationPercent)
                ?? MiniConsumptionDefaults.batteryDegradationPercent
        )
        summerTyreClass = (try? container.decode(RollingResistanceClass.self, forKey: .summerTyreClass))
            ?? MiniConsumptionDefaults.summerTyreClass
        winterTyreClass = (try? container.decode(RollingResistanceClass.self, forKey: .winterTyreClass))
            ?? MiniConsumptionDefaults.winterTyreClass
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt)
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(id, forKey: .id)
        try container.encode(displayName, forKey: .displayName)
        try container.encode(kind, forKey: .kind)
        try container.encode(usableBatteryKWh, forKey: .usableBatteryKWh)
        try container.encode(wltpRangeKm, forKey: .wltpRangeKm)
        try container.encode(peakDCChargingKW, forKey: .peakDCChargingKW)
        try container.encode(batteryDegradationPercent, forKey: .batteryDegradationPercent)
        try container.encode(summerTyreClass, forKey: .summerTyreClass)
        try container.encode(winterTyreClass, forKey: .winterTyreClass)
        try container.encodeIfPresent(createdAt, forKey: .createdAt)
        try container.encodeIfPresent(updatedAt, forKey: .updatedAt)
    }
}

struct VehicleProfileTemplate: Equatable, Identifiable {
    static let customProfileID = "custom"

    let id: String
    let brand: String
    let modelName: String
    let displayName: String
    let usableBatteryKWh: Double
    let wltpRangeKm: Double
    let peakDCChargingKW: Double

    init(
        id: String,
        brand: String,
        modelName: String,
        displayName: String,
        usableBatteryKWh: Double,
        wltpRangeKm: Double,
        peakDCChargingKW: Double
    ) {
        self.id = id
        self.brand = brand
        self.modelName = modelName
        self.displayName = displayName
        self.usableBatteryKWh = usableBatteryKWh
        self.wltpRangeKm = wltpRangeKm
        self.peakDCChargingKW = peakDCChargingKW
    }
}

struct ActiveVehicleProfile: Equatable {
    let profile: VehicleProfile
    let loggedTripKind: VehicleProfileKind

    var usesCustomEVBehavior: Bool {
        profile.kind == .custom
    }
}

struct VehicleProfileResolverInput: Equatable {
    var experimentalCustomVehicleProfileEnabled: Bool
    var experimentalUsableBatteryCapacityKWh: Double
    var experimentalOfficialWLTPRangeKm: Double
    var experimentalMaximumDCChargingSpeedKW: Double
    var batteryDegradationPercent: Int
    var summerTyreClass: RollingResistanceClass
    var winterTyreClass: RollingResistanceClass
}

enum VehicleProfileResolver {
    static let builtInMiniProfileID = "builtInMini"
    static let legacyCustomEVProfileID = "legacyCustomEV"
    static let builtInMiniName = "MINI Cooper SE (F56)"
    static let legacyCustomEVName = "Custom EV"

    static let defaultCustomUsableBatteryCapacityKWh = 28.9
    static let defaultCustomWLTPRangeKm = 234.0
    static let defaultCustomPeakDCChargingKW = 50.0
    static let builtInMiniWLTPRangeKm = 234.0
    static let builtInMiniPeakDCChargingKW = 50.0

    static func activeProfile(for input: VehicleProfileResolverInput) -> ActiveVehicleProfile {
        if input.experimentalCustomVehicleProfileEnabled {
            return ActiveVehicleProfile(
                profile: customEVProfile(from: input),
                loggedTripKind: .customEV
            )
        }

        return ActiveVehicleProfile(
            profile: builtInMiniProfile(from: input),
            loggedTripKind: .mini
        )
    }

    static func activeProfile(
        for input: VehicleProfileResolverInput,
        customProfiles: [VehicleProfile],
        selectedProfileID: String?
    ) -> ActiveVehicleProfile {
        guard let selectedProfileID = selectedProfileID?.trimmingCharacters(in: .whitespacesAndNewlines),
              selectedProfileID.isEmpty == false else {
            return activeProfile(for: input)
        }

        if selectedProfileID == builtInMiniProfileID {
            return ActiveVehicleProfile(
                profile: builtInMiniProfile(from: input),
                loggedTripKind: .mini
            )
        }

        if let selectedProfile = customProfiles.first(where: { $0.id == selectedProfileID }) {
            return ActiveVehicleProfile(
                profile: selectedProfile,
                loggedTripKind: .customEV
            )
        }

        return ActiveVehicleProfile(
            profile: builtInMiniProfile(from: input),
            loggedTripKind: .mini
        )
    }

    static func builtInMiniProfile(from input: VehicleProfileResolverInput) -> VehicleProfile {
        VehicleProfile(
            id: builtInMiniProfileID,
            displayName: builtInMiniName,
            kind: .builtInMini,
            usableBatteryKWh: MiniConsumptionCalculator.nominalUsableBatteryKWh,
            wltpRangeKm: builtInMiniWLTPRangeKm,
            peakDCChargingKW: builtInMiniPeakDCChargingKW,
            batteryDegradationPercent: input.batteryDegradationPercent,
            summerTyreClass: input.summerTyreClass,
            winterTyreClass: input.winterTyreClass,
            createdAt: nil,
            updatedAt: nil
        )
    }

    static func customEVProfile(from input: VehicleProfileResolverInput) -> VehicleProfile {
        VehicleProfile(
            id: legacyCustomEVProfileID,
            displayName: legacyCustomEVName,
            kind: .custom,
            usableBatteryKWh: positiveFinite(
                input.experimentalUsableBatteryCapacityKWh,
                fallback: defaultCustomUsableBatteryCapacityKWh
            ),
            wltpRangeKm: positiveFinite(
                input.experimentalOfficialWLTPRangeKm,
                fallback: defaultCustomWLTPRangeKm
            ),
            peakDCChargingKW: positiveFinite(
                input.experimentalMaximumDCChargingSpeedKW,
                fallback: defaultCustomPeakDCChargingKW
            ),
            batteryDegradationPercent: input.batteryDegradationPercent,
            summerTyreClass: input.summerTyreClass,
            winterTyreClass: input.winterTyreClass,
            createdAt: nil,
            updatedAt: nil
        )
    }

    private static func positiveFinite(_ value: Double, fallback: Double) -> Double {
        value.isFinite && value > 0 ? value : fallback
    }
}

// Settings ownership model:
// - Vehicle profile: vehicle specifications, degradation, calibration, normal charging,
//   tyres, motorway-speed default, and A/C default. Some remain in profile-ID override
//   dictionaries until a later storage migration.
// - Current drive/scenario: battery, weather/road conditions, trailer, and roof box.
// - Trip-local: planned distance, starting battery, arrival reserve, charging-stop levels,
//   and per-trip condition/equipment overrides.
// - Global app preferences: units, Range presentation/map options, onboarding, and access.
// - Trip defaults: Quick Trip distance, planning mode, arrival reserve, and setup time.
struct EffectiveVehicleProfileSettings {
    let profile: VehicleProfile
    let defaultReferenceConsumption: Double
    let manualReferenceConsumption: Double
    let motorwaySpeed: Double
    let airConditioningMode: AirConditioningMode
    let selectedTyreSet: TyreSet
    let summerTyreClass: RollingResistanceClass
    let winterTyreClass: RollingResistanceClass
    let normalMinimumChargingPercent: Double
    let normalFastChargeTargetPercent: Double
    let averageChargingSpeedKW: Double
    let chargingTaperStartSOC: Double
    let useContinuousCalibration: Bool

    var activeRollingResistanceClass: RollingResistanceClass {
        selectedTyreSet == .summer ? summerTyreClass : winterTyreClass
    }
}

struct EffectiveTyreSettings: Equatable {
    let selectedTyreSet: TyreSet
    let summerTyreClass: RollingResistanceClass
    let winterTyreClass: RollingResistanceClass

    var activeRollingResistanceClass: RollingResistanceClass {
        selectedTyreSet == .summer ? summerTyreClass : winterTyreClass
    }
}

enum ReferenceConsumptionResolver {
    static let manualOverrideBounds = 9.5...20.0
    static let legacyFallbackSuppressedProfileIDsKey = "referenceConsumptionLegacyFallbackSuppressedProfileIDs.v1"
    private static let profileDefaultCompatibilityOverrides = [
        VehicleProfileResolver.builtInMiniProfileID: defaultReferenceConsumptionKWhPer100Km
    ]

    static func profileDerivedDefault(for profile: VehicleProfile) -> Double {
        if let compatibilityDefault = profileDefaultCompatibilityOverrides[profile.id] {
            return clamped(compatibilityDefault, fallback: defaultReferenceConsumptionKWhPer100Km)
        }

        let usableBatteryKWh = positiveFinite(
            profile.usableBatteryKWh,
            fallback: VehicleProfileResolver.defaultCustomUsableBatteryCapacityKWh
        )
        let wltpRangeKm = positiveFinite(
            profile.wltpRangeKm,
            fallback: VehicleProfileResolver.defaultCustomWLTPRangeKm
        )
        let derivedDefault = (usableBatteryKWh / wltpRangeKm * 100) * 1.04
        return clamped(derivedDefault, fallback: defaultReferenceConsumptionKWhPer100Km)
    }

    static func manualReference(
        for profile: VehicleProfile,
        overrides: [String: Double],
        legacyBuiltInValue: Double?,
        legacyFallbackSuppressedProfileIDs: Set<String>
    ) -> Double {
        let profileDefault = profileDerivedDefault(for: profile)
        let resolvedValue = overrides[profile.id]
            ?? legacyCompatibilityValue(
                for: profile.id,
                value: legacyBuiltInValue,
                suppressedProfileIDs: legacyFallbackSuppressedProfileIDs
            )
            ?? profileDefault
        return clamped(resolvedValue, fallback: profileDefault)
    }

    static func forecastBaseline(
        profileDefault: Double,
        manualReference: Double,
        automaticCalibrationCanApply: Bool
    ) -> Double {
        automaticCalibrationCanApply
            ? profileDefault * MiniConsumptionCalculator.calibrationSafetyMultiplier
            : manualReference
    }

    static func effectiveReference(
        profileDefault: Double,
        manualReference: Double,
        automaticCalibrationFactor: Double?
    ) -> Double {
        guard let automaticCalibrationFactor else {
            return manualReference
        }

        return profileDefault
            * MiniConsumptionCalculator.calibrationSafetyMultiplier
            * automaticCalibrationFactor
    }

    private static func legacyCompatibilityValue(
        for profileID: String,
        value: Double?,
        suppressedProfileIDs: Set<String>
    ) -> Double? {
        guard suppressedProfileIDs.contains(profileID) == false,
              let value else {
            return nil
        }
        return [VehicleProfileResolver.builtInMiniProfileID: value][profileID]
    }

    private static func positiveFinite(_ value: Double, fallback: Double) -> Double {
        value.isFinite && value > 0 ? value : fallback
    }

    private static func clamped(_ value: Double, fallback: Double) -> Double {
        let finiteValue = value.isFinite ? value : fallback
        return min(max(finiteValue, manualOverrideBounds.lowerBound), manualOverrideBounds.upperBound)
    }
}

enum EffectiveVehicleProfileSettingsResolver {
    static let batteryDegradationOverridesKey = "batteryDegradationByVehicleProfile.v1"
    static let useContinuousCalibrationOverridesKey = "useContinuousCalibrationByVehicleProfile.v1"
    static let normalMinimumChargingPercentOverridesKey = "normalMinimumChargingPercentByVehicleProfile.v1"
    static let normalFastChargeTargetPercentOverridesKey = "normalFastChargeTargetPercentByVehicleProfile.v1"
    static let averageChargingSpeedOverridesKey = "averageChargingSpeedKWByVehicleProfile.v1"
    private static let referenceConsumptionOverridesKey = "referenceConsumptionByVehicleProfile.v1"
    static let motorwaySpeedOverridesKey = "motorwaySpeedByVehicleProfile.v1"
    static let airConditioningModeOverridesKey = "airConditioningModeByVehicleProfile.v1"
    static let selectedTyreSetOverridesKey = "selectedTyreSetByVehicleProfile.v1"
    static let summerTyreClassOverridesKey = "summerTyreClassByVehicleProfile.v1"
    static let winterTyreClassOverridesKey = "winterTyreClassByVehicleProfile.v1"

    static func resolve(defaults: UserDefaults = .standard) -> EffectiveVehicleProfileSettings {
        let legacyMiniDegradation = int(
            defaults: defaults,
            key: "batteryDegradationPercent",
            fallback: MiniConsumptionDefaults.batteryDegradationPercent
        )
        let miniDegradation = batteryDegradationPercent(
            for: VehicleProfileResolver.builtInMiniProfileID,
            legacyBuiltInValue: legacyMiniDegradation,
            defaults: defaults
        )
        let input = VehicleProfileResolverInput(
            experimentalCustomVehicleProfileEnabled: false,
            experimentalUsableBatteryCapacityKWh: VehicleProfileResolver.defaultCustomUsableBatteryCapacityKWh,
            experimentalOfficialWLTPRangeKm: VehicleProfileResolver.defaultCustomWLTPRangeKm,
            experimentalMaximumDCChargingSpeedKW: VehicleProfileResolver.defaultCustomPeakDCChargingKW,
            batteryDegradationPercent: miniDegradation,
            summerTyreClass: MiniConsumptionDefaults.summerTyreClass,
            winterTyreClass: MiniConsumptionDefaults.winterTyreClass
        )
        let profile = VehicleProfileResolver.activeProfile(
            for: input,
            customProfiles: VehicleProfileStore.loadCustomProfiles(defaults: defaults),
            selectedProfileID: VehicleProfileStore.selectedProfileID(defaults: defaults)
        ).profile

        return resolve(profile: profile, defaults: defaults)
    }

    static func resolve(
        profile: VehicleProfile,
        defaults: UserDefaults = .standard
    ) -> EffectiveVehicleProfileSettings {
        let globalReferenceConsumption = double(
            defaults: defaults,
            key: "referenceConsumption",
            fallback: defaultReferenceConsumptionKWhPer100Km
        )
        let resolvedMotorwaySpeed = motorwaySpeed(for: profile, defaults: defaults)
        let resolvedAirConditioningMode = airConditioningMode(for: profile, defaults: defaults)
        let resolvedTyres = tyreSettings(for: profile, defaults: defaults)
        let defaultReferenceConsumption = ReferenceConsumptionResolver.profileDerivedDefault(for: profile)
        let referenceOverrides: [String: Double] = overrides(defaults: defaults, key: referenceConsumptionOverridesKey)
        let suppressedLegacyFallbackProfileIDs = Set(
            defaults.stringArray(forKey: ReferenceConsumptionResolver.legacyFallbackSuppressedProfileIDsKey) ?? []
        )
        let manualReferenceConsumption = ReferenceConsumptionResolver.manualReference(
            for: profile,
            overrides: referenceOverrides,
            legacyBuiltInValue: defaults.object(forKey: "referenceConsumption") == nil
                ? nil
                : globalReferenceConsumption,
            legacyFallbackSuppressedProfileIDs: suppressedLegacyFallbackProfileIDs
        )
        let resolvedMinimumChargingPercent = normalMinimumChargingPercent(for: profile, defaults: defaults)
        let resolvedFastChargeTargetPercent = normalFastChargeTargetPercent(for: profile, defaults: defaults)
        let resolvedAverageChargingSpeed = averageChargingSpeedKW(for: profile, defaults: defaults)
        let resolvedChargingTaperStartSOC = MiniConsumptionCalculator.chargingTaperStartSOC(for: profile)
        let useContinuousCalibration = useContinuousCalibration(
            for: profile.id,
            defaults: defaults
        )

        return EffectiveVehicleProfileSettings(
            profile: profile,
            defaultReferenceConsumption: defaultReferenceConsumption,
            manualReferenceConsumption: manualReferenceConsumption,
            motorwaySpeed: resolvedMotorwaySpeed,
            airConditioningMode: resolvedAirConditioningMode,
            selectedTyreSet: resolvedTyres.selectedTyreSet,
            summerTyreClass: resolvedTyres.summerTyreClass,
            winterTyreClass: resolvedTyres.winterTyreClass,
            normalMinimumChargingPercent: resolvedMinimumChargingPercent,
            normalFastChargeTargetPercent: resolvedFastChargeTargetPercent,
            averageChargingSpeedKW: resolvedAverageChargingSpeed,
            chargingTaperStartSOC: resolvedChargingTaperStartSOC,
            useContinuousCalibration: useContinuousCalibration
        )
    }

    static func motorwaySpeed(
        for profile: VehicleProfile,
        defaults: UserDefaults = .standard
    ) -> Double {
        let values: [String: Double] = overrides(defaults: defaults, key: motorwaySpeedOverridesKey)
        let legacyValue = legacyBuiltInMotorwaySpeed(
            for: profile.id,
            defaults: defaults
        )
        return MiniConsumptionDefaults.normalizedMotorwaySpeed(
            values[profile.id]
                ?? legacyValue
                ?? MiniConsumptionDefaults.motorwaySpeedKmh
        )
    }

    static func airConditioningMode(
        for profile: VehicleProfile,
        defaults: UserDefaults = .standard
    ) -> AirConditioningMode {
        let values: [String: String] = overrides(defaults: defaults, key: airConditioningModeOverridesKey)
        return values[profile.id].flatMap(AirConditioningMode.init(rawValue:))
            ?? legacyBuiltInAirConditioningMode(
                for: profile.id,
                defaults: defaults
            )
            ?? MiniConsumptionDefaults.airConditioningMode
    }

    static func setMotorwaySpeed(
        _ value: Double,
        for profileID: String,
        defaults: UserDefaults = .standard
    ) {
        var values: [String: Double] = overrides(defaults: defaults, key: motorwaySpeedOverridesKey)
        values[profileID] = MiniConsumptionDefaults.normalizedMotorwaySpeed(value)
        if let data = try? JSONEncoder().encode(values) {
            defaults.set(data, forKey: motorwaySpeedOverridesKey)
        }
    }

    static func setAirConditioningMode(
        _ value: AirConditioningMode,
        for profileID: String,
        defaults: UserDefaults = .standard
    ) {
        setStringOverride(value.rawValue, for: profileID, key: airConditioningModeOverridesKey, defaults: defaults)
    }

    static func removeDrivingDefaultOverrides(
        for profileID: String,
        defaults: UserDefaults = .standard
    ) {
        removeDoubleOverride(for: profileID, key: motorwaySpeedOverridesKey, defaults: defaults)
        removeOverride(for: profileID, key: airConditioningModeOverridesKey, defaults: defaults)
    }

    // VehicleProfile tyre classes are profile/template defaults. Once a profile-ID
    // override exists it is the current user preference; legacy scalars are considered
    // only for the stable built-in profile identity.
    static func tyreSettings(
        for profile: VehicleProfile,
        defaults: UserDefaults = .standard
    ) -> EffectiveTyreSettings {
        let selectedOverrides: [String: String] = overrides(
            defaults: defaults,
            key: selectedTyreSetOverridesKey
        )
        let summerOverrides: [String: String] = overrides(
            defaults: defaults,
            key: summerTyreClassOverridesKey
        )
        let winterOverrides: [String: String] = overrides(
            defaults: defaults,
            key: winterTyreClassOverridesKey
        )
        let legacySettings = legacyTyreSettings(for: profile.id, defaults: defaults)

        return EffectiveTyreSettings(
            selectedTyreSet: selectedOverrides[profile.id].flatMap(TyreSet.init(rawValue:))
                ?? legacySettings.selectedTyreSet
                ?? MiniConsumptionDefaults.selectedTyreSet,
            summerTyreClass: summerOverrides[profile.id].flatMap(RollingResistanceClass.init(rawValue:))
                ?? legacySettings.summerTyreClass
                ?? profile.summerTyreClass,
            winterTyreClass: winterOverrides[profile.id].flatMap(RollingResistanceClass.init(rawValue:))
                ?? legacySettings.winterTyreClass
                ?? profile.winterTyreClass
        )
    }

    static func setSelectedTyreSet(
        _ value: TyreSet,
        for profileID: String,
        defaults: UserDefaults = .standard
    ) {
        setStringOverride(value.rawValue, for: profileID, key: selectedTyreSetOverridesKey, defaults: defaults)
    }

    static func setSummerTyreClass(
        _ value: RollingResistanceClass,
        for profileID: String,
        defaults: UserDefaults = .standard
    ) {
        setStringOverride(value.rawValue, for: profileID, key: summerTyreClassOverridesKey, defaults: defaults)
    }

    static func setWinterTyreClass(
        _ value: RollingResistanceClass,
        for profileID: String,
        defaults: UserDefaults = .standard
    ) {
        setStringOverride(value.rawValue, for: profileID, key: winterTyreClassOverridesKey, defaults: defaults)
    }

    static func removeTyreOverrides(
        for profileID: String,
        defaults: UserDefaults = .standard
    ) {
        removeOverride(for: profileID, key: selectedTyreSetOverridesKey, defaults: defaults)
        removeOverride(for: profileID, key: summerTyreClassOverridesKey, defaults: defaults)
        removeOverride(for: profileID, key: winterTyreClassOverridesKey, defaults: defaults)
    }

    static func setUseContinuousCalibration(
        _ isEnabled: Bool,
        for profileID: String,
        defaults: UserDefaults = .standard
    ) {
        var values: [String: Bool] = overrides(
            defaults: defaults,
            key: useContinuousCalibrationOverridesKey
        )
        values[profileID] = isEnabled
        if let data = try? JSONEncoder().encode(values) {
            defaults.set(data, forKey: useContinuousCalibrationOverridesKey)
        }
    }

    static func batteryDegradationPercent(
        for profileID: String,
        legacyBuiltInValue: Int,
        defaults: UserDefaults = .standard
    ) -> Int {
        let values: [String: Int] = overrides(
            defaults: defaults,
            key: batteryDegradationOverridesKey
        )
        let compatibilityValues = [
            VehicleProfileResolver.builtInMiniProfileID: legacyBuiltInValue
        ]
        return MiniConsumptionCalculator.normalizedBatteryDegradationPercent(
            values[profileID]
                ?? compatibilityValues[profileID]
                ?? MiniConsumptionDefaults.batteryDegradationPercent
        )
    }

    static func setBatteryDegradationPercent(
        _ value: Int,
        for profileID: String,
        defaults: UserDefaults = .standard
    ) {
        var values: [String: Int] = overrides(
            defaults: defaults,
            key: batteryDegradationOverridesKey
        )
        values[profileID] = MiniConsumptionCalculator.normalizedBatteryDegradationPercent(value)
        if let data = try? JSONEncoder().encode(values) {
            defaults.set(data, forKey: batteryDegradationOverridesKey)
        }
    }

    static func useContinuousCalibration(
        for profileID: String,
        defaults: UserDefaults = .standard
    ) -> Bool {
        let values: [String: Bool] = overrides(
            defaults: defaults,
            key: useContinuousCalibrationOverridesKey
        )
        return values[profileID]
            ?? (defaults.object(forKey: "useContinuousCalibration") as? Bool)
            ?? MiniConsumptionDefaults.useContinuousCalibration
    }

    static func normalMinimumChargingPercent(
        for profile: VehicleProfile,
        defaults: UserDefaults = .standard
    ) -> Double {
        let values: [String: Double] = overrides(
            defaults: defaults,
            key: normalMinimumChargingPercentOverridesKey
        )
        let resolvedValue = values[profile.id]
            ?? legacyBuiltInChargingValue(
                for: profile,
                key: "normalMinimumChargingPercent",
                defaults: defaults
            )
            ?? ChargingWindow.defaultMinimumPercent
        return clamped(
            resolvedValue,
            to: ChargingWindow.minimumBounds,
            fallback: ChargingWindow.defaultMinimumPercent
        )
    }

    static func setNormalMinimumChargingPercent(
        _ value: Double,
        for profile: VehicleProfile,
        defaults: UserDefaults = .standard
    ) {
        setChargingOverride(
            clamped(value, to: ChargingWindow.minimumBounds, fallback: ChargingWindow.defaultMinimumPercent),
            for: profile.id,
            key: normalMinimumChargingPercentOverridesKey,
            defaults: defaults
        )
    }

    static func normalFastChargeTargetPercent(
        for profile: VehicleProfile,
        defaults: UserDefaults = .standard
    ) -> Double {
        let values: [String: Double] = overrides(
            defaults: defaults,
            key: normalFastChargeTargetPercentOverridesKey
        )
        let resolvedValue = values[profile.id]
            ?? legacyBuiltInChargingValue(
                for: profile,
                key: "normalFastChargeTargetPercent",
                defaults: defaults
            )
            ?? ChargingWindow.defaultTargetPercent
        return clamped(
            resolvedValue,
            to: ChargingWindow.targetBounds,
            fallback: ChargingWindow.defaultTargetPercent
        )
    }

    static func setNormalFastChargeTargetPercent(
        _ value: Double,
        for profile: VehicleProfile,
        defaults: UserDefaults = .standard
    ) {
        setChargingOverride(
            clamped(value, to: ChargingWindow.targetBounds, fallback: ChargingWindow.defaultTargetPercent),
            for: profile.id,
            key: normalFastChargeTargetPercentOverridesKey,
            defaults: defaults
        )
    }

    static func averageChargingSpeedKW(
        for profile: VehicleProfile,
        defaults: UserDefaults = .standard
    ) -> Double {
        let defaultValue = MiniConsumptionCalculator.defaultAverageChargingSpeedKW(for: profile)
        let values: [String: Double] = overrides(
            defaults: defaults,
            key: averageChargingSpeedOverridesKey
        )
        let resolvedValue = values[profile.id]
            ?? legacyBuiltInChargingValue(
                for: profile,
                key: "averageChargingSpeedKW",
                defaults: defaults
            )
            ?? defaultValue
        return clamped(
            resolvedValue,
            to: MiniConsumptionCalculator.averageChargingSpeedBoundsKW(for: profile),
            fallback: defaultValue
        )
    }

    static func setAverageChargingSpeedKW(
        _ value: Double,
        for profile: VehicleProfile,
        defaults: UserDefaults = .standard
    ) {
        setChargingOverride(
            clamped(
                value,
                to: MiniConsumptionCalculator.averageChargingSpeedBoundsKW(for: profile),
                fallback: MiniConsumptionCalculator.defaultAverageChargingSpeedKW(for: profile)
            ),
            for: profile.id,
            key: averageChargingSpeedOverridesKey,
            defaults: defaults
        )
    }

    private static func legacyBuiltInChargingValue(
        for profile: VehicleProfile,
        key: String,
        defaults: UserDefaults
    ) -> Double? {
        guard profile.id == VehicleProfileResolver.builtInMiniProfileID,
              defaults.object(forKey: key) != nil else {
            return nil
        }

        return double(defaults: defaults, key: key, fallback: 0)
    }

    private static func setChargingOverride(
        _ value: Double,
        for profileID: String,
        key: String,
        defaults: UserDefaults
    ) {
        var values: [String: Double] = overrides(defaults: defaults, key: key)
        values[profileID] = value
        if let data = try? JSONEncoder().encode(values) {
            defaults.set(data, forKey: key)
        }
    }

    private struct LegacyTyreSettings {
        let selectedTyreSet: TyreSet?
        let summerTyreClass: RollingResistanceClass?
        let winterTyreClass: RollingResistanceClass?

        static let none = LegacyTyreSettings(
            selectedTyreSet: nil,
            summerTyreClass: nil,
            winterTyreClass: nil
        )
    }

    private static func legacyTyreSettings(
        for profileID: String,
        defaults: UserDefaults
    ) -> LegacyTyreSettings {
        guard profileID == VehicleProfileResolver.builtInMiniProfileID else {
            return .none
        }

        let selectedTyreSet: TyreSet? = optionalRawValue(defaults: defaults, key: "selectedTyreSet")
            ?? (defaults.object(forKey: "winterTyres") as? Bool).map { $0 ? .winter : .summer }
        let legacyRollingResistanceClass: RollingResistanceClass? = optionalRawValue(
            defaults: defaults,
            key: "rollingResistanceClass"
        )

        return LegacyTyreSettings(
            selectedTyreSet: selectedTyreSet,
            summerTyreClass: optionalRawValue(defaults: defaults, key: "summerTyreClass")
                ?? legacyRollingResistanceClass,
            winterTyreClass: optionalRawValue(defaults: defaults, key: "winterTyreClass")
                ?? legacyRollingResistanceClass
        )
    }

    private static func setStringOverride(
        _ value: String,
        for profileID: String,
        key: String,
        defaults: UserDefaults
    ) {
        var values: [String: String] = overrides(defaults: defaults, key: key)
        values[profileID] = value
        if let data = try? JSONEncoder().encode(values) {
            defaults.set(data, forKey: key)
        }
    }

    private static func removeOverride(
        for profileID: String,
        key: String,
        defaults: UserDefaults
    ) {
        var values: [String: String] = overrides(defaults: defaults, key: key)
        values.removeValue(forKey: profileID)
        if let data = try? JSONEncoder().encode(values) {
            defaults.set(data, forKey: key)
        }
    }

    private static func removeDoubleOverride(
        for profileID: String,
        key: String,
        defaults: UserDefaults
    ) {
        var values: [String: Double] = overrides(defaults: defaults, key: key)
        values.removeValue(forKey: profileID)
        if let data = try? JSONEncoder().encode(values) {
            defaults.set(data, forKey: key)
        }
    }

    private static func legacyBuiltInMotorwaySpeed(
        for profileID: String,
        defaults: UserDefaults
    ) -> Double? {
        guard profileID == VehicleProfileResolver.builtInMiniProfileID,
              defaults.object(forKey: "motorwaySpeed") != nil else {
            return nil
        }
        return double(
            defaults: defaults,
            key: "motorwaySpeed",
            fallback: MiniConsumptionDefaults.motorwaySpeedKmh
        )
    }

    private static func legacyBuiltInAirConditioningMode(
        for profileID: String,
        defaults: UserDefaults
    ) -> AirConditioningMode? {
        guard profileID == VehicleProfileResolver.builtInMiniProfileID else {
            return nil
        }
        return optionalRawValue(defaults: defaults, key: "airConditioningMode")
    }

    private static func overrides<Value: Decodable>(defaults: UserDefaults, key: String) -> [String: Value] {
        guard let data = defaults.data(forKey: key),
              data.isEmpty == false,
              let values = try? JSONDecoder().decode([String: Value].self, from: data) else {
            return [:]
        }
        return values
    }

    private static func double(defaults: UserDefaults, key: String, fallback: Double) -> Double {
        defaults.object(forKey: key) as? Double ?? fallback
    }

    private static func int(defaults: UserDefaults, key: String, fallback: Int) -> Int {
        defaults.object(forKey: key) as? Int ?? fallback
    }

    private static func rawValue<Value: RawRepresentable>(
        defaults: UserDefaults,
        key: String,
        fallback: Value
    ) -> Value where Value.RawValue == String {
        optionalRawValue(defaults: defaults, key: key) ?? fallback
    }

    private static func optionalRawValue<Value: RawRepresentable>(
        defaults: UserDefaults,
        key: String
    ) -> Value? where Value.RawValue == String {
        defaults.string(forKey: key).flatMap(Value.init(rawValue:))
    }

    private static func positiveFinite(_ value: Double, fallback: Double) -> Double {
        value.isFinite && value > 0 ? value : fallback
    }

    private static func clamped(_ value: Double, to range: ClosedRange<Double>, fallback: Double) -> Double {
        guard value.isFinite else { return min(max(fallback, range.lowerBound), range.upperBound) }
        return min(max(value, range.lowerBound), range.upperBound)
    }
}

enum VehicleProfileStore {
    static let customProfilesStorageKey = "vehicleProfiles.v1"
    static let selectedProfileIDStorageKey = "selectedVehicleProfileID"
    static let legacyCustomEVMigrationCompletedKey = "vehicleProfiles.legacyCustomEVMigrationCompleted"
    struct MigrationResult: Equatable {
        var createdLegacyCustomEVProfile: Bool
        var updatedLegacyCustomEVProfile: Bool
        var selectedProfileID: String?
    }

    static func loadCustomProfiles(defaults: UserDefaults = .standard) -> [VehicleProfile] {
        guard let data = defaults.data(forKey: customProfilesStorageKey) else {
            return []
        }

        do {
            let profiles = try JSONDecoder().decode([VehicleProfile].self, from: data)
            return profiles.filter { $0.kind == .custom }
        } catch {
            return []
        }
    }

    static func saveCustomProfiles(
        _ profiles: [VehicleProfile],
        defaults: UserDefaults = .standard
    ) {
        let customProfiles = profiles.filter { $0.kind == .custom }

        do {
            let data = try JSONEncoder().encode(customProfiles)
            defaults.set(data, forKey: customProfilesStorageKey)
        } catch {
            assertionFailure("Failed to save vehicle profiles: \(error)")
        }
    }

    static func selectedProfileID(defaults: UserDefaults = .standard) -> String? {
        defaults.string(forKey: selectedProfileIDStorageKey)
    }

    static func setSelectedProfileID(
        _ profileID: String,
        defaults: UserDefaults = .standard
    ) {
        defaults.set(profileID, forKey: selectedProfileIDStorageKey)
    }

    static func createCustomProfile(
        displayName: String,
        usableBatteryKWh: Double,
        wltpRangeKm: Double,
        peakDCChargingKW: Double,
        batteryDegradationPercent: Int,
        defaults: UserDefaults = .standard,
        now: Date = Date()
    ) -> VehicleProfile {
        let profile = VehicleProfile(
            id: UUID().uuidString,
            displayName: sanitizedDisplayName(displayName),
            kind: .custom,
            usableBatteryKWh: positiveFinite(
                usableBatteryKWh,
                fallback: VehicleProfileResolver.defaultCustomUsableBatteryCapacityKWh
            ),
            wltpRangeKm: positiveFinite(
                wltpRangeKm,
                fallback: VehicleProfileResolver.defaultCustomWLTPRangeKm
            ),
            peakDCChargingKW: positiveFinite(
                peakDCChargingKW,
                fallback: VehicleProfileResolver.defaultCustomPeakDCChargingKW
            ),
            batteryDegradationPercent: clampedBatteryDegradationPercent(batteryDegradationPercent),
            summerTyreClass: MiniConsumptionDefaults.summerTyreClass,
            winterTyreClass: MiniConsumptionDefaults.winterTyreClass,
            createdAt: now,
            updatedAt: now
        )

        var profiles = loadCustomProfiles(defaults: defaults)
        profiles.append(profile)
        saveCustomProfiles(profiles, defaults: defaults)
        return profile
    }

    static func updateCustomProfile(
        _ profile: VehicleProfile,
        displayName: String,
        usableBatteryKWh: Double,
        wltpRangeKm: Double,
        peakDCChargingKW: Double,
        defaults: UserDefaults = .standard,
        now: Date = Date()
    ) {
        var profiles = loadCustomProfiles(defaults: defaults)
        guard let index = profiles.firstIndex(where: { $0.id == profile.id }) else {
            return
        }

        profiles[index].displayName = sanitizedDisplayName(displayName)
        profiles[index].usableBatteryKWh = positiveFinite(
            usableBatteryKWh,
            fallback: VehicleProfileResolver.defaultCustomUsableBatteryCapacityKWh
        )
        profiles[index].wltpRangeKm = positiveFinite(
            wltpRangeKm,
            fallback: VehicleProfileResolver.defaultCustomWLTPRangeKm
        )
        profiles[index].peakDCChargingKW = positiveFinite(
            peakDCChargingKW,
            fallback: VehicleProfileResolver.defaultCustomPeakDCChargingKW
        )
        profiles[index].updatedAt = now
        saveCustomProfiles(profiles, defaults: defaults)
    }

    static func updateCustomProfileBatteryDegradation(
        id profileID: String,
        batteryDegradationPercent: Int,
        defaults: UserDefaults = .standard,
        now: Date = Date()
    ) {
        var profiles = loadCustomProfiles(defaults: defaults)
        guard let index = profiles.firstIndex(where: { $0.id == profileID }) else {
            return
        }

        profiles[index].batteryDegradationPercent = clampedBatteryDegradationPercent(batteryDegradationPercent)
        profiles[index].updatedAt = now
        saveCustomProfiles(profiles, defaults: defaults)
    }

    static func deleteCustomProfile(
        id profileID: String,
        defaults: UserDefaults = .standard
    ) {
        let profiles = loadCustomProfiles(defaults: defaults)
            .filter { $0.id != profileID }
        saveCustomProfiles(profiles, defaults: defaults)

        if selectedProfileID(defaults: defaults) == profileID {
            setSelectedProfileID("", defaults: defaults)
            defaults.set(false, forKey: "experimentalCustomVehicleProfileEnabled")
        }
    }

    static func activeProfile(
        for input: VehicleProfileResolverInput,
        defaults: UserDefaults = .standard
    ) -> ActiveVehicleProfile {
        VehicleProfileResolver.activeProfile(
            for: input,
            customProfiles: loadCustomProfiles(defaults: defaults),
            selectedProfileID: selectedProfileID(defaults: defaults)
        )
    }

    @discardableResult
    static func migrateLegacyCustomEVProfileIfNeeded(
        input: VehicleProfileResolverInput,
        defaults: UserDefaults = .standard,
        now: Date = Date()
    ) -> MigrationResult {
        guard defaults.bool(forKey: legacyCustomEVMigrationCompletedKey) == false else {
            return MigrationResult(
                createdLegacyCustomEVProfile: false,
                updatedLegacyCustomEVProfile: false,
                selectedProfileID: selectedProfileID(defaults: defaults)
            )
        }

        var customProfiles = loadCustomProfiles(defaults: defaults)
        var createdLegacyCustomEVProfile = false

        if customProfiles.contains(where: { $0.id == VehicleProfileResolver.legacyCustomEVProfileID }) == false,
           shouldCreateLegacyCustomEVProfile(from: input) {
            var updatedProfile = VehicleProfileResolver.customEVProfile(from: input)
            updatedProfile.displayName = "My EV"
            updatedProfile.createdAt = now
            updatedProfile.updatedAt = now
            customProfiles.append(updatedProfile)
            saveCustomProfiles(customProfiles, defaults: defaults)
            createdLegacyCustomEVProfile = true
        }

        let profileIDs = Set(customProfiles.map(\.id))
        if input.experimentalCustomVehicleProfileEnabled,
           profileIDs.contains(VehicleProfileResolver.legacyCustomEVProfileID) {
            setSelectedProfileID(VehicleProfileResolver.legacyCustomEVProfileID, defaults: defaults)
        }
        defaults.set(true, forKey: legacyCustomEVMigrationCompletedKey)

        return MigrationResult(
            createdLegacyCustomEVProfile: createdLegacyCustomEVProfile,
            updatedLegacyCustomEVProfile: false,
            selectedProfileID: selectedProfileID(defaults: defaults)
        )
    }

    private static func shouldCreateLegacyCustomEVProfile(from input: VehicleProfileResolverInput) -> Bool {
        input.experimentalCustomVehicleProfileEnabled
    }

    private static func sanitizedDisplayName(_ displayName: String) -> String {
        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedName.isEmpty ? "My EV" : trimmedName
    }

    private static func positiveFinite(_ value: Double, fallback: Double) -> Double {
        value.isFinite && value > 0 ? value : fallback
    }

    private static func clampedBatteryDegradationPercent(_ value: Int) -> Int {
        min(max(value, 0), 10)
    }

    private static func rawRepresentable<Value>(
        defaults: UserDefaults,
        forKey key: String,
        defaultValue: Value
    ) -> Value where Value: RawRepresentable, Value.RawValue == String {
        guard let rawValue = defaults.string(forKey: key), let value = Value(rawValue: rawValue) else {
            return defaultValue
        }

        return value
    }
}

private extension VehicleProfile {
    func hasSameEditableProfileValues(as other: VehicleProfile) -> Bool {
        id == other.id
            && displayName == other.displayName
            && kind == other.kind
            && usableBatteryKWh == other.usableBatteryKWh
            && wltpRangeKm == other.wltpRangeKm
            && peakDCChargingKW == other.peakDCChargingKW
            && batteryDegradationPercent == other.batteryDegradationPercent
            && summerTyreClass == other.summerTyreClass
            && winterTyreClass == other.winterTyreClass
    }
}
