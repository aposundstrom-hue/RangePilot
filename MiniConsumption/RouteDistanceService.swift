import Foundation
import os
#if canImport(CoreLocation)
import CoreLocation
#endif
#if canImport(MapKit)
import MapKit
#endif

enum RouteDistanceService {
    private static let logger = Logger(subsystem: "com.ontographist.MiniConsumption", category: "TripAssistant.RouteDistance")

    static func estimatedDrivingDistanceKm(from origin: String, to destination: String) async throws -> Double? {
        try await estimatedDrivingRoute(from: origin, to: destination)?.distanceKm
    }

    static func estimatedDrivingDistanceFromCurrentLocationKm(to destination: String) async throws -> Double? {
        try await estimatedDrivingRouteFromCurrentLocation(to: destination)?.distanceKm
    }

    static func estimatedDrivingDistanceFromCurrentLocationKm(to destination: CLLocationCoordinate2D) async throws -> Double? {
        try await estimatedDrivingRouteFromCurrentLocation(to: destination)?.distanceKm
    }

    static func estimatedDrivingRoute(from origin: String, to destination: String) async throws -> RouteDistanceEstimate? {
#if canImport(MapKit)
        guard let source = try await mapItem(for: origin) else {
            logger.debug("MapKit lookup failed: origin geocode returned no match")
            return nil
        }

        guard let destination = try await mapItem(for: destination) else {
            logger.debug("MapKit lookup failed: destination geocode returned no match")
            return nil
        }

        let request = MKDirections.Request()
        request.source = source
        request.destination = destination
        request.transportType = .automobile

        let response = try await MKDirections(request: request).calculate()
        guard let route = response.routes.min(by: { $0.distance < $1.distance }) else {
            logger.debug("MapKit lookup failed: directions returned no routes")
            return nil
        }

        logger.debug("MapKit lookup succeeded with explicit origin")
        return RouteDistanceEstimate(route: route)
#else
        return nil
#endif
    }

    static func estimatedDrivingRouteFromCurrentLocation(to destination: String) async throws -> RouteDistanceEstimate? {
#if canImport(CoreLocation) && canImport(MapKit)
        guard let origin = await CurrentLocationRouteOriginProvider.requestCurrentLocation() else {
            logger.debug("MapKit lookup failed: current location unavailable or denied")
            return nil
        }

        guard let destination = try await mapItem(for: destination) else {
            logger.debug("MapKit lookup failed: destination geocode returned no match")
            return nil
        }

        let request = MKDirections.Request()
        request.source = MKMapItem(
            location: CLLocation(latitude: origin.latitude, longitude: origin.longitude),
            address: nil
        )
        request.destination = destination
        request.transportType = .automobile

        let response = try await MKDirections(request: request).calculate()
        guard let route = response.routes.min(by: { $0.distance < $1.distance }) else {
            logger.debug("MapKit lookup failed: directions returned no routes")
            return nil
        }

        logger.debug("MapKit lookup succeeded with current location")
        return RouteDistanceEstimate(route: route)
#else
        return nil
#endif
    }

    static func estimatedDrivingRouteFromCurrentLocation(to destination: CLLocationCoordinate2D) async throws -> RouteDistanceEstimate? {
#if canImport(CoreLocation) && canImport(MapKit)
        guard let origin = await CurrentLocationRouteOriginProvider.requestCurrentLocation() else {
            logger.debug("MapKit lookup failed: current location unavailable or denied")
            return nil
        }

        guard CLLocationCoordinate2DIsValid(destination),
              destination.latitude.isFinite,
              destination.longitude.isFinite else {
            logger.debug("MapKit lookup failed: destination coordinate is invalid")
            return nil
        }

        let request = MKDirections.Request()
        request.source = MKMapItem(
            location: CLLocation(latitude: origin.latitude, longitude: origin.longitude),
            address: nil
        )
        request.destination = MKMapItem(
            location: CLLocation(latitude: destination.latitude, longitude: destination.longitude),
            address: nil
        )
        request.transportType = .automobile

        let response = try await MKDirections(request: request).calculate()
        guard let route = response.routes.min(by: { $0.distance < $1.distance }) else {
            logger.debug("MapKit lookup failed: directions returned no routes")
            return nil
        }

        logger.debug("MapKit lookup succeeded with current location and coordinate destination")
        return RouteDistanceEstimate(route: route)
#else
        return nil
#endif
    }

#if canImport(MapKit)
    private static func mapItem(for query: String) async throws -> MKMapItem? {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query

        let response = try await MKLocalSearch(request: request).start()
        return response.mapItems.first
    }
#endif
}

#if canImport(MapKit)
struct RouteDistanceEstimate {
    let distanceKm: Double
    let expectedTravelTime: TimeInterval?
    let averageSpeedKmh: Double?
    let polyline: MKPolyline?

    init(route: MKRoute) {
        let resolvedDistanceKm = route.distance / 1000
        let resolvedExpectedTravelTime = route.expectedTravelTime > 0 ? route.expectedTravelTime : nil

        distanceKm = resolvedDistanceKm
        expectedTravelTime = resolvedExpectedTravelTime
        averageSpeedKmh = resolvedExpectedTravelTime.map { resolvedDistanceKm / ($0 / 3600) }
        polyline = route.polyline.pointCount > 1 ? route.polyline : nil
    }
}

enum RoutePolylineDistance {
    static func coordinate(on polyline: MKPolyline, atDistanceKm targetDistanceKm: Double) -> CLLocationCoordinate2D? {
        let pointCount = polyline.pointCount
        guard pointCount > 1, targetDistanceKm > 0 else {
            return nil
        }

        var coordinates = Array(
            repeating: kCLLocationCoordinate2DInvalid,
            count: pointCount
        )
        polyline.getCoordinates(&coordinates, range: NSRange(location: 0, length: pointCount))

        var traveledMeters = 0.0
        let targetMeters = targetDistanceKm * 1000

        for index in 1..<coordinates.count {
            let previousCoordinate = coordinates[index - 1]
            let currentCoordinate = coordinates[index]
            guard CLLocationCoordinate2DIsValid(previousCoordinate),
                  CLLocationCoordinate2DIsValid(currentCoordinate) else {
                continue
            }

            let previousLocation = CLLocation(
                latitude: previousCoordinate.latitude,
                longitude: previousCoordinate.longitude
            )
            let currentLocation = CLLocation(
                latitude: currentCoordinate.latitude,
                longitude: currentCoordinate.longitude
            )
            let segmentMeters = currentLocation.distance(from: previousLocation)
            guard segmentMeters > 0 else {
                continue
            }

            if traveledMeters + segmentMeters >= targetMeters {
                let progress = (targetMeters - traveledMeters) / segmentMeters
                return CLLocationCoordinate2D(
                    latitude: previousCoordinate.latitude + (currentCoordinate.latitude - previousCoordinate.latitude) * progress,
                    longitude: previousCoordinate.longitude + (currentCoordinate.longitude - previousCoordinate.longitude) * progress
                )
            }

            traveledMeters += segmentMeters
        }

        return nil
    }
}
#endif

#if canImport(CoreLocation)
@MainActor
final class CurrentLocationRouteOriginProvider: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocationCoordinate2D?, Never>?
    private var didRequestAuthorization = false
    private var didRequestLocation = false

    static func requestCurrentLocation() async -> CLLocationCoordinate2D? {
        let provider = CurrentLocationRouteOriginProvider()
        return await provider.requestCurrentLocation()
    }

    private override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    private func requestCurrentLocation() async -> CLLocationCoordinate2D? {
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            handleAuthorizationStatus(manager.authorizationStatus)
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            handleAuthorizationStatus(manager.authorizationStatus)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            finish(with: locations.last?.coordinate)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            finish(with: nil)
        }
    }

    private func handleAuthorizationStatus(_ status: CLAuthorizationStatus) {
        guard continuation != nil else {
            return
        }

        switch status {
        case .notDetermined:
            guard !didRequestAuthorization else {
                return
            }

            didRequestAuthorization = true
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            requestOneShotLocation()
        case .denied, .restricted:
            finish(with: nil)
        @unknown default:
            finish(with: nil)
        }
    }

    private func requestOneShotLocation() {
        guard !didRequestLocation else {
            return
        }

        didRequestLocation = true
        manager.requestLocation()
    }

    private func finish(with coordinate: CLLocationCoordinate2D?) {
        manager.stopUpdatingLocation()
        manager.delegate = nil
        continuation?.resume(returning: coordinate)
        continuation = nil
    }
}
#endif
