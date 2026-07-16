import Foundation

enum TripSessionPolicy {
    static func shouldPreserveTripSettings(hasExistingTrip: Bool) -> Bool {
        hasExistingTrip
    }

    static func assumptionsForRoute<Assumptions>(
        hasExistingTrip: Bool,
        existingTrip: Assumptions,
        currentRange: Assumptions
    ) -> Assumptions {
        shouldPreserveTripSettings(hasExistingTrip: hasExistingTrip)
            ? existingTrip
            : currentRange
    }
}
