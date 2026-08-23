import Foundation
import SwiftData
import WidgetKit

/// Writes the complication's fact sheet, from the watch.
///
/// `WidgetSnapshots` does this on the phone and it is not enough, because the
/// app group is per-device: the watch extension reads the *watch's* container
/// and the phone has never written a byte into it. A complication fed only by
/// the phone's snapshot would be permanently empty on a watch used with no
/// phone in the room, which is the whole case the watch app exists for.
///
/// So this is the same shape as `WidgetSnapshots`, written by the watch, plus
/// the four running fields the phone has no way to know: the wrist is the
/// only process awake while a session runs with the screen off.
///
/// Called from `WatchTodayView` at three seams and no others: when the list
/// appears, after anything ends, and when the app goes to the background —
/// which is every moment after which the complication could be stale. Phase 1
/// wires the fifth: the timer refreshing at each phase boundary.
@MainActor
enum WatchSnapshots {

    /// Rewrites the snapshot and asks WidgetKit to redraw.
    static func refresh(in context: ModelContext, now: Date = .now) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)

        let sessions = (try? context.fetch(FetchDescriptor<PlannedSession>())) ?? []
        let blocks = (try? context.fetch(FetchDescriptor<Block>(
            sortBy: [SortDescriptor(\.startDate, order: .reverse)]))) ?? []

        var snapshot = TodaySnapshot()
        snapshot.writtenOn = now
        snapshot.practiceDone = MorningPractices.done(on: now, in: context)
        snapshot.practiceMinutes = Int((Double(Tuning.practiceMovements) * Practice.seconds / 60).rounded())

        // The whole week, not just today, so the midnight flip shows
        // tomorrow's session without the watch app having been opened.
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

        if let block = blocks.first {
            snapshot.week = block.currentWeek
            snapshot.weekCount = block.weekCount
            snapshot.marksTarget = block.pace.sessionsPerWeek
            let start = DayOffer.weekStart(block.currentWeek, of: block)
            let end = calendar.date(byAdding: .day, value: 7, to: start) ?? start
            snapshot.marksThisWeek = sessions.filter {
                guard let done = $0.completedAt else { return false }
                return done >= start && done < end
            }.count
        }

        // One writer for the running fields, in `Core` so the phone and the
        // tests see the same one. It clears as readily as it fills.
        snapshot.setRunning(ActiveSessionStore.load(now), now: now)

        snapshot.save()
        WidgetCenter.shared.reloadAllTimelines()
    }
}
