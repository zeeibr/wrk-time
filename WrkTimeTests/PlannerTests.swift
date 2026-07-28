import Testing
import Foundation
import SwiftData
@testable import WrkTime

private func draft(_ moves: [DraftMove],
                   work: Int = 40, rest: Int = 45, rounds: Int = 8, day: Int = 0) -> PlanDraft {
    PlanDraft(explanation: "x",
              sessions: [DraftSession(dayOffset: day, title: "Test",
                                      work: work, rest: rest, rounds: rounds, moves: moves)])
}

/// A draft move for the given kit and load, named after a real library move.
///
/// It used to be called "Move". The library is closed now — a name outside it
/// is rejected before any other check — so a placeholder name would make every
/// one of these tests fail for the wrong reason.
private func move(_ equipment: Equipment, _ pounds: Double) -> DraftMove {
    let name = MoveLibrary.all.first { $0.equipment == equipment }?.name ?? "Dead bug"
    return DraftMove(name: name, equipment: equipment.rawValue, cue: "Cue", loadPounds: pounds)
}

@Suite("Plan validation")
struct PlanValidatorTests {

    @Test("Accepts every load the kit can actually be set to")
    func realLoads() throws {
        for equipment in Equipment.allCases {
            for pounds in equipment.availableLoadsPounds {
                _ = try PlanValidator.routines(from: draft([move(equipment, pounds)]))
            }
        }
    }

    // The rings are three different weights, not a matched set. A planner that
    // assumes a uniform ring load produces a session she cannot do, and this is
    // the only thing standing between that and her Tuesday.
    @Test("Rejects a ring weight that does not exist", arguments: [3.0, 7.0, 12.0, 15.0])
    func impossibleRingLoad(pounds: Double) {
        #expect(throws: PlanValidator.Failure.self) {
            try PlanValidator.routines(from: draft([move(.rings, pounds)]))
        }
    }

    @Test("Rejects the beam set to anything but 15")
    func impossibleBeamLoad() {
        #expect(throws: PlanValidator.Failure.self) {
            try PlanValidator.routines(from: draft([move(.beam, 25)]))
        }
    }

    @Test("Rejects equipment that does not exist")
    func unknownEquipment() {
        let barbell = DraftMove(name: "Back squat", equipment: "barbell", cue: "", loadPounds: 95)
        #expect(throws: PlanValidator.Failure.self) {
            try PlanValidator.routines(from: draft([barbell]))
        }
    }

    @Test("Rejects a load on something that loads nothing")
    func loadOnBodyweight() {
        #expect(throws: PlanValidator.Failure.self) {
            try PlanValidator.routines(from: draft([move(.bodyweight, 10)]))
        }
        #expect(throws: PlanValidator.Failure.self) {
            try PlanValidator.routines(from: draft([move(.walkingPad, 5)]))
        }
    }

    @Test("Holds the 60-second work ceiling")
    func workCeiling() throws {
        _ = try PlanValidator.routines(from: draft([move(.beam, 15)], work: 60))
        #expect(throws: PlanValidator.Failure.self) {
            try PlanValidator.routines(from: draft([move(.beam, 15)], work: 61))
        }
    }

    @Test("Rejects nonsense timing and empty weeks")
    func nonsense() {
        #expect(throws: PlanValidator.Failure.self) {
            try PlanValidator.routines(from: draft([move(.beam, 15)], work: 0))
        }
        #expect(throws: PlanValidator.Failure.self) {
            try PlanValidator.routines(from: draft([move(.beam, 15)], rounds: 0))
        }
        #expect(throws: PlanValidator.Failure.self) {
            try PlanValidator.routines(from: draft([move(.beam, 15)], day: 7))
        }
        #expect(throws: PlanValidator.Failure.self) {
            try PlanValidator.routines(from: draft([]))
        }
        #expect(throws: PlanValidator.Failure.self) {
            try PlanValidator.routines(from: PlanDraft(explanation: "x", sessions: []))
        }
    }

    @Test("A rejected week is rejected whole, not silently trimmed")
    func rejectsWhole() {
        // One good session and one impossible one. Keeping the good half would
        // hand her a week the planner never wrote.
        let mixed = PlanDraft(explanation: "x", sessions: [
            DraftSession(dayOffset: 0, title: "Good", work: 40, rest: 45, rounds: 8,
                         moves: [move(.beam, 15)]),
            DraftSession(dayOffset: 2, title: "Bad", work: 40, rest: 45, rounds: 8,
                         moves: [move(.rings, 7)])
        ])
        #expect(throws: PlanValidator.Failure.self) {
            try PlanValidator.routines(from: mixed)
        }
    }
}

@Suite("Offline planner")
struct OfflinePlannerTests {

    // The floor the whole app stands on. If this can emit a week the validator
    // refuses, there is no plan on a phone with no signal.
    @Test("Every week of every pace survives validation")
    func alwaysValid() throws {
        for pace in Pace.allCases {
            for week in 1...12 {
                let routines = try PlanValidator.routines(from: OfflinePlanner.week(week, pace: pace))
                #expect(routines.count == pace.sessionsPerWeek)
            }
        }
    }

    @Test("Schedules the pace's session count on distinct days inside the week")
    func days() {
        for pace in Pace.allCases {
            let days = OfflinePlanner.week(1, pace: pace).sessions.map(\.dayOffset)
            #expect(days.count == pace.sessionsPerWeek)
            #expect(Set(days).count == days.count, "no two sessions on one day")
            #expect(days.allSatisfy { (0...6).contains($0) })
        }
    }

    @Test("Rest days are spread, not stacked at the end")
    func restSpread() {
        for pace in Pace.allCases {
            let days = OfflinePlanner.week(1, pace: pace).sessions.map(\.dayOffset).sorted()
            // Three consecutive training days would mean the two rest days sit
            // together at the end of the week, which the brief rules out.
            let longestRun = days.reduce(into: (best: 1, run: 1, last: -2)) { state, day in
                state.run = day == state.last + 1 ? state.run + 1 : 1
                state.best = max(state.best, state.run)
                state.last = day
            }.best
            #expect(longestRun <= 2, "\(pace.label) trains \(longestRun) days running")
        }
    }

    @Test("Progresses by density and volume, never by load")
    func progression() {
        let early = OfflinePlanner.week(1, pace: .hard).sessions[0]
        let late = OfflinePlanner.week(12, pace: .hard).sessions[0]

        #expect(late.rest < early.rest, "rest must shorten")
        #expect(late.rounds > early.rounds, "rounds must climb at a hard pace")

        // The kit tops out at 15 lb, so a planner reaching for load stalls by
        // week three. Week twelve must not be asking for heavier equipment.
        let earlyLoad = early.moves.map(\.loadPounds).max() ?? 0
        let lateLoad = late.moves.map(\.loadPounds).max() ?? 0
        #expect(lateLoad <= max(earlyLoad, 15))
    }

    @Test("Rest never falls below the floor and work never passes the ceiling")
    func bounds() {
        for pace in Pace.allCases {
            for week in 1...52 {   // deliberately past the block, to test the clamps
                for session in OfflinePlanner.week(week, pace: pace).sessions {
                    #expect(session.rest >= OfflinePlanner.restFloor)
                    #expect(Double(session.work) <= IntervalRoutine.workCeiling)
                    #expect(session.rounds <= OfflinePlanner.roundCeiling)
                }
            }
        }
    }

    @Test("Says nothing rather than inventing a milestone on a repeat week")
    func voice() {
        // Steady progresses every third week, so week two is a repeat.
        let repeated = OfflinePlanner.week(2, pace: .steady).explanation
        #expect(repeated.contains("Same shape"))

        for pace in Pace.allCases {
            for week in 1...12 {
                let line = OfflinePlanner.week(week, pace: pace).explanation
                #expect(!line.contains("!"), "the app never exclaims")
                for banned in ["Crush", "Great job", "You've got this"] {
                    #expect(!line.contains(banned))
                }
            }
        }
    }
}

@Suite("Claude response handling")
struct ClaudePlannerTests {

    private func body(_ json: String) -> Data { Data(json.utf8) }

    @Test("Reads stop_reason before content, so a refusal does not crash")
    func refusalBeforeContent() {
        // A refusal is a successful HTTP 200 with an empty content array.
        // Indexing content[0] here is the standard way to crash on one.
        let refusal = body("""
        {"stop_reason":"refusal","stop_details":{"type":"refusal","category":"cyber"},"content":[]}
        """)
        #expect(throws: PlannerError.self) { try ClaudePlanner.decode(refusal) }
    }

    @Test("Treats a truncated answer as a failure rather than a partial week")
    func truncated() {
        let cut = body("""
        {"stop_reason":"max_tokens","content":[{"type":"text","text":"{\\"explanation\\":\\"a"}]}
        """)
        #expect(throws: PlannerError.self) { try ClaudePlanner.decode(cut) }
    }

    @Test("Finds the text block past an empty thinking block")
    func skipsThinking() throws {
        // Thinking is on by default on Opus 5 and display defaults to omitted,
        // so the first block is a thinking block with empty text.
        let response = body("""
        {"stop_reason":"end_turn","content":[
          {"type":"thinking","thinking":""},
          {"type":"text","text":"{\\"explanation\\":\\"Rest drops to 42 seconds.\\",\\"sessions\\":[{\\"dayOffset\\":0,\\"title\\":\\"Lower\\",\\"work\\":40,\\"rest\\":42,\\"rounds\\":8,\\"moves\\":[{\\"name\\":\\"Beam front squat\\",\\"equipment\\":\\"beam\\",\\"cue\\":\\"Slow.\\",\\"loadPounds\\":15}]}]}"}
        ]}
        """)
        let (draft, raw) = try ClaudePlanner.decode(response)
        #expect(!raw.isEmpty, "the raw text is threaded back for the repair turn")
        #expect(draft.sessions.count == 1)
        #expect(draft.sessions[0].moves[0].loadPounds == 15)
        _ = try PlanValidator.routines(from: draft)
    }

    @Test("Rejects a body that is not the agreed shape")
    func malformed() {
        #expect(throws: PlannerError.self) { try ClaudePlanner.decode(body("not json")) }
        #expect(throws: PlannerError.self) {
            try ClaudePlanner.decode(body("""
            {"stop_reason":"end_turn","content":[{"type":"text","text":"{\\"nope\\":1}"}]}
            """))
        }
    }

    @Test("Names the current model with no date suffix")
    func modelIdentifier() {
        #expect(ClaudePlanner.model == "claude-opus-5")
    }
}

@Suite("Weekly re-planning")
@MainActor
struct RePlanningTests {

    /// A block started `daysAgo` days ago, in an in-memory store.
    private func block(daysAgo: Int, pace: Pace = .building) -> (Block, ModelContext) {
        let container = Store.container(inMemory: true)
        let context = ModelContext(container)
        let start = Calendar.current.date(byAdding: .day, value: -daysAgo, to: .now)!
        let block = Block(startDate: start, goalWeightPounds: 150,
                          startingWeightPounds: 170, pace: pace)
        context.insert(block)
        return (block, context)
    }

    @Test("The current week comes from elapsed time, not from sessions done")
    func currentWeekFromCalendar() {
        #expect(block(daysAgo: 0).0.currentWeek == 1)
        #expect(block(daysAgo: 6).0.currentWeek == 1)
        #expect(block(daysAgo: 7).0.currentWeek == 2)
        #expect(block(daysAgo: 20).0.currentWeek == 3)
        // Clamped at the end rather than running on to week 30.
        #expect(block(daysAgo: 400).0.currentWeek == 12)
    }

    @Test("A block that has run its length is finished")
    func blockEnds() {
        #expect(!block(daysAgo: 83).0.hasEnded)
        #expect(block(daysAgo: 85).0.hasEnded)
    }

    // The gap this whole suite exists for: only week one was ever written, so
    // the block ran dry after seven days.
    @Test("Opening the app in an unplanned week writes that week")
    func plansTheCurrentWeek() async {
        let (block, context) = block(daysAgo: 14)   // week 3
        #expect(block.currentWeek == 3)
        #expect(!PlannerService.isPlanned(3, of: block))

        let outcome = await PlannerService.planCurrentWeekIfNeeded(for: block, in: context)
        let written = try! #require(outcome)
        #expect(written.sessionsWritten == block.pace.sessionsPerWeek)
        #expect(PlannerService.isPlanned(3, of: block))
    }

    @Test("Planning an already-planned week does nothing")
    func idempotent() async {
        let (block, context) = block(daysAgo: 0)
        _ = await PlannerService.planCurrentWeekIfNeeded(for: block, in: context)
        let sessionCount = block.sessions?.count ?? 0

        let second = await PlannerService.planCurrentWeekIfNeeded(for: block, in: context)
        #expect(second == nil, "a second pass must not rewrite the week")
        #expect(block.sessions?.count == sessionCount)
    }

    @Test("A finished block is not extended")
    func doesNotExtendPastTheEnd() async {
        let (block, context) = block(daysAgo: 90)
        let outcome = await PlannerService.planCurrentWeekIfNeeded(for: block, in: context)
        #expect(outcome == nil)
        #expect(block.sessions?.isEmpty ?? true)
    }

    @Test("Sessions land inside the week they were planned for")
    func sessionsLandInTheirWeek() async {
        let (block, context) = block(daysAgo: 21)   // week 4
        _ = await PlannerService.planCurrentWeekIfNeeded(for: block, in: context)

        let start = PlannerService.weekStart(4, of: block)
        let end = Calendar.current.date(byAdding: .day, value: 7, to: start)!
        for session in block.sessions ?? [] {
            #expect(session.scheduledFor >= start && session.scheduledFor < end)
        }
    }

    // Re-planning deletes what is unfinished and rewrites it. A session she
    // actually did is a record of something that happened, and rewriting it
    // would erase a mark off the growth form.
    @Test("Re-planning a week never touches a finished session")
    func keepsCompletedSessions() async {
        let (block, context) = block(daysAgo: 0)
        _ = await PlannerService.planCurrentWeekIfNeeded(for: block, in: context)

        let done = try! #require(block.sessions?.first)
        done.completedAt = .now
        let doneID = done.id

        // Force a rewrite of the same week.
        _ = await PlannerService.planWeek(1, of: block, in: context)

        #expect(block.sessions?.contains { $0.id == doneID && $0.isComplete } == true,
                "the finished session must survive a re-plan")
    }
}

// Serialized because the store's backing is `UserDefaults`, which is process
// -wide: run in parallel, the round-trip and the stale-drop tests clobber each
// other's key. The app has exactly one writer, so this is a property of the
// test harness rather than a hazard in the thing being tested.
@Suite("Move preferences")
@MainActor
struct MovePreferenceTests {

    private func store() -> ModelContext { ModelContext(Store.container(inMemory: true)) }

    // The point of the whole feature: saying you dislike push-ups has to cover
    // the incline and knee variants, because the planner invents those names.
    @Test("A dislike covers variants of the same movement")
    func familyMatching() {
        let context = store()
        MovePreferences.set(.disliked, for: "push-up", in: context)

        #expect(MovePreferences.verdict(for: "Push-up", in: context) == .disliked)
        #expect(MovePreferences.verdict(for: "Incline push-up", in: context) == .disliked)
        #expect(MovePreferences.verdict(for: "Knee push-up", in: context) == .disliked)
        #expect(MovePreferences.verdict(for: "Beam front squat", in: context) == nil)
    }

    @Test("Each reason records the verdict it should, and two record nothing")
    func reasonsMapToVerdicts() {
        #expect(SkipReason.hurt.verdict == .avoided)
        #expect(SkipReason.disliked.verdict == .disliked)
        #expect(SkipReason.tooHard.verdict == .hard)
        // Running out of time says nothing about the move, and neither does a
        // cluttered room. Recording either would quietly demote a move she likes.
        #expect(SkipReason.noTime.verdict == nil)
        #expect(SkipReason.noRoom.verdict == nil)
    }

    @Test("Recording a no-op reason leaves no opinion behind")
    func noOpReasons() {
        let context = store()
        MovePreferences.record(.noTime, for: "Ring deadlift", in: context)
        MovePreferences.record(.noRoom, for: "Ring deadlift", in: context)
        #expect(MovePreferences.verdict(for: "Ring deadlift", in: context) == nil)
    }

    // Pain is the one signal that must not be walked back by a milder one.
    @Test("Pain is sticky")
    func painIsSticky() {
        let context = store()
        MovePreferences.record(.hurt, for: "Beam deadlift", in: context)
        #expect(MovePreferences.verdict(for: "Beam deadlift", in: context) == .avoided)

        MovePreferences.record(.tooHard, for: "Beam deadlift", in: context)
        #expect(MovePreferences.verdict(for: "Beam deadlift", in: context) == .avoided,
                "a later, milder reason must not promote a painful move back in")
    }

    @Test("Repeated skips accumulate rather than overwrite")
    func skipsAccumulate() {
        let context = store()
        MovePreferences.record(.disliked, for: "Wall sit", in: context)
        MovePreferences.record(.disliked, for: "Wall sit", in: context)
        let preference = MovePreferences.all(in: context).first { $0.covers("Wall sit") }
        #expect(preference?.skipCount == 2)
    }

    @Test("An opinion can be withdrawn")
    func canBeCleared() {
        let context = store()
        MovePreferences.set(.avoided, for: "Split squat", in: context)
        MovePreferences.clear("Split squat", in: context)
        #expect(MovePreferences.verdict(for: "Split squat", in: context) == nil)
    }

    @Test("The offline planner substitutes a rejected move rather than serving it")
    func offlineSubstitutes() throws {
        // "Ring halo" is in the Upper template.
        let plain = OfflinePlanner.week(1, pace: .building)
        #expect(plain.sessions.flatMap(\.moves).contains { $0.name == "Ring halo" })

        let avoided = OfflinePlanner.week(1, pace: .building, avoiding: ["ring halo"])
        #expect(!avoided.sessions.flatMap(\.moves).contains { $0.name == "Ring halo" })
        // And the week is still a valid, full week.
        let routines = try PlanValidator.routines(from: avoided)
        #expect(routines.count == Pace.building.sessionsPerWeek)
        for session in avoided.sessions { #expect(session.moves.count == Tuning.movesPerSession) }
    }

    @Test("Substitution keeps the equipment it replaced")
    func substitutionKeepsEquipment() {
        let week = OfflinePlanner.week(1, pace: .building, avoiding: ["ring halo"])
        // The Upper session still uses the rings; only the movement changed.
        let upper = week.sessions.first { $0.title.contains("Upper") }
        #expect(upper?.moves.contains { $0.equipment == Equipment.rings.rawValue } == true)
    }

    @Test("Refusals reach the prompt as absolute and soft rules")
    func prompt() {
        var context = PlanContext(weekNumber: 2, pace: .building, recent: [], loggedSets: [])
        context.avoidedMoves = ["Push-up"]
        context.dislikedMoves = ["Wall sit"]
        let prompt = context.prompt

        #expect(prompt.contains("Never program these"))
        #expect(prompt.contains("Push-up"))
        #expect(prompt.contains("Wall sit"))
    }

    @Test("The engine remembers what was skipped, not just that something was")
    func engineRecordsSkips() {
        let routine = IntervalRoutine(
            name: "T", work: 40, rest: 20, rounds: 4,
            moves: [Move(name: "Alpha", equipment: .beam, cue: "", loadPounds: 15),
                    Move(name: "Beta", equipment: .beam, cue: "", loadPounds: 15)])
        let engine = IntervalEngine(routine: routine, autoTick: false)
        engine.start()

        #expect(engine.skippedMoves.isEmpty)
        engine.skip()
        #expect(engine.skippedMoves == ["Alpha"])
    }
}

@Suite("Walking target")
struct WalkingTests {

    private func draftWith(_ minutes: Int) -> PlanDraft {
        PlanDraft(explanation: "x",
                  sessions: [DraftSession(dayOffset: 0, title: "T", work: 40, rest: 45,
                                          rounds: 8, moves: [move(.beam, 15)])],
                  walkMinutes: minutes)
    }

    // Walking is the one number programmed toward the goal, so its bound is a
    // real limit rather than a sanity check. Five hours a week is where a plan
    // stops being one she can keep.
    @Test("Rejects a target past the ceiling")
    func ceiling() throws {
        _ = try PlanValidator.routines(from: draftWith(PlanValidator.walkCeiling))
        #expect(throws: PlanValidator.Failure.self) {
            try PlanValidator.routines(from: draftWith(PlanValidator.walkCeiling + 1))
        }
        #expect(throws: PlanValidator.Failure.self) {
            try PlanValidator.routines(from: draftWith(-1))
        }
    }

    @Test("The offline target climbs slowly and then holds")
    func offlineProgression() {
        #expect(OfflinePlanner.walkMinutes(week: 1) == OfflinePlanner.baseWalkMinutes)
        #expect(OfflinePlanner.walkMinutes(week: 2) > OfflinePlanner.walkMinutes(week: 1))

        // A beginner should never be handed a jump. Ten minutes a week.
        for week in 2...12 {
            let step = OfflinePlanner.walkMinutes(week: week) - OfflinePlanner.walkMinutes(week: week - 1)
            #expect(step <= OfflinePlanner.walkStep)
        }
        // And it stops climbing well before the validator's limit.
        #expect(OfflinePlanner.walkMinutes(week: 52) == OfflinePlanner.walkCap)
        #expect(OfflinePlanner.walkCap < PlanValidator.walkCeiling)
    }

    @Test("Every offline week's target survives validation")
    func offlineAlwaysValid() throws {
        for pace in Pace.allCases {
            for week in 1...12 {
                _ = try PlanValidator.routines(from: OfflinePlanner.week(week, pace: pace))
            }
        }
    }

    @Test("Walking is carried through the draft, not faked as a session")
    func notASession() {
        let draft = OfflinePlanner.week(3, pace: .building)
        #expect(draft.walkMinutes > 0)
        // A walk must never become a mark on the growth form.
        #expect(draft.sessions.count == Pace.building.sessionsPerWeek)
    }

    @Test("A missing walking history is not read as zero")
    func missingHistoryIsNotZero() {
        var context = PlanContext(weekNumber: 2, pace: .building, recent: [], loggedSets: [])
        context.recentWalkMinutes = nil
        #expect(context.prompt.contains("Do not read it as zero effort"))

        context.recentWalkMinutes = 90
        #expect(context.prompt.contains("90 minutes"))
    }

    @Test("The goal only reaches the prompt as a walking input")
    func goalFramedForWalkingOnly() {
        var context = PlanContext(weekNumber: 2, pace: .building, recent: [], loggedSets: [])
        context.poundsToGoal = 18
        let prompt = context.prompt
        #expect(prompt.contains("18 lb above a goal"))
        #expect(prompt.contains("leave the sessions alone"))
    }
}

@Suite("Interrupted sessions", .serialized)
struct ActiveSessionTests {

    private var routine: IntervalRoutine {
        IntervalRoutine(name: "Lower · beam", work: 40, rest: 45, rounds: 8,
                        moves: [Move(name: "Beam front squat", equipment: .beam,
                                     cue: "Slow.", loadPounds: 15)])
    }

    private func session(elapsed: TimeInterval, savedAgo: TimeInterval,
                         running: Bool = true) -> ActiveSession {
        ActiveSession(routine: routine,
                      startedAt: Date.now.addingTimeInterval(-(elapsed + savedAgo)),
                      elapsed: elapsed,
                      running: running,
                      savedAt: Date.now.addingTimeInterval(-savedAgo))
    }

    // The clock kept running while the app was dead. Resuming at the saved
    // elapsed would silently hand back the minutes she was not training.
    @Test("A running session counts the time the app was gone")
    func countsTimeAway() {
        let interrupted = session(elapsed: 60, savedAgo: 30)
        #expect(abs(interrupted.elapsedNow() - 90) < 1)
    }

    @Test("A paused session does not")
    func pausedDoesNotDrift() {
        let paused = session(elapsed: 60, savedAgo: 300, running: false)
        #expect(abs(paused.elapsedNow() - 60) < 1)
    }

    @Test("Restoring the engine lands on the right round")
    @MainActor
    func restorePosition() {
        let engine = IntervalEngine(routine: routine, autoTick: false)
        // Two full rounds of 40s work plus 45s rest, then 10s into round three.
        engine.restore(to: 180, running: true)

        #expect(engine.status == .running)
        #expect(engine.currentPhase?.round == 3)
        #expect(engine.currentPhase?.isWork == true)
        #expect(abs(engine.elapsed - 180) < 0.5)
    }

    @Test("Restoring paused stays paused")
    @MainActor
    func restorePaused() {
        let engine = IntervalEngine(routine: routine, autoTick: false)
        engine.restore(to: 90, running: false)
        #expect(engine.status == .paused)
    }

    @Test("Restoring past the end starts over rather than finishing instantly")
    @MainActor
    func restorePastEnd() {
        let engine = IntervalEngine(routine: routine, autoTick: false)
        engine.restore(to: 10_000, running: true)
        #expect(engine.elapsed == 0)
        #expect(engine.status == .running)
    }

    @Test("A stale session is dropped rather than offered")
    func staleIsDropped() {
        #expect(session(elapsed: 60, savedAgo: 30).isStale() == false)
        #expect(session(elapsed: 60, savedAgo: 3 * 3600).isStale())
    }

    // The app must not decide on her behalf that she finished. A mark is a
    // session seen through, and one the clock outran while the app was closed
    // is not evidence of anything.
    @Test("A session the clock outran is not offered back")
    func ranOutIsDropped() {
        let total = routine.schedule.total
        #expect(session(elapsed: total - 20, savedAgo: 5).ranOut() == false)
        #expect(session(elapsed: total - 20, savedAgo: 600).ranOut())
    }

    @Test("The summary names the round and what is left")
    func summary() {
        let text = session(elapsed: 180, savedAgo: 0).summary()
        #expect(text.contains("Round 3 of 8"))
        #expect(text.contains("left"))
    }

    @Test("Round-trips through the store")
    func roundTrip() throws {
        ActiveSessionStore.clear()
        #expect(ActiveSessionStore.load() == nil)

        let saved = session(elapsed: 45, savedAgo: 2)
        ActiveSessionStore.save(saved)
        let loaded = try #require(ActiveSessionStore.load())
        #expect(loaded.routine.name == saved.routine.name)
        #expect(abs(loaded.elapsed - 45) < 0.001)

        ActiveSessionStore.clear()
        #expect(ActiveSessionStore.load() == nil)
    }

    @Test("The store discards a stale entry on read")
    func storeDropsStale() {
        ActiveSessionStore.save(session(elapsed: 60, savedAgo: 5 * 3600))
        #expect(ActiveSessionStore.load() == nil)
        // And having read it once, it is gone rather than re-offered.
        #expect(UserDefaults.standard.data(forKey: ActiveSessionStore.key) == nil)
    }
}

@Suite("Goal projection")
struct ProjectionTests {

    @Test("Caps a date that needs more than a pound a week")
    func capsAggressiveDate() throws {
        // 30 lb in four weeks off 180 lb is 7.5 lb a week.
        let soon = Date.now.addingTimeInterval(28 * 86_400)
        let projection = try #require(Projections.project(current: 180, goal: 150, requestedArrival: soon))

        #expect(projection.cappedFromRequestedDate)
        #expect(projection.weeklyRate <= 180 * Projection.safeFraction)
        #expect(projection.arrival > soon, "the date moves, not the rate")
        #expect(projection.cappedNote != nil)
    }

    @Test("Honours a date that is already sensible")
    func honoursGentleDate() throws {
        // 10 lb in twenty weeks is half a pound a week.
        let later = Date.now.addingTimeInterval(20 * 7 * 86_400)
        let projection = try #require(Projections.project(current: 180, goal: 170, requestedArrival: later))

        #expect(!projection.cappedFromRequestedDate)
        #expect(projection.cappedNote == nil)
        #expect(abs(projection.weeksRemaining - 20) < 1)
    }

    @Test("Chooses a gentler rate than the ceiling when no date is given")
    func defaultRate() throws {
        let projection = try #require(Projections.project(current: 180, goal: 150))
        #expect(projection.weeklyRate < 180 * Projection.safeFraction)
        #expect(!projection.cappedFromRequestedDate)
    }

    @Test("Says at goal rather than projecting backwards")
    func atOrBelowGoal() throws {
        let there = try #require(Projections.project(current: 150, goal: 150))
        #expect(there.isComplete)
        #expect(there.summary == "At goal")

        let below = try #require(Projections.project(current: 145, goal: 150))
        #expect(below.isComplete)
    }

    @Test("Refuses to project from nothing")
    func noInput() {
        #expect(Projections.project(current: 0, goal: 150) == nil)
        #expect(Projections.project(current: 180, goal: 0) == nil)
    }
}

@Suite("Flow movements")
struct FlowTests {

    @Test("Flow moves exist and are kept out of the strength library")
    func separated() {
        #expect(!MoveLibrary.flow.isEmpty)
        for move in MoveLibrary.flow { #expect(move.kind == .flow) }

        // `moves(for:)` feeds the strength picker and the offline templates, so
        // a flow movement leaking into it would end up inside a work interval.
        for equipment in Equipment.allCases {
            for move in MoveLibrary.moves(for: equipment) {
                #expect(move.kind == .strength)
            }
        }
    }

    @Test("A generated flow movement is recognised rather than cued as strength")
    func recognisedByName() {
        #expect(PlanValidator.kind(of: "Cat cow") == .flow)
        #expect(PlanValidator.kind(of: "Lymphatic bounce") == .flow)
        #expect(PlanValidator.kind(of: "Beam front squat") == .strength)
        #expect(PlanValidator.kind(of: "Split squat") == .strength)
    }

    // Routines already on disk predate `kindRaw`. Swift's synthesized decoder
    // throws on a missing non-optional key, so this is the test that would have
    // caught making it required — every stored session would have stopped
    // decoding, and the growth form with it.
    @Test("A routine stored before flow existed still decodes")
    func decodesLegacyRoutine() throws {
        let legacy = """
        {"id":"\(UUID().uuidString)","name":"Old","work":40,"rest":45,"rounds":8,
         "dropsFinalRest":true,
         "moves":[{"id":"\(UUID().uuidString)","name":"Beam deadlift",
                   "equipment":"beam","cue":"Hinge.","loadPounds":15}]}
        """
        let routine = try JSONDecoder().decode(IntervalRoutine.self, from: Data(legacy.utf8))
        #expect(routine.moves.count == 1)
        #expect(routine.moves[0].kind == .strength)
    }

    @Test("Flow moves round-trip through the routine encoding")
    func roundTrips() throws {
        let flow = try #require(MoveLibrary.flow.first)
        let routine = IntervalRoutine(name: "Morning", work: 40, rest: 20, rounds: 3, moves: [flow])
        let data = try JSONEncoder().encode(routine)
        let decoded = try JSONDecoder().decode(IntervalRoutine.self, from: data)
        #expect(decoded.moves[0].kind == .flow)
    }
}

@Suite("Warm-up practice")
struct WarmUpTests {

    private let monday = Date(timeIntervalSince1970: 1_700_000_000)

    @Test("A practice is three to five movements, all of them flow")
    func shape() {
        let moves = WarmUp.moves(on: monday)
        #expect((WarmUp.minimum...WarmUp.maximum).contains(moves.count))
        #expect(moves.count == WarmUp.target)
        for move in moves { #expect(move.kind == .flow) }
        // Repeating one movement inside a three-minute practice would read as
        // the app having run out of ideas.
        #expect(Set(moves.map(\.name)).count == moves.count)
    }

    @Test("The same day always produces the same practice")
    func stable() {
        let first = WarmUp.moves(on: monday).map(\.name)
        let again = WarmUp.moves(on: monday.addingTimeInterval(6 * 3600)).map(\.name)
        #expect(first == again)
    }

    @Test("The practice walks rather than cycling every third day")
    func rotates() {
        let fortnight = (0..<14).map {
            WarmUp.moves(on: monday.addingTimeInterval(Double($0) * 86_400))
                .map(\.name).joined(separator: "|")
        }
        // Consecutive days must differ — two sessions in a row opening the same
        // way is the thing this is for.
        for (a, b) in zip(fortnight, fortnight.dropFirst()) { #expect(a != b) }
        // And a fortnight should not be three practices on repeat.
        #expect(Set(fortnight).count >= 10)
    }

    @Test("Anything she has ruled out stays out of the practice")
    func honoursPreferences() {
        let excluded: Set<String> = ["shaking", "lymphatic bounce"]
        for day in 0..<14 {
            let moves = WarmUp.moves(on: monday.addingTimeInterval(Double(day) * 86_400),
                                     avoiding: excluded)
            for move in moves {
                #expect(!excluded.contains(MovePreference.key(move.name)))
            }
        }
    }

    @Test("Ruling out the whole practice gives no practice, not a substitute")
    func canBeEmptied() {
        let everything = Set(MoveLibrary.flow.map { MovePreference.key($0.name) })
        #expect(WarmUp.moves(on: monday, avoiding: everything).isEmpty)
    }

    // MARK: The schedule it produces

    private func session(warmUp count: Int) -> IntervalRoutine {
        IntervalRoutine(name: "Test", work: 40, rest: 30, rounds: 4,
                        moves: [MoveLibrary.all[0]])
            .warmingUp(with: Array(MoveLibrary.flow.prefix(count)))
    }

    @Test("The practice runs first, continuously, and is not a round")
    func schedule() {
        let schedule = session(warmUp: 4).schedule
        #expect(schedule.phases.prefix(4).allSatisfy { $0.isFlow })
        // No rest between one movement and the next — a flow is not intervals.
        #expect(schedule.phases[4].isWork)
        #expect(schedule.flowPhaseCount == 4)
        #expect(schedule.workPhaseCount == 4)
        #expect(Array(schedule.phases.map(\.round).prefix(4)) == [1, 2, 3, 4])
    }

    @Test("The practice is additive — it never costs a round or a second of work")
    func additive() {
        let bare = IntervalRoutine(name: "Test", work: 40, rest: 30, rounds: 4,
                                   moves: [MoveLibrary.all[0]])
        let warmed = session(warmUp: 4)
        #expect(warmed.rounds == bare.rounds)
        #expect(warmed.clampedWork == bare.clampedWork)
        #expect(warmed.totalDuration == bare.totalDuration + 4 * WarmUp.seconds)
    }

    @Test("An empty practice leaves the routine exactly as it was")
    func emptyIsNoOp() {
        let bare = IntervalRoutine(name: "Test", work: 40, rest: 30, rounds: 4,
                                   moves: [MoveLibrary.all[0]])
        #expect(bare.warmingUp(with: []).schedule == bare.schedule)
    }

    @Test("Warm-up phases are never counted down at")
    @MainActor
    func noCountdown() {
        let clock = TestClock()
        let engine = IntervalEngine(routine: session(warmUp: 2),
                                    now: clock.provider, autoTick: false)
        var ticks = 0
        engine.onCountdownTick = { ticks += 1 }
        engine.start()
        // Straight through both flow movements, second by second.
        for _ in 0..<Int(WarmUp.seconds * 2) {
            clock.advance(1)
            engine.refresh()
        }
        #expect(ticks == 0, "the practice must not be cued like a work interval")
        #expect(engine.currentPhase?.isWork == true)
    }

    @Test("Being mid-practice is not being mid-round")
    @MainActor
    func roundsNotYetStarted() {
        let clock = TestClock()
        let engine = IntervalEngine(routine: session(warmUp: 3),
                                    now: clock.provider, autoTick: false)
        engine.start()
        clock.advance(WarmUp.seconds * 2 + 5)
        engine.refresh()
        #expect(engine.isWarmingUp)
        #expect(engine.completedWorkRounds == 0)
        #expect(engine.currentPhase?.position(rounds: 4, flowCount: 3) == "Warm-up 3 / 3")
    }

    @Test("A skipped flow movement is recorded, so she can be asked why")
    @MainActor
    func skipIsRecorded() throws {
        let clock = TestClock()
        let routine = session(warmUp: 2)
        let first = try #require(routine.warmUp.first?.name)
        let engine = IntervalEngine(routine: routine, now: clock.provider, autoTick: false)
        engine.start()
        engine.skip()
        #expect(engine.skippedMoves == [first])
    }

    @Test("A routine stored before warm-ups existed still decodes")
    func decodesLegacyRoutine() throws {
        let legacy = """
        {"id":"\(UUID().uuidString)","name":"Old","work":40,"rest":45,"rounds":8,
         "dropsFinalRest":true,
         "moves":[{"id":"\(UUID().uuidString)","name":"Beam deadlift",
                   "equipment":"beam","cue":"Hinge.","loadPounds":15}]}
        """
        let routine = try JSONDecoder().decode(IntervalRoutine.self, from: Data(legacy.utf8))
        #expect(routine.warmUp.isEmpty)
        #expect(routine.warmUpSeconds == WarmUp.seconds)
        #expect(routine.schedule.phases.first?.isWork == true)
    }

    @Test("A warmed routine round-trips")
    func roundTrips() throws {
        let routine = session(warmUp: 4)
        let decoded = try JSONDecoder().decode(
            IntervalRoutine.self, from: JSONEncoder().encode(routine))
        #expect(decoded.warmUp.map(\.name) == routine.warmUp.map(\.name))
        #expect(decoded.warmUp.allSatisfy { $0.kind == .flow })
        #expect(decoded.totalDuration == routine.totalDuration)
    }
}

@Suite("Timer-only routines")
struct TimerOnlyTests {

    private let bare = IntervalRoutine(name: "Just the clock", work: 45, rest: 30,
                                       rounds: 5, moves: [])

    @Test("A routine with no moves still schedules its intervals")
    func schedules() {
        let schedule = bare.schedule
        #expect(schedule.workPhaseCount == 5)
        #expect(schedule.phases.allSatisfy { $0.move == nil })
        #expect(bare.totalDuration == 45 * 5 + 30 * 4)
    }

    @Test("It runs to the end like any other routine")
    @MainActor
    func runs() {
        let clock = TestClock()
        let engine = IntervalEngine(routine: bare, now: clock.provider, autoTick: false)
        var reason: IntervalEngine.EndReason?
        engine.onFinish = { reason = $0 }
        engine.start()
        clock.advance(bare.totalDuration + 1)
        engine.refresh()
        #expect(reason == .completed)
    }

    @Test("Skipping a move-less interval records nothing to ask about")
    @MainActor
    func skipRecordsNothing() {
        let clock = TestClock()
        let engine = IntervalEngine(routine: bare, now: clock.provider, autoTick: false)
        engine.start()
        engine.skip()
        #expect(engine.skippedMoves.isEmpty)
    }

    @Test("The saved-routine row calls it a timer rather than counting to zero")
    func described() {
        #expect(RoutineListView.rotationNote(bare) == "timer only")
        #expect(RoutineListView.rotationNote(
            IntervalRoutine(name: "One", work: 40, rest: 20, rounds: 3,
                            moves: [MoveLibrary.all[0]])) == "1 move")
    }
}

@Suite("Move plates")
struct MovePlateTests {

    // The point of closing the library: no exception list, no fallback, no
    // matching. Every move the app can be asked to draw has a drawing.
    @Test("Every move in the library has a strip")
    func libraryIsCovered() {
        for move in MoveLibrary.all {
            #expect(MovePlates.strip(for: move) != nil, "no strip for \(move.name)")
        }
    }

    @Test("A move outside the library has none, and is never guessed at")
    func outsideTheLibrary() {
        // Names the planner might invent that the library does not hold.
        // "Ring goblet squat" and "Beam reverse lunge" used to be here and are
        // now real moves — which is the point of adding to a closed library
        // rather than loosening the match.
        for name in ["Side plank", "Turkish get-up", "Kettlebell swing",
                     "Barbell back squat", "Shaking", ""] {
            #expect(MovePlates.strip(for: name) == nil, "\(name) resolved to a plate")
        }
    }

    @Test("A plate never draws kit the move does not use")
    func equipmentMatches() throws {
        // Every strip a real move resolves to either holds that move's kit or
        // holds nothing at all — and holding nothing is only allowed when the
        // move itself carries nothing.
        for move in MoveLibrary.all {
            guard let strip = MovePlates.strip(for: move) else { continue }
            if let drawn = strip.equipment {
                #expect(drawn == move.equipment,
                        "\(move.name) draws \(drawn) but uses \(move.equipment)")
            } else {
                #expect(move.equipment == .bodyweight,
                        "\(move.name) uses \(move.equipment) but draws a bare pattern")
            }
        }
    }

    @Test("The more specific strip wins")
    func specificity() {
        func key(_ name: String, _ equipment: Equipment) -> String? {
            MovePlates.strip(for: Move(name: name, equipment: equipment, cue: ""))?.key
        }
        #expect(key("Beam front squat", .beam) == "front squat")
        #expect(key("Split squat", .bodyweight) == "split squat")
        #expect(key("Wall sit", .bodyweight) == "wall sit")
        #expect(key("Incline walk", .walkingPad) == "incline walk")
        #expect(key("Zone 2 walk", .walkingPad) == "walk")
        #expect(key("Ring deadlift", .rings) == "ring deadlift")
        #expect(key("Beam deadlift", .beam) == "deadlift")
        #expect(key("Arnold press", .dumbbells) == "arnold press")
        #expect(key("Dumbbell press", .dumbbells) == "press")
    }

    @Test("A move nobody has drawn gets no strip rather than the wrong one")
    func unknownIsNil() {
        #expect(MovePlates.strip(for: "") == nil)
    }

    @Test("A strip is two or three panels and its signature is one of them")
    func shape() {
        for strip in MovePlates.all {
            #expect((2...3).contains(strip.panels.count), "\(strip.key) has \(strip.panels.count) panels")
            #expect(strip.panels.indices.contains(strip.signature), "\(strip.key) signature out of range")
            #expect(strip.pair.count == 2, "\(strip.key) cannot make a pair")
        }
    }

    // This is the check the illustrator was doing by hand, six decimal places at
    // a time, for ninety panels. It belongs here: it runs in milliseconds, it
    // runs on every change, and it fails loudly rather than in prose.
    @Test("Every joint stays inside its own panel")
    func withinPanel() {
        for strip in MovePlates.all {
            let width = strip.facing.width
            for (index, pose) in strip.panels.enumerated() {
                for joint in joints(of: pose) {
                    #expect(joint.x >= -0.005 && joint.x <= width + 0.005,
                            "\(strip.key) panel \(index): x \(joint.x) outside 0…\(width)")
                    // The head is a disc drawn around its centre, so it needs
                    // its radius of clearance at the top.
                    #expect(joint.y >= -0.005 && joint.y <= 1 - Anatomy.radius,
                            "\(strip.key) panel \(index): y \(joint.y) outside the panel")
                }
            }
        }
    }

    @Test("Limb segments keep their length in every pose")
    func segmentsHold() {
        // The knee is solved, not placed. If someone swaps the inverse
        // kinematics back for a displaced midpoint, this is what catches it —
        // the old code drew a visibly short shin at the bottom of a squat.
        for strip in MovePlates.all where !isFloorBound(strip) {
            for (index, pose) in strip.panels.enumerated() {
                for leg in pose.legs {
                    guard leg.count == 3 else { continue }
                    let thigh = hypot(leg[1].x - leg[0].x, leg[1].y - leg[0].y)
                    let shin = hypot(leg[2].x - leg[1].x, leg[2].y - leg[1].y)
                    #expect(abs(thigh - Anatomy.thigh) < 0.002,
                            "\(strip.key) panel \(index): thigh \(thigh)")
                    #expect(abs(shin - Anatomy.shin) < 0.002,
                            "\(strip.key) panel \(index): shin \(shin)")
                }
            }
        }
    }

    // Caught by eye, not by any check: a pose that lifts a foot but draws only
    // one leg puts the figure's whole weight on nothing. Every standing pose
    // needs a sole on the ground.
    @Test("A standing figure has at least one foot on the floor")
    func standsOnSomething() {
        for strip in MovePlates.all where !Self.floorBound.contains(strip.key) {
            for (index, pose) in strip.panels.enumerated() {
                let lowest = pose.legs.compactMap(\.last?.y).min() ?? 1
                #expect(abs(lowest - Anatomy.floorY) < 0.02,
                        "\(strip.key) panel \(index) floats: lowest sole at \(lowest)")
            }
        }
    }

    /// Poses whose weight is not on the feet at all, or which stand on the pad
    /// rather than the floor line.
    static let floorBound = ["hip thrust", "glute bridge", "dead bug", "floor fly",
                             "cat cow", "bird dog", "push-up", "walk", "incline walk",
                             "floor press", "pullover"]

    @Test("Consecutive panels differ enough to read as a change")
    func panelsDiffer() {
        for strip in MovePlates.all {
            for index in 1..<strip.panels.count {
                let a = strip.panels[index - 1], b = strip.panels[index]
                // The furthest a single landmark travels, not the sum over all
                // of them. Summing eleven joints inflates the number until any
                // threshold passes — which is how three strips shipped reading
                // as one drawing printed twice.
                let travel = max(
                    zip(joints(of: a), joints(of: b))
                        .map { distance($0.0, $0.1) }.max() ?? 0,
                    abs((a.spineCurve ?? 0) - (b.spineCurve ?? 0)) * Anatomy.head)
                // One head diameter, not a token amount. The illustrator's
                // rule, and the reason three strips slipped through the first
                // pass reading as a single drawing printed twice.
                #expect(travel >= Anatomy.head,
                        "\(strip.key) panels \(index - 1) and \(index) barely differ (\(travel))")
            }
        }
    }

    private func joints(of pose: Pose) -> [CGPoint] {
        [pose.hip, pose.neck, pose.head] + pose.arms.flatMap { $0 } + pose.legs.flatMap { $0 }
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> Double { hypot(b.x - a.x, b.y - a.y) }

    /// Supine and quadruped place their knees rather than solving them — a
    /// foreshortened leg drawn at full length is wrong, not right.
    private func isFloorBound(_ strip: Strip) -> Bool {
        ["hip thrust", "glute bridge", "dead bug", "floor fly", "cat cow", "bird dog",
         "floor press", "pullover"].contains(strip.key)
    }
}

@Suite("Response schema")
struct ResponseSchemaTests {

    private func session(in schema: [String: Any]) throws -> [String: Any] {
        let defs = try #require(schema["$defs"] as? [String: Any])
        return try #require(defs["session"] as? [String: Any])
    }

    private func property(_ name: String, of object: [String: Any]) throws -> [String: Any] {
        let properties = try #require(object["properties"] as? [String: Any])
        return try #require(properties[name] as? [String: Any])
    }

    // The failure this exists for: the first live week after the warm-up
    // shipped came back asking for zero rounds. `minimum` is not supported by
    // structured outputs, so the bound is expressed as a set of legal values.
    @Test("Zero rounds is not a value the schema can express")
    func roundsCannotBeZero() throws {
        let rounds = try property("rounds", of: try session(in: ClaudePlanner.schema(sessions: 4)))
        let values = try #require(rounds["enum"] as? [Int])
        #expect(!values.contains(0))
        #expect(values.allSatisfy { (1...PlanValidator.roundCeiling).contains($0) })
        // It was also the one field in the schema with nothing said about it.
        #expect(rounds["description"] != nil)
    }

    @Test("A work interval over the ceiling is not expressible")
    func workRespectsTheCeiling() throws {
        let work = try property("work", of: try session(in: ClaudePlanner.schema(sessions: 4)))
        let values = try #require(work["enum"] as? [Int])
        #expect(values.allSatisfy { Double($0) <= IntervalRoutine.workCeiling })
        #expect(values.contains(Int(IntervalRoutine.workCeiling)))
        #expect(values.allSatisfy { $0 > 0 })
    }

    @Test("Rest is never negative, and a day is always inside the week")
    func restAndDays() throws {
        let session = try session(in: ClaudePlanner.schema(sessions: 3))
        let rest = try #require(try property("rest", of: session)["enum"] as? [Int])
        #expect(rest.allSatisfy { $0 >= 0 })
        let days = try #require(try property("dayOffset", of: session)["enum"] as? [Int])
        #expect(days == [0, 1, 2, 3, 4, 5, 6])
    }

    @Test("Only loads the kit can be set to are expressible")
    func loadsMatchTheKit() throws {
        let defs = try #require(ClaudePlanner.schema(sessions: 4)["$defs"] as? [String: Any])
        let move = try #require(defs["move"] as? [String: Any])
        let loads = try #require(try property("loadPounds", of: move)["enum"] as? [Double])

        // Zero, for bodyweight and the pad, plus every real load — and nothing
        // else. A schema that offered 20 lb would be describing a kit she does
        // not own.
        let real = Set(Equipment.allCases.flatMap(\.availableLoadsPounds))
        #expect(Set(loads) == real.union([0]))
        #expect(!loads.contains(20))
    }

    @Test("Every session the offline planner writes is expressible")
    func offlineWeeksFitTheSchema() throws {
        // If the deterministic floor could write a week the schema forbids, the
        // two planners would disagree about what a legal session is — and the
        // repair turn would be arguing against a week the app itself produces.
        for pace in Pace.allCases {
            for week in 1...12 {
                let draft = OfflinePlanner.week(week, pace: pace)
                for session in draft.sessions {
                    #expect(ClaudePlanner.workSeconds.contains(session.work),
                            "work \(session.work)s is not in the schema")
                    #expect(ClaudePlanner.roundCounts.contains(session.rounds),
                            "\(session.rounds) rounds is not in the schema")
                    #expect(ClaudePlanner.restSeconds.contains(session.rest),
                            "rest \(session.rest)s is not in the schema")
                    #expect(ClaudePlanner.dayOffsets.contains(session.dayOffset))
                    for move in session.moves {
                        #expect(ClaudePlanner.legalLoads.contains(move.loadPounds),
                                "\(move.loadPounds) lb is not in the schema")
                    }
                }
            }
        }
    }

    @Test("The schema still asks for exactly the pace's sessions")
    func sessionCount() throws {
        for pace in Pace.allCases {
            let schema = ClaudePlanner.schema(sessions: pace.sessionsPerWeek)
            let sessions = try #require(try property("sessions", of: schema)["required"] as? [String])
            #expect(sessions.count == pace.sessionsPerWeek)
        }
    }
}

@Suite("Morning practice")
struct MorningPracticeTests {

    private let monday = Date(timeIntervalSince1970: 1_700_000_000)

    @Test("Eight movements, a minute each, and the rebounding always leads")
    func shape() throws {
        for day in 0..<14 {
            let date = monday.addingTimeInterval(Double(day) * 86_400)
            let moves = Practice.moves(on: date, count: 8)
            #expect(moves.count == 8)
            #expect(moves.first?.name == Practice.opener,
                    "day \(day) opened with \(moves.first?.name ?? "nothing")")
            for move in moves { #expect(move.kind == .flow) }
            // Eight minutes of practice, not eight minutes of one movement.
            #expect(Set(moves.map(\.name)).count == moves.count)
        }
    }

    @Test("It is a routine of pure flow — no rounds, no work, no rest")
    func routineIsAllPractice() {
        let schedule = Practice.routine(on: monday).schedule
        #expect(schedule.phases.allSatisfy { $0.isFlow })
        #expect(schedule.workPhaseCount == 0)
        #expect(schedule.flowPhaseCount == schedule.phases.count)
        #expect(schedule.total == Practice.seconds * Double(schedule.phases.count))
    }

    @Test("The practice is never counted down at")
    @MainActor
    func noCountdown() {
        let clock = TestClock()
        let engine = IntervalEngine(routine: Practice.routine(on: monday),
                                    now: clock.provider, autoTick: false)
        var ticks = 0
        engine.onCountdownTick = { ticks += 1 }
        engine.start()
        for _ in 0..<Int(Practice.seconds * 2) {
            clock.advance(1)
            engine.refresh()
        }
        #expect(ticks == 0)
    }

    @Test("Its phases are movements, not warm-up for work that is not coming")
    func namesItself() throws {
        let practice = Practice.routine(on: monday)
        let phase = try #require(practice.schedule.phases.first)
        #expect(phase.position(rounds: practice.rounds, flowCount: 8) == "Movement 1 / 8")

        // A session's opening flow is still a warm-up.
        let session = IntervalRoutine(name: "S", work: 40, rest: 30, rounds: 4,
                                      moves: [MoveLibrary.all[0]])
            .warmingUp(with: Array(MoveLibrary.flow.prefix(4)))
        let opening = try #require(session.schedule.phases.first)
        #expect(opening.position(rounds: 4, flowCount: 4) == "Warm-up 1 / 4")
    }

    @Test("Consecutive days differ, and the opener does not")
    func rotates() {
        let days = (0..<12).map {
            Practice.moves(on: monday.addingTimeInterval(Double($0) * 86_400), count: 8)
                .map(\.name).joined(separator: "|")
        }
        for (a, b) in zip(days, days.dropFirst()) { #expect(a != b) }
        #expect(Set(days).count >= 8)
    }

    @Test("A session never repeats a movement the morning already used")
    func sessionDoesNotRepeatThePractice() {
        for day in 0..<10 {
            let date = monday.addingTimeInterval(Double(day) * 86_400)
            let practice = Set(Practice.moves(on: date, count: 8)
                .map { MovePreference.key($0.name) })
            let warmUp = WarmUp.afterPractice(on: date, practiceCount: 8)
                .map { MovePreference.key($0.name) }
            #expect(!warmUp.isEmpty)
            for move in warmUp {
                #expect(!practice.contains(move),
                        "day \(day): \(move) is in both the practice and the warm-up")
            }
        }
    }

    @Test("Movements she has ruled out stay out, and the opener can go too")
    func honoursPreferences() {
        let moves = Practice.moves(on: monday, avoiding: ["standing twist"], count: 8)
        for move in moves {
            #expect(MovePreference.key(move.name) != "standing twist")
        }
        // Pain outranks the ritual: if the rebounding itself hurts, the
        // practice opens with something else rather than insisting.
        let withoutOpener = Practice.moves(on: monday, avoiding: ["lymphatic bounce"], count: 8)
        #expect(withoutOpener.first?.name != Practice.opener)
        #expect(!withoutOpener.isEmpty)
    }
}

@Suite("A closed move library")
struct ClosedLibraryTests {

    @Test("The schema offers the library and nothing else")
    func schemaEnumeratesMoves() throws {
        let defs = try #require(ClaudePlanner.schema(sessions: 4)["$defs"] as? [String: Any])
        let move = try #require(defs["move"] as? [String: Any])
        let properties = try #require(move["properties"] as? [String: Any])
        let name = try #require(properties["name"] as? [String: Any])
        let offered = try #require(name["enum"] as? [String])

        #expect(Set(offered) == Set(MoveLibrary.names))
        #expect(!offered.isEmpty)
        // The failure this closes: the planner inventing a name the app then
        // had to guess the shape of.
        #expect(!offered.contains("Beam goblet squat"))
    }

    @Test("A week naming a move that does not exist is rejected whole")
    func validatorRejectsInventedMoves() {
        let draft = PlanDraft(
            explanation: "Week one.",
            sessions: [DraftSession(dayOffset: 0, title: "Lower", work: 40, rest: 45, rounds: 8,
                                    moves: [DraftMove(name: "Beam goblet squat",
                                                      equipment: "beam",
                                                      cue: "Beam at the chest.",
                                                      loadPounds: 15)])],
            walkMinutes: 90)
        #expect(throws: PlanValidator.Failure.unknownMove("Beam goblet squat")) {
            _ = try PlanValidator.routines(from: draft)
        }
    }

    @Test("A real move keeps the library's own name, kind and equipment")
    func validatorNormalises() throws {
        let known = try #require(MoveLibrary.all.first { $0.equipment == .beam })
        let draft = DraftMove(name: known.name.lowercased(), equipment: "beam",
                              cue: "Whatever the planner wrote.", loadPounds: 15)
        let move = try PlanValidator.move(from: draft)
        // The name comes back in the library's spelling, so the plate lookup
        // cannot miss on capitalisation.
        #expect(move.name == known.name)
        #expect(move.kind == known.kind)
        #expect(MovePlates.strip(for: move) != nil)
    }

    @Test("A move claiming the wrong kit is rejected")
    func validatorChecksEquipment() {
        let draft = DraftMove(name: "Beam deadlift", equipment: "dumbbells",
                              cue: "No.", loadPounds: 2)
        #expect(throws: PlanValidator.Failure.unknownEquipment("dumbbells")) {
            _ = try PlanValidator.move(from: draft)
        }
    }

    @Test("Every week the offline planner writes still passes")
    func offlineWeeksSurvive() throws {
        for pace in Pace.allCases {
            for week in 1...12 {
                let draft = OfflinePlanner.week(week, pace: pace)
                let routines = try PlanValidator.routines(from: draft)
                for entry in routines {
                    for move in entry.routine.moves {
                        #expect(MovePlates.strip(for: move) != nil,
                                "\(move.name) has no plate")
                    }
                }
            }
        }
    }
}

@Suite("Configurable shape", .serialized)
struct TuningTests {

    @Test("Both numbers are bounded, whatever is written to them")
    func bounded() {
        defer { Tuning.reset() }
        Tuning.movesPerSession = 99
        #expect(Tuning.movesPerSession == Tuning.movesPerSessionRange.upperBound)
        Tuning.movesPerSession = 0
        #expect(Tuning.movesPerSession == Tuning.movesPerSessionRange.lowerBound)

        Tuning.practiceMovements = 99
        #expect(Tuning.practiceMovements == Tuning.practiceRange.upperBound)
        // The practice can never ask for more movements than the flow library
        // actually holds.
        #expect(Tuning.practiceMovements <= MoveLibrary.flow.count)
    }

    @Test("Five moves a session is the new default")
    func defaults() {
        Tuning.reset()
        #expect(Tuning.movesPerSession == 5)
        #expect(Tuning.practiceMovements == 8)
    }

    @Test("The schema requires exactly as many moves as the setting asks for")
    func schemaFollows() throws {
        defer { Tuning.reset() }
        for count in Tuning.movesPerSessionRange {
            Tuning.movesPerSession = count
            let defs = try #require(ClaudePlanner.schema(sessions: 4)["$defs"] as? [String: Any])
            let session = try #require(defs["session"] as? [String: Any])
            let properties = try #require(session["properties"] as? [String: Any])
            let moves = try #require(properties["moves"] as? [String: Any])
            let required = try #require(moves["required"] as? [String])
            // Named slots, because `minItems` is not supported — so the count
            // has to be the number of required properties or it is not required.
            #expect(required.count == count)
            let slots = try #require(moves["properties"] as? [String: Any])
            #expect(slots.count == count)
        }
    }

    @Test("The offline planner fills the rotation without repeating a move")
    func offlineFollows() {
        defer { Tuning.reset() }
        for count in Tuning.movesPerSessionRange {
            Tuning.movesPerSession = count
            for pace in Pace.allCases {
                let draft = OfflinePlanner.week(1, pace: pace)
                for session in draft.sessions {
                    #expect(session.moves.count == count,
                            "\(pace) wanted \(count), got \(session.moves.count)")
                    #expect(Set(session.moves.map(\.name)).count == session.moves.count,
                            "a move is repeated in the rotation")
                }
            }
        }
    }

    @Test("A longer practice is still the rebounding first and no repeats")
    func practiceFollows() {
        defer { Tuning.reset() }
        let monday = Date(timeIntervalSince1970: 1_700_000_000)
        for count in [3, 5, 8, MoveLibrary.flow.count] {
            Tuning.practiceMovements = count
            let moves = Practice.moves(on: monday)
            #expect(moves.count == Tuning.practiceMovements)
            #expect(moves.first?.name == Practice.opener)
            #expect(Set(moves.map(\.name)).count == moves.count)
        }
    }
}

@Suite("A rest day is not a locked door")
struct RestDayOfferTests {

    /// Mirrors `TodayView.offeredSession`: the most recent unfinished session
    /// earlier this week, else the next one coming up.
    private func offer(from sessions: [(day: Int, done: Bool)],
                       today: Int, weekStart: Int = 0) -> (day: Int, missed: Bool)? {
        let missed = sessions.filter { !$0.done && $0.day < today && $0.day >= weekStart }
            .max(by: { $0.day < $1.day })
        if let missed { return (missed.day, true) }
        let next = sessions.filter { !$0.done && $0.day > today }.min(by: { $0.day < $1.day })
        return next.map { ($0.day, false) }
    }

    @Test("Yesterday's undone session is what a rest day offers first")
    func missedComesFirst() throws {
        // Monday and Tuesday scheduled, Monday done, Tuesday not. Wednesday is
        // a rest day.
        let week = [(day: 0, done: true), (day: 1, done: false), (day: 4, done: false)]
        let result = try #require(offer(from: week, today: 2))
        #expect(result.day == 1)
        #expect(result.missed)
    }

    @Test("With nothing missed, the next one is offered early instead")
    func nextWhenNothingMissed() throws {
        let week = [(day: 0, done: true), (day: 1, done: true), (day: 4, done: false)]
        let result = try #require(offer(from: week, today: 2))
        #expect(result.day == 4)
        #expect(!result.missed)
    }

    @Test("A missed session outranks an upcoming one")
    func missedOutranksUpcoming() throws {
        // Both exist. Offering tomorrow's would leave the skipped one sitting
        // there and quietly shorten the week.
        let week = [(day: 1, done: false), (day: 4, done: false)]
        let result = try #require(offer(from: week, today: 2))
        #expect(result.day == 1)
    }

    @Test("Last week's misses are not dragged into this one")
    func staysWithinTheWeek() throws {
        // Day -3 is last week. A rest day should not offer a session from a
        // week that has closed.
        let sessions = [(day: -3, done: false), (day: 5, done: false)]
        let result = try #require(offer(from: sessions, today: 2, weekStart: 0))
        #expect(result.day == 5)
        #expect(!result.missed)
    }

    @Test("Nothing left to offer is a real answer")
    func nothingToOffer() {
        #expect(offer(from: [(day: 0, done: true), (day: 1, done: true)], today: 2) == nil)
        #expect(offer(from: [], today: 2) == nil)
    }

    @Test("A mark counts for the week it was finished, not the week it was planned")
    func markFollowsTheDoing() {
        // Doing Tuesday's session on Wednesday should mark Wednesday's week.
        // Today bins by `completedAt`, which is what makes picking up a missed
        // session honest rather than back-dated.
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000))
        let planned = calendar.date(byAdding: .day, value: 5, to: start)!
        let finished = calendar.date(byAdding: .day, value: 8, to: start)!

        func week(of date: Date) -> Int {
            (calendar.dateComponents([.day], from: start,
                                     to: calendar.startOfDay(for: date)).day ?? 0) / 7
        }
        #expect(week(of: planned) == 0)
        #expect(week(of: finished) == 1)
    }
}

@Suite("Written-out sequences")
struct IntervalSequenceTests {

    /// Her example, verbatim: 30 on, 30 rest, 20 on, 15 rest, 10 on, 10 on,
    /// 10 on, 30 rest. Note the three work intervals in a row.
    private let hers: [IntervalStep] = [
        .work(30), .rest(30), .work(20), .rest(15),
        .work(10), .work(10), .work(10), .rest(30)
    ]

    private var routine: IntervalRoutine {
        IntervalRoutine(name: "Ladder", work: 40, rest: 30, rounds: 8,
                        moves: [MoveLibrary.all[0], MoveLibrary.all[1]])
            .following(hers)
    }

    @Test("The sequence is followed exactly, in the order it was written")
    func followsTheOrder() {
        let phases = routine.schedule.phases
        #expect(phases.map(\.kind) == [.work, .rest, .work, .rest, .work, .work, .work, .rest])
        #expect(phases.map(\.duration) == [30, 30, 20, 15, 10, 10, 10, 30])
    }

    @Test("Work intervals in a row are allowed — nothing assumes alternation")
    func consecutiveWork() {
        let phases = routine.schedule.phases
        #expect(phases[4].isWork && phases[5].isWork && phases[6].isWork)
        // And they are numbered in sequence, so the header counts truthfully.
        #expect(phases.filter(\.isWork).map(\.round) == [1, 2, 3, 4, 5])
    }

    @Test("Rounds means work intervals, whatever shape the routine is")
    func roundsCounted() {
        #expect(routine.roundCount == 5)
        // The fixed shape is untouched by any of this.
        let fixed = IntervalRoutine(name: "Fixed", work: 40, rest: 30, rounds: 8, moves: [])
        #expect(fixed.roundCount == 8)
    }

    @Test("The total is the honest sum of what was written")
    func total() {
        #expect(routine.totalDuration == 30 + 30 + 20 + 15 + 10 + 10 + 10 + 30)
    }

    @Test("Moves cycle through the work intervals, skipping the rests")
    func movesFollowWork() {
        let onWork = routine.schedule.phases.filter(\.isWork).map(\.move?.name)
        let a = MoveLibrary.all[0].name, b = MoveLibrary.all[1].name
        #expect(onWork == [a, b, a, b, a])
        #expect(routine.schedule.phases.filter(\.isRest).allSatisfy { $0.move == nil })
    }

    @Test("A sequence cannot route around the sixty-second ceiling")
    func ceilingHolds() {
        let over = IntervalRoutine(name: "Over", work: 40, rest: 30, rounds: 1, moves: [])
            .following([.work(90), .rest(400)])
        #expect(over.schedule.phases[0].duration == IntervalRoutine.workCeiling)
        // Rest has no ceiling — a long rest is a choice, not a hazard.
        #expect(over.schedule.phases[1].duration == 400)
    }

    @Test("A sequence still opens with its practice")
    func warmUpComesFirst() {
        let warmed = routine.warmingUp(with: Array(MoveLibrary.flow.prefix(3)))
        let phases = warmed.schedule.phases
        #expect(phases.prefix(3).allSatisfy { $0.isFlow })
        #expect(phases[3].isWork)
        #expect(warmed.roundCount == 5)
    }

    @Test("It runs to the end like any other routine")
    @MainActor
    func runs() {
        let clock = TestClock()
        let engine = IntervalEngine(routine: routine, now: clock.provider, autoTick: false)
        var reason: IntervalEngine.EndReason?
        engine.onFinish = { reason = $0 }
        engine.start()
        clock.advance(routine.totalDuration + 1)
        engine.refresh()
        #expect(reason == .completed)
    }

    @Test("A routine stored before sequences existed still decodes")
    func decodesLegacy() throws {
        let legacy = """
        {"id":"\(UUID().uuidString)","name":"Old","work":40,"rest":45,"rounds":8,
         "dropsFinalRest":true,"moves":[]}
        """
        let decoded = try JSONDecoder().decode(IntervalRoutine.self, from: Data(legacy.utf8))
        #expect(!decoded.isSequence)
        #expect(decoded.roundCount == 8)
        #expect(decoded.schedule.workPhaseCount == 8)
    }

    @Test("A sequence round-trips")
    func roundTrips() throws {
        let decoded = try JSONDecoder().decode(
            IntervalRoutine.self, from: JSONEncoder().encode(routine))
        #expect(decoded.sequence.map(\.seconds) == hers.map(\.seconds))
        #expect(decoded.sequence.map(\.isWork) == hers.map(\.isWork))
        #expect(decoded.totalDuration == routine.totalDuration)
    }
}
