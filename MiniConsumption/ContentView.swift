//
//  ContentView.swift
//  MiniConsumption
//
//  Created by Andreas Sundström on 2026-05-18.
//

import SwiftUI
import UIKit
import Combine
#if canImport(CoreLocation)
import CoreLocation
#endif
#if canImport(MapKit)
import MapKit
#endif

let defaultTripChargingSetupMinutes = 2.0
let sliderAccentColor = Color(red: 0.82, green: 0.70, blue: 0.22)
private let supportedTemperatureRangeC = -20.0...40.0
private let kilometersPerMile = 1.609344
private let windConditionSelectedAtKey = "windConditionSelectedAt"
private let windConditionExpirationInterval: TimeInterval = 12 * 60 * 60

enum MiniConsumptionInitialSetup {
    private static let hasCompletedInitialSetupKey = "hasCompletedInitialSetup"

    private static let existingInstallEvidenceKeys = [
        "referenceConsumption",
        "tripDistance",
        "temperature",
        "airConditioningMode",
        "roadTypeProfile",
        "motorwaySpeed",
        "roadSurface",
        "windCondition",
        "planningMode",
        "currentBatteryPercent",
        "rollingResistanceClass",
        "winterTyres",
        "selectedTyreSet",
        "summerTyreClass",
        "winterTyreClass",
        "useContinuousCalibration",
        "batteryDegradationPercent",
        "arrivalBatteryTargetPercent",
        "normalMinimumChargingPercent",
        "normalFastChargeTargetPercent",
        "averageChargingSpeedKW",
        "tripChargingSetupMinutes",
        "displayUnits",
        "temperatureUnits",
        "weightUnits"
    ]

    static func performIfNeeded(defaults: UserDefaults = .standard, locale: Locale = .current) {
        guard defaults.bool(forKey: hasCompletedInitialSetupKey) == false else {
            normalizeMotorwaySpeedIfNeeded(defaults: defaults)
            expireWindConditionIfNeeded(defaults: defaults)
            return
        }

        guard isFreshInstall(defaults: defaults) else {
            normalizeMotorwaySpeedIfNeeded(defaults: defaults)
            expireWindConditionIfNeeded(defaults: defaults)
            defaults.set(true, forKey: hasCompletedInitialSetupKey)
            return
        }

        let inferredUnits = inferredUnits(for: locale)

        defaults.set(MiniConsumptionDefaults.currentBatteryPercent, forKey: "currentBatteryPercent")
        defaults.set(MiniConsumptionDefaults.planningMode.rawValue, forKey: "planningMode")
        defaults.set(MiniConsumptionDefaults.roadTypeProfile.rawValue, forKey: "roadTypeProfile")
        defaults.set(MiniConsumptionDefaults.motorwaySpeedKmh, forKey: "motorwaySpeed")
        defaults.set(MiniConsumptionDefaults.temperatureC, forKey: "temperature")
        defaults.set(MiniConsumptionDefaults.roadSurface.rawValue, forKey: "roadSurface")
        defaults.set(MiniConsumptionDefaults.windCondition.rawValue, forKey: "windCondition")
        defaults.set(MiniConsumptionDefaults.airConditioningMode.rawValue, forKey: "airConditioningMode")
        defaults.set(MiniConsumptionDefaults.selectedTyreSet.rawValue, forKey: "selectedTyreSet")
        defaults.set(false, forKey: "winterTyres")
        defaults.set(MiniConsumptionDefaults.summerTyreClass.rawValue, forKey: "summerTyreClass")
        defaults.set(MiniConsumptionDefaults.winterTyreClass.rawValue, forKey: "winterTyreClass")
        defaults.set(MiniConsumptionDefaults.summerTyreClass.rawValue, forKey: "rollingResistanceClass")
        defaults.set(MiniConsumptionDefaults.useContinuousCalibration, forKey: "useContinuousCalibration")
        defaults.set(ChargingWindow.defaultMinimumPercent, forKey: "normalMinimumChargingPercent")
        defaults.set(ChargingWindow.defaultTargetPercent, forKey: "normalFastChargeTargetPercent")
        defaults.set(ChargingWindow.defaultArrivalBatteryTargetPercent, forKey: "arrivalBatteryTargetPercent")
        defaults.set(inferredUnits.displayUnits.rawValue, forKey: "displayUnits")
        defaults.set(inferredUnits.temperatureUnits.rawValue, forKey: "temperatureUnits")
        defaults.set(inferredUnits.weightUnits.rawValue, forKey: "weightUnits")
        defaults.set(true, forKey: hasCompletedInitialSetupKey)
    }

    static func expireWindConditionIfNeeded(defaults: UserDefaults = .standard, now: Date = Date()) {
        guard let storedValue = defaults.string(forKey: "windCondition"),
              let condition = WindCondition(rawValue: storedValue) else {
            defaults.removeObject(forKey: windConditionSelectedAtKey)
            return
        }

        guard condition != .normal else {
            defaults.removeObject(forKey: windConditionSelectedAtKey)
            return
        }

        guard let selectedAt = defaults.object(forKey: windConditionSelectedAtKey) as? Double else {
            defaults.set(now.timeIntervalSince1970, forKey: windConditionSelectedAtKey)
            return
        }

        if now.timeIntervalSince1970 - selectedAt > windConditionExpirationInterval {
            defaults.set(WindCondition.normal.rawValue, forKey: "windCondition")
            defaults.removeObject(forKey: windConditionSelectedAtKey)
        }
    }

    private static func isFreshInstall(defaults: UserDefaults) -> Bool {
        !existingInstallEvidenceKeys.contains { defaults.object(forKey: $0) != nil }
            && TripOutcomeStore.load().isEmpty
    }

    private static func normalizeMotorwaySpeedIfNeeded(defaults: UserDefaults) {
        guard let storedSpeed = defaults.object(forKey: "motorwaySpeed") as? Double else {
            defaults.set(MiniConsumptionDefaults.motorwaySpeedKmh, forKey: "motorwaySpeed")
            return
        }

        let normalizedSpeed = MiniConsumptionDefaults.normalizedMotorwaySpeed(storedSpeed)
        if normalizedSpeed != storedSpeed {
            defaults.set(normalizedSpeed, forKey: "motorwaySpeed")
        }
    }

    private static func inferredUnits(for locale: Locale) -> (displayUnits: DisplayUnits, temperatureUnits: TemperatureUnits, weightUnits: WeightUnits) {
        let regionCode = locale.region?.identifier.uppercased()
        let imperialDistanceRegions: Set<String> = ["GB", "LR", "MM", "US"]
        let fahrenheitTemperatureRegions: Set<String> = ["BS", "BZ", "KY", "PW", "US"]
        let imperialWeightRegions: Set<String> = ["GB", "LR", "MM", "US"]

        return (
            displayUnits: regionCode.map(imperialDistanceRegions.contains) == true ? .imperial : .metric,
            temperatureUnits: regionCode.map(fahrenheitTemperatureRegions.contains) == true ? .fahrenheit : .celsius,
            weightUnits: regionCode.map(imperialWeightRegions.contains) == true ? .pounds : .kilograms
        )
    }
}

private enum AppTab {
    case range
    case trip
    case settings
}

private enum RangeDisplayMode: String, CaseIterable, Identifiable {
    case gauge
    case map

    var id: String { rawValue }

    var label: String {
        switch self {
        case .gauge:
            return "Gauge"
        case .map:
            return "Map"
        }
    }
}

private enum SettingsScrollTarget {
    static let vehicleProfileCard = "vehicleProfileCard"
}

private enum CustomVehicleProfileField: Hashable {
    case usableBatteryCapacity
    case officialWLTPRange
    case peakDCChargingSpeed
}

private struct WatchRangeSnapshotPublisher: View {
    let snapshot: WatchRangeStateSnapshot

    var body: some View {
        Color.clear
            .onAppear {
                WatchRangeStateSnapshotStore.save(snapshot)
            }
            .onChange(of: snapshot) {
                WatchRangeStateSnapshotStore.save(snapshot)
            }
    }
}

private enum VehicleProfileEditorMode: Identifiable {
    case create
    case edit(VehicleProfile)

    var id: String {
        switch self {
        case .create:
            return "create"
        case .edit(let profile):
            return "edit-\(profile.id)"
        }
    }
}

private struct VehicleProfileEditorDraft {
    var displayName = ""
    var usableBatteryKWhText = "28.9"
    var wltpRangeText = "234"
    var peakDCChargingKWText = "50"
    private var unchangedWLTPRangeText = "234"
    private var unchangedWLTPRangeKm = VehicleProfileResolver.defaultCustomWLTPRangeKm

    mutating func resetForCreate(displayUnits: DisplayUnits) {
        displayName = ""
        usableBatteryKWhText = Self.formattedDraftNumber(
            VehicleProfileResolver.defaultCustomUsableBatteryCapacityKWh,
            fractionLength: 1
        )
        wltpRangeText = Self.formattedDraftNumber(
            displayUnits.displayDistance(fromKm: VehicleProfileResolver.defaultCustomWLTPRangeKm),
            fractionLength: 0
        )
        unchangedWLTPRangeText = wltpRangeText
        unchangedWLTPRangeKm = VehicleProfileResolver.defaultCustomWLTPRangeKm
        peakDCChargingKWText = Self.formattedDraftNumber(
            VehicleProfileResolver.defaultCustomPeakDCChargingKW,
            fractionLength: 0
        )
    }

    mutating func load(_ profile: VehicleProfile, displayUnits: DisplayUnits) {
        displayName = profile.displayName
        usableBatteryKWhText = Self.formattedDraftNumber(profile.usableBatteryKWh, fractionLength: 1)
        wltpRangeText = Self.formattedDraftNumber(
            displayUnits.displayDistance(fromKm: profile.wltpRangeKm),
            fractionLength: 0
        )
        unchangedWLTPRangeText = wltpRangeText
        unchangedWLTPRangeKm = profile.wltpRangeKm
        peakDCChargingKWText = Self.formattedDraftNumber(profile.peakDCChargingKW, fractionLength: 0)
    }

    mutating func apply(_ template: VehicleProfileTemplate, displayUnits: DisplayUnits) {
        displayName = template.displayName
        usableBatteryKWhText = Self.formattedDraftNumber(template.usableBatteryKWh, fractionLength: 1)
        wltpRangeText = Self.formattedDraftNumber(
            displayUnits.displayDistance(fromKm: template.wltpRangeKm),
            fractionLength: 0
        )
        unchangedWLTPRangeText = wltpRangeText
        unchangedWLTPRangeKm = template.wltpRangeKm
        peakDCChargingKWText = Self.formattedDraftNumber(template.peakDCChargingKW, fractionLength: 0)
    }

    var usableBatteryKWh: Double? {
        Self.parsedDraftNumber(usableBatteryKWhText)
    }

    func wltpRangeKm(displayUnits: DisplayUnits) -> Double? {
        if wltpRangeText == unchangedWLTPRangeText {
            return unchangedWLTPRangeKm
        }

        guard let displayedWLTPRange = Self.parsedDraftNumber(wltpRangeText) else {
            return nil
        }

        return displayUnits.storedDistance(
            fromDisplayed: displayedWLTPRange
        )
    }

    var peakDCChargingKW: Double? {
        Self.parsedDraftNumber(peakDCChargingKWText)
    }

    func canSave(displayUnits: DisplayUnits) -> Bool {
        usableBatteryKWh != nil
            && wltpRangeKm(displayUnits: displayUnits) != nil
            && peakDCChargingKW != nil
    }

    private static func parsedDraftNumber(_ text: String) -> Double? {
        let normalizedText = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        return normalizedText.isEmpty ? nil : Double(normalizedText).flatMap { value in
            value.isFinite && value > 0 ? value : nil
        }
    }

    private static func formattedDraftNumber(_ value: Double, fractionLength: Int) -> String {
        value.formatted(.number.precision(.fractionLength(fractionLength)))
    }
}

private enum TripAssistantMessage {
    case text(String)
    case controlsUpdated(distanceKm: Double?, routeDistanceUnavailable: Bool, updatesAfterDistance: [String])

    func text(displayUnits: DisplayUnits) -> String {
        switch self {
        case .text(let message):
            return message
        case .controlsUpdated(let distanceKm, let routeDistanceUnavailable, let updatesAfterDistance):
            return assumptionText(
                prefix: "Updated",
                distanceKm: distanceKm,
                routeDistanceUnavailable: routeDistanceUnavailable,
                updatesAfterDistance: updatesAfterDistance,
                displayUnits: displayUnits
            )
        }
    }

    private func assumptionText(
        prefix: String,
        distanceKm: Double?,
        routeDistanceUnavailable: Bool,
        updatesAfterDistance: [String],
        displayUnits: DisplayUnits
    ) -> String {
        var updates = [String]()

        if let distanceKm {
            updates.append(prefix == "Updated" ? "Distance \(displayUnits.formattedDistance(distanceKm))" : "distance \(displayUnits.formattedDistance(distanceKm))")
        } else if routeDistanceUnavailable {
            updates.append("route distance unavailable")
        }

        updates.append(contentsOf: updatesAfterDistance)

        guard !updates.isEmpty else {
            return "No route found. Enter a destination to estimate with Maps."
        }

        if prefix == "Updated", distanceKm != nil {
            return "\(updates.joined(separator: ", "))."
        }

        return "\(prefix) \(updates.joined(separator: ", "))."
    }
}

struct ContentView: View {
    @AppStorage("referenceConsumption") private var referenceConsumption = defaultReferenceConsumptionKWhPer100Km
    @AppStorage("tripDistance") private var distance = MiniConsumptionDefaults.tripDistanceKm
    @AppStorage("temperature") private var temperature = MiniConsumptionDefaults.temperatureC
    @AppStorage("airConditioningMode") private var airConditioningMode = MiniConsumptionDefaults.airConditioningMode
    @AppStorage("roadTypeProfile") private var roadTypeProfile = MiniConsumptionDefaults.roadTypeProfile
    @AppStorage("motorwaySpeed") private var motorwaySpeed = MiniConsumptionDefaults.motorwaySpeedKmh
    @AppStorage("roadSurface") private var roadSurface = MiniConsumptionDefaults.roadSurface
    @AppStorage("windCondition") private var windCondition = MiniConsumptionDefaults.windCondition
    @AppStorage("trailerTowModeEnabled") private var trailerTowModeEnabled = false
    @AppStorage("trailerWeightKg") private var trailerWeightKg = MiniConsumptionDefaults.trailerWeightKg
    @AppStorage("boxyTrailerEnabled") private var boxyTrailerEnabled = false
    @AppStorage("planningMode") private var tripPlanningStrategy = MiniConsumptionDefaults.planningMode
    @AppStorage("currentBatteryPercent") private var startBatteryPercent = MiniConsumptionDefaults.currentBatteryPercent
    @AppStorage("rollingResistanceClass") private var rollingResistanceClass = MiniConsumptionDefaults.summerTyreClass
    @AppStorage("winterTyres") private var winterTyres = false
    @AppStorage("selectedTyreSet") private var selectedTyreSet = MiniConsumptionDefaults.selectedTyreSet
    @AppStorage("summerTyreClass") private var summerTyreClass = MiniConsumptionDefaults.summerTyreClass
    @AppStorage("winterTyreClass") private var winterTyreClass = MiniConsumptionDefaults.winterTyreClass
    @AppStorage("useContinuousCalibration") private var useContinuousCalibration = MiniConsumptionDefaults.useContinuousCalibration
    @AppStorage("batteryDegradationPercent") private var miniBatteryDegradationPercent = MiniConsumptionDefaults.batteryDegradationPercent
    @AppStorage("arrivalBatteryTargetPercent") private var arrivalBatteryTargetPercent = ChargingWindow.defaultArrivalBatteryTargetPercent
    @AppStorage("normalMinimumChargingPercent") private var normalMinimumChargingPercent = ChargingWindow.defaultMinimumPercent
    @AppStorage("normalFastChargeTargetPercent") private var normalFastChargeTargetPercent = ChargingWindow.defaultTargetPercent
    @AppStorage("averageChargingSpeedKW") private var averageChargingSpeedKW = MiniConsumptionCalculator.defaultAverageChargingSpeedKW
    @AppStorage("averageChargingSpeedKWByVehicleProfile.v1") private var averageChargingSpeedOverridesByProfileData = Data()
    @AppStorage("referenceConsumptionByVehicleProfile.v1") private var referenceConsumptionOverridesByProfileData = Data()
    @AppStorage("motorwaySpeedByVehicleProfile.v1") private var motorwaySpeedOverridesByProfileData = Data()
    @AppStorage("airConditioningModeByVehicleProfile.v1") private var airConditioningModeOverridesByProfileData = Data()
    @AppStorage("selectedTyreSetByVehicleProfile.v1") private var selectedTyreSetOverridesByProfileData = Data()
    @AppStorage("summerTyreClassByVehicleProfile.v1") private var summerTyreClassOverridesByProfileData = Data()
    @AppStorage("winterTyreClassByVehicleProfile.v1") private var winterTyreClassOverridesByProfileData = Data()
    @AppStorage("normalMinimumChargingPercentByVehicleProfile.v1") private var normalMinimumChargingPercentOverridesByProfileData = Data()
    @AppStorage("normalFastChargeTargetPercentByVehicleProfile.v1") private var normalFastChargeTargetPercentOverridesByProfileData = Data()
    @AppStorage("tripChargingSetupMinutes") private var tripChargingSetupMinutes = defaultTripChargingSetupMinutes
    @AppStorage("quickTripDistance") private var quickTripDistance = MiniConsumptionDefaults.quickTripDistanceKm
    @AppStorage("displayUnits") private var displayUnits = DisplayUnits.metric
    @AppStorage("temperatureUnits") private var temperatureUnits = TemperatureUnits.celsius
    @AppStorage("weightUnits") private var weightUnits = WeightUnits.kilograms
    @AppStorage("rangeDisplayMode") private var rangeDisplayMode = RangeDisplayMode.gauge
    @AppStorage("showRangeMapChargingThresholdCircle") private var showRangeMapChargingThresholdCircle = true
    @AppStorage("hasSeenWelcomePopup") private var hasSeenWelcomePopup = false
    @AppStorage("hasSeenLogActualConsumptionInfo") private var hasSeenLogActualConsumptionInfo = false
    @AppStorage("hasSeenTripPlanningInputInfo") private var hasSeenTripPlanningInputInfo = false
    @AppStorage("hasSeenCustomEVModeInfo") private var hasSeenCustomEVModeInfo = false
    @AppStorage("experimentalCustomVehicleProfileEnabled") private var experimentalCustomVehicleProfileEnabled = false
    @AppStorage("experimentalUsableBatteryCapacityKWh") private var experimentalUsableBatteryCapacityKWh = 28.9
    @AppStorage("experimentalOfficialWLTPRangeKm") private var experimentalOfficialWLTPRangeKm = 234.0
    @AppStorage("experimentalMaximumDCChargingSpeedKW") private var experimentalMaximumDCChargingSpeedKW = 50.0
    @AppStorage(VehicleProfileStore.selectedProfileIDStorageKey) private var selectedVehicleProfileID = VehicleProfileResolver.builtInMiniProfileID
    @State private var outcomes = TripOutcomeStore.load()
    @State private var outcomeActualConsumptionTenths = Int((defaultReferenceConsumptionKWhPer100Km * 10).rounded())
    @State private var outcomeDistanceKm = 15
    @State private var outcomeNote = ""
    @State private var outcomeTemperature = MiniConsumptionDefaults.temperatureC
    @State private var outcomeRoadSurface = MiniConsumptionDefaults.roadSurface
    @State private var outcomeWindCondition = MiniConsumptionDefaults.windCondition
    @State private var outcomeRoadTypeProfile = MiniConsumptionDefaults.roadTypeProfile
    @State private var outcomeMotorwaySpeed = MiniConsumptionDefaults.motorwaySpeedKmh
    @State private var outcomeTyreSet = MiniConsumptionDefaults.selectedTyreSet
    @State private var outcomeRollingResistanceClass = MiniConsumptionDefaults.summerTyreClass
    @State private var batteryDegradationPercent = MiniConsumptionDefaults.batteryDegradationPercent
    @State private var csvExportFile: CSVExportFile?
    @State private var isTripDataEditorPresented = false
    @State private var isSelectingTripData = false
    @State private var selectedTripOutcomeIDs = Set<TripOutcome.ID>()
    @State private var selectedTripOutcomeForDetails: TripOutcome?
    @State private var draftTripDetailsTemperature = MiniConsumptionDefaults.temperatureC
    @State private var draftTripDetailsRoadSurface = MiniConsumptionDefaults.roadSurface
    @State private var draftTripDetailsWindCondition = MiniConsumptionDefaults.windCondition
    @State private var draftTripDetailsRoadTypeProfile = MiniConsumptionDefaults.roadTypeProfile
    @State private var draftTripDetailsMotorwaySpeed = MiniConsumptionDefaults.motorwaySpeedKmh
    @State private var draftTripDetailsRollingResistanceClass = RollingResistanceClass.b
    @State private var draftTripDetailsDistanceKm: Double?
    @State private var draftTripDetailsNote = ""
    @State private var isDeleteAllTripDataConfirmationPresented = false
    @State private var isLogActualConsumptionInfoPresented = false
    @State private var isTripPlanningInputInfoPresented = false
    @State private var isCustomEVModeInfoPresented = false
    @State private var isTripOutcomeCardPresented = false
    @State private var customVehicleProfiles = VehicleProfileStore.loadCustomProfiles()
    @State private var savedDestinations = SavedDestinationStore.load()
    @State private var isSaveDestinationSheetPresented = false
    @State private var savedDestinationName = ""
    @State private var tripAssistantDescription = ""
    @State private var tripAssistantMessage: TripAssistantMessage?
    @State private var tripAssistantRoute: TripRouteDescription?
    @State private var hasTripEstimate = false
    @State private var tripAssistantSearchGeneration = 0
    @State private var tripEstimateDistance = MiniConsumptionDefaults.tripDistanceKm
    @State private var tripEstimateStartBatteryPercent = MiniConsumptionDefaults.currentBatteryPercent
    @State private var tripEstimateTemperature = MiniConsumptionDefaults.temperatureC
    @State private var tripEstimateRoadTypeProfile = MiniConsumptionDefaults.roadTypeProfile
    @State private var tripEstimateMotorwaySpeed = MiniConsumptionDefaults.motorwaySpeedKmh
    @State private var tripEstimateRoadSurface = MiniConsumptionDefaults.roadSurface
    @State private var tripEstimateWindCondition = MiniConsumptionDefaults.windCondition
    @State private var tripEstimatePlanningMode = MiniConsumptionDefaults.planningMode
    @State private var tripEstimateArrivalBatteryTargetPercent = ChargingWindow.defaultArrivalBatteryTargetPercent
    @State private var isTripDistanceMapDerived = false
    @State private var selectedAppTab: AppTab = .range
    @State private var selectedTripChargingOption: TripChargingOption = .userSettings
    @State private var isQuickTripSheetPresented = false
    @State private var isQuickTripChargingAssumptionsExpanded = false
    @State private var isTripChargingWindowAdjustmentPresented = false
    @State private var isTripArrivalReserveAdjustmentPresented = false
    @State private var draftMinimumChargingPercent = ChargingWindow.defaultMinimumPercent
    @State private var draftFastChargeTargetPercent = ChargingWindow.defaultTargetPercent
    @State private var draftArrivalBatteryTargetPercent = ChargingWindow.defaultArrivalBatteryTargetPercent
    @State private var draftTripAssumptionsStartBatteryPercent = MiniConsumptionDefaults.currentBatteryPercent
    @State private var draftTripAssumptionsTemperature = MiniConsumptionDefaults.temperatureC
    @State private var draftTripAssumptionsRoadTypeProfile = MiniConsumptionDefaults.roadTypeProfile
    @State private var draftTripAssumptionsMotorwaySpeed = MiniConsumptionDefaults.motorwaySpeedKmh
    @State private var draftTripAssumptionsRoadSurface = MiniConsumptionDefaults.roadSurface
    @State private var draftTripAssumptionsWindCondition = MiniConsumptionDefaults.windCondition
    @State private var draftTripAssumptionsArrivalBatteryTargetPercent = ChargingWindow.defaultArrivalBatteryTargetPercent
    @State private var isTripAssumptionsEditorPresented = false
#if canImport(MapKit)
    @State private var tripAssistantRouteEstimate: RouteDistanceEstimate?
#endif
    @State private var isTripAssistantInterpreting = false
    @State private var isTripAssistantRouteLookupPending = false
    @State private var isAboutAppGuidePresented = false
    @State private var isResetAllSettingsConfirmationPresented = false
    @State private var isAdditionalSettingsExpanded = false
    @State private var isTripAdvancedChargingSettingsExpanded = false
    @State private var shouldScrollToVehicleProfileCard = false
    @State private var profileEditorMode: VehicleProfileEditorMode?
    @State private var profileEditorDraft = VehicleProfileEditorDraft()
    @State private var selectedVehicleProfileTemplateBrand = VehicleProfileTemplate.customProfileID
    @State private var selectedVehicleProfileTemplateID = VehicleProfileTemplate.customProfileID
    @State private var pendingDeletedVehicleProfile: VehicleProfile?
    @StateObject private var rangeMapLocationProvider = RangeMapLocationProvider()
    @State private var rangeMapAutofitRequestID = 0
    @State private var isRangeChargingReserveInfoPresented = false
    @FocusState private var isTripAssistantDescriptionFocused: Bool
    @FocusState private var focusedCustomVehicleProfileField: CustomVehicleProfileField?

    private var forecast: ForecastResult {
        return forecast(distanceKm: distance, planningMode: tripPlanningStrategy)
    }

    private var tripEstimateForecast: ForecastResult {
        guard isCustomVehicleProfileSelected == false else {
            let calibrationCorrection = activeCalibrationCorrection
            let ruleBasedForecast = MiniConsumptionCalculator.calculateForecast(
                referenceConsumption: experimentalForecastReferenceConsumption(for: calibrationCorrection),
                distance: tripEstimateDistance,
                temperature: tripEstimateTemperature,
                roadTypeProfile: tripEstimateRoadTypeProfile,
                motorwaySpeed: tripEstimateMotorwaySpeed,
                roadSurface: tripEstimateRoadSurface,
                windCondition: tripEstimateWindCondition,
                planningMode: tripEstimatePlanningMode,
                rollingResistanceClass: activeRollingResistanceClass,
                airConditioningMode: activeAirConditioningMode,
                usesCustomVehicleProfile: true,
                usableBatteryKWh: tripPlanningUsableBatteryKWh
            )

            guard useContinuousCalibration else {
                return applyingTrailerConsumptionAdjustment(
                    to: ruleBasedForecast,
                    roadTypeProfile: tripEstimateRoadTypeProfile,
                    motorwaySpeed: tripEstimateMotorwaySpeed
                )
            }

            return applyingTrailerConsumptionAdjustment(
                to: ruleBasedForecast.applyingCalibrationFactor(calibrationCorrection.totalFactor),
                roadTypeProfile: tripEstimateRoadTypeProfile,
                motorwaySpeed: tripEstimateMotorwaySpeed
            )
        }

        let calibrationCorrection = continuousCalibrationSummary.correction(
            for: CalibrationPredictionContext(
                roadTypeProfile: tripEstimateRoadTypeProfile,
                tyreSet: activeSelectedTyreSet
            )
        )
        let ruleBasedForecast = MiniConsumptionCalculator.calculateForecast(
            referenceConsumption: calibratedForecastReferenceConsumption(for: calibrationCorrection),
            distance: tripEstimateDistance,
            temperature: tripEstimateTemperature,
            roadTypeProfile: tripEstimateRoadTypeProfile,
            motorwaySpeed: tripEstimateMotorwaySpeed,
            roadSurface: tripEstimateRoadSurface,
            windCondition: tripEstimateWindCondition,
            planningMode: tripEstimatePlanningMode,
            rollingResistanceClass: activeRollingResistanceClass,
            airConditioningMode: activeAirConditioningMode,
            usesCustomVehicleProfile: false,
            usableBatteryKWh: tripPlanningUsableBatteryKWh
        )

        guard useContinuousCalibration else {
            return applyingTrailerConsumptionAdjustment(
                to: ruleBasedForecast,
                roadTypeProfile: tripEstimateRoadTypeProfile,
                motorwaySpeed: tripEstimateMotorwaySpeed
            )
        }

        return applyingTrailerConsumptionAdjustment(
            to: ruleBasedForecast.applyingCalibrationFactor(calibrationCorrection.totalFactor),
            roadTypeProfile: tripEstimateRoadTypeProfile,
            motorwaySpeed: tripEstimateMotorwaySpeed
        )
    }

    private var rangeForecast: ForecastResult {
        rangeForecast(for: .normal)
    }

    private var cautiousRemainingRange: RemainingRangeEstimate {
        rangeRemainingRange(for: .conservative)
    }

    private var normalRemainingRange: RemainingRangeEstimate {
        rangeRemainingRange(for: .normal)
    }

    private var optimisticRemainingRange: RemainingRangeEstimate {
        rangeRemainingRange(for: .optimistic)
    }

    private var rangeUsableBatteryKWh: Double {
        isCustomVehicleProfileSelected
            ? activeVehicleProfile.profile.usableBatteryKWh
            : effectiveUsableBatteryKWh
    }

    private var rangeGaugeMaximumKm: Double {
        guard isCustomVehicleProfileSelected else {
            return RangeGaugeView.defaultScaleUpperBound
        }

        return ceil(activeVehicleProfile.profile.wltpRangeKm / 20) * 20
    }

    private var rangeGaugeWLTPReferenceKm: Double {
        isCustomVehicleProfileSelected
            ? activeVehicleProfile.profile.wltpRangeKm
            : RangeGaugeView.defaultWLTPReferenceRangeKm
    }

    private var sanitizedExperimentalUsableBatteryCapacityKWh: Double {
        positiveFinite(activeVehicleProfile.profile.usableBatteryKWh, fallback: 28.9)
    }

    private var sanitizedExperimentalOfficialWLTPRangeKm: Double {
        positiveFinite(activeVehicleProfile.profile.wltpRangeKm, fallback: 234)
    }

    private var experimentalReferenceConsumptionKWhPer100Km: Double {
        (sanitizedExperimentalUsableBatteryCapacityKWh / degradedModelWLTPRangeKm(for: activeVehicleProfile.profile) * 100) * 1.04
    }

    private var sanitizedExperimentalMaximumDCChargingSpeedKW: Double {
        positiveFinite(activeVehicleProfile.profile.peakDCChargingKW, fallback: 50)
    }

    private var tripPlanningUsableBatteryKWh: Double {
        isCustomVehicleProfileSelected
            ? sanitizedExperimentalUsableBatteryCapacityKWh
            : effectiveUsableBatteryKWh
    }

    private var tripPlanningAverageChargingSpeedKW: Double {
        activeAverageChargingSpeedKW
    }

    private var tripPlanningChargingTaperStartSOC: Double {
        guard isCustomVehicleProfileSelected else {
            return chargingTaperStartSOC
        }

        switch sanitizedExperimentalMaximumDCChargingSpeedKW {
        case ...75:
            return 80
        case ...125:
            return 75
        case ...200:
            return 70
        default:
            return 65
        }
    }

    private var tripPlanningChargingSpeedBoundsKW: ClosedRange<Double> {
        MiniConsumptionCalculator.averageChargingSpeedBoundsKW(for: activeVehicleProfile.profile)
    }

    private func rangeForecast(for planningMode: PlanningMode) -> ForecastResult {
        guard isCustomVehicleProfileSelected else {
            return forecast(for: planningMode)
        }

        let calibrationCorrection = activeCalibrationCorrection
        let ruleBasedForecast = MiniConsumptionCalculator.calculateForecast(
            referenceConsumption: experimentalForecastReferenceConsumption(for: calibrationCorrection),
            distance: distance,
            temperature: temperature,
            roadTypeProfile: roadTypeProfile,
            motorwaySpeed: activeMotorwaySpeed,
            roadSurface: roadSurface,
            windCondition: windCondition,
            planningMode: planningMode,
            rollingResistanceClass: activeRollingResistanceClass,
            airConditioningMode: activeAirConditioningMode,
            applyDistanceAdjustment: false,
            usesCustomVehicleProfile: true,
            usableBatteryKWh: rangeUsableBatteryKWh
        )

        guard useContinuousCalibration else {
            return applyingTrailerConsumptionAdjustment(
                to: ruleBasedForecast,
                roadTypeProfile: roadTypeProfile,
                motorwaySpeed: activeMotorwaySpeed
            )
        }

        return applyingTrailerConsumptionAdjustment(
            to: ruleBasedForecast.applyingCalibrationFactor(calibrationCorrection.totalFactor),
            roadTypeProfile: roadTypeProfile,
            motorwaySpeed: activeMotorwaySpeed
        )
    }

    private func rangeRemainingRange(for planningMode: PlanningMode) -> RemainingRangeEstimate {
        MiniConsumptionCalculator.calculateRemainingRange(
            currentBatteryPercent: startBatteryPercent,
            expectedKWhPer100km: rangeForecast(for: planningMode).finalKWhPer100km,
            usableBatteryKWh: rangeUsableBatteryKWh
        )
    }

    private func forecast(for planningMode: PlanningMode) -> ForecastResult {
        forecast(
            distanceKm: distance,
            planningMode: planningMode,
            applyDistanceAdjustment: false
        )
    }

    private func forecast(
        distanceKm: Double,
        planningMode: PlanningMode,
        applyDistanceAdjustment: Bool = true
    ) -> ForecastResult {
        let calibrationCorrection = activeCalibrationCorrection
        let ruleBasedForecast = MiniConsumptionCalculator.calculateForecast(
            referenceConsumption: calibratedForecastReferenceConsumption(for: calibrationCorrection),
            distance: distanceKm,
            temperature: temperature,
            roadTypeProfile: roadTypeProfile,
            motorwaySpeed: activeMotorwaySpeed,
            roadSurface: roadSurface,
            windCondition: windCondition,
            planningMode: planningMode,
            rollingResistanceClass: activeRollingResistanceClass,
            airConditioningMode: activeAirConditioningMode,
            applyDistanceAdjustment: applyDistanceAdjustment,
            usesCustomVehicleProfile: false,
            usableBatteryKWh: rangeUsableBatteryKWh
        )

        guard useContinuousCalibration else {
            return applyingTrailerConsumptionAdjustment(
                to: ruleBasedForecast,
                roadTypeProfile: roadTypeProfile,
                motorwaySpeed: activeMotorwaySpeed
            )
        }

        return applyingTrailerConsumptionAdjustment(
            to: ruleBasedForecast.applyingCalibrationFactor(calibrationCorrection.totalFactor),
            roadTypeProfile: roadTypeProfile,
            motorwaySpeed: activeMotorwaySpeed
        )
    }

    private func remainingRange(for planningMode: PlanningMode) -> RemainingRangeEstimate {
        MiniConsumptionCalculator.calculateRemainingRange(
            currentBatteryPercent: startBatteryPercent,
            expectedKWhPer100km: forecast(for: planningMode).finalKWhPer100km,
            usableBatteryKWh: effectiveUsableBatteryKWh
        )
    }

    private var outcomeLogForecast: ForecastResult {
        if isCustomVehicleProfileSelected {
            let calibrationCorrection = continuousCalibrationSummary.correction(
                for: CalibrationPredictionContext(
                    roadTypeProfile: outcomeRoadTypeProfile,
                    tyreSet: outcomeTyreSet
                )
            )
            let ruleBasedForecast = MiniConsumptionCalculator.calculateForecast(
                referenceConsumption: experimentalForecastReferenceConsumption(for: calibrationCorrection),
                distance: distance,
                temperature: outcomeTemperature,
                roadTypeProfile: outcomeRoadTypeProfile,
                motorwaySpeed: outcomeMotorwaySpeed,
                roadSurface: outcomeRoadSurface,
                windCondition: outcomeWindCondition,
                planningMode: .normal,
                rollingResistanceClass: outcomeRollingResistanceClass,
                airConditioningMode: activeAirConditioningMode,
                usesCustomVehicleProfile: true,
                usableBatteryKWh: rangeUsableBatteryKWh
            )

            guard useContinuousCalibration else {
                return ruleBasedForecast
            }

            return ruleBasedForecast.applyingCalibrationFactor(calibrationCorrection.totalFactor)
        }

        let calibrationCorrection = continuousCalibrationSummary.correction(
            for: CalibrationPredictionContext(
                roadTypeProfile: outcomeRoadTypeProfile,
                tyreSet: outcomeTyreSet
            )
        )
        let ruleBasedForecast = MiniConsumptionCalculator.calculateForecast(
            referenceConsumption: calibratedForecastReferenceConsumption(for: calibrationCorrection),
            distance: distance,
            temperature: outcomeTemperature,
            roadTypeProfile: outcomeRoadTypeProfile,
            motorwaySpeed: outcomeMotorwaySpeed,
            roadSurface: outcomeRoadSurface,
            windCondition: outcomeWindCondition,
            planningMode: .normal,
            rollingResistanceClass: outcomeRollingResistanceClass,
            airConditioningMode: activeAirConditioningMode,
            usesCustomVehicleProfile: false,
            usableBatteryKWh: rangeUsableBatteryKWh
        )

        guard useContinuousCalibration else {
            return ruleBasedForecast
        }

        return ruleBasedForecast.applyingCalibrationFactor(calibrationCorrection.totalFactor)
    }

    private var outcomeLogRemainingRange: RemainingRangeEstimate {
        MiniConsumptionCalculator.calculateRemainingRange(
            currentBatteryPercent: startBatteryPercent,
            expectedKWhPer100km: outcomeLogForecast.finalKWhPer100km,
            usableBatteryKWh: rangeUsableBatteryKWh
        )
    }

    private var activeVehicleProfileKind: VehicleProfileKind {
        activeVehicleProfile.loggedTripKind
    }

    private var activeVehicleProfile: ActiveVehicleProfile {
        VehicleProfileResolver.activeProfile(
            for: vehicleProfileResolverInput,
            customProfiles: customVehicleProfiles,
            selectedProfileID: selectedVehicleProfileID
        )
    }

    private var watchRangeStateSnapshot: WatchRangeStateSnapshot {
        let profile = activeVehicleProfile.profile

        return WatchRangeStateSnapshot(
            batteryPercent: startBatteryPercent,
            roadTypeProfile: roadTypeProfile,
            temperatureC: temperature,
            activeVehicleProfileID: profile.id,
            availableVehicleProfiles: availableWatchVehicleProfiles,
            vehicleProfileName: profile.displayName,
            vehicleProfileKind: profile.kind,
            referenceConsumptionKWhPer100Km: activeVehicleProfileManualReferenceConsumption,
            usableBatteryKWh: profile.usableBatteryKWh,
            wltpRangeKm: profile.wltpRangeKm,
            peakDCChargingKW: profile.peakDCChargingKW,
            batteryDegradationPercent: profile.batteryDegradationPercent,
            motorwaySpeed: activeMotorwaySpeed,
            roadSurface: roadSurface,
            windCondition: windCondition,
            airConditioningMode: activeAirConditioningMode,
            selectedTyreSet: activeSelectedTyreSet,
            summerTyreClass: activeSummerTyreClass,
            winterTyreClass: activeWinterTyreClass,
            useContinuousCalibration: useContinuousCalibration,
            displayUnitsRawValue: displayUnits.rawValue,
            temperatureUnitsRawValue: temperatureUnits.rawValue
        )
    }

    private var availableWatchVehicleProfiles: [VehicleProfile] {
        [VehicleProfileResolver.builtInMiniProfile(from: vehicleProfileResolverInput)] + customVehicleProfiles
    }

    private var isCustomVehicleProfileSelected: Bool {
        activeVehicleProfile.usesCustomEVBehavior
    }

    private var activeAverageChargingSpeedKW: Double {
        averageChargingSpeedKW(for: activeVehicleProfile.profile)
    }

    private var activeAverageChargingSpeedDefaultKW: Double {
        MiniConsumptionCalculator.defaultAverageChargingSpeedKW(for: activeVehicleProfile.profile)
    }

    private var activeMotorwaySpeed: Double {
        motorwaySpeed(for: activeVehicleProfile.profile)
    }

    private var normalizedTrailerWeightKg: Double {
        MiniConsumptionDefaults.normalizedTrailerWeightKg(trailerWeightKg)
    }

    private func trailerExtraConsumptionKWhPer100Km(
        roadTypeProfile: RoadTypeProfile,
        motorwaySpeed: Double
    ) -> Double {
        guard trailerTowModeEnabled else {
            return 0
        }

        let weightExtraConsumption = normalizedTrailerWeightKg * 0.003
        let aerodynamicExtraConsumption = boxyTrailerEnabled
            ? boxyTrailerAerodynamicExtraConsumptionKWhPer100Km(
                roadTypeProfile: roadTypeProfile,
                motorwaySpeed: motorwaySpeed
            )
            : 0

        return weightExtraConsumption + aerodynamicExtraConsumption
    }

    private func boxyTrailerAerodynamicExtraConsumptionKWhPer100Km(
        roadTypeProfile: RoadTypeProfile,
        motorwaySpeed: Double
    ) -> Double {
        let baseExtraConsumption: Double
        switch roadTypeProfile {
        case .cityMix:
            baseExtraConsumption = 0.8
        case .countryside:
            baseExtraConsumption = 1.2
        case .motorwayMix:
            baseExtraConsumption = 2.2
        case .motorway:
            baseExtraConsumption = 3.0
        }

        let speedKmh: Double
        switch roadTypeProfile {
        case .cityMix:
            speedKmh = 50
        case .countryside:
            speedKmh = 80
        case .motorwayMix, .motorway:
            speedKmh = MiniConsumptionDefaults.normalizedMotorwaySpeed(motorwaySpeed)
        }

        let speedFactor = pow(speedKmh / 100, 2)
        return baseExtraConsumption * speedFactor
    }

    private var trailerWeightText: String {
        weightUnits.formattedWeight(normalizedTrailerWeightKg)
    }

    private func applyingTrailerConsumptionAdjustment(
        to forecast: ForecastResult,
        roadTypeProfile: RoadTypeProfile,
        motorwaySpeed: Double
    ) -> ForecastResult {
        forecast.applyingFinalConsumptionAddition(
            trailerExtraConsumptionKWhPer100Km(
                roadTypeProfile: roadTypeProfile,
                motorwaySpeed: motorwaySpeed
            )
        )
    }

    private var activeAirConditioningMode: AirConditioningMode {
        airConditioningMode(for: activeVehicleProfile.profile)
    }

    private var activeSelectedTyreSet: TyreSet {
        selectedTyreSet(for: activeVehicleProfile.profile)
    }

    private var activeSummerTyreClass: RollingResistanceClass {
        summerTyreClass(for: activeVehicleProfile.profile)
    }

    private var activeWinterTyreClass: RollingResistanceClass {
        winterTyreClass(for: activeVehicleProfile.profile)
    }

    private var activeNormalMinimumChargingPercent: Double {
        normalMinimumChargingPercent(for: activeVehicleProfile.profile)
    }

    private var activeNormalFastChargeTargetPercent: Double {
        normalFastChargeTargetPercent(for: activeVehicleProfile.profile)
    }

    private var vehicleProfileResolverInput: VehicleProfileResolverInput {
        VehicleProfileResolverInput(
            experimentalCustomVehicleProfileEnabled: experimentalCustomVehicleProfileEnabled,
            experimentalUsableBatteryCapacityKWh: experimentalUsableBatteryCapacityKWh,
            experimentalOfficialWLTPRangeKm: experimentalOfficialWLTPRangeKm,
            experimentalMaximumDCChargingSpeedKW: experimentalMaximumDCChargingSpeedKW,
            batteryDegradationPercent: batteryDegradationPercent,
            summerTyreClass: summerTyreClass,
            winterTyreClass: winterTyreClass
        )
    }

    private func publishWatchRangeStateSnapshot() {
        WatchRangeStateSnapshotStore.save(watchRangeStateSnapshot)
    }

    private var continuousCalibrationSummary: ContinuousCalibrationSummary {
        ContinuousCalibrationSummary(outcomes: outcomes, vehicleProfileKind: activeVehicleProfileKind)
    }

    private var activeCalibrationCorrection: CalibrationCorrection {
        continuousCalibrationSummary.correction(
            for: CalibrationPredictionContext(
                roadTypeProfile: roadTypeProfile,
                tyreSet: activeSelectedTyreSet
            )
        )
    }

    private var normalChargingWindow: ChargingWindow {
        ChargingWindow(
            minimumPercent: activeNormalMinimumChargingPercent,
            targetPercent: activeNormalFastChargeTargetPercent
        )
    }

    private var draftChargingWindow: ChargingWindow {
        ChargingWindow(
            minimumPercent: draftMinimumChargingPercent,
            targetPercent: draftFastChargeTargetPercent
        )
    }

    private var tripPlanningChargingWindow: ChargingWindow {
        normalChargingWindow
    }

    private var effectiveUsableBatteryKWh: Double {
        MiniConsumptionCalculator.effectiveUsableBatteryKWh(degradationPercent: batteryDegradationPercent)
    }

    private var chargingTaperStartSOC: Double {
        MiniConsumptionCalculator.chargingTaperStartSOC(degradationPercent: batteryDegradationPercent)
    }

    private var effectiveReferenceConsumption: Double {
        if isCustomVehicleProfileSelected {
            if useContinuousCalibration, activeCalibrationCorrection.canApply {
                return activeVehicleProfileDefaultReferenceConsumption
                    * MiniConsumptionCalculator.calibrationSafetyMultiplier
                    * activeCalibrationCorrection.totalFactor
            }

            return activeVehicleProfileManualReferenceConsumption
        }

        if useContinuousCalibration, activeCalibrationCorrection.canApply {
            return MiniConsumptionCalculator.continuousCalibrationBaseReferenceConsumptionKWhPer100Km
                * activeCalibrationCorrection.totalFactor
                * MiniConsumptionCalculator.calibrationSafetyMultiplier
        }

        return referenceConsumption
    }

    private func calibratedForecastReferenceConsumption(for correction: CalibrationCorrection) -> Double {
        guard useContinuousCalibration, correction.canApply else {
            return referenceConsumption
        }

        return MiniConsumptionCalculator.continuousCalibrationBaseReferenceConsumptionKWhPer100Km
            * MiniConsumptionCalculator.calibrationSafetyMultiplier
    }

    private func experimentalForecastReferenceConsumption(for correction: CalibrationCorrection) -> Double {
        guard useContinuousCalibration, correction.canApply else {
            return activeVehicleProfileManualReferenceConsumption
        }

        return activeVehicleProfileDefaultReferenceConsumption
            * MiniConsumptionCalculator.calibrationSafetyMultiplier
    }

    private var batteryPlan: BatteryPlan {
        MiniConsumptionCalculator.calculateBatteryPlan(
            totalTripKWh: tripEstimateForecast.totalKWh,
            startBatteryPercent: tripEstimateStartBatteryPercent,
            temperature: tripEstimateTemperature,
            chargingWindow: tripPlanningChargingWindow,
            arrivalBatteryTargetPercent: tripEstimateArrivalBatteryTargetPercent,
            averageChargingSpeedKW: tripPlanningAverageChargingSpeedKW,
            chargingSetupMinutes: tripChargingSetupMinutes,
            usableBatteryKWh: tripPlanningUsableBatteryKWh,
            chargingTaperStartSOC: tripPlanningChargingTaperStartSOC,
            chargingSpeedBoundsKW: tripPlanningChargingSpeedBoundsKW
        )
    }

    private var normalizedQuickTripDistance: Double {
        MiniConsumptionDefaults.normalizedQuickTripDistance(quickTripDistance)
    }

    private var quickTripForecast: ForecastResult {
        guard isCustomVehicleProfileSelected else {
            return forecast(
                distanceKm: normalizedQuickTripDistance,
                planningMode: tripPlanningStrategy,
                applyDistanceAdjustment: false
            )
        }

        let calibrationCorrection = activeCalibrationCorrection
        let ruleBasedForecast = MiniConsumptionCalculator.calculateForecast(
            referenceConsumption: experimentalForecastReferenceConsumption(for: calibrationCorrection),
            distance: normalizedQuickTripDistance,
            temperature: temperature,
            roadTypeProfile: roadTypeProfile,
            motorwaySpeed: activeMotorwaySpeed,
            roadSurface: roadSurface,
            windCondition: windCondition,
            planningMode: tripPlanningStrategy,
            rollingResistanceClass: activeRollingResistanceClass,
            airConditioningMode: activeAirConditioningMode,
            applyDistanceAdjustment: false,
            usesCustomVehicleProfile: true,
            usableBatteryKWh: rangeUsableBatteryKWh
        )

        guard useContinuousCalibration else {
            return applyingTrailerConsumptionAdjustment(
                to: ruleBasedForecast,
                roadTypeProfile: roadTypeProfile,
                motorwaySpeed: activeMotorwaySpeed
            )
        }

        return applyingTrailerConsumptionAdjustment(
            to: ruleBasedForecast.applyingCalibrationFactor(calibrationCorrection.totalFactor),
            roadTypeProfile: roadTypeProfile,
            motorwaySpeed: activeMotorwaySpeed
        )
    }

    private var quickTripBatteryPlan: BatteryPlan {
        MiniConsumptionCalculator.calculateBatteryPlan(
            totalTripKWh: quickTripForecast.totalKWh,
            startBatteryPercent: startBatteryPercent,
            temperature: temperature,
            chargingWindow: tripPlanningChargingWindow,
            arrivalBatteryTargetPercent: arrivalBatteryTargetPercent,
            averageChargingSpeedKW: tripPlanningAverageChargingSpeedKW,
            chargingSetupMinutes: tripChargingSetupMinutes,
            usableBatteryKWh: tripPlanningUsableBatteryKWh,
            chargingTaperStartSOC: tripPlanningChargingTaperStartSOC,
            chargingSpeedBoundsKW: tripPlanningChargingSpeedBoundsKW
        )
    }

    private var remainingRange: RemainingRangeEstimate {
        MiniConsumptionCalculator.calculateRemainingRange(
            currentBatteryPercent: startBatteryPercent,
            expectedKWhPer100km: rangeForecast.finalKWhPer100km,
            usableBatteryKWh: rangeUsableBatteryKWh
        )
    }

    private var displayedQuickTripDistanceBinding: Binding<Double> {
        Binding(
            get: { displayUnits.displayDistance(fromKm: normalizedQuickTripDistance) },
            set: { quickTripDistance = MiniConsumptionDefaults.normalizedQuickTripDistance(displayUnits.storedDistance(fromDisplayed: $0)) }
        )
    }

    private var displayedTripEstimateDistanceBinding: Binding<Double> {
        Binding(
            get: { displayUnits.displayDistance(fromKm: tripEstimateDistance) },
            set: { tripEstimateDistance = min(max(displayUnits.storedDistance(fromDisplayed: $0), 1), 1000) }
        )
    }

    private var displayedTripEstimateTemperatureBinding: Binding<Double> {
        Binding(
            get: { temperatureUnits.displayTemperature(fromCelsius: tripEstimateTemperature).rounded() },
            set: {
                tripEstimateTemperature = min(
                    max(temperatureUnits.storedTemperature(fromDisplayed: $0), supportedTemperatureRangeC.lowerBound),
                    supportedTemperatureRangeC.upperBound
                )
            }
        )
    }

    private var displayedDraftTripAssumptionsTemperatureBinding: Binding<Double> {
        Binding(
            get: { temperatureUnits.displayTemperature(fromCelsius: draftTripAssumptionsTemperature).rounded() },
            set: {
                draftTripAssumptionsTemperature = min(
                    max(temperatureUnits.storedTemperature(fromDisplayed: $0), supportedTemperatureRangeC.lowerBound),
                    supportedTemperatureRangeC.upperBound
                )
            }
        )
    }

    private var displayedDraftTripDetailsTemperatureBinding: Binding<Double> {
        Binding(
            get: { temperatureUnits.displayTemperature(fromCelsius: draftTripDetailsTemperature).rounded() },
            set: {
                draftTripDetailsTemperature = min(
                    max(temperatureUnits.storedTemperature(fromDisplayed: $0), supportedTemperatureRangeC.lowerBound),
                    supportedTemperatureRangeC.upperBound
                )
            }
        )
    }

    private var displayedOutcomeTemperatureBinding: Binding<Double> {
        Binding(
            get: { temperatureUnits.displayTemperature(fromCelsius: outcomeTemperature).rounded() },
            set: {
                outcomeTemperature = min(
                    max(temperatureUnits.storedTemperature(fromDisplayed: $0), supportedTemperatureRangeC.lowerBound),
                    supportedTemperatureRangeC.upperBound
                )
            }
        )
    }

    private var displayedReferenceConsumptionBinding: Binding<Double> {
        Binding(
            get: { displayUnits.displayConsumption(fromKWhPer100Km: activeVehicleProfileManualReferenceConsumption) },
            set: { setManualReferenceConsumption(displayUnits.storedConsumption(fromDisplayed: $0), for: activeVehicleProfile.profile) }
        )
    }

    private var vehicleProfileTemplateSelectionBinding: Binding<String> {
        Binding(
            get: { selectedVehicleProfileTemplateID },
            set: { applySelectedVehicleProfileTemplate(id: $0) }
        )
    }

    private var vehicleProfileTemplateBrandSelectionBinding: Binding<String> {
        Binding(
            get: { selectedVehicleProfileTemplateBrand },
            set: { applySelectedVehicleProfileTemplateBrand($0) }
        )
    }

    private var selectedVehicleProfileBrandTemplates: [VehicleProfileTemplate] {
        guard selectedVehicleProfileTemplateBrand != VehicleProfileTemplate.customProfileID else {
            return []
        }

        return VehicleProfileTemplate.templates(forBrand: selectedVehicleProfileTemplateBrand)
    }

    private var displayedTemperatureBinding: Binding<Double> {
        Binding(
            get: { temperatureUnits.displayTemperature(fromCelsius: temperature).rounded() },
            set: { temperature = temperatureUnits.storedTemperature(fromDisplayed: $0) }
        )
    }

    private var trailerWeightBinding: Binding<Double> {
        Binding(
            get: { weightUnits.displayWeight(fromKg: normalizedTrailerWeightKg) },
            set: { trailerWeightKg = MiniConsumptionDefaults.normalizedTrailerWeightKg(weightUnits.storedWeightKg(fromDisplayed: $0)) }
        )
    }

    private var displayedTrailerWeightRange: ClosedRange<Double> {
        switch weightUnits {
        case .kilograms:
            MiniConsumptionDefaults.trailerWeightRangeKg
        case .pounds:
            400...3300
        }
    }

    private var displayedTrailerWeightStep: Double {
        switch weightUnits {
        case .kilograms:
            MiniConsumptionDefaults.trailerWeightStepKg
        case .pounds:
            100
        }
    }

    private var referenceConsumptionDisplayRange: ClosedRange<Double> {
        let defaultReferenceConsumption = activeVehicleProfileDefaultReferenceConsumption
        return displayRange(forStoredConsumptionRange: (defaultReferenceConsumption - 3.0)...(defaultReferenceConsumption + 3.0))
    }

    private var displayedTripDistanceRange: ClosedRange<Double> {
        displayRange(forStoredDistanceRange: 1...1000)
    }

    private var displayedDraftTripDetailsDistanceBinding: Binding<Double> {
        Binding(
            get: { displayUnits.displayDistance(fromKm: draftTripDetailsDistanceKm ?? 1) },
            set: { draftTripDetailsDistanceKm = min(max(displayUnits.storedDistance(fromDisplayed: $0), 1), 1000) }
        )
    }

    private var displayedTemperatureRange: ClosedRange<Double> {
        temperatureUnits.displayRange(forCelsiusRange: supportedTemperatureRangeC)
    }

    private var displayedMotorwaySpeedRange: ClosedRange<Double> {
        let range = MiniConsumptionDefaults.motorwaySpeedRange
        switch displayUnits {
        case .metric:
            return range
        case .imperial:
            return roundedWholeDisplayRange(
                range.lowerBound / kilometersPerMile,
                range.upperBound / kilometersPerMile
            )
        }
    }

    private var rangeChargingLegRangeKm: Double {
        MiniConsumptionCalculator.calculateChargingLegRange(
            expectedKWhPer100km: forecast(for: .normal).finalKWhPer100km,
            chargingWindow: normalChargingWindow,
            usableBatteryKWh: effectiveUsableBatteryKWh
        )
    }

    private var quickTripChargingLegRangeKm: Double {
        MiniConsumptionCalculator.calculateChargingLegRange(
            expectedKWhPer100km: quickTripForecast.finalKWhPer100km,
            chargingWindow: tripPlanningChargingWindow,
            usableBatteryKWh: tripPlanningUsableBatteryKWh
        )
    }

    private var tripChargingLegRangeKm: Double {
        MiniConsumptionCalculator.calculateChargingLegRange(
            expectedKWhPer100km: tripEstimateForecast.finalKWhPer100km,
            chargingWindow: tripPlanningChargingWindow,
            usableBatteryKWh: tripPlanningUsableBatteryKWh
        )
    }

    private var tripChargingPresentation: TripChargingPresentation {
#if canImport(MapKit)
        let expectedDrivingTime = isTripDistanceMapDerived
            ? tripAssistantRouteEstimate?.expectedTravelTime.map {
                adjustedDrivingTime(
                    mapsDrivingTime: $0,
                    roadTypeProfile: tripEstimateRoadTypeProfile,
                    motorwaySpeedKmh: tripEstimateMotorwaySpeed,
                    displayUnits: displayUnits
                )
            }
            : nil
#else
        let expectedDrivingTime: TimeInterval? = nil
#endif

        return TripChargingPresentation(
            batteryPlan: batteryPlan,
            distanceKm: tripEstimateDistance,
            expectedDrivingTime: expectedDrivingTime,
            expectedKWhPer100km: tripEstimateForecast.finalKWhPer100km,
            chargingLegRangeKm: tripChargingLegRangeKm,
            chargingWindow: tripPlanningChargingWindow,
            temperature: tripEstimateTemperature,
            averageChargingSpeedKW: tripPlanningAverageChargingSpeedKW,
            chargingSetupMinutes: tripChargingSetupMinutes,
            usableBatteryKWh: tripPlanningUsableBatteryKWh,
            chargingTaperStartSOC: tripPlanningChargingTaperStartSOC,
            chargingSpeedBoundsKW: tripPlanningChargingSpeedBoundsKW,
            displayUnits: displayUnits
        )
    }

    private var quickTripChargingPresentation: TripChargingPresentation {
        TripChargingPresentation(
            batteryPlan: quickTripBatteryPlan,
            distanceKm: normalizedQuickTripDistance,
            expectedDrivingTime: nil,
            expectedKWhPer100km: quickTripForecast.finalKWhPer100km,
            chargingLegRangeKm: quickTripChargingLegRangeKm,
            chargingWindow: tripPlanningChargingWindow,
            temperature: temperature,
            averageChargingSpeedKW: tripPlanningAverageChargingSpeedKW,
            chargingSetupMinutes: tripChargingSetupMinutes,
            usableBatteryKWh: tripPlanningUsableBatteryKWh,
            chargingTaperStartSOC: tripPlanningChargingTaperStartSOC,
            chargingSpeedBoundsKW: tripPlanningChargingSpeedBoundsKW,
            displayUnits: displayUnits
        )
    }

    private var selectedTripChargingOptionPlan: TripChargingOptionPlan? {
        tripChargingPresentation.chargingOptionPlan(for: selectedTripChargingOption)
            ?? tripChargingPresentation.chargingOptionPlan(for: .userSettings)
            ?? tripChargingPresentation.chargingOptionPlans.first
    }

    private var selectedQuickTripChargingOptionPlan: TripChargingOptionPlan? {
        quickTripChargingPresentation.chargingOptionPlan(for: .userSettings)
            ?? quickTripChargingPresentation.chargingOptionPlans.first
    }

    private var hasTripRoutePlanningResult: Bool {
        hasTripEstimate
    }

#if canImport(MapKit)
    private var tripAssistantNextChargingSearchCoordinate: CLLocationCoordinate2D? {
        guard let routeEstimate = tripAssistantRouteEstimate,
              let polyline = routeEstimate.polyline,
              batteryPlan.needsCharging,
              let searchDistanceKm = selectedTripChargingOptionPlan?.nextStopDistanceKm
        else {
            return nil
        }

        guard searchDistanceKm > 0, searchDistanceKm < routeEstimate.distanceKm else {
            return nil
        }

        return RoutePolylineDistance.coordinate(on: polyline, atDistanceKm: searchDistanceKm)
    }
#endif

    private var motorwaySpeedBinding: Binding<Double> {
        Binding(
            get: { displayedMotorwaySpeed(fromKmh: MiniConsumptionDefaults.normalizedMotorwaySpeed(activeMotorwaySpeed)) },
            set: { setMotorwaySpeed(MiniConsumptionDefaults.normalizedMotorwaySpeed(storedMotorwaySpeed(fromDisplayed: $0)), for: activeVehicleProfile.profile) }
        )
    }

    private var tripEstimateMotorwaySpeedBinding: Binding<Double> {
        Binding(
            get: { MiniConsumptionDefaults.normalizedMotorwaySpeed(tripEstimateMotorwaySpeed) },
            set: { tripEstimateMotorwaySpeed = MiniConsumptionDefaults.normalizedMotorwaySpeed($0) }
        )
    }

    private var draftTripAssumptionsMotorwaySpeedBinding: Binding<Double> {
        Binding(
            get: { MiniConsumptionDefaults.normalizedMotorwaySpeed(draftTripAssumptionsMotorwaySpeed) },
            set: { draftTripAssumptionsMotorwaySpeed = MiniConsumptionDefaults.normalizedMotorwaySpeed($0) }
        )
    }

    private var displayedDraftTripAssumptionsMotorwaySpeedBinding: Binding<Double> {
        Binding(
            get: { displayedMotorwaySpeed(fromKmh: MiniConsumptionDefaults.normalizedMotorwaySpeed(draftTripAssumptionsMotorwaySpeed)) },
            set: { draftTripAssumptionsMotorwaySpeed = MiniConsumptionDefaults.normalizedMotorwaySpeed(storedMotorwaySpeed(fromDisplayed: $0)) }
        )
    }

    private var displayedDraftTripDetailsMotorwaySpeedBinding: Binding<Double> {
        Binding(
            get: { displayedMotorwaySpeed(fromKmh: MiniConsumptionDefaults.normalizedMotorwaySpeed(draftTripDetailsMotorwaySpeed)) },
            set: { draftTripDetailsMotorwaySpeed = MiniConsumptionDefaults.normalizedMotorwaySpeed(storedMotorwaySpeed(fromDisplayed: $0)) }
        )
    }

    private var displayedOutcomeMotorwaySpeedBinding: Binding<Double> {
        Binding(
            get: { displayedMotorwaySpeed(fromKmh: MiniConsumptionDefaults.normalizedMotorwaySpeed(outcomeMotorwaySpeed)) },
            set: { outcomeMotorwaySpeed = MiniConsumptionDefaults.normalizedMotorwaySpeed(storedMotorwaySpeed(fromDisplayed: $0)) }
        )
    }

    private var tripEstimateStartBatteryPercentBinding: Binding<Double> {
        Binding(
            get: { min(max(tripEstimateStartBatteryPercent, 10), 100) },
            set: { tripEstimateStartBatteryPercent = min(max($0, 10), 100) }
        )
    }

    private var draftTripAssumptionsStartBatteryPercentBinding: Binding<Double> {
        Binding(
            get: { min(max(draftTripAssumptionsStartBatteryPercent, 10), 100) },
            set: { draftTripAssumptionsStartBatteryPercent = min(max($0, 10), 100) }
        )
    }

    private var tripEstimateArrivalBatteryTargetPercentBinding: Binding<Double> {
        Binding(
            get: {
                min(
                    max(tripEstimateArrivalBatteryTargetPercent, ChargingWindow.arrivalBatteryTargetBounds.lowerBound),
                    ChargingWindow.arrivalBatteryTargetBounds.upperBound
                )
            },
            set: {
                tripEstimateArrivalBatteryTargetPercent = min(
                    max($0, ChargingWindow.arrivalBatteryTargetBounds.lowerBound),
                    ChargingWindow.arrivalBatteryTargetBounds.upperBound
                )
            }
        )
    }

    private var draftTripAssumptionsArrivalBatteryTargetPercentBinding: Binding<Double> {
        Binding(
            get: {
                min(
                    max(draftTripAssumptionsArrivalBatteryTargetPercent, ChargingWindow.arrivalBatteryTargetBounds.lowerBound),
                    ChargingWindow.arrivalBatteryTargetBounds.upperBound
                )
            },
            set: {
                draftTripAssumptionsArrivalBatteryTargetPercent = min(
                    max($0, ChargingWindow.arrivalBatteryTargetBounds.lowerBound),
                    ChargingWindow.arrivalBatteryTargetBounds.upperBound
                )
            }
        )
    }

    private var segmentedRoadSurface: Binding<RoadSurface> {
        Binding(
            get: { roadSurface.segmentedEquivalent },
            set: { roadSurface = $0 }
        )
    }

    private var rangeWindConditionBinding: Binding<WindCondition> {
        Binding(
            get: { windCondition },
            set: { setWindCondition($0) }
        )
    }

    private var draftTripDetailsRoadSurfaceBinding: Binding<RoadSurface> {
        Binding(
            get: { draftTripDetailsRoadSurface.segmentedEquivalent },
            set: { draftTripDetailsRoadSurface = $0 }
        )
    }

    private var outcomeRoadSurfaceBinding: Binding<RoadSurface> {
        Binding(
            get: { outcomeRoadSurface.segmentedEquivalent },
            set: { outcomeRoadSurface = $0 }
        )
    }

    private var normalMinimumChargingPercentBinding: Binding<Double> {
        Binding(
            get: {
                let target = clampedFinite(
                    activeNormalFastChargeTargetPercent,
                    in: ChargingWindow.targetBounds,
                    fallback: ChargingWindow.defaultTargetPercent
                )
                let minimum = clampedFinite(
                    activeNormalMinimumChargingPercent,
                    in: ChargingWindow.minimumBounds,
                    fallback: ChargingWindow.defaultMinimumPercent
                )
                return min(minimum, target - 1)
            },
            set: { newValue in
                let clampedValue = clampedFinite(
                    newValue,
                    in: ChargingWindow.minimumBounds,
                    fallback: ChargingWindow.defaultMinimumPercent
                )
                let target = clampedFinite(
                    activeNormalFastChargeTargetPercent,
                    in: ChargingWindow.targetBounds,
                    fallback: ChargingWindow.defaultTargetPercent
                )
                setNormalMinimumChargingPercent(min(clampedValue, target - 1), for: activeVehicleProfile.profile)
            }
        )
    }

    private var normalFastChargeTargetPercentBinding: Binding<Double> {
        Binding(
            get: {
                let minimum = clampedFinite(
                    activeNormalMinimumChargingPercent,
                    in: ChargingWindow.minimumBounds,
                    fallback: ChargingWindow.defaultMinimumPercent
                )
                let target = clampedFinite(
                    activeNormalFastChargeTargetPercent,
                    in: ChargingWindow.targetBounds,
                    fallback: ChargingWindow.defaultTargetPercent
                )
                return max(target, minimum + 1)
            },
            set: { newValue in
                let clampedValue = clampedFinite(
                    newValue,
                    in: ChargingWindow.targetBounds,
                    fallback: ChargingWindow.defaultTargetPercent
                )
                let minimum = clampedFinite(
                    activeNormalMinimumChargingPercent,
                    in: ChargingWindow.minimumBounds,
                    fallback: ChargingWindow.defaultMinimumPercent
                )
                setNormalFastChargeTargetPercent(max(clampedValue, minimum + 1), for: activeVehicleProfile.profile)
            }
        )
    }

    private var draftMinimumChargingPercentBinding: Binding<Double> {
        Binding(
            get: {
                let target = clampedFinite(
                    draftFastChargeTargetPercent,
                    in: ChargingWindow.targetBounds,
                    fallback: ChargingWindow.defaultTargetPercent
                )
                let minimum = clampedFinite(
                    draftMinimumChargingPercent,
                    in: ChargingWindow.minimumBounds,
                    fallback: ChargingWindow.defaultMinimumPercent
                )
                return min(minimum, target - 1)
            },
            set: { newValue in
                let clampedValue = clampedFinite(
                    newValue,
                    in: ChargingWindow.minimumBounds,
                    fallback: ChargingWindow.defaultMinimumPercent
                )
                let target = clampedFinite(
                    draftFastChargeTargetPercent,
                    in: ChargingWindow.targetBounds,
                    fallback: ChargingWindow.defaultTargetPercent
                )
                draftMinimumChargingPercent = min(clampedValue, target - 1)
            }
        )
    }

    private var draftFastChargeTargetPercentBinding: Binding<Double> {
        Binding(
            get: {
                let minimum = clampedFinite(
                    draftMinimumChargingPercent,
                    in: ChargingWindow.minimumBounds,
                    fallback: ChargingWindow.defaultMinimumPercent
                )
                let target = clampedFinite(
                    draftFastChargeTargetPercent,
                    in: ChargingWindow.targetBounds,
                    fallback: ChargingWindow.defaultTargetPercent
                )
                return max(target, minimum + 1)
            },
            set: { newValue in
                let clampedValue = clampedFinite(
                    newValue,
                    in: ChargingWindow.targetBounds,
                    fallback: ChargingWindow.defaultTargetPercent
                )
                let minimum = clampedFinite(
                    draftMinimumChargingPercent,
                    in: ChargingWindow.minimumBounds,
                    fallback: ChargingWindow.defaultMinimumPercent
                )
                draftFastChargeTargetPercent = max(clampedValue, minimum + 1)
            }
        )
    }

    private var draftArrivalBatteryTargetPercentBinding: Binding<Double> {
        Binding(
            get: {
                min(
                    max(draftArrivalBatteryTargetPercent, ChargingWindow.arrivalBatteryTargetBounds.lowerBound),
                    ChargingWindow.arrivalBatteryTargetBounds.upperBound
                )
            },
            set: {
                draftArrivalBatteryTargetPercent = min(
                    max($0, ChargingWindow.arrivalBatteryTargetBounds.lowerBound),
                    ChargingWindow.arrivalBatteryTargetBounds.upperBound
                )
            }
        )
    }

    private var arrivalBatteryTargetPercentBinding: Binding<Double> {
        Binding(
            get: { min(max(arrivalBatteryTargetPercent, ChargingWindow.arrivalBatteryTargetBounds.lowerBound), ChargingWindow.arrivalBatteryTargetBounds.upperBound) },
            set: { arrivalBatteryTargetPercent = min(max($0, ChargingWindow.arrivalBatteryTargetBounds.lowerBound), ChargingWindow.arrivalBatteryTargetBounds.upperBound) }
        )
    }

    private var averageChargingSpeedKWBinding: Binding<Double> {
        Binding(
            get: {
                activeAverageChargingSpeedKW
            },
            set: {
                setAverageChargingSpeedKW($0, for: activeVehicleProfile.profile)
            }
        )
    }

    private func averageChargingSpeedKW(for profile: VehicleProfile) -> Double {
        let defaultValue = MiniConsumptionCalculator.defaultAverageChargingSpeedKW(for: profile)
        let bounds = MiniConsumptionCalculator.averageChargingSpeedBoundsKW(for: profile)

        guard profile.kind == .custom else {
            return clampedFinite(
                averageChargingSpeedKW,
                in: bounds,
                fallback: defaultValue
            )
        }

        guard let overrideValue = averageChargingSpeedOverridesByProfileID[profile.id] else {
            return defaultValue
        }

        return clampedFinite(
            overrideValue,
            in: bounds,
            fallback: defaultValue
        )
    }

    private func setAverageChargingSpeedKW(_ value: Double, for profile: VehicleProfile) {
        let clampedValue = clampedFinite(
            value,
            in: MiniConsumptionCalculator.averageChargingSpeedBoundsKW(for: profile),
            fallback: MiniConsumptionCalculator.defaultAverageChargingSpeedKW(for: profile)
        )

        if profile.kind == .custom {
            var overrides = averageChargingSpeedOverridesByProfileID
            overrides[profile.id] = clampedValue
            averageChargingSpeedOverridesByProfileID = overrides
        } else {
            averageChargingSpeedKW = clampedValue
        }

        resetTransientAlternativeTripPlanSelection()
    }

    private var activeVehicleProfileDefaultReferenceConsumption: Double {
        activeVehicleProfileDefaultReferenceConsumption(for: activeVehicleProfile.profile)
    }

    private var activeVehicleProfileManualReferenceConsumption: Double {
        manualReferenceConsumption(for: activeVehicleProfile.profile)
    }

    private func activeVehicleProfileDefaultReferenceConsumption(for profile: VehicleProfile) -> Double {
        guard profile.kind == .custom else {
            return defaultReferenceConsumptionKWhPer100Km
        }

        let usableBatteryKWh = positiveFinite(
            profile.usableBatteryKWh,
            fallback: VehicleProfileResolver.defaultCustomUsableBatteryCapacityKWh
        )
        let wltpRangeKm = positiveFinite(
            profile.wltpRangeKm,
            fallback: VehicleProfileResolver.defaultCustomWLTPRangeKm
        )
        let modelWLTPRangeKm = degradedModelWLTPRangeKm(for: profile, nominalWLTPRangeKm: wltpRangeKm)
        return (usableBatteryKWh / modelWLTPRangeKm * 100) * 1.04
    }

    private func manualReferenceConsumption(for profile: VehicleProfile) -> Double {
        let defaultValue = activeVehicleProfileDefaultReferenceConsumption(for: profile)

        guard profile.kind == .custom else {
            return clampedFinite(
                referenceConsumption,
                in: 9.5...20,
                fallback: defaultValue
            )
        }

        guard let overrideValue = referenceConsumptionOverridesByProfileID[profile.id] else {
            return defaultValue
        }

        return clampedFinite(
            overrideValue,
            in: 9.5...20,
            fallback: defaultValue
        )
    }

    private func setManualReferenceConsumption(_ value: Double, for profile: VehicleProfile) {
        let clampedValue = clampedFinite(
            value,
            in: 9.5...20,
            fallback: activeVehicleProfileDefaultReferenceConsumption(for: profile)
        )

        if profile.kind == .custom {
            var overrides = referenceConsumptionOverridesByProfileID
            overrides[profile.id] = clampedValue
            referenceConsumptionOverridesByProfileID = overrides
        } else {
            referenceConsumption = clampedValue
        }
    }

    private func resetManualReferenceConsumptionForActiveProfile() {
        if activeVehicleProfile.profile.kind == .custom {
            var overrides = referenceConsumptionOverridesByProfileID
            overrides.removeValue(forKey: activeVehicleProfile.profile.id)
            referenceConsumptionOverridesByProfileID = overrides
        } else {
            referenceConsumption = defaultReferenceConsumptionKWhPer100Km
        }
    }

    private var referenceConsumptionOverridesByProfileID: [String: Double] {
        get {
            guard referenceConsumptionOverridesByProfileData.isEmpty == false,
                  let overrides = try? JSONDecoder().decode(
                    [String: Double].self,
                    from: referenceConsumptionOverridesByProfileData
                  ) else {
                return [:]
            }

            return overrides
        }
        nonmutating set {
            referenceConsumptionOverridesByProfileData = (try? JSONEncoder().encode(newValue)) ?? Data()
        }
    }

    private func motorwaySpeed(for profile: VehicleProfile) -> Double {
        let fallback = MiniConsumptionDefaults.normalizedMotorwaySpeed(motorwaySpeed)
        guard profile.kind == .custom,
              let overrideValue = motorwaySpeedOverridesByProfileID[profile.id] else {
            return fallback
        }

        return MiniConsumptionDefaults.normalizedMotorwaySpeed(overrideValue)
    }

    private func setMotorwaySpeed(_ value: Double, for profile: VehicleProfile) {
        let normalizedValue = MiniConsumptionDefaults.normalizedMotorwaySpeed(value)

        if profile.kind == .custom {
            var overrides = motorwaySpeedOverridesByProfileID
            overrides[profile.id] = normalizedValue
            motorwaySpeedOverridesByProfileID = overrides
        } else {
            motorwaySpeed = normalizedValue
        }
    }

    private func setWindCondition(_ value: WindCondition, now: Date = Date(), defaults: UserDefaults = .standard) {
        windCondition = value
        if value == .normal {
            defaults.removeObject(forKey: windConditionSelectedAtKey)
        } else {
            defaults.set(now.timeIntervalSince1970, forKey: windConditionSelectedAtKey)
        }
    }

    private func expirePersistedWindConditionIfNeeded(defaults: UserDefaults = .standard, now: Date = Date()) {
        MiniConsumptionInitialSetup.expireWindConditionIfNeeded(defaults: defaults, now: now)
        if let storedValue = defaults.string(forKey: "windCondition"),
           let condition = WindCondition(rawValue: storedValue) {
            windCondition = condition
        }
    }

    private func normalizeTrailerWeightIfNeeded() {
        let normalizedWeightKg = MiniConsumptionDefaults.normalizedTrailerWeightKg(trailerWeightKg)
        if normalizedWeightKg != trailerWeightKg {
            trailerWeightKg = normalizedWeightKg
        }
    }

    private func airConditioningMode(for profile: VehicleProfile) -> AirConditioningMode {
        guard profile.kind == .custom,
              let rawValue = airConditioningModeOverridesByProfileID[profile.id],
              let overrideValue = AirConditioningMode(rawValue: rawValue) else {
            return airConditioningMode
        }

        return overrideValue
    }

    private func setAirConditioningMode(_ value: AirConditioningMode, for profile: VehicleProfile) {
        if profile.kind == .custom {
            var overrides = airConditioningModeOverridesByProfileID
            overrides[profile.id] = value.rawValue
            airConditioningModeOverridesByProfileID = overrides
        } else {
            airConditioningMode = value
        }
    }

    private func selectedTyreSet(for profile: VehicleProfile) -> TyreSet {
        guard profile.kind == .custom,
              let rawValue = selectedTyreSetOverridesByProfileID[profile.id],
              let overrideValue = TyreSet(rawValue: rawValue) else {
            return selectedTyreSet
        }

        return overrideValue
    }

    private func setSelectedTyreSet(_ value: TyreSet, for profile: VehicleProfile) {
        if profile.kind == .custom {
            var overrides = selectedTyreSetOverridesByProfileID
            overrides[profile.id] = value.rawValue
            selectedTyreSetOverridesByProfileID = overrides
        } else {
            selectedTyreSet = value
            winterTyres = value == .winter
        }
    }

    private func summerTyreClass(for profile: VehicleProfile) -> RollingResistanceClass {
        guard profile.kind == .custom,
              let rawValue = summerTyreClassOverridesByProfileID[profile.id],
              let overrideValue = RollingResistanceClass(rawValue: rawValue) else {
            return summerTyreClass
        }

        return overrideValue
    }

    private func setSummerTyreClass(_ value: RollingResistanceClass, for profile: VehicleProfile) {
        if profile.kind == .custom {
            var overrides = summerTyreClassOverridesByProfileID
            overrides[profile.id] = value.rawValue
            summerTyreClassOverridesByProfileID = overrides
        } else {
            summerTyreClass = value
        }
    }

    private func winterTyreClass(for profile: VehicleProfile) -> RollingResistanceClass {
        guard profile.kind == .custom,
              let rawValue = winterTyreClassOverridesByProfileID[profile.id],
              let overrideValue = RollingResistanceClass(rawValue: rawValue) else {
            return winterTyreClass
        }

        return overrideValue
    }

    private func setWinterTyreClass(_ value: RollingResistanceClass, for profile: VehicleProfile) {
        if profile.kind == .custom {
            var overrides = winterTyreClassOverridesByProfileID
            overrides[profile.id] = value.rawValue
            winterTyreClassOverridesByProfileID = overrides
        } else {
            winterTyreClass = value
        }
    }

    private func setRollingResistanceClass(_ value: RollingResistanceClass, for profile: VehicleProfile) {
        switch selectedTyreSet(for: profile) {
        case .summer:
            setSummerTyreClass(value, for: profile)
        case .winter:
            setWinterTyreClass(value, for: profile)
        }

        if profile.kind != .custom {
            rollingResistanceClass = value
        }
    }

    private func normalMinimumChargingPercent(for profile: VehicleProfile) -> Double {
        guard profile.kind == .custom,
              let overrideValue = normalMinimumChargingPercentOverridesByProfileID[profile.id] else {
            return clampedFinite(
                normalMinimumChargingPercent,
                in: ChargingWindow.minimumBounds,
                fallback: ChargingWindow.defaultMinimumPercent
            )
        }

        return clampedFinite(
            overrideValue,
            in: ChargingWindow.minimumBounds,
            fallback: ChargingWindow.defaultMinimumPercent
        )
    }

    private func setNormalMinimumChargingPercent(_ value: Double, for profile: VehicleProfile) {
        let clampedValue = clampedFinite(
            value,
            in: ChargingWindow.minimumBounds,
            fallback: ChargingWindow.defaultMinimumPercent
        )

        if profile.kind == .custom {
            var overrides = normalMinimumChargingPercentOverridesByProfileID
            overrides[profile.id] = clampedValue
            normalMinimumChargingPercentOverridesByProfileID = overrides
        } else {
            normalMinimumChargingPercent = clampedValue
        }

        resetTransientAlternativeTripPlanSelection()
    }

    private func normalFastChargeTargetPercent(for profile: VehicleProfile) -> Double {
        guard profile.kind == .custom,
              let overrideValue = normalFastChargeTargetPercentOverridesByProfileID[profile.id] else {
            return clampedFinite(
                normalFastChargeTargetPercent,
                in: ChargingWindow.targetBounds,
                fallback: ChargingWindow.defaultTargetPercent
            )
        }

        return clampedFinite(
            overrideValue,
            in: ChargingWindow.targetBounds,
            fallback: ChargingWindow.defaultTargetPercent
        )
    }

    private func setNormalFastChargeTargetPercent(_ value: Double, for profile: VehicleProfile) {
        let clampedValue = clampedFinite(
            value,
            in: ChargingWindow.targetBounds,
            fallback: ChargingWindow.defaultTargetPercent
        )

        if profile.kind == .custom {
            var overrides = normalFastChargeTargetPercentOverridesByProfileID
            overrides[profile.id] = clampedValue
            normalFastChargeTargetPercentOverridesByProfileID = overrides
        } else {
            normalFastChargeTargetPercent = clampedValue
        }

        resetTransientAlternativeTripPlanSelection()
    }

    private var motorwaySpeedOverridesByProfileID: [String: Double] {
        get { decodedProfileOverrides(from: motorwaySpeedOverridesByProfileData) }
        nonmutating set { motorwaySpeedOverridesByProfileData = encodedProfileOverrides(newValue) }
    }

    private var airConditioningModeOverridesByProfileID: [String: String] {
        get { decodedProfileOverrides(from: airConditioningModeOverridesByProfileData) }
        nonmutating set { airConditioningModeOverridesByProfileData = encodedProfileOverrides(newValue) }
    }

    private var selectedTyreSetOverridesByProfileID: [String: String] {
        get { decodedProfileOverrides(from: selectedTyreSetOverridesByProfileData) }
        nonmutating set { selectedTyreSetOverridesByProfileData = encodedProfileOverrides(newValue) }
    }

    private var summerTyreClassOverridesByProfileID: [String: String] {
        get { decodedProfileOverrides(from: summerTyreClassOverridesByProfileData) }
        nonmutating set { summerTyreClassOverridesByProfileData = encodedProfileOverrides(newValue) }
    }

    private var winterTyreClassOverridesByProfileID: [String: String] {
        get { decodedProfileOverrides(from: winterTyreClassOverridesByProfileData) }
        nonmutating set { winterTyreClassOverridesByProfileData = encodedProfileOverrides(newValue) }
    }

    private var normalMinimumChargingPercentOverridesByProfileID: [String: Double] {
        get { decodedProfileOverrides(from: normalMinimumChargingPercentOverridesByProfileData) }
        nonmutating set { normalMinimumChargingPercentOverridesByProfileData = encodedProfileOverrides(newValue) }
    }

    private var normalFastChargeTargetPercentOverridesByProfileID: [String: Double] {
        get { decodedProfileOverrides(from: normalFastChargeTargetPercentOverridesByProfileData) }
        nonmutating set { normalFastChargeTargetPercentOverridesByProfileData = encodedProfileOverrides(newValue) }
    }

    private func decodedProfileOverrides<Value: Decodable>(from data: Data) -> [String: Value] {
        guard data.isEmpty == false,
              let overrides = try? JSONDecoder().decode([String: Value].self, from: data) else {
            return [:]
        }

        return overrides
    }

    private func encodedProfileOverrides<Value: Encodable>(_ overrides: [String: Value]) -> Data {
        (try? JSONEncoder().encode(overrides)) ?? Data()
    }

    private func resetAverageChargingSpeedForActiveProfile() {
        if activeVehicleProfile.profile.kind == .custom {
            var overrides = averageChargingSpeedOverridesByProfileID
            overrides.removeValue(forKey: activeVehicleProfile.profile.id)
            averageChargingSpeedOverridesByProfileID = overrides
            resetTransientAlternativeTripPlanSelection()
        } else {
            averageChargingSpeedKW = MiniConsumptionCalculator.defaultAverageChargingSpeedKW(for: activeVehicleProfile.profile)
        }
    }

    private var averageChargingSpeedOverridesByProfileID: [String: Double] {
        get {
            guard averageChargingSpeedOverridesByProfileData.isEmpty == false,
                  let overrides = try? JSONDecoder().decode(
                    [String: Double].self,
                    from: averageChargingSpeedOverridesByProfileData
                  ) else {
                return [:]
            }

            return overrides
        }
        nonmutating set {
            averageChargingSpeedOverridesByProfileData = (try? JSONEncoder().encode(newValue)) ?? Data()
        }
    }

    private var tripChargingSetupMinutesBinding: Binding<Double> {
        Binding(
            get: { clampedFinite(tripChargingSetupMinutes, in: 0...5, fallback: defaultTripChargingSetupMinutes) },
            set: { tripChargingSetupMinutes = clampedFinite($0, in: 0...5, fallback: defaultTripChargingSetupMinutes) }
        )
    }

    private var activeAirConditioningModeBinding: Binding<AirConditioningMode> {
        Binding(
            get: { activeAirConditioningMode },
            set: { setAirConditioningMode($0, for: activeVehicleProfile.profile) }
        )
    }

    private var activeSelectedTyreSetBinding: Binding<TyreSet> {
        Binding(
            get: { activeSelectedTyreSet },
            set: { newValue in
                setSelectedTyreSet(newValue, for: activeVehicleProfile.profile)
                setRollingResistanceClass(activeRollingResistanceClass, for: activeVehicleProfile.profile)
            }
        )
    }

    private var activeRollingResistanceClass: RollingResistanceClass {
        activeSelectedTyreSet == .summer ? activeSummerTyreClass : activeWinterTyreClass
    }

    private var activeRollingResistanceClassBinding: Binding<RollingResistanceClass> {
        Binding(
            get: { activeRollingResistanceClass },
            set: { newValue in
                setRollingResistanceClass(newValue, for: activeVehicleProfile.profile)
            }
        )
    }

    private var welcomePopupBinding: Binding<Bool> {
        Binding(
            get: { !hasSeenWelcomePopup },
            set: { _ in }
        )
    }

    private var deleteVehicleProfileConfirmationBinding: Binding<Bool> {
        Binding(
            get: { pendingDeletedVehicleProfile != nil },
            set: { isPresented in
                if !isPresented {
                    pendingDeletedVehicleProfile = nil
                }
            }
        )
    }

    var body: some View {
        lifecycleObservers(for: alertPresenters(for: sheetPresenters(for: appTabs)))
            .background(WatchRangeSnapshotPublisher(snapshot: watchRangeStateSnapshot))
    }

    private var appTabs: some View {
        TabView(selection: $selectedAppTab) {
            NavigationStack {
                rangeTab
            }
            .tabItem {
                Label("Range", systemImage: "gauge.with.dots.needle.bottom.50percent")
            }
            .tag(AppTab.range)

            NavigationStack {
                tripTab
            }
            .tabItem {
                Label("Trip", systemImage: "map")
            }
            .tag(AppTab.trip)

            NavigationStack {
                settingsTab
            }
            .tabItem {
                Label("Settings", systemImage: "gearshape")
            }
            .tag(AppTab.settings)
        }
    }

    private func sheetPresenters<Content: View>(for content: Content) -> some View {
        content
        .sheet(item: $csvExportFile) { exportFile in
            ActivityView(activityItems: [exportFile.url])
        }
        .sheet(isPresented: $isTripDataEditorPresented, onDismiss: reloadTripDataAfterEditing) {
            tripDataEditorSheet
        }
        .sheet(isPresented: $isAboutAppGuidePresented) {
            AboutAppGuideView()
        }
        .sheet(isPresented: $isQuickTripSheetPresented) {
            quickTripSheet
        }
        .sheet(isPresented: $isTripChargingWindowAdjustmentPresented) {
            tripChargingWindowAdjustmentSheet
        }
        .sheet(isPresented: $isTripArrivalReserveAdjustmentPresented) {
            tripArrivalReserveAdjustmentSheet
        }
        .sheet(isPresented: $isTripAssumptionsEditorPresented) {
            tripAssumptionsEditorSheet
        }
        .sheet(isPresented: $isSaveDestinationSheetPresented) {
            saveDestinationSheet
        }
        .sheet(item: $profileEditorMode) { mode in
            vehicleProfileEditorSheet(mode: mode)
        }
        .sheet(isPresented: welcomePopupBinding) {
            WelcomePopupView {
                hasSeenWelcomePopup = true
            }
            .interactiveDismissDisabled()
        }
    }

    private func alertPresenters<Content: View>(for content: Content) -> some View {
        content
        .modifier(
            OneTimeInfoDialogPresenter(
                isLogActualConsumptionInfoPresented: $isLogActualConsumptionInfoPresented,
                isTripPlanningInputInfoPresented: $isTripPlanningInputInfoPresented,
                isCustomEVModeInfoPresented: $isCustomEVModeInfoPresented,
                onAcknowledgeLogActualConsumption: {
                    hasSeenLogActualConsumptionInfo = true
                    presentTripOutcomeCard()
                },
                onAcknowledgeTripPlanningInput: {
                    hasSeenTripPlanningInputInfo = true
                    DispatchQueue.main.async {
                        isTripAssistantDescriptionFocused = true
                    }
                },
                onContinueCustomEVMode: {
                    hasSeenCustomEVModeInfo = true
                },
                onCancelCustomEVMode: {
                    selectBuiltInMiniVehicleProfile()
                }
            )
        )
        .alert("Reset all settings to defaults?", isPresented: $isResetAllSettingsConfirmationPresented) {
            Button("Cancel", role: .cancel) {}
            Button("Reset to app defaults", role: .destructive) {
                resetAllSettingsToDefaults()
            }
        } message: {
            Text("This restores adjustable settings to app defaults. Trip logs and saved trip outcomes are not deleted.")
        }
        .alert("Clear calibration trip data?", isPresented: $isDeleteAllTripDataConfirmationPresented) {
            Button("Cancel", role: .cancel) {}
            Button("Clear data", role: .destructive) {
                deleteAllTripData()
            }
        } message: {
            Text("This deletes logged trips used for continuous calibration.")
        }
        .alert("Delete profile?", isPresented: deleteVehicleProfileConfirmationBinding) {
            Button("Cancel", role: .cancel) {
                pendingDeletedVehicleProfile = nil
            }
            Button("Delete", role: .destructive) {
                deletePendingVehicleProfile()
            }
        } message: {
            Text("This deletes the custom profile. Mini Cooper SE will remain available.")
        }
    }

    private func lifecycleObservers<Content: View>(for content: Content) -> some View {
        content
        .onAppear {
            customVehicleProfiles = VehicleProfileStore.loadCustomProfiles()
            if selectedVehicleProfileID == VehicleProfileResolver.builtInMiniProfileID
                || customVehicleProfiles.contains(where: { $0.id == selectedVehicleProfileID }) == false {
                batteryDegradationPercent = miniBatteryDegradationPercent
            }
            migrateTyreSettingsIfNeeded()
            migrateLegacyCustomEVProfileIfNeeded()
            reconcileSelectedVehicleProfile()
            expirePersistedWindConditionIfNeeded()
            normalizeTrailerWeightIfNeeded()
            roadTypeProfile = roadTypeProfile
            roadSurface = roadSurface.segmentedEquivalent
            publishWatchRangeStateSnapshot()
        }
        .onChange(of: displayUnits) {
            resetTripOutcomeInput()
        }
        .onChange(of: tripEstimateDistance) {
            resetTransientAlternativeTripPlanSelection()
        }
        .onChange(of: tripEstimateStartBatteryPercent) {
            resetTransientAlternativeTripPlanSelection()
        }
        .onChange(of: tripEstimateTemperature) {
            resetTransientAlternativeTripPlanSelection()
        }
        .onChange(of: tripEstimateRoadTypeProfile) {
            resetTransientAlternativeTripPlanSelection()
        }
        .onChange(of: tripEstimateMotorwaySpeed) {
            resetTransientAlternativeTripPlanSelection()
        }
        .onChange(of: tripEstimateRoadSurface) {
            resetTransientAlternativeTripPlanSelection()
        }
        .onChange(of: tripEstimateWindCondition) {
            resetTransientAlternativeTripPlanSelection()
        }
        .onChange(of: tripEstimatePlanningMode) {
            resetTransientAlternativeTripPlanSelection()
        }
        .onChange(of: tripEstimateArrivalBatteryTargetPercent) {
            resetTransientAlternativeTripPlanSelection()
        }
        .onChange(of: normalMinimumChargingPercent) {
            resetTransientAlternativeTripPlanSelection()
        }
        .onChange(of: normalFastChargeTargetPercent) {
            resetTransientAlternativeTripPlanSelection()
        }
        .onChange(of: averageChargingSpeedKW) {
            resetTransientAlternativeTripPlanSelection()
        }
        .onChange(of: tripChargingSetupMinutes) {
            resetTransientAlternativeTripPlanSelection()
        }
        .onChange(of: batteryDegradationPercent) {
            persistActiveVehicleProfileBatteryDegradation()
            resetTransientAlternativeTripPlanSelection()
        }
        .onChange(of: vehicleProfileResolverInput) {
            migrateLegacyCustomEVProfileIfNeeded()
            reconcileSelectedVehicleProfile()
        }
    }

    private var rangeTab: some View {
        ZStack {
            ZStack(alignment: .topTrailing) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12, pinnedViews: [.sectionHeaders]) {
                        pageHeader(title: "Range")
                            .padding(.horizontal)
                            .padding(.top, 12)

                        Section {
                            VStack(alignment: .leading, spacing: 12) {
                                tripConditionsCard
                                tripOutcomeEntry
                            }
                            .padding(.horizontal)
                            .padding(.top, 6)
                            .padding(.bottom)
                        } header: {
                            rangeCard
                                .padding(.horizontal)
                                .padding(.bottom, 6)
                                .background(Color(.systemGroupedBackground))
                                .overlay(alignment: .bottom) {
                                    LinearGradient(
                                        colors: [
                                            Color(.systemGroupedBackground),
                                            Color(.systemGroupedBackground).opacity(0)
                                        ],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                    .frame(height: 18)
                                    .offset(y: 18)
                                    .allowsHitTesting(false)
                                }
                                .zIndex(1)
                        }
                    }
                }

                Text("RangePilot")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(.thinMaterial.opacity(0.55), in: Capsule())
                    .padding(.top, 14)
                    .padding(.trailing)
                    .accessibilityHidden(true)
            }
            .background(Color(.systemGroupedBackground))
            .toolbar(.hidden, for: .navigationBar)

            if isTripOutcomeCardPresented {
                tripOutcomeOverlay
            }
        }
    }

    private var tripTab: some View {
        mainTab(title: "Trip") {
            describeTripCard
            if hasTripRoutePlanningResult {
                tripResultCard
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .onAppear {
            refreshTripEstimateAssumptionsIfNeeded()
        }
    }

    private var quickTripSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    card {
                        VStack(alignment: .leading, spacing: 16) {
                            sliderSection(
                                title: "Distance",
                                value: displayedQuickTripDistanceBinding,
                                range: displayedTripDistanceRange,
                                step: 1,
                                displayValue: displayUnits.formattedDistance(normalizedQuickTripDistance),
                                showsPrecisionButtons: true
                            )

                            Divider()

                            QuickTripChargingSummaryView(
                                presentation: quickTripChargingPresentation,
                                selectedPlan: selectedQuickTripChargingOptionPlan
                            )

                            Divider()

                            resultRow(
                                title: "Between charging stops",
                                value: displayUnits.formattedDistance(quickTripChargingLegRangeKm)
                            )

                            DisclosureGroup(isExpanded: $isQuickTripChargingAssumptionsExpanded) {
                                VStack(alignment: .leading, spacing: 16) {
                                    sliderSection(
                                        title: "Normal minimum before charging",
                                        value: normalMinimumChargingPercentBinding,
                                        range: ChargingWindow.minimumBounds,
                                        step: 1,
                                        displayValue: "\(rounded(normalMinimumChargingPercentBinding.wrappedValue))%"
                                    )

                                    sliderSection(
                                        title: "Normal fast-charge target",
                                        value: normalFastChargeTargetPercentBinding,
                                        range: ChargingWindow.targetBounds,
                                        step: 1,
                                        displayValue: "\(rounded(normalFastChargeTargetPercentBinding.wrappedValue))%"
                                    )
                                }
                                .padding(.top, 8)
                            } label: {
                                Text("Charging assumptions")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                            }
                            .tint(.secondary)
                        }
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Quick trip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        isQuickTripSheetPresented = false
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var tripAssumptionsEditorSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    card {
                        VStack(alignment: .leading, spacing: 16) {
                            Picker("Driving mode", selection: $draftTripAssumptionsRoadTypeProfile) {
                                ForEach(RoadTypeProfile.allCases) { profile in
                                    Text(profile.label).tag(profile)
                                }
                            }
                            .pickerStyle(.segmented)

                            sliderSection(
                                title: "Starting battery",
                                value: draftTripAssumptionsStartBatteryPercentBinding,
                                range: 10...100,
                                step: 1,
                                displayValue: "\(rounded(draftTripAssumptionsStartBatteryPercentBinding.wrappedValue))%"
                            )

                            sliderSection(
                                title: "Arrival battery target",
                                value: draftTripAssumptionsArrivalBatteryTargetPercentBinding,
                                range: ChargingWindow.arrivalBatteryTargetBounds,
                                step: 1,
                                displayValue: "\(rounded(draftTripAssumptionsArrivalBatteryTargetPercentBinding.wrappedValue))%"
                            )

                            sliderSection(
                                title: "Outdoor temperature",
                                value: displayedDraftTripAssumptionsTemperatureBinding,
                                range: displayedTemperatureRange,
                                step: 1,
                                displayValue: temperatureUnits.formattedTemperature(draftTripAssumptionsTemperature)
                            )

                            sliderSection(
                                title: "Motorway speed",
                                value: displayedDraftTripAssumptionsMotorwaySpeedBinding,
                                range: displayedMotorwaySpeedRange,
                                step: 1,
                                displayValue: formattedMotorwaySpeed(draftTripAssumptionsMotorwaySpeed)
                            )
                            .disabled(draftTripAssumptionsRoadTypeProfile.motorwaySpeedScalingFactor == 0)
                            .opacity(draftTripAssumptionsRoadTypeProfile.motorwaySpeedScalingFactor == 0 ? 0.45 : 1)

                            Picker("Road surface", selection: $draftTripAssumptionsRoadSurface) {
                                ForEach(RoadSurface.segmentedCases) { surface in
                                    Text(surface.label).tag(surface)
                                }
                            }
                            .pickerStyle(.segmented)

                            Picker("Wind", selection: $draftTripAssumptionsWindCondition) {
                                ForEach(WindCondition.rangeOrderedCases) { wind in
                                    Text(wind.label).tag(wind)
                                }
                            }
                            .pickerStyle(.segmented)
                        }
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Trip assumptions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        cancelTripAssumptionsEditor()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        applyTripAssumptionsEditor()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var settingsTab: some View {
        ScrollViewReader { proxy in
            mainTab(title: "Settings") {
                aboutAppButton
                vehicleProfileCard
                    .id(SettingsScrollTarget.vehicleProfileCard)
                unitsCard
                chargingSettingsCard
                calibrationCard
                dataCard
                resetAllSettingsCard
            }
            .onAppear {
                scrollToVehicleProfileCardIfNeeded(using: proxy)
            }
            .onChange(of: selectedAppTab) {
                scrollToVehicleProfileCardIfNeeded(using: proxy)
            }
            .onChange(of: shouldScrollToVehicleProfileCard) {
                scrollToVehicleProfileCardIfNeeded(using: proxy)
            }
        }
    }

    private func mainTab<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        ZStack(alignment: .topTrailing) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    pageHeader(title: title)
                    content()
                }
                .padding(.horizontal)
                .padding(.top, 12)
                .padding(.bottom)
            }

            Text("RangePilot")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(.thinMaterial.opacity(0.55), in: Capsule())
                .padding(.top, 14)
                .padding(.trailing)
                .accessibilityHidden(true)
        }
        .background(Color(.systemGroupedBackground))
        .toolbar(.hidden, for: .navigationBar)
    }

    private func pageHeader(title: String) -> some View {
        Text(title)
            .font(.system(size: 28, weight: .semibold, design: .default))
            .foregroundStyle(.primary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func openVehicleProfileSettings() {
        shouldScrollToVehicleProfileCard = true
        selectedAppTab = .settings
    }

    private func scrollToVehicleProfileCardIfNeeded(using proxy: ScrollViewProxy) {
        guard shouldScrollToVehicleProfileCard, selectedAppTab == .settings else {
            return
        }

        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 0.25)) {
                proxy.scrollTo(SettingsScrollTarget.vehicleProfileCard, anchor: .top)
            }
            shouldScrollToVehicleProfileCard = false
        }
    }

    @ViewBuilder
    private var rangeCard: some View {
        switch rangeDisplayMode {
        case .gauge:
            rangeGaugeCard
        case .map:
            rangeMapCard
        }
    }

    private var rangeGaugeCard: some View {
        card {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    rangeProfileChip

                    Spacer()

                    rangeDisplayModePicker
                }

                RangeGaugeView(
                    cautiousRangeKm: cautiousRemainingRange.rangeKm,
                    normalRangeKm: normalRemainingRange.rangeKm,
                    optimisticRangeKm: optimisticRemainingRange.rangeKm,
                    expectedKWhPer100km: rangeForecast.finalKWhPer100km,
                    usableBatteryKWh: rangeUsableBatteryKWh,
                    scaleUpperBound: rangeGaugeMaximumKm,
                    wltpReferenceRangeKm: rangeGaugeWLTPReferenceKm,
                    usesAdaptiveTickDensity: isCustomVehicleProfileSelected,
                    displayUnits: displayUnits,
                    batteryPercent: $startBatteryPercent
                )

                Divider()
                    .opacity(0.75)

                VStack(spacing: 8) {
                    resultRow(
                        title: "Expected consumption",
                        value: displayUnits.formattedConsumption(rangeForecast.finalKWhPer100km)
                    )

                    quickTripSummaryRow
                }
            }
        }
    }

    private var rangeMapCard: some View {
        RangeMapView(
            estimatedRangeKm: normalRemainingRange.rangeKm,
            locationProvider: rangeMapLocationProvider,
            autofitRequestID: rangeMapAutofitRequestID,
            minimumFastChargingStopBatteryPercent: activeNormalMinimumChargingPercent,
            showsChargingThresholdCircle: showRangeMapChargingThresholdCircle,
            batteryPercent: $startBatteryPercent,
            onPlanRouteToDestination: { coordinate in
                planTripToSelectedMapCoordinate(coordinate)
            }
        )
        .frame(maxWidth: .infinity)
        .aspectRatio(1, contentMode: .fit)
        .overlay(alignment: .topLeading) {
            rangeProfileChip
                .padding(12)
        }
        .overlay(alignment: .topTrailing) {
            rangeDisplayModePicker
                .padding(12)
        }
        .overlay(alignment: .bottomTrailing) {
            rangeRecenterButton
                .padding(12)
        }
        .overlay(alignment: .bottomLeading) {
            rangeChargingThresholdToggle
                .padding(12)
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var rangeDisplayModePicker: some View {
        Picker("Range display mode", selection: $rangeDisplayMode) {
            ForEach(RangeDisplayMode.allCases) { mode in
                Text(mode.label).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .frame(width: 146)
    }

    private var rangeProfileChip: some View {
        Button {
            openVehicleProfileSettings()
        } label: {
            HStack(spacing: 5) {
                Text(rangeVehicleProfileSummaryText)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 106, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: 140, alignment: .leading)
            .background(.thinMaterial, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Vehicle profile")
        .accessibilityValue(rangeVehicleProfileSummaryText)
        .accessibilityHint("Opens vehicle profile settings")
    }

    private var rangeRecenterButton: some View {
        Button {
            rangeMapAutofitRequestID += 1
        } label: {
            Image(systemName: "location")
                .font(.headline.weight(.semibold))
                .frame(width: 42, height: 42)
        }
        .buttonStyle(.plain)
        .disabled(rangeMapLocationProvider.coordinate == nil)
        .background(.thinMaterial, in: Circle())
        .foregroundStyle(.tint)
        .opacity(rangeMapLocationProvider.coordinate == nil ? 0.45 : 1)
        .accessibilityLabel("Recenter map")
    }

    private var rangeChargingThresholdToggle: some View {
        Image(systemName: showRangeMapChargingThresholdCircle ? "bolt.circle.fill" : "bolt.slash.circle")
            .font(.headline.weight(.semibold))
            .frame(width: 34, height: 34)
            .contentShape(Circle())
            .gesture(rangeChargingReserveGesture)
            .background(.thinMaterial, in: Circle())
            .foregroundStyle(showRangeMapChargingThresholdCircle ? AnyShapeStyle(.tint) : AnyShapeStyle(Color.secondary.opacity(0.65)))
            .accessibilityLabel("Charging buffer")
            .accessibilityValue(showRangeMapChargingThresholdCircle ? "Shown" : "Hidden")
            .accessibilityHint("Tap to show or hide the charging buffer area. Long press for details.")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction {
                toggleRangeChargingReserve()
            }
            .alert("Charging buffer", isPresented: $isRangeChargingReserveInfoPresented) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(rangeChargingReserveInfoText)
            }
    }

    private var rangeChargingReserveGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.55, maximumDistance: 24)
            .onEnded { _ in
                isRangeChargingReserveInfoPresented = true
            }
            .exclusively(
                before: TapGesture()
                    .onEnded {
                        toggleRangeChargingReserve()
                    }
            )
    }

    private var rangeChargingReserveInfoText: String {
        return """
        Show or hide the charging buffer area.

        Adjust the buffer level in Settings.
        """
    }

    private func toggleRangeChargingReserve() {
        showRangeMapChargingThresholdCircle.toggle()
    }

    private var rangeVehicleProfileSummaryText: String {
        activeVehicleProfile.profile.displayName
    }

    private var experimentalVehicleProfileDetailText: String {
        let usableBatteryText = sanitizedExperimentalUsableBatteryCapacityKWh
            .formatted(.number.precision(.fractionLength(1)))

        return "\(usableBatteryText) kWh • \(displayUnits.formattedDistance(sanitizedExperimentalOfficialWLTPRangeKm)) WLTP"
    }

    private var experimentalTripVehicleProfileRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Vehicle profile")
                .foregroundStyle(.secondary)

            Text("\(activeVehicleProfile.profile.displayName) • \(experimentalTripVehicleProfileDetailText)")
                .fontWeight(.medium)
        }
        .font(.subheadline)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var experimentalTripVehicleProfileDetailText: String {
        let chargingSpeedText = sanitizedExperimentalMaximumDCChargingSpeedKW
            .formatted(.number.precision(.fractionLength(0)))

        return "\(experimentalVehicleProfileDetailText) • \(chargingSpeedText) kW peak DC"
    }

    private var quickTripSummaryRow: some View {
        Button {
            isQuickTripSheetPresented = true
        } label: {
            HStack(spacing: 6) {
                HStack(spacing: 4) {
                    Text("\(displayUnits.formattedDistance(normalizedQuickTripDistance)) trip")
                        .lineLimit(1)

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .foregroundStyle(.secondary)

                Spacer(minLength: 12)

                Text(quickTripSummaryValue)
                    .fontWeight(.medium)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(1)
            }
            .font(.subheadline)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(displayUnits.formattedDistance(normalizedQuickTripDistance)) trip")
        .accessibilityValue(quickTripSummaryValue)
        .accessibilityHint("Opens quick trip estimate")
    }

    private var quickTripSummaryValue: String {
        guard quickTripBatteryPlan.needsCharging else {
            return "~\(rounded(quickTripBatteryPlan.arrivalBatteryPercent))% arrival"
        }

        return "\(quickTripChargingPresentation.chargingStopsText(for: selectedQuickTripChargingOptionPlan)) · \(quickTripChargingPresentation.chargingTimeText(for: selectedQuickTripChargingOptionPlan))"
    }

    private var calibrationCard: some View {
        card(title: "Calibration") {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("Calibration based on logged trips", isOn: $useContinuousCalibration)
                        .font(.subheadline.weight(.semibold))

                    if useContinuousCalibration {
                        Text(continuousCalibrationStatusText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                calibrationSummaryArea

                Divider()

                VStack(spacing: 12) {
                    sliderSection(
                        title: "Manual overall calibration",
                        value: displayedReferenceConsumptionBinding,
                        range: referenceConsumptionDisplayRange,
                        step: 0.1,
                        displayValue: displayUnits.formattedConsumption(activeVehicleProfileManualReferenceConsumption),
                        isVisuallyDisabled: isManualReferenceInactive
                    )
                    .disabled(isManualReferenceInactive)

                    Text("Lower values increase estimated range. Higher values reduce estimated range.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    HStack {
                        Text("Default: \(displayUnits.formattedConsumption(activeVehicleProfileDefaultReferenceConsumption))")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Spacer()

                        Button("Reset to default") {
                            resetManualReferenceConsumptionForActiveProfile()
                        }
                        .buttonStyle(.bordered)
                        .disabled(abs(activeVehicleProfileManualReferenceConsumption - activeVehicleProfileDefaultReferenceConsumption) < 0.001 || isManualReferenceInactive)
                    }
                }
                .opacity(isManualReferenceInactive ? 0.55 : 1)
            }
        }
    }

    private var calibrationSummaryArea: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(calibrationSummaryTitle)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)

            Text(calibrationSummaryDetail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.tertiarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var vehicleProfileCard: some View {
        card(title: "Vehicle profile") {
            VStack(alignment: .leading, spacing: 12) {
                vehicleProfileSelectorRow

                if isCustomVehicleProfileSelected {
                    customVehicleProfileEditAction
                }

                Divider()

                if isCustomVehicleProfileSelected {
                    customVehicleProfileDetails
                } else {
                    miniVehicleProfileDetails
                }

                batteryDegradationControl
            }
        }
    }

    private var vehicleProfileSelectorRow: some View {
        Menu {
            Button {
                selectBuiltInMiniVehicleProfile()
            } label: {
                menuProfileLabel(
                    title: VehicleProfileResolver.builtInMiniName,
                    isSelected: activeVehicleProfile.profile.id == VehicleProfileResolver.builtInMiniProfileID
                )
            }

            ForEach(customVehicleProfiles) { profile in
                Button {
                    selectCustomVehicleProfile(profile)
                } label: {
                    menuProfileLabel(
                        title: profile.displayName,
                        isSelected: activeVehicleProfile.profile.id == profile.id
                    )
                }
            }

            Divider()

            Button {
                presentCreateVehicleProfileSheet()
            } label: {
                Text("Add new profile...")
            }
        } label: {
            HStack(spacing: 4) {
                Text(selectedVehicleProfileDisplayName)
                    .font(.subheadline.weight(.medium))
                    .multilineTextAlignment(.leading)

                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2.weight(.semibold))
            }
            .foregroundStyle(.blue)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Vehicle profile")
        .accessibilityValue(selectedVehicleProfileDisplayName)
    }

    private func menuProfileLabel(title: String, isSelected: Bool) -> some View {
        HStack {
            Text(title)

            if isSelected {
                Image(systemName: "checkmark")
            }
        }
    }

    private var selectedVehicleProfileDisplayName: String {
        activeVehicleProfile.profile.displayName
    }

    private var customVehicleProfileEditAction: some View {
        Button("Edit") {
            presentEditVehicleProfileSheet(activeVehicleProfile.profile)
        }
        .font(.caption)
        .foregroundStyle(.blue)
        .buttonStyle(.plain)
    }

    private var miniVehicleProfileDetails: some View {
        VStack(alignment: .leading, spacing: 8) {
            secondaryResultRow(
                title: "Details",
                value: vehicleProfileDetailText(
                    usableBatteryKWh: MiniConsumptionCalculator.nominalUsableBatteryKWh,
                    wltpRangeKm: VehicleProfileResolver.builtInMiniWLTPRangeKm,
                    peakDCChargingKW: VehicleProfileResolver.builtInMiniPeakDCChargingKW
                )
            )
        }
    }

    private var customVehicleProfileDetails: some View {
        VStack(alignment: .leading, spacing: 8) {
            secondaryResultRow(
                title: "Details",
                value: vehicleProfileDetailText(
                    usableBatteryKWh: activeVehicleProfile.profile.usableBatteryKWh,
                    wltpRangeKm: activeVehicleProfile.profile.wltpRangeKm,
                    peakDCChargingKW: activeVehicleProfile.profile.peakDCChargingKW
                )
            )

            Text("Custom EV estimates are approximate at first. RangePilot was originally modelled on the MINI Cooper SE, but trip logging can calibrate estimates to your vehicle after at least three logged trips in a driving mode.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func vehicleProfileDetailText(
        usableBatteryKWh: Double,
        wltpRangeKm: Double,
        peakDCChargingKW: Double
    ) -> String {
        let usableBatteryText = usableBatteryKWh
            .formatted(.number.precision(.fractionLength(1)))
        let peakChargingText = peakDCChargingKW
            .formatted(.number.precision(.fractionLength(0)))

        return "\(usableBatteryText) kWh • \(displayUnits.formattedDistance(wltpRangeKm)) WLTP • \(peakChargingText) kW peak DC"
    }

    private func vehicleProfileEditorSheet(mode: VehicleProfileEditorMode) -> some View {
        NavigationStack {
            Form {
                if case .create = mode {
                    Section {
                        Picker("Vehicle brand", selection: vehicleProfileTemplateBrandSelectionBinding) {
                            Text("Custom Profile").tag(VehicleProfileTemplate.customProfileID)

                            ForEach(VehicleProfileTemplate.brands, id: \.self) { brand in
                                Text(brand).tag(brand)
                            }
                        }
                        .pickerStyle(.menu)

                        if selectedVehicleProfileTemplateBrand != VehicleProfileTemplate.customProfileID {
                            Picker("Model", selection: vehicleProfileTemplateSelectionBinding) {
                                ForEach(selectedVehicleProfileBrandTemplates) { template in
                                    Text(template.modelName).tag(template.id)
                                }
                            }
                            .pickerStyle(.menu)
                        }

                        Text("Can't find your exact vehicle? Choose the closest model and adjust the values as needed.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Section {
                    TextField("Profile name", text: $profileEditorDraft.displayName)
                        .textInputAutocapitalization(.words)

                    profileEditorNumericTextField(
                        label: "Usable battery capacity",
                        text: $profileEditorDraft.usableBatteryKWhText,
                        unit: "kWh",
                        focusedField: .usableBatteryCapacity
                    )

                    profileEditorNumericTextField(
                        label: "Official WLTP range",
                        text: $profileEditorDraft.wltpRangeText,
                        unit: displayUnits.distanceUnitLabel,
                        focusedField: .officialWLTPRange
                    )

                    profileEditorNumericTextField(
                        label: "Peak DC charging speed",
                        text: $profileEditorDraft.peakDCChargingKWText,
                        unit: "kW",
                        focusedField: .peakDCChargingSpeed
                    )
                }

                if case .edit(let profile) = mode {
                    Section {
                        Button("Delete Profile", role: .destructive) {
                            profileEditorMode = nil
                            pendingDeletedVehicleProfile = profile
                        }
                    }
                }
            }
            .navigationTitle(vehicleProfileEditorTitle(for: mode))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        profileEditorMode = nil
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveVehicleProfileEditor(mode: mode)
                    }
                    .disabled(
                        profileEditorDraft.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || profileEditorDraft.canSave(displayUnits: displayUnits) == false
                    )
                }
            }
        }
    }

    private func vehicleProfileEditorTitle(for mode: VehicleProfileEditorMode) -> String {
        switch mode {
        case .create:
            return "Add Profile"
        case .edit:
            return "Edit Profile"
        }
    }

    private var batteryDegradationControl: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Battery degradation")
                    .font(.subheadline.weight(.semibold))

                Spacer()

                Picker("Battery degradation", selection: $batteryDegradationPercent) {
                    ForEach(0...10, id: \.self) { percent in
                        Text("\(percent)%").tag(percent)
                    }
                }
                .pickerStyle(.menu)
            }

            Text("Battery capacity may gradually decrease over time, often around 1–2% per year.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var vehicleCard: some View {
        card(title: "Vehicle") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Battery degradation")
                        .font(.subheadline.weight(.semibold))

                    Spacer()

                    Picker("Battery degradation", selection: $batteryDegradationPercent) {
                        ForEach(0...10, id: \.self) { percent in
                            Text("\(percent)%").tag(percent)
                        }
                    }
                    .pickerStyle(.menu)
                }

                Text("Battery capacity may gradually decrease over time, often around 1–2% per year.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var unitsCard: some View {
        card(title: "Units") {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center, spacing: 12) {
                    Text("Distance and consumption")
                        .font(.subheadline.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Picker("Units", selection: $displayUnits) {
                        Text("km").tag(DisplayUnits.metric)
                        Text("mi").tag(DisplayUnits.imperial)
                    }
                    .pickerStyle(.segmented)
                    .controlSize(.small)
                    .frame(width: 108)
                }

                HStack(alignment: .center, spacing: 12) {
                    Text("Temperature")
                        .font(.subheadline.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Picker("Temperature", selection: $temperatureUnits) {
                        Text("C").tag(TemperatureUnits.celsius)
                        Text("F").tag(TemperatureUnits.fahrenheit)
                    }
                    .pickerStyle(.segmented)
                    .controlSize(.small)
                    .frame(width: 72)
                }

                HStack(alignment: .center, spacing: 12) {
                    Text("Weight unit")
                        .font(.subheadline.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Picker("Weight unit", selection: $weightUnits) {
                        Text("kg").tag(WeightUnits.kilograms)
                        Text("lbs").tag(WeightUnits.pounds)
                    }
                    .pickerStyle(.segmented)
                    .controlSize(.small)
                    .frame(width: 92)
                }
            }
        }
    }

    private var tripConditionsCard: some View {
        RangeConditionsCard(
            roadTypeProfile: $roadTypeProfile,
            displayedTemperature: displayedTemperatureBinding,
            temperatureRange: displayedTemperatureRange,
            temperatureText: temperatureUnits.formattedTemperature(temperature),
            roadSurface: segmentedRoadSurface,
            windCondition: rangeWindConditionBinding,
            isAdditionalSettingsExpanded: $isAdditionalSettingsExpanded,
            motorwaySpeed: motorwaySpeedBinding,
            motorwaySpeedRange: displayedMotorwaySpeedRange,
            motorwaySpeedText: formattedMotorwaySpeed(activeMotorwaySpeed),
            motorwaySpeedDisabled: roadTypeProfile.motorwaySpeedScalingFactor == 0,
            airConditioningMode: activeAirConditioningModeBinding,
            trailerTowModeEnabled: $trailerTowModeEnabled,
            trailerWeightKg: trailerWeightBinding,
            trailerWeightRange: displayedTrailerWeightRange,
            trailerWeightStep: displayedTrailerWeightStep,
            trailerWeightText: trailerWeightText,
            boxyTrailerEnabled: $boxyTrailerEnabled,
            selectedTyreSet: activeSelectedTyreSetBinding,
            rollingResistanceClass: activeRollingResistanceClassBinding,
            onTyreSetChanged: { newValue in
                setSelectedTyreSet(newValue, for: activeVehicleProfile.profile)
                setRollingResistanceClass(activeRollingResistanceClass, for: activeVehicleProfile.profile)
            }
        )
    }

    private var dataCard: some View {
        card(title: "Data", footnote: "Trip history and calibration data.") {
            VStack(spacing: 8) {
                Button {
                    isTripDataEditorPresented = true
                } label: {
                    Label("View logged trips", systemImage: "list.bullet.rectangle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(outcomes.isEmpty)

                Button {
                    exportTripOutcomes()
                } label: {
                    Label("Export trip history", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(outcomes.isEmpty)

                Button(role: .destructive) {
                    isDeleteAllTripDataConfirmationPresented = true
                } label: {
                    Label("Clear calibration data", systemImage: "arrow.counterclockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(outcomes.isEmpty)
            }
        }
    }

    private var resetAllSettingsCard: some View {
        card {
            VStack(alignment: .leading, spacing: 10) {
                Button(role: .destructive) {
                    isResetAllSettingsConfirmationPresented = true
                } label: {
                    Label("Reset all settings to defaults", systemImage: "arrow.counterclockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)

                Text("Trip logs and saved trip outcomes are not deleted.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var chargingSettingsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Fast-charging planning settings")
                .font(.headline)
                .foregroundStyle(.primary)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Preferred low level before charging")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("\(rounded(normalMinimumChargingPercentBinding.wrappedValue))%")
                        .foregroundStyle(.secondary)
                }

                Slider(
                    value: normalMinimumChargingPercentBinding,
                    in: ChargingWindow.minimumBounds,
                    step: 1
                )
                .tint(sliderAccentColor)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Preferred fast-charging target level")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("\(rounded(normalFastChargeTargetPercentBinding.wrappedValue))%")
                        .foregroundStyle(.secondary)
                }

                Slider(
                    value: normalFastChargeTargetPercentBinding,
                    in: ChargingWindow.targetBounds,
                    step: 1
                )
                .tint(sliderAccentColor)
            }

            DisclosureGroup(isExpanded: $isTripAdvancedChargingSettingsExpanded) {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Charging setup time")
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Text("\(rounded(tripChargingSetupMinutesBinding.wrappedValue)) min")
                                .foregroundStyle(.secondary)
                        }

                        Slider(
                            value: tripChargingSetupMinutesBinding,
                            in: 0...5,
                            step: 1
                        )
                        .tint(sliderAccentColor)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Average fast-charging speed")
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                Text("\(rounded(averageChargingSpeedKWBinding.wrappedValue)) kW")
                                    .foregroundStyle(.secondary)
                            }

                            Slider(
                                value: averageChargingSpeedKWBinding,
                                in: MiniConsumptionCalculator.averageChargingSpeedBoundsKW(for: activeVehicleProfile.profile),
                                step: MiniConsumptionCalculator.averageChargingSpeedStepKW
                            )
                            .tint(sliderAccentColor)
                        }

                        Text("Used as the average charging power up to 80%. This should reflect a normal fast-charge session, not the brief peak.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Button("Reset to default") {
                            resetAverageChargingSpeedForActiveProfile()
                        }
                        .buttonStyle(.bordered)
                        .disabled(abs(averageChargingSpeedKWBinding.wrappedValue - activeAverageChargingSpeedDefaultKW) < 0.001)
                    }
                }
                .padding(.top, 8)
            } label: {
                Text("Advanced settings")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
            }
            .tint(.secondary)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var describeTripCard: some View {
        card {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    TripPlanningDescriptionInputView(
                        text: $tripAssistantDescription,
                        isFocused: $isTripAssistantDescriptionFocused,
                        accentColor: sliderAccentColor,
                        showsClearButton: isTripSearchActive,
                        onClear: clearActiveTripSearch,
                        onFocusChanged: presentTripPlanningInputInfoIfNeeded
                    )

                    favoriteDestinationMenu
                        .padding(.leading, 8)
                        .padding(.bottom, 8)
                }
                .frame(minHeight: 88, alignment: .top)
                .background(Color(.tertiarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 6) {
                    Picker("Planning mode", selection: $tripEstimatePlanningMode) {
                        ForEach(PlanningMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Button {
                    interpretTripAssistantDescription()
                } label: {
                    if isTripAssistantInterpreting || isTripAssistantRouteLookupPending {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Label("Estimate charging plan", systemImage: "sparkle.magnifyingglass")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(sliderAccentColor)
                .disabled(isTripAssistantInterpreting || tripAssistantDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                if hasTripEstimate {
                    Button {
                        presentTripAssumptionsEditor()
                    } label: {
                        Label("Adjust trip assumptions", systemImage: "slider.horizontal.3")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                if let tripAssistantMessage {
                    Text(tripAssistantMessage.text(displayUnits: displayUnits))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var favoriteDestinationMenu: some View {
        Menu {
            if savedDestinations.isEmpty {
                Text("No saved destinations")
            } else {
                ForEach(savedDestinations, id: \.menuID) { destination in
                    Button(savedDestinationPickerTitle(for: destination)) {
                        applySavedDestination(destination)
                    }
                }
            }

            Divider()

            Button("Manage favorites...") {
                presentManageFavoriteDestinationsSheet()
            }
        } label: {
            Label("Favorites", systemImage: "star")
                .font(.caption.weight(.medium))
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
    }

    private var saveDestinationSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Destination name")
                        .font(.subheadline.weight(.semibold))

                    TextField("Destination name", text: $savedDestinationName)
                        .textFieldStyle(.roundedBorder)
                }

                if let savedDestinationQuery {
                    informationalRow(
                        title: "Destination",
                        value: savedDestinationQuery
                    )
                }

                if savedDestinations.isEmpty == false {
                    Divider()

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Saved destinations")
                            .font(.subheadline.weight(.semibold))

                        List {
                            ForEach(savedDestinations, id: \.menuID) { destination in
                                HStack {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(destination.name)
                                            .font(.subheadline.weight(.medium))
                                        if destination.destinationQuery != destination.name {
                                            Text(destination.destinationQuery)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }

                                    Spacer()

                                    Button(role: .destructive) {
                                        deleteSavedDestination(destination)
                                    } label: {
                                        Image(systemName: "trash")
                                    }
                                    .buttonStyle(.borderless)
                                    .accessibilityLabel("Delete \(destination.name)")
                                }
                            }
                        }
                        .listStyle(.plain)
                        .frame(minHeight: 120)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding()
            .navigationTitle("Save destination")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isSaveDestinationSheetPresented = false
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveCurrentDestination()
                    }
                    .disabled(savedDestinationQuery == nil)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var tripResultCard: some View {
        card(title: "Route and charging", footnote: "Preview, assumptions, and charging estimate.") {
            VStack(alignment: .leading, spacing: 16) {
#if canImport(MapKit)
                if let tripAssistantRoute,
                   !tripAssistantRoute.destination.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    TripRoutePreviewView(
                        route: tripAssistantRoute,
                        routePolyline: tripAssistantRouteEstimate?.polyline,
                        needsCharging: batteryPlan.needsCharging,
                        selectedPlan: selectedTripChargingOptionPlan,
                        onPlanRouteToCoordinate: { coordinate, destinationLabel in
                            planTripToSelectedMapCoordinate(coordinate, destinationLabel: destinationLabel)
                        },
                        onSearchChargersNearby: { coordinate in
                            Task {
                                await AppleMapsHandoff.openChargingSearch(centeredAt: coordinate)
                            }
                        }
                    )
                }
#endif

                if isCustomVehicleProfileSelected {
                    experimentalTripVehicleProfileRow
                }

                TripChargingSummaryView(
                    presentation: tripChargingPresentation,
                    routeDistanceText: displayUnits.formattedDistance(tripEstimateDistance),
                    selectedPlan: selectedTripChargingOptionPlan,
                    selectedOption: selectedTripChargingOption,
                    selectOption: { selectedTripChargingOption = $0 }
                )

                saveDestinationResultAction

#if canImport(MapKit)
                if let tripAssistantRoute,
                   !tripAssistantRoute.destination.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    tripRouteActionButtons(for: tripAssistantRoute)
                }
#endif
            }
        }
    }

    private var saveDestinationResultAction: some View {
        Button {
            presentSaveDestinationSheet()
        } label: {
            Label("Save destination", systemImage: "star")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    private var tripChargingWindowAdjustmentSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                sliderSection(
                    title: "Normal minimum before charging",
                    value: draftMinimumChargingPercentBinding,
                    range: ChargingWindow.minimumBounds,
                    step: 1,
                    displayValue: "\(rounded(draftMinimumChargingPercentBinding.wrappedValue))%"
                )

                sliderSection(
                    title: "Normal fast-charge target",
                    value: draftFastChargeTargetPercentBinding,
                    range: ChargingWindow.targetBounds,
                    step: 1,
                    displayValue: "\(rounded(draftFastChargeTargetPercentBinding.wrappedValue))%"
                )

                Spacer(minLength: 0)
            }
            .padding()
            .navigationTitle("Between charges")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isTripChargingWindowAdjustmentPresented = false
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Update") {
                        setNormalMinimumChargingPercent(draftMinimumChargingPercent, for: activeVehicleProfile.profile)
                        setNormalFastChargeTargetPercent(draftFastChargeTargetPercent, for: activeVehicleProfile.profile)
                        selectedTripChargingOption = .userSettings
                        isTripChargingWindowAdjustmentPresented = false
                    }
                }
            }
        }
        .presentationDetents([.height(280), .medium])
    }

    private var tripArrivalReserveAdjustmentSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                sliderSection(
                    title: "Arrival battery target",
                    value: draftArrivalBatteryTargetPercentBinding,
                    range: ChargingWindow.arrivalBatteryTargetBounds,
                    step: 1,
                    displayValue: "\(rounded(draftArrivalBatteryTargetPercent))%"
                )

                Spacer(minLength: 0)
            }
            .padding()
            .navigationTitle("Arrival reserve")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isTripArrivalReserveAdjustmentPresented = false
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Update") {
                        tripEstimateArrivalBatteryTargetPercent = draftArrivalBatteryTargetPercent
                        selectedTripChargingOption = .userSettings
                        isTripArrivalReserveAdjustmentPresented = false
                    }
                }
            }
        }
        .presentationDetents([.height(220), .medium])
    }

    private func presentTripChargingWindowAdjustment() {
        draftMinimumChargingPercent = activeNormalMinimumChargingPercent
        draftFastChargeTargetPercent = activeNormalFastChargeTargetPercent
        isTripChargingWindowAdjustmentPresented = true
    }

    private func presentTripArrivalReserveAdjustment() {
        draftArrivalBatteryTargetPercent = tripEstimateArrivalBatteryTargetPercent
        isTripArrivalReserveAdjustmentPresented = true
    }

    private func presentTripAssumptionsEditor() {
        draftTripAssumptionsRoadTypeProfile = tripEstimateRoadTypeProfile
        draftTripAssumptionsArrivalBatteryTargetPercent = tripEstimateArrivalBatteryTargetPercentBinding.wrappedValue
        draftTripAssumptionsStartBatteryPercent = tripEstimateStartBatteryPercentBinding.wrappedValue
        draftTripAssumptionsTemperature = tripEstimateTemperature
        draftTripAssumptionsMotorwaySpeed = tripEstimateMotorwaySpeedBinding.wrappedValue
        draftTripAssumptionsRoadSurface = tripEstimateRoadSurface
        draftTripAssumptionsWindCondition = tripEstimateWindCondition
        isTripAssumptionsEditorPresented = true
    }

    private func cancelTripAssumptionsEditor() {
        isTripAssumptionsEditorPresented = false
    }

    private func applyTripAssumptionsEditor() {
        tripEstimateRoadTypeProfile = draftTripAssumptionsRoadTypeProfile
        tripEstimateArrivalBatteryTargetPercent = draftTripAssumptionsArrivalBatteryTargetPercentBinding.wrappedValue
        tripEstimateStartBatteryPercent = draftTripAssumptionsStartBatteryPercentBinding.wrappedValue
        tripEstimateTemperature = draftTripAssumptionsTemperature
        tripEstimateMotorwaySpeed = draftTripAssumptionsMotorwaySpeedBinding.wrappedValue
        tripEstimateRoadSurface = draftTripAssumptionsRoadSurface
        tripEstimateWindCondition = draftTripAssumptionsWindCondition
        hasTripEstimate = true
        isTripAssumptionsEditorPresented = false
    }

    private func resetTransientAlternativeTripPlanSelection() {
        guard hasTripEstimate, selectedTripChargingOption != .userSettings else {
            return
        }

        selectedTripChargingOption = .userSettings
    }

    private var tripOutcomeEntry: some View {
        Button {
            presentLogActualConsumptionEntry()
        } label: {
            Label("Log trip with these conditions", systemImage: "square.and.pencil")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .tint(sliderAccentColor)
    }

    private var tripOutcomeOverlay: some View {
        ZStack {
            Color.black
                .opacity(0.28)
                .ignoresSafeArea()

            tripOutcomeCard
                .padding(.horizontal, 16)
                .padding(.vertical, 24)
                .frame(maxWidth: 430)
                .transition(.scale(scale: 0.96).combined(with: .opacity))
        }
        .animation(.snappy, value: isTripOutcomeCardPresented)
    }

    private var tripOutcomeCard: some View {
        card(title: "Log actual outcome", footnote: "Save the actual average consumption for a drive using the currently set conditions.") {
            VStack(alignment: .leading, spacing: 12) {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    actualConsumptionPicker
                    actualDistancePicker
                }

                Divider()

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if isCustomVehicleProfileSelected {
                            customEVOutcomeIndicator
                        }

                        loggedTripConditionFields(
                            roadTypeProfile: $outcomeRoadTypeProfile,
                            motorwaySpeed: displayedOutcomeMotorwaySpeedBinding,
                            motorwaySpeedKmh: outcomeMotorwaySpeed,
                            temperature: displayedOutcomeTemperatureBinding,
                            temperatureC: outcomeTemperature,
                            roadSurface: outcomeRoadSurfaceBinding,
                            windCondition: $outcomeWindCondition,
                            rollingResistanceClass: $outcomeRollingResistanceClass
                        )

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Tyre set")
                                .font(.subheadline.weight(.semibold))

                            Picker("Tyre set", selection: $outcomeTyreSet) {
                                ForEach(TyreSet.allCases) { tyreSet in
                                    Text(tyreSet.label).tag(tyreSet as TyreSet)
                                }
                            }
                            .pickerStyle(.segmented)
                            .onChange(of: outcomeTyreSet) { _, newValue in
                                outcomeRollingResistanceClass = newValue == .summer ? activeSummerTyreClass : activeWinterTyreClass
                            }
                        }

                        TextField("Optional note", text: $outcomeNote, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                            .lineLimit(1...4)
                    }
                    .padding(.top, 2)
                    .padding(.bottom, 28)
                }
                .frame(maxHeight: 360)

                HStack {
                    Button("Cancel", role: .cancel) {
                        cancelTripOutcome()
                    }
                    .buttonStyle(.bordered)

                    Spacer()
                    Button("Save") {
                        saveTripOutcome()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(validOutcomeInput == nil)
                }
            }
        }
        .shadow(color: .black.opacity(0.18), radius: 24, y: 10)
    }

    private var customEVOutcomeIndicator: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(activeVehicleProfile.profile.displayName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(sliderAccentColor)

            Text("This outcome will calibrate this profile only.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(sliderAccentColor.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func loggedTripConditionFields(
        roadTypeProfile: Binding<RoadTypeProfile>,
        motorwaySpeed: Binding<Double>,
        motorwaySpeedKmh: Double,
        temperature: Binding<Double>,
        temperatureC: Double,
        roadSurface: Binding<RoadSurface>,
        windCondition: Binding<WindCondition>,
        rollingResistanceClass: Binding<RollingResistanceClass>
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("Route profile", selection: roadTypeProfile) {
                ForEach([RoadTypeProfile.countryside, .cityMix, .motorwayMix, .motorway]) { profile in
                    Text(profile.label).tag(profile)
                }
            }
            .pickerStyle(.segmented)

            sliderSection(
                title: "Motorway speed",
                value: motorwaySpeed,
                range: displayedMotorwaySpeedRange,
                step: 1,
                displayValue: formattedMotorwaySpeed(motorwaySpeedKmh)
            )
            .disabled(roadTypeProfile.wrappedValue.motorwaySpeedScalingFactor == 0)
            .opacity(roadTypeProfile.wrappedValue.motorwaySpeedScalingFactor == 0 ? 0.45 : 1)

            sliderSection(
                title: "Outdoor temperature",
                value: temperature,
                range: displayedTemperatureRange,
                step: 1,
                displayValue: temperatureUnits.formattedTemperature(temperatureC)
            )

            VStack(alignment: .leading, spacing: 8) {
                Text("Road surface condition")
                    .font(.subheadline.weight(.semibold))

                Picker("Road surface condition", selection: roadSurface) {
                    ForEach(RoadSurface.segmentedCases) { surface in
                        Text(surface.label).tag(surface as RoadSurface)
                    }
                }
                .pickerStyle(.segmented)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Wind")
                    .font(.subheadline.weight(.semibold))

                Picker("Wind", selection: windCondition) {
                    ForEach(WindCondition.rangeOrderedCases) { wind in
                        Text(wind.label).tag(wind as WindCondition)
                    }
                }
                .pickerStyle(.segmented)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Rolling resistance")
                    .font(.subheadline.weight(.semibold))

                Picker("Rolling resistance", selection: rollingResistanceClass) {
                    ForEach(RollingResistanceClass.rangeOrderedCases) { tyreClass in
                        Text(tyreClass.label).tag(tyreClass as RollingResistanceClass)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
    }

    private var actualConsumptionPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("Actual average", selection: $outcomeActualConsumptionTenths) {
                ForEach(outcomeConsumptionTenthsRange, id: \.self) { tenths in
                    Text(consumptionText(forTenths: tenths))
                        .tag(tenths)
                }
            }
            .pickerStyle(.wheel)
            .frame(height: 104)
            .clipped()

            Text(actualConsumptionPickerTitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private var actualDistancePicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("Distance", selection: $outcomeDistanceKm) {
                ForEach(outcomeDistanceDisplayRange, id: \.self) { distance in
                    Text("\(distance)")
                        .tag(distance)
                }
            }
            .pickerStyle(.wheel)
            .frame(height: 104)
            .clipped()

            Text(actualDistancePickerTitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private var actualConsumptionPickerTitle: String {
        "Actual average (\(displayUnits.consumptionUnitLabel))"
    }

    private var actualDistancePickerTitle: String {
        "Distance (\(displayUnits.distanceUnitLabel))"
    }

    private var tripDataEditorSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                if outcomes.isEmpty {
                    ContentUnavailableView(
                        "No Trip Data",
                        systemImage: "car.side",
                        description: Text("Recorded trips will appear here after you save trip outcomes.")
                    )
                } else {
                    tripDataEditorHeader

                    List {
                        ForEach(tripDataEditorOutcomes) { outcome in
                            tripDataRow(for: outcome)
                        }
                    }
                    .listStyle(.plain)

                    tripDataEditorActions
                }
            }
            .padding()
            .navigationTitle("Edit trip data")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        isTripDataEditorPresented = false
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .sheet(item: $selectedTripOutcomeForDetails) { outcome in
            tripOutcomeDetailsSheet(for: outcome)
        }
    }

    private var tripDataEditorHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(outcomes.count) recorded \(outcomes.count == 1 ? "trip" : "trips")")
                    .font(.subheadline.weight(.semibold))
                Text(tripDataEditorCalibrationSummaryText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(isSelectingTripData ? "Cancel" : "Select") {
                isSelectingTripData.toggle()
                selectedTripOutcomeIDs.removeAll()
            }
            .buttonStyle(.bordered)
        }
    }

    private var tripDataEditorCalibrationSummaryText: String {
        if isCustomVehicleProfileSelected {
            return "\(continuousCalibrationSummary.validTripCount) eligible for \(activeVehicleProfile.profile.displayName) calibration. Only trips logged with a custom profile are used to improve this forecast."
        }

        return "\(continuousCalibrationSummary.validTripCount) eligible for calibration. Only eligible trips are used to improve the forecast."
    }

    private func tripOutcomeDetailsSheet(for outcome: TripOutcome) -> some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    card(title: "Trip details") {
                        VStack(alignment: .leading, spacing: 14) {
                            resultRow(
                                title: "Date",
                                value: outcome.date.formatted(date: .abbreviated, time: .shortened)
                            )

                            resultRow(
                                title: "Actual consumption",
                                value: tripOutcomeConsumptionText(for: outcome)
                            )

                            resultRow(
                                title: "Calibration",
                                value: tripOutcomeCalibrationEligibilityText(for: outcome)
                            )

                            if outcome.vehicleProfileKind == .customEV {
                                resultRow(
                                    title: "Profile",
                                    value: "Custom profile"
                                )
                            }

                            Divider()

                            loggedTripConditionFields(
                                roadTypeProfile: $draftTripDetailsRoadTypeProfile,
                                motorwaySpeed: displayedDraftTripDetailsMotorwaySpeedBinding,
                                motorwaySpeedKmh: draftTripDetailsMotorwaySpeed,
                                temperature: displayedDraftTripDetailsTemperatureBinding,
                                temperatureC: draftTripDetailsTemperature,
                                roadSurface: draftTripDetailsRoadSurfaceBinding,
                                windCondition: $draftTripDetailsWindCondition,
                                rollingResistanceClass: $draftTripDetailsRollingResistanceClass
                            )

                            if draftTripDetailsDistanceKm != nil {
                                sliderSection(
                                    title: "Distance",
                                    value: displayedDraftTripDetailsDistanceBinding,
                                    range: displayedTripDistanceRange,
                                    step: 1,
                                    displayValue: displayUnits.formattedDistance(draftTripDetailsDistanceKm ?? 0),
                                    showsPrecisionButtons: true
                                )
                            } else {
                                resultRow(title: "Distance", value: "Distance not saved")
                            }

                            TextField("Notes", text: $draftTripDetailsNote, axis: .vertical)
                                .textFieldStyle(.roundedBorder)
                                .lineLimit(1...4)
                        }
                    }

                    Button("Delete trip", role: .destructive) {
                        deleteTripOutcomeDetails(for: outcome)
                    }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Trip details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        cancelTripOutcomeDetails()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save changes") {
                        saveTripOutcomeDetails(for: outcome)
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var tripDataEditorActions: some View {
        HStack {
            Button("Delete all", role: .destructive) {
                isDeleteAllTripDataConfirmationPresented = true
            }
            .buttonStyle(.bordered)
            .disabled(outcomes.isEmpty)

            Spacer()

            Button("Delete", role: .destructive) {
                deleteSelectedTripData()
            }
            .buttonStyle(.borderedProminent)
            .disabled(selectedTripOutcomeIDs.isEmpty)
        }
    }

    private var tripDataEditorOutcomes: [TripOutcome] {
        outcomes.sorted { $0.date > $1.date }
    }

    private func tripDataRow(for outcome: TripOutcome) -> some View {
        Button {
            if isSelectingTripData {
                toggleTripDataSelection(for: outcome)
                return
            }

            presentTripOutcomeDetails(for: outcome)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                if isSelectingTripData {
                    Image(systemName: selectedTripOutcomeIDs.contains(outcome.id) ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(selectedTripOutcomeIDs.contains(outcome.id) ? sliderAccentColor : .secondary)
                        .font(.title3)
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(outcome.date.formatted(date: .abbreviated, time: .shortened))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)

                            if outcome.vehicleProfileKind == .customEV {
                                customEVTripBadge
                            }
                        }

                        Spacer()

                        Text(tripOutcomeConsumptionText(for: outcome))
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                    }

                    Text(tripOutcomeDetailText(for: outcome))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(tripOutcomeCalibrationEligibilityText(for: outcome))
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    if !outcome.note.isEmpty {
                        Text(outcome.note)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .lineLimit(2)
                    }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var customEVTripBadge: some View {
        Text("Custom profile")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(sliderAccentColor)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(sliderAccentColor.opacity(0.12), in: Capsule())
    }

    private var aboutAppButton: some View {
        Button {
            isAboutAppGuidePresented = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "info.circle")
                    .font(.body)

                Text("About the app")
                    .font(.subheadline.weight(.semibold))

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens app information")
    }

    private func card<Content: View>(
        title: String? = nil,
        footnote: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if let title {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)

                    if let footnote {
                        Text(footnote)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            content()
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func sliderSection(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        displayValue: String,
        isVisuallyDisabled: Bool = false,
        showsPrecisionButtons: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(displayValue)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                if showsPrecisionButtons {
                    PrecisionNudgeButton(symbol: "−") {
                        value.wrappedValue = clamped(value.wrappedValue - step, to: range)
                    }
                    .accessibilityLabel("Decrease \(title.lowercased())")
                }

                Slider(value: value, in: range, step: step)
                    .tint(isVisuallyDisabled ? .secondary : sliderAccentColor)
                    .opacity(isVisuallyDisabled ? 0.55 : 1)

                if showsPrecisionButtons {
                    PrecisionNudgeButton(symbol: "+") {
                        value.wrappedValue = clamped(value.wrappedValue + step, to: range)
                    }
                    .accessibilityLabel("Increase \(title.lowercased())")
                }
            }
        }
    }

    private func clamped(_ value: Double, to range: ClosedRange<Double>) -> Double {
        min(max(value, range.lowerBound), range.upperBound)
    }

    private func informationalRow(title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            Spacer(minLength: 16)
            Text(value)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
    }

    private func resultRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
                .multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
    }

    private func secondaryResultRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }

    private func outcomeField(title: String, text: Binding<String>, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                TextField(title, text: text)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.roundedBorder)
                Text(unit)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func experimentalNumericField(
        label: String,
        value: Binding<Double>,
        unit: String,
        fractionLength: Int,
        focusedField: CustomVehicleProfileField? = nil
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .font(.subheadline.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Group {
                    if let focusedField {
                        TextField(
                            label,
                            value: value,
                            format: .number.precision(.fractionLength(fractionLength))
                        )
                        .focused($focusedCustomVehicleProfileField, equals: focusedField)
                    } else {
                        TextField(
                            label,
                            value: value,
                            format: .number.precision(.fractionLength(fractionLength))
                        )
                    }
                }
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .textFieldStyle(.roundedBorder)
                .frame(width: 92)

                Text(unit)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 28, alignment: .leading)
            }
        }
    }

    private func profileEditorNumericTextField(
        label: String,
        text: Binding<String>,
        unit: String,
        focusedField: CustomVehicleProfileField
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .font(.subheadline.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                TextField(label, text: text)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .textFieldStyle(.roundedBorder)
                    .focused($focusedCustomVehicleProfileField, equals: focusedField)
                    .frame(width: 92)

                Text(unit)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 28, alignment: .leading)
            }
        }
    }

    private func rounded(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0)))
    }

    private func clampedFinite(
        _ value: Double,
        in range: ClosedRange<Double>,
        fallback: Double
    ) -> Double {
        let finiteValue = value.isFinite ? value : fallback
        return min(max(finiteValue, range.lowerBound), range.upperBound)
    }

    private func positiveFinite(_ value: Double, fallback: Double) -> Double {
        value.isFinite && value > 0 ? value : fallback
    }

    private func degradedModelWLTPRangeKm(
        for profile: VehicleProfile,
        nominalWLTPRangeKm: Double? = nil
    ) -> Double {
        let nominalRangeKm = nominalWLTPRangeKm ?? positiveFinite(
            profile.wltpRangeKm,
            fallback: VehicleProfileResolver.defaultCustomWLTPRangeKm
        )
        let degradationPercent = min(max(profile.batteryDegradationPercent, 0), 10)
        return nominalRangeKm * (1.0 - Double(degradationPercent) / 100.0)
    }

    private func consumptionText(forTenths tenths: Int) -> String {
        displayUnits.formatConsumptionValue(
            fromKWhPer100Km: displayUnits.storedConsumption(fromDisplayed: Double(tenths) / 10)
        )
    }

    private var outcomeConsumptionTenthsRange: ClosedRange<Int> {
        switch displayUnits {
        case .metric:
            80...300
        case .imperial:
            20...78
        }
    }

    private var outcomeDistanceDisplayRange: ClosedRange<Int> {
        switch displayUnits {
        case .metric:
            5...300
        case .imperial:
            3...190
        }
    }

    private func displayRange(forStoredDistanceRange range: ClosedRange<Double>) -> ClosedRange<Double> {
        let lower = displayUnits.displayDistance(fromKm: range.lowerBound)
        let upper = displayUnits.displayDistance(fromKm: range.upperBound)
        return roundedWholeDisplayRange(lower, upper)
    }

    private func displayRange(forStoredConsumptionRange range: ClosedRange<Double>) -> ClosedRange<Double> {
        let lower = displayUnits.displayConsumption(fromKWhPer100Km: range.lowerBound)
        let upper = displayUnits.displayConsumption(fromKWhPer100Km: range.upperBound)
        return roundedTenthsDisplayRange(lower, upper)
    }

    private func displayedMotorwaySpeed(fromKmh speed: Double) -> Double {
        switch displayUnits {
        case .metric:
            speed
        case .imperial:
            speed / kilometersPerMile
        }
    }

    private func storedMotorwaySpeed(fromDisplayed speed: Double) -> Double {
        switch displayUnits {
        case .metric:
            speed
        case .imperial:
            speed * kilometersPerMile
        }
    }

    private func formattedMotorwaySpeed(_ speedKmh: Double) -> String {
        let unitLabel = displayUnits == .metric ? "km/h" : "mph"
        return "\(rounded(displayedMotorwaySpeed(fromKmh: speedKmh))) \(unitLabel)"
    }

    private func roundedWholeDisplayRange(_ firstValue: Double, _ secondValue: Double) -> ClosedRange<Double> {
        let lower = min(firstValue, secondValue).rounded()
        let upper = max(firstValue, secondValue).rounded()
        return lower...max(lower, upper)
    }

    private func roundedTenthsDisplayRange(_ firstValue: Double, _ secondValue: Double) -> ClosedRange<Double> {
        let lower = (min(firstValue, secondValue) * 10).rounded() / 10
        let upper = (max(firstValue, secondValue) * 10).rounded() / 10
        return lower...max(lower, upper)
    }

    private var isManualReferenceInactive: Bool {
        useContinuousCalibration && activeCalibrationCorrection.canApply
    }

    private var continuousCalibrationStatusText: String {
        guard activeCalibrationCorrection.canApply else {
            return isCustomVehicleProfileSelected ? "\(activeVehicleProfile.profile.displayName) calibration" : "Reference value"
        }

        return activeCalibrationCorrection.displaySourceLabel(for: activeVehicleProfileKind)
    }

    private var calibrationSummaryTitle: String {
        if useContinuousCalibration, activeCalibrationCorrection.canApply {
            return "\(activeCalibrationCorrection.displaySourceLabel(for: activeVehicleProfileKind)): \(displayUnits.formattedConsumption(effectiveReferenceConsumption))"
        }

        if isCustomVehicleProfileSelected {
            return "\(activeVehicleProfile.profile.displayName) reference: \(displayUnits.formattedConsumption(effectiveReferenceConsumption))"
        }

        return "Reference value: \(displayUnits.formattedConsumption(effectiveReferenceConsumption))"
    }

    private var calibrationSummaryDetail: String {
        if useContinuousCalibration, activeCalibrationCorrection.canApply {
            let count = activeCalibrationCorrection.usableRecordCount
            return "Based on \(count) logged \(count == 1 ? "trip" : "trips")"
        }

        if useContinuousCalibration {
            return isCustomVehicleProfileSelected
                ? "Need at least 3 logged trips for \(activeVehicleProfile.profile.displayName)"
                : "Need at least 3 logged trips"
        }

        if isCustomVehicleProfileSelected {
            return "\(activeVehicleProfile.profile.displayName) uses the profile battery and WLTP values while continuous calibration is off."
        }

        return "Manual overall calibration is used while calibration based on logged trips is off."
    }

    private var validSavedDestinationName: String? {
        let trimmedName = savedDestinationName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedName.isEmpty ? nil : trimmedName
    }

    private var savedDestinationQuery: String? {
        let destinationQuery = tripAssistantDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        return destinationQuery.isEmpty ? nil : destinationQuery
    }

    private func savedDestinationPickerTitle(for destination: SavedDestination) -> String {
        destination.name
    }

    private func presentSaveDestinationSheet() {
        savedDestinationName = tripAssistantDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        isSaveDestinationSheetPresented = true
    }

    private func presentManageFavoriteDestinationsSheet() {
        savedDestinationName = ""
        isSaveDestinationSheetPresented = true
    }

    private func saveCurrentDestination() {
        guard let destinationQuery = savedDestinationQuery else {
            return
        }

        let name = validSavedDestinationName ?? destinationQuery
        let savedDestination = SavedDestination(
            name: name,
            destinationQuery: destinationQuery
        )
        savedDestinations.append(savedDestination)
        savedDestinations.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        savedDestinations = SavedDestinationStore.sanitized(savedDestinations)
        SavedDestinationStore.save(savedDestinations)
        isSaveDestinationSheetPresented = false
    }

    private func applySavedDestination(_ destination: SavedDestination) {
        let destinationQuery = destination.destinationQuery.trimmingCharacters(in: .whitespacesAndNewlines)

        tripAssistantDescription = destinationQuery
        tripAssistantRoute = nil
#if canImport(MapKit)
        tripAssistantRouteEstimate = nil
#endif
        isTripDistanceMapDerived = false

        guard destinationQuery.isEmpty == false else {
            tripAssistantMessage = .text("No route found. Enter a destination to estimate with Maps.")
            return
        }

        runTripAssistantEstimate(
            description: destinationQuery,
            fallbackDistanceKm: nil,
            preservesCurrentTripAssumptions: true
        )
    }

    private func deleteSavedDestination(_ destination: SavedDestination) {
        savedDestinations.removeAll { $0.id == destination.id }
        SavedDestinationStore.save(savedDestinations)
    }

    private var validOutcomeInput: TripOutcomeInput? {
        let displayedConsumption = Double(outcomeActualConsumptionTenths) / 10
        let actualConsumptionKWhPer100Km = displayUnits.storedConsumption(fromDisplayed: displayedConsumption)
        let actualDistanceKm = displayUnits.storedDistance(fromDisplayed: Double(outcomeDistanceKm))

        return TripOutcomeInput(
            actualConsumptionKWhPer100Km: actualConsumptionKWhPer100Km,
            actualDistanceKm: actualDistanceKm
        )
    }

    private func saveTripOutcome() {
        guard let input = validOutcomeInput else {
            return
        }

        let outcome = TripOutcome(
            date: Date(),
            vehicleProfileKind: activeVehicleProfileKind,
            predictedRangeKm: outcomeLogRemainingRange.rangeKm,
            predictedConsumptionKWhPer100Km: outcomeLogForecast.finalKWhPer100km,
            actualConsumptionKWhPer100Km: input.actualConsumptionKWhPer100Km,
            actualDistanceKm: input.actualDistanceKm,
            batteryStartPercent: nil,
            batteryEndPercent: nil,
            distanceKm: input.actualDistanceKm,
            plannedDistanceKm: distance,
            referenceConsumptionKWhPer100Km: isCustomVehicleProfileSelected
                ? experimentalReferenceConsumptionKWhPer100Km
                : outcomeLogForecast.referenceConsumptionKWhPer100km,
            currentBatteryPercent: startBatteryPercent,
            motorwayShare: outcomeRoadTypeProfile.legacyMotorwayShare,
            roadTypeProfile: outcomeRoadTypeProfile,
            motorwaySpeedKmh: outcomeMotorwaySpeed,
            temperatureC: outcomeTemperature,
            roadSurface: outcomeRoadSurface,
            windCondition: outcomeWindCondition,
            planningMode: nil,
            airConditioningMode: activeAirConditioningMode,
            tyreSet: outcomeTyreSet,
            rollingResistanceClass: outcomeRollingResistanceClass,
            winterTyres: outcomeTyreSet == .winter,
            note: outcomeNote.trimmingCharacters(in: .whitespacesAndNewlines)
        )

        outcomes.append(outcome)
        TripOutcomeStore.save(outcomes)
        resetTripOutcomeInput()
        isTripOutcomeCardPresented = false
    }

    private func presentTripOutcomeCard() {
        resetTripOutcomeInput()
        withAnimation(.snappy) {
            isTripOutcomeCardPresented = true
        }
    }

    private func presentLogActualConsumptionEntry() {
        guard hasSeenLogActualConsumptionInfo else {
            isLogActualConsumptionInfoPresented = true
            return
        }

        presentTripOutcomeCard()
    }

    private func presentTripPlanningInputInfoIfNeeded(isFocused: Bool) {
        guard isFocused,
              !hasSeenTripPlanningInputInfo,
              !isTripPlanningInputInfoPresented else {
            return
        }

        isTripAssistantDescriptionFocused = false
        isTripPlanningInputInfoPresented = true
    }

    private func cancelTripOutcome() {
        resetTripOutcomeInput()
        withAnimation(.snappy) {
            isTripOutcomeCardPresented = false
        }
    }

    private func resetTripOutcomeInput() {
        let forecastConsumptionTenths = Int((displayUnits.displayConsumption(fromKWhPer100Km: forecast(for: .normal).finalKWhPer100km) * 10).rounded())
        outcomeActualConsumptionTenths = min(
            max(forecastConsumptionTenths, outcomeConsumptionTenthsRange.lowerBound),
            outcomeConsumptionTenthsRange.upperBound
        )
        outcomeDistanceKm = displayUnits == .metric ? 15 : 10
        outcomeNote = ""
        outcomeTemperature = temperature
        outcomeRoadSurface = roadSurface
        outcomeWindCondition = windCondition
        outcomeRoadTypeProfile = roadTypeProfile
        outcomeMotorwaySpeed = MiniConsumptionDefaults.normalizedMotorwaySpeed(activeMotorwaySpeed)
        outcomeTyreSet = activeSelectedTyreSet
        outcomeRollingResistanceClass = activeRollingResistanceClass
    }

#if canImport(MapKit)
    private func tripRouteActionButtons(for route: TripRouteDescription) -> some View {
        HStack(spacing: 8) {
            Button {
                Task {
                    await AppleMapsHandoff.openRoute(
                        origin: route.origin,
                        destination: route.destination
                    )
                }
            } label: {
                Label("Show route in Maps", systemImage: "arrow.triangle.turn.up.right.diamond")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            if batteryPlan.needsCharging {
                Button {
                    Task {
                        if let tripAssistantNextChargingSearchCoordinate {
                            await AppleMapsHandoff.openChargingSearch(centeredAt: tripAssistantNextChargingSearchCoordinate)
                            return
                        }

                        await AppleMapsHandoff.openChargingSearch(near: route.destination)
                    }
                } label: {
                    Label("Find charger for next stop", systemImage: "bolt.car")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!canFindNextCharger(for: route))
            }
        }
    }

    private func canFindNextCharger(for route: TripRouteDescription) -> Bool {
        batteryPlan.needsCharging
            && selectedTripChargingOptionPlan?.nextStopDistanceKm != nil
            && (tripAssistantNextChargingSearchCoordinate != nil || route.destination.isEmpty == false)
    }
#endif

    private func interpretTripAssistantDescription() {
        let description = tripAssistantDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !description.isEmpty else {
            return
        }

        runTripAssistantEstimate(
            description: description,
            fallbackDistanceKm: nil,
            preservesCurrentTripAssumptions: false
        )
    }

    private func refreshTripEstimateAssumptionsIfNeeded() {
        guard hasTripRoutePlanningResult == false else {
            return
        }

        resetTripEstimateAssumptionsFromCurrentSettings()
    }

#if canImport(CoreLocation) && canImport(MapKit)
    private func planTripToSelectedMapCoordinate(
        _ coordinate: CLLocationCoordinate2D,
        destinationLabel: String = "Selected map point"
    ) {
        let input = NaturalLanguageTripEstimateInput(
            batteryPercentage: nil,
            plannedDistanceKm: nil,
            route: TripRouteDescription(origin: nil, destination: destinationLabel),
            chargingPreference: nil,
            batteryThresholdQuestionPercent: nil,
            roadTypeProfile: nil,
            hasExplicitRoadTypeWording: false,
            motorwaySpeed: nil,
            temperature: nil,
            roadSurface: nil,
            windCondition: nil,
            planningMode: nil
        )

        selectedAppTab = .trip
        resetTripEstimateAssumptionsFromCurrentSettings()
        tripAssistantSearchGeneration += 1
        let searchGeneration = tripAssistantSearchGeneration
        tripAssistantDescription = destinationLabel
        tripAssistantRoute = input.route
        tripAssistantRouteEstimate = nil
        tripAssistantMessage = .text("Looking up route distance with Apple Maps.")
        isTripAssistantInterpreting = false
        isTripAssistantRouteLookupPending = true
        isTripAssistantDescriptionFocused = false

        Task {
            var routeEstimate: RouteDistanceEstimate?
            var routeDistanceKm: Double?
            var routeLookupFailed = false

            do {
                routeEstimate = try await RouteDistanceService.estimatedDrivingRouteFromCurrentLocation(to: coordinate)
                routeDistanceKm = routeEstimate?.distanceKm
                routeLookupFailed = routeDistanceKm == nil
            } catch {
                routeLookupFailed = true
            }

            await MainActor.run {
                guard searchGeneration == tripAssistantSearchGeneration else {
                    return
                }

                let roadTypeSelection = applyTripAssistantInput(
                    input,
                    routeEstimate: routeEstimate,
                    fallbackDistanceKm: nil,
                    preservesCurrentTripAssumptions: false
                )
                isTripAssistantRouteLookupPending = false
                tripAssistantMessage = tripAssistantSummary(
                    for: input,
                    routeDistanceKm: routeDistanceKm,
                    routeLookupFailed: routeLookupFailed,
                    resolvedRoadTypeProfile: roadTypeSelection.roadTypeProfile
                )
            }
        }
    }
#endif

    private func runTripAssistantEstimate(
        description: String,
        fallbackDistanceKm: Double?,
        preservesCurrentTripAssumptions: Bool
    ) {
        if preservesCurrentTripAssumptions == false {
            resetTripEstimateAssumptionsFromCurrentSettings()
        }

        tripAssistantSearchGeneration += 1
        let searchGeneration = tripAssistantSearchGeneration
        isTripAssistantInterpreting = true
        tripAssistantMessage = nil

        Task {
            let input = await NaturalLanguageTripParser.parse(description)
            var routeEstimate: RouteDistanceEstimate?
            var routeDistanceKm: Double?
            var routeLookupFailed = false

            if let route = input.route {
                await MainActor.run {
                    isTripAssistantRouteLookupPending = true
                    tripAssistantMessage = .text("Looking up route distance with Apple Maps.")
                }

                do {
                    if let origin = route.origin {
                        routeEstimate = try await RouteDistanceService.estimatedDrivingRoute(from: origin, to: route.destination)
                    } else {
                        routeEstimate = try await RouteDistanceService.estimatedDrivingRouteFromCurrentLocation(to: route.destination)
                    }
                    routeDistanceKm = routeEstimate?.distanceKm
                    routeLookupFailed = routeDistanceKm == nil
                } catch {
                    routeLookupFailed = true
                }
            }

            await MainActor.run {
                guard searchGeneration == tripAssistantSearchGeneration else {
                    return
                }

                let roadTypeSelection = applyTripAssistantInput(
                    input,
                    routeEstimate: routeEstimate,
                    fallbackDistanceKm: fallbackDistanceKm,
                    preservesCurrentTripAssumptions: preservesCurrentTripAssumptions
                )
                isTripAssistantInterpreting = false
                isTripAssistantRouteLookupPending = false
                isTripAssistantDescriptionFocused = false
                tripAssistantMessage = tripAssistantSummary(
                    for: input,
                    routeDistanceKm: routeDistanceKm ?? input.plannedDistanceKm,
                    routeLookupFailed: routeLookupFailed,
                    resolvedRoadTypeProfile: roadTypeSelection.roadTypeProfile
                )
            }
        }
    }

    private var isTripSearchActive: Bool {
        hasTripEstimate
            || isTripAssistantInterpreting
            || isTripAssistantRouteLookupPending
            || tripAssistantDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    private func clearActiveTripSearch() {
        tripAssistantSearchGeneration += 1
        tripAssistantDescription = ""
        tripAssistantMessage = nil
        tripAssistantRoute = nil
#if canImport(MapKit)
        tripAssistantRouteEstimate = nil
#endif
        hasTripEstimate = false
        isTripAssistantInterpreting = false
        isTripAssistantRouteLookupPending = false
        isTripAssistantDescriptionFocused = false
        isTripAssumptionsEditorPresented = false
        selectedTripChargingOption = .userSettings
        resetTripEstimateAssumptionsFromCurrentSettings()
    }

    private func resetTripEstimateAssumptionsFromCurrentSettings() {
        tripEstimateDistance = min(max(distance, 1), 1000)
        tripEstimateStartBatteryPercent = min(max(startBatteryPercent, 10), 100)
        tripEstimateTemperature = temperature
        tripEstimateRoadTypeProfile = roadTypeProfile
        tripEstimateMotorwaySpeed = MiniConsumptionDefaults.normalizedMotorwaySpeed(activeMotorwaySpeed)
        tripEstimateRoadSurface = roadSurface.segmentedEquivalent
        tripEstimateWindCondition = windCondition
        tripEstimatePlanningMode = tripPlanningStrategy
        tripEstimateArrivalBatteryTargetPercent = min(
            max(arrivalBatteryTargetPercent, ChargingWindow.arrivalBatteryTargetBounds.lowerBound),
            ChargingWindow.arrivalBatteryTargetBounds.upperBound
        )
        isTripDistanceMapDerived = false
    }

    private func applyTripAssistantInput(
        _ input: NaturalLanguageTripEstimateInput,
        routeEstimate: RouteDistanceEstimate?,
        fallbackDistanceKm: Double? = nil,
        preservesCurrentTripAssumptions: Bool = false
    ) -> TripRoadTypeSelection.Result {
        tripAssistantRoute = input.route
        if preservesCurrentTripAssumptions == false {
            selectedTripChargingOption = .userSettings
        }
#if canImport(MapKit)
        tripAssistantRouteEstimate = routeEstimate
#endif

        let routeDistanceKm = routeEstimate?.distanceKm
        let resolvedDistanceKm = preservesCurrentTripAssumptions
            ? routeDistanceKm ?? fallbackDistanceKm ?? input.plannedDistanceKm
            : routeDistanceKm ?? input.plannedDistanceKm ?? fallbackDistanceKm
        let routeAverageSpeedKmh = routeEstimate?.averageSpeedKmh

        if let resolvedDistanceKm {
            tripEstimateDistance = min(max(resolvedDistanceKm, 1), 1000)
            isTripDistanceMapDerived = routeDistanceKm != nil
        } else {
            tripEstimateDistance = min(max(distance, 1), 1000)
            isTripDistanceMapDerived = false
        }

        if preservesCurrentTripAssumptions {
            hasTripEstimate = true
            return TripRoadTypeSelection.Result(
                roadTypeProfile: tripEstimateRoadTypeProfile,
                usedFallback: false
            )
        } else {
            if let batteryPercentage = input.batteryPercentage {
                tripEstimateStartBatteryPercent = min(max(batteryPercentage, 10), 100)
            } else {
                tripEstimateStartBatteryPercent = startBatteryPercent
            }

            let roadTypeSelection = TripRoadTypeSelection.resolve(
                parsedRoadType: input.roadTypeProfile,
                hasExplicitRoadTypeWording: input.hasExplicitRoadTypeWording,
                distanceKm: resolvedDistanceKm,
                currentRoadType: roadTypeProfile,
                routeAverageSpeedKmh: routeAverageSpeedKmh
            )
            tripEstimateRoadTypeProfile = roadTypeSelection.roadTypeProfile

            if let motorwaySpeed = input.motorwaySpeed {
                tripEstimateMotorwaySpeed = MiniConsumptionDefaults.normalizedMotorwaySpeed(motorwaySpeed)
            } else {
                tripEstimateMotorwaySpeed = MiniConsumptionDefaults.normalizedMotorwaySpeed(motorwaySpeed)
            }

            if let temperature = input.temperature {
                tripEstimateTemperature = min(max(temperature, supportedTemperatureRangeC.lowerBound), supportedTemperatureRangeC.upperBound)
            } else {
                tripEstimateTemperature = temperature
            }

            if let roadSurface = input.roadSurface {
                tripEstimateRoadSurface = roadSurface.segmentedEquivalent
            } else {
                tripEstimateRoadSurface = roadSurface.segmentedEquivalent
            }

            if let windCondition = input.windCondition {
                tripEstimateWindCondition = windCondition
            } else {
                tripEstimateWindCondition = windCondition
            }

            if let planningMode = input.planningMode {
                tripEstimatePlanningMode = planningMode
            } else {
                tripEstimatePlanningMode = tripPlanningStrategy
            }

            tripEstimateArrivalBatteryTargetPercent = min(
                max(arrivalBatteryTargetPercent, ChargingWindow.arrivalBatteryTargetBounds.lowerBound),
                ChargingWindow.arrivalBatteryTargetBounds.upperBound
            )
            hasTripEstimate = true

            return roadTypeSelection
        }
    }

    private func tripAssistantSummary(
        for input: NaturalLanguageTripEstimateInput,
        routeDistanceKm: Double?,
        routeLookupFailed: Bool,
        resolvedRoadTypeProfile: RoadTypeProfile
    ) -> TripAssistantMessage {
        var updatesAfterDistance = [String]()

        if let batteryPercentage = input.batteryPercentage {
            updatesAfterDistance.append("battery \(rounded(batteryPercentage))%")
        }
        if input.hasExplicitRoadTypeWording || input.roadTypeProfile != nil || routeDistanceKm != nil {
            updatesAfterDistance.append(resolvedRoadTypeProfile.label.lowercased())
        }
        if let motorwaySpeed = input.motorwaySpeed {
            updatesAfterDistance.append(formattedMotorwaySpeed(motorwaySpeed))
        }
        if let temperature = input.temperature {
            updatesAfterDistance.append(temperatureUnits.formattedTemperature(temperature))
        }
        if let roadSurface = input.roadSurface {
            updatesAfterDistance.append(roadSurface.segmentedEquivalent.label.lowercased())
        }
        if let windCondition = input.windCondition {
            updatesAfterDistance.append(windCondition.label.lowercased())
        }
        if let planningMode = input.planningMode {
            updatesAfterDistance.append("\(planningMode.label.lowercased()) strategy")
        }

        return .controlsUpdated(
            distanceKm: routeDistanceKm,
            routeDistanceUnavailable: routeLookupFailed && routeDistanceKm == nil,
            updatesAfterDistance: updatesAfterDistance
        )
    }

    private func deleteSelectedTripData() {
        outcomes.removeAll { selectedTripOutcomeIDs.contains($0.id) }
        TripOutcomeStore.save(outcomes)
        selectedTripOutcomeIDs.removeAll()
        isSelectingTripData = false
    }

    private func presentTripOutcomeDetails(for outcome: TripOutcome) {
        draftTripDetailsTemperature = outcome.temperatureC
        draftTripDetailsRoadSurface = outcome.roadSurface
        draftTripDetailsWindCondition = outcome.windCondition
        draftTripDetailsRoadTypeProfile = outcome.roadTypeProfile
        draftTripDetailsMotorwaySpeed = MiniConsumptionDefaults.normalizedMotorwaySpeed(outcome.motorwaySpeedKmh)
        draftTripDetailsRollingResistanceClass = outcome.rollingResistanceClass ?? .b
        draftTripDetailsDistanceKm = outcome.editableLoggedDistanceKm
        draftTripDetailsNote = outcome.note
        selectedTripOutcomeForDetails = outcome
    }

    private func cancelTripOutcomeDetails() {
        selectedTripOutcomeForDetails = nil
    }

    private func saveTripOutcomeDetails(for outcome: TripOutcome) {
        guard let index = outcomes.firstIndex(where: { $0.id == outcome.id }) else {
            selectedTripOutcomeForDetails = nil
            return
        }

        outcomes[index] = outcome.updatingEditableAssumptions(
            temperatureC: draftTripDetailsTemperature,
            roadSurface: draftTripDetailsRoadSurface,
            windCondition: draftTripDetailsWindCondition,
            roadTypeProfile: draftTripDetailsRoadTypeProfile,
            motorwaySpeedKmh: draftTripDetailsMotorwaySpeed,
            rollingResistanceClass: draftTripDetailsRollingResistanceClass,
            storedDistanceKm: draftTripDetailsDistanceKm,
            note: draftTripDetailsNote.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        TripOutcomeStore.save(outcomes)
        selectedTripOutcomeForDetails = nil
    }

    private func deleteTripOutcomeDetails(for outcome: TripOutcome) {
        outcomes.removeAll { $0.id == outcome.id }
        TripOutcomeStore.save(outcomes)
        selectedTripOutcomeForDetails = nil
        selectedTripOutcomeIDs.remove(outcome.id)
        if selectedTripOutcomeIDs.isEmpty {
            isSelectingTripData = false
        }
    }

    private func deleteAllTripData() {
        outcomes.removeAll()
        TripOutcomeStore.save(outcomes)
        resetTripDataEditor()
    }

    private func resetTripDataEditor() {
        isSelectingTripData = false
        selectedTripOutcomeIDs.removeAll()
        selectedTripOutcomeForDetails = nil
        isDeleteAllTripDataConfirmationPresented = false
    }

    private func reloadTripDataAfterEditing() {
        outcomes = TripOutcomeStore.load()
        resetTripDataEditor()
    }

    private func resetAllSettingsToDefaults() {
        startBatteryPercent = MiniConsumptionDefaults.currentBatteryPercent
        roadTypeProfile = MiniConsumptionDefaults.roadTypeProfile
        motorwaySpeed = MiniConsumptionDefaults.motorwaySpeedKmh
        temperature = MiniConsumptionDefaults.temperatureC
        roadSurface = MiniConsumptionDefaults.roadSurface
        setWindCondition(MiniConsumptionDefaults.windCondition)
        tripPlanningStrategy = MiniConsumptionDefaults.planningMode
        airConditioningMode = MiniConsumptionDefaults.airConditioningMode

        selectedTyreSet = MiniConsumptionDefaults.selectedTyreSet
        winterTyres = false
        summerTyreClass = MiniConsumptionDefaults.summerTyreClass
        winterTyreClass = MiniConsumptionDefaults.winterTyreClass
        rollingResistanceClass = MiniConsumptionDefaults.summerTyreClass

        distance = MiniConsumptionDefaults.tripDistanceKm
        quickTripDistance = MiniConsumptionDefaults.quickTripDistanceKm
        isTripDistanceMapDerived = false
        normalMinimumChargingPercent = ChargingWindow.defaultMinimumPercent
        normalFastChargeTargetPercent = ChargingWindow.defaultTargetPercent
        arrivalBatteryTargetPercent = ChargingWindow.defaultArrivalBatteryTargetPercent
        averageChargingSpeedKW = MiniConsumptionCalculator.defaultAverageChargingSpeedKW
        averageChargingSpeedOverridesByProfileData = Data()
        referenceConsumptionOverridesByProfileData = Data()
        motorwaySpeedOverridesByProfileData = Data()
        airConditioningModeOverridesByProfileData = Data()
        selectedTyreSetOverridesByProfileData = Data()
        summerTyreClassOverridesByProfileData = Data()
        winterTyreClassOverridesByProfileData = Data()
        normalMinimumChargingPercentOverridesByProfileData = Data()
        normalFastChargeTargetPercentOverridesByProfileData = Data()
        miniBatteryDegradationPercent = MiniConsumptionDefaults.batteryDegradationPercent
        batteryDegradationPercent = MiniConsumptionDefaults.batteryDegradationPercent

        useContinuousCalibration = MiniConsumptionDefaults.useContinuousCalibration
        referenceConsumption = defaultReferenceConsumptionKWhPer100Km
        displayUnits = .metric
        temperatureUnits = .celsius
        weightUnits = .kilograms
        experimentalCustomVehicleProfileEnabled = false
        VehicleProfileStore.setSelectedProfileID(VehicleProfileResolver.builtInMiniProfileID)
        selectedVehicleProfileID = VehicleProfileResolver.builtInMiniProfileID
        experimentalUsableBatteryCapacityKWh = 28.9
        experimentalOfficialWLTPRangeKm = 234
        experimentalMaximumDCChargingSpeedKW = 50
    }

    private func toggleTripDataSelection(for outcome: TripOutcome) {
        if selectedTripOutcomeIDs.contains(outcome.id) {
            selectedTripOutcomeIDs.remove(outcome.id)
        } else {
            selectedTripOutcomeIDs.insert(outcome.id)
        }
    }

    private func tripOutcomeConsumptionText(for outcome: TripOutcome) -> String {
        guard let consumption = outcome.resolvedActualConsumptionKWhPer100Km else {
            return "No consumption"
        }

        return displayUnits.formattedConsumption(consumption)
    }

    private func tripOutcomeDetailText(for outcome: TripOutcome) -> String {
        let distanceText = outcome.loggedOutcomeDistanceKm.map {
            displayUnits.formattedDistance($0)
        } ?? "Distance not saved"
        let tyreClassText = (outcome.rollingResistanceClass ?? .b).label

        return [
            distanceText,
            temperatureUnits.formattedTemperature(outcome.temperatureC),
            outcome.roadSurface.label,
            "\(outcome.windCondition.label) wind",
            outcome.roadTypeProfile.label,
            "Tyres \(tyreClassText)"
        ].joined(separator: " • ")
    }

    private func tripOutcomeCalibrationEligibilityText(for outcome: TripOutcome) -> String {
        let display = CalibrationTripEligibility.display(for: outcome)
        if display.eligible, outcome.vehicleProfileKind == .customEV {
            return "Eligible for custom profile calibration"
        }

        return display.eligible ? "Eligible for calibration" : display.displayReason ?? "Not used for calibration"
    }

    private func calibrationExclusionLabel(for reason: CalibrationTripExclusionReason) -> String {
        switch reason {
        case .tooShort:
            "Under \(displayUnits.formattedDistance(CalibrationTripQuality.minimumCalibrationTripDistanceKm))"
        case .missingDistance,
                .missingActualConsumption,
                .invalidActualConsumption,
                .unrealisticActualConsumption,
                .missingPredictedBaseline:
            reason.label
        }
    }

    private func migrateTyreSettingsIfNeeded(defaults: UserDefaults = .standard) {
        if defaults.object(forKey: "selectedTyreSet") == nil {
            selectedTyreSet = winterTyres ? .winter : .summer
        }

        if defaults.object(forKey: "summerTyreClass") == nil {
            summerTyreClass = rollingResistanceClass
        }

        if defaults.object(forKey: "winterTyreClass") == nil {
            winterTyreClass = defaults.object(forKey: "winterTyres") as? Bool == true
                ? rollingResistanceClass
                : MiniConsumptionDefaults.winterTyreClass
        }

        winterTyres = selectedTyreSet == .winter
        rollingResistanceClass = activeRollingResistanceClass
    }

    private func migrateLegacyCustomEVProfileIfNeeded(defaults: UserDefaults = .standard) {
        VehicleProfileStore.migrateLegacyCustomEVProfileIfNeeded(
            input: vehicleProfileResolverInput,
            defaults: defaults
        )
        customVehicleProfiles = VehicleProfileStore.loadCustomProfiles(defaults: defaults)
    }

    private func reconcileSelectedVehicleProfile(defaults: UserDefaults = .standard) {
        customVehicleProfiles = VehicleProfileStore.loadCustomProfiles(defaults: defaults)
        let storedSelection = VehicleProfileStore.selectedProfileID(defaults: defaults)
            ?? VehicleProfileResolver.builtInMiniProfileID

        if storedSelection == VehicleProfileResolver.builtInMiniProfileID {
            selectBuiltInMiniVehicleProfile(defaults: defaults)
            return
        }

        guard let profile = customVehicleProfiles.first(where: { $0.id == storedSelection }) else {
            selectBuiltInMiniVehicleProfile(defaults: defaults)
            return
        }

        selectedVehicleProfileID = profile.id
        experimentalCustomVehicleProfileEnabled = true
        syncExperimentalCustomEVValues(from: profile)
        batteryDegradationPercent = profile.batteryDegradationPercent
    }

    private func selectBuiltInMiniVehicleProfile(defaults: UserDefaults = .standard) {
        VehicleProfileStore.setSelectedProfileID(
            VehicleProfileResolver.builtInMiniProfileID,
            defaults: defaults
        )
        selectedVehicleProfileID = VehicleProfileResolver.builtInMiniProfileID
        experimentalCustomVehicleProfileEnabled = false
        batteryDegradationPercent = miniBatteryDegradationPercent
        customVehicleProfiles = VehicleProfileStore.loadCustomProfiles(defaults: defaults)
    }

    private func selectCustomVehicleProfile(
        _ profile: VehicleProfile,
        defaults: UserDefaults = .standard
    ) {
        customVehicleProfiles = VehicleProfileStore.loadCustomProfiles(defaults: defaults)
        guard let selectedProfile = customVehicleProfiles.first(where: { $0.id == profile.id }) else {
            selectBuiltInMiniVehicleProfile(defaults: defaults)
            return
        }

        syncExperimentalCustomEVValues(from: selectedProfile)
        VehicleProfileStore.setSelectedProfileID(
            selectedProfile.id,
            defaults: defaults
        )
        selectedVehicleProfileID = selectedProfile.id
        experimentalCustomVehicleProfileEnabled = true
        batteryDegradationPercent = selectedProfile.batteryDegradationPercent
    }

    private func presentCreateVehicleProfileSheet() {
        selectedVehicleProfileTemplateBrand = VehicleProfileTemplate.customProfileID
        selectedVehicleProfileTemplateID = VehicleProfileTemplate.customProfileID
        profileEditorDraft.resetForCreate(displayUnits: displayUnits)
        profileEditorMode = .create
    }

    private func presentEditVehicleProfileSheet(_ profile: VehicleProfile) {
        selectedVehicleProfileTemplateBrand = VehicleProfileTemplate.customProfileID
        selectedVehicleProfileTemplateID = VehicleProfileTemplate.customProfileID
        profileEditorDraft.load(profile, displayUnits: displayUnits)
        profileEditorMode = .edit(profile)
    }

    private func applySelectedVehicleProfileTemplateBrand(_ brand: String) {
        selectedVehicleProfileTemplateBrand = brand

        guard brand != VehicleProfileTemplate.customProfileID else {
            selectedVehicleProfileTemplateID = VehicleProfileTemplate.customProfileID
            profileEditorDraft.resetForCreate(displayUnits: displayUnits)
            return
        }

        let templates = VehicleProfileTemplate.templates(forBrand: brand)
        if let selectedTemplate = templates.first(where: { $0.id == selectedVehicleProfileTemplateID }) {
            applySelectedVehicleProfileTemplate(id: selectedTemplate.id)
        } else if let firstTemplate = templates.first {
            applySelectedVehicleProfileTemplate(id: firstTemplate.id)
        }
    }

    private func applySelectedVehicleProfileTemplate(id: String) {
        selectedVehicleProfileTemplateID = id

        guard id != VehicleProfileTemplate.customProfileID else {
            selectedVehicleProfileTemplateBrand = VehicleProfileTemplate.customProfileID
            profileEditorDraft.resetForCreate(displayUnits: displayUnits)
            return
        }

        if let template = VehicleProfileTemplate.template(id: id) {
            selectedVehicleProfileTemplateBrand = template.brand
            profileEditorDraft.apply(template, displayUnits: displayUnits)
        }
    }

    private func saveVehicleProfileEditor(mode: VehicleProfileEditorMode) {
        guard let usableBatteryKWh = profileEditorDraft.usableBatteryKWh,
              let wltpRangeKm = profileEditorDraft.wltpRangeKm(displayUnits: displayUnits),
              let peakDCChargingKW = profileEditorDraft.peakDCChargingKW else {
            return
        }

        switch mode {
        case .create:
            let profile = VehicleProfileStore.createCustomProfile(
                displayName: profileEditorDraft.displayName,
                usableBatteryKWh: usableBatteryKWh,
                wltpRangeKm: wltpRangeKm,
                peakDCChargingKW: peakDCChargingKW,
                batteryDegradationPercent: batteryDegradationPercent
            )
            customVehicleProfiles = VehicleProfileStore.loadCustomProfiles()
            selectCustomVehicleProfile(profile)
        case .edit(let profile):
            VehicleProfileStore.updateCustomProfile(
                profile,
                displayName: profileEditorDraft.displayName,
                usableBatteryKWh: usableBatteryKWh,
                wltpRangeKm: wltpRangeKm,
                peakDCChargingKW: peakDCChargingKW
            )
            customVehicleProfiles = VehicleProfileStore.loadCustomProfiles()

            if selectedVehicleProfileID == profile.id,
               let updatedProfile = customVehicleProfiles.first(where: { $0.id == profile.id }) {
                selectCustomVehicleProfile(updatedProfile)
            }
        }

        profileEditorMode = nil
    }

    private func deletePendingVehicleProfile() {
        guard let profile = pendingDeletedVehicleProfile else {
            return
        }

        VehicleProfileStore.deleteCustomProfile(id: profile.id)
        var overrides = averageChargingSpeedOverridesByProfileID
        overrides.removeValue(forKey: profile.id)
        averageChargingSpeedOverridesByProfileID = overrides
        var referenceOverrides = referenceConsumptionOverridesByProfileID
        referenceOverrides.removeValue(forKey: profile.id)
        referenceConsumptionOverridesByProfileID = referenceOverrides
        var motorwaySpeedOverrides = motorwaySpeedOverridesByProfileID
        motorwaySpeedOverrides.removeValue(forKey: profile.id)
        motorwaySpeedOverridesByProfileID = motorwaySpeedOverrides
        var airConditioningOverrides = airConditioningModeOverridesByProfileID
        airConditioningOverrides.removeValue(forKey: profile.id)
        airConditioningModeOverridesByProfileID = airConditioningOverrides
        var tyreSetOverrides = selectedTyreSetOverridesByProfileID
        tyreSetOverrides.removeValue(forKey: profile.id)
        selectedTyreSetOverridesByProfileID = tyreSetOverrides
        var summerTyreClassOverrides = summerTyreClassOverridesByProfileID
        summerTyreClassOverrides.removeValue(forKey: profile.id)
        summerTyreClassOverridesByProfileID = summerTyreClassOverrides
        var winterTyreClassOverrides = winterTyreClassOverridesByProfileID
        winterTyreClassOverrides.removeValue(forKey: profile.id)
        winterTyreClassOverridesByProfileID = winterTyreClassOverrides
        var minimumChargingOverrides = normalMinimumChargingPercentOverridesByProfileID
        minimumChargingOverrides.removeValue(forKey: profile.id)
        normalMinimumChargingPercentOverridesByProfileID = minimumChargingOverrides
        var fastChargeTargetOverrides = normalFastChargeTargetPercentOverridesByProfileID
        fastChargeTargetOverrides.removeValue(forKey: profile.id)
        normalFastChargeTargetPercentOverridesByProfileID = fastChargeTargetOverrides
        customVehicleProfiles = VehicleProfileStore.loadCustomProfiles()

        if selectedVehicleProfileID == profile.id {
            selectBuiltInMiniVehicleProfile()
        }

        pendingDeletedVehicleProfile = nil
    }

    private func syncExperimentalCustomEVValues(from profile: VehicleProfile) {
        experimentalUsableBatteryCapacityKWh = profile.usableBatteryKWh
        experimentalOfficialWLTPRangeKm = profile.wltpRangeKm
        experimentalMaximumDCChargingSpeedKW = profile.peakDCChargingKW
    }

    private func persistActiveVehicleProfileBatteryDegradation(defaults: UserDefaults = .standard) {
        if isCustomVehicleProfileSelected {
            VehicleProfileStore.updateCustomProfileBatteryDegradation(
                id: activeVehicleProfile.profile.id,
                batteryDegradationPercent: batteryDegradationPercent,
                defaults: defaults
            )
            customVehicleProfiles = VehicleProfileStore.loadCustomProfiles(defaults: defaults)
        } else {
            miniBatteryDegradationPercent = batteryDegradationPercent
        }
    }

    private func exportTripOutcomes() {
        guard !outcomes.isEmpty else {
            return
        }

        do {
            let csv = TripOutcomeCSV.generate(from: outcomes)
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("mini-trip-outcomes-\(Date().timeIntervalSince1970).csv")
            try csv.write(to: url, atomically: true, encoding: .utf8)
            csvExportFile = CSVExportFile(url: url)
        } catch {
            assertionFailure("Failed to export trip outcomes: \(error)")
        }
    }

    private func parsedPositiveDouble(_ text: String) -> Double? {
        guard let value = parsedDouble(text), value > 0 else {
            return nil
        }
        return value
    }

    private func parsedPercent(_ text: String) -> Double? {
        guard let value = parsedDouble(text), (0...100).contains(value) else {
            return nil
        }
        return value
    }

    private func parsedDouble(_ text: String) -> Double? {
        let normalized = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        return Double(normalized)
    }
}

#if canImport(MapKit)
private struct TripRoutePreviewView: View {
    let route: TripRouteDescription
    let routePolyline: MKPolyline?
    let needsCharging: Bool
    let selectedPlan: TripChargingOptionPlan?
    let onPlanRouteToCoordinate: (CLLocationCoordinate2D, String) -> Void
    let onSearchChargersNearby: (CLLocationCoordinate2D) -> Void
    @State private var mapPosition: MapCameraPosition
    @State private var latestMapTouchPoint: CGPoint?
    @State private var selectedContextCoordinate: CLLocationCoordinate2D?
    @State private var isContextDialogPresented = false
    @State private var isRouteMapExpanded = false
    @State private var routeMapWidth: CGFloat = 0

    private let compactRouteMapHeight: CGFloat = 170

    init(
        route: TripRouteDescription,
        routePolyline: MKPolyline?,
        needsCharging: Bool,
        selectedPlan: TripChargingOptionPlan?,
        onPlanRouteToCoordinate: @escaping (CLLocationCoordinate2D, String) -> Void,
        onSearchChargersNearby: @escaping (CLLocationCoordinate2D) -> Void
    ) {
        self.route = route
        self.routePolyline = routePolyline
        self.needsCharging = needsCharging
        self.selectedPlan = selectedPlan
        self.onPlanRouteToCoordinate = onPlanRouteToCoordinate
        self.onSearchChargersNearby = onSearchChargersNearby
        _mapPosition = State(initialValue: Self.mapPosition(for: routePolyline))
    }

    private var hasRenderableRoute: Bool {
        guard let routePolyline else {
            return false
        }

        return !route.destination.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && routePolyline.pointCount > 1
            && routePolyline.boundingMapRect.size.width.isFinite
            && routePolyline.boundingMapRect.size.height.isFinite
    }

    private var stopAnnotations: [TripRouteStopAnnotation] {
        guard needsCharging, let selectedPlan else {
            return []
        }

        guard let routePolyline else {
            return []
        }

        return selectedPlan.stopDistancesKm.enumerated().compactMap { index, distanceKm in
            guard let coordinate = RoutePolylineDistance.coordinate(on: routePolyline, atDistanceKm: distanceKm) else {
                return nil
            }

            return TripRouteStopAnnotation(
                index: index + 1,
                distanceKm: distanceKm,
                coordinate: coordinate
            )
        }
    }

    private var routeCoordinates: [CLLocationCoordinate2D] {
        guard let routePolyline else {
            return []
        }

        let pointCount = routePolyline.pointCount
        guard pointCount > 1 else {
            return []
        }

        var coordinates = Array(repeating: kCLLocationCoordinate2DInvalid, count: pointCount)
        routePolyline.getCoordinates(&coordinates, range: NSRange(location: 0, length: pointCount))
        return coordinates.filter(CLLocationCoordinate2DIsValid)
    }

    private var startCoordinate: CLLocationCoordinate2D? {
        routeCoordinates.first
    }

    private var destinationCoordinate: CLLocationCoordinate2D? {
        routeCoordinates.last
    }

    private var routeMapIdentity: String {
        Self.mapIdentity(for: route, routePolyline: routePolyline)
    }

    private var captionText: String {
        guard needsCharging else {
            return "No charging stop estimated for this trip."
        }

        guard !stopAnnotations.isEmpty else {
            return "Estimated charging stop areas unavailable for this option."
        }

        return "Estimated charging stop areas, not charger stations."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Route preview", systemImage: "map")
                .font(.subheadline.weight(.semibold))

            if hasRenderableRoute {
                routeMap
            }

            Text(captionText)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .onAppear(perform: resetMapPosition)
        .onChange(of: routeMapIdentity) {
            resetMapPosition()
        }
        .confirmationDialog(
            "Map point",
            isPresented: $isContextDialogPresented,
            titleVisibility: .visible
        ) {
            Button("New trip to this point") {
                guard let selectedContextCoordinate else {
                    return
                }

                onPlanRouteToCoordinate(
                    selectedContextCoordinate,
                    Self.coordinateDestinationLabel(for: selectedContextCoordinate)
                )
                self.selectedContextCoordinate = nil
            }

            // TODO: Enable once trip planning supports intermediate MKDirections stops.
            Button("Add waypoint (coming soon)") {}
                .disabled(true)

            Button("Search chargers nearby") {
                guard let selectedContextCoordinate else {
                    return
                }

                onSearchChargersNearby(selectedContextCoordinate)
                self.selectedContextCoordinate = nil
            }

            Button("Cancel", role: .cancel) {
                selectedContextCoordinate = nil
            }
        } message: {
            if let selectedContextCoordinate {
                Text(Self.coordinateDestinationLabel(for: selectedContextCoordinate))
            }
        }
    }

    private var routeMap: some View {
        let mapHeight = isRouteMapExpanded ? max(compactRouteMapHeight, routeMapWidth) : compactRouteMapHeight

        return ZStack(alignment: .topTrailing) {
            if hasRenderableRoute, mapHeight > 1 {
                mapContent
                    .frame(maxWidth: .infinity)
                    .frame(height: mapHeight)
            } else {
                Color.clear
            }

            Button {
                withAnimation(.snappy(duration: 0.24)) {
                    isRouteMapExpanded.toggle()
                }
            } label: {
                Image(systemName: isRouteMapExpanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 32, height: 32)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.primary)
            .background(.ultraThinMaterial, in: Circle())
            .shadow(color: .black.opacity(0.16), radius: 4, y: 1)
            .padding(8)
            .accessibilityLabel(isRouteMapExpanded ? "Collapse route preview map" : "Expand route preview map")
            .accessibilityHint("Toggles the route preview map height.")
        }
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear {
                        routeMapWidth = proxy.size.width
                    }
                    .onChange(of: proxy.size.width) { _, newWidth in
                        routeMapWidth = newWidth
                    }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: mapHeight)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    @ViewBuilder
    private var mapContent: some View {
        if let routePolyline {
            MapReader { mapProxy in
                Map(position: $mapPosition, interactionModes: [.pan, .zoom]) {
                    MapPolyline(routePolyline)
                        .stroke(sliderAccentColor, lineWidth: 4)

                    if let startCoordinate {
                        Annotation("Start", coordinate: startCoordinate) {
                            routeEndpointMarker(color: .green, systemImage: "location.fill")
                        }
                    }

                    if let destinationCoordinate {
                        Annotation("Destination", coordinate: destinationCoordinate) {
                            routeEndpointMarker(color: .red, systemImage: "flag.fill")
                        }
                    }

                    ForEach(stopAnnotations) { annotation in
                        Annotation("Estimated stop \(annotation.index)", coordinate: annotation.coordinate) {
                            estimatedStopMarker(index: annotation.index)
                        }
                    }
                }
                .simultaneousGesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .local)
                        .onChanged { value in
                            latestMapTouchPoint = value.location
                        }
                )
                .simultaneousGesture(
                    LongPressGesture(minimumDuration: 0.55)
                        .onEnded { completed in
                            guard completed,
                                  let point = latestMapTouchPoint,
                                  let coordinate = mapProxy.convert(point, from: .local),
                                  Self.isValid(coordinate) else {
                                return
                            }

                            selectedContextCoordinate = coordinate
                            isContextDialogPresented = true
                        }
                )
            }
            .id(routeMapIdentity)
        } else {
            Color.clear
        }
    }

    private func resetMapPosition() {
        mapPosition = Self.mapPosition(for: routePolyline)
    }

    private static func mapPosition(for routePolyline: MKPolyline?) -> MapCameraPosition {
        guard let mapRect = paddedMapRect(for: routePolyline) else {
            return .automatic
        }

        return .rect(mapRect)
    }

    private static func paddedMapRect(for routePolyline: MKPolyline?) -> MKMapRect? {
        guard let routePolyline, routePolyline.pointCount > 1 else {
            return nil
        }

        let boundingMapRect = routePolyline.boundingMapRect
        guard boundingMapRect.origin.x.isFinite,
              boundingMapRect.origin.y.isFinite,
              boundingMapRect.size.width.isFinite,
              boundingMapRect.size.height.isFinite else {
            return nil
        }

        let centerCoordinate = MKMapPoint(x: boundingMapRect.midX, y: boundingMapRect.midY).coordinate
        let minimumPadding = MKMapPointsPerMeterAtLatitude(centerCoordinate.latitude) * 700
        let horizontalPadding = max(boundingMapRect.width * 0.18, minimumPadding)
        let verticalPadding = max(boundingMapRect.height * 0.24, minimumPadding)

        return boundingMapRect.insetBy(dx: -horizontalPadding, dy: -verticalPadding)
    }

    private static func coordinateDestinationLabel(for coordinate: CLLocationCoordinate2D) -> String {
        String(
            format: "%.5f, %.5f",
            locale: Locale(identifier: "en_US_POSIX"),
            coordinate.latitude,
            coordinate.longitude
        )
    }

    private static func isValid(_ coordinate: CLLocationCoordinate2D) -> Bool {
        CLLocationCoordinate2DIsValid(coordinate)
            && coordinate.latitude.isFinite
            && coordinate.longitude.isFinite
    }

    private static func mapIdentity(
        for route: TripRouteDescription,
        routePolyline: MKPolyline?
    ) -> String {
        guard let routePolyline else {
            return "missing-route-\(route.destination)"
        }

        let rect = routePolyline.boundingMapRect
        return [
            route.origin ?? "",
            route.destination,
            "\(routePolyline.pointCount)",
            String(format: "%.0f", rect.origin.x),
            String(format: "%.0f", rect.origin.y),
            String(format: "%.0f", rect.size.width),
            String(format: "%.0f", rect.size.height)
        ].joined(separator: "|")
    }

    private func routeEndpointMarker(color: Color, systemImage: String) -> some View {
        Image(systemName: systemImage)
            .font(.caption2.weight(.bold))
            .foregroundStyle(.white)
            .frame(width: 22, height: 22)
            .background(color, in: Circle())
            .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
    }

    private func estimatedStopMarker(index: Int) -> some View {
        Text("\(index)")
            .font(.caption2.weight(.bold))
            .foregroundStyle(.white)
            .frame(width: 24, height: 24)
            .background(sliderAccentColor, in: Circle())
            .overlay {
                Circle()
                    .stroke(.white, lineWidth: 2)
            }
            .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
    }
}

private struct TripRouteStopAnnotation: Identifiable {
    var id: Int { index }

    let index: Int
    let distanceKm: Double
    let coordinate: CLLocationCoordinate2D
}
#endif

@MainActor
final class RangeMapLocationProvider: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var coordinate: CLLocationCoordinate2D?
    @Published private(set) var authorizationStatus: CLAuthorizationStatus
    @Published private(set) var didFailLocation = false

    private let manager = CLLocationManager()
    private var didRequestAuthorization = false

    override init() {
        authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    var isLocationUnavailable: Bool {
        switch authorizationStatus {
        case .denied, .restricted:
            return true
        case .authorizedAlways, .authorizedWhenInUse:
            return didFailLocation && coordinate == nil
        case .notDetermined:
            return false
        @unknown default:
            return true
        }
    }

    func activateIfNeeded() {
        didFailLocation = false
        handleAuthorizationStatus(manager.authorizationStatus)
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            handleAuthorizationStatus(manager.authorizationStatus)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            coordinate = locations.last?.coordinate
            didFailLocation = false
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            didFailLocation = true
        }
    }

    private func handleAuthorizationStatus(_ status: CLAuthorizationStatus) {
        authorizationStatus = status

        switch status {
        case .notDetermined:
            guard !didRequestAuthorization else {
                return
            }

            didRequestAuthorization = true
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            manager.requestLocation()
        case .denied, .restricted:
            coordinate = nil
        @unknown default:
            coordinate = nil
            didFailLocation = true
        }
    }
}

struct RangeMapView: View {
    let estimatedRangeKm: Double
    @ObservedObject var locationProvider: RangeMapLocationProvider
    let autofitRequestID: Int
    let minimumFastChargingStopBatteryPercent: Double
    let showsChargingThresholdCircle: Bool
    @Binding var batteryPercent: Double
    let onPlanRouteToDestination: (CLLocationCoordinate2D) -> Void

    @State private var mapPosition: MapCameraPosition = .automatic
    @State private var isManualCamera = false
    @State private var isApplyingAutofit = false
    @State private var hasFittedInitialCamera = false
    @State private var selectedDestinationCoordinate: CLLocationCoordinate2D?
    @State private var latestMapTouchPoint: CGPoint?

    private let batteryPercentRange = 0.0...100.0
    // Compensates for straight-line map radius versus real road distance.
    private let rangeMapRadiusCorrectionFactor = 0.82

    private var coordinateIdentity: String {
        guard let coordinate = locationProvider.coordinate, Self.isValid(coordinate) else {
            return "missing"
        }

        return "\(coordinate.latitude),\(coordinate.longitude)"
    }

    private var rangeRadiusMeters: CLLocationDistance {
        max(0, estimatedRangeKm * rangeMapRadiusCorrectionFactor) * 1_000
    }

    private var chargingThresholdRadiusMeters: CLLocationDistance? {
        guard showsChargingThresholdCircle,
              batteryPercent > minimumFastChargingStopBatteryPercent else {
            return nil
        }

        let practicalRangeKm = estimatedRangeKm * (1 - minimumFastChargingStopBatteryPercent / batteryPercent)
        return max(0, practicalRangeKm * rangeMapRadiusCorrectionFactor) * 1_000
    }

    private var rangeHaloRadiusMeters: CLLocationDistance {
        rangeRadiusMeters * 1.02
    }

    private var cameraFitRadiusMeters: CLLocationDistance {
        max(0, estimatedRangeKm) * 1_000 * 0.95
    }

    private func reserveZonePolygon(
        center coordinate: CLLocationCoordinate2D,
        thresholdRadiusMeters: CLLocationDistance
    ) -> MKPolygon? {
        guard thresholdRadiusMeters > 0,
              thresholdRadiusMeters < rangeRadiusMeters else {
            return nil
        }

        return Self.circularBandPolygon(
            center: coordinate,
            innerRadiusMeters: thresholdRadiusMeters,
            outerRadiusMeters: rangeRadiusMeters
        )
    }

    var body: some View {
        ZStack {
            if let coordinate = locationProvider.coordinate, Self.isValid(coordinate) {
                MapReader { mapProxy in
                    Map(position: $mapPosition, interactionModes: [.pan, .zoom]) {
                        MapCircle(center: coordinate, radius: rangeHaloRadiusMeters)
                            .foregroundStyle(sliderAccentColor.opacity(0.13))

                        if let chargingThresholdRadiusMeters {
                            MapCircle(center: coordinate, radius: chargingThresholdRadiusMeters)
                                .foregroundStyle(sliderAccentColor.opacity(0.16))

                            if let reserveZonePolygon = reserveZonePolygon(
                                center: coordinate,
                                thresholdRadiusMeters: chargingThresholdRadiusMeters
                            ) {
                                MapPolygon(reserveZonePolygon)
                                    .foregroundStyle(Color.secondary.opacity(0.11))
                            }

                            MapCircle(center: coordinate, radius: rangeRadiusMeters)
                                .foregroundStyle(Color.clear)
                                .stroke(sliderAccentColor.opacity(0.30), lineWidth: 2)
                        } else {
                            MapCircle(center: coordinate, radius: rangeRadiusMeters)
                                .foregroundStyle(sliderAccentColor.opacity(0.16))
                                .stroke(sliderAccentColor.opacity(0.30), lineWidth: 2)
                        }

                        if let selectedDestinationCoordinate {
                            Marker("Destination", systemImage: "mappin", coordinate: selectedDestinationCoordinate)
                                .tint(sliderAccentColor)
                        }

                        UserAnnotation()
                    }
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 0, coordinateSpace: .local)
                            .onChanged { value in
                                latestMapTouchPoint = value.location
                            }
                    )
                    .simultaneousGesture(
                        LongPressGesture(minimumDuration: 0.55)
                            .onEnded { completed in
                                guard completed,
                                      let point = latestMapTouchPoint,
                                      let destination = mapProxy.convert(point, from: .local),
                                      Self.isValid(destination) else {
                                    return
                                }

                                selectedDestinationCoordinate = destination
                            }
                    )
                    .onMapCameraChange(frequency: .onEnd) { _ in
                        guard hasFittedInitialCamera, !isApplyingAutofit else {
                            return
                        }

                        isManualCamera = true
                    }
                }
            } else {
                mapFallbackContent
            }
        }
        .frame(maxWidth: .infinity)
        .overlay(alignment: .bottom) {
            if selectedDestinationCoordinate != nil {
                destinationSelectionCallout
                    .padding(.horizontal, 12)
                    .padding(.bottom, 64)
            }
        }
        .overlay(alignment: .bottom) {
            HStack(spacing: 8) {
                PrecisionNudgeButton(symbol: "−") {
                    batteryPercent = clampedBatteryPercent(batteryPercent - 1)
                }
                .accessibilityLabel("Decrease current battery level")
                .offset(y: 0)

                BatteryLevelSlider(value: $batteryPercent, range: batteryPercentRange)
                    .frame(width: 156, height: 34)

                PrecisionNudgeButton(symbol: "+") {
                    batteryPercent = clampedBatteryPercent(batteryPercent + 1)
                }
                .accessibilityLabel("Increase current battery level")
                .offset(y: 0)
            }
                .padding(.bottom, 14)
                .allowsHitTesting(selectedDestinationCoordinate == nil)
        }
        .onAppear {
            locationProvider.activateIfNeeded()
            fitCameraIfAllowed()
        }
        .onChange(of: coordinateIdentity) {
            fitCameraIfAllowed()
        }
        .onChange(of: estimatedRangeKm) {
            fitCameraIfAllowed()
        }
        .onChange(of: autofitRequestID) {
            isManualCamera = false
            fitCamera()
        }
    }

    private var destinationSelectionCallout: some View {
        HStack(spacing: 8) {
            Button("Plan route to this place") {
                if let selectedDestinationCoordinate {
                    onPlanRouteToDestination(selectedDestinationCoordinate)
                    self.selectedDestinationCoordinate = nil
                }
            }
            .buttonStyle(.borderedProminent)

            Button("Cancel") {
                selectedDestinationCoordinate = nil
            }
            .buttonStyle(.bordered)
        }
        .font(.caption.weight(.medium))
        .controlSize(.small)
        .padding(8)
        .background(.thinMaterial, in: Capsule())
    }

    private func clampedBatteryPercent(_ value: Double) -> Double {
        min(max(value, batteryPercentRange.lowerBound), batteryPercentRange.upperBound)
    }

    @ViewBuilder
    private var mapFallbackContent: some View {
        if locationProvider.isLocationUnavailable {
            Text("Enable location access to see your estimated range area.")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.secondarySystemGroupedBackground))
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.secondarySystemGroupedBackground))
        }
    }

    private func fitCameraIfAllowed() {
        guard !isManualCamera else {
            return
        }

        fitCamera()
    }

    private func fitCamera() {
        guard let coordinate = locationProvider.coordinate, Self.isValid(coordinate) else {
            return
        }

        let fittedMeters = max(cameraFitRadiusMeters * 2.4, 1_200)
        isApplyingAutofit = true
        hasFittedInitialCamera = true
        mapPosition = .region(
            MKCoordinateRegion(
                center: coordinate,
                latitudinalMeters: fittedMeters,
                longitudinalMeters: fittedMeters
            )
        )

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            isApplyingAutofit = false
        }
    }

    private static func isValid(_ coordinate: CLLocationCoordinate2D) -> Bool {
        CLLocationCoordinate2DIsValid(coordinate)
            && coordinate.latitude.isFinite
            && coordinate.longitude.isFinite
    }

    private static func circularBandPolygon(
        center: CLLocationCoordinate2D,
        innerRadiusMeters: CLLocationDistance,
        outerRadiusMeters: CLLocationDistance,
        segments: Int = 512
    ) -> MKPolygon {
        let outerCoordinates = circularCoordinates(
            center: center,
            radiusMeters: outerRadiusMeters,
            segments: segments
        )
        let innerCoordinates = circularCoordinates(
            center: center,
            radiusMeters: innerRadiusMeters,
            segments: segments
        )
        let innerPolygon = MKPolygon(coordinates: innerCoordinates, count: innerCoordinates.count)

        return MKPolygon(
            coordinates: outerCoordinates,
            count: outerCoordinates.count,
            interiorPolygons: [innerPolygon]
        )
    }

    private static func circularCoordinates(
        center: CLLocationCoordinate2D,
        radiusMeters: CLLocationDistance,
        segments: Int
    ) -> [CLLocationCoordinate2D] {
        let earthRadiusMeters = 6_371_000.0
        let angularDistance = radiusMeters / earthRadiusMeters
        let latitude = center.latitude * .pi / 180
        let longitude = center.longitude * .pi / 180

        return (0..<segments).map { index in
            let bearing = 2 * .pi * Double(index) / Double(segments)
            let destinationLatitude = asin(
                sin(latitude) * cos(angularDistance)
                    + cos(latitude) * sin(angularDistance) * cos(bearing)
            )
            let destinationLongitude = longitude + atan2(
                sin(bearing) * sin(angularDistance) * cos(latitude),
                cos(angularDistance) - sin(latitude) * sin(destinationLatitude)
            )

            return CLLocationCoordinate2D(
                latitude: destinationLatitude * 180 / .pi,
                longitude: destinationLongitude * 180 / .pi
            )
        }
    }
}

private struct RangeGaugeTick: Identifiable {
    enum Prominence {
        case major
        case minor
    }

    var id: Double { value }

    let value: Double
    let prominence: Prominence
}

struct RangeGaugeView: View {
    static let defaultScaleUpperBound = 260.0
    static let defaultWLTPReferenceRangeKm = 234.0

    let cautiousRangeKm: Double
    let normalRangeKm: Double
    let optimisticRangeKm: Double
    let expectedKWhPer100km: Double
    let usableBatteryKWh: Double
    let scaleUpperBound: Double
    let wltpReferenceRangeKm: Double
    let usesAdaptiveTickDensity: Bool
    let displayUnits: DisplayUnits
    @Binding var batteryPercent: Double

    private let scaleLowerBound = 0.0
    private let startAngle = -122.0
    private let endAngle = 122.0
    private let minimumUncertaintyAngle = 8.0
    private let batteryPercentRange = 0.0...100.0
    private var scaleTicks: [RangeGaugeTick] {
        guard usesReducedDensityTicks else {
            return Array(stride(from: 20.0, through: sanitizedScaleUpperBound, by: 20.0))
                .map { value in
                    RangeGaugeTick(
                        value: value,
                        prominence: value.truncatingRemainder(dividingBy: 40) == 20 ? .major : .minor
                    )
                }
        }

        return Array(stride(from: 50.0, through: sanitizedScaleUpperBound, by: 50.0))
            .map { value in
                RangeGaugeTick(
                    value: value,
                    prominence: value.truncatingRemainder(dividingBy: 100) == 0 ? .major : .minor
                )
            }
    }
    private var sanitizedScaleUpperBound: Double {
        max(20, scaleUpperBound.isFinite ? scaleUpperBound : Self.defaultScaleUpperBound)
    }
    private var usesReducedDensityTicks: Bool {
        usesAdaptiveTickDensity && sanitizedScaleUpperBound > Self.defaultScaleUpperBound
    }

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { proxy in
                let width = proxy.size.width
                let side = min(width, 338)
                let center = CGPoint(x: width / 2, y: side * 0.44)
                let radius = side * 0.36
                let labelRadius = radius + 19
                let tickOuterRadius = radius + 2
                let majorTickInnerRadius = radius - 11
                let minorTickInnerRadius = radius - 7
                let wltpLabelRadius = usesAdaptiveTickDensity ? radius + 42 : radius + 30
                let wltpMarkerAngle = angle(for: wltpReferenceRangeKm)
                let cautiousAngle = angle(for: cautiousRangeKm)
                let normalAngle = angle(for: normalRangeKm)
                let optimisticAngle = angle(for: optimisticRangeKm)
                let intervalStartAngle = min(cautiousAngle, optimisticAngle)
                let intervalEndAngle = max(cautiousAngle, optimisticAngle)
                let uncertaintyMidAngle = (intervalStartAngle + intervalEndAngle) / 2
                let uncertaintyHalfWidth = max((intervalEndAngle - intervalStartAngle) / 2, minimumUncertaintyAngle / 2)
                let fanStartAngle = max(startAngle, uncertaintyMidAngle - uncertaintyHalfWidth)
                let fanEndAngle = min(endAngle, uncertaintyMidAngle + uncertaintyHalfWidth)

                ZStack {
                    ZStack {
                        RangeGaugeArc(
                            center: center,
                            radius: radius,
                            startAngle: startAngle,
                            endAngle: endAngle
                        )
                        .stroke(
                            Color.secondary.opacity(0.18),
                            style: StrokeStyle(lineWidth: 14, lineCap: .round)
                        )

                        RangeGaugeArc(
                            center: center,
                            radius: radius,
                            startAngle: fanStartAngle,
                            endAngle: fanEndAngle
                        )
                        .stroke(
                            sliderAccentColor.opacity(0.16),
                            style: StrokeStyle(lineWidth: 20, lineCap: .round)
                        )
                        .blur(radius: 3)

                        RangeGaugeArc(
                            center: center,
                            radius: radius,
                            startAngle: fanStartAngle,
                            endAngle: fanEndAngle
                        )
                        .stroke(
                            sliderAccentColor.opacity(0.38),
                            style: StrokeStyle(lineWidth: 10, lineCap: .round)
                        )

                        RangeGaugeNeedleCone(
                            center: center,
                            innerRadius: 13,
                            outerRadius: radius - 2,
                            angle: normalAngle,
                            rangeStartAngle: fanStartAngle,
                            rangeEndAngle: fanEndAngle
                        )
                        .fill(sliderAccentColor.opacity(0.13))
                        .blur(radius: 0.7)

                        ForEach(scaleTicks) { tick in
                            let valueAngle = angle(for: tick.value)
                            let tickOpacity = tick.prominence == .major ? 0.56 : (usesReducedDensityTicks ? 0.34 : 0.36)
                            let tickLineWidth = tick.prominence == .major ? 2 : (usesReducedDensityTicks ? 1.25 : 1.3)
                            let labelSize = tick.prominence == .major || !usesReducedDensityTicks ? 11.0 : 10.0
                            let labelWeight: Font.Weight = tick.prominence == .major || !usesReducedDensityTicks ? .semibold : .medium
                            let labelOpacity = tick.prominence == .major ? 0.72 : (usesReducedDensityTicks ? 0.48 : 0.52)

                            NeedleShape(
                                center: point(
                                    for: valueAngle,
                                    radius: tick.prominence == .major ? majorTickInnerRadius : minorTickInnerRadius,
                                    center: center
                                ),
                                end: point(for: valueAngle, radius: tickOuterRadius, center: center)
                            )
                            .stroke(
                                Color.secondary.opacity(tickOpacity),
                                style: StrokeStyle(lineWidth: tickLineWidth, lineCap: .round)
                            )

                            Text(displayUnits.formatDistanceValue(fromKm: tick.value))
                                .font(.system(
                                    size: labelSize,
                                    weight: labelWeight,
                                    design: .rounded
                                ))
                                .foregroundStyle(.secondary.opacity(labelOpacity))
                                .position(point(for: valueAngle, radius: labelRadius, center: center))
                        }

                        NeedleShape(
                            center: point(for: wltpMarkerAngle, radius: radius + 7, center: center),
                            end: point(for: wltpMarkerAngle, radius: radius + 16, center: center)
                        )
                        .stroke(
                            Color.secondary.opacity(0.34),
                            style: StrokeStyle(lineWidth: 1.2, lineCap: .round)
                        )

                        Text("WLTP")
                            .font(.system(size: 9, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary.opacity(0.56))
                            .position(point(for: wltpMarkerAngle, radius: wltpLabelRadius, center: center))

                        NeedleShape(
                            center: center,
                            end: point(for: normalAngle, radius: radius - 31, center: center)
                        )
                        .stroke(
                            Color.primary.opacity(0.82),
                            style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
                        )

                        Circle()
                            .fill(Color(.secondarySystemGroupedBackground))
                            .frame(width: 24, height: 24)
                            .overlay(
                                Circle()
                                    .stroke(sliderAccentColor.opacity(0.65), lineWidth: 2.5)
                            )
                            .position(center)

                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(displayUnits.formatDistanceValue(fromKm: normalRangeKm))
                                .font(.system(size: 50, weight: .semibold, design: .rounded))
                                .foregroundStyle(.primary)
                            Text(displayUnits.distanceUnitLabel)
                                .font(.title3.weight(.medium))
                                .foregroundStyle(.secondary)
                                .frame(width: 34, alignment: .leading)
                        }
                        .position(x: center.x + 19, y: center.y + radius * 0.34)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Range gauge")
                    .accessibilityHint("Tap or drag the gauge arc to adjust the battery level needed for a target range.")
                    .accessibilityValue(
                        "Cautious \(displayUnits.formattedDistance(cautiousRangeKm)), normal \(displayUnits.formattedDistance(normalRangeKm)), optimistic \(displayUnits.formattedDistance(optimisticRangeKm))"
                    )

                    RangeGaugeArc(
                        center: center,
                        radius: radius,
                        startAngle: startAngle,
                        endAngle: endAngle
                    )
                    .stroke(
                        Color.primary.opacity(0.001),
                        style: StrokeStyle(lineWidth: 56, lineCap: .round)
                    )
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                updateBatteryPercent(for: value.location, center: center)
                            }
                    )
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Target range")
                    .accessibilityHint("Adjusts the current battery level required for the selected range.")

                    let batterySliderWidth = min(width * 0.50, 198)
                    HStack(spacing: 8) {
                        PrecisionNudgeButton(symbol: "−") {
                            batteryPercent = clampedBatteryPercent(batteryPercent - 1)
                        }
                        .accessibilityLabel("Decrease current battery level")
                        .offset(y: 0)

                        BatteryLevelSlider(value: $batteryPercent, range: batteryPercentRange)
                            .frame(width: batterySliderWidth, height: 56)

                        PrecisionNudgeButton(symbol: "+") {
                            batteryPercent = clampedBatteryPercent(batteryPercent + 1)
                        }
                        .accessibilityLabel("Increase current battery level")
                        .offset(y: 0)
                    }
                        .position(
                            x: center.x + BatteryLevelSlider.trailingLabelOffset,
                            y: center.y + radius * 0.91 - 3
                        )
                }
                .frame(width: width, height: proxy.size.height)
            }
            .frame(height: 276)

        }
        .frame(maxWidth: .infinity)
    }

    private func angle(for value: Double) -> Double {
        let clampedValue = min(max(value, scaleLowerBound), sanitizedScaleUpperBound)
        let progress = (clampedValue - scaleLowerBound) / (sanitizedScaleUpperBound - scaleLowerBound)
        return startAngle + progress * (endAngle - startAngle)
    }

    private func updateBatteryPercent(for location: CGPoint, center: CGPoint) {
        let targetRangeKm = range(for: angle(for: location, center: center))
        batteryPercent = batteryPercent(forTargetRangeKm: targetRangeKm)
    }

    private func angle(for location: CGPoint, center: CGPoint) -> Double {
        let deltaX = location.x - center.x
        let deltaY = center.y - location.y
        let angle = atan2(deltaX, deltaY) * 180 / .pi
        return min(max(angle, startAngle), endAngle)
    }

    private func range(for angle: Double) -> Double {
        let progress = (angle - startAngle) / (endAngle - startAngle)
        return scaleLowerBound + progress * (sanitizedScaleUpperBound - scaleLowerBound)
    }

    private func batteryPercent(forTargetRangeKm targetRangeKm: Double) -> Double {
        guard expectedKWhPer100km > 0 else {
            return batteryPercentRange.lowerBound
        }

        let targetEnergyKWh = max(0, targetRangeKm) * expectedKWhPer100km / 100
        let requiredPercent = targetEnergyKWh / usableBatteryKWh * 100
        let roundedPercent = requiredPercent.rounded()
        return min(max(roundedPercent, batteryPercentRange.lowerBound), batteryPercentRange.upperBound)
    }

    private func clampedBatteryPercent(_ value: Double) -> Double {
        min(max(value, batteryPercentRange.lowerBound), batteryPercentRange.upperBound)
    }

    private func point(for angle: Double, radius: Double, center: CGPoint) -> CGPoint {
        let radians = angle * .pi / 180
        return CGPoint(
            x: center.x + sin(radians) * radius,
            y: center.y - cos(radians) * radius
        )
    }

}

private struct PrecisionNudgeButton: View {
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(symbol)
                .font(.system(size: 17, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .frame(width: 25, height: 25)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct RangeGaugeArc: Shape {
    let center: CGPoint
    let radius: Double
    let startAngle: Double
    let endAngle: Double

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let steps = max(Int(abs(endAngle - startAngle) / 3), 1)

        for step in 0...steps {
            let progress = Double(step) / Double(steps)
            let angle = startAngle + (endAngle - startAngle) * progress
            let point = point(for: angle)

            if step == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }

        return path
    }

    private func point(for angle: Double) -> CGPoint {
        let radians = angle * .pi / 180
        return CGPoint(
            x: center.x + sin(radians) * radius,
            y: center.y - cos(radians) * radius
        )
    }
}

struct BatteryLevelSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>

    static let trailingLabelOffset = 0.0

    private let capWidth = 7.0
    private let outlineWidth = 3.0
    private let controlHeight = 31.0

    var body: some View {
        GeometryReader { proxy in
            let bodySlotWidth = max(proxy.size.width, 1)

            VStack(spacing: 1) {
                let bodyWidth = max(bodySlotWidth - capWidth - 2, 1)
                let fillProgress = progress(for: value)
                let fillWidth = max(0, (bodyWidth - outlineWidth * 2) * fillProgress)

                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(.systemGray6),
                                    Color(.systemGray5).opacity(0.58),
                                    Color(.systemGray6)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: bodyWidth, height: controlHeight)
                        .overlay(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .stroke(Color.secondary.opacity(0.18), lineWidth: outlineWidth)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .stroke(Color.white.opacity(0.20), lineWidth: 1)
                                .padding(1.5)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .stroke(
                                    LinearGradient(
                                        colors: [
                                            Color.black.opacity(0.12),
                                            Color.black.opacity(0.02),
                                            Color.white.opacity(0.12)
                                        ],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    ),
                                    lineWidth: 1
                                )
                        )

                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    sliderAccentColor.opacity(0.72),
                                    sliderAccentColor.opacity(0.96),
                                    sliderAccentColor.opacity(0.76)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: fillWidth, height: controlHeight - outlineWidth * 2)
                        .padding(.leading, outlineWidth)
                        .overlay(
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .stroke(Color.white.opacity(0.18), lineWidth: 0.8)
                                .padding(.leading, outlineWidth)
                        )

                    BatteryLevelDividers(outlineWidth: outlineWidth)
                        .frame(width: bodyWidth, height: controlHeight)
                        .mask(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .frame(width: fillWidth, height: controlHeight - outlineWidth * 2)
                                .padding(.leading, outlineWidth)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))

                    RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(.systemGray5),
                                    Color(.systemGray4),
                                    Color(.systemGray5)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: capWidth, height: controlHeight * 0.54)
                        .overlay(
                            RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                                .stroke(Color.secondary.opacity(0.20), lineWidth: 1)
                        )
                        .shadow(color: Color.black.opacity(0.08), radius: 1.5, x: 1, y: 1)
                        .offset(x: bodyWidth - 1)

                    Text("\(roundedPercentText(value))%")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .frame(width: bodyWidth, height: controlHeight)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { gesture in
                            updateValue(from: gesture.location.x, bodyWidth: bodyWidth)
                        }
                )
                .frame(width: bodySlotWidth, height: controlHeight)
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .center)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Current battery level")
        .accessibilityValue("\(roundedPercentText(value)) percent")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                value = clamped(value + 1)
            case .decrement:
                value = clamped(value - 1)
            @unknown default:
                break
            }
        }
    }

    private func progress(for value: Double) -> Double {
        (clamped(value) - range.lowerBound) / (range.upperBound - range.lowerBound)
    }

    private func updateValue(from locationX: Double, bodyWidth: Double) {
        let usableWidth = max(bodyWidth - outlineWidth * 2, 1)
        let progress = min(max((locationX - outlineWidth) / usableWidth, 0), 1)
        let rawValue = range.lowerBound + progress * (range.upperBound - range.lowerBound)
        value = clamped(rawValue.rounded())
    }

    private func clamped(_ value: Double) -> Double {
        min(max(value, range.lowerBound), range.upperBound)
    }

    private func roundedPercentText(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0)))
    }
}

private struct BatteryLevelDividers: View {
    let outlineWidth: Double

    var body: some View {
        GeometryReader { proxy in
            let innerWidth = max(proxy.size.width - outlineWidth * 2, 1)
            let innerHeight = max(proxy.size.height - outlineWidth * 2, 1)

            ZStack {
                ForEach(1..<10, id: \.self) { index in
                    let xPosition = outlineWidth + innerWidth * Double(index) / 10

                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.clear,
                                    Color.white.opacity(0.16),
                                    Color.black.opacity(0.10),
                                    Color.clear
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 0.8, height: innerHeight)
                        .position(x: xPosition, y: outlineWidth + innerHeight / 2)
                }
            }
            .allowsHitTesting(false)
        }
    }
}

struct RangeGaugeNeedleCone: Shape {
    let center: CGPoint
    let innerRadius: Double
    let outerRadius: Double
    let angle: Double
    let rangeStartAngle: Double
    let rangeEndAngle: Double

    private let innerHalfAngle = 2.2
    private let outerAnglePadding = 2.5

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let outerStartAngle = min(rangeStartAngle, rangeEndAngle) - outerAnglePadding
        let outerEndAngle = max(rangeStartAngle, rangeEndAngle) + outerAnglePadding
        let innerStartAngle = angle - innerHalfAngle
        let innerEndAngle = angle + innerHalfAngle
        let steps = max(Int(abs(outerEndAngle - outerStartAngle) / 2), 1)

        path.move(to: point(for: innerStartAngle, radius: innerRadius))
        path.addLine(to: point(for: outerStartAngle, radius: outerRadius))

        for step in 0...steps {
            let progress = Double(step) / Double(steps)
            let currentAngle = outerStartAngle + (outerEndAngle - outerStartAngle) * progress
            path.addLine(to: point(for: currentAngle, radius: outerRadius))
        }

        path.addLine(to: point(for: innerEndAngle, radius: innerRadius))
        path.closeSubpath()
        return path
    }

    private func point(for angle: Double, radius: Double) -> CGPoint {
        let radians = angle * .pi / 180
        return CGPoint(
            x: center.x + sin(radians) * radius,
            y: center.y - cos(radians) * radius
        )
    }
}

struct NeedleShape: Shape {
    let center: CGPoint
    let end: CGPoint

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: center)
        path.addLine(to: end)
        return path
    }
}

struct TripOutcome: Codable, Identifiable {
    private nonisolated static let legacyBatteryCapacityKWh = 26.0

    var id = UUID()
    let date: Date
    let vehicleProfileKind: VehicleProfileKind
    let predictedRangeKm: Double
    let predictedConsumptionKWhPer100Km: Double
    let actualConsumptionKWhPer100Km: Double?
    let actualDistanceKm: Double?
    let batteryStartPercent: Double?
    let batteryEndPercent: Double?
    let distanceKm: Double?
    let plannedDistanceKm: Double?
    let referenceConsumptionKWhPer100Km: Double?
    let currentBatteryPercent: Double?
    let motorwayShare: Double
    let roadTypeProfile: RoadTypeProfile
    let motorwaySpeedKmh: Double
    let temperatureC: Double
    let roadSurface: RoadSurface
    let windCondition: WindCondition
    let planningMode: PlanningMode?
    let airConditioningMode: AirConditioningMode?
    let tyreSet: TyreSet?
    let rollingResistanceClass: RollingResistanceClass?
    let winterTyres: Bool
    let note: String

    init(
        id: UUID = UUID(),
        date: Date,
        vehicleProfileKind: VehicleProfileKind = .mini,
        predictedRangeKm: Double,
        predictedConsumptionKWhPer100Km: Double,
        actualConsumptionKWhPer100Km: Double?,
        actualDistanceKm: Double?,
        batteryStartPercent: Double?,
        batteryEndPercent: Double?,
        distanceKm: Double?,
        plannedDistanceKm: Double?,
        referenceConsumptionKWhPer100Km: Double?,
        currentBatteryPercent: Double?,
        motorwayShare: Double,
        roadTypeProfile: RoadTypeProfile,
        motorwaySpeedKmh: Double,
        temperatureC: Double,
        roadSurface: RoadSurface,
        windCondition: WindCondition,
        planningMode: PlanningMode?,
        airConditioningMode: AirConditioningMode? = nil,
        tyreSet: TyreSet?,
        rollingResistanceClass: RollingResistanceClass?,
        winterTyres: Bool,
        note: String
    ) {
        self.id = id
        self.date = date
        self.vehicleProfileKind = vehicleProfileKind
        self.predictedRangeKm = predictedRangeKm
        self.predictedConsumptionKWhPer100Km = predictedConsumptionKWhPer100Km
        self.actualConsumptionKWhPer100Km = actualConsumptionKWhPer100Km
        self.actualDistanceKm = actualDistanceKm
        self.batteryStartPercent = batteryStartPercent
        self.batteryEndPercent = batteryEndPercent
        self.distanceKm = distanceKm
        self.plannedDistanceKm = plannedDistanceKm
        self.referenceConsumptionKWhPer100Km = referenceConsumptionKWhPer100Km
        self.currentBatteryPercent = currentBatteryPercent
        self.motorwayShare = motorwayShare
        self.roadTypeProfile = roadTypeProfile
        self.motorwaySpeedKmh = motorwaySpeedKmh
        self.temperatureC = temperatureC
        self.roadSurface = roadSurface
        self.windCondition = windCondition
        self.planningMode = planningMode
        self.airConditioningMode = airConditioningMode
        self.tyreSet = tyreSet
        self.rollingResistanceClass = rollingResistanceClass
        self.winterTyres = winterTyres
        self.note = note
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case date
        case vehicleProfileKind
        case predictedRangeKm
        case predictedConsumptionKWhPer100Km
        case actualConsumptionKWhPer100Km
        case actualDistanceKm
        case batteryStartPercent
        case batteryEndPercent
        case distanceKm
        case plannedDistanceKm
        case referenceConsumptionKWhPer100Km
        case currentBatteryPercent
        case motorwayShare
        case roadTypeProfile
        case motorwaySpeedKmh
        case temperatureC
        case roadSurface
        case windCondition
        case planningMode
        case airConditioningMode
        case tyreSet
        case rollingResistanceClass
        case winterTyres
        case note
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let legacyMotorwayShare = try container.decodeIfPresent(Double.self, forKey: .motorwayShare)
        let decodedRoadTypeProfile = try container.decodeIfPresent(RoadTypeProfile.self, forKey: .roadTypeProfile)
        let resolvedRoadTypeProfile = decodedRoadTypeProfile
            ?? legacyMotorwayShare.map(RoadTypeProfile.init(legacyMotorwayShare:))
            ?? .motorwayMix

        self.init(
            id: try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID(),
            date: try container.decode(Date.self, forKey: .date),
            vehicleProfileKind: try container.decodeIfPresent(VehicleProfileKind.self, forKey: .vehicleProfileKind) ?? .mini,
            predictedRangeKm: try container.decode(Double.self, forKey: .predictedRangeKm),
            predictedConsumptionKWhPer100Km: try container.decode(Double.self, forKey: .predictedConsumptionKWhPer100Km),
            actualConsumptionKWhPer100Km: try container.decodeIfPresent(Double.self, forKey: .actualConsumptionKWhPer100Km),
            actualDistanceKm: try container.decodeIfPresent(Double.self, forKey: .actualDistanceKm),
            batteryStartPercent: try container.decodeIfPresent(Double.self, forKey: .batteryStartPercent),
            batteryEndPercent: try container.decodeIfPresent(Double.self, forKey: .batteryEndPercent),
            distanceKm: try container.decodeIfPresent(Double.self, forKey: .distanceKm),
            plannedDistanceKm: try container.decodeIfPresent(Double.self, forKey: .plannedDistanceKm),
            referenceConsumptionKWhPer100Km: try container.decodeIfPresent(Double.self, forKey: .referenceConsumptionKWhPer100Km),
            currentBatteryPercent: try container.decodeIfPresent(Double.self, forKey: .currentBatteryPercent),
            motorwayShare: legacyMotorwayShare ?? resolvedRoadTypeProfile.legacyMotorwayShare,
            roadTypeProfile: resolvedRoadTypeProfile,
            motorwaySpeedKmh: try container.decode(Double.self, forKey: .motorwaySpeedKmh),
            temperatureC: try container.decode(Double.self, forKey: .temperatureC),
            roadSurface: try container.decode(RoadSurface.self, forKey: .roadSurface),
            windCondition: try container.decode(WindCondition.self, forKey: .windCondition),
            planningMode: try container.decodeIfPresent(PlanningMode.self, forKey: .planningMode),
            airConditioningMode: try container.decodeIfPresent(AirConditioningMode.self, forKey: .airConditioningMode),
            tyreSet: try container.decodeIfPresent(TyreSet.self, forKey: .tyreSet),
            rollingResistanceClass: try container.decodeIfPresent(RollingResistanceClass.self, forKey: .rollingResistanceClass),
            winterTyres: try container.decodeIfPresent(Bool.self, forKey: .winterTyres) ?? false,
            note: try container.decodeIfPresent(String.self, forKey: .note) ?? ""
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(date, forKey: .date)
        try container.encode(vehicleProfileKind, forKey: .vehicleProfileKind)
        try container.encode(predictedRangeKm, forKey: .predictedRangeKm)
        try container.encode(predictedConsumptionKWhPer100Km, forKey: .predictedConsumptionKWhPer100Km)
        try container.encodeIfPresent(actualConsumptionKWhPer100Km, forKey: .actualConsumptionKWhPer100Km)
        try container.encodeIfPresent(actualDistanceKm, forKey: .actualDistanceKm)
        try container.encodeIfPresent(batteryStartPercent, forKey: .batteryStartPercent)
        try container.encodeIfPresent(batteryEndPercent, forKey: .batteryEndPercent)
        try container.encodeIfPresent(distanceKm, forKey: .distanceKm)
        try container.encodeIfPresent(plannedDistanceKm, forKey: .plannedDistanceKm)
        try container.encodeIfPresent(referenceConsumptionKWhPer100Km, forKey: .referenceConsumptionKWhPer100Km)
        try container.encodeIfPresent(currentBatteryPercent, forKey: .currentBatteryPercent)
        try container.encode(motorwayShare, forKey: .motorwayShare)
        try container.encode(roadTypeProfile, forKey: .roadTypeProfile)
        try container.encode(motorwaySpeedKmh, forKey: .motorwaySpeedKmh)
        try container.encode(temperatureC, forKey: .temperatureC)
        try container.encode(roadSurface, forKey: .roadSurface)
        try container.encode(windCondition, forKey: .windCondition)
        try container.encodeIfPresent(airConditioningMode, forKey: .airConditioningMode)
        try container.encodeIfPresent(tyreSet, forKey: .tyreSet)
        try container.encodeIfPresent(rollingResistanceClass, forKey: .rollingResistanceClass)
        try container.encode(winterTyres, forKey: .winterTyres)
        try container.encode(note, forKey: .note)
    }

    nonisolated var resolvedTyreSet: TyreSet {
        tyreSet ?? (winterTyres ? .winter : .summer)
    }

    nonisolated var resolvedActualConsumptionKWhPer100Km: Double? {
        if let actualConsumptionKWhPer100Km {
            return actualConsumptionKWhPer100Km
        }

        guard
            let distanceKm,
            let batteryStartPercent,
            let batteryEndPercent,
            distanceKm > 0,
            batteryEndPercent <= batteryStartPercent,
            (0...100).contains(batteryStartPercent),
            (0...100).contains(batteryEndPercent)
        else {
            return nil
        }

        let batteryUsedPercent = batteryStartPercent - batteryEndPercent
        let actualKWhUsed = Self.legacyBatteryCapacityKWh * (batteryUsedPercent / 100)
        return actualKWhUsed / distanceKm * 100
    }

    nonisolated var calibrationDistanceKm: Double? {
        actualDistanceKm ?? distanceKm
    }

    nonisolated var loggedOutcomeDistanceKm: Double? {
        actualDistanceKm ?? distanceKm
    }

    nonisolated var editableLoggedDistanceKm: Double? {
        loggedOutcomeDistanceKm
    }

    nonisolated var isEligibleForCalibration: Bool {
        guard let calibrationDistanceKm else {
            return false
        }

        return calibrationDistanceKm >= CalibrationTripQuality.minimumCalibrationTripDistanceKm(
            for: roadTypeProfile
        )
    }

    nonisolated var normalBaselinePredictedConsumptionKWhPer100Km: Double {
        fixedCalibrationBaselinePredictedConsumptionKWhPer100Km ?? predictedConsumptionKWhPer100Km
    }

    nonisolated var fixedCalibrationBaselinePredictedConsumptionKWhPer100Km: Double? {
        guard let calibrationDistanceKm else {
            return nil
        }

        return MiniConsumptionCalculator.calculateForecast(
            referenceConsumption: fixedCalibrationBaselineReferenceConsumptionKWhPer100Km,
            distance: calibrationDistanceKm,
            temperature: temperatureC,
            roadTypeProfile: roadTypeProfile,
            motorwaySpeed: motorwaySpeedKmh,
            roadSurface: roadSurface,
            windCondition: windCondition,
            planningMode: .normal,
            rollingResistanceClass: rollingResistanceClass ?? .b
        )
        .finalKWhPer100km
    }

    private nonisolated var fixedCalibrationBaselineReferenceConsumptionKWhPer100Km: Double {
        switch vehicleProfileKind {
        case .mini:
            MiniConsumptionCalculator.continuousCalibrationBaseReferenceConsumptionKWhPer100Km
        case .customEV:
            referenceConsumptionKWhPer100Km ?? predictedConsumptionKWhPer100Km
        }
    }

    func updatingEditableAssumptions(
        temperatureC: Double,
        roadSurface: RoadSurface,
        windCondition: WindCondition,
        roadTypeProfile: RoadTypeProfile,
        motorwaySpeedKmh: Double,
        rollingResistanceClass: RollingResistanceClass,
        storedDistanceKm: Double?,
        note: String
    ) -> TripOutcome {
        let updatedLoggedDistanceKm = loggedOutcomeDistanceKm == nil ? nil : storedDistanceKm

        return TripOutcome(
            id: id,
            date: date,
            vehicleProfileKind: vehicleProfileKind,
            predictedRangeKm: predictedRangeKm,
            predictedConsumptionKWhPer100Km: predictedConsumptionKWhPer100Km,
            actualConsumptionKWhPer100Km: actualConsumptionKWhPer100Km,
            actualDistanceKm: loggedOutcomeDistanceKm == nil ? actualDistanceKm : updatedLoggedDistanceKm,
            batteryStartPercent: batteryStartPercent,
            batteryEndPercent: batteryEndPercent,
            distanceKm: loggedOutcomeDistanceKm == nil ? distanceKm : updatedLoggedDistanceKm,
            plannedDistanceKm: plannedDistanceKm,
            referenceConsumptionKWhPer100Km: referenceConsumptionKWhPer100Km,
            currentBatteryPercent: currentBatteryPercent,
            motorwayShare: roadTypeProfile.legacyMotorwayShare,
            roadTypeProfile: roadTypeProfile,
            motorwaySpeedKmh: MiniConsumptionDefaults.normalizedMotorwaySpeed(motorwaySpeedKmh),
            temperatureC: temperatureC,
            roadSurface: roadSurface,
            windCondition: windCondition,
            planningMode: planningMode,
            airConditioningMode: airConditioningMode,
            tyreSet: tyreSet,
            rollingResistanceClass: rollingResistanceClass,
            winterTyres: winterTyres,
            note: note
        )
    }
}

private struct TripOutcomeInput {
    let actualConsumptionKWhPer100Km: Double
    let actualDistanceKm: Double?
}

struct CalibrationPredictionContext {
    let roadTypeProfile: RoadTypeProfile
    let tyreSet: TyreSet
}

struct CalibrationCorrection {
    enum Source {
        case manual
        case global
        case drivingMode
    }

    let source: Source
    let roadTypeProfile: RoadTypeProfile
    let tyreSet: TyreSet
    let usableRecordCount: Int
    // Overall calibration learned from the balanced global sample.
    let globalFactor: Double
    // Relative adjustment for this road type, multiplied with globalFactor.
    let modeDeviationFactor: Double?

    var totalFactor: Double {
        Self.clamp(globalFactor * (modeDeviationFactor ?? 1), to: 0.85...1.20)
    }

    var canApply: Bool {
        source != .manual
    }

    var displaySourceLabel: String {
        displaySourceLabel(for: .mini)
    }

    func displaySourceLabel(for vehicleProfileKind: VehicleProfileKind) -> String {
        switch source {
        case .manual:
            vehicleProfileKind == .customEV ? "Custom profile calibration" : "Reference value"
        case .global:
            switch vehicleProfileKind {
            case .mini:
                "\(tyreSet.label) tyre calibration"
            case .customEV:
                "Custom profile \(tyreSet.label) calibration"
            }
        case .drivingMode:
            switch vehicleProfileKind {
            case .mini:
                "\(tyreSet.label) + route type calibration"
            case .customEV:
                "Custom profile \(tyreSet.label) + route type calibration"
            }
        }
    }

    private nonisolated static func clamp(_ value: Double, to range: ClosedRange<Double>) -> Double {
        min(max(value, range.lowerBound), range.upperBound)
    }
}

fileprivate enum CalibrationTripExclusionReason: Hashable {
    case missingDistance
    case tooShort
    case missingActualConsumption
    case invalidActualConsumption
    case unrealisticActualConsumption
    case missingPredictedBaseline

    var label: String {
        switch self {
        case .missingDistance:
            "Missing distance"
        case .tooShort:
            "Under 15 km"
        case .missingActualConsumption:
            "Missing consumption"
        case .invalidActualConsumption:
            "Invalid consumption"
        case .unrealisticActualConsumption:
            "Outside calibration range"
        case .missingPredictedBaseline:
            "Missing baseline"
        }
    }

    nonisolated var displayReason: String {
        switch self {
        case .missingDistance:
            "Missing distance"
        case .tooShort:
            "Too short for calibration"
        case .missingActualConsumption:
            "Missing consumption data"
        case .invalidActualConsumption:
            "Invalid consumption data"
        case .unrealisticActualConsumption:
            "Consumption outside calibration range"
        case .missingPredictedBaseline:
            "Missing forecast baseline"
        }
    }
}

fileprivate struct CalibrationExclusionSummary: Identifiable {
    let reason: CalibrationTripExclusionReason
    let count: Int

    var id: String {
        reason.label
    }
}

fileprivate struct CalibrationTripEligibilityDisplay {
    let eligible: Bool
    let displayReason: String?
}

fileprivate enum CalibrationTripEligibility {
    nonisolated static func coreExclusionReason(for outcome: TripOutcome) -> CalibrationTripExclusionReason? {
        guard let calibrationDistanceKm = outcome.calibrationDistanceKm else {
            return .missingDistance
        }

        let minimumDistanceKm = CalibrationTripQuality.minimumCalibrationTripDistanceKm(
            for: outcome.roadTypeProfile
        )
        guard calibrationDistanceKm >= minimumDistanceKm else {
            return .tooShort
        }

        guard let actualConsumptionKWhPer100Km = outcome.resolvedActualConsumptionKWhPer100Km else {
            return .missingActualConsumption
        }

        guard actualConsumptionKWhPer100Km > 0 else {
            return .invalidActualConsumption
        }

        guard (4...45).contains(actualConsumptionKWhPer100Km) else {
            return .unrealisticActualConsumption
        }

        guard
            let fixedBaseline = outcome.fixedCalibrationBaselinePredictedConsumptionKWhPer100Km,
            fixedBaseline > 0
        else {
            return .missingPredictedBaseline
        }

        return nil
    }

    nonisolated static func exclusionReason(for outcome: TripOutcome) -> CalibrationTripExclusionReason? {
        coreExclusionReason(for: outcome)
    }

    nonisolated static func display(for outcome: TripOutcome) -> CalibrationTripEligibilityDisplay {
        guard let exclusionReason = exclusionReason(for: outcome) else {
            return CalibrationTripEligibilityDisplay(eligible: true, displayReason: nil)
        }

        return CalibrationTripEligibilityDisplay(
            eligible: false,
            displayReason: exclusionReason.displayReason
        )
    }
}

struct ContinuousCalibrationSummary {
    private static let minimumValidTrips = 3
    private static let maximumCalibrationSampleCount = 10
    private static let globalShrinkageTripCount = 10.0

    let validTripCount: Int
    let meanFactor: Double
    let excludedTripCount: Int
    fileprivate let exclusionSummaries: [CalibrationExclusionSummary]
    private let samples: [CalibrationFactorSample]
    private let tyreSamples: [TyreSet: [CalibrationFactorSample]]
    private let tyreModeSamples: [TyreSet: [RoadTypeProfile: [CalibrationFactorSample]]]

    var canApply: Bool {
        validTripCount >= Self.minimumValidTrips
    }

    func hasMultipleActiveRoadTypeProfiles(for tyreSet: TyreSet) -> Bool {
        tyreModeSamples[tyreSet, default: [:]].values
            .filter { $0.count >= Self.minimumValidTrips }
            .count >= 2
    }

    var globalCorrectionFactor: Double {
        guard canApply else {
            return 1
        }

        let weight = min(1, Double(validTripCount) / Self.globalShrinkageTripCount)
        return Self.clamp(1 + weight * (meanFactor - 1), to: 0.88...1.15)
    }

    func correction(for context: CalibrationPredictionContext) -> CalibrationCorrection {
        let contextTyreSamples = tyreSamples[context.tyreSet] ?? []
        let contextModeSamples = tyreModeSamples[context.tyreSet]?[context.roadTypeProfile] ?? []
        let contextMeanFactor = Self.meanFactor(in: contextTyreSamples) ?? 1
        let contextGlobalFactor = Self.globalCorrectionFactor(
            meanFactor: contextMeanFactor,
            count: contextTyreSamples.count
        )
        let contextCanApply = contextTyreSamples.count >= Self.minimumValidTrips

        if contextModeSamples.count >= Self.minimumValidTrips,
           let modeMean = Self.meanFactor(in: contextModeSamples),
           let modeDeviationFactor = Self.modeDeviationFactor(
                modeMeanFactor: modeMean,
                globalMeanFactor: contextMeanFactor,
                count: contextModeSamples.count
           ) {
            return CalibrationCorrection(
                source: .drivingMode,
                roadTypeProfile: context.roadTypeProfile,
                tyreSet: context.tyreSet,
                usableRecordCount: contextModeSamples.count,
                globalFactor: contextGlobalFactor,
                modeDeviationFactor: modeDeviationFactor
            )
        }

        guard contextCanApply else {
            return CalibrationCorrection(
                source: .manual,
                roadTypeProfile: context.roadTypeProfile,
                tyreSet: context.tyreSet,
                usableRecordCount: contextTyreSamples.count,
                globalFactor: 1,
                modeDeviationFactor: nil
            )
        }

        return CalibrationCorrection(
            source: .global,
            roadTypeProfile: context.roadTypeProfile,
            tyreSet: context.tyreSet,
            usableRecordCount: contextTyreSamples.count,
            globalFactor: contextGlobalFactor,
            modeDeviationFactor: nil
        )
    }

    init(outcomes: [TripOutcome], vehicleProfileKind: VehicleProfileKind? = nil) {
        let filteredOutcomes = vehicleProfileKind.map { profileKind in
            outcomes.filter { $0.vehicleProfileKind == profileKind }
        } ?? outcomes
        let sortedOutcomes = filteredOutcomes.sorted { $0.date > $1.date }
        let exclusionReasons = sortedOutcomes.compactMap { outcome in
            CalibrationTripEligibility.exclusionReason(for: outcome)
        }

        let allUsableSamples: [CalibrationFactorSample] = sortedOutcomes.compactMap { outcome in
            guard CalibrationTripEligibility.exclusionReason(for: outcome) == nil else {
                return nil
            }

            return CalibrationFactorSample(outcome: outcome)
        }

        let cappedTyreModeSamples = Dictionary(
            uniqueKeysWithValues: TyreSet.allCases.map { tyreSet in
                let modeSamples = Dictionary(
                    uniqueKeysWithValues: RoadTypeProfile.allCases.map { roadTypeProfile in
                        let samples = Array(
                            allUsableSamples
                                .filter {
                                    $0.tyreSet == tyreSet
                                        && $0.roadTypeProfile == roadTypeProfile
                                }
                                .prefix(Self.maximumCalibrationSampleCount)
                        )
                        return (roadTypeProfile, samples)
                    }
                )
                return (tyreSet, modeSamples)
            }
        )

        let cappedTyreSamples = Dictionary(
            uniqueKeysWithValues: TyreSet.allCases.map { tyreSet in
                let samples = RoadTypeProfile.allCases.flatMap {
                    cappedTyreModeSamples[tyreSet]?[$0] ?? []
                }
                return (tyreSet, samples)
            }
        )

        tyreModeSamples = cappedTyreModeSamples
        tyreSamples = cappedTyreSamples
        samples = TyreSet.allCases.flatMap { cappedTyreSamples[$0] ?? [] }
        validTripCount = samples.count
        meanFactor = Self.meanFactor(in: samples) ?? 1
        excludedTripCount = exclusionReasons.count
        exclusionSummaries = Dictionary(grouping: exclusionReasons, by: { $0 })
            .map { reason, reasons in
                CalibrationExclusionSummary(reason: reason, count: reasons.count)
            }
            .sorted {
                if $0.count == $1.count {
                    return $0.reason.label < $1.reason.label
                }

                return $0.count > $1.count
            }
    }

    private static func globalCorrectionFactor(meanFactor: Double, count: Int) -> Double {
        let weight = min(1, Double(count) / globalShrinkageTripCount)
        return clamp(1 + weight * (meanFactor - 1), to: 0.88...1.15)
    }

    private static func modeDeviationFactor(
        modeMeanFactor: Double,
        globalMeanFactor: Double,
        count: Int
    ) -> Double? {
        guard globalMeanFactor > 0 else {
            return nil
        }

        let weight = min(1, Double(count) / globalShrinkageTripCount)
        let relativeDeviation = modeMeanFactor / globalMeanFactor
        return 1 + weight * (relativeDeviation - 1)
    }

    private static func meanFactor(in samples: [CalibrationFactorSample]) -> Double? {
        guard !samples.isEmpty else {
            return nil
        }

        return samples.reduce(0) { $0 + $1.factor } / Double(samples.count)
    }

    private static func clamp(_ value: Double, to range: ClosedRange<Double>) -> Double {
        min(max(value, range.lowerBound), range.upperBound)
    }
}

private struct CalibrationFactorSample {
    let factor: Double
    let roadTypeProfile: RoadTypeProfile
    let tyreSet: TyreSet

    nonisolated init?(outcome: TripOutcome) {
        guard
            case .none = CalibrationTripEligibility.coreExclusionReason(for: outcome),
            let actualConsumptionKWhPer100Km = outcome.resolvedActualConsumptionKWhPer100Km,
            let fixedBaseline = outcome.fixedCalibrationBaselinePredictedConsumptionKWhPer100Km,
            fixedBaseline > 0
        else {
            return nil
        }

        factor = actualConsumptionKWhPer100Km / fixedBaseline
        roadTypeProfile = outcome.roadTypeProfile
        tyreSet = outcome.resolvedTyreSet
    }
}

private struct CSVExportFile: Identifiable {
    let id = UUID()
    let url: URL
}

struct SavedDestination: Codable, Identifiable {
    var id = UUID()
    let name: String
    let destinationQuery: String

    var menuID: String {
        id.uuidString
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case destinationQuery
        case distanceKm
    }

    init(id: UUID = UUID(), name: String, destinationQuery: String) {
        self.id = id
        self.name = name
        self.destinationQuery = destinationQuery
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()

        let decodedName = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        name = decodedName

        if let decodedDestinationQuery = try container.decodeIfPresent(String.self, forKey: .destinationQuery) {
            destinationQuery = decodedDestinationQuery
        } else {
            destinationQuery = decodedName
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(destinationQuery, forKey: .destinationQuery)
    }
}

private struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

private enum TripOutcomeCSV {
    private nonisolated static let header = [
        "id",
        "date",
        "predictedRangeKm",
        "normalBaselinePredictedConsumptionKWhPer100Km",
        "actualConsumptionKWhPer100Km",
        "actualDistanceKm",
        "batteryStartPercent",
        "batteryEndPercent",
        "distanceKm",
        "plannedDistanceKm",
        "referenceConsumptionKWhPer100Km",
        "currentBatteryPercent",
        "motorwayShare",
        "roadTypeProfile",
        "motorwaySpeedKmh",
        "temperatureC",
        "roadSurface",
        "windCondition",
        "airConditioningMode",
        "tyreSet",
        "rollingResistanceClass",
        "winterTyres",
        "note"
    ]

    nonisolated static func generate(from outcomes: [TripOutcome]) -> String {
        var rows = [header.joined(separator: ",")]
        rows.append(contentsOf: outcomes.map(row(for:)))
        return rows.joined(separator: "\n") + "\n"
    }

    private nonisolated static func row(for outcome: TripOutcome) -> String {
        [
            outcome.id.uuidString,
            ISO8601DateFormatter().string(from: outcome.date),
            String(outcome.predictedRangeKm),
            String(outcome.normalBaselinePredictedConsumptionKWhPer100Km),
            optionalString(outcome.resolvedActualConsumptionKWhPer100Km),
            optionalString(outcome.actualDistanceKm),
            optionalString(outcome.batteryStartPercent),
            optionalString(outcome.batteryEndPercent),
            optionalString(outcome.distanceKm),
            optionalString(outcome.plannedDistanceKm),
            optionalString(outcome.referenceConsumptionKWhPer100Km),
            optionalString(outcome.currentBatteryPercent),
            String(outcome.motorwayShare),
            outcome.roadTypeProfile.rawValue,
            String(outcome.motorwaySpeedKmh),
            String(outcome.temperatureC),
            outcome.roadSurface.rawValue,
            outcome.windCondition.rawValue,
            outcome.airConditioningMode?.rawValue ?? "",
            outcome.resolvedTyreSet.rawValue,
            outcome.rollingResistanceClass?.rawValue ?? "",
            String(outcome.winterTyres),
            outcome.note
        ]
        .map(escape)
        .joined(separator: ",")
    }

    private nonisolated static func escape(_ value: String) -> String {
        let escapedValue = value.replacingOccurrences(of: "\"", with: "\"\"")
        let needsQuotes = escapedValue.contains(",")
            || escapedValue.contains("\"")
            || escapedValue.contains("\n")
            || escapedValue.contains("\r")

        return needsQuotes ? "\"\(escapedValue)\"" : escapedValue
    }

    private nonisolated static func optionalString(_ value: Double?) -> String {
        guard let value else {
            return ""
        }

        return String(value)
    }
}

enum TripOutcomeStore {
    private static let fileName = "trip-outcomes.json"

    static func load() -> [TripOutcome] {
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode([TripOutcome].self, from: data)
        } catch {
            return []
        }
    }

    static func save(_ outcomes: [TripOutcome]) {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(outcomes)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            assertionFailure("Failed to save trip outcomes: \(error)")
        }
    }

    private static var fileURL: URL {
        let documentsDirectory = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        )[0]
        return documentsDirectory.appendingPathComponent(fileName)
    }
}

enum SavedDestinationStore {
    private static let storageKey = "savedTrips"

    static func load(defaults: UserDefaults = .standard) -> [SavedDestination] {
        guard let data = defaults.data(forKey: storageKey) else {
            return []
        }

        do {
            return sanitized(try JSONDecoder().decode([SavedDestination].self, from: data))
        } catch {
            return []
        }
    }

    static func save(_ destinations: [SavedDestination], defaults: UserDefaults = .standard) {
        do {
            let data = try JSONEncoder().encode(destinations)
            defaults.set(data, forKey: storageKey)
        } catch {
            assertionFailure("Failed to save destinations: \(error)")
        }
    }

    static func sanitized(_ destinations: [SavedDestination]) -> [SavedDestination] {
        var seenIDs = Set<SavedDestination.ID>()

        return destinations.compactMap { destination in
            let name = destination.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let destinationQuery = destination.destinationQuery.trimmingCharacters(in: .whitespacesAndNewlines)
            guard destinationQuery.isEmpty == false,
                  seenIDs.insert(destination.id).inserted
            else {
                return nil
            }

            return SavedDestination(
                id: destination.id,
                name: name.isEmpty ? destinationQuery : name,
                destinationQuery: destinationQuery
            )
        }
    }
}

struct AboutAppGuideView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    guideSection {
                        Text("RangePilot helps electric vehicle drivers estimate real-world range and charging needs.")
                        Text("Adjust battery level and driving conditions to see how temperature, speed, wind, road surface, tyres, and other factors affect expected range.")
                        Text("Create custom vehicle profiles, log trips, and optionally calibrate estimates to match your own vehicle and driving habits over time.")
                        Text("The app focuses on quick, understandable estimates for everyday driving and simpler trip planning. It is intentionally lighter and simpler than full route-planning tools.")
                        Text("All data remains stored locally on your device.")
                        aboutLinksSection
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("About the app")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    private var aboutLinksSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Link("Website", destination: URL(string: "https://sites.google.com/view/mini-range/")!)
            Link("FAQ", destination: URL(string: "https://sites.google.com/view/mini-range/faq")!)
        }
        .font(.subheadline)
        .padding(.top, 8)
    }

    private func guideSection<Content: View>(
        title: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title {
                Text(title)
                    .font(.headline)
            }

            content()
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func guideItem(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
            Text(text)
        }
    }
}

private struct RangeConditionsCard: View {
    @Binding var roadTypeProfile: RoadTypeProfile
    let displayedTemperature: Binding<Double>
    let temperatureRange: ClosedRange<Double>
    let temperatureText: String
    let roadSurface: Binding<RoadSurface>
    @Binding var windCondition: WindCondition
    @Binding var isAdditionalSettingsExpanded: Bool
    let motorwaySpeed: Binding<Double>
    let motorwaySpeedRange: ClosedRange<Double>
    let motorwaySpeedText: String
    let motorwaySpeedDisabled: Bool
    @Binding var airConditioningMode: AirConditioningMode
    @Binding var trailerTowModeEnabled: Bool
    let trailerWeightKg: Binding<Double>
    let trailerWeightRange: ClosedRange<Double>
    let trailerWeightStep: Double
    let trailerWeightText: String
    @Binding var boxyTrailerEnabled: Bool
    @Binding var selectedTyreSet: TyreSet
    let rollingResistanceClass: Binding<RollingResistanceClass>
    let onTyreSetChanged: (TyreSet) -> Void

    var body: some View {
        RangeDrivingConditionsControlsView(
            roadTypeProfile: $roadTypeProfile,
            displayedTemperature: displayedTemperature,
            temperatureRange: temperatureRange,
            temperatureText: temperatureText,
            roadSurface: roadSurface,
            windCondition: $windCondition,
            isAdditionalSettingsExpanded: $isAdditionalSettingsExpanded,
            motorwaySpeed: motorwaySpeed,
            motorwaySpeedRange: motorwaySpeedRange,
            motorwaySpeedText: motorwaySpeedText,
            motorwaySpeedDisabled: motorwaySpeedDisabled,
            airConditioningMode: $airConditioningMode,
            trailerTowModeEnabled: $trailerTowModeEnabled,
            trailerWeightKg: trailerWeightKg,
            trailerWeightRange: trailerWeightRange,
            trailerWeightStep: trailerWeightStep,
            trailerWeightText: trailerWeightText,
            boxyTrailerEnabled: $boxyTrailerEnabled,
            selectedTyreSet: $selectedTyreSet,
            rollingResistanceClass: rollingResistanceClass,
            onTyreSetChanged: onTyreSetChanged
        )
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct RangeDrivingConditionsControlsView: View {
    @Binding var roadTypeProfile: RoadTypeProfile
    let displayedTemperature: Binding<Double>
    let temperatureRange: ClosedRange<Double>
    let temperatureText: String
    let roadSurface: Binding<RoadSurface>
    @Binding var windCondition: WindCondition
    @Binding var isAdditionalSettingsExpanded: Bool
    let motorwaySpeed: Binding<Double>
    let motorwaySpeedRange: ClosedRange<Double>
    let motorwaySpeedText: String
    let motorwaySpeedDisabled: Bool
    @Binding var airConditioningMode: AirConditioningMode
    @Binding var trailerTowModeEnabled: Bool
    let trailerWeightKg: Binding<Double>
    let trailerWeightRange: ClosedRange<Double>
    let trailerWeightStep: Double
    let trailerWeightText: String
    @Binding var boxyTrailerEnabled: Bool
    @Binding var selectedTyreSet: TyreSet
    let rollingResistanceClass: Binding<RollingResistanceClass>
    let onTyreSetChanged: (TyreSet) -> Void

    var body: some View {
        VStack(spacing: 18) {
            RangeRouteTypeSection(roadTypeProfile: $roadTypeProfile)

            RangeRoadSurfaceSection(roadSurface: roadSurface)

            RangeSliderSection(
                title: "Outdoor temperature",
                value: displayedTemperature,
                range: temperatureRange,
                step: 1,
                displayValue: temperatureText
            )

            Divider()

            DisclosureGroup(isExpanded: $isAdditionalSettingsExpanded) {
                VStack(alignment: .leading, spacing: 12) {
                    RangeSliderSection(
                        title: "Motorway speed",
                        value: motorwaySpeed,
                        range: motorwaySpeedRange,
                        step: 1,
                        displayValue: motorwaySpeedText
                    )
                    .disabled(motorwaySpeedDisabled)
                    .opacity(motorwaySpeedDisabled ? 0.45 : 1)

                    RangeWindSection(windCondition: $windCondition)

                    RangeAirConditioningSection(airConditioningMode: $airConditioningMode)

                    RangeTrailerTowSection(
                        isEnabled: $trailerTowModeEnabled,
                        weightKg: trailerWeightKg,
                        weightRange: trailerWeightRange,
                        weightStep: trailerWeightStep,
                        weightText: trailerWeightText,
                        boxyTrailerEnabled: $boxyTrailerEnabled
                    )

                    RangeTyreSection(
                        selectedTyreSet: $selectedTyreSet,
                        rollingResistanceClass: rollingResistanceClass,
                        onTyreSetChanged: onTyreSetChanged
                    )
                }
                .padding(.top, 8)
            } label: {
                Text("Additional settings")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
            }
            .tint(.secondary)
        }
    }
}

private struct RangeRouteTypeSection: View {
    @Binding var roadTypeProfile: RoadTypeProfile
    private let profiles: [RoadTypeProfile] = [.countryside, .cityMix, .motorwayMix, .motorway]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 0) {
                ForEach(profiles) { profile in
                    routeTypeButton(for: profile)
                }
            }
            .padding(2)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private func routeTypeButton(for profile: RoadTypeProfile) -> some View {
        Button {
            roadTypeProfile = profile
        } label: {
            Text(profile.label)
                .font(.caption.weight(.semibold))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.9)
                .frame(maxWidth: .infinity, minHeight: 38)
                .padding(.horizontal, 4)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(roadTypeProfile == profile ? .primary : .secondary)
        .background {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(.background)
                .shadow(color: .black.opacity(0.12), radius: 1, y: 1)
                .opacity(roadTypeProfile == profile ? 1 : 0)
        }
        .overlay(alignment: .trailing) {
            Divider()
                .padding(.vertical, 7)
                .opacity(profile == profiles.last ? 0 : 1)
        }
    }
}

private struct RangeSliderSection: View {
    let title: String
    let value: Binding<Double>
    let range: ClosedRange<Double>
    let step: Double
    let displayValue: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(displayValue)
                    .foregroundStyle(.secondary)
            }

            Slider(value: value, in: range, step: step)
                .tint(sliderAccentColor)
        }
    }
}

private struct RangeRoadSurfaceSection: View {
    let roadSurface: Binding<RoadSurface>

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Road surface condition", selection: roadSurface) {
                ForEach(RoadSurface.segmentedCases) { surface in
                    Text(surface.label).tag(surface as RoadSurface)
                }
            }
            .pickerStyle(.segmented)
        }
    }
}

private struct RangeWindSection: View {
    @Binding var windCondition: WindCondition

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Wind")
                .font(.subheadline.weight(.semibold))

            Picker("Wind", selection: $windCondition) {
                ForEach(WindCondition.rangeOrderedCases) { condition in
                    Text(condition.label).tag(condition as WindCondition)
                }
            }
            .pickerStyle(.segmented)
        }
    }
}

private struct RangeAirConditioningSection: View {
    @Binding var airConditioningMode: AirConditioningMode

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Air conditioning")
                .font(.subheadline.weight(.semibold))

            Picker("Air conditioning", selection: $airConditioningMode) {
                ForEach(AirConditioningMode.allCases) { mode in
                    Text(mode.label).tag(mode as AirConditioningMode)
                }
            }
            .pickerStyle(.segmented)
        }
    }
}

private struct RangeTrailerTowSection: View {
    @Binding var isEnabled: Bool
    let weightKg: Binding<Double>
    let weightRange: ClosedRange<Double>
    let weightStep: Double
    let weightText: String
    @Binding var boxyTrailerEnabled: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Trailer / tow mode", isOn: $isEnabled)
                .font(.subheadline.weight(.semibold))

            Text("Adds an estimated consumption penalty when driving with a trailer.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if isEnabled {
                RangeSliderSection(
                    title: "Trailer weight",
                    value: weightKg,
                    range: weightRange,
                    step: weightStep,
                    displayValue: weightText
                )
                .padding(.top, 2)

                Toggle("Boxy trailer / caravan", isOn: $boxyTrailerEnabled)
                    .font(.subheadline.weight(.semibold))
                    .padding(.top, 2)

                Text("Adds an extra aerodynamic penalty for enclosed trailers and caravans.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct RangeTyreSection: View {
    @Binding var selectedTyreSet: TyreSet
    let rollingResistanceClass: Binding<RollingResistanceClass>
    let onTyreSetChanged: (TyreSet) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Tyre set")
                    .font(.subheadline.weight(.semibold))

                Picker("Tyre set", selection: $selectedTyreSet) {
                    ForEach(TyreSet.allCases) { tyreSet in
                        Text(tyreSet.label).tag(tyreSet as TyreSet)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: selectedTyreSet) { _, newValue in
                    onTyreSetChanged(newValue)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Rolling resistance")
                    .font(.subheadline.weight(.semibold))

                Picker("Rolling resistance", selection: rollingResistanceClass) {
                    ForEach(RollingResistanceClass.rangeOrderedCases) { resistanceClass in
                        Text(resistanceClass.label).tag(resistanceClass as RollingResistanceClass)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
    }
}

struct WelcomePopupView: View {
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Welcome")
                    .font(.title2.weight(.semibold))

                Text("Welcome to RangePilot\n\nDrag the battery slider to see the estimated range.\n\nChange vehicle profile and driving conditions to explore different range scenarios.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button("Got it") {
                onDismiss()
            }
            .buttonStyle(.borderedProminent)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(22)
        .presentationDetents([.height(260)])
        .presentationDragIndicator(.hidden)
    }
}

private struct OneTimeInfoDialogPresenter: ViewModifier {
    @Binding var isLogActualConsumptionInfoPresented: Bool
    @Binding var isTripPlanningInputInfoPresented: Bool
    @Binding var isCustomEVModeInfoPresented: Bool
    let onAcknowledgeLogActualConsumption: () -> Void
    let onAcknowledgeTripPlanningInput: () -> Void
    let onContinueCustomEVMode: () -> Void
    let onCancelCustomEVMode: () -> Void

    func body(content: Content) -> some View {
        content
            .alert("Log actual consumption", isPresented: $isLogActualConsumptionInfoPresented) {
                Button("Got it!") {
                    onAcknowledgeLogActualConsumption()
                }
            } message: {
                Text("""
                Log examples of your car's actual consumption to calibrate the app to your car and your real-world driving.

                Calibration becomes active after at least 3 logged trips.

                You can turn calibration on or off at any time in Settings.
                """)
            }
            .alert("Plan a trip", isPresented: $isTripPlanningInputInfoPresented) {
                Button("Got it!") {
                    onAcknowledgeTripPlanningInput()
                }
            } message: {
                Text("""
                Enter a destination, address, or place name.

                You can also describe a trip in your own words.

                Example:

                "From San Francisco to Santa Cruz"
                """)
            }
            .alert("Custom profile", isPresented: $isCustomEVModeInfoPresented) {
                Button("Continue") {
                    onContinueCustomEVMode()
                }

                Button("Cancel", role: .cancel) {
                    onCancelCustomEVMode()
                }
            } message: {
                Text("""
                RangePilot was originally modelled on the MINI Cooper SE 2019–2023.

                Custom profiles allow you to use the app with other electric vehicles by entering battery capacity, WLTP range, and charging speed.

                Custom EV estimates are approximate at first. Trip logging can calibrate estimates to your vehicle after at least three logged trips in a driving mode.

                If you want to use the app for your MINI Cooper SE again, select the built-in MINI profile.
                """)
            }
    }
}

private struct TripPlanningDescriptionInputView: View {
    @Binding var text: String
    let isFocused: FocusState<Bool>.Binding
    let accentColor: Color
    let showsClearButton: Bool
    let onClear: () -> Void
    let onFocusChanged: (Bool) -> Void

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Where are you going?", text: $text, axis: .vertical)
                .lineLimit(3...5)
                .textInputAutocapitalization(.sentences)
                .submitLabel(.done)
                .focused(isFocused)
                .padding(.top, 10)
                .padding(.leading, 12)

            if showsClearButton {
                Button {
                    onClear()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 34)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear destination")
                .accessibilityHint("Starts a new trip planning session.")
            }

            Image(systemName: "mic.fill")
                .font(.body.weight(.semibold))
                .frame(width: 34, height: 34)
                .foregroundStyle(accentColor)
                .accessibilityLabel("Voice entry")
                .accessibilityHint("Use keyboard dictation from the focused trip description field.")
                .padding(.trailing, 6)
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()

                Button("Done") {
                    isFocused.wrappedValue = false
                }
            }
        }
        .onChange(of: isFocused.wrappedValue) { _, isFocused in
            onFocusChanged(isFocused)
        }
        .simultaneousGesture(
            TapGesture().onEnded {
                onFocusChanged(true)
            }
        )
    }
}



#Preview {
    ContentView()
}
