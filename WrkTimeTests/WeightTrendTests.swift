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

// MARK: - Scrubbing the chart

@Suite("The chart under a finger")
struct ProjectionPlotTests {

    /// Four readings a few days apart, oldest first — the order the chart
    /// plots them in.
    private var readings: [WeightEntry] {
        entries([(12, 170.2), (8, 169.6), (5, 169.1), (0, 168.4)])
            .sorted { $0.date < $1.date }
    }

    private var plot: ProjectionPlot {
        ProjectionPlot(size: CGSize(width: 340, height: 168),
                       readings: readings, goal: 0, projection: nil)
    }

    @Test("A finger on a reading picks that reading")
    func exact() {
        let plot = self.plot
        for (index, point) in plot.points.enumerated() {
            #expect(plot.nearestIndex(toX: point.x) == index)
        }
    }

    @Test("Between two readings it picks the nearer, not the earlier")
    func between() {
        let plot = self.plot
        let a = plot.points[1].x
        let b = plot.points[2].x
        #expect(plot.nearestIndex(toX: a + (b - a) * 0.2) == 1)
        #expect(plot.nearestIndex(toX: a + (b - a) * 0.8) == 2)
    }

    @Test("Past either end it holds at the end reading rather than losing the finger")
    func offTheEnds() {
        let plot = self.plot
        // Dragging off the canvas is a normal thing a finger does; the readout
        // must not blank out at the edges.
        #expect(plot.nearestIndex(toX: -400) == 0)
        #expect(plot.nearestIndex(toX: 9_000) == plot.points.count - 1)
    }

    @Test("With nothing plotted there is nothing to pick")
    func empty() {
        let bare = ProjectionPlot(size: CGSize(width: 340, height: 168),
                                  readings: [], goal: 0, projection: nil)
        #expect(bare.nearestIndex(toX: 100) == nil)
    }
}

// MARK: - Where the ticks sit

@Suite("Ticks follow the session they came after")
struct TickPositionTests {

    private func day(_ d: Int, hour: Int) -> Date {
        Calendar.current.date(byAdding: .hour, value: d * 24 + hour,
                              to: Calendar.current.startOfDay(for: .now))!
    }

    @Test("An extra sits just past the session it followed")
    func followsItsSession() {
        // Sessions Mon and Wed; the extra came Tuesday, after session one.
        let positions = GrowthForm.tickPositions(
            sessions: [day(0, hour: 9), day(2, hour: 9)],
            extras: [day(1, hour: 18)])
        #expect(positions.count == 1)
        // Past dot 0 (position 0), before dot 1 (position 1).
        #expect(positions[0] > 0 && positions[0] < 1)
    }

    @Test("Same-day extras cluster closer than different days")
    func sameDayClosest() {
        let sessions = [day(0, hour: 9)]
        // Two extras Monday evening, one Wednesday — all after session one.
        let positions = GrowthForm.tickPositions(
            sessions: sessions,
            extras: [day(0, hour: 18), day(0, hour: 20), day(2, hour: 18)])
        let sameDayGap = positions[1] - positions[0]
        let crossDayGap = positions[2] - positions[1]
        #expect(sameDayGap > 0)
        #expect(crossDayGap > sameDayGap, "a new day steps wider than the same day")
    }

    @Test("An extra before any session hangs ahead of the first dot")
    func beforeTheWeekStarts() {
        let positions = GrowthForm.tickPositions(
            sessions: [day(3, hour: 9)],
            extras: [day(1, hour: 9)])
        #expect(positions[0] < 0, "ahead of dot zero, wrapped just before it")
    }

    @Test("A heavy day cannot run into the next session's dot")
    func clampedInsideTheGap() {
        let sessions = [day(0, hour: 9), day(4, hour: 9)]
        let extras = (0..<6).map { day(1 + $0 % 3, hour: 10 + $0) }
        let positions = GrowthForm.tickPositions(sessions: sessions, extras: extras)
        #expect(positions.allSatisfy { $0 > 0 && $0 < 1 },
                "all six followed session one and stay inside its gap")
    }
}
