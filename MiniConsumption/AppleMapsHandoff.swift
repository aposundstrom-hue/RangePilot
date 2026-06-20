import Foundation
#if canImport(MapKit)
import MapKit
#endif
#if canImport(UIKit)
import UIKit
#endif

#if canImport(MapKit) && canImport(UIKit)
@MainActor
enum AppleMapsHandoff {
    private static let chargerSearchQuery = NSLocalizedString("EV charger", comment: "Apple Maps charger search query")
    private static let chargerSearchRadiusMeters = 25_000.0

    static func openRoute(origin: String?, destination: String) async {
        let destination = destination.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !destination.isEmpty,
              let destinationMapItem = await mapItem(for: destination) else {
            return
        }

        destinationMapItem.name = destination

        let launchOptions = [
            MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving
        ]

        if let origin = origin?.trimmingCharacters(in: .whitespacesAndNewlines),
           !origin.isEmpty,
           let originMapItem = await mapItem(for: origin) {
            originMapItem.name = origin
            MKMapItem.openMaps(
                with: [originMapItem, destinationMapItem],
                launchOptions: launchOptions
            )
            return
        }

        destinationMapItem.openInMaps(launchOptions: launchOptions)
    }

    static func openChargingSearch(near destination: String) async {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = destination

        guard let response = try? await MKLocalSearch(request: request).start(),
              let coordinate = response.mapItems.first?.location.coordinate else {
            return
        }

        await openChargingSearch(centeredAt: coordinate)
    }

    static func openChargingSearch(centeredAt coordinate: CLLocationCoordinate2D) async {
        guard CLLocationCoordinate2DIsValid(coordinate),
              coordinate.latitude.isFinite,
              coordinate.longitude.isFinite else {
            return
        }

        let region = MKCoordinateRegion(
            center: coordinate,
            latitudinalMeters: chargerSearchRadiusMeters * 2,
            longitudinalMeters: chargerSearchRadiusMeters * 2
        )

        let mapItems = await validatedLocalChargerResults(near: coordinate)
        if !mapItems.isEmpty {
            MKMapItem.openMaps(
                with: Array(mapItems.prefix(10)),
                launchOptions: [
                    MKLaunchOptionsMapCenterKey: NSValue(mkCoordinate: coordinate),
                    MKLaunchOptionsMapSpanKey: NSValue(mkCoordinateSpan: region.span)
                ]
            )
            return
        }

        openChargerSearchArea(centeredAt: coordinate)
    }

    private static func validatedLocalChargerResults(near coordinate: CLLocationCoordinate2D) async -> [MKMapItem] {
        guard CLLocationCoordinate2DIsValid(coordinate),
              coordinate.latitude.isFinite,
              coordinate.longitude.isFinite else {
            return []
        }

        let region = MKCoordinateRegion(
            center: coordinate,
            latitudinalMeters: chargerSearchRadiusMeters * 2,
            longitudinalMeters: chargerSearchRadiusMeters * 2
        )
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = chargerSearchQuery
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
                    && mapItem.location.distance(from: centerLocation) <= chargerSearchRadiusMeters
            }
            .sorted { $0.location.distance(from: centerLocation) < $1.location.distance(from: centerLocation) }
    }

    private static func openChargerSearchArea(centeredAt coordinate: CLLocationCoordinate2D) {
        let coordinateValue = String(
            format: "%.6f,%.6f",
            locale: Locale(identifier: "en_US_POSIX"),
            coordinate.latitude,
            coordinate.longitude
        )
        var components = URLComponents(string: "https://maps.apple.com/")
        components?.queryItems = [
            URLQueryItem(name: "ll", value: coordinateValue),
            URLQueryItem(name: "sll", value: coordinateValue),
            URLQueryItem(name: "z", value: "12")
        ]

        guard let url = components?.url else {
            return
        }

        UIApplication.shared.open(url)
    }

    private static func mapItem(for query: String) async -> MKMapItem? {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        return try? await MKLocalSearch(request: request).start().mapItems.first
    }
}
#endif
