import Foundation
import SwiftData

/// Pulls Health readings into the local store.
///
/// The app keeps its own copy rather than querying Health on every render: the
/// watch app and the projection both need this data, and a SwiftData store
/// syncs through CloudKit where a HealthKit query does not.
@MainActor
final class HealthSync {
    private let health: any HealthService
    private let context: ModelContext

    init(health: any HealthService, context: ModelContext) {
        self.health = health
        self.context = context
    }

    /// Import anything new since the last reading we hold. Safe to call on
    /// every launch — readings are matched on their timestamp, so a repeated
    /// import cannot duplicate a weigh-in.
    func importWeights() async {
        guard await health.requestAuthorization() else { return }

        let existing = (try? context.fetch(FetchDescriptor<WeightEntry>())) ?? []
        let latest = existing.map(\.date).max()
        let since = latest ?? Calendar.current.date(byAdding: .day, value: -90, to: .now) ?? .now

        let known = Set(existing.map(\.date))
        for reading in await health.weights(since: since) where !known.contains(reading.date) {
            context.insert(WeightEntry(date: reading.date, pounds: reading.pounds, source: .health))
        }

        try? context.save()
    }

    /// Write a finished session back so it counts toward the Activity rings.
    func record(session: PlannedSession, start: Date, end: Date) async {
        session.completedAt = end
        try? context.save()
        try? await health.saveWorkout(start: start, end: end, activeEnergyKilocalories: nil)
    }
}

// MARK: - Trend

/// Weight, reduced to the two numbers the app actually shows and the one it
/// projects from.
struct WeightTrend {
    let entries: [WeightEntry]

    var latest: WeightEntry? {
        entries.max { $0.date < $1.date }
    }

    /// A seven-day mean, not the last reading. Day-to-day weight is mostly
    /// water, and showing the raw number as if it were progress is the single
    /// most demoralising thing a weight tracker can do.
    var sevenDayMean: Double? {
        mean(overDays: 7)
    }

    /// Pounds per week, from the difference between the last two weekly means.
    /// Negative means losing.
    var weeklyRate: Double? {
        guard let recent = mean(overDays: 7, endingDaysAgo: 0),
              let prior = mean(overDays: 7, endingDaysAgo: 7) else { return nil }
        return recent - prior
    }

    /// When the current rate would reach the goal. Nil when the trend is flat
    /// or going the wrong way — projecting a date from a rate that isn't
    /// happening would be a lie told with arithmetic.
    func projectedDate(toGoal goal: Double) -> Date? {
        guard let current = sevenDayMean, let rate = weeklyRate, rate < -0.05 else { return nil }
        let poundsToGo = current - goal
        guard poundsToGo > 0 else { return nil }
        let weeks = poundsToGo / -rate
        return Calendar.current.date(byAdding: .day, value: Int(weeks * 7), to: .now)
    }

    private func mean(overDays days: Int, endingDaysAgo offset: Int = 0) -> Double? {
        let calendar = Calendar.current
        guard let end = calendar.date(byAdding: .day, value: -offset, to: .now),
              let start = calendar.date(byAdding: .day, value: -days, to: end) else { return nil }
        let window = entries.filter { $0.date > start && $0.date <= end }
        guard !window.isEmpty else { return nil }
        return window.map(\.pounds).reduce(0, +) / Double(window.count)
    }
}
