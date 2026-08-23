import Foundation

/// What the plan still has to offer on a day whose own session is done, or
/// on a rest day.
///
/// This is the selection `TodayView.offeredSession` makes, lifted out so the
/// wrist and the phone cannot answer it differently — and so it can be
/// tested, which on the phone it never could be: it was a computed property
/// on a view, reachable only by building the view.
///
/// The order is the whole rule and it is deliberate. **Missed comes first.**
/// Pulling tomorrow's session forward on a day she already skipped one would
/// leave the skipped session sitting there and quietly shorten the week.
///
/// Nothing here is copy. Each surface writes its own sentence from `Kind` —
/// the wrist has room for four words and the phone has room for a paragraph.
enum DayOffer {

    /// Which of the two offers this is, so the caller can say it in its own
    /// voice. Offered, never urged, on both.
    enum Kind: Equatable {
        /// A session earlier in this week that went undone.
        case missed
        /// The next one written, taken early.
        case early
    }

    struct Offer {
        let session: PlannedSession
        let kind: Kind

        /// The weekday the session was written for — the one word both
        /// surfaces build their sentence around.
        var day: String {
            session.scheduledFor.formatted(.dateTime.weekday(.wide))
        }
    }

    /// - Parameters:
    ///   - sessions: every planned session in the store; filtering is this
    ///     function's job, not the caller's.
    ///   - weekStart: the first day of the current block week, so a session
    ///     missed *last* week is not dragged into this one.
    ///   - today: midnight of today. A session scheduled for today is
    ///     neither missed nor early — it is today, and the caller shows it.
    static func next(from sessions: [PlannedSession],
                     weekStart: Date,
                     today: Date) -> Offer? {
        // Most recent first, so "the day before" is what gets offered rather
        // than the oldest thing in the week.
        if let missed = sessions
            .filter({ !$0.isComplete && $0.scheduledFor < today && $0.scheduledFor >= weekStart })
            .max(by: { $0.scheduledFor < $1.scheduledFor }) {
            return Offer(session: missed, kind: .missed)
        }

        if let next = sessions
            .filter({ !$0.isComplete && $0.scheduledFor > today })
            .min(by: { $0.scheduledFor < $1.scheduledFor }) {
            return Offer(session: next, kind: .early)
        }
        return nil
    }

    /// The first day of `weekNumber`, counted from the block's own start
    /// rather than from a calendar week.
    ///
    /// The same arithmetic as `PlannerService.weekStart`, which lives in the
    /// phone target and so cannot be called from the watch. Two spellings of
    /// one question is exactly the shape CLAUDE.md warns about, so this is
    /// the one to keep: `PlannerService.weekStart` should forward to it when
    /// the phone is next touched.
    static func weekStart(_ weekNumber: Int, of block: Block) -> Date {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: block.startDate)
        return calendar.date(byAdding: .day, value: (weekNumber - 1) * 7, to: start) ?? start
    }

    /// A session she finished **today**, whatever day it was written for.
    ///
    /// `FinishedSessions.today` on the phone, which lives in `TodayView.swift`
    /// and so is out of the watch's reach. Same rule: the session today was
    /// written for wins, so a day holding both reads as the day the plan
    /// describes rather than as whatever finished last.
    static func finishedToday(_ sessions: [PlannedSession], now: Date = .now,
                              calendar: Calendar = .current) -> PlannedSession? {
        let done = sessions.filter {
            guard let at = $0.completedAt else { return false }
            return calendar.isDate(at, inSameDayAs: now)
        }
        return done.first { calendar.isDate($0.scheduledFor, inSameDayAs: now) }
            ?? done.max { ($0.completedAt ?? .distantPast) < ($1.completedAt ?? .distantPast) }
    }
}
