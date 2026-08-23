import Testing
import Foundation
import SwiftData
@testable import WrkTime

// MARK: - Never the network

/// Fails every request, so a test can exercise the planner's fallback without
/// ever reaching the API.
///
/// This exists because the tests *were* reaching it. Ten call sites used
/// `PlannerService.planWeek`'s default `ClaudePlanner()`, which reads her key
/// out of the Keychain and calls Anthropic for real — so a full suite run on a
/// machine with a key spent her money, once per call site, every run. That is
/// where the simulator's 485 requests and $37 came from, not from the app.
/// A test must never be able to spend.
final class BlockedProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
    }
    override func stopLoading() {}
}

extension ClaudePlanner {
    /// A planner wired to a session that cannot leave the machine.
    static var blocked: ClaudePlanner {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [BlockedProtocol.self]
        return ClaudePlanner(session: URLSession(configuration: configuration))
    }
}

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
    @Test("A ring weight that does not exist cannot be asked for at all",
          arguments: [3.0, 7.0, 12.0, 15.0])
    func impossibleRingLoad(pounds: Double) throws {
        // This used to be a rejection. It is now unrepresentable, which is
        // stronger: the schema asks Claude for a move *name* and nothing else,
        // so the load comes from the closed library rather than from the model.
        // "Ring halo" is the 5 lb ring whatever a draft claims alongside it.
        let routines = try PlanValidator.routines(from: draft([move(.rings, pounds)]))
        let ring = try #require(routines.first?.routine.moves.first)
        #expect(ring.loadPounds == 5, "took the draft's load instead of the library's")
        #expect(Equipment.rings.availableLoadsPounds.contains(ring.loadPounds ?? 0))
    }

    // The ladder after the August 2026 purchases. Each line is something in
    // the house; the test exists so a load cannot be quietly dropped or
    // invented without this file noticing.
    @Test("The kit's ladder matches what is in the house")
    func ladder() {
        #expect(Equipment.dumbbells.availableLoadsPounds == [2, 3, 5])
        #expect(Equipment.singleDumbbell.availableLoadsPounds == [10, 15])
        #expect(Equipment.rings.availableLoadsPounds == [5, 8, 10])
        #expect(Equipment.beam.availableLoadsPounds == [15])
        #expect(Equipment.kettlebell.availableLoadsPounds == [9, 13, 18, 35])
        #expect(Equipment.singleDumbbell.label(forLoad: 15) == "One 15 lb dumbbell")
        #expect(Equipment.kettlebell.label(forLoad: 35) == "35 lb kettlebell")
    }

    @Test("The beam is fifteen pounds whatever a draft says")
    func impossibleBeamLoad() throws {
        let routines = try PlanValidator.routines(from: draft([move(.beam, 25)]))
        let beam = try #require(routines.first?.routine.moves.first)
        #expect(beam.loadPounds == 15)
    }

    @Test("Rejects equipment that does not exist")
    func unknownEquipment() {
        let barbell = DraftMove(name: "Back squat", equipment: "barbell", cue: "", loadPounds: 95)
        #expect(throws: PlanValidator.Failure.self) {
            try PlanValidator.routines(from: draft([barbell]))
        }
    }

    @Test("A bodyweight move carries no load whatever a draft says")
    func loadOnBodyweight() throws {
        let routines = try PlanValidator.routines(from: draft([move(.bodyweight, 10)]))
        let move = try #require(routines.first?.routine.moves.first)
        #expect(move.loadPounds == nil)
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
        // The bad half names a move outside the closed library — which is what
        // "impossible" means now that loads and equipment are the library's to
        // supply rather than the model's to state.
        let mixed = PlanDraft(explanation: "x", sessions: [
            DraftSession(dayOffset: 0, title: "Good", work: 40, rest: 45, rounds: 8,
                         moves: [move(.beam, 15)]),
            DraftSession(dayOffset: 2, title: "Bad", work: 40, rest: 45, rounds: 8,
                         moves: [DraftMove(name: "Barbell back squat")])
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

    @Test("A timeout does not report itself as being offline")
    func transportFailuresAreToldApart() throws {
        // These four arrived at the same sentence for a long time, and the
        // one that actually happens — the model thinking past the clock on a
        // phone that is perfectly online — read as "No connection to Claude".
        let timedOut = try #require(PlannerError.transport(URLError(.timedOut)).errorDescription)
        #expect(timedOut.contains("did not answer within"))
        #expect(!timedOut.contains("No connection"))

        let offline = try #require(
            PlannerError.transport(URLError(.notConnectedToInternet)).errorDescription)
        #expect(offline.contains("No connection to Claude"))

        let stopped = try #require(PlannerError.transport(URLError(.cancelled)).errorDescription)
        #expect(stopped.contains("cancelled"))

        // Every one of them still says where the week came from.
        for sentence in [timedOut, offline, stopped] {
            #expect(sentence.contains("drawn from the plan's own rules"))
        }
    }

    @Test("Allows the model longer to think than one answer takes to arrive")
    func timeoutHasRoomForThinking() {
        // `timeoutInterval` is the gap between packets, and a non-streamed
        // request sends nothing until generation finishes — so this is a
        // ceiling on thinking, not on the network.
        #expect(ClaudePlanner.timeout >= 300)
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
        #expect(!PlannerService.isPlanned(3, of: block, in: context))

        let outcome = await PlannerService.planCurrentWeekIfNeeded(for: block, in: context, planner: .blocked)
        let written = try! #require(outcome)
        #expect(written.sessionsWritten == block.pace.sessionsPerWeek)
        #expect(PlannerService.isPlanned(3, of: block, in: context))
    }

    @Test("Planning an already-planned week does nothing")
    func idempotent() async {
        let (block, context) = block(daysAgo: 0)
        _ = await PlannerService.planCurrentWeekIfNeeded(for: block, in: context, planner: .blocked)
        let sessionCount = block.sessions?.count ?? 0

        let second = await PlannerService.planCurrentWeekIfNeeded(for: block, in: context, planner: .blocked)
        #expect(second == nil, "a second pass must not rewrite the week")
        #expect(block.sessions?.count == sessionCount)
    }

    @Test("A finished block is not extended")
    func doesNotExtendPastTheEnd() async {
        let (block, context) = block(daysAgo: 90)
        let outcome = await PlannerService.planCurrentWeekIfNeeded(for: block, in: context, planner: .blocked)
        #expect(outcome == nil)
        #expect(block.sessions?.isEmpty ?? true)
    }

    @Test("Sessions land inside the week they were planned for")
    func sessionsLandInTheirWeek() async {
        let (block, context) = block(daysAgo: 21)   // week 4
        _ = await PlannerService.planCurrentWeekIfNeeded(for: block, in: context, planner: .blocked)

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
        _ = await PlannerService.planCurrentWeekIfNeeded(for: block, in: context, planner: .blocked)

        let done = try! #require(block.sessions?.first)
        done.completedAt = .now
        let doneID = done.id

        // Force a rewrite of the same week.
        _ = await PlannerService.planWeek(1, of: block, in: context, planner: .blocked)

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
        // The kettlebell day opens on the kettlebell deadlift.
        let plain = OfflinePlanner.week(1, pace: .building, moves: 5)
        #expect(plain.sessions.flatMap(\.moves).contains { $0.name == "Kettlebell deadlift" })

        let avoided = OfflinePlanner.week(1, pace: .building,
                                          avoiding: ["kettlebell deadlift"], moves: 5)
        #expect(!avoided.sessions.flatMap(\.moves).contains { $0.name == "Kettlebell deadlift" })
        // And the week is still a valid, full week.
        let routines = try PlanValidator.routines(from: avoided)
        #expect(routines.count == Pace.building.sessionsPerWeek)
        for session in avoided.sessions { #expect(session.moves.count == 5) }
    }

    @Test("Substitution keeps the equipment it replaced")
    func substitutionKeepsEquipment() {
        let week = OfflinePlanner.week(1, pace: .building, avoiding: ["kettlebell deadlift"])
        // The kettlebell day still uses the bell; only the hinge changed.
        let bell = week.sessions.first { $0.title.contains("kettlebell") }
        #expect(bell?.moves.contains { $0.equipment == Equipment.kettlebell.rawValue } == true)
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
        // "Round 3 / 8" rather than "of" — the card now reads its position from
        // `Phase.position`, the same call the timer header and the lock screen
        // use, so the three cannot word the same session differently. It also
        // knows a flow movement is not a round, which is what stopped the
        // practice's card reading "Round 4 of 0".
        let text = session(elapsed: 180, savedAgo: 0).summary()
        #expect(text.contains("Round 3 / 8"))
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
        // After the last movement, the setup pause, then round one.
        #expect(schedule.phases[4].isRest)
        #expect(schedule.phases[5].isWork)
        #expect(schedule.flowPhaseCount == 4)
        #expect(schedule.workPhaseCount == 4)
        #expect(Array(schedule.phases.map(\.round).prefix(4)) == [1, 2, 3, 4])
    }

    @Test("A setup pause sits between the practice and round one — time to get the kit out")
    func setupPause() {
        let schedule = session(warmUp: 4).schedule
        #expect(schedule.phases[4].isRest)
        #expect(schedule.phases[4].duration == WarmUp.setupSeconds)
        // No set precedes it, so it asks for no reps.
        #expect(schedule.setEnding(before: 4) == nil)

        // The morning practice never gets one: all flow, no work coming, and
        // a pause at the end would count down at the ritual it closes.
        let practice = IntervalRoutine(name: "Practice", work: 0, rest: 0, rounds: 0, moves: [])
            .warmingUp(with: Array(MoveLibrary.flow.prefix(3)), seconds: 60)
        #expect(practice.schedule.phases.allSatisfy { $0.isFlow })

        // A session with no warm-up starts when she presses start — the pause
        // belongs to the seam between flow and work, not to every routine.
        let bare = IntervalRoutine(name: "Bare", work: 40, rest: 30, rounds: 4,
                                   moves: [MoveLibrary.all[0]])
        #expect(bare.schedule.phases.first?.isWork == true)
    }

    @Test("The practice is additive — it never costs a round or a second of work")
    func additive() {
        let bare = IntervalRoutine(name: "Test", work: 40, rest: 30, rounds: 4,
                                   moves: [MoveLibrary.all[0]])
        let warmed = session(warmUp: 4)
        #expect(warmed.rounds == bare.rounds)
        #expect(warmed.clampedWork == bare.clampedWork)
        #expect(warmed.totalDuration
                == bare.totalDuration + 4 * WarmUp.seconds + WarmUp.setupSeconds)
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
        // Straight through both flow movements and the setup pause, second by
        // second.
        for _ in 0..<Int(WarmUp.seconds * 2 + WarmUp.setupSeconds) {
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
@MainActor
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

    // The point of closing the library: no fallback, no matching. Every move
    // the app can be asked to draw has a drawing — except the ones her call
    // deferred, which must have *none* rather than a borrowed one.
    @Test("Every move in the library has a strip, unless deferred — then none")
    func libraryIsCovered() {
        for move in MoveLibrary.all {
            if MovePlates.deferred.contains(MovePreference.key(move.name)) {
                #expect(MovePlates.strip(for: move) == nil,
                        "\(move.name) is deferred but resolved to a plate")
            } else {
                #expect(MovePlates.strip(for: move) != nil, "no strip for \(move.name)")
            }
        }
    }

    @Test("A move outside the library has none, and is never guessed at")
    func outsideTheLibrary() {
        // Names the planner might invent that the library does not hold.
        // "Ring goblet squat" and "Beam reverse lunge" used to be here and are
        // now real moves — which is the point of adding to a closed library
        // rather than loosening the match.
        // "Side plank" was the example here until it was drawn in August 2026.
        for name in ["Chin tuck", "Turkish get-up", "Kettlebell swing",
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
        // The pad's two moves are gone from the library, so they have no plate
        // — nil rather than a drawing of something else, which is the whole
        // point of the lookup being a lookup.
        #expect(key("Incline walk", .walkingPad) == nil)
        #expect(key("Zone 2 walk", .walkingPad) == nil)
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
                             "floor press", "pullover",
                             // The mat, August 2026: none of these stand.
                             "forearm plank", "side plank", "lying leg raise", "bicycle crunch", "plank shoulder tap", "superman", "one-leg bridge", "side leg lift", "reverse tabletop hold", "russian twist", "plank pull-through", "thread the needle", "child's pose reach", "tall-kneeling press", "single-dumbbell floor press"]

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
         "floor press", "pullover",
         // Supine additions (August 2026): each places its knee rather than
         // solving it, exactly as the glute bridge does.
         "beam triceps extension", "ring bridge", "dead bug press",
         "dumbbell floor press",
         // The mat and the kneel (August 2026) place every joint.
         "forearm plank", "side plank", "lying leg raise", "bicycle crunch", "plank shoulder tap", "superman", "one-leg bridge", "side leg lift", "reverse tabletop hold", "russian twist", "plank pull-through", "thread the needle", "child's pose reach", "tall-kneeling press", "single-dumbbell floor press"].contains(strip.key)
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

    @Test("A move is a name and nothing else")
    func moveIsJustAName() throws {
        // A load the kit cannot be set to used to be expressible-and-rejected.
        // It is now not expressible: the schema asks for a name, and the closed
        // library supplies the equipment, the cue and the load for it.
        //
        // That is also what brought the compiled grammar back under its size
        // limit. Four fields, each paid for once per move slot per session —
        // twenty-five times at the hard pace — is what returned 400, "schema
        // too complex".
        let defs = try #require(ClaudePlanner.schema(sessions: 4)["$defs"] as? [String: Any])
        let move = try #require(defs["move"] as? [String: Any])
        let properties = try #require(move["properties"] as? [String: Any])

        #expect(Array(properties.keys) == ["name"])
        #expect(move["required"] as? [String] == ["name"])
        #expect(properties["loadPounds"] == nil)
        #expect(properties["equipment"] == nil)
        #expect(properties["cue"] == nil)

        // Every load the app can produce is still one the kit offers — it just
        // comes from the library rather than from the model.
        let real = Set(Equipment.allCases.flatMap(\.availableLoadsPounds))
        for move in MoveLibrary.all where move.loadPounds != nil {
            #expect(real.contains(move.loadPounds ?? 0), "\(move.name) names a load the kit lacks")
        }
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

    @Test("The library's declaration order is not welded into the practice")
    func neighboursVary() {
        // The window used to be a contiguous run, so whatever sat on the next
        // line of `Equipment.swift` sat next to it in every practice it ever
        // appeared in. Corkscrew followed Arm circles every time, for no
        // reason but the order they were typed in.
        //
        // Consecutive days differing was already tested and already true —
        // the *start* moved. This is the property that was not: that being in
        // one practice together does not mean being in all of them together.
        var successors: [String: Set<String>] = [:]
        var seen: [String: Int] = [:]
        for day in 0..<60 {
            let names = Practice.moves(on: monday.addingTimeInterval(Double(day) * 86_400),
                                       count: 8).map(\.name)
            for name in names.dropLast() { seen[name, default: 0] += 1 }
            for (a, b) in zip(names, names.dropFirst()) {
                successors[a, default: []].insert(b)
            }
        }
        // Only movements that turned up often enough for "always" to mean
        // anything. A movement seen twice having one successor is chance.
        let welded = successors.filter { seen[$0.key, default: 0] >= 3 && $0.value.count == 1 }
        #expect(welded.isEmpty,
                "always followed by the same movement: \(welded.keys.sorted())")
    }

    @Test("Every spacing the walk can take still lands on distinct movements")
    func walkNeverRepeatsWithinADay() {
        // The whole reason the step has to be coprime with the pool. If it
        // ever is not, a practice asks for the same movement twice and the
        // warm-up that reads "what the practice did not use" gets it wrong
        // in the same breath.
        for pool in 1...40 {
            for step in Rotation.steps(for: pool) {
                let landed = (0..<pool).map { ($0 * step) % pool }
                #expect(Set(landed).count == pool,
                        "a step of \(step) repeats inside a pool of \(pool)")
            }
        }
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

@Suite("A rotation is not the library's table of contents")
struct RotationOrderTests {

    @Test("The declaration order is not welded into a rotation")
    func neighboursVary() {
        // The strength twin of the morning practice's bug, and the blunter
        // version: this took the *first* N moves of the library and did not
        // vary at all, so whatever sat next to a move in `Equipment.swift`
        // sat next to it in every rotation it ever appeared in.
        //
        // A rotation now has a fixed *shape* — hinge, squat or lunge, row,
        // push, floor — so the neighbour of a slot is always the next slot.
        // What must still vary is which hinge, which row: every slot has to
        // see several different moves across the turns.
        var perSlot: [Int: Set<String>] = [:]
        for turn in 0..<60 {
            let names = MoveLibrary.rotation(of: 5, varying: turn).map(\.name)
            #expect(names.count == 5)
            #expect(Set(names).count == names.count, "turn \(turn) named a move twice")
            for (slot, name) in names.enumerated() { perSlot[slot, default: []].insert(name) }
        }
        for (slot, seen) in perSlot {
            #expect(seen.count >= 3, "slot \(slot) only ever offered \(seen.sorted())")
        }
        let prefix = MoveLibrary.available.filter { $0.kind == .strength }.prefix(5).map(\.name)
        #expect(MoveLibrary.rotation(of: 5, varying: 0).map(\.name) != prefix)
    }

    @Test("Varying never reaches past a refusal or repeats what is in hand")
    func stillHonoursTheRules() {
        // The walk changed which moves come back. It must not have changed
        // which moves are allowed to.
        let ruledOut: Set<String> = ["push-up"]
        let inHand = Set(["Beam front squat"].map { MovePreference.key($0) })
        for turn in 0..<40 {
            let picked = MoveLibrary.rotation(of: 6, avoiding: ruledOut,
                                              excluding: inHand, varying: turn)
            for move in picked {
                // Containment, so the incline and knee variants go too.
                #expect(!MovePreference.anyCovers(ruledOut, move.name))
                #expect(!inHand.contains(MovePreference.key(move.name)))
                #expect(move.kind == .strength)
                #expect(move.equipment.isOwned)
            }
        }
    }

    @Test("Preferred kit is still spent before anything else")
    func preferenceSurvivesTheWalk() {
        // The walk varies inside each half, never across them — a beam day
        // filling up with dumbbells is what `preferring` exists to stop.
        let beam = MoveLibrary.moves(for: .beam)
        for turn in 0..<20 {
            let picked = MoveLibrary.rotation(of: 3, preferring: [.beam], varying: turn)
            #expect(picked.count == 3)
            #expect(picked.allSatisfy { $0.equipment == .beam },
                    "turn \(turn) reached off the beam with \(beam.count) beam moves free")
        }
    }

    @Test("The same turn always gives the same rotation")
    func stable() {
        // A plan she opens twice reads the same both times. This is why the
        // walk takes a seed rather than shuffling.
        for turn in 0..<10 {
            #expect(MoveLibrary.rotation(of: 5, varying: turn).map(\.name)
                    == MoveLibrary.rotation(of: 5, varying: turn).map(\.name))
        }
    }

    @Test("Sessions in one offline week do not all end with the same two moves")
    func offlineTopUpVaries() {
        // The templates hold three moves and a rotation is five, so every
        // offline session is topped up. All of them used to be topped up
        // identically.
        let week = OfflinePlanner.week(1, pace: .hard, moves: 5)
        let fillers = week.sessions.map {
            $0.moves.suffix(2).map(\.name).joined(separator: "|")
        }
        #expect(fillers.count >= 4)
        #expect(Set(fillers).count > 1, "every session filled with \(fillers.first ?? "")")
    }

    @Test("The next offline week asks for the same moves, not new ones")
    func offlineWeeksRepeatOnPurpose() {
        // Deliberately unchanged: repeating a week is how a movement gets
        // easier before the numbers do, and the explanation says so. Only the
        // rest and the rounds move.
        let first = OfflinePlanner.week(1, pace: .hard, moves: 5)
        let later = OfflinePlanner.week(2, pace: .hard, moves: 5)
        #expect(first.sessions.map { $0.moves.map(\.name) }
                == later.sessions.map { $0.moves.map(\.name) })
    }

    @Test("A topped-up offline week still passes the validator")
    func offlineWeekSurvivesValidation() throws {
        // The top-up used to walk `MoveLibrary.all`, so it could name kit she
        // does not own — and the validator rejects a week whole, which would
        // throw away the plan that is supposed to be the floor.
        for size in Tuning.movesPerSessionRange {
            for pace in Pace.allCases {
                let week = OfflinePlanner.week(3, pace: pace, moves: size)
                _ = try PlanValidator.routines(from: week)
                for session in week.sessions {
                    #expect(session.moves.count == size)
                    #expect(Set(session.moves.map(\.name)).count == session.moves.count)
                }
            }
        }
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

        // Every name offered is one she owns and the library holds. Compared
        // this way rather than against `Set(MoveLibrary.names)` taken a moment
        // later: `names` reads what she owns, and a suite running beside this
        // one can change that between the two reads.
        #expect(!offered.isEmpty)
        #expect(Set(offered).isSubset(of: Set(MoveLibrary.all.map(\.name))))
        #expect(offered.allSatisfy { name in
            MoveLibrary.all.first { $0.name == name }?.kind == .strength
        })
        // The failure this closes: the planner inventing a name the app then
        // had to guess the shape of.
        #expect(!offered.contains("Beam goblet squat"))

        // And not a flow movement anywhere in it. The only place a generated
        // move lands is the rotation, where it becomes a work phase and gets
        // counted down at — so offering the spinal wave here was offering to
        // program a practice as a forty-second set.
        let flow = Set(MoveLibrary.flow.map(\.name))
        #expect(Set(offered).isDisjoint(with: flow))
        #expect(!flow.isEmpty, "the library has no flow movements to exclude")
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

    @Test("The kit comes from the library, not from the draft")
    func validatorTakesEquipmentFromTheLibrary() throws {
        // Also no longer a rejection, for the same reason: equipment is not a
        // field the model fills in. A legal name determines it, so a draft
        // claiming the wrong kit cannot survive as one — it simply is not read.
        let draft = DraftMove(name: "Beam deadlift", equipment: "dumbbells",
                              cue: "No.", loadPounds: 2)
        let move = try PlanValidator.move(from: draft)
        #expect(move.equipment == .beam)
        #expect(move.loadPounds == 15)
        // And the cue is the authored one, not whatever came back.
        #expect(move.cue != "No.")
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
            // An array now, not named slots. The slots made the count a schema
            // guarantee, which `minItems` cannot express — but they cost one
            // whole move definition each, and at five sessions of five that was
            // what the grammar could not compile.
            //
            // The count is still enforced, just a layer later: `plan` counts the
            // moves in every session, hands a short week back to the model with
            // the reason, and falls to the offline planner if the repair turn
            // does not fix it. The number is named in the description so the
            // model is told, and checked afterwards so it cannot be ignored.
            #expect(moves["type"] as? String == "array")
            let items = try #require(moves["items"] as? [String: Any])
            #expect(items["$ref"] as? String == "#/$defs/move")
            let description = try #require(moves["description"] as? String)
            #expect(description.contains("\(count)"))
        }
    }

    @Test("The offline planner fills the rotation without repeating a move")
    func offlineFollows() {
        defer { Tuning.reset() }
        for count in Tuning.movesPerSessionRange {
            Tuning.movesPerSession = count
            for pace in Pace.allCases {
                let draft = OfflinePlanner.week(1, pace: pace, moves: count)
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

    @Test("Ten seconds unless she says otherwise")
    func defaultsToTen() {
        Tuning.reset()
        #expect(Tuning.plateSeconds == 10)
    }

    @Test("Bounded at both ends rather than free")
    func clamps() {
        Tuning.reset()
        Tuning.plateSeconds = 99
        #expect(Tuning.plateSeconds == Tuning.plateRange.upperBound)
        Tuning.plateSeconds = 0
        #expect(Tuning.plateSeconds == Tuning.plateRange.lowerBound)
        Tuning.reset()
    }

    @Test("Reset puts it back to the default, not to zero")
    func resets() {
        Tuning.plateSeconds = 17
        #expect(Tuning.plateSeconds == 17)
        Tuning.reset()
        #expect(Tuning.plateSeconds == Tuning.defaultPlateSeconds)
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
        // The setup pause, then her first written interval.
        #expect(phases[3].isRest)
        #expect(phases[4].isWork)
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

@Suite("Ruling a move out repairs today", .serialized)
@MainActor
struct PlanRepairTests {

    private func store() throws -> ModelContext {
        ModelContext(try ModelContainer(
            for: Store.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
    }

    /// A session scheduled for today, holding the given moves.
    private func session(_ moves: [Move], in context: ModelContext) -> PlannedSession {
        let routine = IntervalRoutine(name: "Push · dumbbells", work: 40, rest: 45,
                                      rounds: 8, moves: moves)
        let session = PlannedSession(scheduledFor: .now, title: routine.name, routine: routine)
        context.insert(session)
        return session
    }

    private func move(_ name: String, _ equipment: Equipment) -> Move {
        MoveLibrary.all.first { $0.name == name }
            ?? Move(name: name, equipment: equipment, cue: "")
    }

    @Test("Saying a move hurts takes it out of today's session")
    func replacesInToday() throws {
        let context = try store()
        let planned = session([move("Incline push-up", .bodyweight),
                               move("Dead bug", .bodyweight)], in: context)

        let summary = MovePreferences.set(.avoided, for: "Incline push-up", in: context)

        #expect(summary.sessionsChanged == 1)
        let names = try #require(planned.routine?.moves.map(\.name))
        #expect(!names.contains("Incline push-up"), "it is still there: \(names)")
        #expect(names.count == 2, "the rotation was trimmed rather than repaired")
    }

    /// Her actual case: the planner invented "Knee push-up" before the library
    /// closed, so the move in the session is not one the library holds.
    @Test("A move the library never had is still replaced")
    func replacesAnInventedName() throws {
        let context = try store()
        let invented = Move(name: "Knee push-up", equipment: .bodyweight,
                            cue: "Knees down, hands under the shoulders.")
        let planned = session([move("Lateral raise", .dumbbells), invented], in: context)

        let summary = MovePreferences.set(.avoided, for: "Knee push-up", in: context)

        #expect(summary.sessionsChanged == 1, "nothing was rewritten")
        let names = try #require(planned.routine?.moves.map(\.name))
        #expect(!names.contains("Knee push-up"), "it is still there: \(names)")
    }

    @Test("A finished session is never rewritten")
    func leavesFinishedAlone() throws {
        let context = try store()
        let planned = session([move("Dead bug", .bodyweight)], in: context)
        planned.completedAt = .now

        _ = MovePreferences.set(.avoided, for: "Dead bug", in: context)
        #expect(planned.routine?.moves.first?.name == "Dead bug",
                "a record of what happened was rewritten")
    }

    @Test("With nothing free on that kit, the move stays rather than the slot emptying")
    func staysWhenNothingIsFree() throws {
        let context = try store()
        let all = MoveLibrary.moves(for: .bodyweight)
        let planned = session([all[0]], in: context)
        // Rule out every other bodyweight move first.
        MovePreferences.apply(.avoided, to: all.dropFirst().map(\.name), in: context)

        let summary = MovePreferences.set(.avoided, for: all[0].name, in: context)
        #expect(summary.slotsLeft == 1)
        #expect(planned.routine?.moves.count == 1)
    }
}

@Suite("Resizing a rotation needs no model", .serialized)
@MainActor
struct RotationResizeTests {

    private func store() throws -> ModelContext {
        ModelContext(try ModelContainer(
            for: Store.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
    }

    @discardableResult
    private func session(_ moves: [Move], in context: ModelContext,
                         done: Bool = false) -> PlannedSession {
        let routine = IntervalRoutine(name: "Lower · beam", work: 40, rest: 45,
                                      rounds: 8, moves: moves)
        let session = PlannedSession(scheduledFor: .now, title: routine.name, routine: routine)
        if done { session.completedAt = .now }
        context.insert(session)
        return session
    }

    private var beam: [Move] { MoveLibrary.moves(for: .beam) }

    @Test("Growing the rotation fills it without a Claude request")
    func grows() throws {
        let context = try store()
        let planned = session(Array(beam.prefix(3)), in: context)

        let summary = PlanRepair.resize(to: 5, in: context)

        #expect(summary.sessionsChanged == 1)
        let moves = try #require(planned.routine?.moves)
        #expect(moves.count == 5)
        #expect(Set(moves.map(\.name)).count == 5, "a move was repeated")
        // The three it had are all still there: growing adds — and puts the
        // session in running order — but drops nothing.
        #expect(Set(beam.prefix(3).map(\.name)).isSubset(of: Set(moves.map(\.name))))
    }

    @Test("It leans on the kit the session already uses")
    func keepsTheKit() throws {
        let context = try store()
        let planned = session(Array(beam.prefix(2)), in: context)
        PlanRepair.resize(to: 4, in: context)

        let added = try #require(planned.routine?.moves.dropFirst(2))
        #expect(added.allSatisfy { $0.equipment == .beam },
                "a beam day filled up with something else: \(added.map(\.name))")
    }

    @Test("Shrinking keeps one of each pattern before a second of any")
    func shrinks() throws {
        let context = try store()
        let planned = session(beam, in: context)
        PlanRepair.resize(to: 2, in: context)
        // All thirteen beam moves, cut to two: the hinge and the squat, in
        // running order — not the first two as typed into the library.
        #expect(planned.routine?.moves.map(\.name) == ["Beam deadlift", "Beam front squat"])
    }

    @Test("It never reaches past something she has ruled out")
    func honoursRefusals() throws {
        let context = try store()
        let planned = session([beam[0]], in: context)
        MovePreferences.apply(.avoided, to: [beam[1].name], in: context)

        PlanRepair.resize(to: 5, in: context)
        let names = try #require(planned.routine?.moves.map(\.name))
        #expect(!names.contains(beam[1].name))
    }

    @Test("A finished session keeps the shape it was done in")
    func leavesFinishedAlone() throws {
        let context = try store()
        let planned = session(Array(beam.prefix(2)), in: context, done: true)
        let summary = PlanRepair.resize(to: 5, in: context)
        #expect(summary.sessionsChanged == 0)
        #expect(planned.routine?.moves.count == 2)
    }

    @Test("Resizing to the size it already is changes nothing")
    func noOp() throws {
        let context = try store()
        session(Array(beam.prefix(3)), in: context)
        #expect(PlanRepair.resize(to: 3, in: context).sessionsChanged == 0)
    }

    @Test("A timer-only session is left alone")
    func skipsMovelessSessions() throws {
        let context = try store()
        let planned = session([], in: context)
        #expect(PlanRepair.resize(to: 5, in: context).sessionsChanged == 0)
        #expect(planned.routine?.moves.isEmpty == true)
    }
}

@Suite("When the model is worth asking", .serialized)
@MainActor
struct PlanTriggerTests {

    private func store() throws -> ModelContext {
        ModelContext(try ModelContainer(
            for: Store.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
    }

    private func block(in context: ModelContext, startingDaysAgo days: Int = 21) -> Block {
        let block = Block(startDate: Date.now.addingTimeInterval(-Double(days) * 86_400),
                          goalWeightPounds: 150, startingWeightPounds: 165)
        context.insert(block)
        return block
    }

    private func session(_ daysAgo: Int, done: Bool, on block: Block, in context: ModelContext) {
        let routine = IntervalRoutine(name: "S", work: 40, rest: 45, rounds: 8, moves: [])
        let s = PlannedSession(scheduledFor: Date.now.addingTimeInterval(-Double(daysAgo) * 86_400),
                               title: "S", routine: routine)
        if done { s.completedAt = .now }
        s.block = block
        context.insert(s)
    }

    /// Without a key the question never arises — the offline planner is the
    /// plan, not a fallback.
    @Test("With no key set it never asks")
    func noKey() throws {
        let context = try store()
        let block = block(in: context)
        let decision = PlanTrigger.decide(week: 3, of: block, in: context, hasKey: false)
        #expect(!decision.asksClaude)
        #expect(decision.reason.contains("No key"))
    }

    @Test("A clean week steps on rather than being written again")
    func cleanWeekSteps() throws {
        let context = try store()
        let block = block(in: context)
        session(3, done: true, on: block, in: context)
        session(5, done: true, on: block, in: context)
        UserDefaults.standard.set(Date.now, forKey: PlanTrigger.Memo.lastAsked)
        defer { UserDefaults.standard.removeObject(forKey: PlanTrigger.Memo.lastAsked) }

        // Week 3 is not a check-in week and nothing changed.
        let decision = PlanTrigger.decide(week: 3, of: block, in: context, hasKey: true)
        #expect(!decision.asksClaude)
        #expect(decision.reason.contains("Nothing changed"))
    }

    @Test("A missed session is exactly what the model is for")
    func missedAsks() throws {
        let context = try store()
        let block = block(in: context)
        session(2, done: false, on: block, in: context)
        UserDefaults.standard.set(Date.now, forKey: PlanTrigger.Memo.lastAsked)
        defer { UserDefaults.standard.removeObject(forKey: PlanTrigger.Memo.lastAsked) }

        let decision = PlanTrigger.decide(week: 3, of: block, in: context, hasKey: true)
        #expect(decision.asksClaude)
        #expect(decision.reason.contains("undone"))
    }

    @Test("Week one is always written fresh")
    func weekOneAsks() throws {
        let context = try store()
        let block = block(in: context, startingDaysAgo: 0)
        #expect(PlanTrigger.decide(week: 1, of: block, in: context, hasKey: true).asksClaude)
    }

    @Test("A check-in lands every fourth week so it cannot drift")
    func checkInWeeks() throws {
        let context = try store()
        let block = block(in: context)
        UserDefaults.standard.set(Date.now, forKey: PlanTrigger.Memo.lastAsked)
        defer { UserDefaults.standard.removeObject(forKey: PlanTrigger.Memo.lastAsked) }

        for week in [5, 9] {
            #expect(PlanTrigger.decide(week: week, of: block, in: context, hasKey: true).asksClaude,
                    "week \(week) should be a check-in")
        }
    }

    @Test("Over twelve weeks this is a handful of requests, not twelve")
    func costOverABlock() throws {
        // The point of the whole thing, stated as an assertion: a block where
        // she turns up is a few calls, not one a week.
        let context = try store()
        let block = block(in: context)
        for day in 1...13 { session(day, done: true, on: block, in: context) }
        UserDefaults.standard.set(Date.now, forKey: PlanTrigger.Memo.lastAsked)
        defer { UserDefaults.standard.removeObject(forKey: PlanTrigger.Memo.lastAsked) }

        let asks = (1...12).filter {
            PlanTrigger.decide(week: $0, of: block, in: context, hasKey: true).asksClaude
        }
        #expect(asks.count <= 5, "a clean block asked \(asks.count) times")
    }
}

@Suite("Six in the morning")
@MainActor
struct PlanSchedulerTests {

    /// A fixed zone so the test says the same thing wherever it runs.
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar
    }

    private func date(_ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day,
                                           hour: hour, minute: minute))!
    }

    @Test("A night owl still wakes to a plan")
    func laterTonight() {
        // Half past one in the morning: six is still ahead, today.
        let next = PlanScheduler.nextMorning(after: date(7, 28, 1, 30), calendar: calendar)
        #expect(next == date(7, 28, 6))
    }

    @Test("Past six means tomorrow, not this instant")
    func alreadyPast() {
        // The trap this guards is `nextDate` matching the time that just went
        // by, which would make the request eligible immediately and burn the
        // morning slot at nine at night.
        let next = PlanScheduler.nextMorning(after: date(7, 28, 21, 0), calendar: calendar)
        #expect(next == date(7, 29, 6))
    }

    @Test("Six o'clock exactly means the next one")
    func onTheHour() {
        #expect(PlanScheduler.nextMorning(after: date(7, 28, 6), calendar: calendar)
                == date(7, 29, 6))
    }

    @Test("It is always ahead, whatever hour it is asked at")
    func alwaysFuture() {
        for hour in 0..<24 {
            let now = date(7, 28, hour, 17)
            #expect(PlanScheduler.nextMorning(after: now, calendar: calendar) > now)
        }
    }

    @Test("The plist permits the identifier the code registers")
    func identifierIsDeclared() throws {
        // These two live in different files and nothing but this test connects
        // them. A mismatch is not a misbehaviour — `register` traps, and the
        // app dies at launch.
        let permitted = Bundle.main
            .object(forInfoDictionaryKey: "BGTaskSchedulerPermittedIdentifiers") as? [String]
        #expect(permitted?.contains(PlanScheduler.taskIdentifier) == true,
                "Info.plist permits \(permitted ?? []), code registers \(PlanScheduler.taskIdentifier)")
    }
}

@Suite("The audit's findings, held down")
@MainActor
struct AuditRegressionTests {

    // MARK: A week that is planned is a week that is saved

    @Test("Planning saves, so a context that does not autosave still keeps the week")
    func planningSaves() async throws {
        // The six a.m. background task must build its own `ModelContext`, and a
        // hand-made context has `autosaveEnabled == false`. Nothing in the
        // planner saved, so the week was inserted, never written, and dropped
        // when the context deallocated — after the request had been billed.
        let container = Store.container(inMemory: true)
        let writing = ModelContext(container)
        writing.autosaveEnabled = false

        let block = Block(startDate: .now, goalWeightPounds: 150, startingWeightPounds: 165)
        writing.insert(block)
        try writing.save()

        _ = await PlannerService.planWeek(1, of: block, in: writing, planner: .blocked)

        // A second, independent context sees it only if it actually reached the
        // store. Reading back through `writing` would pass either way.
        let reading = ModelContext(container)
        let stored = try reading.fetch(FetchDescriptor<PlannedSession>())
        #expect(!stored.isEmpty, "the week was never written to the store")
    }

    // MARK: A rewrite does not double up on a day already trained

    @Test("A rewritten week leaves no second session on a day she has finished")
    func rewriteRespectsAFinishedDay() async throws {
        let container = Store.container(inMemory: true)
        let context = ModelContext(container)
        let block = Block(startDate: .now, goalWeightPounds: 150, startingWeightPounds: 165)
        context.insert(block)

        _ = await PlannerService.planWeek(1, of: block, in: context, planner: .blocked)
        let first = try #require(
            (block.sessions ?? []).min(by: { $0.scheduledFor < $1.scheduledFor }))
        let trainedDay = Calendar.current.startOfDay(for: first.scheduledFor)
        first.completedAt = .now
        try context.save()

        _ = await PlannerService.planWeek(1, of: block, in: context, planner: .blocked)

        let onThatDay = (block.sessions ?? []).filter {
            Calendar.current.startOfDay(for: $0.scheduledFor) == trainedDay
        }
        #expect(onThatDay.count == 1, "a rewrite added a second session to a finished day")
        #expect(onThatDay.first?.isComplete == true)
    }

    // MARK: One rule for "ruled out"

    @Test("A dislike covers its variants wherever the question is asked")
    func ruledOutIsContainmentEverywhere() {
        // The app ships exactly one seeded preference — "push-up" — written so
        // it also covers the incline and knee variants. Three planner paths
        // compared exact names instead, so the first substitute offered for any
        // bodyweight move was the incline push-up she is on record as
        // disliking.
        let ruledOut: Set<String> = ["push-up"]
        #expect(MovePreference.anyCovers(ruledOut, "Incline push-up"))
        #expect(MovePreference.anyCovers(ruledOut, "Push-up"))
        #expect(!MovePreference.anyCovers(ruledOut, "Beam front squat"))
    }

    @Test("A substitute is never something she has ruled out")
    func substituteRespectsAVariant() throws {
        let bodyweight = MoveLibrary.all.filter { $0.equipment == .bodyweight && $0.kind == .strength }
        let source = try #require(bodyweight.first { !$0.name.lowercased().contains("push-up") })

        let swap = MoveLibrary.substitute(for: source, avoiding: ["push-up"])
        if let swap {
            #expect(!swap.name.lowercased().contains("push-up"),
                    "offered \(swap.name) against a recorded dislike of push-ups")
        }
    }

    // MARK: A resumed run knows what it is

    @Test("A resumed run carries its own subject rather than being guessed at the end")
    func activeSessionCarriesItsSubject() throws {
        var session = ActiveSession(routine: Practice.routine(on: .now), startedAt: .now,
                                    elapsed: 120, running: true, savedAt: .now)
        session.setSubject(ActiveSession.Subject.practice)

        let data = try JSONEncoder().encode(session)
        let back = try JSONDecoder().decode(ActiveSession.self, from: data)
        #expect(back.subject == .practice)

        let id = UUID()
        session.setSubject(ActiveSession.Subject.session(id))
        let asSession = try JSONDecoder().decode(
            ActiveSession.self, from: try JSONEncoder().encode(session))
        #expect(asSession.subject == .session(id))
    }

    @Test("A session stored by the previous build still decodes, as unknown")
    func oldActiveSessionDecodes() throws {
        // The stored copy is JSON on disk and the synthesized decoder throws on
        // a missing non-optional key, so both new fields must be Optional.
        let json = """
        {"routine":\(String(decoding: try JSONEncoder().encode(Practice.routine(on: .now)), as: UTF8.self)),
         "startedAt":0,"elapsed":60,"running":true,"savedAt":0}
        """
        let back = try JSONDecoder().decode(ActiveSession.self, from: Data(json.utf8))
        #expect(back.subject == .unknown)
    }

    @Test("The resume card never counts a practice in rounds it does not have")
    func practiceSummaryDoesNotSayRoundOfZero() {
        // `Practice.routine()` is built with zero rounds, so reading `rounds`
        // produced "Round 4 of 0".
        let session = ActiveSession(routine: Practice.routine(on: .now), startedAt: .now,
                                    elapsed: 180, running: false, savedAt: .now)
        let summary = session.summary()
        #expect(!summary.contains("of 0"), "\(summary)")
        #expect(summary.contains("Movement"), "\(summary)")
    }

    // MARK: The backup carries the whole store

    @Test("A backup carries her opinions, her practice history and the block's pace")
    func archiveCarriesEverything() throws {
        let container = Store.container(inMemory: true)
        let context = ModelContext(container)

        let block = Block(startDate: .now, goalWeightPounds: 150,
                          startingWeightPounds: 165, pace: .steady)
        context.insert(block)
        MovePreferences.set(.avoided, for: "Beam good morning", in: context)
        MorningPractices.record(Array(MoveLibrary.flow.prefix(3)), in: context)
        try context.save()

        let archive = try ArchiveService.export(from: context)
        #expect(archive.preferences.count == 1)
        #expect(archive.practices.count == 1)
        #expect(archive.blocks.first?.paceRaw == Pace.steady.rawValue)

        // Onto an empty store, as a new phone would be.
        let fresh = ModelContext(Store.container(inMemory: true))
        try ArchiveService.restore(archive, into: fresh)

        let lists = MovePreferences.lists(in: fresh)
        #expect(lists.avoided.contains("Beam good morning"),
                "a restore lost the move she said hurt")
        #expect(MorningPractices.all(in: fresh).count == 1)
        #expect(try fresh.fetch(FetchDescriptor<Block>()).first?.pace == .steady)
    }

    @Test("Restoring the same file twice adds nothing the second time")
    func restoreIsIdempotent() throws {
        let container = Store.container(inMemory: true)
        let context = ModelContext(container)
        let block = Block(startDate: .now, goalWeightPounds: 150, startingWeightPounds: 165)
        context.insert(block)
        MovePreferences.set(.disliked, for: "Ring row", in: context)
        MorningPractices.record(Array(MoveLibrary.flow.prefix(3)), in: context)
        try context.save()

        let archive = try ArchiveService.export(from: context)
        let fresh = ModelContext(Store.container(inMemory: true))
        try ArchiveService.restore(archive, into: fresh)
        try ArchiveService.restore(archive, into: fresh)

        #expect(MovePreferences.all(in: fresh).count == 1)
        #expect(MorningPractices.all(in: fresh).count == 1)
    }
}

@Suite("The audit's second tier")
@MainActor
struct AuditSecondTierTests {

    @Test("A workout is never longer than the routine that produced it")
    func healthDurationIsCapped() {
        // Pause for a phone call and resume half an hour later, and wall-clock
        // said a thirteen-minute routine was a forty-three-minute workout —
        // every one of those minutes counting toward the Exercise ring. Same
        // shape when the app is suspended and only discovers it finished on
        // the way back.
        let routine = IntervalRoutine(name: "Beam", work: 40, rest: 45, rounds: 8, moves: [])
        let start = Date(timeIntervalSince1970: 0)
        let total = routine.schedule.total
        let cappedEnd = min(start.addingTimeInterval(3_600),
                            start.addingTimeInterval(total))
        #expect(cappedEnd.timeIntervalSince(start) == total)
    }

    @Test("The weight import watermark ignores her own typed entries")
    func importWatermarkIsHealthOnly() {
        // Block setup writes a manual entry at `.now`, so watermarking on the
        // latest entry of any kind closed the ninety-day backfill on the very
        // first launch — and it could never reopen, because the mark only
        // moves forward.
        let now = Date()
        let entries = [
            WeightEntry(date: now, pounds: 165, source: .manual),
            WeightEntry(date: now.addingTimeInterval(-5 * 86_400), pounds: 166, source: .health)
        ]
        let watermark = entries.filter { $0.source == .health }.map(\.date).max()
        #expect(watermark == now.addingTimeInterval(-5 * 86_400))
        #expect(watermark != now)
    }

    @Test("Marks from before a block began are not counted as its first week")
    func marksBeforeTheBlockAreNotWeekOne() {
        // `dateComponents` returns a negative day count and integer division
        // truncates toward zero, so the six days before a block started all
        // landed in week 0 — a fresh block opening with the previous one's last
        // week already drawn on it.
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        for daysBefore in 1...6 {
            let done = calendar.date(byAdding: .day, value: -daysBefore, to: start)!
            let days = calendar.dateComponents([.day], from: start,
                                               to: calendar.startOfDay(for: done)).day ?? 0
            #expect(days < 0, "day \(daysBefore) before the block read as \(days)")
            #expect(days / 7 == 0, "and truncated into week 0, which is why the guard is on days")
        }
    }

    @Test("Token counts add across a repair turn rather than replacing each other")
    func usageAccumulates() {
        var total = ClaudePlanner.Usage()
        total += ClaudePlanner.Usage(inputTokens: 1_800, outputTokens: 4_000)
        total += ClaudePlanner.Usage(inputTokens: 6_200, outputTokens: 3_500)
        #expect(total.inputTokens == 8_000)
        #expect(total.outputTokens == 7_500)
        // A repaired week costs two requests and used to be recorded as one.
        #expect(total.dollars > ClaudePlanner.Usage(inputTokens: 6_200, outputTokens: 3_500).dollars)
    }

    @Test("Usage is read straight off a response body")
    func usageReadsRawData() {
        let body = Data(#"{"usage":{"input_tokens":1234,"output_tokens":567}}"#.utf8)
        let usage = ClaudePlanner.Usage.read(body)
        #expect(usage.inputTokens == 1234)
        #expect(usage.outputTokens == 567)
        #expect(ClaudePlanner.Usage.read(Data("not json".utf8)) == ClaudePlanner.Usage())
    }
}

@Suite("More than one workout a day")
@MainActor
struct ExtraWorkTests {

    private func store() -> ModelContext { ModelContext(Store.container(inMemory: true)) }

    // MARK: The record

    @Test("A finished routine is recorded, and is not a mark")
    func recordsWithoutMarking() throws {
        // Her call when asked: volume, not a mark. Rule 3 holds — the growth
        // form means "I did the plan" — but the work had been leaving nothing
        // behind at all, so a heavy week was invisible to her and the planner.
        let context = store()
        let block = Block(startDate: .now, goalWeightPounds: 150, startingWeightPounds: 165)
        context.insert(block)
        try context.save()

        let routine = IntervalRoutine(name: "Extra · beam", work: 40, rest: 45, rounds: 6,
                                      moves: [MoveLibrary.all[0]])
        RoutineRuns.record(routine, source: .extra, seconds: 300, in: context)

        let runs = RoutineRuns.all(in: context)
        #expect(runs.count == 1)
        #expect(runs.first?.roundsCompleted == 6)
        #expect(runs.first?.source == .extra)
        // The thing that must not have happened.
        let sessions = try context.fetch(FetchDescriptor<PlannedSession>())
        #expect(sessions.allSatisfy { !$0.isComplete })
    }

    @Test("A routine run survives a backup, and a second restore adds nothing")
    func archivesTheRun() throws {
        // A new model is not finished until it is in the archive — the store
        // once had eight types and the archive carried six.
        let context = store()
        let routine = IntervalRoutine(name: "Ladder", work: 30, rest: 30, rounds: 4, moves: [])
        RoutineRuns.record(routine, source: .saved, seconds: 240, in: context)

        let archive = try ArchiveService.export(from: context)
        #expect(archive.routineRuns.count == 1)

        let fresh = store()
        try ArchiveService.restore(archive, into: fresh)
        try ArchiveService.restore(archive, into: fresh)
        let restored = RoutineRuns.all(in: fresh)
        #expect(restored.count == 1, "a second restore duplicated the run")
        #expect(restored.first?.name == "Ladder")
        #expect(restored.first?.source == .saved)
    }

    // MARK: The composer

    @Test("An extra session never programs a move she has ruled out")
    func extraRespectsRefusals() {
        // Containment, so "push-up" bars the incline and knee variants.
        let extra = ExtraSession.build(week: 3, pace: .building, avoiding: ["push-up"])
        #expect(!extra.moves.isEmpty)
        #expect(extra.moves.allSatisfy { !$0.name.lowercased().contains("push-up") })
        #expect(extra.moves.allSatisfy { $0.kind == .strength })
    }

    @Test("An extra session is not the session she just did")
    func extraDoesNotRepeatToday() {
        let done = MoveLibrary.all.filter { $0.equipment == .beam && $0.kind == .strength }
        let extra = ExtraSession.build(week: 1, pace: .building, avoiding: [],
                                       notRepeating: done.map(\.name))
        let repeated = Set(extra.moves.map { MovePreference.key($0.name) })
            .intersection(done.map { MovePreference.key($0.name) })
        #expect(repeated.isEmpty, "offered \(repeated) again")
    }

    @Test("An extra session is shorter than the plan's, and opens with flow")
    func extraIsShorterAndWarmsUp() {
        let extra = ExtraSession.build(week: 6, pace: .hard, avoiding: [])
        let planned = OfflinePlanner.shape(week: 6, pace: .hard)
        #expect(extra.roundCount < planned.rounds)
        #expect(extra.roundCount >= ExtraSession.minimumRounds)
        #expect(!extra.warmUp.isEmpty)
        #expect(extra.warmUp.allSatisfy { $0.kind == .flow })
    }

    @Test("Every offered extra clears the seven-minute floor, warm-up included")
    func extraClearsTheTickFloor() {
        // Her ask: extras "are all 7 mins so they count" toward the form's
        // smaller ticks. The floor is on the written length — finishing the
        // whole offer is one session, warm-up and all.
        for week in 1...12 {
            for pace in [Pace.steady, .building, .hard] {
                let extra = ExtraSession.build(week: week, pace: pace, avoiding: [])
                #expect(extra.totalDuration >= RoutineRun.substantialSeconds,
                        "week \(week), \(pace.label): \(extra.totalDuration)s")
            }
        }
    }

    @Test("Everything ruled out still yields a session rather than a bare timer")
    func extraNeverEmpties() {
        // A rotation of nothing would be a plain interval timer presented as a
        // session. Refusals still hold; only the done-today exclusion relaxes.
        let everything = MoveLibrary.all.filter { $0.kind == .strength }.map(\.name)
        let extra = ExtraSession.build(week: 1, pace: .building, avoiding: [],
                                       notRepeating: everything)
        #expect(!extra.moves.isEmpty)
    }

    // MARK: One rotation builder

    @Test("The shared rotation builder respects both sets, differently")
    func rotationBuilder() {
        let out = MoveLibrary.rotation(of: 4, avoiding: ["push-up"])
        #expect(out.count == 4)
        #expect(Set(out.map(\.name)).count == 4, "returned a duplicate")
        #expect(out.allSatisfy { !$0.name.lowercased().contains("push-up") })

        // `excluding` is exact, so a near-name is still available.
        let beam = try? #require(MoveLibrary.all.first { $0.equipment == .beam })
        if let beam {
            let without = MoveLibrary.rotation(of: 3, excluding: [MovePreference.key(beam.name)])
            #expect(!without.contains { $0.name == beam.name })
        }
    }

    @Test("The rotation prefers the kit it is given")
    func rotationPrefersKit() {
        let out = MoveLibrary.rotation(of: 3, preferring: [.beam])
        #expect(out.first?.equipment == .beam)
    }

    // MARK: Considered by the planner

    @Test("The workload counts the last seven days")
    func workloadCounts() throws {
        let context = store()
        let block = Block(startDate: .now, goalWeightPounds: 150, startingWeightPounds: 165)
        context.insert(block)

        let today = PlannedSession(scheduledFor: .now, title: "Lower", routine: nil)
        today.block = block
        today.completedAt = .now
        context.insert(today)

        let old = PlannedSession(scheduledFor: Date.now.addingTimeInterval(-20 * 86_400),
                                 title: "Ancient", routine: nil)
        old.block = block
        old.completedAt = Date.now.addingTimeInterval(-20 * 86_400)
        context.insert(old)
        try context.save()

        let routine = IntervalRoutine(name: "Mine", work: 30, rest: 30, rounds: 5, moves: [])
        RoutineRuns.record(routine, source: .saved, seconds: 200, in: context)
        RoutineRuns.record(routine, source: .extra, seconds: 200, in: context)

        let workload = PlannerService.workload(for: block, in: context)
        #expect(workload.sessionsDone == 1)
        #expect(workload.sessionsPlanned == 1, "a session from three weeks ago was counted")
        #expect(workload.routineRuns == 2)
        #expect(workload.beyondThePlan == 2)
        #expect(workload.carriedNotableExtra)
    }

    @Test("The prompt tells the model what to do with extra work")
    func promptCarriesGuidance() {
        // The heading alone was the whole instruction for off-plan work, which
        // is why it had never changed a week.
        var snapshot = PlanContext(weekNumber: 4, pace: .building, recent: ["Tue · Lower · finished"],
                                   loggedSets: [])
        snapshot.workload = PlanContext.Workload(sessionsDone: 4, sessionsPlanned: 4, routineRuns: 3)
        #expect(snapshot.prompt.contains("3 extra workouts of her own"))
        #expect(snapshot.prompt.contains("room to progress"))

        // And the direction that protects her: extra work next to missed
        // sessions is not a licence to program more.
        snapshot.workload = PlanContext.Workload(sessionsDone: 1, sessionsPlanned: 4, routineRuns: 3)
        #expect(snapshot.prompt.contains("not as a reason to add work"))
    }

    @Test("A week carrying extra work is worth asking about")
    func extraWorkTriggersAsking() throws {
        // It has to be a trigger, not only a prompt line: a week the model is
        // not asked about is written by `OfflinePlanner`, which gets no context
        // at all, so the heaviest weeks would be the ones stepped on blindly.
        let context = store()
        let block = Block(startDate: Date.now.addingTimeInterval(-14 * 86_400),
                          goalWeightPounds: 150, startingWeightPounds: 165)
        context.insert(block)
        // A clean fortnight, so no other signal fires.
        for offset in [-3, -5] {
            let session = PlannedSession(scheduledFor: Date.now.addingTimeInterval(Double(offset) * 86_400),
                                         title: "Done", routine: nil)
            session.block = block
            session.completedAt = Date.now.addingTimeInterval(Double(offset) * 86_400)
            context.insert(session)
        }
        try context.save()
        UserDefaults.standard.set(Date.now, forKey: PlanTrigger.Memo.lastAsked)

        let quiet = PlanTrigger.decide(week: 3, of: block, in: context, hasKey: true)
        #expect(!quiet.asksClaude, "asked for reason: \(quiet.reason)")

        let routine = IntervalRoutine(name: "Mine", work: 30, rest: 30, rounds: 5, moves: [])
        RoutineRuns.record(routine, source: .saved, seconds: 200, in: context)
        RoutineRuns.record(routine, source: .extra, seconds: 200, in: context)

        let busy = PlanTrigger.decide(week: 3, of: block, in: context, hasKey: true)
        #expect(busy.asksClaude)
        #expect(busy.reason.contains("workouts of your own"))
        UserDefaults.standard.removeObject(forKey: PlanTrigger.Memo.lastAsked)
    }

    @Test("Two planned sessions finished on one day are two marks")
    func twoSessionsOneDayTwoMarks() throws {
        // Locks in the behaviour multiple-sessions-a-day depends on: marks bin
        // by `completedAt` with no per-day cap, so a second finished planned
        // session is a second mark. That is right — it is the plan.
        let context = store()
        let start = Calendar.current.startOfDay(for: .now)
        let block = Block(startDate: start, goalWeightPounds: 150, startingWeightPounds: 165)
        context.insert(block)
        for title in ["First", "Second"] {
            let session = PlannedSession(scheduledFor: start, title: title, routine: nil)
            session.block = block
            session.completedAt = .now
            context.insert(session)
        }
        try context.save()

        let done = try context.fetch(FetchDescriptor<PlannedSession>()).filter(\.isComplete)
        #expect(done.count == 2)
    }
}

@Suite("Every finished run is written down")
@MainActor
struct RunRecordingContractTests {

    @Test("Only the two non-plan kinds record a run, and each records its own kind")
    func recordedSources() {
        // The contract that was broken. Recording lived in `TodayView.finish`,
        // and a routine started from the Timer tab has its own `onEnd` closure
        // that never reaches it — so those runs left no trace at all. It lives
        // in `WorkoutTimerView.report` now, driven by the engine's ending, so
        // no presenter gets to decide whether a finished workout is recorded.
        #expect(ActiveSession.Subject.routine.recordedSource == .saved)
        #expect(ActiveSession.Subject.extra.recordedSource == .extra)
        // A planned session earns a mark instead, and only the presenter has
        // the row to mark. The practice keeps its own record.
        #expect(ActiveSession.Subject.session(UUID()).recordedSource == nil)
        #expect(ActiveSession.Subject.practice.recordedSource == nil)
        #expect(ActiveSession.Subject.unknown.recordedSource == nil)
    }

    @Test("A run started from the Timer tab carries the subject that records it")
    func timerTabSubjectRecords() {
        // `RoutineListView` presents with `subject: .routine`; the guard is that
        // this subject is one that writes a record.
        #expect(ActiveSession.Subject.routine.recordedSource != nil)
    }

    @Test("A resumed run keeps its recording kind across the store")
    func resumedRunStillRecords() throws {
        var session = ActiveSession(routine: Practice.routine(on: .now), startedAt: .now,
                                    elapsed: 60, running: true, savedAt: .now)
        session.setSubject(ActiveSession.Subject.routine)
        let back = try JSONDecoder().decode(
            ActiveSession.self, from: try JSONEncoder().encode(session))
        #expect(back.subject.recordedSource == .saved)
    }
}

@Suite("The pad is not in the library")
struct WalkingIsNotASetTests {

    @Test("No walk is selectable anywhere")
    func padMovesAreGone() {
        // Her words: "40 seconds of an incline walk or zone 2 walk isn't going
        // to do anything and will take longer to set up the treadmill" — and
        // then, decisively: the walks already come from Whoop through Health,
        // so naming them as moves was duplicating a number she already has.
        #expect(!MoveLibrary.all.contains { $0.equipment == .walkingPad })
        #expect(MoveLibrary.moves(for: .walkingPad).isEmpty)
        #expect(!MoveLibrary.names.contains { $0.lowercased().contains("walk") })
        #expect(!MoveLibrary.rotation(of: 40).contains { $0.equipment == .walkingPad })
    }

    @Test("A generated week naming a walk is rejected whole")
    func validatorRejectsAWalk() {
        // The library is closed, so a walk is now simply an unknown move —
        // refused rather than trimmed, like anything else outside the kit.
        let draft = DraftMove(name: "Zone 2 walk", equipment: Equipment.walkingPad.rawValue,
                              cue: "A pace you could hold a conversation at.", loadPounds: 0)
        #expect(throws: PlanValidator.Failure.self) { try PlanValidator.move(from: draft) }
    }

    @Test("Walking is still tracked, just not as an interval")
    func walkingStillCounts() {
        // The pad stays in `Equipment` so anything already stored against it
        // still decodes, and the weekly target is untouched — that number comes
        // from Health, which is where Whoop writes her walks.
        #expect(Equipment.allCases.contains(.walkingPad))
        #expect(PlanValidator.walkCeiling > 0)
    }
}

// MARK: - What a day shows as finished

@Suite("The session a day shows as finished")
@MainActor
struct FinishedSessionTests {

    private func session(day: Int, title: String, finished: Date?) -> PlannedSession {
        let when = Calendar.current.date(byAdding: .day, value: day, to: .now)!
        let session = PlannedSession(scheduledFor: when, title: title, routine: nil)
        session.completedAt = finished
        return session
    }

    @Test("A session pulled forward on a rest day is what today shows")
    func pulledForward() {
        // Her case: today is a rest day, so she did tomorrow's session.
        let tomorrow = session(day: 1, title: "Lower · beam", finished: .now)
        #expect(FinishedSessions.today([tomorrow])?.title == "Lower · beam")
    }

    @Test("A session finished on another day is not today's")
    func yesterdaysStaysYesterdays() {
        let yesterday = session(day: -1, title: "Upper · rings",
                                finished: Calendar.current.date(byAdding: .day, value: -1, to: .now))
        #expect(FinishedSessions.today([yesterday]) == nil)
    }

    @Test("Today's own session wins over one pulled forward")
    func todaysWins() {
        let mine = session(day: 0, title: "Full · mixed", finished: .now)
        let early = session(day: 2, title: "Lower · beam",
                            finished: Date.now.addingTimeInterval(-600))
        #expect(FinishedSessions.today([early, mine])?.title == "Full · mixed")
    }

    @Test("A session still to do is not finished")
    func unfinished() {
        #expect(FinishedSessions.today([session(day: 0, title: "Full", finished: nil)]) == nil)
    }
}

// MARK: - When a load has been outgrown

@Suite("The step up a load")
struct LoadProgressionTests {

    private func halo() -> Move {
        MoveLibrary.all.first { $0.name == "Ring halo" }!
    }

    /// A counted rep-mode session: reps, with the seconds each set ran.
    private func log(_ reps: [Int], seconds: Double = 45, pounds: Double = 5,
                     daysAgo: Int = 1, mode: SessionMode = .reps) -> SetLog {
        let log = SetLog(sourceID: UUID(), move: halo(), reps: reps,
                         date: Calendar.current.date(byAdding: .day, value: -daysAgo, to: .now)!)
        log.loadPounds = pounds
        log.setSeconds = reps.map { _ in seconds }
        log.modeRaw = mode == .intervals ? nil : mode.rawValue
        return log
    }

    @Test("Two set sessions at the top of the range is ready")
    func readyByReps() {
        let history = [log([12, 13, 12], daysAgo: 4), log([12, 12, 14], daysAgo: 1)]
        #expect(LoadProgression.ready(move: halo(), history: history))
        #expect(LoadProgression.nextLoad(for: halo()) == 8)
    }

    @Test("Pace is not a measure of anything any more")
    func paceDoesNotCount() {
        // Eighteen a minute with a light weight used to promote the load;
        // eleven reps is under the range's top however fast they went.
        let history = [log([11, 11], seconds: 30, daysAgo: 4), log([11, 11], seconds: 30, daysAgo: 1)]
        #expect(!LoadProgression.ready(move: halo(), history: history))
    }

    @Test("An interval session never qualifies")
    func intervalsDoNotCount() {
        // Sixteen reps in a forty-second interval is conditioning, not a set
        // two short of failure.
        let history = [log([16, 16], daysAgo: 4, mode: .intervals),
                       log([16, 16], daysAgo: 1, mode: .intervals)]
        #expect(!LoadProgression.ready(move: halo(), history: history))
        // And a rep session between two interval ones is still only one.
        let mixed = [log([12, 12], daysAgo: 4, mode: .intervals), log([12, 12], daysAgo: 2),
                     log([12, 12], daysAgo: 1, mode: .intervals)]
        #expect(!LoadProgression.ready(move: halo(), history: mixed))
    }

    @Test("One strong session is a good day, not a verdict")
    func oneSessionIsNotEnough() {
        #expect(!LoadProgression.ready(move: halo(), history: [log([14, 13])]))
    }

    @Test("A short set in the latest sessions holds the weight")
    func fadingSetHolds() {
        let history = [log([12, 12], daysAgo: 4), log([14, 9], daysAgo: 1)]
        #expect(!LoadProgression.ready(move: halo(), history: history))
    }

    @Test("Counts at the old load say nothing about the new one")
    func oldLoadDoesNotCarry() {
        let moved = halo().applyingLoad(from: ["ring halo": 8])
        let history = [log([14, 14], daysAgo: 6), log([13, 12], daysAgo: 3)]
        #expect(!LoadProgression.ready(move: moved, history: history))
    }

    @Test("A row counted loosely cannot qualify")
    func noSecondsNoVerdict() {
        let loose = log([14, 14], daysAgo: 4)
        loose.setSeconds = nil
        #expect(!LoadProgression.ready(move: halo(), history: [loose, log([14, 13])]))
    }

    @Test("The heaviest load on the equipment has nowhere to go")
    func topOfTheKit() {
        var bell = MoveLibrary.all.first { $0.name == "Kettlebell deadlift" }!
        #expect(LoadProgression.nextLoad(for: bell) == 35)
        bell.loadPounds = Equipment.kettlebell.availableLoadsPounds.max()
        #expect(LoadProgression.nextLoad(for: bell) == nil)
    }

    @Test("The dumbbells now step 2, 3, 5")
    func dumbbellSteps() {
        let press = MoveLibrary.all.first { $0.name == "Dumbbell press" }!
        #expect(LoadProgression.nextLoad(for: press) == 3)
        #expect(LoadProgression.nextLoad(for: press.applyingLoad(from: ["dumbbell press": 3])) == 5)
        #expect(LoadProgression.nextLoad(for: press.applyingLoad(from: ["dumbbell press": 5])) == nil)
    }

    @Test("A large jump is bridged; a small one is taken directly")
    func bridges() {
        let bell = MoveLibrary.all.first { $0.name == "Kettlebell deadlift" }!
        let big = LoadProgression.Suggestion(move: bell, currentPounds: 18, nextPounds: 35)
        #expect(big.isBigJump)
        #expect(big.bridge?.contains("94 percent") == true)
        #expect(big.line == "Kettlebell deadlift has outgrown the 18 lb kettlebell — the 35 lb kettlebell is ready when you are.")
        let small = LoadProgression.Suggestion(move: bell, currentPounds: 15, nextPounds: 18)
        #expect(!small.isBigJump)
        #expect(small.bridge == nil)
        let pair = LoadProgression.Suggestion(move: MoveLibrary.all.first { $0.name == "Dumbbell press" }!,
                                              currentPounds: 2, nextPounds: 3)
        #expect(pair.line.contains("outgrown the two 2 lb dumbbells — the two 3 lb dumbbells"))
    }
}


// MARK: - The sampler

@Suite("The sampler")
struct MoveSamplerTests {

    @Test("Tried is derived from everything she finished")
    func derivedTried() {
        let routine = IntervalRoutine(name: "S", work: 40, rest: 20, rounds: 2,
                                      moves: [MoveLibrary.all[0]])
        let keys = MoveSampler.triedKeys(routines: [routine],
                                         runMoveNames: [["Ring row"]],
                                         logMoveNames: ["Bicep curl"])
        #expect(keys.contains(MovePreference.key(MoveLibrary.all[0].name)))
        #expect(keys.contains("ring row"))
        #expect(keys.contains("bicep curl"))
    }

    @Test("A flight is six untried strength moves at ten on, ten off, no mark's worth of anything")
    func flight() {
        let routine = MoveSampler.build(from: MoveLibrary.all, tried: [])
        #expect(routine.moves.count == MoveSampler.count)
        #expect(routine.work == 10)
        #expect(routine.rest == 10)
        #expect(routine.rounds == routine.moves.count)
        #expect(routine.moves.allSatisfy { $0.kind == .strength })
        #expect(routine.warmUp.isEmpty)
    }

    @Test("Tried moves fall out, refusals never appear, and a spent library re-tastes")
    func progression() {
        let first = MoveSampler.build(from: MoveLibrary.all, tried: [])
        let tried = Set(first.moves.map { MovePreference.key($0.name) })
        let second = MoveSampler.build(from: MoveLibrary.all, tried: tried)
        #expect(Set(second.moves.map { MovePreference.key($0.name) })
            .isDisjoint(with: tried))

        // Every strength move tried: the flight fills rather than shrinking.
        // Counted off the library actually passed in, not off
        // `MoveLibrary.names` — that reads what she *owns*, so mixing the two
        // made this assertion depend on whether the simulator's app had the
        // band switched off. The sampler takes its pool as a parameter
        // precisely so it can be tested without that.
        let strength = MoveLibrary.all.filter { $0.kind == .strength }
        let everything = Set(strength.map { MovePreference.key($0.name) })
        #expect(MoveSampler.build(from: MoveLibrary.all, tried: everything)
            .moves.count == MoveSampler.count)

        let refused = MoveSampler.build(from: MoveLibrary.all, tried: [],
                                        avoiding: ["push-up"])
        #expect(!refused.moves.contains { MovePreference.anyCovers(["push-up"], $0.name) })

        let progress = MoveSampler.progress(library: MoveLibrary.all, tried: tried)
        #expect(progress.tried == MoveSampler.count)
        #expect(progress.total == strength.count)
    }
}

// MARK: - What she actually owns

/// The ownership layer, tested through invariants that hold whatever is
/// stored. `Tuning.ownedEquipment` is process-wide `UserDefaults` and these
/// suites run in parallel, so a test that switched a drawer off would change
/// what every other suite's rotation could reach. The mutating path is
/// exercised by hand in the simulator instead.
@Suite("Owned equipment")
struct OwnedEquipmentTests {

    @Test("Her own body and the pad cannot be switched off")
    func alwaysOwned() {
        #expect(Equipment.alwaysOwned.contains(.bodyweight))
        #expect(Equipment.alwaysOwned.contains(.walkingPad))
        #expect(Equipment.bodyweight.isOwned)
        // The list Settings offers never includes them.
        #expect(!Equipment.switchable.contains(.bodyweight))
        #expect(!Equipment.switchable.contains(.walkingPad))
        #expect(Equipment.switchable.allSatisfy { !Equipment.alwaysOwned.contains($0) })
    }

    @Test("Nothing may be offered or generated on kit she does not have")
    func offersStayInsideTheKit() {
        #expect(MoveLibrary.available.allSatisfy { $0.equipment.isOwned })
        // The planner's schema enum is built from what she owns.
        let names = Set(MoveLibrary.names)
        #expect(names.allSatisfy { name in
            MoveLibrary.all.first { $0.name == name }?.equipment.isOwned == true
        })
        // And so is every rotation, which is the one builder they all use.
        #expect(MoveLibrary.rotation(of: 6).allSatisfy { $0.equipment.isOwned })
        #expect(MoveLibrary.rotation(of: 40).allSatisfy { $0.equipment.isOwned })
    }

    @Test("A move is still read back after its kit goes away")
    func stillReadsBack() {
        // `all` stays the truth for reading: a week written when she had the
        // band must still draw and still run. Only offering is filtered.
        #expect(MoveLibrary.all.count >= MoveLibrary.available.count)
        for move in MoveLibrary.all where !move.equipment.isOwned {
            #expect(MoveLibrary.all.contains { $0.name == move.name })
        }
    }

    @Test("A generated week may not name kit she does not have")
    func validatorGuardsTheKit() throws {
        for equipment in Equipment.switchable where !equipment.isOwned {
            guard let move = MoveLibrary.moves(for: equipment).first else { continue }
            #expect(throws: PlanValidator.Failure.self) {
                _ = try PlanValidator.move(from: DraftMove(name: move.name))
            }
        }
    }
}
