//
//  ContentView.swift
//  RangePilot Watch App
//
//  Created by Andreas Sundström on 2026-06-07.
//

import SwiftUI

private let watchRangeAccentColor = Color(red: 0.82, green: 0.70, blue: 0.22)

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var temperatureUnit: WatchTemperatureUnit
    @State private var batteryPercent: Double
    @State private var drivingMode: DrivingMode
    @State private var temperatureC: Double
    @State private var vehicleProfile: WatchVehicleProfile
    @State private var displayUnits: WatchDisplayUnits
    @State private var forecastAssumptions: WatchForecastAssumptions
    @State private var isShowingTemperatureSelector = false

    init(snapshot: WatchRangeStateSnapshot? = WatchRangeStateSnapshotStore.load()) {
        if let snapshot {
            let profiles = WatchVehicleProfile.availableProfiles(snapshot: snapshot)
            let activeProfile = WatchVehicleProfile.activeProfile(snapshot: snapshot, availableProfiles: profiles)

            _batteryPercent = State(initialValue: snapshot.batteryPercent)
            _drivingMode = State(initialValue: DrivingMode(roadTypeProfile: snapshot.roadTypeProfile))
            _temperatureC = State(initialValue: snapshot.temperatureC)
            _vehicleProfile = State(initialValue: activeProfile)
            _temperatureUnit = State(initialValue: WatchTemperatureUnit(snapshotRawValue: snapshot.temperatureUnitsRawValue))
            _displayUnits = State(initialValue: WatchDisplayUnits(snapshotRawValue: snapshot.displayUnitsRawValue))
            _forecastAssumptions = State(initialValue: WatchForecastAssumptions(snapshot: snapshot))
        } else {
            _batteryPercent = State(initialValue: MiniConsumptionDefaults.currentBatteryPercent)
            _drivingMode = State(initialValue: .motorwayMix)
            _temperatureC = State(initialValue: MiniConsumptionDefaults.temperatureC)
            _vehicleProfile = State(initialValue: .miniCooperSE)
            _temperatureUnit = State(initialValue: .celsius)
            _displayUnits = State(initialValue: .metric)
            _forecastAssumptions = State(initialValue: .defaults)
        }
    }

    private var displayedBatteryPercent: Int {
        Int(batteryPercent.rounded())
    }

    private var displayedRange: Int {
        Int(displayUnits.displayDistance(fromKm: remainingRange.rangeKm).rounded())
    }

    private var rangeGaugeMaximumKm: Double {
        let wltpRangeKm = vehicleProfile.calculationProfile.wltpRangeKm

        guard vehicleProfile.calculationProfile.kind == .custom,
              wltpRangeKm.isFinite,
              wltpRangeKm > 0 else {
            return WatchRangeGauge.defaultScaleUpperBoundKm
        }

        return ceil(wltpRangeKm / 20) * 20
    }

    private var forecast: ForecastResult {
        MiniConsumptionCalculator.calculateForecast(
            referenceConsumption: vehicleProfile.referenceConsumptionKWhPer100Km,
            distance: MiniConsumptionDefaults.tripDistanceKm,
            temperature: temperatureC,
            roadTypeProfile: drivingMode.roadTypeProfile,
            motorwaySpeed: forecastAssumptions.motorwaySpeed,
            roadSurface: forecastAssumptions.roadSurface,
            windCondition: forecastAssumptions.windCondition,
            planningMode: MiniConsumptionDefaults.planningMode,
            rollingResistanceClass: forecastAssumptions.activeRollingResistanceClass,
            airConditioningMode: forecastAssumptions.airConditioningMode,
            applyDistanceAdjustment: false,
            usesCustomVehicleProfile: vehicleProfile.calculationProfile.kind == .custom,
            usableBatteryKWh: vehicleProfile.calculationProfile.usableBatteryKWh
        )
    }

    private var remainingRange: RemainingRangeEstimate {
        MiniConsumptionCalculator.calculateRemainingRange(
            currentBatteryPercent: batteryPercent,
            expectedKWhPer100km: forecast.finalKWhPer100km,
            usableBatteryKWh: vehicleProfile.calculationProfile.usableBatteryKWh
        )
    }

    private func applySnapshot(_ snapshot: WatchRangeStateSnapshot) {
        let profiles = WatchVehicleProfile.availableProfiles(snapshot: snapshot)

        batteryPercent = snapshot.batteryPercent
        drivingMode = DrivingMode(roadTypeProfile: snapshot.roadTypeProfile)
        temperatureC = snapshot.temperatureC
        vehicleProfile = WatchVehicleProfile.activeProfile(snapshot: snapshot, availableProfiles: profiles)
        displayUnits = WatchDisplayUnits(snapshotRawValue: snapshot.displayUnitsRawValue)
        temperatureUnit = WatchTemperatureUnit(snapshotRawValue: snapshot.temperatureUnitsRawValue)
        forecastAssumptions = WatchForecastAssumptions(snapshot: snapshot)
    }

    private func reloadSnapshotIfAvailable(onlyIfStale: Bool = false) {
        if onlyIfStale, WatchRangeStateSnapshotStore.needsStartupRefresh() == false {
            return
        }

        UserDefaults(suiteName: WatchRangeStateSnapshotStore.appGroupID)?.synchronize()

        WatchRangeStateSnapshotStore.loadLatestFromPhone { snapshot in
            guard let snapshot else {
                return
            }

            Task { @MainActor in
                applySnapshot(snapshot)
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 6)

            VStack(spacing: 4) {
                WatchRangeGauge(
                    rangeKm: remainingRange.rangeKm,
                    displayedRange: displayedRange,
                    rangeUnitTitle: displayUnits.distanceUnitLabel,
                    scaleUpperBoundKm: rangeGaugeMaximumKm,
                    batteryPercent: displayedBatteryPercent,
                    temperatureTitle: Temperature.title(for: temperatureC, unit: temperatureUnit),
                    onRefreshTap: {
                        reloadSnapshotIfAvailable()
                    },
                    onTemperatureTap: {
                        isShowingTemperatureSelector = true
                    }
                )
                .frame(width: 154, height: 150)

                DrivingModeSelectionRow(
                    selectedMode: drivingMode,
                    onSelect: { selectedMode in
                        drivingMode = selectedMode
                    }
                )

                Text(vehicleProfile.displayName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }

            Spacer(minLength: 4)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .containerBackground(.black, for: .navigation)
        .focusable(true)
        .digitalCrownRotation(
            $batteryPercent,
            from: 0,
            through: 100,
            by: 1,
            sensitivity: .medium,
            isContinuous: false,
            isHapticFeedbackEnabled: true
        )
        .sheet(isPresented: $isShowingTemperatureSelector) {
            TemperatureSelector(
                selectedTemperatureC: temperatureC,
                selectedUnit: temperatureUnit,
                onDone: { selectedTemperatureC in
                    temperatureC = selectedTemperatureC
                    isShowingTemperatureSelector = false
                }
            )
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active,
                  isShowingTemperatureSelector == false else {
                return
            }

            reloadSnapshotIfAvailable(onlyIfStale: true)
        }
        .onAppear {
            reloadSnapshotIfAvailable(onlyIfStale: true)
        }
    }
}

private struct WatchRangeGauge: View {
    static let defaultScaleUpperBoundKm = 260.0

    let rangeKm: Double
    let displayedRange: Int
    let rangeUnitTitle: String
    let scaleUpperBoundKm: Double
    let batteryPercent: Int
    let temperatureTitle: String
    let onRefreshTap: () -> Void
    let onTemperatureTap: () -> Void

    private let arcStartAngle = 165.0
    private let arcEndAngle = 375.0

    private var progress: Double {
        guard rangeKm.isFinite,
              scaleUpperBoundKm.isFinite,
              scaleUpperBoundKm > 0 else {
            return 0
        }

        return min(max(rangeKm / scaleUpperBoundKm, 0), 1)
    }

    var body: some View {
        ZStack {
            WatchRangeArc(
                startAngle: arcStartAngle,
                endAngle: arcEndAngle
            )
                .stroke(
                    Color.white.opacity(0.16),
                    style: StrokeStyle(lineWidth: 9, lineCap: .round)
                )

            WatchRangeArc(
                startAngle: arcStartAngle,
                endAngle: arcStartAngle + (arcEndAngle - arcStartAngle) * progress
            )
                .stroke(
                    LinearGradient(
                        colors: [
                            watchRangeAccentColor.opacity(0.78),
                            watchRangeAccentColor
                        ],
                        startPoint: .bottomLeading,
                        endPoint: .topTrailing
                    ),
                    style: StrokeStyle(lineWidth: 9, lineCap: .round)
                )
                .shadow(color: watchRangeAccentColor.opacity(0.28), radius: 6, x: 0, y: 2)

            VStack(spacing: 1) {
                Text("\(displayedRange)")
                    .font(.system(size: 38, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.94))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.64)
                    .overlay(alignment: .trailing) {
                        Text(rangeUnitTitle)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.68))
                            .lineLimit(1)
                            .offset(x: 18, y: 6)
                    }

                WatchBatteryReadout(batteryPercent: batteryPercent)
                    .padding(.top, -1)
                    .offset(x: 3)
            }
            .offset(y: -7)

            HStack(spacing: 7) {
                WatchRefreshControlButton(action: onRefreshTap)

                WatchGaugeControlButton(
                    systemName: "thermometer.medium",
                    title: temperatureTitle,
                    action: onTemperatureTap
                )
            }
            .offset(y: 54)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Remaining range \(displayedRange) \(rangeUnitTitle), battery \(batteryPercent) percent, \(temperatureTitle)")
    }
}

private struct WatchBatteryReadout: View {
    let batteryPercent: Int

    private var fillFraction: Double {
        min(max(Double(batteryPercent) / 100, 0), 1)
    }

    var body: some View {
        HStack(spacing: 2) {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(.white.opacity(0.08))

                GeometryReader { geometry in
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(watchRangeAccentColor.opacity(0.68))
                        .frame(width: max(6, geometry.size.width * fillFraction))
                        .padding(3)
                }
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(.white.opacity(0.42), lineWidth: 1.25)

                Text("\(batteryPercent)%")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.95))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(width: 58, height: 26)

            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(.white.opacity(0.34))
                .frame(width: 4, height: 12)
        }
        .frame(width: 64, height: 26)
    }
}

private struct WatchRangeArc: Shape {
    let startAngle: Double
    let endAngle: Double

    func path(in rect: CGRect) -> Path {
        let lineInset = 6.0
        let radius = min(rect.width, rect.height) / 2 - lineInset
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let steps = max(1, Int(abs(endAngle - startAngle) / 3))
        var path = Path()

        for step in 0...steps {
            let progress = Double(step) / Double(steps)
            let angle = (startAngle + (endAngle - startAngle) * progress) * .pi / 180
            let point = CGPoint(
                x: center.x + cos(angle) * radius,
                y: center.y + sin(angle) * radius
            )

            if step == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }

        return path
    }
}

private struct WatchRefreshControlButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.76))
                .frame(width: 28, height: 28)
                .background(
                    Circle()
                        .fill(.white.opacity(0.08))
                )
                .frame(width: 42, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Refresh iPhone values")
    }
}

private struct WatchGaugeControlButton: View {
    let systemName: String
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: systemName)
                    .font(.system(size: 13, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.white.opacity(0.76))
                    .frame(width: 28, height: 28)
                    .background(
                        Circle()
                            .fill(.white.opacity(0.08))
                    )

                Text(title)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.9))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .frame(minWidth: 70, minHeight: 44)
        }
        .buttonStyle(.plain)
    }
}

private struct DrivingModeSelectionRow: View {
    let selectedMode: DrivingMode
    let onSelect: (DrivingMode) -> Void

    var body: some View {
        HStack(spacing: 5) {
            ForEach(DrivingMode.allCases) { mode in
                DrivingModeSelectionButton(
                    mode: mode,
                    isSelected: mode == selectedMode,
                    action: {
                        onSelect(mode)
                    }
                )
            }
        }
        .frame(width: 154, height: 30)
        .accessibilityElement(children: .contain)
    }
}

private struct DrivingModeSelectionButton: View {
    let mode: DrivingMode
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(isSelected ? watchRangeAccentColor.opacity(0.18) : Color.white.opacity(0.05))
                    .overlay {
                        Circle()
                            .stroke(
                                isSelected ? watchRangeAccentColor.opacity(0.72) : Color.white.opacity(0.08),
                                lineWidth: isSelected ? 1 : 0.5
                            )
                    }

                DrivingModeIcon(mode: mode)
                    .foregroundStyle(isSelected ? watchRangeAccentColor : Color.white.opacity(0.48))
            }
            .frame(width: 30, height: 30)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(mode.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct DrivingModeIcon: View {
    let mode: DrivingMode

    var body: some View {
        switch mode {
        case .motorwayMix:
            MotorwayMixIcon()
        default:
            Image(systemName: mode.symbolName)
                .font(.system(size: 14, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
        }
    }
}

private struct MotorwayMixIcon: View {
    var body: some View {
        ZStack {
            Image(systemName: DrivingMode.calmRoads.symbolName)
                .font(.system(size: 10, weight: .semibold))
                .offset(x: -5)

            Image(systemName: DrivingMode.motorway.symbolName)
                .font(.system(size: 10, weight: .semibold))
                .offset(x: 5)

            Rectangle()
                .frame(width: 1, height: 19)
                .rotationEffect(.degrees(28))
                .opacity(0.62)
        }
        .frame(width: 20, height: 20)
        .symbolRenderingMode(.hierarchical)
    }
}

private enum WatchTemperatureUnit: String {
    case celsius
    case fahrenheit

    init(snapshotRawValue: String?) {
        switch snapshotRawValue {
        case Self.fahrenheit.rawValue:
            self = .fahrenheit
        case Self.celsius.rawValue:
            fallthrough
        default:
            self = .celsius
        }
    }

    var label: String {
        switch self {
        case .celsius:
            "°C"
        case .fahrenheit:
            "°F"
        }
    }

    var displayRange: ClosedRange<Double> {
        switch self {
        case .celsius:
            -20.0...35.0
        case .fahrenheit:
            0.0...100.0
        }
    }

    var displayStep: Double {
        switch self {
        case .celsius:
            1.0
        case .fahrenheit:
            2.0
        }
    }

    func displayTemperature(fromCelsius celsius: Double) -> Double {
        switch self {
        case .celsius:
            celsius
        case .fahrenheit:
            celsius * 9 / 5 + 32
        }
    }

    func celsius(fromDisplayed value: Double) -> Double {
        switch self {
        case .celsius:
            value
        case .fahrenheit:
            (value - 32) * 5 / 9
        }
    }

    func snappedDisplayValue(_ value: Double) -> Double {
        let steppedValue = (value / displayStep).rounded() * displayStep
        return min(max(steppedValue, displayRange.lowerBound), displayRange.upperBound)
    }

    func snappedDisplayValue(fromCelsius celsius: Double) -> Double {
        snappedDisplayValue(displayTemperature(fromCelsius: celsius))
    }
}

private enum WatchDisplayUnits: String {
    case metric
    case imperial

    private static let kilometersPerMile = 1.609344

    init(snapshotRawValue: String?) {
        switch snapshotRawValue {
        case Self.imperial.rawValue:
            self = .imperial
        case Self.metric.rawValue:
            fallthrough
        default:
            self = .metric
        }
    }

    var distanceUnitLabel: String {
        switch self {
        case .metric:
            "km"
        case .imperial:
            "mi"
        }
    }

    func displayDistance(fromKm kilometers: Double) -> Double {
        switch self {
        case .metric:
            kilometers
        case .imperial:
            kilometers / Self.kilometersPerMile
        }
    }
}

private enum DrivingMode: String, CaseIterable, Identifiable {
    case calmRoads = "Calm roads"
    case cityMix = "City mix"
    case motorwayMix = "Motorway mix"
    case motorway = "Motorway"

    var id: String { rawValue }
    var title: String { rawValue }
    var symbolName: String {
        switch self {
        case .calmRoads:
            "leaf.fill"
        case .cityMix:
            "building.2"
        case .motorwayMix, .motorway:
            "road.lanes"
        }
    }

    init(roadTypeProfile: RoadTypeProfile) {
        switch roadTypeProfile {
        case .countryside:
            self = .calmRoads
        case .cityMix:
            self = .cityMix
        case .motorwayMix:
            self = .motorwayMix
        case .motorway:
            self = .motorway
        }
    }

    var roadTypeProfile: RoadTypeProfile {
        switch self {
        case .calmRoads:
            .countryside
        case .cityMix:
            .cityMix
        case .motorwayMix:
            .motorwayMix
        case .motorway:
            .motorway
        }
    }
}

private enum Temperature {
    static func title(for celsius: Double, unit: WatchTemperatureUnit) -> String {
        "\(Int(unit.displayTemperature(fromCelsius: celsius).rounded()))\(unit.label)"
    }
}

private struct WatchForecastAssumptions: Equatable {
    var motorwaySpeed: Double
    var roadSurface: RoadSurface
    var windCondition: WindCondition
    var airConditioningMode: AirConditioningMode
    var selectedTyreSet: TyreSet
    var summerTyreClass: RollingResistanceClass
    var winterTyreClass: RollingResistanceClass
    var useContinuousCalibration: Bool

    var activeRollingResistanceClass: RollingResistanceClass {
        selectedTyreSet == .summer ? summerTyreClass : winterTyreClass
    }

    static let defaults = WatchForecastAssumptions(
        motorwaySpeed: MiniConsumptionDefaults.motorwaySpeedKmh,
        roadSurface: MiniConsumptionDefaults.roadSurface,
        windCondition: MiniConsumptionDefaults.windCondition,
        airConditioningMode: MiniConsumptionDefaults.airConditioningMode,
        selectedTyreSet: MiniConsumptionDefaults.selectedTyreSet,
        summerTyreClass: MiniConsumptionDefaults.summerTyreClass,
        winterTyreClass: MiniConsumptionDefaults.winterTyreClass,
        useContinuousCalibration: MiniConsumptionDefaults.useContinuousCalibration
    )

    init(
        motorwaySpeed: Double,
        roadSurface: RoadSurface,
        windCondition: WindCondition,
        airConditioningMode: AirConditioningMode,
        selectedTyreSet: TyreSet,
        summerTyreClass: RollingResistanceClass,
        winterTyreClass: RollingResistanceClass,
        useContinuousCalibration: Bool
    ) {
        self.motorwaySpeed = MiniConsumptionDefaults.normalizedMotorwaySpeed(motorwaySpeed)
        self.roadSurface = roadSurface
        self.windCondition = windCondition
        self.airConditioningMode = airConditioningMode
        self.selectedTyreSet = selectedTyreSet
        self.summerTyreClass = summerTyreClass
        self.winterTyreClass = winterTyreClass
        self.useContinuousCalibration = useContinuousCalibration
    }

    init(snapshot: WatchRangeStateSnapshot) {
        self.init(
            motorwaySpeed: snapshot.motorwaySpeed,
            roadSurface: snapshot.roadSurface,
            windCondition: snapshot.windCondition,
            airConditioningMode: snapshot.airConditioningMode,
            selectedTyreSet: snapshot.selectedTyreSet,
            summerTyreClass: snapshot.summerTyreClass,
            winterTyreClass: snapshot.winterTyreClass,
            useContinuousCalibration: snapshot.useContinuousCalibration
        )
    }
}

private struct WatchVehicleProfile: Identifiable, Equatable {
    let id: String
    let displayName: String
    let calculationProfile: VehicleProfile
    let referenceConsumptionOverrideKWhPer100Km: Double?

    init(
        id: String,
        displayName: String,
        calculationProfile: VehicleProfile,
        referenceConsumptionOverrideKWhPer100Km: Double? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.calculationProfile = calculationProfile
        self.referenceConsumptionOverrideKWhPer100Km = referenceConsumptionOverrideKWhPer100Km
    }

    var referenceConsumptionKWhPer100Km: Double {
        if let referenceConsumptionOverrideKWhPer100Km {
            return referenceConsumptionOverrideKWhPer100Km
        }

        guard calculationProfile.kind == .custom else {
            return defaultReferenceConsumptionKWhPer100Km
        }

        return calculationProfile.usableBatteryKWh / degradedWLTPRangeKm * 100 * 1.04
    }

    private var degradedWLTPRangeKm: Double {
        let nominalRangeKm = calculationProfile.wltpRangeKm.isFinite && calculationProfile.wltpRangeKm > 0
            ? calculationProfile.wltpRangeKm
            : VehicleProfileResolver.defaultCustomWLTPRangeKm
        let degradationPercent = min(max(calculationProfile.batteryDegradationPercent, 0), 10)
        return nominalRangeKm * (1.0 - Double(degradationPercent) / 100.0)
    }

    static let miniCooperSE = WatchVehicleProfile(
        id: VehicleProfileResolver.builtInMiniProfileID,
        displayName: VehicleProfileResolver.builtInMiniName,
        calculationProfile: VehicleProfileResolver.builtInMiniProfile(from: defaultResolverInput)
    )

    static func activeProfile(
        snapshot: WatchRangeStateSnapshot,
        availableProfiles: [WatchVehicleProfile]
    ) -> WatchVehicleProfile {
        if let activeVehicleProfileID = snapshot.activeVehicleProfileID,
           let profile = availableProfiles.first(where: { $0.id == activeVehicleProfileID }) {
            return profile.withReferenceConsumptionOverride(snapshot.referenceConsumptionKWhPer100Km)
        }

        let snapshotProfile = WatchVehicleProfile(snapshot: snapshot)
        return availableProfiles.first(where: { $0.id == snapshotProfile.id })?
            .withReferenceConsumptionOverride(snapshot.referenceConsumptionKWhPer100Km)
            ?? snapshotProfile
    }

    static func availableProfiles(snapshot: WatchRangeStateSnapshot) -> [WatchVehicleProfile] {
        guard let profiles = snapshot.availableVehicleProfiles,
              profiles.isEmpty == false else {
            return [WatchVehicleProfile(snapshot: snapshot)]
        }

        let syncedProfiles = profiles.map {
            WatchVehicleProfile(profile: $0)
        }

        return syncedProfiles.contains(where: { $0.id == VehicleProfileResolver.builtInMiniProfileID })
            ? syncedProfiles
            : [.miniCooperSE] + syncedProfiles
    }

    init(profile: VehicleProfile, referenceConsumptionOverrideKWhPer100Km: Double? = nil) {
        self.init(
            id: profile.id,
            displayName: profile.displayName,
            calculationProfile: profile,
            referenceConsumptionOverrideKWhPer100Km: referenceConsumptionOverrideKWhPer100Km
        )
    }

    private init(snapshot: WatchRangeStateSnapshot) {
        let inferredProfileKind: VehicleProfileDefinitionKind = snapshot.vehicleProfileName == VehicleProfileResolver.builtInMiniName
            ? .builtInMini
            : .custom
        let profileKind = snapshot.vehicleProfileKind ?? inferredProfileKind
        let profileID = profileKind == .builtInMini
            ? VehicleProfileResolver.builtInMiniProfileID
            : snapshot.vehicleProfileName.lowercased().replacingOccurrences(of: " ", with: "-")

        self.init(
            id: profileID,
            displayName: snapshot.vehicleProfileName,
            calculationProfile: VehicleProfile(
                id: profileID,
                displayName: snapshot.vehicleProfileName,
                kind: profileKind,
                usableBatteryKWh: snapshot.usableBatteryKWh,
                wltpRangeKm: snapshot.wltpRangeKm,
                peakDCChargingKW: snapshot.peakDCChargingKW,
                batteryDegradationPercent: snapshot.batteryDegradationPercent,
                summerTyreClass: snapshot.summerTyreClass,
                winterTyreClass: snapshot.winterTyreClass,
                createdAt: nil,
                updatedAt: nil
            ),
            referenceConsumptionOverrideKWhPer100Km: snapshot.referenceConsumptionKWhPer100Km
        )
    }

    private func withReferenceConsumptionOverride(_ referenceConsumption: Double?) -> WatchVehicleProfile {
        WatchVehicleProfile(
            id: id,
            displayName: displayName,
            calculationProfile: calculationProfile,
            referenceConsumptionOverrideKWhPer100Km: referenceConsumption
        )
    }

    private static let defaultResolverInput = VehicleProfileResolverInput(
        experimentalCustomVehicleProfileEnabled: false,
        experimentalUsableBatteryCapacityKWh: VehicleProfileResolver.defaultCustomUsableBatteryCapacityKWh,
        experimentalOfficialWLTPRangeKm: VehicleProfileResolver.defaultCustomWLTPRangeKm,
        experimentalMaximumDCChargingSpeedKW: VehicleProfileResolver.defaultCustomPeakDCChargingKW,
        batteryDegradationPercent: MiniConsumptionDefaults.batteryDegradationPercent,
        summerTyreClass: MiniConsumptionDefaults.summerTyreClass,
        winterTyreClass: MiniConsumptionDefaults.winterTyreClass
    )

}

private struct TemperatureSelector: View {
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isCrownFocused: Bool
    private let selectedUnit: WatchTemperatureUnit
    @State private var draftDisplayedTemperature: Double

    let onDone: (Double) -> Void

    init(
        selectedTemperatureC: Double,
        selectedUnit: WatchTemperatureUnit,
        onDone: @escaping (Double) -> Void
    ) {
        self.selectedUnit = selectedUnit
        _draftDisplayedTemperature = State(
            initialValue: selectedUnit.snappedDisplayValue(fromCelsius: selectedTemperatureC)
        )
        self.onDone = onDone
    }

    var body: some View {
        VStack(spacing: 10) {
            Spacer(minLength: 8)

            VStack(spacing: 3) {
                Text("Temperature")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(1)

                Text("\(Int(draftDisplayedTemperature.rounded()))\(selectedUnit.label)")
                    .font(.system(size: 48, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.66)
            }

            Button {
                onDone(selectedUnit.celsius(fromDisplayed: selectedUnit.snappedDisplayValue(draftDisplayedTemperature)))
            } label: {
                Text("Done")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            Button {
                dismiss()
            } label: {
                Text("Cancel")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .containerBackground(.black, for: .navigation)
        .focusable(true)
        .focused($isCrownFocused)
        .digitalCrownRotation(
            $draftDisplayedTemperature,
            from: selectedUnit.displayRange.lowerBound,
            through: selectedUnit.displayRange.upperBound,
            by: selectedUnit.displayStep,
            sensitivity: .medium,
            isContinuous: false,
            isHapticFeedbackEnabled: true
        )
        .onChange(of: draftDisplayedTemperature) { _, newValue in
            let snappedValue = selectedUnit.snappedDisplayValue(newValue)
            guard snappedValue != newValue else {
                return
            }

            draftDisplayedTemperature = snappedValue
        }
        .onAppear {
            isCrownFocused = true
        }
    }
}

private struct BatteryGauge: View {
    let percent: Double

    var body: some View {
        GeometryReader { proxy in
            let fillWidth = max(0, proxy.size.width - 10) * percent / 100

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(.white.opacity(0.45), lineWidth: 3)

                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.green, Color.mint],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: fillWidth)
                    .padding(5)

                HStack {
                    Spacer()

                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(.white.opacity(0.45))
                        .frame(width: 5, height: 18)
                        .offset(x: 8)
                }
            }
            .shadow(color: .green.opacity(0.35), radius: 8, x: 0, y: 3)
        }
    }
}

private struct WatchRow: View {
    let title: String
    let value: String
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                Spacer(minLength: 4)

                Text(value)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.78))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white.opacity(0.58))
            }
            .padding(.horizontal, 7)
            .frame(height: 22)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(.white.opacity(0.07))
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ContentView()
}
