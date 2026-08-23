import Foundation
import HealthKit
import Observation

/// The workout session on the wrist: the thing that keeps the app alive with
/// the screen off, and the thing that records the heart rate.
///
/// # THE OWNER WRITES HEALTH
///
/// `finishWorkout()` below writes an `HKWorkout`. That is the whole reason the
/// phone's `HealthSync.record` must **not** also write one for a session the
/// watch started: two writers would put the same session into Health twice,
/// and a doubled workout is a doubled walk all over again — except this time
/// `RecordedWalk.deduplicated` is not there to catch it, because a strength
/// session is never read back.
///
/// The rule is the same one the record follows: the device that started the
/// session owns it, and the owner writes. This class is one half of that; the
/// other half is the phone declining to write for a watch-owned session, wired
/// at integration. What this class owes that arrangement is exactly one
/// workout per `end(at:)`, which is why `end` takes the session away from
/// itself before it does anything asynchronous — a second call finds nothing
/// to finish rather than finishing it again.
///
/// # Failure is quiet
///
/// A watch simulator without a paired phone, a user who declined Health, a
/// store that throws: none of them stop the timer. Every throw is caught and
/// the session simply has no workout and no heart rate. The count on the wrist
/// is the app's job; Health is a record it keeps when it can.
@Observable
@MainActor
final class WatchWorkout {
    /// The latest heart rate the builder has collected, in beats per minute.
    /// Nil until the first sample lands — and it stays nil for a whole session
    /// if Health is unavailable, which the view must be able to show.
    private(set) var heartRate: Double?

    /// Whether a session is currently collecting. False after `end(at:)`, and
    /// false the whole time if starting one failed.
    private(set) var isRunning = false

    private let store = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    /// Held strongly: HealthKit's delegates are weak, and a collector that
    /// deallocates is a session that silently stops reporting.
    private var collector: Collector?

    init() {}

    // MARK: - Authorization

    /// Ask once, for everything the wrist needs.
    ///
    /// Asked by the app rather than by `start(at:)`, so the permission sheet
    /// never lands on top of a running count. The share list is what the live
    /// data source actually writes into the workout — the workout itself, the
    /// energy and the heart rate it collects — and the read list matches what
    /// the phone's `HealthKitService` reads where the watch has any use for it.
    ///
    /// Returns false for a refusal or for no Health at all; both are normal and
    /// neither is an error worth throwing.
    static func requestAuthorization() async -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else { return false }

        var share: Set<HKSampleType> = [HKWorkoutType.workoutType()]
        if let energy = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) { share.insert(energy) }
        if let heartRate = HKQuantityType.quantityType(forIdentifier: .heartRate) { share.insert(heartRate) }

        var read: Set<HKObjectType> = [HKWorkoutType.workoutType()]
        if let heartRate = HKQuantityType.quantityType(forIdentifier: .heartRate) { read.insert(heartRate) }
        if let energy = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) { read.insert(energy) }
        if let resting = HKQuantityType.quantityType(forIdentifier: .restingHeartRate) { read.insert(resting) }

        do {
            try await HKHealthStore().requestAuthorization(toShare: share, read: read)
            return true
        } catch {
            // A throw here means the sheet could not be presented, not that she
            // said no. Either way the wrist carries on without it.
            return false
        }
    }

    // MARK: - The session

    /// Begin a workout session and start collecting.
    ///
    /// Requests nothing itself — authorization is the app's job, above. Called
    /// when the engine starts, with the engine's own start date so the workout
    /// and the record agree about when the session began.
    func start(at date: Date = .now) async {
        guard HKHealthStore.isHealthDataAvailable(), session == nil else { return }

        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .traditionalStrengthTraining
        configuration.locationType = .indoor

        do {
            let session = try HKWorkoutSession(healthStore: store, configuration: configuration)
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: store,
                                                         workoutConfiguration: configuration)

            let collector = Collector(owner: self)
            session.delegate = collector
            builder.delegate = collector

            self.session = session
            self.builder = builder
            self.collector = collector
            heartRate = nil

            session.startActivity(with: date)
            try await builder.beginCollection(at: date)
            isRunning = true
        } catch {
            // No session, no workout, no heart rate — and a timer that runs.
            clear()
        }
    }

    /// End the session and write the workout. Exactly one, or none.
    ///
    /// The session and builder are taken off this object *before* the first
    /// `await`, so a second `end` — a stop button pressed twice, an `onEnded`
    /// that fires alongside a scene going away — has nothing left to finish.
    func end(at date: Date = .now) async {
        guard let session, let builder else { return }
        self.session = nil
        self.builder = nil
        isRunning = false

        session.end()
        do {
            try await builder.endCollection(at: date)
            _ = try await builder.finishWorkout()
        } catch {
            // The session still happened; Health just has no row for it. The
            // record the app keeps is written by the engine either way.
        }
        // The collector outlives the awaits above so a late sample is not sent
        // to a deallocated delegate; it goes now that there is nothing left.
        collector = nil
    }

    /// The last heart rate stays readable after the session ends — the finish
    /// screen is the one place it is worth reading twice.
    private func clear() {
        session = nil
        builder = nil
        collector = nil
        isRunning = false
    }

    fileprivate func report(heartRate value: Double) {
        heartRate = value
    }

    /// Called when the session fails or stops from underneath us — a watch
    /// that ran out of battery for the sensor, Health revoked mid-session.
    /// Nothing is written; the timer keeps counting.
    fileprivate func fail() {
        clear()
    }

    // MARK: - Delegate

    /// HealthKit calls its delegates off the main actor, so the delegate is a
    /// plain object that reads what it needs where it is called and hops with a
    /// `Double`. Nothing non-`Sendable` crosses.
    private final class Collector: NSObject, HKLiveWorkoutBuilderDelegate,
                                   HKWorkoutSessionDelegate, @unchecked Sendable {
        private weak var owner: WatchWorkout?
        private let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate)
        private let unit = HKUnit.count().unitDivided(by: .minute())

        init(owner: WatchWorkout) {
            self.owner = owner
        }

        func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder,
                            didCollectDataOf collectedTypes: Set<HKSampleType>) {
            guard let heartRateType, collectedTypes.contains(heartRateType) else { return }
            // Read on this thread; send only the number.
            guard let value = workoutBuilder.statistics(for: heartRateType)?
                .mostRecentQuantity()?
                .doubleValue(for: unit) else { return }
            let owner = owner
            Task { @MainActor in owner?.report(heartRate: value) }
        }

        func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {
            // Pauses and laps; the engine is the clock, so there is nothing to do.
        }

        func workoutSession(_ workoutSession: HKWorkoutSession,
                            didChangeTo toState: HKWorkoutSessionState,
                            from fromState: HKWorkoutSessionState,
                            date: Date) {
            // `end(at:)` drives the ending; a state change is not a second path
            // into writing a workout, deliberately.
        }

        func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
            let owner = owner
            Task { @MainActor in owner?.fail() }
        }
    }
}
