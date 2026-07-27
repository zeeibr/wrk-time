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

    /// One sentence, in the app's voice, naming the reason. Shown on Today so
    /// an adjustment never arrives unexplained.
    var explanation: String {
        switch guidance {
        case .ease:
            "Sleep and heart rate are both off your usual. Today drops a round — that is the plan working, not you failing."
        case .push:
            "You slept well and your variability is up. Today adds a round if you want it."
        case .hold:
            "Nothing unusual in last night's numbers. The plan stands."
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
