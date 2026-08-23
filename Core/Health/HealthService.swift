import Foundation

/// What the app needs from Health, stated as a protocol so the planner and the
/// projection can be tested without a device, a Health store, or a scale.
protocol HealthService: Sendable {
    /// Ask for read access. Returns false if the user declines or Health is
    /// unavailable — never throws for a refusal, because a refusal is a normal
    /// outcome and the app has to keep working after one.
    func requestAuthorization() async -> Bool

    /// Body mass readings, newest first. Loftilla writes these via its own app.
    func weights(since: Date) async -> [WeightReading]

    /// Nightly sleep duration, newest first. Whoop writes these.
    func sleepDurations(since: Date) async -> [DatedValue]

    /// Heart rate variability (SDNN, ms), newest first. Whoop writes these.
    func heartRateVariability(since: Date) async -> [DatedValue]

    /// Resting heart rate (bpm), newest first.
    func restingHeartRate(since: Date) async -> [DatedValue]

    /// Walks recorded by something else — Whoop, the Watch, the iPhone.
    ///
    /// Context for the planner, not marks on the growth form: a mark is a
    /// finished *planned session*, and a walk Whoop logged is not one. It tells
    /// the plan you moved, which is a different fact and a useful one.
    ///
    /// Excludes anything this app wrote, or the app's own sessions would come
    /// back as evidence of extra activity it already knows about.
    func walks(since: Date) async -> [RecordedWalk]

    /// Record a finished session so it counts toward the Activity rings.
    func saveWorkout(start: Date, end: Date, activeEnergyKilocalories: Double?) async throws
}

struct WeightReading: Equatable, Sendable {
    let date: Date
    let pounds: Double
}

struct DatedValue: Equatable, Sendable {
    let date: Date
    let value: Double
}

/// A walk somebody else logged.
struct RecordedWalk: Equatable, Sendable {
    let date: Date
    let minutes: Double
    /// What wrote it — "Whoop", "Apple Watch". Shown, never guessed at.
    let source: String
}

// MARK: - Recovery

/// The signals the planner actually acts on, reduced to something small enough
/// to reason about.
struct RecoverySnapshot: Equatable, Sendable {
    var sleepHours: Double?
    var hrv: Double?
    var restingHeartRate: Double?

    /// Compared against the trailing baseline, not against a population norm —
    /// what matters is whether *you* are down on *yourself*.
    var hrvBaseline: Double?
    var restingHeartRateBaseline: Double?

    /// How the planner should treat today. Deliberately three coarse states:
    /// a continuous "recovery score" would imply a precision this data does not
    /// have, and would invite the app to make claims it cannot support.
    enum Guidance: Equatable { case hold, ease, push }

    var guidance: Guidance {
        var strikes = 0
        if let sleepHours, sleepHours < 6.5 { strikes += 1 }
        if let hrv, let hrvBaseline, hrv < hrvBaseline * 0.9 { strikes += 1 }
        if let restingHeartRate, let restingHeartRateBaseline,
           restingHeartRate > restingHeartRateBaseline + 5 { strikes += 1 }

        if strikes >= 2 { return .ease }

        let sleptWell = (sleepHours ?? 0) >= 7
        let hrvUp = if let hrv, let hrvBaseline { hrv > hrvBaseline * 1.05 } else { false }
        if strikes == 0, sleptWell, hrvUp { return .push }

        return .hold
    }

    /// One sentence, in the app's voice, naming what the numbers say.
    ///
    /// It used to say "Today drops a round" and "Today adds a round" — and
    /// neither happens. `PlanContext` carries no sleep, variability or heart
    /// rate; `PlanTrigger` never consults recovery; there is no control that
    /// adds or removes a round. The app was describing an adaptation it does
    /// not perform, on the screen whose whole claim is that every number here
    /// is paired with a consequence.
    ///
    /// So it reports the reading and leaves the decision where it actually
    /// lives — with her. When recovery genuinely reaches the planner, this is
    /// the string that gets to promise something again.
    ///
    /// Nil when there is nothing to report. A snapshot with every field empty
    /// falls to `.hold`, which used to render "Nothing unusual in last night's
    /// numbers" above three em dashes and four lines above "Nothing came
    /// through from Health" — the screen asserting knowledge of a night it had
    /// no reading for, and contradicting itself in the same breath.
    var explanation: String? {
        guard sleepHours != nil || hrv != nil || restingHeartRate != nil else { return nil }
        return switch guidance {
        case .ease:
            "Sleep and heart rate are both off your usual. Nothing changes on its own — take a round off if today asks for it."
        case .push:
            "You slept well and your variability is up. Today is written as it was; there is room in it if you want more."
        case .hold:
            "Nothing unusual in last night's numbers. The plan stands as written."
        }
    }
}

// MARK: - Stub

/// Used in previews, tests, and on a device where the user declined Health.
/// Returning plausible data rather than nothing keeps previews honest about
/// what a populated screen looks like.
struct StubHealthService: HealthService {
    var authorized = true
    var readings: [WeightReading] = StubHealthService.sampleWeights

    func requestAuthorization() async -> Bool { authorized }

    func weights(since: Date) async -> [WeightReading] {
        readings.filter { $0.date >= since }
    }

    func sleepDurations(since: Date) async -> [DatedValue] {
        Self.series(from: since, base: 7.2, spread: 0.8)
    }

    func walks(since: Date) async -> [RecordedWalk] {
        Self.series(from: since, base: 32, spread: 12)
            .prefix(4)
            .map { RecordedWalk(date: $0.date, minutes: $0.value, source: "Whoop") }
    }

    func heartRateVariability(since: Date) async -> [DatedValue] {
        Self.series(from: since, base: 64, spread: 7)
    }

    func restingHeartRate(since: Date) async -> [DatedValue] {
        Self.series(from: since, base: 58, spread: 3)
    }

    func saveWorkout(start: Date, end: Date, activeEnergyKilocalories: Double?) async throws {}

    static let sampleWeights: [WeightReading] = {
        (0..<28).map { day in
            WeightReading(
                date: Calendar.current.date(byAdding: .day, value: -day, to: .now) ?? .now,
                // A real trend: downward, but noisy enough to be believable.
                pounds: 168.4 + Double(day) * 0.11 + sin(Double(day) * 1.7) * 0.4
            )
        }
    }()

    private static func series(from: Date, base: Double, spread: Double) -> [DatedValue] {
        (0..<14).map { day in
            DatedValue(
                date: Calendar.current.date(byAdding: .day, value: -day, to: .now) ?? .now,
                value: base + sin(Double(day) * 1.3) * spread
            )
        }
    }
}
