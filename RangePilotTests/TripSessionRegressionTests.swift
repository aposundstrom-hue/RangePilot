import Testing
@testable import RangePilot

@Suite("Trip session regressions")
struct TripSessionRegressionTests {
    private struct Assumptions: Equatable {
        var battery: Double
        var temperature: Double
    }

    @Test("Destination-only parsing cannot invent numeric settings")
    func destinationOnlyUsesCurrentRangeSettings() {
        let deterministic = NaturalLanguageTripHeuristicParser.parse("Uppsala")
        let model = modelInput(battery: 70, temperature: 15, speed: 110)
        let merged = model.mergingDeterministicValues(from: deterministic)
        let currentRange = Assumptions(battery: 57, temperature: 19)
        let seeded = TripSessionPolicy.assumptionsForRoute(
            hasExistingTrip: false,
            existingTrip: Assumptions(battery: 70, temperature: 15),
            currentRange: currentRange
        )

        #expect(merged.batteryPercentage == nil)
        #expect(merged.temperature == nil)
        #expect(merged.motorwaySpeed == nil)
        #expect(seeded == currentRange)
    }

    @Test("Explicit battery, temperature, and speed remain available")
    func explicitNumericSettingsAreUsed() {
        let deterministic = NaturalLanguageTripHeuristicParser.parse(
            "Drive to Uppsala with 62% battery at 8 celsius and motorway speed 105 km/h"
        )
        let merged = modelInput(battery: 70, temperature: 15, speed: 110)
            .mergingDeterministicValues(from: deterministic)

        #expect(merged.batteryPercentage == 62)
        #expect(merged.temperature == 8)
        #expect(merged.motorwaySpeed == 105)
    }

    @Test("A first trip uses the latest Range settings")
    func firstTripUsesLatestRangeSettings() {
        let stale = Assumptions(battery: 70, temperature: 15)
        let latestRange = Assumptions(battery: 43, temperature: 6)

        let seeded = TripSessionPolicy.assumptionsForRoute(
            hasExistingTrip: false,
            existingTrip: stale,
            currentRange: latestRange
        )

        #expect(seeded == latestRange)
    }

    @Test("Manual trip adjustments survive recalculation")
    func manualAdjustmentsSurviveRecalculation() {
        let adjustedTrip = Assumptions(battery: 81, temperature: -4)
        let currentRange = Assumptions(battery: 35, temperature: 12)

        let recalculated = TripSessionPolicy.assumptionsForRoute(
            hasExistingTrip: true,
            existingTrip: adjustedTrip,
            currentRange: currentRange
        )

        #expect(recalculated == adjustedTrip)
    }

    @Test("Starting over seeds the next trip from current Range settings")
    func startOverUsesCurrentRangeSettingsAgain() {
        let previousTrip = Assumptions(battery: 81, temperature: -4)
        let currentRange = Assumptions(battery: 29, temperature: 21)

        let nextTrip = TripSessionPolicy.assumptionsForRoute(
            hasExistingTrip: false,
            existingTrip: previousTrip,
            currentRange: currentRange
        )

        #expect(nextTrip == currentRange)
    }

    private func modelInput(
        battery: Double?,
        temperature: Double?,
        speed: Double?
    ) -> NaturalLanguageTripEstimateInput {
        NaturalLanguageTripEstimateInput(
            batteryPercentage: battery,
            plannedDistanceKm: nil,
            route: TripRouteDescription(origin: nil, destination: "Uppsala"),
            chargingPreference: nil,
            batteryThresholdQuestionPercent: nil,
            roadTypeProfile: nil,
            hasExplicitRoadTypeWording: false,
            motorwaySpeed: speed,
            temperature: temperature,
            roadSurface: nil,
            windCondition: nil,
            planningMode: nil
        )
    }
}
