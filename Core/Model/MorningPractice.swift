import Foundation
import SwiftData

/// The morning practice: eight flow movements, a minute each, every day.
///
/// This is not a warm-up and not a session. She asked for it in as many words —
/// "one of those every morning separate to the workout sessions but mandatory …
/// it's important we do these every day" — and the two properties that follow
/// from *every day* are the ones the code has to protect:
///
/// **It is not tied to the plan.** It appears on a rest day, in week one and in
/// week twelve, and on a day the planner never wrote. Nothing about it is
/// conditional on a `PlannedSession` existing.
///
/// **It does not earn a mark.** Rule three stands: one mark on the growth form
/// is one finished planned session. A practice that drew on the form would make
/// the form mean "I moved" rather than "I did the plan", and the daily thing
/// would quietly swamp the weekly one. It keeps its own record instead.
enum Practice {
    /// How many movements this morning asks for. Eight by default — long
    /// enough to be a practice in its own right, short enough to survive a
    /// morning — and hers to change in Settings.
    static var count: Int { Tuning.practiceMovements }
    /// A minute each — eight minutes in total.
    ///
    /// Sixty seconds is also `IntervalRoutine.workCeiling`, and that is a
    /// coincidence rather than a constraint: the ceiling governs *work*
    /// intervals, and a flow phase is not one. Nothing here is clamped by it.
    static let seconds: TimeInterval = 60

    /// The movement every morning opens with.
    ///
    /// Named rather than positioned, so the rotation cannot ever displace it.
    static let opener = "Lymphatic bounce"

    /// Today's practice: the rebounding first, then seven more.
    ///
    /// Rotated by the date the same way the session warm-up is, so the same day
    /// always produces the same practice and consecutive days differ. The
    /// opener is lifted out of the rotation entirely — it leads every day, and
    /// leaving it in the pool would occasionally place it fourth.
    static func moves(on date: Date,
                      avoiding excluded: Set<String> = [],
                      count wanted: Int? = nil,
                      library: [Move] = MoveLibrary.flow) -> [Move] {
        let count = wanted ?? Self.count
        let allowed = library.filter { move in
            !excluded.contains { !$0.isEmpty && MovePreference.key(move.name).contains($0) }
        }
        guard !allowed.isEmpty else { return [] }

        let lead = allowed.first { MovePreference.key($0.name) == MovePreference.key(opener) }
        let rest = allowed.filter { $0.name != lead?.name }
        guard !rest.isEmpty else { return lead.map { [$0] } ?? [] }

        let following = (lead == nil ? count : count - 1)
        return (lead.map { [$0] } ?? [])
            + Rotation.walk(rest, taking: following, varying: Rotation.dayIndex(date))
    }

    /// The practice as something the interval engine can run.
    ///
    /// A routine of pure flow: no rounds, no rest, no work interval. The
    /// schedule allows that precisely so this can exist without a second engine.
    static func routine(on date: Date, avoiding excluded: Set<String> = [],
                        library: [Move] = MoveLibrary.flow) -> IntervalRoutine {
        IntervalRoutine(name: "Morning practice", work: 0, rest: 0, rounds: 0, moves: [])
            .warmingUp(with: moves(on: date, avoiding: excluded, library: library),
                       seconds: seconds)
    }
}

/// One morning's practice, done or not.
///
/// A row exists only once the practice has been *finished*. There is no record
/// of a day she did not do it, and that is deliberate: a table of absences is a
/// ledger of failure, and this app does not keep one. "Has today been done" is
/// a lookup, not a score.
@Model
final class MorningPractice {
    var id: UUID = UUID()
    /// Midnight of the day this belongs to, so a practice at 06:00 and one at
    /// 23:30 land on the same day and the second cannot double-count.
    var day: Date = Date()
    var completedAt: Date = Date()
    /// What she actually did, in case the rotation changes under an old record.
    var moveNames: [String] = []

    init(day: Date, moveNames: [String], completedAt: Date = .now) {
        self.day = Calendar.current.startOfDay(for: day)
        self.moveNames = moveNames
        self.completedAt = completedAt
    }
}

@MainActor
enum MorningPractices {
    static func all(in context: ModelContext) -> [MorningPractice] {
        (try? context.fetch(FetchDescriptor<MorningPractice>())) ?? []
    }

    static func done(on date: Date = .now, in context: ModelContext) -> Bool {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: date)
        // Both sides normalised, which `run` and the fortnight strip already
        // did and this did not. `day` is stored as an absolute instant stamped
        // in whatever zone she was in when she finished, so comparing it raw
        // against a freshly computed midnight failed the moment she changed
        // time zone: a practice done that morning in Los Angeles read as not
        // done from New York, Today offered it again, and `record`'s guard let
        // a second row through for a day that already had one.
        return all(in: context).contains { calendar.startOfDay(for: $0.day) == day }
    }

    /// Records today's, once. Called twice in a day it does nothing the second
    /// time rather than writing a duplicate.
    static func record(_ moves: [Move], on date: Date = .now, in context: ModelContext) {
        guard !done(on: date, in: context) else { return }
        context.insert(MorningPractice(day: date, moveNames: moves.map(\.name)))
    }

    /// Consecutive days up to and including today.
    ///
    /// Reported as a plain count of days and never as a target, a badge or a
    /// thing to protect. It exists because "every day" is the whole point of
    /// the practice and a number is the shortest honest way to say how it is
    /// going — not to make her afraid of losing it.
    static func run(upTo date: Date = .now, in context: ModelContext) -> Int {
        let calendar = Calendar.current
        let days = Set(all(in: context).map { calendar.startOfDay(for: $0.day) })
        guard !days.isEmpty else { return 0 }

        var cursor = calendar.startOfDay(for: date)
        // Today not being done yet does not break yesterday's run — the day is
        // not over.
        if !days.contains(cursor) {
            cursor = calendar.date(byAdding: .day, value: -1, to: cursor) ?? cursor
        }
        var length = 0
        while days.contains(cursor) {
            length += 1
            cursor = calendar.date(byAdding: .day, value: -1, to: cursor) ?? cursor
        }
        return length
    }
}
