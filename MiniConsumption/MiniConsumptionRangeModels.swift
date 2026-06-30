import Foundation

nonisolated let defaultReferenceConsumptionKWhPer100Km = 13.6

enum MiniConsumptionDefaults {
    static let tripDistanceKm = 300.0
    static let quickTripDistanceKm = 50.0
    static let temperatureC = 15.0
    static let airConditioningMode = AirConditioningMode.on
    static let roadTypeProfile = RoadTypeProfile.motorwayMix
    nonisolated static let motorwaySpeedKmh = 110.0
    nonisolated static let motorwaySpeedRange = 90.0...150.0
    static let roadSurface = RoadSurface.dry
    static let windCondition = WindCondition.normal
    static let planningMode = PlanningMode.normal
    static let currentBatteryPercent = 70.0
    static let selectedTyreSet = TyreSet.summer
    static let summerTyreClass = RollingResistanceClass.b
    static let winterTyreClass = RollingResistanceClass.c
    static let useContinuousCalibration = true
    static let batteryDegradationPercent = 3
    nonisolated static let trailerWeightKg = 500.0
    nonisolated static let trailerWeightRangeKg = 200.0...1500.0
    static let trailerWeightStepKg = 50.0

    nonisolated static func normalizedMotorwaySpeed(_ speed: Double) -> Double {
        guard speed.isFinite else {
            return motorwaySpeedKmh
        }

        return min(max(speed, motorwaySpeedRange.lowerBound), motorwaySpeedRange.upperBound)
    }

    static func normalizedQuickTripDistance(_ distance: Double) -> Double {
        guard distance.isFinite else {
            return quickTripDistanceKm
        }

        return min(max(distance, 1), 1000)
    }

    nonisolated static func normalizedTrailerWeightKg(_ weightKg: Double) -> Double {
        guard weightKg.isFinite else {
            return trailerWeightKg
        }

        return min(max(weightKg, trailerWeightRangeKg.lowerBound), trailerWeightRangeKg.upperBound)
    }
}

enum CalibrationTripQuality {
    nonisolated static let minimumCalibrationTripDistanceKm = 15.0
    nonisolated static let minimumCityMixCalibrationTripDistanceKm = 5.0

    nonisolated static func minimumCalibrationTripDistanceKm(for roadTypeProfile: RoadTypeProfile) -> Double {
        roadTypeProfile == .cityMix
            ? minimumCityMixCalibrationTripDistanceKm
            : minimumCalibrationTripDistanceKm
    }
}

enum VehicleProfileKind: String, Codable {
    case mini
    case customEV
}

enum RoadSurface: String, Codable, CaseIterable, Identifiable {
    case dry
    case damp
    case wet
    case heavyRain
    case snowSlush

    var id: Self { self }

    static var segmentedCases: [Self] {
        [.snowSlush, .wet, .dry]
    }

    var segmentedEquivalent: Self {
        switch self {
        case .dry:
            .dry
        case .damp, .wet, .heavyRain:
            .wet
        case .snowSlush:
            .snowSlush
        }
    }

    var label: String {
        switch self {
        case .dry:
            "Dry"
        case .damp:
            "Damp"
        case .wet:
            "Wet"
        case .heavyRain:
            "Heavy rain"
        case .snowSlush:
            "Snow"
        }
    }

    nonisolated var adjustment: Double {
        switch self {
        case .dry:
            0.0
        case .damp:
            0.01
        case .wet:
            0.03
        case .heavyRain:
            0.05
        case .snowSlush:
            0.06
        }
    }

    nonisolated var addsExtraHighRange: Bool {
        switch self {
        case .heavyRain, .snowSlush:
            true
        case .dry, .damp, .wet:
            false
        }
    }
}

enum TyreSet: String, Codable, CaseIterable, Identifiable {
    case summer
    case winter

    var id: Self { self }

    var label: String {
        switch self {
        case .summer:
            "Summer"
        case .winter:
            "Winter"
        }
    }
}

enum AirConditioningMode: String, Codable, CaseIterable, Identifiable {
    case on
    case off

    var id: Self { self }

    var label: String {
        switch self {
        case .on:
            "On"
        case .off:
            "Off"
        }
    }
}

struct RouteProfile: Sendable {
    let baseFactor: Double
    let speedSensitivity: Double
    let windSensitivity: Double
    let winterSensitivity: Double
    let legacyMotorwayShare: Double
}

enum RoadTypeProfile: Codable, CaseIterable, Identifiable, RawRepresentable, Sendable {
    case cityMix
    case countryside
    case motorwayMix
    case motorway

    var id: Self { self }

    nonisolated init?(rawValue: String) {
        switch rawValue {
        case "cityMix", "urban":
            self = .cityMix
        case "countryside", "slowRoads":
            self = .countryside
        case "motorwayMix", "mixed":
            self = .motorwayMix
        case "motorway":
            self = .motorway
        default:
            return nil
        }
    }

    nonisolated var rawValue: String {
        switch self {
        case .cityMix:
            "cityMix"
        case .countryside:
            "countryside"
        case .motorwayMix:
            "motorwayMix"
        case .motorway:
            "motorway"
        }
    }

    var label: String {
        switch self {
        case .cityMix:
            "City mix"
        case .countryside:
            "Calm roads"
        case .motorwayMix:
            "Motorway mix"
        case .motorway:
            "Motorway"
        }
    }

    var assumptionLabel: String {
        switch self {
        case .cityMix:
            "city-mix driving"
        case .countryside:
            "calm-road driving"
        case .motorwayMix:
            "mixed motorway driving"
        case .motorway:
            "motorway driving"
        }
    }

    nonisolated var routeProfile: RouteProfile {
        switch self {
        case .cityMix:
            RouteProfile(
                baseFactor: 0.99,
                speedSensitivity: 0.05,
                windSensitivity: 0.20,
                winterSensitivity: 0.18,
                legacyMotorwayShare: 5
            )
        case .countryside:
            RouteProfile(
                baseFactor: 0.96,
                speedSensitivity: 0.10,
                windSensitivity: 0.40,
                winterSensitivity: 0.12,
                legacyMotorwayShare: 15
            )
        case .motorwayMix:
            // Main forecasts blend motorway, countryside, and city mix; only direct lookups
            // such as speed sensitivity and legacy migration use this profile as-is.
            RouteProfile(
                baseFactor: 1.074,
                speedSensitivity: 0.60,
                windSensitivity: 0.76,
                winterSensitivity: 0.648,
                legacyMotorwayShare: 60
            )
        case .motorway:
            RouteProfile(
                baseFactor: 1.15,
                speedSensitivity: 0.9,
                windSensitivity: 1.00,
                winterSensitivity: 1.00,
                legacyMotorwayShare: 65
            )
        }
    }

    nonisolated var consumptionFactor: Double {
        routeProfile.baseFactor
    }

    nonisolated var windScalingFactor: Double {
        routeProfile.windSensitivity
    }

    nonisolated var motorwaySpeedScalingFactor: Double {
        routeProfile.speedSensitivity
    }

    nonisolated var winterScalingFactor: Double {
        routeProfile.winterSensitivity
    }

    nonisolated var legacyMotorwayShare: Double {
        routeProfile.legacyMotorwayShare
    }

    nonisolated init(legacyMotorwayShare: Double) {
        switch legacyMotorwayShare {
        case 65...:
            self = .motorway
        case 25..<65:
            self = .motorwayMix
        case 10..<25:
            self = .countryside
        case ...10:
            self = .cityMix
        default:
            self = .motorwayMix
        }
    }
}

enum WindCondition: String, Codable, CaseIterable, Identifiable {
    case tailwind
    case normal
    case headwind

    var id: Self { self }

    static var rangeOrderedCases: [Self] {
        [.headwind, .normal, .tailwind]
    }

    var label: String {
        switch self {
        case .tailwind:
            "Tailwind"
        case .normal:
            "Normal"
        case .headwind:
            "Headwind"
        }
    }

    nonisolated var adjustment: Double {
        switch self {
        case .tailwind:
            -0.03
        case .normal:
            0.0
        case .headwind:
            0.06
        }
    }

    nonisolated var addsExtraHighRange: Bool {
        self == .headwind
    }
}

enum RollingResistanceClass: String, Codable, CaseIterable, Identifiable {
    case unknown
    case a
    case b
    case c
    case d
    case e

    var id: Self { self }

    static var rangeOrderedCases: [Self] {
        [.a, .b, .c, .d, .e, .unknown]
    }

    var label: String {
        switch self {
        case .unknown:
            "Unknown"
        default:
            rawValue.uppercased()
        }
    }

    nonisolated var adjustment: Double {
        switch self {
        case .unknown:
            0.0
        case .a:
            -0.025
        case .b:
            0.0
        case .c:
            0.025
        case .d:
            0.055
        case .e:
            0.075
        }
    }
}

enum PlanningMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case conservative
    case normal
    case optimistic

    var id: Self { self }

    var label: String {
        switch self {
        case .optimistic:
            "Optimistic"
        case .normal:
            "Normal"
        case .conservative:
            "Cautious"
        }
    }

    nonisolated var adjustmentFactor: Double {
        switch self {
        case .optimistic:
            0.94
        case .normal:
            1.00
        case .conservative:
            1.08
        }
    }

    nonisolated var lowRangeFactor: Double {
        switch self {
        case .optimistic:
            0.94
        case .normal:
            0.92
        case .conservative:
            0.95
        }
    }

    nonisolated var highRangeFactor: Double {
        switch self {
        case .optimistic:
            1.08
        case .normal:
            1.12
        case .conservative:
            1.18
        }
    }
}
