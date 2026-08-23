import Foundation

/// What sort of movement this is.
///
/// Strength work and flow work want opposite things from a timer. A split squat
/// is a set: forty seconds of effort against a rest. A spinal wave or a round
/// of arm swings is a *practice* — continuous, unhurried, and ruined by being
/// counted down at. Without this distinction the planner would happily drop a
/// lymphatic bounce into a work interval and cue it like a deadlift.
enum MoveKind: String, Codable, Sendable, CaseIterable {
    case strength
    case flow
    /// The walking pad. A third kind rather than a filter written out at each
    /// site, for the same reason `.flow` is one.
    ///
    /// Her words: *"40 seconds of an incline walk or zone 2 walk isn't going to
    /// do anything and will take longer to set up the treadmill."* The pad was
    /// `.strength` by default, so it was rotation-eligible everywhere — the
    /// planner's move enum offered it, the picker listed it, and
    /// `MoveLibrary.rotation` could put it in an extra session. A work interval
    /// is the wrong unit for walking entirely.
    ///
    /// Walking already has its own place: a weekly minutes target the planner
    /// sets, drawn on Signals and read back from Health. Four filters already
    /// ask `kind == .strength`, so naming this excludes the pad from all of
    /// them at once rather than adding a fifth thing to remember.
    case walk

    var label: String {
        switch self {
        case .strength: "Strength"
        case .flow: "Flow"
        case .walk: "Walking"
        }
    }
}

/// How a move that cannot be done all at once divides.
///
/// Her ask, in her words: moves "that need to be done on both sides/both ways
/// should have a double timer situation in the session so were getting the full
/// time on each side." So a sided move takes one full work interval per side —
/// the second side is added to the session, never carved out of the first.
enum Sided: String, Codable, Sendable {
    /// One leg or arm at a time — a lunge, a split squat.
    case sides
    /// One direction and then the other — a halo, a circle.
    case directions

    /// What each of the two work intervals is called.
    var labels: (first: String, second: String) {
        switch self {
        case .sides: ("Left side", "Right side")
        case .directions: ("One way", "Other way")
        }
    }
}

/// A movement the user can actually do with the kit they own.
struct Move: Identifiable, Hashable, Codable {
    var id: UUID = UUID()
    var name: String
    var equipment: Equipment
    /// One line of form, in plain words. Shown under the name while working.
    var cue: String
    /// The load this move is written for, where the equipment offers a choice.
    ///
    /// The rings are three different weights, so "the 8 lb ring" in a cue has
    /// to be a fact the app knows rather than a sentence it happens to print —
    /// otherwise logging that move would offer the wrong weight by default.
    var loadPounds: Double?

    /// Optional on purpose. Routines are stored as JSON in `PlannedSession`,
    /// `SavedRoutine` and `ActiveSession`, and Swift's synthesized decoder
    /// *throws* on a missing non-optional key rather than using its default —
    /// so adding this as non-optional would have made every routine already on
    /// disk undecodable. Optional decodes as nil and reads as `.strength`.
    var kindRaw: MoveKind?

    /// Set when the move is done one side or one direction at a time.
    /// Optional for the same reason `kindRaw` is; nil means the move is done
    /// all at once.
    var sidedRaw: String?

    /// The movement this is a variant of (`MovementCatalog`), stored so a
    /// variant can one day be renamed without losing what it was. Optional
    /// for the reason every stored addition is; nil is read back through
    /// the catalog by name, which is how every routine on disk today works.
    var movementID: String?

    var kind: MoveKind { kindRaw ?? .strength }
    var sided: Sided? { sidedRaw.flatMap(Sided.init(rawValue:)) }
    /// The movement, from the stored id or the catalog by name.
    var movement: Movement? {
        if let movementID, let found = MovementCatalog.byID[movementID] { return found }
        return MovementCatalog.movement(for: name)
    }

    init(id: UUID = UUID(), name: String, equipment: Equipment, kind: MoveKind = .strength,
         cue: String, loadPounds: Double? = nil, sided: Sided? = nil) {
        self.id = id
        self.name = name
        self.equipment = equipment
        self.cue = cue
        self.loadPounds = loadPounds
        self.kindRaw = kind
        self.sidedRaw = sided?.rawValue
    }

    var symbol: String { equipment.symbol }
    /// Names the one thing this move needs, not the whole drawer. A move using
    /// the 10 lb ring says so; it does not list all three rings.
    var equipmentLabel: String { equipment.label(forLoad: loadPounds) }
}

/// One stretch of a hand-built sequence.
///
/// A routine can be a fixed shape — so many rounds of so much work against so
/// much rest — or a written-out sequence where every interval is its own
/// length. The second is what "30 on, 30 rest, 20 on, 15 rest, 10 on, 10 on,
/// 10 on, 30 rest" needs, and note that it has three work intervals in a row:
/// a step says what it is, so nothing here assumes work and rest alternate.
struct IntervalStep: Identifiable, Hashable, Codable, Sendable {
    var id: UUID = UUID()
    var isWork: Bool
    var seconds: TimeInterval

    static func work(_ seconds: TimeInterval) -> IntervalStep {
        IntervalStep(isWork: true, seconds: seconds)
    }
    static func rest(_ seconds: TimeInterval) -> IntervalStep {
        IntervalStep(isWork: false, seconds: seconds)
    }

    /// The same ceiling the fixed shape has, enforced here so a sequence cannot
    /// route around it.
    var clamped: TimeInterval {
        isWork ? min(seconds, IntervalRoutine.workCeiling) : max(seconds, 0)
    }
}

/// How a session is worked, from `docs/COACH-BRIEF.md` §5. Three, and they
/// are not interchangeable.
enum SessionMode: String, Codable, CaseIterable, Hashable {
    /// Timed work against timed rest, every turn through the rotation a
    /// round. Conditioning, in the brief's word — the heart more than the
    /// muscle. The default, and what every routine stored before the mode
    /// existed is.
    case intervals
    /// Straight sets: every set of a move, then the next move. A set is open
    /// until she ends it, capped as a safety net; rest between sets comes
    /// from the move's pattern, rest between moves is flat plus the setup
    /// buffer. The base of the week, and the only mode a step-up can be
    /// earned in.
    case reps
    /// Every minute on the minute, one hard set of one move, the rotation in
    /// turn. The set has the first part of the minute and the rest is rest;
    /// the clock never shifts, so the minute stays on the minute.
    case emom

    var label: String {
        switch self {
        case .intervals: "Intervals"
        case .reps: "Sets"
        case .emom: "EMOM"
        }
    }

    /// One line of what the mode is for, said honestly.
    var note: String {
        switch self {
        case .intervals: "Timed work, timed rest, as many tidy reps as the interval holds. This is for the heart more than the muscle."
        case .reps: "Three sets of a move, then the next. A set ends when you end it — eight to twelve reps, stopping a couple short of failure."
        case .emom: "One crisp set at the top of every minute, then rest until the next. Three to five reps, not to the limit; if they take longer than twenty-five seconds, the load is wrong, not the rest."
        }
    }
}

/// A self-guided interval routine: fixed work and rest, a rotation of moves,
/// and a number of rounds. This is also the shape the planner emits, so a
/// generated session and a hand-built one run through the same engine.
///
/// A routine may have **no moves at all**. That is not an unfinished routine —
/// it is a plain interval timer, which is sometimes the only thing wanted, and
/// the schedule handles it by leaving the move on each phase nil.
struct IntervalRoutine: Identifiable, Hashable, Codable {
    var id: UUID = UUID()
    var name: String
    var work: TimeInterval
    var rest: TimeInterval
    var rounds: Int
    var moves: [Move]
    /// The rest after the final round is pointless — you've finished. Dropping
    /// it is the default because it makes the stated total honest.
    var dropsFinalRest: Bool = true

    /// The flow practice that opens the session, before round one.
    ///
    /// Optional for the same reason `Move.kindRaw` is: routines are already on
    /// disk as JSON without these keys, and Swift's synthesized decoder throws
    /// on a missing non-optional key rather than falling back to the property's
    /// default. A non-optional array here would have made every stored routine
    /// undecodable at a stroke.
    var warmUpMoves: [Move]?
    var warmUpSecondsRaw: TimeInterval?

    /// A written-out sequence, when the routine is not a fixed shape.
    ///
    /// Optional for the same reason the warm-up is: routines are on disk as
    /// JSON without this key, and the synthesized decoder throws on a missing
    /// non-optional one. Empty and nil both mean "use work, rest and rounds".
    var steps: [IntervalStep]?

    /// How many times the written-out cadence runs.
    ///
    /// Her ask: *"i want to be able to say repeat this cadence for x rounds
    /// without having to set 6 things x more times."* Writing 30/30, 20/20,
    /// 10/10 and then wanting it four times over meant twenty-four steppers.
    ///
    /// Optional for the reason every field added to a stored routine is: these
    /// are JSON on disk and the synthesized decoder *throws* on a missing
    /// non-optional key, so a non-optional here would make every routine
    /// already saved undecodable. Nil reads as one pass.
    var sequenceRepeatsRaw: Int?

    /// The session mode. Optional, like every field added to a stored
    /// routine: the decoder throws on a missing non-optional key. Nil reads
    /// as `.intervals`, which is what every routine on disk before the mode
    /// existed was.
    var modeRaw: String?
    /// Sets per move in `.reps`; nil reads as `Self.defaultSets`.
    var setsPerMoveRaw: Int?

    var mode: SessionMode { modeRaw.flatMap(SessionMode.init(rawValue:)) ?? .intervals }
    /// What a work interval is called in this mode — the header's "Round 3 /
    /// 8" is "Set 3 / 12" in reps mode and "Minute 3 / 12" on the minute.
    var roundWord: String {
        switch mode {
        case .intervals: "Round"
        case .reps: "Set"
        case .emom: "Minute"
        }
    }
    var setsPerMove: Int { max(setsPerMoveRaw ?? Self.defaultSets, 1) }

    static let defaultSets = 3
    /// A rep set is open until she ends it; this is the net under it. Twelve
    /// reps at a 3-1-1 tempo runs sixty to seventy-five seconds with the
    /// resets, so the net sits well above that: a set still running at a
    /// hundred is a forgotten tap, not a set. Deliberately above the
    /// interval ceiling — a set is not an interval.
    static let repSetCeiling: TimeInterval = 100
    /// The working part of an EMOM minute. Eight reps in twenty-five seconds
    /// leaves thirty-five to rest, which is the point of the mode.
    static let emomWorkSeconds: TimeInterval = 25
    static let emomMinute: TimeInterval = 60
    /// Rest between moves in `.reps`, before the setup buffer — flat, because
    /// moving to another pattern is partly recovery in itself. After a big
    /// lower lift it is the lift's own rest instead.
    static let betweenMovesSeconds = 20

    /// "8 rounds · 13:10", "3 sets × 5 moves · 24:10", "12 minutes on the
    /// minute · 11:25" — the one line every surface uses to say the shape,
    /// so Today, the extras and the builder cannot describe a set session
    /// in rounds.
    var shapeLine: String {
        let length = totalDuration.durationString
        switch mode {
        case .reps:
            let n = moves.count
            return "\(setsPerMove) \(setsPerMove == 1 ? "set" : "sets") × \(n) \(n == 1 ? "move" : "moves") · \(length)"
        case .emom:
            return "\(rounds) minutes on the minute · \(length)"
        case .intervals:
            return "\(roundCount) \(roundCount == 1 ? "round" : "rounds") · \(length)"
        }
    }

    /// What a rotation row says a move will take: "40s ×3", "3 sets × 8–12",
    /// "25s ×2" on the minute — with "each side" where the move is sided.
    func rowMeasure(for move: Move) -> String {
        let base: String
        switch mode {
        case .reps: base = "\(setsPerMove) sets × 8–12"
        case .emom:
            let turns = max(rounds / max(RoutineSchedule.sidedCycle(of: moves).count, 1), 1)
            base = "\(Int(Self.emomWorkSeconds))s ×\(turns)"
        case .intervals:
            let turns = rounds / max(moves.count, 1)
            base = "\(Int(clampedWork))s ×\(turns)"
        }
        guard let sided = move.sided else { return base }
        return base + (sided == .directions ? " each way" : " each side")
    }

    /// The same routine in another mode.
    func inMode(_ mode: SessionMode, sets: Int? = nil) -> IntervalRoutine {
        var copy = self
        copy.modeRaw = mode == .intervals ? nil : mode.rawValue
        copy.setsPerMoveRaw = mode == .reps ? sets ?? setsPerMoveRaw : nil
        return copy
    }

    var sequence: [IntervalStep] { steps ?? [] }
    var isSequence: Bool { !sequence.isEmpty }
    /// At least one, however the stored value got there.
    var sequenceRepeats: Int { max(sequenceRepeatsRaw ?? 1, 1) }

    /// How many work intervals this routine holds, however it is shaped. The
    /// header counts against this, so "Round 3 / 7" is true of a sequence too.
    ///
    /// For the fixed shape this counts the sided expansion: a turn on a move
    /// done one side at a time is two work intervals, and every surface that
    /// reads this — the header, the haptics, the completion figure — must
    /// agree with the schedule about how many there are.
    var roundCount: Int {
        if isSequence { return sequence.filter(\.isWork).count * sequenceRepeats }
        // Every set of every move, sides counted, is a work interval.
        if mode == .reps {
            return RoutineSchedule.sidedCycle(of: moves).count * setsPerMove
        }
        // A minute is a minute: a sided move takes one minute per side, and
        // `rounds` already counts minutes.
        if mode == .emom { return rounds }
        guard rounds > 0, !moves.isEmpty else { return rounds }
        return (1...rounds).reduce(0) { count, turn in
            count + (moves[(turn - 1) % moves.count].sided != nil ? 2 : 1)
        }
    }

    var warmUp: [Move] { warmUpMoves ?? [] }
    /// How long each flow movement runs. Longer than a work interval on
    /// purpose: this is a practice, and forty seconds of arm swings is barely
    /// enough to stop rushing them.
    var warmUpSeconds: TimeInterval { warmUpSecondsRaw ?? WarmUp.seconds }

    /// The ceiling the user asked for. Enforced at the model layer rather than
    /// in the UI, so nothing downstream can exceed it.
    static let workCeiling: TimeInterval = 60

    var clampedWork: TimeInterval { min(work, Self.workCeiling) }

    /// The same routine as a written-out sequence, optionally repeated.
    func following(_ steps: [IntervalStep], repeats: Int = 1) -> IntervalRoutine {
        var copy = self
        copy.steps = steps.isEmpty ? nil : steps
        copy.sequenceRepeatsRaw = steps.isEmpty ? nil : max(repeats, 1)
        return copy
    }

    /// A name derived from what the routine is — "Rings · 8 × 40/45",
    /// "Flow · 6 movements" — for rows that were saved as "Untitled" before
    /// the builder learned to do this itself. An almanac names real things.
    var derivedName: String {
        if rounds == 0, moves.isEmpty, !warmUp.isEmpty {
            return warmUp.count == 1 ? "Flow · 1 movement" : "Flow · \(warmUp.count) movements"
        }
        let shape: String
        switch mode {
        case .reps: shape = "\(setsPerMove) sets × \(moves.count)"
        case .emom: shape = "EMOM \(rounds)"
        case .intervals:
            shape = isSequence
                ? "\(sequence.count) \(sequence.count == 1 ? "interval" : "intervals")"
                : "\(rounds) × \(Int(clampedWork))/\(Int(rest))"
        }
        guard let kit = moves.first?.equipment else { return "Timer · \(shape)" }
        let single = moves.allSatisfy { $0.equipment == kit }
        return "\(single ? kit.shortLabel : "Mixed") · \(shape)"
    }

    /// The same routine with `sided` stamped from the library onto moves
    /// stored before the flag existed.
    ///
    /// Stored routines are JSON written by whatever build wrote them, so a
    /// week planned before sidedness would run its split squat as one
    /// unlabelled interval while a new week runs two — the same move meaning
    /// two different things depending on when it was written. Same precedent
    /// as `PlanRepair`: what is already written is brought up to what the
    /// library now knows. Applied where stored routines are read back — never
    /// to an interrupted run, whose saved schedule must stay exactly the one
    /// she is resumed into.
    func adoptingLibrarySidedness() -> IntervalRoutine {
        var copy = self
        copy.moves = moves.map { move in
            guard move.sidedRaw == nil,
                  let known = MoveLibrary.all.first(where: {
                      MovePreference.key($0.name) == MovePreference.key(move.name)
                  }),
                  known.sidedRaw != nil
            else { return move }
            var move = move
            move.sidedRaw = known.sidedRaw
            return move
        }
        return copy
    }

    /// The same routine with a flow practice on the front.
    func warmingUp(with moves: [Move], seconds: TimeInterval = WarmUp.seconds) -> IntervalRoutine {
        var copy = self
        copy.warmUpMoves = moves.isEmpty ? nil : moves
        copy.warmUpSecondsRaw = moves.isEmpty ? nil : seconds
        return copy
    }

    var totalDuration: TimeInterval {
        schedule.total
    }

    var schedule: RoutineSchedule { RoutineSchedule(routine: self) }
}

// MARK: - Schedule

/// One stretch of the routine — a flow movement, a work interval, or the rest
/// after it.
struct Phase: Equatable {
    /// `flow` is a third kind rather than a work interval with a flag, because
    /// almost everything the app does at a boundary asks this question: the
    /// field holds still through flow, no countdown is cued into it, and it is
    /// not a round. A boolean would have had to be checked in all of those
    /// places and would have been forgotten in one.
    enum Kind: Equatable { case flow, work, rest }

    let kind: Kind
    /// 1-based, for display. Counts rounds for work and rest; counts position
    /// in the practice for flow.
    let round: Int
    let move: Move?
    /// "Left side", "Other way" — set on the work intervals of a sided move,
    /// so every surface reading this phase says which side it is.
    var side: String? = nil
    /// A rep set: the phase runs to `duration` only as a net, and she is
    /// expected to end it herself. The field holds still rather than rising
    /// with a clock that means nothing.
    var openEnded: Bool = false
    /// "Set 2 of 3" on a work phase in `.reps`, so the screen and the lock
    /// screen say the same thing about where in the move she is.
    var setLabel: String? = nil
    let duration: TimeInterval
    /// Seconds from routine start at which this phase begins and ends.
    let start: TimeInterval
    let end: TimeInterval

    var isWork: Bool { kind == .work }
    var isFlow: Bool { kind == .flow }
    var isRest: Bool { kind == .rest }

    /// "Round 3 / 8", or "Warm-up 2 / 4" during the practice.
    ///
    /// Lives on the phase rather than in each view because the screen and the
    /// lock screen must never be able to disagree about where the session is —
    /// they are the same session read in two places.
    func position(rounds: Int, flowCount: Int, word: String = "Round") -> String {
        guard isFlow else { return "\(word) \(round) / \(rounds)" }
        // A routine with no rounds is the morning practice, not a warm-up for
        // something else. Calling it a warm-up would name it after work that is
        // not coming.
        let label = rounds > 0 ? "Warm-up" : "Movement"
        return "\(label) \(round) / \(max(flowCount, round))"
    }
}

/// The routine flattened into an ordered list of phases with absolute offsets.
///
/// Everything about progress is derived from elapsed time against these
/// offsets rather than by accumulating per-tick decrements, so the clock cannot
/// drift no matter how irregular the ticks are.
struct RoutineSchedule: Equatable {
    let phases: [Phase]
    let total: TimeInterval

    init(routine: IntervalRoutine) {
        var built: [Phase] = []
        var cursor: TimeInterval = 0
        let work = routine.clampedWork
        let moves = routine.moves

        // The practice comes first, and it runs continuously — no rest between
        // one movement and the next. A rest interval inside a flow would be the
        // countdown logic reasserting itself over something that is meant to be
        // unhurried.
        let flowLength = routine.warmUpSeconds
        for (position, move) in routine.warmUp.enumerated() where flowLength > 0 {
            built.append(Phase(kind: .flow, round: position + 1, move: move,
                               duration: flowLength, start: cursor, end: cursor + flowLength))
            cursor += flowLength
        }

        // Time to get the kit out, when work follows the warm-up. The flow
        // runs empty-handed and round one usually does not; a rest phase
        // between them is the register that already does this job — it shows
        // "Next up" with the first move, asks for no reps because no set
        // precedes it, and is not a round. The morning practice never gets
        // one: all flow, nothing to set up for.
        let opensWork = routine.isSequence
            ? routine.sequence.contains { $0.isWork && $0.clamped > 0 }
            : routine.mode == .reps ? !moves.isEmpty : routine.rounds > 0
        if !built.isEmpty, opensWork {
            let setup = WarmUp.setupSeconds
            built.append(Phase(kind: .rest, round: 1, move: nil,
                               duration: setup, start: cursor, end: cursor + setup))
            cursor += setup
        }

        // A written-out sequence: every interval its own length, in the order
        // she wrote them, with no assumption that work and rest alternate.
        // Moves are taken from the rotation in turn as work intervals arrive,
        // exactly as rounds do.
        if routine.isSequence {
            var round = 0
            // A sided move claims two of the work steps she wrote — one per
            // side — rather than adding steps she did not ask for. Her
            // sequence's shape is hers; only the move assignment expands.
            let cycle = Self.sidedCycle(of: moves)
            // The cadence, however many times she asked for it. Rounds keep
            // counting across passes rather than restarting, so "Round 7 / 12"
            // is true of a three-work cadence run four times.
            for _ in 0..<routine.sequenceRepeats {
                for step in routine.sequence {
                    let length = step.clamped
                    guard length > 0 else { continue }
                    if step.isWork {
                        round += 1
                        let slot = cycle.isEmpty ? nil : cycle[(round - 1) % cycle.count]
                        built.append(Phase(kind: .work, round: round, move: slot?.move,
                                           side: slot?.side,
                                           duration: length, start: cursor, end: cursor + length))
                    } else {
                        built.append(Phase(kind: .rest, round: max(round, 1), move: nil,
                                           duration: length, start: cursor, end: cursor + length))
                    }
                    cursor += length
                }
            }
            phases = built
            total = cursor
            return
        }

        // Straight sets, `docs/COACH-BRIEF.md` §5 and §7. Every set of a move
        // in turn, sides back to back; the move's own rest between its sets;
        // then the flat rest plus the setup buffer before the next move,
        // shown as "Next up" so she knows what to fetch. The final rest is
        // dropped as in every shape — she has finished.
        if routine.mode == .reps {
            // Sets of nothing are nothing: a set routine without moves has
            // no work, not a timer-only shape borrowed from intervals.
            guard !moves.isEmpty else { phases = built; total = cursor; return }
            var round = 0
            for (position, move) in moves.enumerated() {
                let pattern = MoveTaxonomy.pattern(for: move.name)
                let setRest = TimeInterval(pattern?.restSeconds ?? MovePattern.accessory.restSeconds)
                let sides: [String?] = move.sided.map { [$0.labels.first, $0.labels.second] } ?? [nil]
                for set in 1...routine.setsPerMove {
                    for side in sides {
                        round += 1
                        let cap = IntervalRoutine.repSetCeiling
                        built.append(Phase(kind: .work, round: round, move: move, side: side,
                                           openEnded: true,
                                           setLabel: "Set \(set) of \(routine.setsPerMove)",
                                           duration: cap, start: cursor, end: cursor + cap))
                        cursor += cap
                    }
                    let lastSet = set == routine.setsPerMove
                    let lastMove = position == moves.count - 1
                    if lastSet && lastMove { break }
                    let next = lastSet ? moves[position + 1] : nil
                    var rest: TimeInterval
                    if let next {
                        // Between moves: the big lift keeps its own rest,
                        // everything else the flat thirty, and the setup
                        // buffer on top — separate numbers, added here.
                        let between = (pattern?.isBigLift ?? false)
                            ? setRest : TimeInterval(IntervalRoutine.betweenMovesSeconds)
                        rest = between + TimeInterval(MoveTaxonomy.setupSeconds(from: move, to: next))
                    } else {
                        rest = setRest
                    }
                    built.append(Phase(kind: .rest, round: round, move: next,
                                       duration: rest, start: cursor, end: cursor + rest))
                    cursor += rest
                }
            }
            phases = built
            total = cursor
            return
        }

        // Every minute on the minute: `rounds` minutes, the rotation in turn,
        // one set in the first part of each minute and the remainder to rest.
        // No phase is open-ended — the clock is the whole idea — and the last
        // minute's rest is dropped like every final rest.
        if routine.mode == .emom, routine.rounds > 0 {
            let cycle = Self.sidedCycle(of: moves)
            for minute in 1...routine.rounds {
                let slot = cycle.isEmpty ? nil : cycle[(minute - 1) % cycle.count]
                let work = IntervalRoutine.emomWorkSeconds
                built.append(Phase(kind: .work, round: minute, move: slot?.move, side: slot?.side,
                                   duration: work, start: cursor, end: cursor + work))
                cursor += work
                guard minute < routine.rounds else { break }
                let rest = IntervalRoutine.emomMinute - work
                let next = cycle.isEmpty ? nil : cycle[minute % cycle.count].move
                built.append(Phase(kind: .rest, round: minute, move: next,
                                   duration: rest, start: cursor, end: cursor + rest))
                cursor += rest
            }
            phases = built
            total = cursor
            return
        }

        // A routine may be nothing but its practice — that is the morning
        // ritual, eight flow movements and no rounds at all. Without this the
        // schedule would invent a work interval to satisfy `max(rounds, 1)`.
        guard routine.rounds > 0 else {
            phases = built
            total = cursor
            return
        }

        // `rounds` counts turns through the rotation; a sided turn becomes two
        // full work intervals, one per side. The second side is added to the
        // session — never carved out of the first, and never a round removed
        // from anyone else.
        var slots: [(move: Move?, side: String?)] = []
        for turn in 1...routine.rounds {
            guard let move = moves.isEmpty ? nil : moves[(turn - 1) % moves.count] else {
                slots.append((nil, nil))
                continue
            }
            if let sided = move.sided {
                slots.append((move, sided.labels.first))
                slots.append((move, sided.labels.second))
            } else {
                slots.append((move, nil))
            }
        }

        for (index, slot) in slots.enumerated() {
            let round = index + 1
            built.append(Phase(kind: .work, round: round, move: slot.move, side: slot.side,
                               duration: work, start: cursor, end: cursor + work))
            cursor += work

            let isLast = index == slots.count - 1
            if !(isLast && routine.dropsFinalRest), routine.rest > 0 {
                built.append(Phase(kind: .rest, round: round, move: nil,
                                   duration: routine.rest, start: cursor, end: cursor + routine.rest))
                cursor += routine.rest
            }
        }

        phases = built
        total = cursor
    }

    /// The rotation with every sided move expanded to one entry per side, in
    /// order. One definition — the fixed shape, the sequence and `roundCount`
    /// must agree on it exactly.
    static func sidedCycle(of moves: [Move]) -> [(move: Move, side: String?)] {
        moves.flatMap { move -> [(move: Move, side: String?)] in
            guard let sided = move.sided else { return [(move, nil)] }
            return [(move, sided.labels.first), (move, sided.labels.second)]
        }
    }

    /// The phase containing `elapsed`, or nil once the routine is over.
    func index(atElapsed elapsed: TimeInterval) -> Int? {
        guard elapsed >= 0, elapsed < total else { return nil }
        // Phases are short and few; a linear scan is faster than a binary
        // search here and far easier to reason about.
        return phases.firstIndex { elapsed < $0.end }
    }

    /// Offset at which a given phase begins — used when skipping.
    func start(of index: Int) -> TimeInterval {
        guard phases.indices.contains(index) else { return total }
        return phases[index].start
    }

    var workPhaseCount: Int { phases.filter(\.isWork).count }

    /// Which set a phase is, counting work intervals only — the index reps are
    /// filed under. Nil for a rest or a flow movement, which are not sets.
    ///
    /// One definition, because three places need to agree on it: the screen
    /// filing a number during the rest that follows a set, the record that
    /// stores them, and the summary that reads them back out.
    func setOrdinal(of index: Int) -> Int? {
        guard phases.indices.contains(index), phases[index].isWork else { return nil }
        return phases[..<index].filter(\.isWork).count
    }

    /// The set the rest at `index` follows, if it follows one.
    func setEnding(before index: Int) -> Int? {
        guard phases.indices.contains(index) else { return nil }
        let earlier = phases[..<index].filter(\.isWork).count
        return earlier > 0 ? earlier - 1 : nil
    }
    var flowPhaseCount: Int { phases.filter(\.isFlow).count }

    /// Where round one starts. The header reads "Warm-up 2 / 4" before this and
    /// "Round 3 / 8" after it.
    var workBegins: TimeInterval { phases.first(where: \.isWork)?.start ?? 0 }
}
