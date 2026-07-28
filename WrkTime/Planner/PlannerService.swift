import Foundation
import SwiftData

/// Turns a week into rows in the store.
///
/// The order here is the whole design: **ask Claude, validate, and fall back**.
/// A generated week is never written to the store on the strength of having
/// parsed — it has to survive `PlanValidator` first, and if it does not, the
/// deterministic planner writes the week instead. That means there is no state
/// in which the reader opens the app to an empty plan, and no state in which a
/// session asks her for a barbell.
///
/// Completed sessions are never touched. Re-planning a week rewrites what has
/// not happened yet and leaves the record of what has.
/// Whether a week is being written right now, and by whom.
///
/// Planning is a network call that can take the better part of a minute on a
/// slow connection, and it happens at exactly two moments the reader is
/// watching: just after starting a block, and on the first launch of a new
/// week. Without this both were silent — the sheet closed and Today simply sat
/// there. Nothing about that told her the app was working rather than broken.
@Observable
@MainActor
final class PlannerActivity {
    private(set) var week: Int?
    /// True when there is a key set, so the wait is a network wait rather than
    /// the offline planner taking a millisecond.
    private(set) var askingClaude = false

    var isPlanning: Bool { week != nil }

    /// One line naming what is happening. Says "Claude" only when that is
    /// actually true — the offline planner is not Claude and should not borrow
    /// its name to look busier.
    var note: String? {
        guard let week else { return nil }
        return askingClaude
            ? "Asking Claude for week \(week). This takes a moment."
            : "Writing week \(week)."
    }

    func begin(week: Int) {
        self.week = week
        askingClaude = KeychainStore.has(.claudeAPIKey)
    }

    func finish() {
        week = nil
        askingClaude = false
    }
}

@MainActor
enum PlannerService {
    enum Source: Equatable {
        case claude
        /// Carries why, so Settings can say what happened once rather than
        /// leaving the reader to wonder why the week reads generically.
        case offline(String?)
        /// Written from the plan's own rules **on purpose** rather than because
        /// something failed. Kept apart from `offline` so the copy can say the
        /// difference: one is a fallback, the other is thrift.
        case stepped(String)
    }

    struct Outcome {
        var explanation: String
        var source: Source
        var sessionsWritten: Int
        var walkMinutes: Int = 0
    }

    /// Where the last week's explanation is kept so Today can show it.
    ///
    /// These are plain `UserDefaults` keys read by `@AppStorage` in the views.
    /// The service owns them rather than each caller, so an explanation cannot
    /// be produced and then dropped on the floor — which is exactly what
    /// happened when the writing was left to the call site.
    enum Memo {
        static let explanation = "lastPlanExplanation"
        static let failure = "lastPlanFailure"
        static let weekNumber = "lastPlanWeek"
        static let walkMinutes = "lastPlanWalkMinutes"
        static let steppedReason = "lastPlanStepped"

        static var lastExplanation: String? {
            let text = UserDefaults.standard.string(forKey: explanation)
            return (text?.isEmpty ?? true) ? nil : text
        }

        static func record(_ outcome: Outcome, week: Int) {
            let defaults = UserDefaults.standard
            defaults.set(outcome.explanation, forKey: explanation)
            defaults.set(week, forKey: weekNumber)
            defaults.set(outcome.walkMinutes, forKey: walkMinutes)

            // A failure is only worth saying out loud if she was expecting
            // Claude to answer. With no key set, the offline planner *is* the
            // plan — announcing that every week would be noise about a choice
            // she already made.
            let reason: String? = if case .offline(let note) = outcome.source,
                                     KeychainStore.has(.claudeAPIKey) { note } else { nil }
            defaults.set(reason ?? "", forKey: failure)

            // Said separately from a failure, because it is not one.
            let stepped: String? = if case .stepped(let note) = outcome.source { note } else { nil }
            defaults.set(stepped ?? "", forKey: steppedReason)
        }
    }

    /// Whether a week has had anything written to it yet.
    static func isPlanned(_ weekNumber: Int, of block: Block) -> Bool {
        let start = weekStart(weekNumber, of: block)
        let end = Calendar.current.date(byAdding: .day, value: 7, to: start) ?? start
        return (block.sessions ?? []).contains { $0.scheduledFor >= start && $0.scheduledFor < end }
    }

    /// Writes the week the block is currently in, if nobody has yet.
    ///
    /// This is what makes the block twelve weeks rather than one. Planning
    /// happens lazily, when the app is opened into a week with nothing in it,
    /// rather than on a schedule or a background task: a plan written a week
    /// ahead would be written without knowing what she actually did, which is
    /// the one input the planner most needs.
    ///
    /// Returns nil when there was nothing to do, so the caller can tell "the
    /// week was already planned" from "the week was planned just now".
    static func planCurrentWeekIfNeeded(for block: Block,
                                        in context: ModelContext,
                                        planner: ClaudePlanner = ClaudePlanner()) async -> Outcome? {
        guard !block.hasEnded else { return nil }
        let week = block.currentWeek
        guard !isPlanned(week, of: block) else { return nil }
        return await planWeek(week, of: block, in: context, planner: planner)
    }

    /// Plans `weekNumber` (1-based) of `block` and writes it to the store.
    /// Plans `weekNumber` (1-based) of `block` and writes it to the store.
    ///
    /// `force` bypasses the decision about whether the model is worth asking —
    /// it is what the Rewrite button in Settings uses, because that is her
    /// asking directly.
    static func planWeek(_ weekNumber: Int,
                         of block: Block,
                         in context: ModelContext,
                         force: Bool = false,
                         planner: ClaudePlanner = ClaudePlanner()) async -> Outcome {
        // Fetched here rather than inside `context(for:)` because Health is
        // async and the snapshot is not.
        let walked = await recentWalkMinutes()
        var snapshot = self.context(for: block, weekNumber: weekNumber, in: context)
        snapshot.recentWalkMinutes = walked
        snapshot.poundsToGoal = poundsToGoal(for: block, in: context)

        // Read once: the same opinions steer the fallback week, the flow
        // practice, and nothing else may reach past them.
        let refused = MovePreferences.lists(in: context)
        let excluded = Set((refused.avoided + refused.disliked).map { MovePreference.key($0) })

        var draft: PlanDraft
        var source: Source

        // Ask the model when there is something to adapt to. A clean week with
        // nothing new to say produces the same shape either way, and the
        // progression itself is arithmetic the app already does.
        let decision = force
            ? PlanTrigger.Decision(asksClaude: true, reason: "You asked for this week to be written again.")
            : PlanTrigger.decide(week: weekNumber, of: block, in: context)

        guard decision.asksClaude else {
            let draft = OfflinePlanner.week(weekNumber, pace: block.pace, avoiding: excluded)
            let written = write(routines(from: draft), weekNumber: weekNumber, of: block,
                                avoiding: excluded, in: context)
            let outcome = Outcome(explanation: draft.explanation, source: .stepped(decision.reason),
                                  sessionsWritten: written, walkMinutes: draft.walkMinutes)
            Memo.record(outcome, week: weekNumber)
            return outcome
        }

        do {
            PlanTrigger.recordCall()
            defer { PlanTrigger.record(ClaudePlanner.lastUsage) }
            let generated = try await planner.plan(snapshot)
            // Parsing is not trusting. If the week breaks the kit or the
            // ceiling, it is discarded whole and the offline planner runs.
            _ = try PlanValidator.routines(from: generated)
            draft = generated
            source = .claude
        } catch {
            // The fallback honours her preferences too. A week written because
            // the network failed is still a week she has to do.
            draft = OfflinePlanner.week(weekNumber, pace: block.pace, avoiding: excluded)
            source = .offline((error as? LocalizedError)?.errorDescription
                              ?? (error as? PlanValidator.Failure)?.errorDescription)
        }

        // The offline draft is validated too. It is built from the real library
        // so it should always pass — and if a future edit breaks that, this is
        // where it surfaces rather than in a session she is halfway through.
        guard let routines = try? PlanValidator.routines(from: draft) else {
            return Outcome(explanation: "This week could not be written.",
                           source: source, sessionsWritten: 0)
        }

        let written = write(routines, weekNumber: weekNumber, of: block,
                            avoiding: excluded, in: context)
        let outcome = Outcome(explanation: draft.explanation, source: source,
                              sessionsWritten: written, walkMinutes: draft.walkMinutes)
        Memo.record(outcome, week: weekNumber)
        return outcome
    }

    /// Validated routines, or an empty week rather than a bad one.
    private static func routines(from draft: PlanDraft) -> [(dayOffset: Int, routine: IntervalRoutine)] {
        (try? PlanValidator.routines(from: draft)) ?? []
    }

    // MARK: - Store

    /// The first day of `weekNumber`, counted from the block's own start rather
    /// than from a calendar week, so week two always begins seven days after
    /// week one regardless of which day the block started on.
    static func weekStart(_ weekNumber: Int, of block: Block) -> Date {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: block.startDate)
        return calendar.date(byAdding: .day, value: (weekNumber - 1) * 7, to: start) ?? start
    }

    /// Writes the week, opening every session with its flow practice.
    ///
    /// The warm-up is attached here rather than by either planner because this
    /// is the first point at which the session's *date* is known, and the
    /// practice rotates by day so two sessions in one week do not open with the
    /// same four movements.
    private static func write(_ routines: [(dayOffset: Int, routine: IntervalRoutine)],
                              weekNumber: Int,
                              of block: Block,
                              avoiding excluded: Set<String>,
                              in context: ModelContext) -> Int {
        let calendar = Calendar.current
        let start = weekStart(weekNumber, of: block)
        let end = calendar.date(byAdding: .day, value: 7, to: start) ?? start

        // Clear what was planned for this week and not done. A finished session
        // is a record of something that happened and is never rewritten.
        for existing in block.sessions ?? [] where !existing.isComplete
            && existing.scheduledFor >= start && existing.scheduledFor < end {
            context.delete(existing)
        }

        // Days this week she has already trained. Kept out of the loop below,
        // because a finished session being left alone is only half the rule —
        // the other half is not writing a second one on top of it. A rewrite
        // mid-week used to hand Monday a fresh incomplete session next to the
        // one she had finished, and everything downstream believed it: Today
        // listed the day as still to do, and `PlanTrigger` counted it as a
        // session missed, so the following week was adapted around work she
        // had actually done.
        let trained = Set((block.sessions ?? [])
            .filter { $0.isComplete && $0.scheduledFor >= start && $0.scheduledFor < end }
            .map { calendar.startOfDay(for: $0.scheduledFor) })

        var written = 0
        for entry in routines {
            guard let day = calendar.date(byAdding: .day, value: entry.dayOffset, to: start) else { continue }
            guard !trained.contains(calendar.startOfDay(for: day)) else { continue }
            let routine = entry.routine.warmingUp(
                with: WarmUp.afterPractice(on: day, avoiding: excluded))
            let session = PlannedSession(scheduledFor: day,
                                         title: entry.routine.name,
                                         routine: routine)
            session.block = block
            context.insert(session)
            written += 1
        }

        // Saved here rather than left to the caller, because the caller is not
        // always a view. A `ModelContext` made by hand — as the six a.m.
        // background task must — has `autosaveEnabled == false`, so the whole
        // week was inserted, never written to disk, and discarded when the
        // context deallocated. The request was still made and still billed,
        // and `setTaskCompleted(success:)` still reported success.
        //
        // The one place that mutates is the one place that saves. Anything
        // else leaves it to whichever context happens to be passed in.
        try? context.save()
        return written
    }

    /// Minutes walked in the last seven days, as Health recorded them. Nil
    /// when nothing came back — which is not the same as zero, and the prompt
    /// says so.
    static func recentWalkMinutes(_ health: HealthService = HealthKitService()) async -> Int? {
        let walks = await health.walks(since: Date.now.addingTimeInterval(-7 * 86_400))
        guard !walks.isEmpty else { return nil }
        return Int(walks.reduce(0) { $0 + $1.minutes }.rounded())
    }

    /// How far she is from the goal, on the trailing mean rather than the last
    /// reading, and only when she actually set one.
    static func poundsToGoal(for block: Block, in context: ModelContext) -> Double? {
        guard block.hasGoal else { return nil }
        let entries = (try? context.fetch(FetchDescriptor<WeightEntry>())) ?? []
        guard let mean = WeightTrend(entries: entries).sevenDayMean else { return nil }
        return max(mean - block.goalWeightPounds, 0)
    }

    // MARK: - Snapshot

    /// Everything the planner is told. Read from the store, never inferred.
    static func context(for block: Block,
                        weekNumber: Int,
                        in context: ModelContext) -> PlanContext {
        let fortnightAgo = Date.now.addingTimeInterval(-14 * 86_400)

        let recent = (block.sessions ?? [])
            .filter { $0.scheduledFor >= fortnightAgo && $0.scheduledFor <= .now }
            .sorted { $0.scheduledFor > $1.scheduledFor }
            .prefix(10)
            .map { session in
                let day = session.scheduledFor.formatted(.dateTime.weekday(.abbreviated))
                return "\(day) · \(session.title) · \(session.isComplete ? "finished" : "not done")"
            }

        let sets = (try? context.fetch(FetchDescriptor<LoggedSet>(
            predicate: #Predicate { $0.date >= fortnightAgo },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        ))) ?? []

        let weights = (try? context.fetch(FetchDescriptor<WeightEntry>())) ?? []
        let window = (try? context.fetch(FetchDescriptor<FastWindow>()))?.first
        let preferences = MovePreferences.lists(in: context)

        return PlanContext(
            weekNumber: weekNumber,
            pace: block.pace,
            recent: Array(recent),
            loggedSets: sets.prefix(10).map(\.summary),
            weightNote: weightNote(block: block, entries: weights),
            eatingWindow: window.map { window in
                let opens = String(format: "%02d:%02d", window.windowOpensHour, window.windowOpensMinute)
                let closes = String(format: "%02d:%02d", window.windowClosesHour, window.windowClosesMinute)
                return "\(opens)–\(closes)"
            },
            avoidedMoves: preferences.avoided,
            dislikedMoves: preferences.disliked,
            hardMoves: preferences.hard,
            // Threaded back in so week five reads as a continuation of week
            // four rather than as a fresh start with amnesia.
            lastExplanation: Memo.lastExplanation
        )
    }

    /// Weight is passed as a trend and a direction, never as a target to
    /// program toward. The plan's job is to hold muscle while the number moves;
    /// it is not the thing moving the number, and the planner is told so.
    private static func weightNote(block: Block, entries: [WeightEntry]) -> String? {
        guard block.hasGoal, let mean = WeightTrend(entries: entries).sevenDayMean else { return nil }
        guard let projection = Projections.project(current: mean, goal: block.goalWeightPounds) else { return nil }

        let direction = projection.isComplete ? "at her goal" :
            "\(Int(projection.poundsRemaining.rounded())) lb above a goal she set herself"
        return "\(Int(mean.rounded())) lb on a seven-reading average, \(direction). "
             + "Do not program toward the weight — keep the resistance work honest so she holds muscle while it moves."
    }
}
