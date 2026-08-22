import Foundation
import SwiftData
import WidgetKit

/// Writes the widget's fact sheet and asks WidgetKit to redraw.
///
/// Called from two seams and deliberately no others: the app going to
/// background — the widget is only visible when the app is not — and the
/// planner writing a week, which is the one mutation that happens with the
/// app closed. Everything she does in the app funnels through the first.
@MainActor
enum WidgetSnapshots {
    static func refresh(in context: ModelContext) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)

        let sessions = (try? context.fetch(FetchDescriptor<PlannedSession>())) ?? []
        let block = (try? context.fetch(FetchDescriptor<Block>(
            sortBy: [SortDescriptor(\.startDate, order: .reverse)]))) ?? []

        var snapshot = TodaySnapshot()
        snapshot.writtenOn = .now
        snapshot.practiceDone = MorningPractices.done(in: context)
        snapshot.practiceMinutes = Int((Double(Tuning.practiceMovements) * Practice.seconds / 60).rounded())

        snapshot.days = (0..<7).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: today)
            else { return nil }
            let planned = sessions.first { calendar.isDate($0.scheduledFor, inSameDayAs: day) }
            return TodaySnapshot.Day(
                date: day,
                title: planned?.title,
                minutes: (planned?.routine?.totalDuration).map { Int(($0 / 60).rounded()) },
                done: planned?.isComplete ?? false)
        }

        if let block = block.first {
            snapshot.week = block.currentWeek
            snapshot.weekCount = block.weekCount
            snapshot.marksTarget = block.pace.sessionsPerWeek
            let start = PlannerService.weekStart(block.currentWeek, of: block)
            let end = calendar.date(byAdding: .day, value: 7, to: start) ?? start
            snapshot.marksThisWeek = sessions.filter {
                guard let done = $0.completedAt else { return false }
                return done >= start && done < end
            }.count
        }

        snapshot.save()
        WidgetCenter.shared.reloadAllTimelines()
    }
}
