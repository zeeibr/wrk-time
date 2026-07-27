import Testing
import Foundation
@testable import WrkTime

private func entries(_ poundsByDaysAgo: [(Int, Double)]) -> [WeightEntry] {
    poundsByDaysAgo.map { daysAgo, pounds in
        WeightEntry(
            date: Calendar.current.date(byAdding: .day, value: -daysAgo, to: .now)!,
            pounds: pounds,
            source: .health
        )
    }
}

@Suite("Weight trend")
struct WeightTrendTests {

    @Test("Reports a seven-day mean, not the last reading")
    func mean() {
        // A noisy week around 170 with a low outlier this morning.
        let trend = WeightTrend(entries: entries([
            (0, 167.0), (1, 170.5), (2, 170.0), (3, 170.5), (4, 171.0), (5, 170.5), (6, 170.5)
        ]))
        let mean = try! #require(trend.sevenDayMean)
        #expect(mean > 169.5 && mean < 170.5, "one light morning must not move the headline number")
    }

    @Test("Weekly rate compares this week's mean against last week's")
    func rate() {
        var readings: [(Int, Double)] = []
        for day in 0..<7 { readings.append((day, 168.0)) }
        for day in 7..<14 { readings.append((day, 170.0)) }
        let rate = try! #require(WeightTrend(entries: entries(readings)).weeklyRate)
        #expect(abs(rate - (-2.0)) < 0.001)
    }

    @Test("Projects a goal date only when the trend is actually going there")
    func projection() {
        var losing: [(Int, Double)] = []
        for day in 0..<7 { losing.append((day, 168.0)) }
        for day in 7..<14 { losing.append((day, 169.0)) }
        let projected = WeightTrend(entries: entries(losing)).projectedDate(toGoal: 148)
        #expect(projected != nil)
        if let projected { #expect(projected > .now) }
    }

    @Test("Refuses to project from a flat or rising trend")
    func noFalseProjection() {
        var flat: [(Int, Double)] = []
        for day in 0..<14 { flat.append((day, 168.0)) }
        #expect(WeightTrend(entries: entries(flat)).projectedDate(toGoal: 148) == nil)

        var gaining: [(Int, Double)] = []
        for day in 0..<7 { gaining.append((day, 170.0)) }
        for day in 7..<14 { gaining.append((day, 168.0)) }
        #expect(WeightTrend(entries: entries(gaining)).projectedDate(toGoal: 148) == nil)
    }

    @Test("Refuses to project when the goal is already met")
    func goalMet() {
        var losing: [(Int, Double)] = []
        for day in 0..<7 { losing.append((day, 146.0)) }
        for day in 7..<14 { losing.append((day, 148.0)) }
        #expect(WeightTrend(entries: entries(losing)).projectedDate(toGoal: 148) == nil)
    }

    @Test("Copes with an empty history rather than guessing")
    func empty() {
        let trend = WeightTrend(entries: [])
        #expect(trend.sevenDayMean == nil)
        #expect(trend.weeklyRate == nil)
        #expect(trend.projectedDate(toGoal: 148) == nil)
    }
}

@Suite("Recovery guidance")
struct RecoveryTests {

    @Test("Two signals down means ease off")
    func ease() {
        let snapshot = RecoverySnapshot(
            sleepHours: 5.5, hrv: 50, restingHeartRate: 58,
            hrvBaseline: 64, restingHeartRateBaseline: 58
        )
        #expect(snapshot.guidance == .ease)
    }

    @Test("Slept well with variability up means you may push")
    func push() {
        let snapshot = RecoverySnapshot(
            sleepHours: 7.6, hrv: 70, restingHeartRate: 56,
            hrvBaseline: 64, restingHeartRateBaseline: 58
        )
        #expect(snapshot.guidance == .push)
    }

    @Test("One signal off is not enough to change the plan")
    func hold() {
        let snapshot = RecoverySnapshot(
            sleepHours: 6.0, hrv: 64, restingHeartRate: 58,
            hrvBaseline: 64, restingHeartRateBaseline: 58
        )
        #expect(snapshot.guidance == .hold)
    }

    @Test("Missing data holds the plan rather than inventing a reason to change it")
    func missing() {
        #expect(RecoverySnapshot().guidance == .hold)
        #expect(RecoverySnapshot(sleepHours: 8).guidance == .hold)
    }
}
