import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

struct NaturalLanguageTripEstimateInput {
    var batteryPercentage: Double?
    var plannedDistanceKm: Double?
    var route: TripRouteDescription?
    var chargingPreference: ChargingPreference?
    var batteryThresholdQuestionPercent: Double?
    var roadTypeProfile: RoadTypeProfile?
    var hasExplicitRoadTypeWording: Bool
    var motorwaySpeed: Double?
    var temperature: Double?
    var roadSurface: RoadSurface?
    var windCondition: WindCondition?
    var planningMode: PlanningMode?
}

enum ChargingPreference: Equatable {
    case balanced
    case minimumStops
    case shortStops(maxMinutesPerStop: Double?)
    case maxMinutesPerStop(Double)
    case questionStopsOnly
    case questionLegRangeOnly

    var label: String {
        switch self {
        case .balanced:
            return "Balanced"
        case .minimumStops:
            return "Fewer stops"
        case .shortStops(let maxMinutesPerStop):
            if let maxMinutesPerStop {
                return "Short stops, max ~\(maxMinutesPerStop.formatted(.number.precision(.fractionLength(0)))) min"
            }

            return "Short stops"
        case .maxMinutesPerStop(let minutes):
            return "Max ~\(minutes.formatted(.number.precision(.fractionLength(0)))) min per stop"
        case .questionStopsOnly:
            return "Question: charging stops"
        case .questionLegRangeOnly:
            return "Question: leg range"
        }
    }
}

struct TripRouteDescription {
    let origin: String?
    let destination: String

    nonisolated init?(origin: String?, destination: String?) {
        guard let destination, !destination.isEmpty else {
            return nil
        }

        if let origin, RouteEndpointNormalizer.areNearDuplicates(origin, destination) {
            self.origin = nil
        } else {
            self.origin = origin?.isEmpty == true ? nil : origin
        }
        self.destination = destination
    }

    nonisolated init(origin: String?, destination: String) {
        if let origin, RouteEndpointNormalizer.areNearDuplicates(origin, destination) {
            self.origin = nil
        } else {
            self.origin = origin
        }
        self.destination = destination
    }
}

enum NaturalLanguageTripParser {
    static func parse(_ description: String) async -> NaturalLanguageTripEstimateInput {
        let deterministicInput = NaturalLanguageTripHeuristicParser.parse(description)
#if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            if let modelInput = await FoundationModelsTripParser.parse(description) {
                let input = modelInput.validated
                    .sanitizingRoute()
                    .mergingDeterministicValues(from: deterministicInput)
                    .sanitizingRoute()
                    .requiringExplicitRouteOrigin(in: description)
                    .groundingRoute(in: description)
                    .applyingFallbackDestination(from: description)
                    .markingExplicitRoadTypeWording(in: description)
                return input
            }
        }

        let input = deterministicInput
            .sanitizingRoute()
            .requiringExplicitRouteOrigin(in: description)
            .groundingRoute(in: description)
            .applyingFallbackDestination(from: description)
            .markingExplicitRoadTypeWording(in: description)
        return input
#else
        let input = deterministicInput
            .sanitizingRoute()
            .requiringExplicitRouteOrigin(in: description)
            .groundingRoute(in: description)
            .applyingFallbackDestination(from: description)
            .markingExplicitRoadTypeWording(in: description)
        return input
#endif
    }
}

enum TripRoadTypeSelection {
    struct Result {
        let roadTypeProfile: RoadTypeProfile
        let usedFallback: Bool
    }

    static func resolve(
        parsedRoadType: RoadTypeProfile?,
        hasExplicitRoadTypeWording: Bool,
        distanceKm: Double?,
        currentRoadType: RoadTypeProfile,
        routeAverageSpeedKmh: Double? = nil
    ) -> Result {
        if hasExplicitRoadTypeWording, let parsedRoadType {
            return Result(roadTypeProfile: parsedRoadType, usedFallback: false)
        }

        guard let distanceKm else {
            return Result(roadTypeProfile: currentRoadType, usedFallback: false)
        }

        let fallbackRoadType: RoadTypeProfile = distanceKm <= 20 ? .cityMix : .motorwayMix
        let resolvedRoadType = fallbackRoadType == .motorwayMix && routeAverageSpeedKmh.map { $0 > 95 } == true
            ? RoadTypeProfile.motorway
            : fallbackRoadType

        return Result(roadTypeProfile: resolvedRoadType, usedFallback: true)
    }
}

#if canImport(FoundationModels)
@available(iOS 26.0, *)
@Generable
struct FoundationModelsTripExtraction {
    @Guide(description: "Battery percentage as a number from 0 to 100, if explicitly mentioned.")
    var batteryPercentage: Double?

    @Guide(description: "Planned trip distance in kilometers, if explicitly mentioned.")
    var plannedDistanceKm: Double?

    @Guide(description: "Trip origin or start place text, if explicitly mentioned. Extract only the place name, not battery, weather, or other trip conditions.")
    var originText: String?

    @Guide(description: "Trip destination place text, if explicitly mentioned. Extract only the place name, not battery, weather, or other trip conditions.")
    var destinationText: String?

    @Guide(description: "Road type profile. Use cityMix, countryside, motorwayMix, or motorway.")
    var roadTypeProfile: String?

    @Guide(description: "Motorway speed in km/h, if explicitly mentioned.")
    var motorwaySpeed: Double?

    @Guide(description: "Temperature in Celsius, if explicitly mentioned. Convert Fahrenheit mentions to Celsius.")
    var temperature: Double?

    @Guide(description: "Road surface. Use dry, damp, wet, heavyRain, or snowSlush.")
    var roadSurface: String?

    @Guide(description: "Wind condition. Use tailwind, normal, or headwind.")
    var windCondition: String?

    @Guide(description: "Planning mode. Use conservative, normal, or optimistic.")
    var planningMode: String?
}

@available(iOS 26.0, *)
enum FoundationModelsTripParser {
    static func parse(_ description: String) async -> FoundationModelsTripExtraction? {
        let model = SystemLanguageModel.default
        guard model.isAvailable else {
            return nil
        }

        let session = LanguageModelSession(
            model: model,
            instructions: """
            Extract only structured trip-planning fields for Mini Range.
            Do not answer the user's driving question.
            Do not invent missing numbers.
            Extract originText and destinationText when the user names a start place, origin, destination, or place they are going to.
            Keep originText and destinationText as clean place names only.
            Leave plannedDistanceKm empty unless the user explicitly states a distance.
            Use roadTypeProfile mapping:
            mostly motorway, highway, or freeway = motorway;
            mixed roads, some motorway, or some local roads = motorwayMix;
            city, local, urban, or suburban roads = cityMix;
            calm roads, country roads, countryside, regional roads, or back roads = countryside.
            """
        )

        do {
            let response = try await session.respond(
                to: description,
                generating: FoundationModelsTripExtraction.self
            )
            return response.content
        } catch {
            return nil
        }
    }
}

@available(iOS 26.0, *)
extension FoundationModelsTripExtraction {
    var validated: NaturalLanguageTripEstimateInput {
        NaturalLanguageTripEstimateInput(
            batteryPercentage: validatedPercent(batteryPercentage),
            plannedDistanceKm: validatedPositive(plannedDistanceKm),
            route: TripRouteDescription(
                origin: cleanedRouteEndpoint(originText),
                destination: cleanedRouteEndpoint(destinationText)
            ),
            chargingPreference: nil,
            batteryThresholdQuestionPercent: nil,
            roadTypeProfile: RoadTypeProfile(naturalLanguageValue: roadTypeProfile),
            hasExplicitRoadTypeWording: false,
            motorwaySpeed: validatedMotorwaySpeed(motorwaySpeed),
            temperature: temperature,
            roadSurface: RoadSurface(naturalLanguageValue: roadSurface),
            windCondition: WindCondition(naturalLanguageValue: windCondition),
            planningMode: PlanningMode(naturalLanguageValue: planningMode)
        )
    }
}
#endif

enum NaturalLanguageTripHeuristicParser {
    static func parse(_ description: String) -> NaturalLanguageTripEstimateInput {
        let text = description.lowercased()
        let plannedDistanceKm = explicitDistanceKm(in: text)
        let batteryThresholdQuestionPercent = batteryThresholdQuestionPercent(in: text)
        let batteryPercentage = if let batteryThresholdQuestionPercent {
            startingBatteryPercent(in: text, excluding: batteryThresholdQuestionPercent)
        } else {
            firstNumber(in: text, near: ["percent", "procent", "%", "battery", "batteri"]).flatMap(validatedPercent)
        }

        return NaturalLanguageTripEstimateInput(
            batteryPercentage: batteryPercentage,
            plannedDistanceKm: plannedDistanceKm.flatMap(validatedPositive),
            route: route(in: description),
            chargingPreference: chargingPreference(in: text),
            batteryThresholdQuestionPercent: batteryThresholdQuestionPercent,
            roadTypeProfile: RoadTypeProfile(naturalLanguageValue: text),
            hasExplicitRoadTypeWording: explicitRoadTypeWordingDetected(in: description),
            motorwaySpeed: firstNumber(in: text, near: ["km/h", "kph", "motorway speed", "speed"]).flatMap(validatedMotorwaySpeed),
            temperature: firstTemperatureNumber(in: text),
            roadSurface: RoadSurface(naturalLanguageValue: text),
            windCondition: WindCondition(naturalLanguageValue: text),
            planningMode: PlanningMode(naturalLanguageValue: text)
        )
    }

    private static func explicitDistanceKm(in text: String) -> Double? {
        if let kilometers = firstNumber(in: text, near: ["kilometer", "kilometers", "kilometre", "kilometres", "km"]) {
            return kilometers
        }

        if let miles = firstNumber(in: text, near: ["mile", "miles", "mi"]) {
            return miles * 1.60934
        }

        return nil
    }

    private static func batteryThresholdQuestionPercent(in text: String) -> Double? {
        guard containsAny(text, [
            "hur långt",
            "hur langt",
            "hur långt kan jag köra",
            "hur langt kan jag kora",
            "kommer jag innan",
            "innan jag har",
            "innan batteriet",
            "how far",
            "how far can i drive",
            "how far until",
            "before i reach",
            "before battery",
            "down to"
        ]) else {
            return nil
        }

        guard containsAny(text, [
            "batteri",
            "batteriet",
            "battery",
            "procent",
            "percent",
            "%"
        ]) else {
            return nil
        }

        let patterns = [
            #"(?:innan jag har|innan batteriet är nere på|innan batteriet ar nere pa|before i reach|before battery(?: is)?(?: down)?(?: to)?|until i'?m down to|until i am down to|down to)\s+(\d+(?:[.,]\d+)?)\s*(?:%|procent|percent)?"#,
            #"(\d+(?:[.,]\d+)?)\s*(?:%|procent|percent)\??$"#
        ]

        for pattern in patterns {
            guard
                let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
                let match = regex.firstMatch(
                    in: text,
                    range: NSRange(text.startIndex..<text.endIndex, in: text)
                ),
                match.numberOfRanges == 2,
                let range = Range(match.range(at: 1), in: text),
                let percent = Double(text[range].replacingOccurrences(of: ",", with: ".")).flatMap(validatedPercent)
            else {
                continue
            }

            return percent
        }

        return nil
    }

    private static func startingBatteryPercent(in text: String, excluding thresholdPercent: Double) -> Double? {
        let pattern = #"(\d+(?:[.,]\d+)?)\s*(?:%|procent|percent)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }

        let matches = regex.matches(
            in: text,
            range: NSRange(text.startIndex..<text.endIndex, in: text)
        )

        for match in matches {
            guard let range = Range(match.range(at: 1), in: text),
                  let percent = Double(text[range].replacingOccurrences(of: ",", with: ".")).flatMap(validatedPercent),
                  abs(percent - thresholdPercent) > 0.001 else {
                continue
            }

            return percent
        }

        return nil
    }

    private static func chargingPreference(in text: String) -> ChargingPreference? {
        if containsAny(text, [
            "hur långt kan jag köra mellan laddstoppen",
            "hur langt kan jag kora mellan laddstoppen",
            "mellan laddstoppen",
            "between charging stops",
            "between charge stops",
            "drive between charging stops",
            "80-10"
        ]) {
            return .questionLegRangeOnly
        }

        if containsAny(text, [
            "hur många gånger måste jag ladda",
            "hur manga ganger maste jag ladda",
            "hur många gånger behöver jag ladda",
            "hur manga ganger behover jag ladda",
            "how many times do i need to charge",
            "how many charging stops",
            "how many times must i charge"
        ]) {
            return .questionStopsOnly
        }

        if let minutes = maxChargingMinutesPerStop(in: text) {
            return .maxMinutesPerStop(minutes)
        }

        if containsAny(text, [
            "korta laddstopp",
            "kortare laddstopp",
            "short charging stops",
            "short charge stops",
            "plan with short"
        ]) {
            return .shortStops(maxMinutesPerStop: nil)
        }

        if containsAny(text, [
            "så få gånger som möjligt",
            "sa fa ganger som mojligt",
            "helst inte ladda så många gånger",
            "helst inte ladda sa manga ganger",
            "färre längre stopp",
            "farre langre stopp",
            "få laddstopp",
            "fa laddstopp",
            "as few stops as possible",
            "few charging stops",
            "fewer longer stops",
            "minimum stops"
        ]) {
            return .minimumStops
        }

        return nil
    }

    private static func maxChargingMinutesPerStop(in text: String) -> Double? {
        let patterns = [
            #"(?:max|maximalt|maximum|inte mer än|inte mer an|inte ladda mer än|inte ladda mer an|no more than|don['’]?t want to charge more than)\s+(\d+(?:[.,]\d+)?)\s*(?:min|minuter|minutes?)\s*(?:per|varje)?\s*(?:laddstopp|stopp|charging stop|charge stop)?"#,
            #"(\d+(?:[.,]\d+)?)\s*(?:min|minuter|minutes?)\s*(?:per|varje)\s*(?:laddstopp|stopp|charging stop|charge stop)"#
        ]

        for pattern in patterns {
            guard
                let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
                let match = regex.firstMatch(
                    in: text,
                    range: NSRange(text.startIndex..<text.endIndex, in: text)
                ),
                match.numberOfRanges == 2,
                let range = Range(match.range(at: 1), in: text),
                let minutes = Double(text[range].replacingOccurrences(of: ",", with: "."))
            else {
                continue
            }

            guard minutes > 0 else {
                continue
            }

            return minutes
        }

        return nil
    }

    private static func containsAny(_ text: String, _ needles: [String]) -> Bool {
        needles.contains { text.contains($0) }
    }

    private static func firstTemperatureNumber(in text: String) -> Double? {
        if let explicitFahrenheit = firstNumber(in: text, followedBy: ["°f", " °f", " f", " fahrenheit"]) {
            return TemperatureUnits.fahrenheit.storedTemperature(fromDisplayed: explicitFahrenheit)
        }

        if let explicitCelsius = firstNumber(in: text, followedBy: ["°c", " °c", " c", " celsius"]) {
            return explicitCelsius
        }

        if let explicitDegrees = firstNumber(in: text, followedBy: ["°", " grader", " degrees"]) {
            return explicitDegrees
        }

        return firstNumber(in: text, near: ["celsius", "temperature", "temperatur", "varmt"])
    }

    private static func firstNumber(in text: String, near keywords: [String]) -> Double? {
        let pattern = #"[-+]?\d+(?:[.,]\d+)?"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }

        let matches = regex.matches(
            in: text,
            range: NSRange(text.startIndex..<text.endIndex, in: text)
        )

        for match in matches {
            guard let range = Range(match.range, in: text) else {
                continue
            }

            let windowStart = text.index(range.lowerBound, offsetBy: -25, limitedBy: text.startIndex) ?? text.startIndex
            let windowEnd = text.index(range.upperBound, offsetBy: 25, limitedBy: text.endIndex) ?? text.endIndex
            let window = String(text[windowStart..<windowEnd])
            guard keywords.contains(where: window.contains) else {
                continue
            }

            return Double(text[range].replacingOccurrences(of: ",", with: "."))
        }

        return nil
    }

    private static func firstNumber(in text: String, followedBy suffixes: [String]) -> Double? {
        let pattern = #"[-+]?\d+(?:[.,]\d+)?"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }

        let matches = regex.matches(
            in: text,
            range: NSRange(text.startIndex..<text.endIndex, in: text)
        )

        for match in matches {
            guard let range = Range(match.range, in: text) else {
                continue
            }

            let suffixEnd = text.index(range.upperBound, offsetBy: 12, limitedBy: text.endIndex) ?? text.endIndex
            let suffix = String(text[range.upperBound..<suffixEnd])
            guard suffixes.contains(where: { suffix.hasPrefix($0) }) else {
                continue
            }

            return Double(text[range].replacingOccurrences(of: ",", with: "."))
        }

        return nil
    }

    private static func route(in description: String) -> TripRouteDescription? {
        if hasExplicitRouteSeparator(description),
           let route = originDestinationRoute(in: description) {
            return route
        }

        if hasExplicitRouteSeparator(description),
           let route = destinationOriginRoute(in: description) {
            return route
        }

        let origin = explicitOrigin(in: description)
        let destination = explicitDestination(in: description)
        if let route = TripRouteDescription(origin: origin, destination: destination) {
            return route
        }

        return destination.map { TripRouteDescription(origin: nil, destination: $0) }
    }

    private static func originDestinationRoute(in description: String) -> TripRouteDescription? {
        let patterns = [
            #"\b(?:från|fran|from|de|desde|da|von)\s+([^.!?;]+?)\s+(?:till|to|à|a|al|hacia|nach)\s+([^.!?;]+?)(?=$|[.!?;]|\s+(?:med|with|and|och|battery|batteri)\b)"#,
            #"^\s*(?!(?:drive|go|travel|route|navigate|köra|kora|åka|aka|resa|navigera)\b)([^.!?;]+?)\s+(?:till|to)\s+([^.!?;]+?)(?=$|[.!?;]|\s+(?:med|with|and|och|battery|batteri)\b)"#,
            #"^\s*([^.!?;]+?)\s*(?:->|→)\s*([^.!?;]+?)(?=$|[.!?;]|\s+(?:med|with|and|och|battery|batteri)\b)"#
        ]

        for pattern in patterns {
            guard
                let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
                let match = regex.firstMatch(
                    in: description,
                    range: NSRange(description.startIndex..<description.endIndex, in: description)
                ),
                match.numberOfRanges == 3,
                let originRange = Range(match.range(at: 1), in: description),
                let destinationRange = Range(match.range(at: 2), in: description)
            else {
                continue
            }

            let origin = cleanedRouteEndpoint(String(description[originRange]))
            let destination = cleanedRouteEndpoint(String(description[destinationRange]))
            guard !origin.isEmpty, !destination.isEmpty else {
                continue
            }

            return TripRouteDescription(origin: origin, destination: destination)
        }

        return nil
    }

    private static func destinationOriginRoute(in description: String) -> TripRouteDescription? {
        let patterns = [
            #"\b(?:till|to|à|a|al|hacia|nach)\s+([^.!?;]+?)\s+(?:från|fran|from|de|desde|da|von)\s+([^.!?;]+?)(?=$|[.!?;]|\s+(?:med|with|and|och|battery|batteri)\b)"#
        ]

        for pattern in patterns {
            guard
                let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
                let match = regex.firstMatch(
                    in: description,
                    range: NSRange(description.startIndex..<description.endIndex, in: description)
                ),
                match.numberOfRanges == 3,
                let destinationRange = Range(match.range(at: 1), in: description),
                let originRange = Range(match.range(at: 2), in: description)
            else {
                continue
            }

            let origin = cleanedRouteEndpoint(String(description[originRange]))
            let destination = cleanedRouteEndpoint(String(description[destinationRange]))
            guard !origin.isEmpty, !destination.isEmpty else {
                continue
            }

            return TripRouteDescription(origin: origin, destination: destination)
        }

        return nil
    }

    private static func explicitOrigin(in description: String) -> String? {
        firstEndpoint(
            in: description,
            patterns: [
                #"\b(?:startpunkt|utgångspunkt|origin|start|starting point|origen|départ|partenza)\s*(?:är|is|=|:)\s+(.+?)(?=$|[.!?;])"#,
                #"\b(?:jag är på|jag är i|jag startar från|jag börjar från|i(?:'|’)?m starting from|i am starting from|i start from|starting from)\s+(.+?)(?=$|[.!?;])"#
            ]
        )
    }

    private static func explicitDestination(in description: String) -> String? {
        firstEndpoint(
            in: description,
            patterns: [
                #"\b(?:destination|mål|destino|ziel|destinationen)\s*(?:är|is|=|:)\s+(.+?)(?=$|[.!?;])"#,
                #"\b(?:jag ska|jag åker|jag aker|jag kör|jag kor|i(?:'|’)?m going|i am going|i go|i drive|drive|go)\s+(?:till|to|à|a|al|hacia|nach)\s+(.+?)(?=$|[.!?;]|\s+(?:från|fran|from|de|desde|da|von|med|with|and|och|battery|batteri)\b)"#,
                #"^\s*(?:till|to|à|a|al|hacia|nach)\s+(.+?)(?=$|[.!?;]|\s+(?:från|fran|from|de|desde|da|von|med|with|and|och|battery|batteri)\b)"#
            ]
        )
    }

    private static func firstEndpoint(in description: String, patterns: [String]) -> String? {
        for pattern in patterns {
            guard
                let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
                let match = regex.firstMatch(
                    in: description,
                    range: NSRange(description.startIndex..<description.endIndex, in: description)
                ),
                match.numberOfRanges == 2,
                let range = Range(match.range(at: 1), in: description)
            else {
                continue
            }

            let endpoint = cleanedRouteEndpoint(String(description[range]))
            if !endpoint.isEmpty {
                return endpoint
            }
        }

        return nil
    }
}

nonisolated func cleanedRouteEndpoint(_ value: String?) -> String? {
    guard let value else {
        return nil
    }

    let cleaned = cleanedRouteEndpoint(value)
    return cleaned.isEmpty ? nil : cleaned
}

nonisolated func cleanedRouteEndpoint(_ value: String) -> String {
    var endpoint = value.trimmingCharacters(in: .whitespacesAndNewlines)
    let stopPatterns = [
        #"\s+(?:från|fran|from|de|desde|da|von|med|with|and|och|battery|batteri|har|have|it is|det är|det ar)\b.*$"#,
        #",\s*(?:\d|battery|batteri|temperature|temperatur).*$"#,
        #"\s+\d+\s*(?:%|percent|procent|°|grader|degrees)\b.*$"#
    ]

    for pattern in stopPatterns {
        endpoint = endpoint.replacingOccurrences(
            of: pattern,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
    }

    endpoint = endpoint.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
    return endpoint
}

extension NaturalLanguageTripEstimateInput {
    func mergingDeterministicValues(from deterministicInput: NaturalLanguageTripEstimateInput) -> Self {
        let mergedRoute = deterministicInput.route ?? route
        let mergedPlannedDistance = deterministicInput.plannedDistanceKm ?? plannedDistanceKm

        return Self(
            batteryPercentage: deterministicInput.batteryPercentage ?? batteryPercentage,
            plannedDistanceKm: mergedPlannedDistance,
            route: mergedRoute,
            chargingPreference: deterministicInput.chargingPreference ?? chargingPreference,
            batteryThresholdQuestionPercent: deterministicInput.batteryThresholdQuestionPercent ?? batteryThresholdQuestionPercent,
            roadTypeProfile: roadTypeProfile ?? deterministicInput.roadTypeProfile,
            hasExplicitRoadTypeWording: hasExplicitRoadTypeWording || deterministicInput.hasExplicitRoadTypeWording,
            motorwaySpeed: deterministicInput.motorwaySpeed ?? motorwaySpeed,
            temperature: deterministicInput.temperature ?? temperature,
            roadSurface: roadSurface ?? deterministicInput.roadSurface,
            windCondition: windCondition ?? deterministicInput.windCondition,
            planningMode: planningMode ?? deterministicInput.planningMode
        )
    }

    func sanitizingRoute() -> Self {
        guard let route else {
            return self
        }

        var input = self
        input.route = TripRouteDescription(origin: route.origin, destination: route.destination)
        return input
    }

    func requiringExplicitRouteOrigin(in description: String) -> Self {
        guard let route, !hasExplicitRouteSeparator(description) else {
            return self
        }

        var input = self
        if let destination = fallbackDestinationCandidate(from: description) {
            input.route = TripRouteDescription(origin: nil, destination: destination)
        } else if route.origin != nil {
            input.route = TripRouteDescription(origin: nil, destination: route.destination)
        }
        return input
    }

    func groundingRoute(in description: String) -> Self {
        guard let route else {
            return self
        }

        guard RouteEndpointGrounder.isGrounded(route.destination, in: description) else {
            var input = self
            input.route = nil
            return input
        }

        let groundedOrigin = route.origin.flatMap {
            RouteEndpointGrounder.isGrounded($0, in: description) ? $0 : nil
        }

        var input = self
        input.route = TripRouteDescription(origin: groundedOrigin, destination: route.destination)
        return input
    }

    func applyingFallbackDestination(from description: String) -> Self {
        guard route == nil,
              plannedDistanceKm == nil,
              let destination = fallbackDestinationCandidate(from: description) else {
            return self
        }

        var input = self
        input.route = TripRouteDescription(origin: nil, destination: destination)
        return input
    }

    func markingExplicitRoadTypeWording(in description: String) -> Self {
        var input = self
        input.hasExplicitRoadTypeWording = explicitRoadTypeWordingDetected(in: description)
        return input
    }
}

func explicitRoadTypeWordingDetected(in description: String) -> Bool {
    let text = description
        .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "sv_SE"))
        .lowercased()

    let patterns = [
        #"\b(?:city|town|urban|across town|stad|stadskorning)\b"#,
        #"\b(?:calm roads?|back roads?|country roads?|countryside|regional roads?|smaller roads?|avoid motorway|landsvag|smavagar|undvik motorvag)\b"#,
        #"\b(?:motorway mix|mixed roads?|mixed|some motorway|partly motorway|blandat|delvis motorvag)\b"#,
        #"\b(?:mostly motorway|mainly motorway|motorway|highway|freeway|motorvag|mest motorvag|e4|e20)\b"#
    ]

    return patterns.contains { pattern in
        text.range(of: pattern, options: .regularExpression) != nil
    }
}

func hasExplicitRouteSeparator(_ text: String) -> Bool {
    let patterns = [
        #"\b(?:från|fran|from)\b.+\b(?:till|to)\b"#,
        #"\b(?:till|to)\b.+\b(?:från|fran|from)\b"#,
        #"\b(?:till|to)\b"#,
        #"->|→"#
    ]

    return patterns.contains { pattern in
        text.range(of: pattern, options: [.regularExpression, .caseInsensitive, .diacriticInsensitive]) != nil
    }
}

func fallbackDestinationCandidate(from description: String) -> String? {
    var text = description.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else {
        return nil
    }

    let distancePattern = #"\b(?:\d+(?:[.,]\d+)?\s*)?(?:km|kilometer|kilometers|kilometre|kilometres|mi|mile|miles)\b"#
    if text.range(of: distancePattern, options: [.regularExpression, .caseInsensitive]) != nil {
        return nil
    }

    let trailingSentencePattern = #"[.!?;].*\S"#
    if text.range(of: trailingSentencePattern, options: .regularExpression) != nil {
        return nil
    }

    let leadingTravelPattern = #"^\s*(?:(?:drive|go|travel|route|navigate)\s+(?:to|towards)|(?:köra|kora|åka|aka|resa|navigera)\s+(?:till|mot)|(?:to|till|mot|towards))\s+"#
    text = text.replacingOccurrences(
        of: leadingTravelPattern,
        with: "",
        options: [.regularExpression, .caseInsensitive]
    )

    let routeSeparatorPattern = #"\b(?:från|fran|from|de|desde|da|von)\b.+\b(?:till|to|à|a|al|hacia|nach)\b|\b(?:till|to|à|a|al|hacia|nach)\b.+\b(?:från|fran|from|de|desde|da|von)\b|.+\s+\b(?:till|to|à|al|hacia|nach)\b\s+.+"#
    if text.range(of: routeSeparatorPattern, options: [.regularExpression, .caseInsensitive]) != nil {
        return nil
    }

    text = cleanedRouteEndpoint(text)
    guard !text.isEmpty, text.count <= 40 else {
        return nil
    }

    let words = text.components(separatedBy: CharacterSet.whitespacesAndNewlines).filter { !$0.isEmpty }
    guard (1...4).contains(words.count) else {
        return nil
    }

    let normalizedWords = words.map {
        $0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "sv_SE")).lowercased()
    }
    let blockedWords: Set<String> = [
        "how", "hur", "far", "langt", "långt", "can", "kan", "will", "kommer",
        "battery", "batteri", "batteriet", "charge", "charging", "ladda", "laddning",
        "percent", "procent", "temperature", "temperatur", "speed", "hastighet",
        "motorway", "highway", "motorvag", "motorväg"
    ]
    guard normalizedWords.allSatisfy({ !blockedWords.contains($0) }) else {
        return nil
    }

    let allowedScalars = CharacterSet.letters
        .union(.decimalDigits)
        .union(.whitespaces)
        .union(CharacterSet(charactersIn: "',’-"))
    guard text.unicodeScalars.allSatisfy({ allowedScalars.contains($0) }) else {
        return nil
    }

    return text
}

enum RouteEndpointGrounder {
    static func isGrounded(_ endpoint: String, in description: String) -> Bool {
        let endpointText = normalized(endpoint)
        let descriptionText = normalized(description)

        guard endpointText.count >= 2, descriptionText.count >= 2 else {
            return false
        }

        if descriptionText.contains(endpointText) {
            return true
        }

        let endpointTokens = tokens(in: endpoint)
        let descriptionTokens = tokens(in: description)
        guard !endpointTokens.isEmpty else {
            return false
        }

        let groundedTokenCount = endpointTokens.filter { endpointToken in
            descriptionTokens.contains { descriptionToken in
                areNearMatches(endpointToken, descriptionToken)
                    || descriptionToken.contains(endpointToken)
                    || endpointToken.contains(descriptionToken)
            }
        }.count

        return groundedTokenCount == endpointTokens.count
    }

    private static func tokens(in value: String) -> [String] {
        normalizedWords(value)
            .filter { $0.count >= 2 }
    }

    private static func normalized(_ value: String) -> String {
        normalizedWords(value).joined()
    }

    private static func normalizedWords(_ value: String) -> [String] {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "sv_SE"))
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }

    private static func areNearMatches(_ lhs: String, _ rhs: String) -> Bool {
        guard min(lhs.count, rhs.count) >= 4 else {
            return lhs == rhs
        }

        let limit = max(1, min(2, max(lhs.count, rhs.count) / 4))
        return levenshteinDistance(lhs, rhs, maximum: limit) <= limit
    }

    private static func levenshteinDistance(_ lhs: String, _ rhs: String, maximum: Int) -> Int {
        let left = Array(lhs)
        let right = Array(rhs)

        if abs(left.count - right.count) > maximum {
            return maximum + 1
        }

        var previous = Array(0...right.count)
        var current = Array(repeating: 0, count: right.count + 1)

        for leftIndex in 1...left.count {
            current[0] = leftIndex
            var rowMinimum = current[0]

            for rightIndex in 1...right.count {
                let substitutionCost = left[leftIndex - 1] == right[rightIndex - 1] ? 0 : 1
                current[rightIndex] = min(
                    previous[rightIndex] + 1,
                    current[rightIndex - 1] + 1,
                    previous[rightIndex - 1] + substitutionCost
                )
                rowMinimum = min(rowMinimum, current[rightIndex])
            }

            if rowMinimum > maximum {
                return maximum + 1
            }

            swap(&previous, &current)
        }

        return previous[right.count]
    }
}

enum RouteEndpointNormalizer {
    nonisolated static func areNearDuplicates(_ lhs: String, _ rhs: String) -> Bool {
        let left = normalized(lhs)
        let right = normalized(rhs)

        guard !left.isEmpty, !right.isEmpty else {
            return false
        }

        if left == right {
            return true
        }

        if min(left.count, right.count) >= 5, left.contains(right) || right.contains(left) {
            return true
        }

        let limit = max(1, min(3, max(left.count, right.count) / 4))
        return levenshteinDistance(left, right, maximum: limit) <= limit
    }

    private nonisolated static func normalized(_ value: String) -> String {
        var text = value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "sv_SE"))
            .lowercased()

        let artifactPatterns = [
            #"\b(?:jag|ska|skall|vill|åka|aka|köra|kora|till|to|mot|destination|mål|mal|start|från|fran|from|i|på|pa|är|ar|am|is|the|a|an)\b"#,
            #"\b(?:eh|um|uh|alltså|alltsa|typ|liksom)\b"#,
            #"\b(?:med|with|och|and|battery|batteri|procent|percent|grader|degrees|varmt|ute)\b.*$"#,
            #"\d+\s*(?:%|procent|percent|°|grader|degrees)?\b"#
        ]

        for pattern in artifactPatterns {
            text = text.replacingOccurrences(
                of: pattern,
                with: " ",
                options: [.regularExpression, .caseInsensitive]
            )
        }

        text = text
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined()

        return text
    }

    private nonisolated static func levenshteinDistance(_ lhs: String, _ rhs: String, maximum: Int) -> Int {
        let left = Array(lhs)
        let right = Array(rhs)

        if abs(left.count - right.count) > maximum {
            return maximum + 1
        }

        var previous = Array(0...right.count)
        var current = Array(repeating: 0, count: right.count + 1)

        for leftIndex in 1...left.count {
            current[0] = leftIndex
            var rowMinimum = current[0]

            for rightIndex in 1...right.count {
                let substitutionCost = left[leftIndex - 1] == right[rightIndex - 1] ? 0 : 1
                current[rightIndex] = min(
                    previous[rightIndex] + 1,
                    current[rightIndex - 1] + 1,
                    previous[rightIndex - 1] + substitutionCost
                )
                rowMinimum = min(rowMinimum, current[rightIndex])
            }

            if rowMinimum > maximum {
                return maximum + 1
            }

            swap(&previous, &current)
        }

        return previous[right.count]
    }
}

nonisolated func validatedPercent(_ value: Double?) -> Double? {
    guard let value else {
        return nil
    }

    return (0...100).contains(value) ? value : nil
}

nonisolated func validatedPositive(_ value: Double?) -> Double? {
    guard let value else {
        return nil
    }

    return value > 0 ? value : nil
}

nonisolated func validatedMotorwaySpeed(_ value: Double?) -> Double? {
    guard let value else {
        return nil
    }

    return (50...200).contains(value) ? value : nil
}

extension RoadTypeProfile {
    nonisolated init?(naturalLanguageValue value: String?) {
        guard let value else {
            return nil
        }

        let text = value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "sv_SE"))
            .lowercased()

        if text.contains("avoid motorway") || text.contains("undvik motorvag") {
            self = .countryside
        } else if text.contains("motorwaymix") || text.contains("motorway mix") {
            self = .motorwayMix
        } else if text.contains("citymix") || text.contains("city mix") {
            self = .cityMix
        } else if text.contains("motorway")
            || text.contains("highway")
            || text.contains("freeway")
            || text.contains("motorvag")
            || text.range(of: #"\be(?:4|20)\b"#, options: .regularExpression) != nil {
            if text.contains("some") || text.contains("mixed") || text.contains("partly") || text.contains("blandat") {
                self = .motorwayMix
            } else {
                self = .motorway
            }
        } else if text.contains("mixed") || text.contains("some local") || text.contains("blandat") {
            self = .motorwayMix
        } else if text.contains("city")
            || text.contains("town")
            || text.contains("local")
            || text.contains("urban")
            || text.contains("suburban")
            || text.contains("slow")
            || text.contains("stad")
            || text.contains("lokal")
            || text.contains("långsam")
            || text.contains("langsam") {
            self = .cityMix
        } else if text.contains("country")
            || text.contains("countryside")
            || text.contains("calm road")
            || text.contains("regional")
            || text.contains("back road")
            || text.contains("smaller road")
            || text.contains("landsvag")
            || text.contains("smavagar") {
            self = .countryside
        } else {
            return nil
        }
    }
}

extension RoadSurface {
    nonisolated init?(naturalLanguageValue value: String?) {
        guard let value else {
            return nil
        }

        let text = value.lowercased()
        if text.contains("snow") || text.contains("slush") || text.contains("icy") {
            self = .snowSlush
        } else if text.contains("heavy rain") || text.contains("storm") {
            self = .heavyRain
        } else if text.contains("wet") || text.contains("rain") {
            self = .wet
        } else if text.contains("damp") || text.contains("moist") {
            self = .damp
        } else if text.contains("dry") {
            self = .dry
        } else {
            return nil
        }
    }
}

extension WindCondition {
    nonisolated init?(naturalLanguageValue value: String?) {
        guard let value else {
            return nil
        }

        let text = value.lowercased()
        if text.contains("tailwind") {
            self = .tailwind
        } else if text.contains("headwind") || text.contains("windy") || text.contains("strong wind") {
            self = .headwind
        } else if text.contains("normal wind") || text.contains("calm") {
            self = .normal
        } else {
            return nil
        }
    }
}

extension PlanningMode {
    nonisolated init?(naturalLanguageValue value: String?) {
        guard let value else {
            return nil
        }

        let text = value.lowercased()
        if text.contains("cautious") || text.contains("conservative") || text.contains("safe") {
            self = .conservative
        } else if text.contains("optimistic") {
            self = .optimistic
        } else if text.contains("normal") {
            self = .normal
        } else {
            return nil
        }
    }
}
