import Foundation
import SwiftData

/// How hard the block pushes — the one dial the reader gets over the plan.
///
/// This changes how often you train and how quickly load and rounds climb. It
/// deliberately does **not** claim to change how fast the scale moves: with
/// short sessions and 2–15 lb kit, the sessions are not where the
/// energy balance is decided, and a dial that implied otherwise would be
/// lying. What it genuinely buys is a faster strength curve and more days
/// under tension — which is worth having, and worth being honest about.
enum Pace: String, Codable, CaseIterable, Identifiable, Sendable {
    case steady
    case building
    case hard

    var id: String { rawValue }

    var label: String {
        switch self {
        case .steady: "Steady"
        case .building: "Building"
        case .hard: "Hard"
        }
    }

    /// What it actually changes, in the units the plan is written in.
    var note: String {
        switch self {
        // Never "load moves". The kit is four fixed weights and a walking pad,
        // so load *cannot* move — `OfflinePlanner` progresses rest down, work
        // up and rounds up, and the system prompt tells Claude the same thing.
        // This is the first sentence she reads on the first screen she sees,
        // and it described a progression the app is incapable of.
        case .steady: "Three sessions a week. The shape steps on every third week."
        case .building: "Four a week. The shape steps on every other week."
        case .hard: "Five a week. Rest shortens weekly and rounds climb."
        }
    }

    /// The honest line about what this does and does not do.
    var expectation: String {
        switch self {
        case .steady:
            "Room to miss a day without losing the week."
        case .building:
            "The middle setting, and the one most weeks survive contact with."
        case .hard:
            "Strength climbs fastest here. It will not move the scale faster — that is decided by the walking, not by these short sessions."
        }
    }

    var sessionsPerWeek: Int {
        switch self {
        case .steady: 3
        case .building: 4
        case .hard: 5
        }
    }

    /// Weeks between one step up in load or rounds.
    var progressionWeeks: Int {
        switch self {
        case .steady: 3
        case .building: 2
        case .hard: 1
        }
    }

    /// Rounds added at each progression step.
    var roundStep: Int { self == .hard ? 1 : 0 }
}

/// An 84-day block. The planner writes one of these and revises it weekly.
@Model
final class Block {
    var id: UUID = UUID()
    var startDate: Date = Date()
    var lengthInDays: Int = 84
    var goalWeightPounds: Double = 0
    var startingWeightPounds: Double = 0
    /// Stored raw because SwiftData + CloudKit want a primitive with a default.
    var paceRaw: String = Pace.building.rawValue
    /// CloudKit requires every relationship to declare its inverse, so this
    /// pairs with `PlannedSession.block`.
    @Relationship(deleteRule: .cascade, inverse: \PlannedSession.block)
    var sessions: [PlannedSession]? = []

    init(startDate: Date = .now,
         goalWeightPounds: Double,
         startingWeightPounds: Double,
         pace: Pace = .building) {
        self.startDate = startDate
        self.goalWeightPounds = goalWeightPounds
        self.startingWeightPounds = startingWeightPounds
        self.paceRaw = pace.rawValue
    }

    var pace: Pace {
        get { Pace(rawValue: paceRaw) ?? .building }
        set { paceRaw = newValue.rawValue }
    }

    /// Pounds between where you started and where you said you were going.
    /// Negative when the goal is above the start, which is a legitimate goal
    /// and one the projection has to handle without editorialising.
    var goalDelta: Double { startingWeightPounds - goalWeightPounds }

    var hasGoal: Bool { goalWeightPounds > 0 && startingWeightPounds > 0 }

    var dayNumber: Int {
        let days = Calendar.current.dateComponents([.day], from: startDate, to: .now).day ?? 0
        return min(max(days + 1, 1), lengthInDays)
    }

    var endDate: Date {
        Calendar.current.date(byAdding: .day, value: lengthInDays, to: startDate) ?? startDate
    }

    var weekCount: Int { max(lengthInDays / 7, 1) }

    /// The week you are actually in, from the calendar.
    ///
    /// Derived from elapsed time rather than from how many sessions you have
    /// finished: a block is a span of time, not a queue of work, and a quiet
    /// week has to be able to exist. This lives on the block rather than in a
    /// view because the planner needs the same answer — the week the planner
    /// writes and the week Today draws must never be able to disagree.
    var currentWeek: Int {
        let calendar = Calendar.current
        let days = calendar.dateComponents([.day],
                                           from: calendar.startOfDay(for: startDate),
                                           to: .now).day ?? 0
        return min(max(days / 7 + 1, 1), weekCount)
    }

    /// True once the twelve weeks are up. The planner stops here rather than
    /// quietly extending a block she has finished.
    var hasEnded: Bool { Date.now >= endDate }

    /// Seeds this block's growth form, so one season's drawing is not another's.
    ///
    /// Built from the identifier's bytes rather than `hashValue`, which Swift
    /// seeds randomly per process — using it would redraw the form differently
    /// on every launch, which is precisely what the form promises not to do.
    var formSeed: UInt64 {
        let b = id.uuid
        let bytes = [b.0, b.1, b.2, b.3, b.4, b.5, b.6, b.7]
        return bytes.reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
    }
}

/// A session the planner scheduled. `completedAt` is the only thing that turns
/// it into a mark on the growth form — a session you started and abandoned does
/// not count, and the app does not pretend otherwise.
@Model
final class PlannedSession {
    var id: UUID = UUID()
    var scheduledFor: Date = Date()
    var title: String = ""
    /// The routine encoded, so a session runs through the same engine as a
    /// hand-built one.
    var routineData: Data?
    var completedAt: Date?
    var perceivedEffort: Int?
    /// Reps counted per set, in the order the sets were worked. Whoop asks for
    /// sets and reps rather than intervals, and only she knows the number —
    /// the app times the work, it cannot count it. Optional because rows
    /// written before this existed have none, and a set she did not count is
    /// stored as zero rather than guessed at.
    var repCounts: [Int]?
    var block: Block?

    init(scheduledFor: Date, title: String, routine: IntervalRoutine?) {
        self.scheduledFor = scheduledFor
        self.title = title
        self.routineData = routine.flatMap { try? JSONEncoder().encode($0) }
    }

    var routine: IntervalRoutine? {
        guard let routineData else { return nil }
        let stored = try? JSONDecoder().decode(IntervalRoutine.self, from: routineData)
        // A finished session is a record, and a record does not shift under a
        // library change: `mark` froze the routine she actually ran — her
        // loads as they were that day — and stepping a move up to the 8 lb
        // ring tomorrow must not quietly rewrite what today's copy for Whoop
        // says she lifted.
        guard completedAt == nil else { return stored }
        // A session still ahead is the plan, and the plan keeps up: sidedness
        // from the library, and her current loads, so the week already written
        // asks for the ring she actually uses.
        return stored?
            .adoptingLibrarySidedness()
            .applyingLoads(from: MoveOverrides.table(in: modelContext))
    }

    var isComplete: Bool { completedAt != nil }
}

/// A routine the user built themselves. Kept separate from planned sessions so
/// the planner can never overwrite something you made.
@Model
final class SavedRoutine {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var lastRunAt: Date?
    var routineData: Data = Data()

    init(routine: IntervalRoutine) {
        self.routineData = (try? JSONEncoder().encode(routine)) ?? Data()
    }

    var routine: IntervalRoutine? {
        // Repaired on read for the same reason a planned session is. An
        // interrupted run is deliberately not: `ActiveSession` decodes its own
        // stored routine, and a resumed schedule must be exactly the one she
        // left.
        (try? JSONDecoder().decode(IntervalRoutine.self, from: routineData))?
            .adoptingLibrarySidedness()
            .applyingLoads(from: MoveOverrides.table(in: modelContext))
    }

    /// Rewrites this record in place.
    ///
    /// Editing a saved routine used to be impossible: tapping one ran it, and
    /// there was no other way in. A routine with a typo in its name or one
    /// round too many could only be replaced by building it again — and since
    /// there was no way to delete one either, the wrong one stayed forever.
    func update(to routine: IntervalRoutine) {
        routineData = (try? JSONEncoder().encode(routine)) ?? routineData
    }
}

/// A set done off the plan — twenty squats while the kettle boils.
///
/// Deliberately **not** a mark. Rule 3 stands: one mark is one finished planned
/// session, and if loose work drew on the growth form the form would stop
/// meaning "I did the plan" and become a general activity log. It is still
/// worth keeping — it is real work, it is volume the planner should know about
/// when it decides next week, and an almanac records what happened rather than
/// only what was scheduled.
@Model
final class LoggedSet {
    var id: UUID = UUID()
    var date: Date = Date()
    /// Stored by name and equipment rather than as a `Move`, so a set kept
    /// today still reads correctly if the move library changes under it.
    var moveName: String = ""
    var equipmentRaw: String = Equipment.bodyweight.rawValue
    var reps: Int = 0
    /// Nil for bodyweight and the pad, which have nothing to load.
    var loadPounds: Double?

    init(move: Move, reps: Int, loadPounds: Double?, date: Date = .now) {
        self.date = date
        self.moveName = move.name
        self.equipmentRaw = move.equipment.rawValue
        self.reps = reps
        self.loadPounds = loadPounds
    }

    var equipment: Equipment { Equipment(rawValue: equipmentRaw) ?? .bodyweight }

    /// "12 × Beam front squat · 15 lb"
    var summary: String {
        let load = loadPounds.map { " · \(Int($0)) lb" } ?? ""
        return "\(reps) × \(moveName)\(load)"
    }
}

/// Where a run that was not a planned session came from.
enum RunSource: String, Codable, Sendable, CaseIterable {
    /// A routine she built in the Timer tab.
    case saved
    /// A session the app composed for a day whose plan was already finished.
    case extra

    var label: String {
        switch self {
        case .saved: "Your own routine"
        case .extra: "Extra session"
        }
    }
}

/// A workout she finished that the plan did not ask for.
///
/// Her words: *"sometimes i do a lot of them in a day and i want that to be
/// considered."* Before this, finishing a routine she had built overwrote a
/// single `lastRunAt` and left nothing else — no history, no volume, no Health
/// entry, nothing the planner could see. Running one ten times was
/// indistinguishable from running it once, so a heavy week was invisible.
///
/// **Not a mark**, and that was her call when asked. Rule 3 stands for the same
/// reason it stands for `LoggedSet` and `MorningPractice`: the growth form means
/// "I did the plan", and if everything drew on it the form would become a
/// general activity log and stop being able to say that. This is volume — real
/// work, recorded, and passed to the planner as a reason the next week might
/// have room in it.
///
/// Stored by name rather than by reference to a `SavedRoutine`: deleting a
/// routine must not delete the record of having done it, and an extra session
/// has no stored routine to point at in the first place.
@Model
final class RoutineRun {
    /// Long enough to be real work rather than a moment on the timer. Her
    /// ask: extra sessions "that are real ones (over 7 mins)" earn a smaller
    /// tick on the growth form. One definition, so the form, the extra
    /// session builder and anything else that asks cannot disagree.
    static let substantialSeconds: TimeInterval = 7 * 60

    var id: UUID = UUID()
    var finishedAt: Date = Date()
    var name: String = ""
    /// Work intervals actually seen through — `roundCount`, never `rounds`.
    var roundsCompleted: Int = 0
    var seconds: TimeInterval = 0
    /// How long the routine was *written* to run, warm-up included. Optional
    /// because rows recorded before the key existed decode nil.
    var plannedSeconds: TimeInterval?
    /// How much of that written length was flow — the warm-up — so the weekly
    /// minutes can put qi gong under qi gong instead of under strength.
    var flowSeconds: TimeInterval?
    /// Reps counted per set, in the order the sets were worked. See
    /// `PlannedSession.repCounts`.
    var repCounts: [Int]?
    /// The routine as run, encoded — so a run can be reopened and done again,
    /// even after the saved routine it came from is edited or deleted, and
    /// even for an extra that was composed on the spot and never stored
    /// anywhere else. Optional: rows recorded before this carried nothing.
    var routineData: Data?
    var moveNames: [String] = []
    var sourceRaw: String = RunSource.saved.rawValue

    init(name: String, roundsCompleted: Int, seconds: TimeInterval,
         moveNames: [String], source: RunSource, finishedAt: Date = .now) {
        self.name = name
        self.roundsCompleted = roundsCompleted
        self.seconds = seconds
        self.moveNames = moveNames
        self.sourceRaw = source.rawValue
        self.finishedAt = finishedAt
    }

    var source: RunSource { RunSource(rawValue: sourceRaw) ?? .saved }

    /// Whether this run was a real session, judged by what the routine asked
    /// of her — its written length — never by the elapsed clock. Skipping
    /// through the rests still finished the session; her words: "that is
    /// still one session and should count toward the mark." Rows from before
    /// `plannedSeconds` fall back to elapsed, the only number they have.
    var isSubstantial: Bool {
        (plannedSeconds ?? seconds) >= Self.substantialSeconds
    }

    /// "Ladder · 6 rounds · 8:20"
    var summary: String {
        let rounds = roundsCompleted == 1 ? "1 round" : "\(roundsCompleted) rounds"
        return roundsCompleted > 0
            ? "\(name) · \(rounds) · \(seconds.durationString)"
            : "\(name) · \(seconds.durationString)"
    }
}

@MainActor
enum RoutineRuns {
    static func all(in context: ModelContext) -> [RoutineRun] {
        (try? context.fetch(FetchDescriptor<RoutineRun>(
            sortBy: [SortDescriptor(\.finishedAt, order: .reverse)]))) ?? []
    }

    /// Records a finished routine from the routine itself, so the caller does
    /// not have to know what the record wants.
    /// Returns the row it wrote, so a count that arrives after the ending —
    /// the last set, which has no rest to be counted in — can be filed against
    /// the same record rather than a second one.
    @discardableResult
    static func record(_ routine: IntervalRoutine, source: RunSource,
                       seconds: TimeInterval, reps: [Int] = [],
                       in context: ModelContext) -> RoutineRun {
        let run = RoutineRun(name: routine.name,
                             roundsCompleted: routine.roundCount,
                             seconds: seconds,
                             moveNames: routine.moves.map(\.name),
                             source: source)
        run.repCounts = reps.contains(where: { $0 > 0 }) ? reps : nil
        run.plannedSeconds = routine.schedule.total
        run.flowSeconds = routine.schedule.phases.filter(\.isFlow)
            .reduce(0) { $0 + $1.duration }
        run.routineData = try? JSONEncoder().encode(routine)
        context.insert(run)
        // Saved here rather than left to the caller. Recording a finished
        // workout is the effect that must not depend on anything else running,
        // and this app has lost that effect five times.
        try? context.save()
        return run
    }

    static func since(_ date: Date, in context: ModelContext) -> [RoutineRun] {
        all(in: context).filter { $0.finishedAt >= date }
    }

    /// What tapping a past run should open: the living saved routine when it
    /// still exists — so an edit she made since is honoured — otherwise the
    /// copy the run carries, which is exactly what she ran. Nil for rows
    /// recorded before runs kept their routine; those stay a plain ledger.
    static func reopen(_ run: RoutineRun,
                       in context: ModelContext) -> (routine: IntervalRoutine, saved: SavedRoutine?)? {
        guard let data = run.routineData,
              let stored = try? JSONDecoder().decode(IntervalRoutine.self, from: data)
        else { return nil }

        let saved = ((try? context.fetch(FetchDescriptor<SavedRoutine>())) ?? [])
            .first { $0.routine?.id == stored.id }
        if let saved, let current = saved.routine {
            return (current, saved)
        }
        return (stored.adoptingLibrarySidedness()
                    .applyingLoads(from: MoveOverrides.table(in: context)), nil)
    }
}

/// A move she asked to add to the library, and where it stands in review.
///
/// The built-in library is closed so that every planned move has a drawing and
/// a validated load by construction. Her own additions do not reopen it — they
/// go through this queue instead: names pile up as `queued`, one send hands the
/// whole batch to Claude to check against the kit and write the entry, and only
/// an `approved` row joins the working library. An approved custom move has no
/// drawing, deliberately — `MovePlates.strip(for:)` is a lookup, and a drawing
/// of the wrong movement is worse than none.
@Model
final class CustomMove {
    var id: UUID = UUID()
    var name: String = ""
    var statusRaw: String = Status.queued.rawValue
    var equipmentRaw: String = Equipment.bodyweight.rawValue
    /// Strength or flow — decided by the review, never asked of her. A queued
    /// qi gong movement is recognised as flow and joins the practice pool; a
    /// lift joins the rotations. She types a name and nothing else.
    var kindRaw: String = MoveKind.strength.rawValue
    var cue: String = ""
    var loadPounds: Double?
    var sidedRaw: String?
    /// What it works, in plain words — "shoulders, upper back". Written by the
    /// review, shown in the row, and how the muscle filter finds it.
    var muscles: String?
    /// The reviewer's one line: why a queued name was turned away, or anything
    /// worth knowing about an approval.
    var note: String?
    var addedAt: Date = Date()

    enum Status: String { case queued, approved, rejected }

    init(name: String) {
        self.name = name
        self.addedAt = .now
    }

    var status: Status { Status(rawValue: statusRaw) ?? .queued }

    var kind: MoveKind { MoveKind(rawValue: kindRaw) ?? .strength }

    /// The approved entry as a working move, carrying its reviewed kind.
    var move: Move {
        Move(name: name,
             equipment: Equipment(rawValue: equipmentRaw) ?? .bodyweight,
             kind: kind,
             cue: cue,
             loadPounds: loadPounds,
             sided: sidedRaw.flatMap(Sided.init(rawValue:)))
    }
}

@MainActor
enum CustomMoves {
    static func all(in context: ModelContext) -> [CustomMove] {
        (try? context.fetch(FetchDescriptor<CustomMove>(
            sortBy: [SortDescriptor(\.addedAt)]))) ?? []
    }

    /// Every approved addition, whatever its kind.
    static func approved(in context: ModelContext) -> [Move] {
        all(in: context).filter { $0.status == .approved }.map(\.move)
    }

    /// Her approved strength moves — what the planner's enum, the validator
    /// and the rotations mean by "the library, including hers". Never flow:
    /// a rotation entry becomes a work phase.
    static func strength(in context: ModelContext) -> [Move] {
        approved(in: context).filter { $0.kind == .strength }
    }

    /// Her approved flow movements — they join the practice and warm-up pool,
    /// never a rotation.
    static func flow(in context: ModelContext) -> [Move] {
        approved(in: context).filter { $0.kind == .flow }
    }
}

/// Her load for a built-in move, where it differs from the library's default.
///
/// The library is closed but the loads inside it are hers: "Ring halo" ships
/// on the 5 lb ring, and once that stops being challenging the right answer
/// is the 8 — not a duplicate move, not a reopened library. One row per move,
/// only ever a load the equipment can actually be set to, and applied where
/// stored routines are read back so already-written weeks pick it up too.
@Model
final class MoveOverride {
    var id: UUID = UUID()
    var moveName: String = ""
    var loadPounds: Double = 0

    init(moveName: String, loadPounds: Double) {
        self.moveName = moveName
        self.loadPounds = loadPounds
    }
}

/// Deliberately not `@MainActor`: the stored-routine getters apply overrides
/// on whatever context owns the model, including the overnight planner's.
enum MoveOverrides {
    /// Key → pounds, for the appliers.
    static func table(in context: ModelContext?) -> [String: Double] {
        guard let context else { return [:] }
        let rows = (try? context.fetch(FetchDescriptor<MoveOverride>())) ?? []
        return Dictionary(rows.map { (MovePreference.key($0.moveName), $0.loadPounds) },
                          uniquingKeysWith: { _, last in last })
    }

    /// Sets or clears in one motion: choosing the library's own default load
    /// is not an override, it is the end of one.
    @MainActor
    static func set(_ pounds: Double, for move: Move, in context: ModelContext) {
        let key = MovePreference.key(move.name)
        let existing = (try? context.fetch(FetchDescriptor<MoveOverride>()))?
            .filter { MovePreference.key($0.moveName) == key } ?? []
        existing.forEach(context.delete)
        if pounds != move.loadPounds, move.equipment.availableLoadsPounds.contains(pounds) {
            context.insert(MoveOverride(moveName: move.name, loadPounds: pounds))
        }
        try? context.save()
    }
}

extension Move {
    /// This move at her load, when she has set one. The cue is corrected too —
    /// "The 5 lb ring in both hands" naming a ring she is not holding would be
    /// the app contradicting itself mid-set.
    func applyingLoad(from table: [String: Double]) -> Move {
        guard let pounds = table[MovePreference.key(name)], pounds > 0,
              equipment.availableLoadsPounds.contains(pounds),
              pounds != loadPounds
        else { return self }
        var move = self
        if let old = loadPounds {
            move.cue = cue.replacingOccurrences(of: "\(Int(old)) lb", with: "\(Int(pounds)) lb")
        }
        move.loadPounds = pounds
        return move
    }
}

extension IntervalRoutine {
    /// The routine with her loads applied throughout — rotation and warm-up
    /// both, though in practice only strength moves carry loads.
    func applyingLoads(from table: [String: Double]) -> IntervalRoutine {
        guard !table.isEmpty else { return self }
        var copy = self
        copy.moves = moves.map { $0.applyingLoad(from: table) }
        copy.warmUpMoves = warmUpMoves.map { $0.map { $0.applyingLoad(from: table) } }
        return copy
    }
}

/// One move's counted sets from one session.
///
/// Reps live on the session as a flat list against the schedule, which is the
/// right shape for writing them down and the wrong one for reading them back:
/// a `RoutineRun` keeps move *names* and no schedule, so months later there is
/// no honest way to say which set belonged to which move. This is that answer,
/// recorded once at the ending — with the load, because eight reps of the 8 lb
/// ring is not eight of the 5.
@Model
final class SetLog {
    var id: UUID = UUID()
    var date: Date = Date()
    /// The session or run these sets came from, so re-counting the last set
    /// rewrites its row rather than adding a second one.
    var sourceID: UUID?
    var moveName: String = ""
    var loadPounds: Double?
    /// Counted sets in the order they were worked. For a sided move this is
    /// one entry per side.
    var reps: [Int] = []
    /// How long each counted set ran, aligned with `reps`. She lifts to time,
    /// so a count only means something next to its interval — nine reps in
    /// forty seconds and nine in sixty are different sessions. Optional
    /// because rows from before the key have no honest value to invent.
    var setSeconds: [Double]?
    var sidedRaw: String?

    init(sourceID: UUID?, move: Move, reps: [Int], date: Date = .now) {
        self.sourceID = sourceID
        self.moveName = move.name
        self.loadPounds = move.loadPounds
        self.reps = reps
        self.sidedRaw = move.sidedRaw
        self.date = date
    }

    var sided: Sided? { sidedRaw.flatMap(Sided.init(rawValue:)) }
    /// Turns, which is what she did — a sided move's two intervals are one.
    var turns: Int { sided != nil ? max(reps.count / 2, 1) : reps.count }
    var best: Int { reps.max() ?? 0 }
    var total: Int { reps.reduce(0, +) }
}

@MainActor
enum SetLogs {
    /// Writes this session's counted sets, replacing anything already written
    /// for the same session so a late count corrects rather than duplicates.
    static func record(_ routine: IntervalRoutine, reps: [Int],
                       sourceID: UUID?, date: Date = .now,
                       in context: ModelContext) {
        let existing = ((try? context.fetch(FetchDescriptor<SetLog>())) ?? [])
            .filter { $0.sourceID == sourceID && sourceID != nil }
        existing.forEach(context.delete)

        for entry in WhoopSummary.counted(for: routine, reps: reps) {
            let log = SetLog(sourceID: sourceID, move: entry.move,
                             reps: entry.reps, date: date)
            log.setSeconds = entry.seconds.map { Double($0) }
            context.insert(log)
        }
        try? context.save()
    }

    /// Every session this move was counted in, oldest first.
    static func history(for move: Move, in context: ModelContext) -> [SetLog] {
        let key = MovePreference.key(move.name)
        return ((try? context.fetch(FetchDescriptor<SetLog>(
            sortBy: [SortDescriptor(\.date)]))) ?? [])
            .filter { MovePreference.key($0.moveName) == key && !$0.reps.isEmpty }
    }
}

/// A weight reading. Source is recorded because a Health-sourced number and a
/// typed one deserve different trust when projecting.
@Model
final class WeightEntry {
    enum Source: String, Codable { case health, manual }

    var id: UUID = UUID()
    var date: Date = Date()
    var pounds: Double = 0
    var sourceRaw: String = Source.manual.rawValue

    init(date: Date, pounds: Double, source: Source) {
        self.date = date
        self.pounds = pounds
        self.sourceRaw = source.rawValue
    }

    var source: Source { Source(rawValue: sourceRaw) ?? .manual }
}

// MARK: - Container

enum Store {
    static let schema = Schema([
        Block.self, PlannedSession.self, SavedRoutine.self, WeightEntry.self,
        LoggedSet.self, MovePreference.self, MorningPractice.self,
        RoutineRun.self, CustomMove.self, MoveOverride.self, SetLog.self
    ])

    /// Local-first, synced through the user's own private CloudKit database.
    /// No server of ours, and the watch app reads the same store.
    ///
    /// If the container fails to open we fall back to a local store rather than
    /// crashing: a signed-out iCloud account or a provisioning problem should
    /// cost you sync, not the ability to run a workout.
    ///
    /// Sync is behind `CLOUDKIT_SYNC` because that fallback cannot catch the
    /// failure that matters. Handed a container the process is not entitled to,
    /// CloudKit traps inside CoreData's mirroring delegate on its own queue —
    /// `try?` never sees it and the app dies at launch. iOS gives an app no
    /// supported way to read its own entitlements, so whether this build is
    /// provisioned for sync has to be stated at build time. Turn the flag on
    /// once the team, bundle identifier and iCloud container are real; until
    /// then the app runs local-only, which is the intended degradation anyway.
    @MainActor
    static func container(inMemory: Bool = false) -> ModelContainer {
        #if CLOUDKIT_SYNC
        if !inMemory {
            let synced = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false,
                cloudKitDatabase: .private(cloudKitContainerIdentifier)
            )
            if let container = try? ModelContainer(for: schema, configurations: synced) {
                return container
            }
        }
        #endif

        let local = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: inMemory,
            cloudKitDatabase: .none
        )
        if let container = try? ModelContainer(for: schema, configurations: local) {
            return container
        }

        // Neither store would open. There is no sensible way to continue.
        fatalError("Could not open the store, synced or local.")
    }

    static let cloudKitContainerIdentifier = "iCloud.com.wrktime.app"
}
