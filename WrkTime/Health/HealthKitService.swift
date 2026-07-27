import Foundation
import HealthKit

/// The real thing.
///
/// Everything the app reads is written by something else: the Loftilla scale
/// writes body mass through its own app, Whoop writes sleep, HRV and heart
/// rate. We only read, and we only write completed workouts back.
final class HealthKitService: HealthService, @unchecked Sendable {
    private let store = HKHealthStore()

    private var readTypes: Set<HKObjectType> {
        var types: Set<HKObjectType> = []
        if let bodyMass = HKQuantityType.quantityType(forIdentifier: .bodyMass) { types.insert(bodyMass) }
        if let hrv = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN) { types.insert(hrv) }
        if let resting = HKQuantityType.quantityType(forIdentifier: .restingHeartRate) { types.insert(resting) }
        if let heartRate = HKQuantityType.quantityType(forIdentifier: .heartRate) { types.insert(heartRate) }
        types.insert(HKCategoryType.categoryType(forIdentifier: .sleepAnalysis)!)
        return types
    }

    private var writeTypes: Set<HKSampleType> {
        var types: Set<HKSampleType> = [HKWorkoutType.workoutType()]
        if let energy = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) { types.insert(energy) }
        return types
    }

    func requestAuthorization() async -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else { return false }
        do {
            try await store.requestAuthorization(toShare: writeTypes, read: readTypes)
            return true
        } catch {
            // A thrown error here means the request could not be presented, not
            // that the user said no. Either way the app carries on without it.
            return false
        }
    }

    // MARK: - Reads

    func weights(since: Date) async -> [WeightReading] {
        guard let type = HKQuantityType.quantityType(forIdentifier: .bodyMass) else { return [] }
        let samples = await quantitySamples(type: type, since: since)
        return samples.map {
            WeightReading(date: $0.startDate,
                          pounds: $0.quantity.doubleValue(for: .pound()))
        }
    }

    func heartRateVariability(since: Date) async -> [DatedValue] {
        guard let type = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN) else { return [] }
        let unit = HKUnit.secondUnit(with: .milli)
        return await quantitySamples(type: type, since: since).map {
            DatedValue(date: $0.startDate, value: $0.quantity.doubleValue(for: unit))
        }
    }

    func restingHeartRate(since: Date) async -> [DatedValue] {
        guard let type = HKQuantityType.quantityType(forIdentifier: .restingHeartRate) else { return [] }
        let unit = HKUnit.count().unitDivided(by: .minute())
        return await quantitySamples(type: type, since: since).map {
            DatedValue(date: $0.startDate, value: $0.quantity.doubleValue(for: unit))
        }
    }

    /// Sleep is stored as many category samples per night, so they are summed
    /// per calendar day. Only *asleep* states count — time in bed awake is not
    /// sleep, and treating it as such would flatter the numbers.
    func sleepDurations(since: Date) async -> [DatedValue] {
        guard let type = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) else { return [] }
        let samples: [HKCategorySample] = await withCheckedContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(withStart: since, end: nil)
            let query = HKSampleQuery(sampleType: type, predicate: predicate,
                                      limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, results, _ in
                continuation.resume(returning: (results as? [HKCategorySample]) ?? [])
            }
            store.execute(query)
        }

        let asleep: Set<Int> = [
            HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
            HKCategoryValueSleepAnalysis.asleepCore.rawValue,
            HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
            HKCategoryValueSleepAnalysis.asleepREM.rawValue
        ]

        var byNight: [Date: TimeInterval] = [:]
        let calendar = Calendar.current
        for sample in samples where asleep.contains(sample.value) {
            // A night belongs to the day it ends on, so a 23:40 bedtime and a
            // 00:20 one land in the same night rather than either side of it.
            let night = calendar.startOfDay(for: sample.endDate)
            byNight[night, default: 0] += sample.endDate.timeIntervalSince(sample.startDate)
        }

        return byNight
            .map { DatedValue(date: $0.key, value: $0.value / 3600) }
            .sorted { $0.date > $1.date }
    }

    private func quantitySamples(type: HKQuantityType, since: Date) async -> [HKQuantitySample] {
        await withCheckedContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(withStart: since, end: nil)
            let sort = [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]
            let query = HKSampleQuery(sampleType: type, predicate: predicate,
                                      limit: HKObjectQueryNoLimit, sortDescriptors: sort) { _, results, _ in
                continuation.resume(returning: (results as? [HKQuantitySample]) ?? [])
            }
            store.execute(query)
        }
    }

    // MARK: - Writes

    func saveWorkout(start: Date, end: Date, activeEnergyKilocalories: Double?) async throws {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .functionalStrengthTraining
        configuration.locationType = .indoor

        let builder = HKWorkoutBuilder(healthStore: store, configuration: configuration, device: .local())
        try await builder.beginCollection(at: start)

        if let kilocalories = activeEnergyKilocalories,
           let energyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) {
            let sample = HKQuantitySample(
                type: energyType,
                quantity: HKQuantity(unit: .kilocalorie(), doubleValue: kilocalories),
                start: start,
                end: end
            )
            try await builder.addSamples([sample])
        }

        try await builder.endCollection(at: end)
        _ = try await builder.finishWorkout()
    }

    // MARK: - Snapshot

    /// Latest values against a fourteen-day baseline, which is the shortest
    /// window that is not dominated by a single bad night.
    func recoverySnapshot() async -> RecoverySnapshot {
        let since = Calendar.current.date(byAdding: .day, value: -14, to: .now) ?? .now
        async let sleep = sleepDurations(since: since)
        async let hrv = heartRateVariability(since: since)
        async let resting = restingHeartRate(since: since)

        let (sleepValues, hrvValues, restingValues) = await (sleep, hrv, resting)

        return RecoverySnapshot(
            sleepHours: sleepValues.first?.value,
            hrv: hrvValues.first?.value,
            restingHeartRate: restingValues.first?.value,
            hrvBaseline: Self.mean(hrvValues.dropFirst().map(\.value)),
            restingHeartRateBaseline: Self.mean(restingValues.dropFirst().map(\.value))
        )
    }

    private static func mean(_ values: some Collection<Double>) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }
}
