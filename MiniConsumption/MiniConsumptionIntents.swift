import AppIntents
import Foundation
#if canImport(CoreLocation)
import CoreLocation
#endif
#if canImport(MapKit)
import MapKit
#endif

struct EstimateCurrentRangeIntent: AppIntent {
    static let title: LocalizedStringResource = "Estimate Current Range"
    static let description = IntentDescription("Estimate the remaining driving range using Mini Range settings.")
    static let openAppWhenRun = false

    init() {}

    init(preset: DrivingPreset) {
        self.preset = preset
    }

    static var parameterSummary: some ParameterSummary {
        Summary("Estimate range with \(\.$batteryPercentage) percent battery")
    }

    @Parameter(title: "Battery percentage", requestValueDialog: "What is your current battery percentage?")
    var batteryPercentage: Double?

    @Parameter(title: "Temperature", requestValueDialog: "What temperature should I use?")
    var temperature: Double?

    @Parameter(title: "Road Profile")
    var roadProfile: RoadTypeProfile?

    @Parameter(title: "Preset")
    var preset: DrivingPreset?

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let settings = MiniConsumptionSettingsSnapshot.load()
        let resolvedBatteryPercentage: Double
        if let batteryPercentage {
            resolvedBatteryPercentage = normalizeBatteryPercentInput(batteryPercentage)
        } else {
            resolvedBatteryPercentage = normalizeBatteryPercentInput(
                try await $batteryPercentage.requestValue("What is your current battery percentage?")
            )
        }
        let resolvedTemperature = temperature.map(settings.temperatureUnits.storedTemperature(fromDisplayed:)) ?? settings.temperature
        let resolvedPreset = preset ?? .currentSettings
        let forecast = settings.forecast(
            distance: settings.tripDistance,
            temperature: resolvedPreset.temperature(resolvedTemperature),
            roadTypeProfile: roadProfile ?? resolvedPreset.roadTypeProfile(settings.roadTypeProfile),
            motorwaySpeed: settings.motorwaySpeed,
            roadSurface: resolvedPreset.roadSurface(settings.roadSurface),
            windCondition: settings.windCondition,
            planningMode: settings.planningMode,
            applyDistanceAdjustment: false
        )
        let range = MiniConsumptionCalculator.calculateRemainingRange(
            currentBatteryPercent: resolvedBatteryPercentage,
            expectedKWhPer100km: forecast.finalKWhPer100km,
            usableBatteryKWh: settings.effectiveUsableBatteryKWh
        )

        let response = "Estimated range is about \(settings.displayUnits.spokenDistance(range.rangeKm))."
        return .result(dialog: IntentDialog(stringLiteral: response))
    }
}

struct PlanTripChargingIntent: AppIntent {
    static let title: LocalizedStringResource = "Plan Trip Charging"
    static let description = IntentDescription("Estimate whether a planned trip needs charging using Mini Range settings.")
    static let openAppWhenRun = false

    init() {}

    init(preset: DrivingPreset) {
        self.preset = preset
    }

    static var parameterSummary: some ParameterSummary {
        Summary("Plan a trip")
    }

    @Parameter(title: "Planned distance", requestValueDialog: "How far is the trip?")
    var plannedDistance: Double?

    @Parameter(title: "Battery percentage", requestValueDialog: "What is your current battery percentage?")
    var batteryPercentage: Double?

    @Parameter(title: "Planning Mode")
    var planningMode: PlanningMode?

    @Parameter(title: "Preset")
    var preset: DrivingPreset?

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let settings = MiniConsumptionSettingsSnapshot.load()
        let resolvedDistance: Double
        if let plannedDistance {
            resolvedDistance = plannedDistance
        } else {
            resolvedDistance = try await $plannedDistance.requestValue("How far is the trip?")
        }

        let resolvedBatteryPercentage: Double
        if let batteryPercentage {
            resolvedBatteryPercentage = normalizeBatteryPercentInput(batteryPercentage)
        } else {
            resolvedBatteryPercentage = normalizeBatteryPercentInput(
                try await $batteryPercentage.requestValue("What is your current battery percentage?")
            )
        }

        let resolvedPreset = preset ?? .currentSettings
        let tripDistance = max(1, settings.displayUnits.storedDistance(fromDisplayed: resolvedDistance))
        let resolvedPlanningMode = planningMode ?? settings.planningMode
        let forecast = settings.forecast(
            distance: tripDistance,
            temperature: resolvedPreset.temperature(settings.temperature),
            roadTypeProfile: resolvedPreset.roadTypeProfile(settings.roadTypeProfile),
            motorwaySpeed: settings.motorwaySpeed,
            roadSurface: resolvedPreset.roadSurface(settings.roadSurface),
            windCondition: settings.windCondition,
            planningMode: resolvedPlanningMode
        )
        let plan = MiniConsumptionCalculator.calculateBatteryPlan(
            totalTripKWh: forecast.totalKWh,
            startBatteryPercent: resolvedBatteryPercentage,
            temperature: settings.temperature,
            chargingWindow: settings.normalChargingWindow,
            arrivalBatteryTargetPercent: normalizeBatteryPercentInput(settings.arrivalBatteryTargetPercent),
            averageChargingSpeedKW: settings.averageChargingSpeedKW,
            chargingSetupMinutes: settings.tripChargingSetupMinutes,
            usableBatteryKWh: settings.effectiveUsableBatteryKWh,
            chargingTaperStartSOC: settings.chargingTaperStartSOC
        )

        let response: String
        if plan.needsCharging {
            response = "Charging will likely be needed."
        } else {
            response = "You should arrive with about \(formattedBatteryPercent(plan.arrivalBatteryPercent)) battery."
        }

        return .result(dialog: IntentDialog(stringLiteral: response))
    }
}

struct PlanMiniRangeTripIntent: AppIntent {
    static let title: LocalizedStringResource = "Plan Mini Range Trip"
    static let description = IntentDescription("Plan a Mini Range trip from a natural language description.")
    static let openAppWhenRun = false

    static var parameterSummary: some ParameterSummary {
        Summary("Plan Mini Range trip from \(\.$naturalLanguageTripDescription)")
    }

    @Parameter(title: "Trip description", requestValueDialog: "Where are you going, or how far is the trip?")
    var naturalLanguageTripDescription: String

    @Parameter(title: "Battery percentage", requestValueDialog: "What is your current battery percentage?")
    var batteryPercentage: Double?

    @Parameter(title: "Outdoor temperature")
    var outdoorTemperature: Double?

    @Parameter(title: "Planning Mode")
    var planningMode: PlanningMode?

    @Parameter(title: "Road Surface")
    var roadSurface: RoadSurface?

    @Parameter(title: "Wind")
    var wind: WindCondition?

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let settings = MiniConsumptionSettingsSnapshot.load()
        var parsedInput = await NaturalLanguageTripParser.parse(naturalLanguageTripDescription)

        var resolvedRouteEstimate = await routeEstimate(for: parsedInput.route)
        var resolvedDistanceKm = parsedInput.plannedDistanceKm ?? resolvedRouteEstimate?.distanceKm
        if resolvedDistanceKm == nil {
            let requestedTripDetail = try await $naturalLanguageTripDescription.requestValue(
                "Where are you going, or how far is the trip?"
            )
            let additionalInput = await NaturalLanguageTripParser.parse(requestedTripDetail)
            parsedInput = parsedInput.mergingForIntentClarification(with: additionalInput)
            resolvedRouteEstimate = await routeEstimate(for: parsedInput.route)
            resolvedDistanceKm = parsedInput.plannedDistanceKm ?? resolvedRouteEstimate?.distanceKm
        }

        guard let tripDistanceKm = resolvedDistanceKm else {
            return .result(dialog: "I need a destination or trip distance to estimate that.")
        }

        let resolvedBatteryPercentage: Double
        if let batteryPercentage {
            resolvedBatteryPercentage = normalizeBatteryPercentInput(batteryPercentage)
        } else if let parsedBatteryPercentage = parsedInput.batteryPercentage {
            resolvedBatteryPercentage = normalizeBatteryPercentInput(parsedBatteryPercentage)
        } else {
            resolvedBatteryPercentage = normalizeBatteryPercentInput(
                try await $batteryPercentage.requestValue("What is your current battery percentage?")
            )
        }

        let roadTypeSelection = TripRoadTypeSelection.resolve(
            parsedRoadType: parsedInput.roadTypeProfile,
            hasExplicitRoadTypeWording: parsedInput.hasExplicitRoadTypeWording,
            distanceKm: tripDistanceKm,
            currentRoadType: settings.roadTypeProfile,
            routeAverageSpeedKmh: resolvedRouteEstimate?.averageSpeedKmh
        )
        let resolvedTemperature = outdoorTemperature.map(settings.temperatureUnits.storedTemperature(fromDisplayed:))
            ?? parsedInput.temperature
            ?? settings.temperature
        let resolvedRoadSurface = roadSurface ?? parsedInput.roadSurface ?? settings.roadSurface
        let resolvedWindCondition = wind ?? parsedInput.windCondition ?? settings.windCondition
        let resolvedPlanningMode = planningMode ?? parsedInput.planningMode ?? settings.planningMode
        let resolvedMotorwaySpeed = parsedInput.motorwaySpeed ?? settings.motorwaySpeed

        let forecast = settings.forecast(
            distance: max(1, tripDistanceKm),
            temperature: resolvedTemperature,
            roadTypeProfile: roadTypeSelection.roadTypeProfile,
            motorwaySpeed: resolvedMotorwaySpeed,
            roadSurface: resolvedRoadSurface,
            windCondition: resolvedWindCondition,
            planningMode: resolvedPlanningMode
        )
        let plan = MiniConsumptionCalculator.calculateBatteryPlan(
            totalTripKWh: forecast.totalKWh,
            startBatteryPercent: resolvedBatteryPercentage,
            temperature: resolvedTemperature,
            chargingWindow: settings.normalChargingWindow,
            arrivalBatteryTargetPercent: normalizeBatteryPercentInput(settings.arrivalBatteryTargetPercent),
            averageChargingSpeedKW: settings.averageChargingSpeedKW,
            chargingSetupMinutes: settings.tripChargingSetupMinutes,
            usableBatteryKWh: settings.effectiveUsableBatteryKWh,
            chargingTaperStartSOC: settings.chargingTaperStartSOC
        )

        let chargingRecommendation = plan.needsCharging ? "Charging recommended" : "No charging recommended"
        let chargingTime = spokenChargingTime(plan.estimatedChargingMinutes)
        let assumptions = "Assuming \(settings.displayUnits.spokenDistance(tripDistanceKm)), \(roadTypeSelection.roadTypeProfile.assumptionLabel), \(settings.temperatureUnits.spokenTemperature(resolvedTemperature))."
        let response = "Arrival about \(formattedBatteryPercent(plan.arrivalBatteryPercent)). \(chargingRecommendation): \(plan.chargingStops) \(plan.chargingStops == 1 ? "stop" : "stops"), about \(chargingTime). \(assumptions)"

        return .result(dialog: IntentDialog(stringLiteral: response))
    }

    private func routeEstimate(for route: TripRouteDescription?) async -> RouteDistanceEstimate? {
        guard let route else {
            return nil
        }

        if let origin = route.origin {
            return try? await RouteDistanceService.estimatedDrivingRoute(from: origin, to: route.destination)
        }

        return try? await RouteDistanceService.estimatedDrivingRouteFromCurrentLocation(to: route.destination)
    }

    private func spokenChargingTime(_ minutes: Double) -> String {
        let roundedMinutes = Int(minutes.rounded())
        if roundedMinutes < 60 {
            return "\(roundedMinutes) minutes charging"
        }

        let hours = roundedMinutes / 60
        let remainingMinutes = roundedMinutes % 60
        if remainingMinutes == 0 {
            return "\(hours) \(hours == 1 ? "hour" : "hours") charging"
        }

        return "\(hours) \(hours == 1 ? "hour" : "hours") \(remainingMinutes) minutes charging"
    }
}

struct CheckMiniRangeTripIntent: AppIntent {
    static let title: LocalizedStringResource = "Check Mini Range Trip"
    static let description = IntentDescription("Check whether a planned Mini Range trip is likely possible from a battery level.")
    static let openAppWhenRun = false

    static var parameterSummary: some ParameterSummary {
        Summary("Check trip from \(\.$naturalLanguageTripDescription) with \(\.$batteryPercentage) percent battery")
    }

    @Parameter(title: "Trip description", requestValueDialog: "Where are you going, or how far is the trip?")
    var naturalLanguageTripDescription: String

    @Parameter(title: "Battery percentage", requestValueDialog: "What is your current battery percentage?")
    var batteryPercentage: Double?

    @Parameter(title: "Arrival battery target")
    var arrivalBatteryTarget: Double?

    @Parameter(title: "Temperature")
    var temperature: Double?

    @Parameter(title: "Planning Mode")
    var planningMode: PlanningMode?

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let settings = MiniConsumptionSettingsSnapshot.load()
        var parsedInput = await NaturalLanguageTripParser.parse(naturalLanguageTripDescription)
        var estimate = await MiniRangeTripIntentEstimate.resolve(
            parsedInput: parsedInput,
            settings: settings,
            temperatureOverride: temperature,
            planningModeOverride: planningMode
        )

        if estimate == nil {
            let requestedTripDetail = try await $naturalLanguageTripDescription.requestValue(
                "Where are you going, or how far is the trip?"
            )
            let additionalInput = await NaturalLanguageTripParser.parse(requestedTripDetail)
            parsedInput = parsedInput.mergingForIntentClarification(with: additionalInput)
            estimate = await MiniRangeTripIntentEstimate.resolve(
                parsedInput: parsedInput,
                settings: settings,
                temperatureOverride: temperature,
                planningModeOverride: planningMode
            )
        }

        guard let estimate else {
            return .result(dialog: "I need a destination or trip distance to estimate that.")
        }

        let resolvedBatteryPercentage: Double
        if let batteryPercentage {
            resolvedBatteryPercentage = normalizeBatteryPercentInput(batteryPercentage)
        } else if let parsedBatteryPercentage = parsedInput.batteryPercentage {
            resolvedBatteryPercentage = normalizeBatteryPercentInput(parsedBatteryPercentage)
        } else {
            resolvedBatteryPercentage = normalizeBatteryPercentInput(
                try await $batteryPercentage.requestValue("What is your current battery percentage?")
            )
        }

        let target = normalizeBatteryPercentInput(arrivalBatteryTarget ?? settings.arrivalBatteryTargetPercent)
        let plan = MiniConsumptionCalculator.calculateBatteryPlan(
            totalTripKWh: estimate.forecast.totalKWh,
            startBatteryPercent: resolvedBatteryPercentage,
            temperature: estimate.temperature,
            chargingWindow: settings.normalChargingWindow,
            arrivalBatteryTargetPercent: target,
            averageChargingSpeedKW: settings.averageChargingSpeedKW,
            chargingSetupMinutes: settings.tripChargingSetupMinutes,
            usableBatteryKWh: settings.effectiveUsableBatteryKWh,
            chargingTaperStartSOC: settings.chargingTaperStartSOC
        )

        let response: String
        if plan.needsCharging {
            response = "Not comfortably. Estimated arrival battery is below your margin. Plan \(plan.chargingStops) \(plan.chargingStops == 1 ? "charging stop" : "charging stops"), about \(spokenChargingTime(plan.estimatedChargingMinutes))."
        } else {
            response = "Yes, likely. Estimated arrival battery is about \(formattedBatteryPercent(plan.arrivalBatteryPercent)). No charging stop needed."
        }

        return .result(dialog: IntentDialog(stringLiteral: response))
    }
}

struct RequiredBatteryForTripIntent: AppIntent {
    static let title: LocalizedStringResource = "Required Battery for Trip"
    static let description = IntentDescription("Estimate the starting battery needed for a planned Mini Range trip.")
    static let openAppWhenRun = false

    static var parameterSummary: some ParameterSummary {
        Summary("Battery needed for \(\.$naturalLanguageTripDescription)")
    }

    @Parameter(title: "Trip description", requestValueDialog: "Where are you going, or how far is the trip?")
    var naturalLanguageTripDescription: String

    @Parameter(title: "Arrival battery target")
    var arrivalBatteryTarget: Double?

    @Parameter(title: "Temperature")
    var temperature: Double?

    @Parameter(title: "Planning Mode")
    var planningMode: PlanningMode?

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let settings = MiniConsumptionSettingsSnapshot.load()
        var parsedInput = await NaturalLanguageTripParser.parse(naturalLanguageTripDescription)
        var estimate = await MiniRangeTripIntentEstimate.resolve(
            parsedInput: parsedInput,
            settings: settings,
            temperatureOverride: temperature,
            planningModeOverride: planningMode
        )

        if estimate == nil {
            let requestedTripDetail = try await $naturalLanguageTripDescription.requestValue(
                "Where are you going, or how far is the trip?"
            )
            let additionalInput = await NaturalLanguageTripParser.parse(requestedTripDetail)
            parsedInput = parsedInput.mergingForIntentClarification(with: additionalInput)
            estimate = await MiniRangeTripIntentEstimate.resolve(
                parsedInput: parsedInput,
                settings: settings,
                temperatureOverride: temperature,
                planningModeOverride: planningMode
            )
        }

        guard let estimate else {
            return .result(dialog: "I need a destination or trip distance to estimate that.")
        }

        let target = normalizeBatteryPercentInput(arrivalBatteryTarget ?? settings.arrivalBatteryTargetPercent)
        let requiredBatteryPercent = estimate.forecast.totalKWh / settings.effectiveUsableBatteryKWh * 100 + target
        let displayedBatteryPercent = clampedBatteryPercentForDisplay(requiredBatteryPercent)
        let response: String
        if requiredBatteryPercent > 100 {
            response = "You would need more than 100 percent battery. Charging en route is likely needed."
        } else {
            response = "You need about \(formattedBatteryPercent(displayedBatteryPercent)) battery to arrive with \(formattedBatteryPercent(target))."
        }

        return .result(dialog: IntentDialog(stringLiteral: response))
    }
}

struct FindChargersNearLimitIntent: AppIntent {
    static let title: LocalizedStringResource = "Find Chargers Near Limit"
    static let description = IntentDescription("Search for EV chargers near where Mini Range expects you to reach your lower battery limit.")
    static let openAppWhenRun = false
    private static let chargerSearchRadiusMeters = 25_000.0

    static var parameterSummary: some ParameterSummary {
        Summary("Find chargers toward \(\.$directionOrDestination)")
    }

    @Parameter(title: "Direction or destination", requestValueDialog: "Where are you heading?")
    var directionOrDestination: String

    @Parameter(title: "Battery percentage", requestValueDialog: "What is your current battery percentage?")
    var batteryPercentage: Double?

    @Parameter(title: "Temperature")
    var temperature: Double?

    @Parameter(title: "Planning Mode")
    var planningMode: PlanningMode?

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let settings = MiniConsumptionSettingsSnapshot.load()
        var parsedInput = await NaturalLanguageTripParser.parse(directionOrDestination)

        let resolvedBatteryPercentage: Double
        if let batteryPercentage {
            resolvedBatteryPercentage = normalizeBatteryPercentInput(batteryPercentage)
        } else if let parsedBatteryPercentage = parsedInput.batteryPercentage {
            resolvedBatteryPercentage = normalizeBatteryPercentInput(parsedBatteryPercentage)
        } else {
            resolvedBatteryPercentage = normalizeBatteryPercentInput(
                try await $batteryPercentage.requestValue("What is your current battery percentage?")
            )
        }

        let lowerBatteryLimit = normalizeBatteryPercentInput(settings.normalChargingWindow.minimumPercent)
        if resolvedBatteryPercentage <= lowerBatteryLimit {
            let handoff = await nearbyChargingHandoff()
            return .result(
                opensIntent: OpenURLIntent(handoff.url),
                dialog: "You are already near your lower battery limit. I’ll open Maps nearby."
            )
        }

        var estimate = await MiniRangeTripIntentEstimate.resolve(
            parsedInput: parsedInput,
            settings: settings,
            temperatureOverride: temperature,
            planningModeOverride: planningMode
        )

        if estimate == nil {
            let requestedDirection = try await $directionOrDestination.requestValue("Where are you heading?")
            let additionalInput = await NaturalLanguageTripParser.parse(requestedDirection)
            parsedInput = parsedInput.mergingForIntentClarification(with: additionalInput)
            estimate = await MiniRangeTripIntentEstimate.resolve(
                parsedInput: parsedInput,
                settings: settings,
                temperatureOverride: temperature,
                planningModeOverride: planningMode
            )
        }

        guard let estimate else {
            let handoff = await chargingHandoffNearDestination(parsedInput: parsedInput)
            return .result(
                opensIntent: OpenURLIntent(handoff.url),
                dialog: "I couldn’t place that route, but I can open a nearby charger search area."
            )
        }

        let rangeToLimitKm = MiniConsumptionCalculator.calculateRangeToBatteryThreshold(
            startBatteryPercent: resolvedBatteryPercentage,
            thresholdBatteryPercent: lowerBatteryLimit,
            expectedKWhPer100km: estimate.forecast.finalKWhPer100km,
            usableBatteryKWh: settings.effectiveUsableBatteryKWh
        )

        if let coordinate = lowerLimitCoordinateAlongRoute(estimate: estimate, rangeToLimitKm: rangeToLimitKm) {
            let handoff = await chargingHandoff(centeredAt: coordinate)
            if handoff.opensChargerResults {
                return .result(
                    dialog: "You should reach your lower battery limit in about \(settings.displayUnits.spokenDistance(rangeToLimitKm)). I’ll show chargers around that area."
                )
            }

            return .result(
                opensIntent: OpenURLIntent(handoff.url),
                dialog: "You should reach your lower battery limit in about \(settings.displayUnits.spokenDistance(rangeToLimitKm)). I’ll open that area in Maps."
            )
        }

        let destinationHandoff = await chargingHandoffNearDestination(parsedInput: parsedInput)
        return .result(
            opensIntent: OpenURLIntent(destinationHandoff.url),
            dialog: "You should reach your lower battery limit in about \(settings.displayUnits.spokenDistance(rangeToLimitKm)). I’ll open the estimated area."
        )
    }

    @MainActor
    private func lowerLimitCoordinateAlongRoute(estimate: MiniRangeTripIntentEstimate, rangeToLimitKm: Double) -> CLLocationCoordinate2D? {
#if canImport(MapKit)
        guard let polyline = estimate.routeEstimate?.polyline,
              let coordinate = RoutePolylineDistance.coordinate(on: polyline, atDistanceKm: rangeToLimitKm) else {
            return nil
        }

        return coordinate
#else
        return nil
#endif
    }

    @MainActor
    private func chargingHandoffNearDestination(parsedInput: NaturalLanguageTripEstimateInput) async -> ChargerHandoff {
        if let destination = parsedInput.route?.destination {
#if canImport(MapKit)
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = destination
            if let coordinate = try? await MKLocalSearch(request: request).start().mapItems.first?.location.coordinate {
                return await chargingHandoff(centeredAt: coordinate)
            }
#endif
        }

        return await nearbyChargingHandoff()
    }

    @MainActor
    private func nearbyChargingHandoff() async -> ChargerHandoff {
#if canImport(CoreLocation) && canImport(MapKit)
        if let coordinate = await CurrentLocationRouteOriginProvider.requestCurrentLocation() {
            return await chargingHandoff(centeredAt: coordinate)
        }
#endif
        return ChargerHandoff(url: chargerAreaSearchURL())
    }

    private func chargingHandoff(centeredAt coordinate: CLLocationCoordinate2D) async -> ChargerHandoff {
#if canImport(MapKit)
        guard CLLocationCoordinate2DIsValid(coordinate),
              coordinate.latitude.isFinite,
              coordinate.longitude.isFinite else {
            return ChargerHandoff(url: chargerAreaSearchURL())
        }

        let mapItems = await validatedLocalChargerResults(near: coordinate)
        if !mapItems.isEmpty {
            let region = MKCoordinateRegion(
                center: coordinate,
                latitudinalMeters: Self.chargerSearchRadiusMeters * 2,
                longitudinalMeters: Self.chargerSearchRadiusMeters * 2
            )
            MKMapItem.openMaps(
                with: Array(mapItems.prefix(10)),
                launchOptions: [
                    MKLaunchOptionsMapCenterKey: NSValue(mkCoordinate: coordinate),
                    MKLaunchOptionsMapSpanKey: NSValue(mkCoordinateSpan: region.span)
                ]
            )
            return ChargerHandoff(url: chargerAreaSearchURL(centeredAt: coordinate), opensChargerResults: true)
        }
#endif

        return ChargerHandoff(url: chargerAreaSearchURL(centeredAt: coordinate))
    }

#if canImport(MapKit)
    private func validatedLocalChargerResults(near coordinate: CLLocationCoordinate2D) async -> [MKMapItem] {
        guard CLLocationCoordinate2DIsValid(coordinate),
              coordinate.latitude.isFinite,
              coordinate.longitude.isFinite else {
            return []
        }

        let region = MKCoordinateRegion(
            center: coordinate,
            latitudinalMeters: Self.chargerSearchRadiusMeters * 2,
            longitudinalMeters: Self.chargerSearchRadiusMeters * 2
        )
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = "EV charger"
        request.region = region
        request.resultTypes = .pointOfInterest
        request.pointOfInterestFilter = MKPointOfInterestFilter(including: [.evCharger])

        guard let response = try? await MKLocalSearch(request: request).start(),
              !response.mapItems.isEmpty else {
            return []
        }

        let centerLocation = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        return response.mapItems
            .filter { mapItem in
                let resultCoordinate = mapItem.location.coordinate
                return CLLocationCoordinate2DIsValid(resultCoordinate)
                    && resultCoordinate.latitude.isFinite
                    && resultCoordinate.longitude.isFinite
                    && mapItem.location.distance(from: centerLocation) <= Self.chargerSearchRadiusMeters
            }
            .sorted { $0.location.distance(from: centerLocation) < $1.location.distance(from: centerLocation) }
    }
#endif

    private func chargerAreaSearchURL(centeredAt coordinate: CLLocationCoordinate2D? = nil) -> URL {
        var components = URLComponents(string: "https://maps.apple.com/")!
        var queryItems = [
            URLQueryItem(name: "z", value: "12")
        ]

        if let coordinate,
           CLLocationCoordinate2DIsValid(coordinate),
           coordinate.latitude.isFinite,
           coordinate.longitude.isFinite {
            let coordinateValue = String(
                format: "%.6f,%.6f",
                locale: Locale(identifier: "en_US_POSIX"),
                coordinate.latitude,
                coordinate.longitude
            )
            queryItems.append(URLQueryItem(name: "ll", value: coordinateValue))
            queryItems.append(URLQueryItem(name: "sll", value: coordinateValue))
        }

        components.queryItems = queryItems
        return components.url!
    }

    private struct ChargerHandoff {
        let url: URL
        var opensChargerResults = false
    }
}

enum DrivingPreset: String, AppEnum {
    case currentSettings
    case winter
    case motorway
    case city

    nonisolated static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Driving Preset")
    }

    nonisolated static var caseDisplayRepresentations: [DrivingPreset: DisplayRepresentation] {
        [
            .currentSettings: DisplayRepresentation(title: "Current Settings"),
            .winter: DisplayRepresentation(title: "Winter"),
            .motorway: DisplayRepresentation(title: "Motorway"),
            .city: DisplayRepresentation(title: "City")
        ]
    }

    func temperature(_ storedTemperature: Double) -> Double {
        switch self {
        case .winter:
            min(storedTemperature, -5)
        case .currentSettings, .motorway, .city:
            storedTemperature
        }
    }

    func roadTypeProfile(_ storedProfile: RoadTypeProfile) -> RoadTypeProfile {
        switch self {
        case .motorway:
            .motorway
        case .city:
            .cityMix
        case .currentSettings, .winter:
            storedProfile
        }
    }

    func roadSurface(_ storedSurface: RoadSurface) -> RoadSurface {
        switch self {
        case .winter:
            .snowSlush
        case .currentSettings, .motorway, .city:
            storedSurface
        }
    }
}

struct DescribeTripIntent: AppIntent {
    static let title: LocalizedStringResource = "Describe Trip"
    static let description = IntentDescription("Estimate a Mini Range trip from a short natural language description.")
    static let openAppWhenRun = false

    static var parameterSummary: some ParameterSummary {
        Summary("Estimate trip from \(\.$tripDescription)")
    }

    @Parameter(title: "Trip description", requestValueDialog: "Describe the trip.")
    var tripDescription: String

    @Parameter(title: "Planned distance", requestValueDialog: "How far is the trip?")
    var plannedDistanceKm: Double?

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
#if !canImport(FoundationModels)
        return .result(dialog: "Natural language trip descriptions require Apple Foundation Models support.")
#else
        if #unavailable(iOS 26.0) {
            return .result(dialog: "Natural language trip descriptions require Apple Foundation Models support.")
        }

        let parsedInput = await NaturalLanguageTripParser.parse(tripDescription)
        let settings = MiniConsumptionSettingsSnapshot.load()
        let requestedDistance: Double?
        if parsedInput.plannedDistanceKm == nil, plannedDistanceKm == nil {
            requestedDistance = settings.displayUnits.storedDistance(
                fromDisplayed: try await $plannedDistanceKm.requestValue("How far is the trip?")
            )
        } else {
            requestedDistance = nil
        }

        guard let tripDistance = parsedInput.plannedDistanceKm
            ?? plannedDistanceKm.map(settings.displayUnits.storedDistance(fromDisplayed:))
            ?? requestedDistance else {
            return .result(dialog: "I need a trip distance to estimate that.")
        }

        let batteryPercentage = normalizeBatteryPercentInput(parsedInput.batteryPercentage ?? settings.currentBatteryPercent)
        let roadTypeSelection = TripRoadTypeSelection.resolve(
            parsedRoadType: parsedInput.roadTypeProfile,
            hasExplicitRoadTypeWording: parsedInput.hasExplicitRoadTypeWording,
            distanceKm: tripDistance,
            currentRoadType: settings.roadTypeProfile
        )
        let roadTypeProfile = roadTypeSelection.roadTypeProfile
        let temperature = parsedInput.temperature ?? settings.temperature
        let motorwaySpeed = parsedInput.motorwaySpeed ?? settings.motorwaySpeed
        let roadSurface = parsedInput.roadSurface ?? settings.roadSurface
        let windCondition = parsedInput.windCondition ?? settings.windCondition
        let planningMode = parsedInput.planningMode ?? settings.planningMode

        let forecast = settings.forecast(
            distance: max(1, tripDistance),
            temperature: temperature,
            roadTypeProfile: roadTypeProfile,
            motorwaySpeed: motorwaySpeed,
            roadSurface: roadSurface,
            windCondition: windCondition,
            planningMode: planningMode
        )
        let plan = MiniConsumptionCalculator.calculateBatteryPlan(
            totalTripKWh: forecast.totalKWh,
            startBatteryPercent: batteryPercentage,
            temperature: temperature,
            chargingWindow: settings.normalChargingWindow,
            arrivalBatteryTargetPercent: normalizeBatteryPercentInput(settings.arrivalBatteryTargetPercent),
            averageChargingSpeedKW: settings.averageChargingSpeedKW,
            chargingSetupMinutes: settings.tripChargingSetupMinutes,
            usableBatteryKWh: settings.effectiveUsableBatteryKWh,
            chargingTaperStartSOC: settings.chargingTaperStartSOC
        )

        let assumption = "Assuming \(roadTypeProfile.assumptionLabel) and \(formattedBatteryPercent(batteryPercentage)) battery"
        let response: String
        if plan.needsCharging {
            response = "\(assumption), charging needed. Estimate \(plan.chargingStops) \(plan.chargingStops == 1 ? "stop" : "stops")."
        } else {
            response = "\(assumption), trip fits. Final battery about \(formattedBatteryPercent(plan.arrivalBatteryPercent))."
        }

        return .result(dialog: IntentDialog(stringLiteral: response))
#endif
    }
}

struct AskTripAssistantIntent: AppIntent {
    static let title: LocalizedStringResource = "Ask Trip Assistant"
    static let description = IntentDescription("Ask Mini Range a handsfree trip-planning question.")
    static let openAppWhenRun = false

    static var parameterSummary: some ParameterSummary {
        Summary("Ask about \(\.$tripMessage)")
    }

    @Parameter(title: "Trip message", requestValueDialog: "What should I know about your trip?")
    var tripMessage: String

    @Parameter(title: "Battery percentage", requestValueDialog: "What is your current battery percentage?")
    var batteryPercentage: Double?

    @Parameter(title: "Trip detail", requestValueDialog: "How far are you driving, or where are you going?")
    var tripDetail: String?

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let parsedInput = await NaturalLanguageTripParser.parse(tripMessage)
        let settings = MiniConsumptionSettingsSnapshot.load()
        let resolver = TripAssistantIntentResolver(
            parsedInput: parsedInput,
            settings: settings,
            providedBatteryPercentage: nil,
            providedDistanceKm: nil
        )

        if parsedInput.batteryThresholdQuestionPercent != nil,
           resolver.resolvedBatteryPercentage == nil {
            let requestedBattery = normalizeBatteryPercentInput(
                try await $batteryPercentage.requestValue("What is your current battery percentage?")
            )
            let updatedResolver = resolver.with(batteryPercentage: requestedBattery)
            return .result(dialog: IntentDialog(stringLiteral: updatedResolver.thresholdAnswerText))
        }

        if parsedInput.chargingPreference == .questionLegRangeOnly {
            return .result(dialog: IntentDialog(stringLiteral: resolver.chargingLegAnswerText))
        }

        if resolver.requiresTripDistance {
            let requestedTripDetail = try await $tripDetail.requestValue("How far are you driving, or where are you going?")
            let requestedInput = await NaturalLanguageTripParser.parse(requestedTripDetail)
            let updatedResolver = resolver.with(additionalInput: requestedInput)
            return .result(dialog: IntentDialog(stringLiteral: await updatedResolver.tripPlanAnswerText))
        }

        return .result(dialog: IntentDialog(stringLiteral: await resolver.answerText()))
    }
}

private struct TripAssistantIntentResolver {
    let parsedInput: NaturalLanguageTripEstimateInput
    let settings: MiniConsumptionSettingsSnapshot
    let providedBatteryPercentage: Double?
    let providedDistanceKm: Double?

    var resolvedBatteryPercentage: Double? {
        if let parsedBatteryPercentage = parsedInput.batteryPercentage {
            return normalizeBatteryPercentInput(parsedBatteryPercentage)
        }

        return providedBatteryPercentage.map(normalizeBatteryPercentInput)
    }

    var tripDistanceKm: Double? {
        parsedInput.plannedDistanceKm ?? providedDistanceKm
    }

    var requiresTripDistance: Bool {
        tripDistanceKm == nil
            && parsedInput.route == nil
            && parsedInput.chargingPreference != .questionLegRangeOnly
            && parsedInput.batteryThresholdQuestionPercent == nil
    }

    func with(batteryPercentage: Double?) -> Self {
        Self(
            parsedInput: parsedInput,
            settings: settings,
            providedBatteryPercentage: batteryPercentage,
            providedDistanceKm: providedDistanceKm
        )
    }

    func with(additionalInput: NaturalLanguageTripEstimateInput) -> Self {
        var updatedInput = parsedInput
        updatedInput.plannedDistanceKm = parsedInput.plannedDistanceKm ?? additionalInput.plannedDistanceKm
        updatedInput.route = parsedInput.route ?? additionalInput.route
        updatedInput.batteryPercentage = parsedInput.batteryPercentage ?? additionalInput.batteryPercentage
        if parsedInput.hasExplicitRoadTypeWording {
            updatedInput.roadTypeProfile = parsedInput.roadTypeProfile
        } else if additionalInput.hasExplicitRoadTypeWording {
            updatedInput.roadTypeProfile = additionalInput.roadTypeProfile
        } else {
            updatedInput.roadTypeProfile = parsedInput.roadTypeProfile ?? additionalInput.roadTypeProfile
        }
        updatedInput.hasExplicitRoadTypeWording = parsedInput.hasExplicitRoadTypeWording
            || additionalInput.hasExplicitRoadTypeWording
        updatedInput.motorwaySpeed = parsedInput.motorwaySpeed ?? additionalInput.motorwaySpeed
        updatedInput.temperature = parsedInput.temperature ?? additionalInput.temperature
        updatedInput.roadSurface = parsedInput.roadSurface ?? additionalInput.roadSurface
        updatedInput.windCondition = parsedInput.windCondition ?? additionalInput.windCondition
        updatedInput.planningMode = parsedInput.planningMode ?? additionalInput.planningMode

        return Self(
            parsedInput: updatedInput,
            settings: settings,
            providedBatteryPercentage: providedBatteryPercentage,
            providedDistanceKm: additionalInput.plannedDistanceKm
        )
    }

    func answerText() async -> String {
        if parsedInput.batteryThresholdQuestionPercent != nil {
            return thresholdAnswerText
        }

        if parsedInput.chargingPreference == .questionLegRangeOnly {
            return chargingLegAnswerText
        }

        return await tripPlanAnswerText
    }

    var thresholdAnswerText: String {
        guard let rawThresholdPercent = parsedInput.batteryThresholdQuestionPercent,
              let startBatteryPercent = resolvedBatteryPercentage else {
            return "What is your current battery percentage?"
        }
        let thresholdPercent = normalizeBatteryPercentInput(rawThresholdPercent)

        guard startBatteryPercent > thresholdPercent else {
            return "You are already at or below \(formattedBatteryPercent(thresholdPercent)) battery."
        }

        let forecast = forecast(distance: settings.tripDistance, applyDistanceAdjustment: false)
        let rangeKm = MiniConsumptionCalculator.calculateRangeToBatteryThreshold(
            startBatteryPercent: startBatteryPercent,
            thresholdBatteryPercent: thresholdPercent,
            expectedKWhPer100km: forecast.finalKWhPer100km,
            usableBatteryKWh: settings.effectiveUsableBatteryKWh
        )
        return "About \(settings.displayUnits.spokenDistance(rangeKm)) until \(formattedBatteryPercent(thresholdPercent)) battery."
    }

    var chargingLegAnswerText: String {
        let hasConcreteTripDistance = tripDistanceKm != nil
        let forecast = forecast(
            distance: tripDistanceKm ?? settings.tripDistance,
            usesRoadTypeFallback: hasConcreteTripDistance,
            applyDistanceAdjustment: hasConcreteTripDistance
        )
        let legRangeKm = MiniConsumptionCalculator.calculateChargingLegRange(
            expectedKWhPer100km: forecast.finalKWhPer100km,
            chargingWindow: settings.normalChargingWindow,
            usableBatteryKWh: settings.effectiveUsableBatteryKWh
        )
        return "You can drive about \(settings.displayUnits.spokenDistance(legRangeKm)) between normal charging stops."
    }

    var tripPlanAnswerText: String {
        get async {
            if let route = parsedInput.route,
               tripDistanceKm == nil,
               let routeDistanceKm = await routeDistanceKm(for: route) {
                return tripPlanAnswerText(distanceKm: routeDistanceKm)
            }

            guard let tripDistanceKm else {
                return "How far are you driving, or where are you going?"
            }

            return tripPlanAnswerText(distanceKm: tripDistanceKm)
        }
    }

    private func tripPlanAnswerText(distanceKm: Double) -> String {
        let forecast = forecast(distance: max(1, distanceKm), usesRoadTypeFallback: true)
        let batteryPercentage = resolvedBatteryPercentage ?? normalizeBatteryPercentInput(settings.currentBatteryPercent)
        let plan = MiniConsumptionCalculator.calculateBatteryPlan(
            totalTripKWh: forecast.totalKWh,
            startBatteryPercent: batteryPercentage,
            temperature: resolvedTemperature,
            chargingWindow: settings.normalChargingWindow,
            arrivalBatteryTargetPercent: normalizeBatteryPercentInput(settings.arrivalBatteryTargetPercent),
            averageChargingSpeedKW: settings.averageChargingSpeedKW,
            chargingSetupMinutes: settings.tripChargingSetupMinutes,
            usableBatteryKWh: settings.effectiveUsableBatteryKWh,
            chargingTaperStartSOC: settings.chargingTaperStartSOC
        )

        if plan.needsCharging {
            return "You likely need \(plan.chargingStops) \(plan.chargingStops == 1 ? "charging stop" : "charging stops") for that trip."
        }

        return "With \(formattedBatteryPercent(batteryPercentage)) battery, that trip likely fits without charging."
    }

    private func forecast(
        distance: Double,
        usesRoadTypeFallback: Bool = false,
        applyDistanceAdjustment: Bool = true
    ) -> ForecastResult {
        let roadTypeSelection = TripRoadTypeSelection.resolve(
            parsedRoadType: parsedInput.roadTypeProfile,
            hasExplicitRoadTypeWording: parsedInput.hasExplicitRoadTypeWording,
            distanceKm: usesRoadTypeFallback ? distance : nil,
            currentRoadType: settings.roadTypeProfile
        )

        return settings.forecast(
            distance: max(1, distance),
            temperature: resolvedTemperature,
            roadTypeProfile: roadTypeSelection.roadTypeProfile,
            motorwaySpeed: parsedInput.motorwaySpeed ?? settings.motorwaySpeed,
            roadSurface: parsedInput.roadSurface ?? settings.roadSurface,
            windCondition: parsedInput.windCondition ?? settings.windCondition,
            planningMode: parsedInput.planningMode ?? settings.planningMode,
            applyDistanceAdjustment: applyDistanceAdjustment
        )
    }

    private var resolvedTemperature: Double {
        parsedInput.temperature ?? settings.temperature
    }

    private func routeDistanceKm(for route: TripRouteDescription) async -> Double? {
        if let origin = route.origin {
            return try? await RouteDistanceService.estimatedDrivingDistanceKm(from: origin, to: route.destination)
        }

        return try? await RouteDistanceService.estimatedDrivingDistanceFromCurrentLocationKm(to: route.destination)
    }
}

struct MiniConsumptionShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: EstimateCurrentRangeIntent(),
            phrases: [
                "Estimate range in \(.applicationName)",
                "Estimate current range in \(.applicationName)",
                "Estimate range with battery in \(.applicationName)",
                "Check my Mini range in \(.applicationName)",
                "How far can I drive in \(.applicationName)"
            ],
            shortTitle: "Estimate Range",
            systemImageName: "battery.75"
        )
        AppShortcut(
            intent: EstimateCurrentRangeIntent(preset: .winter),
            phrases: [
                "Estimate winter range in \(.applicationName)",
                "How far can I drive in winter in \(.applicationName)"
            ],
            shortTitle: "Winter Range",
            systemImageName: "snowflake"
        )
        AppShortcut(
            intent: PlanTripChargingIntent(),
            phrases: [
                "Plan trip charging in \(.applicationName)",
                "Check trip charging in \(.applicationName)",
                "Plan a trip in \(.applicationName)",
                "Do I need to charge in \(.applicationName)"
            ],
            shortTitle: "Plan Charging",
            systemImageName: "bolt.car"
        )
        AppShortcut(
            intent: PlanTripChargingIntent(preset: .motorway),
            phrases: [
                "Plan a motorway trip in \(.applicationName)",
                "Do I need to charge on the motorway in \(.applicationName)"
            ],
            shortTitle: "Motorway Trip",
            systemImageName: "road.lanes"
        )
        AppShortcut(
            intent: PlanMiniRangeTripIntent(),
            phrases: [
                "Plan a Mini Range trip in \(.applicationName)",
                "Plan a Mini trip in \(.applicationName)",
                "Plan my Mini Range trip in \(.applicationName)",
                "Estimate a Mini Range trip in \(.applicationName)"
            ],
            shortTitle: "Plan Mini Trip",
            systemImageName: "map"
        )
        AppShortcut(
            intent: CheckMiniRangeTripIntent(),
            phrases: [
                "Check if I can drive in \(.applicationName)",
                "Can I drive in \(.applicationName)",
                "Check a Mini Range trip in \(.applicationName)"
            ],
            shortTitle: "Can I Drive",
            systemImageName: "checkmark.circle"
        )
        AppShortcut(
            intent: RequiredBatteryForTripIntent(),
            phrases: [
                "How much battery do I need in \(.applicationName)",
                "How much battery do I need for a trip in \(.applicationName)",
                "Estimate required battery in \(.applicationName)",
                "Battery needed for a trip in \(.applicationName)"
            ],
            shortTitle: "Battery Needed",
            systemImageName: "battery.100"
        )
        AppShortcut(
            intent: FindChargersNearLimitIntent(),
            phrases: [
                "Find chargers near my limit in \(.applicationName)",
                "Find chargers on my way in \(.applicationName)",
                "Search chargers before my battery limit in \(.applicationName)"
            ],
            shortTitle: "Find Chargers",
            systemImageName: "bolt.car"
        )
        AppShortcut(
            intent: DescribeTripIntent(),
            phrases: [
                "Describe a trip in \(.applicationName)",
                "Estimate a described trip in \(.applicationName)"
            ],
            shortTitle: "Describe Trip",
            systemImageName: "text.bubble"
        )
        AppShortcut(
            intent: AskTripAssistantIntent(),
            phrases: [
                "Ask Trip Assistant in \(.applicationName)",
                "Ask \(.applicationName) about my trip",
                "Tell \(.applicationName) about my trip",
                "Tell \(.applicationName) I'm driving",
                "Ask \(.applicationName) about driving",
                "Ask \(.applicationName) how far I can drive before twenty percent",
                "Ask \(.applicationName) how many times I need to charge",
                "Ask \(.applicationName) how far between charging stops"
            ],
            shortTitle: "Ask Trip",
            systemImageName: "sparkle.magnifyingglass"
        )
    }
}

private struct MiniRangeTripIntentEstimate {
    let distanceKm: Double
    let routeEstimate: RouteDistanceEstimate?
    let roadTypeSelection: TripRoadTypeSelection.Result
    let temperature: Double
    let forecast: ForecastResult

    static func resolve(
        parsedInput: NaturalLanguageTripEstimateInput,
        settings: MiniConsumptionSettingsSnapshot,
        temperatureOverride: Double?,
        planningModeOverride: PlanningMode?
    ) async -> Self? {
        let routeEstimate = await routeEstimate(for: parsedInput.route)
        guard let distanceKm = parsedInput.plannedDistanceKm ?? routeEstimate?.distanceKm else {
            return nil
        }

        let roadTypeSelection = TripRoadTypeSelection.resolve(
            parsedRoadType: parsedInput.roadTypeProfile,
            hasExplicitRoadTypeWording: parsedInput.hasExplicitRoadTypeWording,
            distanceKm: distanceKm,
            currentRoadType: settings.roadTypeProfile,
            routeAverageSpeedKmh: routeEstimate?.averageSpeedKmh
        )
        let resolvedTemperature = temperatureOverride.map(settings.temperatureUnits.storedTemperature(fromDisplayed:))
            ?? parsedInput.temperature
            ?? settings.temperature
        let resolvedPlanningMode = planningModeOverride ?? parsedInput.planningMode ?? settings.planningMode

        let forecast = settings.forecast(
            distance: max(1, distanceKm),
            temperature: resolvedTemperature,
            roadTypeProfile: roadTypeSelection.roadTypeProfile,
            motorwaySpeed: parsedInput.motorwaySpeed ?? settings.motorwaySpeed,
            roadSurface: parsedInput.roadSurface ?? settings.roadSurface,
            windCondition: parsedInput.windCondition ?? settings.windCondition,
            planningMode: resolvedPlanningMode
        )

        return Self(
            distanceKm: max(1, distanceKm),
            routeEstimate: routeEstimate,
            roadTypeSelection: roadTypeSelection,
            temperature: resolvedTemperature,
            forecast: forecast
        )
    }

    private static func routeEstimate(for route: TripRouteDescription?) async -> RouteDistanceEstimate? {
        guard let route else {
            return nil
        }

        if let origin = route.origin {
            return try? await RouteDistanceService.estimatedDrivingRoute(from: origin, to: route.destination)
        }

        return try? await RouteDistanceService.estimatedDrivingRouteFromCurrentLocation(to: route.destination)
    }
}

private extension NaturalLanguageTripEstimateInput {
    func mergingForIntentClarification(with additionalInput: NaturalLanguageTripEstimateInput) -> Self {
        var updatedInput = self
        updatedInput.plannedDistanceKm = plannedDistanceKm ?? additionalInput.plannedDistanceKm
        updatedInput.route = route ?? additionalInput.route
        updatedInput.batteryPercentage = batteryPercentage ?? additionalInput.batteryPercentage
        if hasExplicitRoadTypeWording {
            updatedInput.roadTypeProfile = roadTypeProfile
        } else if additionalInput.hasExplicitRoadTypeWording {
            updatedInput.roadTypeProfile = additionalInput.roadTypeProfile
        } else {
            updatedInput.roadTypeProfile = roadTypeProfile ?? additionalInput.roadTypeProfile
        }
        updatedInput.hasExplicitRoadTypeWording = hasExplicitRoadTypeWording || additionalInput.hasExplicitRoadTypeWording
        updatedInput.motorwaySpeed = motorwaySpeed ?? additionalInput.motorwaySpeed
        updatedInput.temperature = temperature ?? additionalInput.temperature
        updatedInput.roadSurface = roadSurface ?? additionalInput.roadSurface
        updatedInput.windCondition = windCondition ?? additionalInput.windCondition
        updatedInput.planningMode = planningMode ?? additionalInput.planningMode
        updatedInput.chargingPreference = chargingPreference ?? additionalInput.chargingPreference
        updatedInput.batteryThresholdQuestionPercent = batteryThresholdQuestionPercent
            ?? additionalInput.batteryThresholdQuestionPercent

        return updatedInput
    }
}

private func normalizeBatteryPercentInput(_ value: Double) -> Double {
    guard value.isFinite, value > 0 else {
        return 0
    }

    let normalizedValue: Double
    switch value {
    case ..<1:
        normalizedValue = value * 100
    case ...100:
        normalizedValue = value
    case ...1_000:
        normalizedValue = value / 10
    case ...10_000:
        normalizedValue = value / 100
    case ...100_000:
        normalizedValue = value / 1_000
    default:
        normalizedValue = value
    }

    return clampedBatteryPercentForDisplay(normalizedValue)
}

private func clampedBatteryPercentForDisplay(_ value: Double) -> Double {
    guard value.isFinite else {
        return 0
    }

    return min(max(value, 0), 100)
}

private func formattedBatteryPercent(_ value: Double) -> String {
    "\(Int(clampedBatteryPercentForDisplay(value).rounded())) percent"
}

private func spokenChargingTime(_ minutes: Double) -> String {
    let roundedMinutes = Int(minutes.rounded())
    if roundedMinutes < 60 {
        return "\(roundedMinutes) minutes"
    }

    let hours = roundedMinutes / 60
    let remainingMinutes = roundedMinutes % 60
    if remainingMinutes == 0 {
        return "\(hours) \(hours == 1 ? "hour" : "hours")"
    }

    return "\(hours) \(hours == 1 ? "hour" : "hours") \(remainingMinutes) minutes"
}

extension RoadTypeProfile: AppEnum {
    nonisolated static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Road Profile")
    }

    nonisolated static var caseDisplayRepresentations: [RoadTypeProfile: DisplayRepresentation] {
        [
            .cityMix: DisplayRepresentation(title: "City mix"),
            .countryside: DisplayRepresentation(title: "Calm roads"),
            .motorwayMix: DisplayRepresentation(title: "Motorway mix"),
            .motorway: DisplayRepresentation(title: "Motorway"),
        ]
    }
}

extension RoadSurface: AppEnum {
    nonisolated static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Road Surface")
    }

    nonisolated static var caseDisplayRepresentations: [RoadSurface: DisplayRepresentation] {
        [
            .dry: DisplayRepresentation(title: "Dry"),
            .damp: DisplayRepresentation(title: "Damp"),
            .wet: DisplayRepresentation(title: "Wet"),
            .heavyRain: DisplayRepresentation(title: "Heavy rain"),
            .snowSlush: DisplayRepresentation(title: "Snow or slush")
        ]
    }
}

extension WindCondition: AppEnum {
    nonisolated static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Wind")
    }

    nonisolated static var caseDisplayRepresentations: [WindCondition: DisplayRepresentation] {
        [
            .tailwind: DisplayRepresentation(title: "Tailwind"),
            .normal: DisplayRepresentation(title: "Normal"),
            .headwind: DisplayRepresentation(title: "Headwind")
        ]
    }
}

extension PlanningMode: AppEnum {
    nonisolated static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Planning Mode")
    }

    nonisolated static var caseDisplayRepresentations: [PlanningMode: DisplayRepresentation] {
        [
            .conservative: DisplayRepresentation(title: "Cautious"),
            .normal: DisplayRepresentation(title: "Normal"),
            .optimistic: DisplayRepresentation(title: "Optimistic")
        ]
    }
}
