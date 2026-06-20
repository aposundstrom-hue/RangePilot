import Foundation

enum DisplayUnits: String, CaseIterable, Identifiable {
    case metric
    case imperial

    private nonisolated static let kilometersPerMile = 1.609344
    private nonisolated static let milesPer100Kilometers = 62.1371192

    nonisolated var id: Self { self }

    nonisolated var label: String {
        switch self {
        case .metric:
            "Metric"
        case .imperial:
            "Imperial"
        }
    }

    nonisolated var distanceUnitLabel: String {
        switch self {
        case .metric:
            "km"
        case .imperial:
            "mi"
        }
    }

    nonisolated var consumptionUnitLabel: String {
        switch self {
        case .metric:
            "kWh/100 km"
        case .imperial:
            "mi/kWh"
        }
    }

    nonisolated func displayDistance(fromKm kilometers: Double) -> Double {
        switch self {
        case .metric:
            return kilometers
        case .imperial:
            return kilometers / Self.kilometersPerMile
        }
    }

    nonisolated func storedDistance(fromDisplayed value: Double) -> Double {
        switch self {
        case .metric:
            return value
        case .imperial:
            return value * Self.kilometersPerMile
        }
    }

    nonisolated func displayConsumption(fromKWhPer100Km kWhPer100Km: Double) -> Double {
        switch self {
        case .metric:
            return kWhPer100Km
        case .imperial:
            guard kWhPer100Km > 0 else {
                return 0
            }
            return Self.milesPer100Kilometers / kWhPer100Km
        }
    }

    nonisolated func storedConsumption(fromDisplayed value: Double) -> Double {
        switch self {
        case .metric:
            return value
        case .imperial:
            guard value > 0 else {
                return 0
            }
            return Self.milesPer100Kilometers / value
        }
    }

    nonisolated func formatDistanceValue(fromKm kilometers: Double, fractionLength: Int = 0) -> String {
        displayDistance(fromKm: kilometers).formatted(.number.precision(.fractionLength(fractionLength)))
    }

    nonisolated func formatConsumptionValue(fromKWhPer100Km kWhPer100Km: Double, fractionLength: Int = 1) -> String {
        displayConsumption(fromKWhPer100Km: kWhPer100Km).formatted(.number.precision(.fractionLength(fractionLength)))
    }

    nonisolated func formattedDistance(_ kilometers: Double, fractionLength: Int = 0) -> String {
        "\(formatDistanceValue(fromKm: kilometers, fractionLength: fractionLength)) \(distanceUnitLabel)"
    }

    nonisolated func formattedConsumption(_ kWhPer100Km: Double, fractionLength: Int = 1) -> String {
        "\(formatConsumptionValue(fromKWhPer100Km: kWhPer100Km, fractionLength: fractionLength)) \(consumptionUnitLabel)"
    }

    nonisolated func spokenDistance(_ kilometers: Double) -> String {
        let roundedValue = Int(displayDistance(fromKm: kilometers).rounded())
        switch self {
        case .metric:
            return "\(roundedValue) kilometers"
        case .imperial:
            return "\(roundedValue) miles"
        }
    }
}

enum TemperatureUnits: String, CaseIterable, Identifiable {
    case celsius
    case fahrenheit

    nonisolated var id: Self { self }

    nonisolated var label: String {
        switch self {
        case .celsius:
            "Celsius"
        case .fahrenheit:
            "Fahrenheit"
        }
    }

    nonisolated var temperatureUnitLabel: String {
        switch self {
        case .celsius:
            "°C"
        case .fahrenheit:
            "°F"
        }
    }

    nonisolated func displayTemperature(fromCelsius celsius: Double) -> Double {
        switch self {
        case .celsius:
            celsius
        case .fahrenheit:
            celsius * 9 / 5 + 32
        }
    }

    nonisolated func storedTemperature(fromDisplayed value: Double) -> Double {
        switch self {
        case .celsius:
            value
        case .fahrenheit:
            (value - 32) * 5 / 9
        }
    }

    nonisolated func formattedTemperature(_ celsius: Double) -> String {
        "\(displayTemperature(fromCelsius: celsius).formatted(.number.precision(.fractionLength(0)))) \(temperatureUnitLabel)"
    }

    nonisolated func displayRange(forCelsiusRange range: ClosedRange<Double>) -> ClosedRange<Double> {
        let lower = displayTemperature(fromCelsius: range.lowerBound).rounded()
        let upper = displayTemperature(fromCelsius: range.upperBound).rounded()
        return min(lower, upper)...max(lower, upper)
    }

    nonisolated func spokenTemperature(_ celsius: Double) -> String {
        let roundedValue = Int(displayTemperature(fromCelsius: celsius).rounded())
        switch self {
        case .celsius:
            return "\(roundedValue) degrees Celsius"
        case .fahrenheit:
            return "\(roundedValue) degrees Fahrenheit"
        }
    }
}

enum WeightUnits: String, CaseIterable, Identifiable {
    case kilograms
    case pounds

    private nonisolated static let poundsPerKilogram = 2.2046226218

    nonisolated var id: Self { self }

    nonisolated var unitLabel: String {
        switch self {
        case .kilograms:
            "kg"
        case .pounds:
            "lbs"
        }
    }

    nonisolated func displayWeight(fromKg kilograms: Double) -> Double {
        switch self {
        case .kilograms:
            kilograms
        case .pounds:
            kilograms * Self.poundsPerKilogram
        }
    }

    nonisolated func storedWeightKg(fromDisplayed value: Double) -> Double {
        switch self {
        case .kilograms:
            value
        case .pounds:
            value / Self.poundsPerKilogram
        }
    }

    nonisolated func roundedDisplayWeight(fromKg kilograms: Double) -> Double {
        let displayedWeight = displayWeight(fromKg: kilograms)
        switch self {
        case .kilograms:
            return (displayedWeight / 50).rounded() * 50
        case .pounds:
            if displayedWeight < 500 {
                return (displayedWeight / 50).rounded() * 50
            }
            return (displayedWeight / 100).rounded() * 100
        }
    }

    nonisolated func formattedWeight(_ kilograms: Double) -> String {
        "\(Int(roundedDisplayWeight(fromKg: kilograms))) \(unitLabel)"
    }
}

func roundedKilometers(_ value: Double) -> String {
    "\(Int(value.rounded())) kilometers"
}

func roundedPercent(_ value: Double) -> String {
    "\(Int(value.rounded())) percent"
}

func oneDecimal(_ value: Double) -> String {
    value.formatted(.number.precision(.fractionLength(1)))
}
