import SwiftUI

nonisolated private let tripDrivingTimeKilometersPerMile = 1.609344
nonisolated private let tripDrivingTimeBaselineSpeedKmh = 110.0
nonisolated private let tripDrivingTimeBaselineSpeedMph = 65.0
nonisolated private let tripDrivingTimeSpeedToleranceKmh = 0.001

nonisolated func adjustedDrivingTime(
    mapsDrivingTime: TimeInterval,
    roadTypeProfile: RoadTypeProfile,
    motorwaySpeedKmh: Double,
    displayUnits: DisplayUnits
) -> TimeInterval {
    guard mapsDrivingTime > 0, motorwaySpeedKmh > 0 else {
        return mapsDrivingTime
    }

    let affectedShare = roadTypeProfile.drivingTimeAffectedShare
    guard affectedShare > 0 else {
        return mapsDrivingTime
    }

    let baselineSpeedKmh = switch displayUnits {
    case .metric:
        tripDrivingTimeBaselineSpeedKmh
    case .imperial:
        tripDrivingTimeBaselineSpeedMph * tripDrivingTimeKilometersPerMile
    }

    guard abs(motorwaySpeedKmh - baselineSpeedKmh) > tripDrivingTimeSpeedToleranceKmh else {
        return mapsDrivingTime
    }

    let unaffectedTime = mapsDrivingTime * (1 - affectedShare)
    let affectedTime = mapsDrivingTime * affectedShare
    let adjustedAffectedTime = affectedTime * (baselineSpeedKmh / motorwaySpeedKmh)

    return unaffectedTime + adjustedAffectedTime
}

private extension RoadTypeProfile {
    nonisolated var drivingTimeAffectedShare: Double {
        switch self {
        case .motorway:
            0.90
        case .motorwayMix:
            0.60
        case .cityMix, .countryside:
            0.00
        }
    }
}

struct TripChargingPresentation {
    private static let optimisedMinimumBatteryPercent = 7.0
    private static let optimisedOverTargetAllowancePercent = 8.0

    let batteryPlan: BatteryPlan
    let distanceKm: Double
    let expectedDrivingTime: TimeInterval?
    let expectedKWhPer100km: Double
    let chargingLegRangeKm: Double
    let chargingWindow: ChargingWindow
    let temperature: Double
    let averageChargingSpeedKW: Double
    let chargingSetupMinutes: Double
    let usableBatteryKWh: Double
    let chargingTaperStartSOC: Double
    let chargingSpeedBoundsKW: ClosedRange<Double>
    let displayUnits: DisplayUnits

    var chargingStopsText: String {
        guard batteryPlan.needsCharging else {
            return "0 stops"
        }

        return "\(batteryPlan.chargingStops) \(batteryPlan.chargingStops == 1 ? "stop" : "stops")"
    }

    var chargingTimeText: String {
        guard batteryPlan.needsCharging else {
            return "0 min"
        }

        return "~\(displayedTotalChargingMinutes.formatted(.number.precision(.fractionLength(0)))) min"
    }

    var expectedConsumptionText: String {
        displayUnits.formattedConsumption(expectedKWhPer100km)
    }

    func chargingStopsText(for plan: TripChargingOptionPlan?) -> String {
        guard batteryPlan.needsCharging else {
            return "0 stops"
        }

        guard let plan else {
            return chargingStopsText
        }

        return "\(plan.stops) \(plan.stops == 1 ? "stop" : "stops")"
    }

    func chargingTimeText(for plan: TripChargingOptionPlan?) -> String {
        guard batteryPlan.needsCharging else {
            return "0 min"
        }

        guard let plan else {
            return chargingTimeText
        }

        return "~\(plan.totalMinutes.formatted(.number.precision(.fractionLength(0)))) min"
    }

    var drivingTimeText: String? {
        guard let expectedDrivingTime else {
            return nil
        }

        return formattedTripTime(seconds: expectedDrivingTime)
    }

    func totalTripTimeText(for plan: TripChargingOptionPlan?) -> String? {
        guard let expectedDrivingTime else {
            return nil
        }

        let chargingSeconds = chargingMinutes(for: plan) * 60
        return "~\(formattedTripTime(seconds: expectedDrivingTime + chargingSeconds))"
    }

    var arrivalBatteryTitle: String {
        batteryPlan.needsCharging ? "Arrival reserve" : "Final battery"
    }

    var arrivalBatteryText: String {
        "~\(batteryPlan.arrivalBatteryPercent.formatted(.number.precision(.fractionLength(0))))%"
    }

    var chargingLegRangeText: String {
        displayUnits.formattedDistance(chargingLegRangeKm)
    }

    var chargingLegRangeTitle: String {
        let minimum = formattedChargingWindowPercent(chargingWindow.minimumPercent)
        let target = formattedChargingWindowPercent(chargingWindow.targetPercent)
        return "Between charges (\(minimum)-\(target)%)"
    }

    func chargingLegRangeText(for plan: TripChargingOptionPlan?) -> String {
        guard let plan, plan.option != .userSettings else {
            return chargingLegRangeText
        }

        return displayUnits.formattedDistance(plan.distanceBetweenStopsKm)
    }

    func chargingLegRangeTitle(for plan: TripChargingOptionPlan?) -> String {
        guard let plan, plan.option != .userSettings else {
            return chargingLegRangeTitle
        }

        let minimum = formattedChargingWindowPercent(chargingWindow(for: plan.option).minimumPercent)
        let target = formattedChargingWindowPercent(plan.averageTargetPercent)
        return "Between charges (\(minimum)-\(target)%)"
    }

    func coldFirstChargeNoteText(for plan: TripChargingOptionPlan?) -> String? {
        let penaltyMinutes = coldFirstChargePenaltyMinutes(
            distanceBeforeFirstStopKm: plan?.nextStopDistanceKm ?? estimatedCoreFirstLegDistanceKm
        )
        guard penaltyMinutes > 0 else {
            return nil
        }

        let roundedPenalty = max(1, Int(penaltyMinutes.rounded()))
        return "Cold battery: first fast charge may be ~\(roundedPenalty) min longer."
    }

    var chargingExamples: [ChargingExamplePresentation] {
        chargingOptionPlans.map { ChargingExamplePresentation(plan: $0, displayUnits: displayUnits) }
    }

    var reducedChargingTimeAlternative: ChargingExamplePresentation? {
        guard
            let userSettingsPlan = chargingOptionPlan(for: .userSettings),
            let shortestChargingTimePlan = chargingOptionPlan(for: .shortestChargingTime),
            shortestChargingTimePlan.totalMinutes < userSettingsPlan.totalMinutes - 0.5
        else {
            return nil
        }

        let minimum = formattedChargingWindowPercent(chargingWindow(for: shortestChargingTimePlan.option).minimumPercent)
        let target = formattedChargingWindowPercent(shortestChargingTimePlan.averageTargetPercent)
        return ChargingExamplePresentation(
            plan: shortestChargingTimePlan,
            displayUnits: displayUnits,
            strategyDetail: "Uses ~\(minimum)-\(target)% charging legs"
        )
    }

    var chargingOptionPlans: [TripChargingOptionPlan] {
        guard
            batteryPlan.chargingStops > 0,
            displayedTotalChargingMinutes > 0,
            distanceKm > 0,
            expectedKWhPer100km > 0,
            chargingLegRangeKm >= 10
        else {
            return []
        }

        guard let userSettingsPlan = plannedChargingOptionPlan(option: .userSettings) else {
            return []
        }

        return [
            plannedChargingOptionPlan(option: .shortestChargingTime),
            userSettingsPlan
        ].compactMap { $0 }
    }

    func chargingOptionPlan(for option: TripChargingOption) -> TripChargingOptionPlan? {
        chargingOptionPlans.first { $0.option == option }
    }

    private var displayedTotalChargingMinutes: Double {
        guard batteryPlan.chargingStops > 0, batteryPlan.estimatedChargingMinutes > 0 else {
            return batteryPlan.estimatedChargingMinutes
        }

        return batteryPlan.estimatedChargingMinutes + coldFirstChargePenaltyMinutes(
            distanceBeforeFirstStopKm: estimatedCoreFirstLegDistanceKm
        )
    }

    private func chargingMinutes(for plan: TripChargingOptionPlan?) -> Double {
        guard batteryPlan.needsCharging else {
            return 0
        }

        return plan?.totalMinutes ?? displayedTotalChargingMinutes
    }

    private func formattedTripTime(seconds: TimeInterval) -> String {
        let totalMinutes = max(0, Int((seconds / 60).rounded()))
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        guard hours > 0 else {
            return "\(minutes) min"
        }

        guard minutes > 0 else {
            return "\(hours) h"
        }

        return "\(hours) h \(minutes) min"
    }

    private func formattedChargingWindowPercent(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0)))
    }

    private var estimatedCoreFirstLegDistanceKm: Double {
        guard batteryPlan.chargingStops > 0 else {
            return 0
        }

        return MiniConsumptionCalculator.calculateChargingStopDistances(
            distanceKm: distanceKm,
            startBatteryPercent: batteryPlan.startBatteryPercent,
            expectedKWhPer100km: expectedKWhPer100km,
            chargingWindow: chargingWindow,
            arrivalBatteryTargetPercent: batteryPlan.reserveBatteryPercent,
            usableBatteryKWh: usableBatteryKWh
        ).first ?? distanceKm / Double(batteryPlan.chargingStops + 1)
    }

    private var baseColdFirstChargePenaltyMinutes: Double {
        switch temperature {
        case 20...:
            return 0
        case 10..<20:
            return 20 - temperature
        case 5..<10:
            return 10 + (10 - temperature)
        default:
            return 15
        }
    }

    private func coldFirstChargeDistanceMultiplier(distanceBeforeFirstStopKm: Double) -> Double {
        let anchors = [
            (distanceKm: 0.0, multiplier: 1.00),
            (distanceKm: 50.0, multiplier: 0.85),
            (distanceKm: 100.0, multiplier: 0.70),
            (distanceKm: 150.0, multiplier: 0.50),
            (distanceKm: 200.0, multiplier: 0.35)
        ]
        let distance = max(0, distanceBeforeFirstStopKm)

        guard let firstAnchor = anchors.first, let lastAnchor = anchors.last else {
            return 1
        }

        if distance <= firstAnchor.distanceKm {
            return firstAnchor.multiplier
        }

        if distance >= lastAnchor.distanceKm {
            return lastAnchor.multiplier
        }

        for index in 1..<anchors.count {
            let lowerAnchor = anchors[index - 1]
            let upperAnchor = anchors[index]

            guard distance <= upperAnchor.distanceKm else {
                continue
            }

            let progress = (distance - lowerAnchor.distanceKm) / (upperAnchor.distanceKm - lowerAnchor.distanceKm)
            return lowerAnchor.multiplier + progress * (upperAnchor.multiplier - lowerAnchor.multiplier)
        }

        return lastAnchor.multiplier
    }

    private func coldFirstChargePenaltyMinutes(distanceBeforeFirstStopKm: Double) -> Double {
        guard batteryPlan.chargingStops > 0, batteryPlan.estimatedChargingMinutes > 0 else {
            return 0
        }

        return baseColdFirstChargePenaltyMinutes
            * coldFirstChargeDistanceMultiplier(distanceBeforeFirstStopKm: distanceBeforeFirstStopKm)
    }

    private func plannedChargingOptionPlan(option: TripChargingOption) -> TripChargingOptionPlan? {
        guard let plan = chargingPlanCandidate(option: option) else {
            return nil
        }

        let roundedMinutes = max(5, roundedToNearest(plan.totalMinutes / Double(plan.stops), increment: 5))
        let optionChargingWindow = chargingWindow(for: option)

        return TripChargingOptionPlan(
            option: option,
            stops: plan.stops,
            minutesPerStop: Double(roundedMinutes),
            distanceBetweenStopsKm: plan.distanceBetweenStopsKm,
            totalMinutes: plan.totalMinutes,
            averageTargetPercent: plan.averageTargetPercent,
            finalStopTargetPercent: plan.finalStopTargetPercent,
            targetDetail: plan.finalStopTargetPercent < optionChargingWindow.targetPercent - 0.5
                ? "last stop to ~\(roundedToNearest(plan.finalStopTargetPercent, increment: 1))%"
                : "~\(roundedToNearest(plan.averageTargetPercent, increment: 1))% target",
            stopDistancesKm: plan.stopDistancesKm
        )
    }

    private func chargingPlanCandidate(option: TripChargingOption) -> ChargingPlanCandidate? {
        let optionChargingWindow = chargingWindow(for: option)
        let distanceBetweenStops = MiniConsumptionCalculator.calculateChargingLegRange(
            expectedKWhPer100km: expectedKWhPer100km,
            chargingWindow: optionChargingWindow,
            usableBatteryKWh: usableBatteryKWh
        )
        let intermediateMinimumPercent = optionChargingWindow.minimumPercent
        let defaultTargetPercent = optionChargingWindow.targetPercent
        let maximumTargetPercent = maximumTargetPercent(for: option)
        let finalArrivalTargetPercent = finalArrivalTargetPercent(for: option)
        let stopDistancesKm = MiniConsumptionCalculator.calculateChargingStopDistances(
            distanceKm: distanceKm,
            startBatteryPercent: batteryPlan.startBatteryPercent,
            expectedKWhPer100km: expectedKWhPer100km,
            chargingWindow: optionChargingWindow,
            arrivalBatteryTargetPercent: finalArrivalTargetPercent,
            usableBatteryKWh: usableBatteryKWh
        )
        let stops = stopDistancesKm.count

        guard
            stops > 0,
            distanceBetweenStops > 0
        else {
            return nil
        }

        var totalMinutes = 0.0
        var targetPercents = [Double]()
        var currentSOC = batteryPlan.startBatteryPercent
        var previousStopDistanceKm = 0.0

        for stopIndex in stopDistancesKm.indices {
            let stopDistanceKm = stopDistancesKm[stopIndex]
            let legDistanceKm = stopDistanceKm - previousStopDistanceKm
            let nextLegDistanceKm = stopIndex == stops - 1
                ? distanceKm - stopDistanceKm
                : stopDistancesKm[stopIndex + 1] - stopDistanceKm
            let legEnergyPercent = legDistanceKm * expectedKWhPer100km / 100 / usableBatteryKWh * 100
            let nextLegEnergyPercent = nextLegDistanceKm * expectedKWhPer100km / 100 / usableBatteryKWh * 100
            let arrivalSOC = currentSOC - legEnergyPercent
            guard arrivalSOC >= 0, nextLegEnergyPercent > 0 else {
                return nil
            }

            let requiredTargetPercent = stopIndex == stops - 1
                ? finalArrivalTargetPercent + nextLegEnergyPercent
                : intermediateMinimumPercent + nextLegEnergyPercent
            let targetPercent = targetPercent(
                requiredPercent: requiredTargetPercent,
                defaultTargetPercent: defaultTargetPercent,
                maximumTargetPercent: maximumTargetPercent,
                isFinalStop: stopIndex == stops - 1,
                option: option
            )

            guard targetPercent > arrivalSOC else {
                return nil
            }

            let stopChargingMinutes = MiniConsumptionCalculator.estimateSegmentedChargingMinutes(
                fromPercent: arrivalSOC,
                toPercent: targetPercent,
                averageChargingSpeedKW: averageChargingSpeedKW,
                usableBatteryKWh: usableBatteryKWh,
                chargingTaperStartSOC: chargingTaperStartSOC,
                chargingSpeedBoundsKW: chargingSpeedBoundsKW
            )
            let stopTotalMinutes = stopChargingMinutes + max(0, chargingSetupMinutes)
            totalMinutes += stopTotalMinutes
            targetPercents.append(targetPercent)
            currentSOC = targetPercent
            previousStopDistanceKm = stopDistanceKm
        }

        let finalLegDistanceKm = distanceKm - (stopDistancesKm.last ?? 0)
        let finalLegEnergyPercent = finalLegDistanceKm * expectedKWhPer100km / 100 / usableBatteryKWh * 100
        guard totalMinutes > 0, currentSOC - finalLegEnergyPercent >= finalArrivalTargetPercent - 0.1 else {
            return nil
        }

        let firstStopDistanceKm = stopDistancesKm.first ?? distanceBetweenStops
        let effectiveColdPenaltyMinutes = coldFirstChargePenaltyMinutes(distanceBeforeFirstStopKm: firstStopDistanceKm)
        let totalMinutesWithColdPenalty = totalMinutes + effectiveColdPenaltyMinutes

        return ChargingPlanCandidate(
            stops: stops,
            distanceBetweenStopsKm: distanceBetweenStops,
            totalMinutes: totalMinutesWithColdPenalty,
            averageTargetPercent: targetPercents.reduce(0, +) / Double(targetPercents.count),
            finalStopTargetPercent: targetPercents.last ?? defaultTargetPercent,
            stopDistancesKm: stopDistancesKm
        )
    }

    private var optimisedDynamicTargetPercent: Double {
        min(max(chargingTaperStartSOC, 70), 80)
    }

    private func chargingWindow(for option: TripChargingOption) -> ChargingWindow {
        switch option {
        case .shortestChargingTime:
            return ChargingWindow(
                minimumPercent: Self.optimisedMinimumBatteryPercent,
                targetPercent: optimisedDynamicTargetPercent
            )
        case .fewerStops, .userSettings:
            return chargingWindow
        }
    }

    private func finalArrivalTargetPercent(for option: TripChargingOption) -> Double {
        switch option {
        case .shortestChargingTime:
            return Self.optimisedMinimumBatteryPercent
        case .fewerStops, .userSettings:
            return batteryPlan.reserveBatteryPercent
        }
    }

    private func maximumTargetPercent(for option: TripChargingOption) -> Double {
        switch option {
        case .shortestChargingTime:
            return min(100, optimisedDynamicTargetPercent + Self.optimisedOverTargetAllowancePercent)
        case .fewerStops:
            return 100
        case .userSettings:
            return chargingWindow.targetPercent
        }
    }

    private func targetPercent(
        requiredPercent: Double,
        defaultTargetPercent: Double,
        maximumTargetPercent: Double,
        isFinalStop: Bool,
        option: TripChargingOption
    ) -> Double {
        switch option {
        case .userSettings:
            return isFinalStop ? requiredPercent : defaultTargetPercent
        case .fewerStops:
            return min(100, max(requiredPercent, defaultTargetPercent))
        case .shortestChargingTime:
            return min(maximumTargetPercent, isFinalStop ? requiredPercent : max(requiredPercent, defaultTargetPercent))
        }
    }

    private func roundedToNearest(_ value: Double, increment: Double) -> Int {
        guard increment > 0 else {
            return Int(value.rounded())
        }

        return Int((value / increment).rounded() * increment)
    }

    private func roundedLegDistance(_ distanceKm: Double, maxLegKm: Double) -> Int {
        let roundedDistance = roundedToNearest(distanceKm, increment: 10)
        guard Double(roundedDistance) <= maxLegKm else {
            return Int((maxLegKm / 10).rounded(.down) * 10)
        }

        return roundedDistance
    }

    private func roundedTotalMinutes(_ value: Double) -> Int {
        max(5, roundedToNearest(value, increment: 5))
    }

}

enum TripChargingOption: String, CaseIterable, Identifiable {
    case shortestChargingTime
    case fewerStops
    case userSettings

    var id: Self { self }

    nonisolated static var displayedOptions: [TripChargingOption] {
        [.shortestChargingTime, .userSettings]
    }

    nonisolated var title: String {
        switch self {
        case .shortestChargingTime:
            return "Optimised for charging time"
        case .fewerStops:
            return "Fewer stops"
        case .userSettings:
            return "Your charging window"
        }
    }

    nonisolated var symbol: String {
        switch self {
        case .userSettings:
            return "slider.horizontal.3"
        case .fewerStops:
            return "road.lanes"
        case .shortestChargingTime:
            return "timer"
        }
    }

    nonisolated var prefersFewestStopsFirst: Bool {
        switch self {
        case .userSettings, .fewerStops:
            return true
        case .shortestChargingTime:
            return false
        }
    }
}

struct TripChargingOptionPlan: Identifiable {
    var id: TripChargingOption { option }

    let option: TripChargingOption
    let stops: Int
    let minutesPerStop: Double
    let distanceBetweenStopsKm: Double
    let totalMinutes: Double
    let averageTargetPercent: Double
    let finalStopTargetPercent: Double
    let targetDetail: String
    let stopDistancesKm: [Double]

    var nextStopDistanceKm: Double? {
        stopDistancesKm.first
    }
}

private struct ChargingPlanCandidate {
    let stops: Int
    let distanceBetweenStopsKm: Double
    let totalMinutes: Double
    let averageTargetPercent: Double
    let finalStopTargetPercent: Double
    let stopDistancesKm: [Double]
}

struct ChargingExamplePresentation: Identifiable {
    var id: TripChargingOption { option }

    let option: TripChargingOption
    let title: String
    let symbol: String
    let primaryDetail: String
    let distanceDetail: String
    let strategyDetail: String?
    let stops: Int
    let minutesPerStop: Double
    let distanceBetweenStopsKm: Double

    nonisolated init(
        plan: TripChargingOptionPlan,
        displayUnits: DisplayUnits,
        strategyDetail: String? = nil
    ) {
        let roundedDistanceCandidate = Int((plan.distanceBetweenStopsKm / 10).rounded() * 10)
        let roundedDistance = Double(roundedDistanceCandidate) <= plan.distanceBetweenStopsKm
            ? roundedDistanceCandidate
            : Int((plan.distanceBetweenStopsKm / 10).rounded(.down) * 10)
        let stopLabel = plan.stops == 1 ? "stop" : "stops"
        let roundedDistanceKm = Double(roundedDistance)

        option = plan.option
        title = plan.option.title
        symbol = plan.option.symbol
        primaryDetail = "\(plan.stops) \(stopLabel) · ~\(max(5, Int((plan.totalMinutes / 5).rounded() * 5))) min total"
        distanceDetail = "~\(displayUnits.formattedDistance(roundedDistanceKm)) between stops · \(plan.targetDetail)"
        self.strategyDetail = strategyDetail
        stops = plan.stops
        minutesPerStop = plan.minutesPerStop
        distanceBetweenStopsKm = roundedDistanceKm
    }
}

struct QuickTripChargingSummaryView: View {
    let presentation: TripChargingPresentation
    let selectedPlan: TripChargingOptionPlan?

    var body: some View {
        VStack(spacing: 10) {
            summaryRow(
                title: "Charging stops",
                value: presentation.chargingStopsText(for: selectedPlan)
            )

            if presentation.batteryPlan.needsCharging {
                summaryRow(
                    title: "Charging time",
                    value: presentation.chargingTimeText(for: selectedPlan)
                )
            } else {
                summaryRow(
                    title: "Arrival battery",
                    value: presentation.arrivalBatteryText
                )
            }

            summaryRow(
                title: "Expected consumption",
                value: presentation.expectedConsumptionText
            )
        }
    }

    private func summaryRow(title: String, value: String) -> some View {
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
}

struct TripChargingSummaryView: View {
    let presentation: TripChargingPresentation
    let routeDistanceText: String?
    let selectedPlan: TripChargingOptionPlan?
    let selectedOption: TripChargingOption?
    let selectOption: (TripChargingOption) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(spacing: 10) {
                if let routeDistanceText {
                    summaryRow(
                        title: "Route distance",
                        value: routeDistanceText
                    )
                }

                summaryRow(
                    title: "Charging stops",
                    value: presentation.chargingStopsText(for: selectedPlan)
                )
                if let drivingTimeText = presentation.drivingTimeText {
                    summaryRow(
                        title: "Driving time",
                        value: drivingTimeText
                    )
                }
                summaryRow(
                    title: "Charging time",
                    value: presentation.chargingTimeText(for: selectedPlan)
                )
                if let totalTripTimeText = presentation.totalTripTimeText(for: selectedPlan) {
                    summaryRow(
                        title: "Total trip time",
                        value: totalTripTimeText
                    )
                }
                summaryRow(
                    title: "Expected consumption",
                    value: presentation.expectedConsumptionText
                )
                summaryRow(
                    title: presentation.arrivalBatteryTitle,
                    value: presentation.arrivalBatteryText
                )
                summaryRow(
                    title: presentation.chargingLegRangeTitle(for: selectedPlan),
                    value: presentation.chargingLegRangeText(for: selectedPlan)
                )
            }

            if let coldFirstChargeNoteText = presentation.coldFirstChargeNoteText(for: selectedPlan) {
                Text(coldFirstChargeNoteText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let alternative = presentation.reducedChargingTimeAlternative {
                let isSelected = alternative.option == selectedOption
                Button {
                    selectOption(isSelected ? .userSettings : alternative.option)
                } label: {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: alternative.symbol)
                            .font(.caption)
                            .foregroundStyle(isSelected ? rangePilotAccentColor : .secondary)
                            .frame(width: 18)

                        VStack(alignment: .leading, spacing: 3) {
                            Text("Alternative charging plan for reduced charging time")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundStyle(isSelected ? rangePilotAccentColor : .primary)

                            Text(alternative.primaryDetail)
                                .font(.footnote)
                                .foregroundStyle(.secondary)

                            Text(alternative.distanceDetail)
                                .font(.caption)
                                .foregroundStyle(.tertiary)

                            if let strategyDetail = alternative.strategyDetail {
                                Text(strategyDetail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer(minLength: 8)

                        if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(rangePilotAccentColor)
                                .accessibilityHidden(true)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Alternative charging plan for reduced charging time")
                .accessibilityHint(isSelected ? "Switches back to your charging window plan." : "Selects the reduced charging time plan for the route preview and summary.")
                .padding(10)
                .background {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isSelected ? rangePilotAccentColor.opacity(0.12) : Color(.tertiarySystemGroupedBackground))
                }
            }
        }
    }

    private func summaryRow(
        title: String,
        value: String
    ) -> some View {
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
}
