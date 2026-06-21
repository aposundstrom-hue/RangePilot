import Foundation

enum MiniConsumptionCalculator {
    nonisolated static let nominalUsableBatteryKWh = 28.9
    nonisolated static let continuousCalibrationBaseReferenceConsumptionKWhPer100Km = defaultReferenceConsumptionKWhPer100Km
    nonisolated static let calibrationSafetyMultiplier = 1.03
    static let effectiveFastChargePowerBelow80KW = 41.0
    static let defaultAverageChargingSpeedKW = effectiveFastChargePowerBelow80KW
    static let averageChargingSpeedBoundsKW = 20.0...200.0
    static let averageChargingSpeedStepKW = 1.0
    static let averageChargingSpeedPeakDCDeratingFactor = 0.60

    static func averageChargingSpeedBoundsKW(for profile: VehicleProfile) -> ClosedRange<Double> {
        let peakDCChargingKW = profile.peakDCChargingKW.isFinite && profile.peakDCChargingKW > 0
            ? profile.peakDCChargingKW
            : averageChargingSpeedBoundsKW.upperBound
        let upperBound = min(peakDCChargingKW, averageChargingSpeedBoundsKW.upperBound)
        let lowerBound = min(averageChargingSpeedBoundsKW.lowerBound, upperBound)
        return lowerBound...upperBound
    }

    static func defaultAverageChargingSpeedKW(for profile: VehicleProfile) -> Double {
        guard profile.kind == .custom else {
            return defaultAverageChargingSpeedKW
        }

        let peakDCChargingKW = profile.peakDCChargingKW.isFinite && profile.peakDCChargingKW > 0
            ? profile.peakDCChargingKW
            : VehicleProfileResolver.defaultCustomPeakDCChargingKW
        let roundedAverage = (peakDCChargingKW * averageChargingSpeedPeakDCDeratingFactor / averageChargingSpeedStepKW).rounded()
            * averageChargingSpeedStepKW
        let bounds = averageChargingSpeedBoundsKW(for: profile)
        return min(
            max(roundedAverage, bounds.lowerBound),
            bounds.upperBound
        )
    }

    private struct ChargingSpeedSegment {
        let lowerBoundPercent: Double
        let upperBoundPercent: Double
        let speedMultiplier: Double
    }

    nonisolated static func effectiveUsableBatteryKWh(degradationPercent: Int) -> Double {
        let clampedDegradationPercent = min(max(degradationPercent, 0), 10)
        return nominalUsableBatteryKWh * (1.0 - Double(clampedDegradationPercent) / 100.0)
    }

    nonisolated static func chargingTaperStartSOC(degradationPercent: Int) -> Double {
        max(70, 80 - 0.5 * Double(degradationPercent))
    }

    static func calculateRemainingRange(
        currentBatteryPercent: Double,
        expectedKWhPer100km: Double,
        usableBatteryKWh: Double = MiniConsumptionCalculator.nominalUsableBatteryKWh
    ) -> RemainingRangeEstimate {
        let availableEnergyKWh = max(0, currentBatteryPercent / 100 * usableBatteryKWh)
        let rangeKm = expectedKWhPer100km > 0 ? availableEnergyKWh / expectedKWhPer100km * 100 : 0

        return RemainingRangeEstimate(
            availableEnergyKWh: availableEnergyKWh,
            rangeKm: rangeKm
        )
    }

    static func calculateChargingLegRange(
        expectedKWhPer100km: Double,
        chargingWindow: ChargingWindow = .normal,
        usableBatteryKWh: Double = MiniConsumptionCalculator.nominalUsableBatteryKWh
    ) -> Double {
        expectedKWhPer100km > 0 ? chargingWindow.energyKWh(usableBatteryKWh: usableBatteryKWh) / expectedKWhPer100km * 100 : 0
    }

    static func calculateRangeToBatteryThreshold(
        startBatteryPercent: Double,
        thresholdBatteryPercent: Double,
        expectedKWhPer100km: Double,
        usableBatteryKWh: Double = MiniConsumptionCalculator.nominalUsableBatteryKWh
    ) -> Double {
        let availableEnergyKWh = max(0, (startBatteryPercent - thresholdBatteryPercent) / 100 * usableBatteryKWh)
        return expectedKWhPer100km > 0 ? availableEnergyKWh / expectedKWhPer100km * 100 : 0
    }

    static func calculateFirstChargingStopSearchDistance(
        startBatteryPercent: Double,
        expectedKWhPer100km: Double,
        chargingWindow: ChargingWindow = .normal,
        usableBatteryKWh: Double = MiniConsumptionCalculator.nominalUsableBatteryKWh
    ) -> Double {
        calculateRangeToBatteryThreshold(
            startBatteryPercent: startBatteryPercent,
            thresholdBatteryPercent: chargingWindow.minimumPercent,
            expectedKWhPer100km: expectedKWhPer100km,
            usableBatteryKWh: usableBatteryKWh
        ) * 0.9
    }

    static func calculateChargingStopDistances(
        distanceKm: Double,
        startBatteryPercent: Double,
        expectedKWhPer100km: Double,
        chargingWindow: ChargingWindow = .normal,
        arrivalBatteryTargetPercent: Double,
        usableBatteryKWh: Double = MiniConsumptionCalculator.nominalUsableBatteryKWh
    ) -> [Double] {
        guard
            distanceKm > 0,
            expectedKWhPer100km > 0,
            usableBatteryKWh > 0
        else {
            return []
        }

        let percentPerKm = expectedKWhPer100km / 100 / usableBatteryKWh * 100
        guard percentPerKm > 0 else {
            return []
        }

        func distance(forBatteryPercent batteryPercent: Double) -> Double {
            max(0, batteryPercent) / percentPerKm
        }

        let lowerThresholdPercent = chargingWindow.minimumPercent
        let targetPercent = chargingWindow.targetPercent
        let arrivalTargetPercent = min(max(arrivalBatteryTargetPercent, 0), 100)
        let noChargeReachKm = distance(forBatteryPercent: startBatteryPercent - arrivalTargetPercent)

        guard distanceKm > noChargeReachKm else {
            return []
        }

        let firstLegReachKm = distance(forBatteryPercent: startBatteryPercent - lowerThresholdPercent)
        let chargeLegKm = distance(forBatteryPercent: targetPercent - lowerThresholdPercent)
        let finalLegReachKm = distance(forBatteryPercent: targetPercent - arrivalTargetPercent)
        let minimumRouteSpacingKm = min(5, max(0.5, distanceKm * 0.02))

        guard chargeLegKm > 0, finalLegReachKm > 0 else {
            return []
        }

        func clampedStopDistance(_ candidate: Double) -> Double {
            min(max(candidate, minimumRouteSpacingKm), max(minimumRouteSpacingKm, distanceKm - minimumRouteSpacingKm))
        }

        var stopDistancesKm = [Double]()
        var nextStopDistanceKm = clampedStopDistance(firstLegReachKm)

        while nextStopDistanceKm < distanceKm {
            if let previousStopDistanceKm = stopDistancesKm.last,
               nextStopDistanceKm - previousStopDistanceKm < minimumRouteSpacingKm {
                nextStopDistanceKm = previousStopDistanceKm + minimumRouteSpacingKm
            }

            guard nextStopDistanceKm < distanceKm else {
                break
            }

            stopDistancesKm.append(nextStopDistanceKm)

            let remainingDistanceKm = distanceKm - nextStopDistanceKm
            guard remainingDistanceKm > finalLegReachKm else {
                break
            }

            nextStopDistanceKm += chargeLegKm
        }

        return stopDistancesKm.reduce(into: [Double]()) { uniqueStops, stopDistanceKm in
            let clampedDistanceKm = clampedStopDistance(stopDistanceKm)
            guard clampedDistanceKm > 0, clampedDistanceKm < distanceKm else {
                return
            }

            if let previousDistanceKm = uniqueStops.last,
               clampedDistanceKm - previousDistanceKm < minimumRouteSpacingKm {
                return
            }

            uniqueStops.append(clampedDistanceKm)
        }
    }

    static func calculateBatteryPlan(
        totalTripKWh: Double,
        startBatteryPercent: Double,
        temperature: Double,
        chargingWindow: ChargingWindow = .normal,
        arrivalBatteryTargetPercent: Double? = nil,
        averageChargingSpeedKW: Double = defaultAverageChargingSpeedKW,
        chargingSetupMinutes: Double = 0,
        usableBatteryKWh: Double = MiniConsumptionCalculator.nominalUsableBatteryKWh,
        chargingTaperStartSOC: Double = 80,
        chargingSpeedBoundsKW: ClosedRange<Double> = averageChargingSpeedBoundsKW
    ) -> BatteryPlan {
        let reserveBatteryPercent = arrivalBatteryTargetPercent ?? chargingWindow.minimumPercent

        let startEnergy = startBatteryPercent / 100 * usableBatteryKWh
        let reserveEnergy = reserveBatteryPercent / 100 * usableBatteryKWh
        let usableTripEnergy = max(0, startEnergy - reserveEnergy)

        if totalTripKWh <= usableTripEnergy {
            let arrivalBatteryPercent = (startEnergy - totalTripKWh) / usableBatteryKWh * 100

            return BatteryPlan(
                startBatteryPercent: startBatteryPercent,
                reserveBatteryPercent: reserveBatteryPercent,
                arrivalBatteryPercent: arrivalBatteryPercent,
                needsCharging: false,
                chargingStops: 0,
                totalChargePercentNeeded: 0,
                estimatedChargingMinutes: 0
            )
        }

        let remainingEnergyNeeded = totalTripKWh - usableTripEnergy
        let stopEnergy = chargingWindow.energyKWh(usableBatteryKWh: usableBatteryKWh)
        let chargingStops = Int(ceil(remainingEnergyNeeded / stopEnergy))
        let totalChargePercentNeeded = remainingEnergyNeeded / usableBatteryKWh * 100
        let estimatedChargingMinutes = estimateTotalChargingMinutes(
            energyNeededKWh: remainingEnergyNeeded,
            weatherC: temperature,
            stopEnergyKWh: stopEnergy,
            chargingStops: chargingStops,
            chargingWindow: chargingWindow,
            averageChargingSpeedKW: averageChargingSpeedKW,
            usableBatteryKWh: usableBatteryKWh,
            chargingTaperStartSOC: chargingTaperStartSOC,
            chargingSpeedBoundsKW: chargingSpeedBoundsKW
        )
        let totalSetupMinutes = max(0, chargingSetupMinutes) * Double(chargingStops)

        return BatteryPlan(
            startBatteryPercent: startBatteryPercent,
            reserveBatteryPercent: reserveBatteryPercent,
            arrivalBatteryPercent: reserveBatteryPercent,
            needsCharging: true,
            chargingStops: chargingStops,
            totalChargePercentNeeded: totalChargePercentNeeded,
            estimatedChargingMinutes: estimatedChargingMinutes + totalSetupMinutes
        )
    }

    static func estimateTotalChargingMinutes(
        energyNeededKWh: Double,
        weatherC: Double,
        stopEnergyKWh: Double,
        chargingStops: Int,
        chargingWindow: ChargingWindow = .normal,
        averageChargingSpeedKW: Double = defaultAverageChargingSpeedKW,
        usableBatteryKWh: Double = MiniConsumptionCalculator.nominalUsableBatteryKWh,
        chargingTaperStartSOC: Double = 80,
        chargingSpeedBoundsKW: ClosedRange<Double> = averageChargingSpeedBoundsKW
    ) -> Double {
        var remainingEnergy = energyNeededKWh
        var totalMinutes = 0.0

        for stopIndex in 0..<chargingStops {
            let stopEnergyNeeded = min(remainingEnergy, stopEnergyKWh)
            let stopMinutes = estimateChargingMinutes(
                energyNeededKWh: stopEnergyNeeded,
                weatherC: weatherC,
                stopIndex: stopIndex,
                chargingWindow: chargingWindow,
                averageChargingSpeedKW: averageChargingSpeedKW,
                usableBatteryKWh: usableBatteryKWh,
                chargingTaperStartSOC: chargingTaperStartSOC,
                chargingSpeedBoundsKW: chargingSpeedBoundsKW
            )
            totalMinutes += stopMinutes
            remainingEnergy -= stopEnergyNeeded
        }

        return totalMinutes
    }

    static func estimateChargingMinutes(
        energyNeededKWh: Double,
        weatherC: Double,
        stopIndex: Int,
        chargingWindow: ChargingWindow = .normal,
        averageChargingSpeedKW: Double = defaultAverageChargingSpeedKW,
        usableBatteryKWh: Double = MiniConsumptionCalculator.nominalUsableBatteryKWh,
        chargingTaperStartSOC: Double = 80,
        chargingSpeedBoundsKW: ClosedRange<Double> = averageChargingSpeedBoundsKW
    ) -> Double {
        let maxStopEnergyKWh = chargingWindow.energyKWh(usableBatteryKWh: usableBatteryKWh)
        let cappedEnergyNeeded = min(energyNeededKWh, maxStopEnergyKWh)

        guard cappedEnergyNeeded > 0 else {
            return 0
        }

        return estimateSegmentedChargingMinutes(
            energyNeededKWh: cappedEnergyNeeded,
            chargingWindow: chargingWindow,
            averageChargingSpeedKW: averageChargingSpeedKW,
            usableBatteryKWh: usableBatteryKWh,
            chargingTaperStartSOC: chargingTaperStartSOC,
            chargingSpeedBoundsKW: chargingSpeedBoundsKW
        )
    }

    static func estimateSegmentedChargingMinutes(
        energyNeededKWh: Double,
        chargingWindow: ChargingWindow = .normal,
        averageChargingSpeedKW: Double = defaultAverageChargingSpeedKW,
        usableBatteryKWh: Double = MiniConsumptionCalculator.nominalUsableBatteryKWh,
        chargingTaperStartSOC: Double = 80,
        chargingSpeedBoundsKW: ClosedRange<Double> = averageChargingSpeedBoundsKW
    ) -> Double {
        estimateSegmentedChargingMinutes(
            fromPercent: chargingWindow.minimumPercent,
            toPercent: min(100, chargingWindow.minimumPercent + energyNeededKWh / usableBatteryKWh * 100),
            averageChargingSpeedKW: averageChargingSpeedKW,
            usableBatteryKWh: usableBatteryKWh,
            chargingTaperStartSOC: chargingTaperStartSOC,
            chargingSpeedBoundsKW: chargingSpeedBoundsKW
        )
    }

    static func estimateSegmentedChargingMinutes(
        fromPercent: Double,
        toPercent: Double,
        averageChargingSpeedKW: Double = defaultAverageChargingSpeedKW,
        usableBatteryKWh: Double = MiniConsumptionCalculator.nominalUsableBatteryKWh,
        chargingTaperStartSOC: Double = 80,
        chargingSpeedBoundsKW: ClosedRange<Double> = averageChargingSpeedBoundsKW
    ) -> Double {
        let clampedAverageChargingSpeedKW = min(
            max(averageChargingSpeedKW, chargingSpeedBoundsKW.lowerBound),
            chargingSpeedBoundsKW.upperBound
        )
        let startPercent = min(max(fromPercent, 0), 100)
        let endPercent = min(max(toPercent, startPercent), 100)
        let taperStartPercent = min(max(chargingTaperStartSOC, 65), 80)
        let speedSegments = [
            ChargingSpeedSegment(lowerBoundPercent: 0, upperBoundPercent: 20, speedMultiplier: 0.9),
            ChargingSpeedSegment(lowerBoundPercent: 20, upperBoundPercent: taperStartPercent, speedMultiplier: 1.0),
            ChargingSpeedSegment(lowerBoundPercent: taperStartPercent, upperBoundPercent: 90, speedMultiplier: 0.6),
            ChargingSpeedSegment(lowerBoundPercent: 90, upperBoundPercent: 100, speedMultiplier: 0.25)
        ]

        return speedSegments.reduce(0.0) { totalMinutes, segment in
            let segmentStartPercent = max(startPercent, segment.lowerBoundPercent)
            let segmentEndPercent = min(endPercent, segment.upperBoundPercent)
            let segmentEnergyKWh = max(0, segmentEndPercent - segmentStartPercent) / 100 * usableBatteryKWh
            let segmentChargingSpeedKW = clampedAverageChargingSpeedKW * segment.speedMultiplier

            return totalMinutes + segmentEnergyKWh / segmentChargingSpeedKW * 60
        }
    }

    nonisolated static func calculateForecast(
        referenceConsumption: Double,
        distance: Double,
        temperature: Double,
        roadTypeProfile: RoadTypeProfile,
        motorwaySpeed: Double,
        roadSurface: RoadSurface,
        windCondition: WindCondition,
        planningMode: PlanningMode,
        rollingResistanceClass: RollingResistanceClass,
        airConditioningMode: AirConditioningMode = .on,
        applyDistanceAdjustment: Bool = true,
        usesCustomVehicleProfile: Bool = false,
        usableBatteryKWh: Double = MiniConsumptionCalculator.nominalUsableBatteryKWh
    ) -> ForecastResult {
        if roadTypeProfile == .motorwayMix {
            let cityMixResult = calculateRouteForecast(
                referenceConsumption: referenceConsumption,
                distance: distance,
                temperature: temperature,
                roadTypeProfile: .cityMix,
                motorwaySpeed: motorwaySpeed,
                roadSurface: roadSurface,
                windCondition: windCondition,
                planningMode: planningMode,
                rollingResistanceClass: rollingResistanceClass,
                airConditioningMode: .on,
                applyDistanceAdjustment: applyDistanceAdjustment,
                motorwaySpeedSensitivityOverride: 0,
                usesCustomVehicleProfile: usesCustomVehicleProfile,
                usableBatteryKWh: usableBatteryKWh
            )
            let countrysideResult = calculateRouteForecast(
                referenceConsumption: referenceConsumption,
                distance: distance,
                temperature: temperature,
                roadTypeProfile: .countryside,
                motorwaySpeed: motorwaySpeed,
                roadSurface: roadSurface,
                windCondition: windCondition,
                planningMode: planningMode,
                rollingResistanceClass: rollingResistanceClass,
                airConditioningMode: .on,
                applyDistanceAdjustment: applyDistanceAdjustment,
                motorwaySpeedSensitivityOverride: 0,
                usesCustomVehicleProfile: usesCustomVehicleProfile,
                usableBatteryKWh: usableBatteryKWh
            )
            let motorwayResult = calculateRouteForecast(
                referenceConsumption: referenceConsumption,
                distance: distance,
                temperature: temperature,
                roadTypeProfile: .motorway,
                motorwaySpeed: motorwaySpeed,
                roadSurface: roadSurface,
                windCondition: windCondition,
                planningMode: planningMode,
                rollingResistanceClass: rollingResistanceClass,
                airConditioningMode: .on,
                applyDistanceAdjustment: applyDistanceAdjustment,
                motorwaySpeedSensitivityOverride: 0,
                usesCustomVehicleProfile: usesCustomVehicleProfile,
                usableBatteryKWh: usableBatteryKWh
            )
            let blendedResult = blendedForecastResult(
                cityMixResult: cityMixResult,
                countrysideResult: countrysideResult,
                motorwayResult: motorwayResult
            )
            let motorwayMixSpeedFactor = scaledMotorwaySpeedFactor(
                speedSensitivity: RoadTypeProfile.motorwayMix.motorwaySpeedScalingFactor,
                motorwaySpeed: motorwaySpeed,
                referenceConsumption: referenceConsumption,
                usableBatteryKWh: usableBatteryKWh
            )

            let speedAdjustedResult = applyingMotorwaySpeedFactor(
                motorwayMixSpeedFactor,
                to: blendedResult
            )

            return applyingAirConditioningAdjustment(
                to: speedAdjustedResult,
                roadTypeProfile: .motorwayMix,
                temperature: temperature,
                airConditioningMode: airConditioningMode
            )
        }

        return calculateRouteForecast(
            referenceConsumption: referenceConsumption,
            distance: distance,
            temperature: temperature,
            roadTypeProfile: roadTypeProfile,
            motorwaySpeed: motorwaySpeed,
            roadSurface: roadSurface,
            windCondition: windCondition,
            planningMode: planningMode,
            rollingResistanceClass: rollingResistanceClass,
            airConditioningMode: airConditioningMode,
            applyDistanceAdjustment: applyDistanceAdjustment,
            usesCustomVehicleProfile: usesCustomVehicleProfile,
            usableBatteryKWh: usableBatteryKWh
        )
    }

    private nonisolated static func calculateRouteForecast(
        referenceConsumption: Double,
        distance: Double,
        temperature: Double,
        roadTypeProfile: RoadTypeProfile,
        motorwaySpeed: Double,
        roadSurface: RoadSurface,
        windCondition: WindCondition,
        planningMode: PlanningMode,
        rollingResistanceClass: RollingResistanceClass,
        airConditioningMode: AirConditioningMode,
        applyDistanceAdjustment: Bool,
        motorwaySpeedSensitivityOverride: Double? = nil,
        usesCustomVehicleProfile: Bool,
        usableBatteryKWh: Double
    ) -> ForecastResult {
        let temperatureAdjustment = temperatureAdjustmentKWhPer100km(for: temperature)
        let distanceAdjustment = applyDistanceAdjustment ? distanceAdjustmentKWhPer100km(for: distance) : 0

        let baseEstimateKWhPer100km = referenceConsumption
            + temperatureAdjustment
            + distanceAdjustment

        let roadTypeFactor = roadTypeProfile.consumptionFactor
        let customMotorwayBaselineFactor = customMotorwayBaselineFactor(
            roadTypeProfile: roadTypeProfile,
            usesCustomVehicleProfile: usesCustomVehicleProfile
        )
        let coldMotorwayFactor = coldMotorwayFactor(
            temperature: temperature,
            motorwayScalingFactor: roadTypeProfile.winterScalingFactor,
            usableBatteryKWh: usableBatteryKWh
        )
        let coldCityFactor = cityColdWeatherFactor(
            temperature: temperature,
            roadTypeProfile: roadTypeProfile
        )
        let motorwaySpeedFactor = scaledMotorwaySpeedFactor(
            speedSensitivity: motorwaySpeedSensitivityOverride ?? roadTypeProfile.motorwaySpeedScalingFactor,
            motorwaySpeed: motorwaySpeed,
            referenceConsumption: referenceConsumption,
            usableBatteryKWh: usableBatteryKWh
        )
        let roadSurfaceFactor = 1 + roadSurface.adjustment
        let windFactor = 1 + windCondition.adjustment * roadTypeProfile.windScalingFactor
        let rollingResistanceFactor = 1 + rollingResistanceClass.adjustment

        let adjustmentFactor = roadTypeFactor
            * customMotorwayBaselineFactor
            * coldMotorwayFactor
            * coldCityFactor
            * motorwaySpeedFactor
            * roadSurfaceFactor
            * windFactor
            * rollingResistanceFactor

        let calibratedKWhPer100km = baseEstimateKWhPer100km * adjustmentFactor
        let planningModeFactor = planningModeAdjustmentFactor(for: planningMode)
        let plannedKWhPer100km = calibratedKWhPer100km * planningModeFactor
        let airConditioningAdjustmentKWhPer100km = plannedKWhPer100km * airConditioningAdjustmentFactor(
            for: airConditioningMode,
            roadTypeProfile: roadTypeProfile,
            temperature: temperature
        )
        let finalKWhPer100km = max(0, plannedKWhPer100km + airConditioningAdjustmentKWhPer100km)
        let totalKWh = finalKWhPer100km * distance / 100
        let usableBatteryPercentageUsed = usableBatteryKWh > 0 ? totalKWh / usableBatteryKWh * 100 : 0
        let extraHighRange = roadSurface.addsExtraHighRange || windCondition.addsExtraHighRange ? 0.03 : 0

        return ForecastResult(
            referenceConsumptionKWhPer100km: referenceConsumption,
            baseEstimateKWhPer100km: baseEstimateKWhPer100km,
            adjustmentFactor: adjustmentFactor,
            calibratedKWhPer100km: calibratedKWhPer100km,
            finalKWhPer100km: finalKWhPer100km,
            totalKWh: totalKWh,
            likelyRangeLow: finalKWhPer100km * planningMode.lowRangeFactor,
            likelyRangeHigh: finalKWhPer100km * (planningMode.highRangeFactor + extraHighRange),
            usableBatteryPercentageUsed: usableBatteryPercentageUsed,
            temperatureAdjustmentKWhPer100km: temperatureAdjustment,
            distanceAdjustmentKWhPer100km: distanceAdjustment,
            roadTypeFactor: roadTypeFactor * customMotorwayBaselineFactor,
            coldMotorwayFactor: coldMotorwayFactor * coldCityFactor,
            motorwaySpeedFactor: motorwaySpeedFactor,
            roadSurfaceFactor: roadSurfaceFactor,
            windFactor: windFactor,
            rollingResistanceFactor: rollingResistanceFactor,
            planningModeFactor: planningModeFactor,
            airConditioningAdjustmentKWhPer100km: airConditioningAdjustmentKWhPer100km
        )
    }

    private nonisolated static func applyingMotorwaySpeedFactor(
        _ motorwaySpeedFactor: Double,
        to result: ForecastResult
    ) -> ForecastResult {
        let adjustedAdjustmentFactor = result.adjustmentFactor * motorwaySpeedFactor
        let adjustedCalibratedKWhPer100km = result.calibratedKWhPer100km * motorwaySpeedFactor
        let adjustedPlannedKWhPer100km = adjustedCalibratedKWhPer100km * result.planningModeFactor
        let airConditioningAdjustmentFactor = result.airConditioningAdjustmentFactor
        let adjustedAirConditioningAdjustmentKWhPer100km = adjustedPlannedKWhPer100km * airConditioningAdjustmentFactor
        let adjustedFinalKWhPer100km = max(
            0,
            adjustedPlannedKWhPer100km + adjustedAirConditioningAdjustmentKWhPer100km
        )
        let finalRatio = result.finalKWhPer100km > 0
            ? adjustedFinalKWhPer100km / result.finalKWhPer100km
            : 0

        return ForecastResult(
            referenceConsumptionKWhPer100km: result.referenceConsumptionKWhPer100km,
            baseEstimateKWhPer100km: result.baseEstimateKWhPer100km,
            adjustmentFactor: adjustedAdjustmentFactor,
            calibratedKWhPer100km: adjustedCalibratedKWhPer100km,
            finalKWhPer100km: adjustedFinalKWhPer100km,
            totalKWh: result.totalKWh * finalRatio,
            likelyRangeLow: result.likelyRangeLow * finalRatio,
            likelyRangeHigh: result.likelyRangeHigh * finalRatio,
            usableBatteryPercentageUsed: result.usableBatteryPercentageUsed * finalRatio,
            temperatureAdjustmentKWhPer100km: result.temperatureAdjustmentKWhPer100km,
            distanceAdjustmentKWhPer100km: result.distanceAdjustmentKWhPer100km,
            roadTypeFactor: result.roadTypeFactor,
            coldMotorwayFactor: result.coldMotorwayFactor,
            motorwaySpeedFactor: motorwaySpeedFactor,
            roadSurfaceFactor: result.roadSurfaceFactor,
            windFactor: result.windFactor,
            rollingResistanceFactor: result.rollingResistanceFactor,
            planningModeFactor: result.planningModeFactor,
            airConditioningAdjustmentKWhPer100km: adjustedAirConditioningAdjustmentKWhPer100km
        )
    }

    private nonisolated static func applyingAirConditioningAdjustment(
        to result: ForecastResult,
        roadTypeProfile: RoadTypeProfile,
        temperature: Double,
        airConditioningMode: AirConditioningMode
    ) -> ForecastResult {
        let plannedKWhPer100km = result.calibratedKWhPer100km * result.planningModeFactor
        let airConditioningAdjustmentKWhPer100km = plannedKWhPer100km * airConditioningAdjustmentFactor(
            for: airConditioningMode,
            roadTypeProfile: roadTypeProfile,
            temperature: temperature
        )
        let adjustedFinalKWhPer100km = max(0, plannedKWhPer100km + airConditioningAdjustmentKWhPer100km)
        let finalRatio = result.finalKWhPer100km > 0
            ? adjustedFinalKWhPer100km / result.finalKWhPer100km
            : 0

        return ForecastResult(
            referenceConsumptionKWhPer100km: result.referenceConsumptionKWhPer100km,
            baseEstimateKWhPer100km: result.baseEstimateKWhPer100km,
            adjustmentFactor: result.adjustmentFactor,
            calibratedKWhPer100km: result.calibratedKWhPer100km,
            finalKWhPer100km: adjustedFinalKWhPer100km,
            totalKWh: result.totalKWh * finalRatio,
            likelyRangeLow: result.likelyRangeLow * finalRatio,
            likelyRangeHigh: result.likelyRangeHigh * finalRatio,
            usableBatteryPercentageUsed: result.usableBatteryPercentageUsed * finalRatio,
            temperatureAdjustmentKWhPer100km: result.temperatureAdjustmentKWhPer100km,
            distanceAdjustmentKWhPer100km: result.distanceAdjustmentKWhPer100km,
            roadTypeFactor: result.roadTypeFactor,
            coldMotorwayFactor: result.coldMotorwayFactor,
            motorwaySpeedFactor: result.motorwaySpeedFactor,
            roadSurfaceFactor: result.roadSurfaceFactor,
            windFactor: result.windFactor,
            rollingResistanceFactor: result.rollingResistanceFactor,
            planningModeFactor: result.planningModeFactor,
            airConditioningAdjustmentKWhPer100km: airConditioningAdjustmentKWhPer100km
        )
    }

    private nonisolated static func blendedForecastResult(
        cityMixResult: ForecastResult,
        countrysideResult: ForecastResult,
        motorwayResult: ForecastResult
    ) -> ForecastResult {
        let cityMixWeight = 0.2
        let countrysideWeight = 0.2
        let motorwayWeight = 0.6

        func blend(_ cityMixValue: Double, _ countrysideValue: Double, _ motorwayValue: Double) -> Double {
            cityMixValue * cityMixWeight
                + countrysideValue * countrysideWeight
                + motorwayValue * motorwayWeight
        }

        return ForecastResult(
            referenceConsumptionKWhPer100km: blend(
                cityMixResult.referenceConsumptionKWhPer100km,
                countrysideResult.referenceConsumptionKWhPer100km,
                motorwayResult.referenceConsumptionKWhPer100km
            ),
            baseEstimateKWhPer100km: blend(
                cityMixResult.baseEstimateKWhPer100km,
                countrysideResult.baseEstimateKWhPer100km,
                motorwayResult.baseEstimateKWhPer100km
            ),
            adjustmentFactor: blend(
                cityMixResult.adjustmentFactor,
                countrysideResult.adjustmentFactor,
                motorwayResult.adjustmentFactor
            ),
            calibratedKWhPer100km: blend(
                cityMixResult.calibratedKWhPer100km,
                countrysideResult.calibratedKWhPer100km,
                motorwayResult.calibratedKWhPer100km
            ),
            finalKWhPer100km: blend(
                cityMixResult.finalKWhPer100km,
                countrysideResult.finalKWhPer100km,
                motorwayResult.finalKWhPer100km
            ),
            totalKWh: blend(cityMixResult.totalKWh, countrysideResult.totalKWh, motorwayResult.totalKWh),
            likelyRangeLow: blend(
                cityMixResult.likelyRangeLow,
                countrysideResult.likelyRangeLow,
                motorwayResult.likelyRangeLow
            ),
            likelyRangeHigh: blend(
                cityMixResult.likelyRangeHigh,
                countrysideResult.likelyRangeHigh,
                motorwayResult.likelyRangeHigh
            ),
            usableBatteryPercentageUsed: blend(
                cityMixResult.usableBatteryPercentageUsed,
                countrysideResult.usableBatteryPercentageUsed,
                motorwayResult.usableBatteryPercentageUsed
            ),
            temperatureAdjustmentKWhPer100km: blend(
                cityMixResult.temperatureAdjustmentKWhPer100km,
                countrysideResult.temperatureAdjustmentKWhPer100km,
                motorwayResult.temperatureAdjustmentKWhPer100km
            ),
            distanceAdjustmentKWhPer100km: blend(
                cityMixResult.distanceAdjustmentKWhPer100km,
                countrysideResult.distanceAdjustmentKWhPer100km,
                motorwayResult.distanceAdjustmentKWhPer100km
            ),
            roadTypeFactor: blend(cityMixResult.roadTypeFactor, countrysideResult.roadTypeFactor, motorwayResult.roadTypeFactor),
            coldMotorwayFactor: blend(
                cityMixResult.coldMotorwayFactor,
                countrysideResult.coldMotorwayFactor,
                motorwayResult.coldMotorwayFactor
            ),
            motorwaySpeedFactor: blend(
                cityMixResult.motorwaySpeedFactor,
                countrysideResult.motorwaySpeedFactor,
                motorwayResult.motorwaySpeedFactor
            ),
            roadSurfaceFactor: blend(
                cityMixResult.roadSurfaceFactor,
                countrysideResult.roadSurfaceFactor,
                motorwayResult.roadSurfaceFactor
            ),
            windFactor: blend(cityMixResult.windFactor, countrysideResult.windFactor, motorwayResult.windFactor),
            rollingResistanceFactor: blend(
                cityMixResult.rollingResistanceFactor,
                countrysideResult.rollingResistanceFactor,
                motorwayResult.rollingResistanceFactor
            ),
            planningModeFactor: blend(
                cityMixResult.planningModeFactor,
                countrysideResult.planningModeFactor,
                motorwayResult.planningModeFactor
            ),
            airConditioningAdjustmentKWhPer100km: blend(
                cityMixResult.airConditioningAdjustmentKWhPer100km,
                countrysideResult.airConditioningAdjustmentKWhPer100km,
                motorwayResult.airConditioningAdjustmentKWhPer100km
            )
        )
    }

    nonisolated static func temperatureAdjustmentKWhPer100km(for temperature: Double) -> Double {
        interpolatedTemperatureAdjustmentKWhPer100km(for: temperature)
    }

    nonisolated static func distanceAdjustmentKWhPer100km(for distance: Double) -> Double {
        switch distance {
        case 20...80:
            0.2
        default:
            0
        }
    }

    private nonisolated static func planningModeAdjustmentFactor(
        for planningMode: PlanningMode
    ) -> Double {
        planningMode.adjustmentFactor
    }

    private nonisolated static func customMotorwayBaselineFactor(
        roadTypeProfile: RoadTypeProfile,
        usesCustomVehicleProfile: Bool
    ) -> Double {
        guard usesCustomVehicleProfile, roadTypeProfile == .motorway else {
            return 1
        }

        return 1.03
    }

    nonisolated static func airConditioningAdjustmentFactor(
        for airConditioningMode: AirConditioningMode,
        roadTypeProfile: RoadTypeProfile,
        temperature: Double
    ) -> Double {
        guard airConditioningMode == .off else {
            return 0
        }

        let warmIntensity = min(1.0, max(0.0, (temperature - 18.0) / 12.0))
        let basePenalty: Double
        let additionalWarmPenalty: Double

        switch roadTypeProfile {
        case .cityMix:
            basePenalty = 0.020
            additionalWarmPenalty = 0.040
        case .countryside:
            basePenalty = 0.015
            additionalWarmPenalty = 0.030
        case .motorwayMix:
            basePenalty = 0.010
            additionalWarmPenalty = 0.020
        case .motorway:
            basePenalty = 0.005
            additionalWarmPenalty = 0.015
        }

        return -(basePenalty + warmIntensity * additionalWarmPenalty)
    }

    nonisolated static func motorwaySpeedFactor(
        roadTypeProfile: RoadTypeProfile,
        motorwaySpeed: Double,
        referenceConsumption: Double = defaultReferenceConsumptionKWhPer100Km,
        usableBatteryKWh: Double = nominalUsableBatteryKWh
    ) -> Double {
        scaledMotorwaySpeedFactor(
            speedSensitivity: roadTypeProfile.motorwaySpeedScalingFactor,
            motorwaySpeed: motorwaySpeed,
            referenceConsumption: referenceConsumption,
            usableBatteryKWh: usableBatteryKWh
        )
    }

    nonisolated static func motorwaySpeedSensitivityFactor(
        usableBatteryKWh: Double,
        referenceConsumption: Double = defaultReferenceConsumptionKWhPer100Km
    ) -> Double {
        let capacityDelta = max(0, usableBatteryKWh - nominalUsableBatteryKWh)
        let capacityFactor = max(0.85, 1.0 - capacityDelta * 0.003)
        let referenceRatio = referenceConsumption / defaultReferenceConsumptionKWhPer100Km
        let inefficiencyRestore = min(max((referenceRatio - 1.0) / 0.50, 0), 1)
        return capacityFactor + (1.0 - capacityFactor) * 0.50 * inefficiencyRestore
    }

    nonisolated static func coldMotorwayFactor(
        temperature: Double,
        motorwayScalingFactor: Double,
        usableBatteryKWh: Double = nominalUsableBatteryKWh
    ) -> Double {
        scaledColdMotorwayFactor(
            temperature: temperature,
            motorwayScalingFactor: motorwayScalingFactor,
            usableBatteryKWh: usableBatteryKWh
        )
    }

    private nonisolated static func cityColdWeatherFactor(
        temperature: Double,
        roadTypeProfile: RoadTypeProfile
    ) -> Double {
        guard roadTypeProfile == .cityMix, temperature < 0 else {
            return 1
        }

        let cappedCold = min(max(-temperature, 0), 20)
        return 1 + cappedCold / 20 * 0.06
    }
}

struct ForecastResult {
    let referenceConsumptionKWhPer100km: Double
    let baseEstimateKWhPer100km: Double
    let adjustmentFactor: Double
    let calibratedKWhPer100km: Double
    let finalKWhPer100km: Double
    let totalKWh: Double
    let likelyRangeLow: Double
    let likelyRangeHigh: Double
    let usableBatteryPercentageUsed: Double
    let temperatureAdjustmentKWhPer100km: Double
    let distanceAdjustmentKWhPer100km: Double
    let roadTypeFactor: Double
    let coldMotorwayFactor: Double
    let motorwaySpeedFactor: Double
    let roadSurfaceFactor: Double
    let windFactor: Double
    let rollingResistanceFactor: Double
    let planningModeFactor: Double
    let airConditioningAdjustmentKWhPer100km: Double

    nonisolated func applyingCalibrationFactor(_ factor: Double) -> ForecastResult {
        guard factor > 0, factor != 1 else {
            return self
        }

        let adjustedCalibratedKWhPer100km = calibratedKWhPer100km * factor
        let adjustedPlannedKWhPer100km = adjustedCalibratedKWhPer100km * planningModeFactor
        let adjustedAirConditioningAdjustmentKWhPer100km = adjustedPlannedKWhPer100km * airConditioningAdjustmentFactor
        let adjustedFinalKWhPer100km = max(
            0,
            adjustedPlannedKWhPer100km + adjustedAirConditioningAdjustmentKWhPer100km
        )
        let distanceFactor = finalKWhPer100km > 0 ? totalKWh / finalKWhPer100km : 0
        let lowRangeFactor = finalKWhPer100km > 0 ? likelyRangeLow / finalKWhPer100km : 0
        let highRangeFactor = finalKWhPer100km > 0 ? likelyRangeHigh / finalKWhPer100km : 0
        let batteryPercentageFactor = finalKWhPer100km > 0 ? usableBatteryPercentageUsed / finalKWhPer100km : 0

        return ForecastResult(
            referenceConsumptionKWhPer100km: referenceConsumptionKWhPer100km,
            baseEstimateKWhPer100km: baseEstimateKWhPer100km,
            adjustmentFactor: adjustmentFactor,
            calibratedKWhPer100km: adjustedCalibratedKWhPer100km,
            finalKWhPer100km: adjustedFinalKWhPer100km,
            totalKWh: adjustedFinalKWhPer100km * distanceFactor,
            likelyRangeLow: adjustedFinalKWhPer100km * lowRangeFactor,
            likelyRangeHigh: adjustedFinalKWhPer100km * highRangeFactor,
            usableBatteryPercentageUsed: adjustedFinalKWhPer100km * batteryPercentageFactor,
            temperatureAdjustmentKWhPer100km: temperatureAdjustmentKWhPer100km,
            distanceAdjustmentKWhPer100km: distanceAdjustmentKWhPer100km,
            roadTypeFactor: roadTypeFactor,
            coldMotorwayFactor: coldMotorwayFactor,
            motorwaySpeedFactor: motorwaySpeedFactor,
            roadSurfaceFactor: roadSurfaceFactor,
            windFactor: windFactor,
            rollingResistanceFactor: rollingResistanceFactor,
            planningModeFactor: planningModeFactor,
            airConditioningAdjustmentKWhPer100km: adjustedAirConditioningAdjustmentKWhPer100km
        )
    }

    fileprivate nonisolated var airConditioningAdjustmentFactor: Double {
        let plannedKWhPer100km = calibratedKWhPer100km * planningModeFactor
        guard plannedKWhPer100km > 0 else {
            return 0
        }

        return airConditioningAdjustmentKWhPer100km / plannedKWhPer100km
    }

    nonisolated func applyingFinalConsumptionAddition(_ additionalKWhPer100km: Double) -> ForecastResult {
        guard additionalKWhPer100km.isFinite, additionalKWhPer100km != 0 else {
            return self
        }

        let adjustedFinalKWhPer100km = max(0, finalKWhPer100km + additionalKWhPer100km)
        let distanceFactor = finalKWhPer100km > 0 ? totalKWh / finalKWhPer100km : 0
        let lowRangeFactor = finalKWhPer100km > 0 ? likelyRangeLow / finalKWhPer100km : 0
        let highRangeFactor = finalKWhPer100km > 0 ? likelyRangeHigh / finalKWhPer100km : 0
        let batteryPercentageFactor = finalKWhPer100km > 0 ? usableBatteryPercentageUsed / finalKWhPer100km : 0

        return ForecastResult(
            referenceConsumptionKWhPer100km: referenceConsumptionKWhPer100km,
            baseEstimateKWhPer100km: baseEstimateKWhPer100km,
            adjustmentFactor: adjustmentFactor,
            calibratedKWhPer100km: calibratedKWhPer100km,
            finalKWhPer100km: adjustedFinalKWhPer100km,
            totalKWh: adjustedFinalKWhPer100km * distanceFactor,
            likelyRangeLow: adjustedFinalKWhPer100km * lowRangeFactor,
            likelyRangeHigh: adjustedFinalKWhPer100km * highRangeFactor,
            usableBatteryPercentageUsed: adjustedFinalKWhPer100km * batteryPercentageFactor,
            temperatureAdjustmentKWhPer100km: temperatureAdjustmentKWhPer100km,
            distanceAdjustmentKWhPer100km: distanceAdjustmentKWhPer100km,
            roadTypeFactor: roadTypeFactor,
            coldMotorwayFactor: coldMotorwayFactor,
            motorwaySpeedFactor: motorwaySpeedFactor,
            roadSurfaceFactor: roadSurfaceFactor,
            windFactor: windFactor,
            rollingResistanceFactor: rollingResistanceFactor,
            planningModeFactor: planningModeFactor,
            airConditioningAdjustmentKWhPer100km: airConditioningAdjustmentKWhPer100km
        )
    }
}

struct ChargingWindow: Equatable {
    static let defaultMinimumPercent = 10.0
    static let defaultTargetPercent = 80.0
    static let defaultArrivalBatteryTargetPercent = 15.0
    static let arrivalBatteryTargetBounds = 5.0...30.0
    static let minimumBounds = 0.0...40.0
    static let targetBounds = 50.0...100.0
    static let normal = ChargingWindow(
        minimumPercent: defaultMinimumPercent,
        targetPercent: defaultTargetPercent
    )

    let minimumPercent: Double
    let targetPercent: Double

    init(minimumPercent: Double, targetPercent: Double) {
        let clampedMinimum = min(max(minimumPercent, Self.minimumBounds.lowerBound), Self.minimumBounds.upperBound)
        let clampedTarget = min(max(targetPercent, Self.targetBounds.lowerBound), Self.targetBounds.upperBound)

        if clampedMinimum < clampedTarget {
            self.minimumPercent = clampedMinimum
            self.targetPercent = clampedTarget
        } else {
            self.minimumPercent = min(clampedMinimum, clampedTarget - 1)
            self.targetPercent = max(clampedTarget, clampedMinimum + 1)
        }
    }

    var percentSpan: Double {
        max(0, targetPercent - minimumPercent)
    }

    var legLabel: String {
        "\(roundedPercent(targetPercent))-\(roundedPercent(minimumPercent))% leg"
    }

    var chargingLegDescription: String {
        "\(roundedPercent(targetPercent))-\(roundedPercent(minimumPercent))% charging legs"
    }

    func energyKWh(usableBatteryKWh: Double) -> Double {
        usableBatteryKWh * percentSpan / 100
    }

    private func roundedPercent(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0)))
    }
}

struct RemainingRangeEstimate {
    let availableEnergyKWh: Double
    let rangeKm: Double
}

struct BatteryPlan {
    let startBatteryPercent: Double
    let reserveBatteryPercent: Double
    let arrivalBatteryPercent: Double
    let needsCharging: Bool
    let chargingStops: Int
    let totalChargePercentNeeded: Double
    let estimatedChargingMinutes: Double
}

nonisolated func interpolatedTemperatureAdjustmentKWhPer100km(for temperature: Double) -> Double {
    let anchors: [(temperature: Double, adjustment: Double)] = [
        (-30, 2.4),
        (-20, 2.0),
        (-10, 1.4),
        (0, 0.8),
        (5, 0.3),
        (15, 0.0),
        (21, 0.0),
        (26, -0.35),
        (30, 0.05),
        (35, 0.4),
        (40, 0.7)
    ]

    guard let firstAnchor = anchors.first, let lastAnchor = anchors.last else {
        return 0
    }

    if temperature <= firstAnchor.temperature {
        return firstAnchor.adjustment
    }

    if temperature >= lastAnchor.temperature {
        return lastAnchor.adjustment
    }

    guard let upperIndex = anchors.firstIndex(where: { temperature <= $0.temperature }) else {
        return lastAnchor.adjustment
    }

    let lowerAnchor = anchors[upperIndex - 1]
    let upperAnchor = anchors[upperIndex]
    let progress = (temperature - lowerAnchor.temperature) / (upperAnchor.temperature - lowerAnchor.temperature)
    return lowerAnchor.adjustment + (upperAnchor.adjustment - lowerAnchor.adjustment) * progress
}

nonisolated func scaledColdMotorwayFactor(
    temperature: Double,
    motorwayScalingFactor: Double,
    usableBatteryKWh: Double = MiniConsumptionCalculator.nominalUsableBatteryKWh
) -> Double {
    guard motorwayScalingFactor > 0, temperature < 5 else {
        return 1
    }

    let cappedTemperature = max(temperature, -20)
    let fullMotorwayIncrease: Double

    if cappedTemperature >= 0 {
        fullMotorwayIncrease = (5 - cappedTemperature) / 5 * 0.02
    } else if cappedTemperature >= -10 {
        fullMotorwayIncrease = 0.02 + (-cappedTemperature / 10) * 0.04
    } else {
        fullMotorwayIncrease = 0.06 + ((-10 - cappedTemperature) / 10) * 0.03
    }

    let currentColdFactor = 1 + fullMotorwayIncrease * motorwayScalingFactor
    let profileBlend = min(
        max((usableBatteryKWh - MiniConsumptionCalculator.nominalUsableBatteryKWh) / 45.0, 0),
        1
    )
    let coldSeverity = min(max(fullMotorwayIncrease / 0.06, 0), 1)
    let vehicleColdBoost = 1 + profileBlend * motorwayScalingFactor * coldSeverity * 0.10
    return currentColdFactor * vehicleColdBoost
}

nonisolated func scaledMotorwaySpeedFactor(
    speedSensitivity: Double,
    motorwaySpeed: Double,
    referenceConsumption: Double = defaultReferenceConsumptionKWhPer100Km,
    usableBatteryKWh: Double = MiniConsumptionCalculator.nominalUsableBatteryKWh
) -> Double {
    guard speedSensitivity > 0 else {
        return 1
    }

    let speed = min(max(motorwaySpeed, 90), 150)
    let lowSpeedProgress = (speed - 90) / 60
    let post105Progress = max(speed - 105, 0) / 45
    let post120Progress = max(speed - 120, 0) / 30
    let baseIncrease = 0.20 * pow(lowSpeedProgress, 1.10)
    let post105Increase = 0.30 * pow(post105Progress, 1.55)
    let post120Increase = 0.22 * pow(post120Progress, 2.20)
    let speedIncrease = baseIncrease + post105Increase + post120Increase
    let capacityFactor = MiniConsumptionCalculator.motorwaySpeedSensitivityFactor(
        usableBatteryKWh: usableBatteryKWh,
        referenceConsumption: referenceConsumption
    )
    return 1 + speedSensitivity * capacityFactor * speedIncrease
}
