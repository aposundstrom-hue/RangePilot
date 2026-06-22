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
        self.batteryDegradationPercent = batteryDegradationPercent
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
        batteryDegradationPercent = try container.decodeIfPresent(Int.self, forKey: .batteryDegradationPercent)
            ?? MiniConsumptionDefaults.batteryDegradationPercent
        summerTyreClass = try container.decodeIfPresent(RollingResistanceClass.self, forKey: .summerTyreClass)
            ?? MiniConsumptionDefaults.summerTyreClass
        winterTyreClass = try container.decodeIfPresent(RollingResistanceClass.self, forKey: .winterTyreClass)
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
            usableBatteryKWh: MiniConsumptionCalculator.effectiveUsableBatteryKWh(
                degradationPercent: input.batteryDegradationPercent
            ),
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
            summerTyreClass: rawRepresentable(
                defaults: defaults,
                forKey: "summerTyreClass",
                defaultValue: MiniConsumptionDefaults.summerTyreClass
            ),
            winterTyreClass: rawRepresentable(
                defaults: defaults,
                forKey: "winterTyreClass",
                defaultValue: MiniConsumptionDefaults.winterTyreClass
            ),
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
