import Testing
import Foundation
@testable import WrkTime

/// The three session modes, `docs/COACH-BRIEF.md` §5 and §7–8.
@Suite("Session modes")
@MainActor
struct SessionModeTests {

    private func named(_ name: String) -> Move { MoveLibrary.all.first { $0.name == name }! }

    /// Kettlebell deadlift (hinge, big lift, 90 s), kettlebell row (pull,
    /// 75 s, **sided** — so each set is two work phases), dead bug (floor
    /// core, 45 s). One implement, one position change.
    private var reps: IntervalRoutine {
        IntervalRoutine(name: "Sets", work: 40, rest: 20, rounds: 0,
                        moves: [named("Kettlebell deadlift"), named("Kettlebell row"), named("Dead bug")])
            .inMode(.reps, sets: 3)
    }

    @Test("A stored routine without a mode is intervals")
    func decodesAsIntervals() throws {
        let json = """
        {"id":"\(UUID().uuidString)","name":"Old","work":40,"rest":20,"rounds":8,"moves":[],"dropsFinalRest":true}
        """ as String
        let routine = try JSONDecoder().decode(IntervalRoutine.self, from: Data(json.utf8))
        #expect(routine.mode == .intervals)
        #expect(routine.setsPerMove == IntervalRoutine.defaultSets)
    }

    @Test("Reps mode: every set of a move, then the next move")
    func straightSets() {
        let work = reps.schedule.phases.filter(\.isWork)
        // 3 + (3 × 2 sides) + 3
        #expect(work.count == 12)
        #expect(reps.roundCount == 12)
        #expect(work.prefix(3).allSatisfy { $0.move?.name == "Kettlebell deadlift" })
        #expect(work[3...8].allSatisfy { $0.move?.name == "Kettlebell row" })
        #expect(work[3].side != nil && work[3].side != work[4].side)
        #expect(work.allSatisfy { $0.openEnded })
        #expect(work[0].setLabel == "Set 1 of 3")
        #expect(work[2].setLabel == "Set 3 of 3")
        #expect(work.allSatisfy { $0.duration == IntervalRoutine.repSetCeiling })
    }

    @Test("Rest between sets is the pattern's; between moves it is flat plus setup")
    func restTable() {
        let phases = reps.schedule.phases
        let rests = phases.filter(\.isRest)
        // deadlift: 2 set rests at 90; then to the row: big lift keeps 90, no
        // implement change, no position change → 90.
        #expect(rests[0].duration == 90)
        #expect(rests[1].duration == 90)
        #expect(rests[2].duration == 90)
        #expect(rests[2].move?.name == "Kettlebell row", "the between-moves rest says what is next")
        // row: 2 set rests at 75; then to the dead bug: flat 30 + position
        // change 20 (bodyweight is not a fetch) = 50.
        #expect(rests[3].duration == 75)
        #expect(rests[4].duration == 75)
        #expect(rests[5].duration == 50)
        #expect(rests[5].move?.name == "Dead bug")
        // dead bug: 2 set rests at 45, and no rest after the last set.
        #expect(rests[6].duration == 45)
        #expect(rests[7].duration == 45)
        #expect(rests.count == 8)
        #expect(phases.last?.isWork == true)
    }

    @Test("Ending a set starts the rest and keeps the real length")
    func endSet() {
        let clock = TestClock()
        let engine = IntervalEngine(routine: reps, now: clock.provider, autoTick: false)
        engine.start()
        clock.advance(42)
        engine.refresh()
        #expect(engine.currentPhase?.isWork == true)
        engine.endSet()
        #expect(engine.currentPhase?.isRest == true)
        #expect(engine.setDurations[0] == 42)
        #expect(engine.skippedMoves.isEmpty, "a set she ended is not a set she skipped")
        #expect(engine.remainingInPhase == 90)
    }

    @Test("The net: a forgotten tap ends the set at the ceiling")
    func ceiling() {
        let clock = TestClock()
        let engine = IntervalEngine(routine: reps, now: clock.provider, autoTick: false)
        engine.start()
        clock.advance(IntervalRoutine.repSetCeiling + 1)
        engine.refresh()
        #expect(engine.currentPhase?.isRest == true)
        #expect(engine.setDurations.isEmpty, "no tap, no measured length")
    }

    @Test("A sided move in reps mode works both sides in every set")
    func sidedSets() {
        let routine = IntervalRoutine(name: "Sets", work: 40, rest: 20, rounds: 0,
                                      moves: [named("Ring halo")]).inMode(.reps, sets: 2)
        let work = routine.schedule.phases.filter(\.isWork)
        #expect(work.count == 4)
        #expect(routine.roundCount == 4)
        #expect(work[0].side != nil && work[1].side != nil && work[0].side != work[1].side)
        // No rest between the two sides of one set; rest after the pair.
        #expect(routine.schedule.phases[1].isWork)
        #expect(routine.schedule.phases[2].isRest)
    }

    @Test("EMOM: one set at the top of each minute, the clock never shifts")
    func emom() {
        let routine = IntervalRoutine(name: "EMOM", work: 40, rest: 20, rounds: 6,
                                      moves: [named("Kettlebell deadlift"), named("Kettlebell goblet squat")])
            .inMode(.emom)
        let phases = routine.schedule.phases
        #expect(phases.filter(\.isWork).count == 6)
        #expect(routine.roundCount == 6)
        for (minute, phase) in phases.filter(\.isWork).enumerated() {
            #expect(phase.start == Double(minute) * 60, "minute \(minute) starts at \(phase.start)")
            #expect(phase.duration == IntervalRoutine.emomWorkSeconds)
            #expect(!phase.openEnded)
        }
        #expect(phases.filter(\.isRest).allSatisfy { $0.duration == 35 })
        // Six minutes less the final rest.
        #expect(routine.schedule.total == 5 * 60 + 25)
        #expect(phases.filter(\.isWork).map { $0.move?.name } ==
                ["Kettlebell deadlift", "Kettlebell goblet squat", "Kettlebell deadlift",
                 "Kettlebell goblet squat", "Kettlebell deadlift", "Kettlebell goblet squat"])
    }

    @Test("The warm-up's setup pause still precedes a rep session")
    func warmUpThenSets() {
        let routine = reps.warmingUp(with: [named("Arm circles")])
        let phases = routine.schedule.phases
        #expect(phases[0].isFlow)
        #expect(phases[1].isRest && phases[1].duration == WarmUp.setupSeconds)
        #expect(phases[2].isWork && phases[2].openEnded)
    }

    @Test("The Whoop copy reports sets, and real lengths when she ended them")
    func whoop() {
        let routine = reps
        let uncounted = WhoopSummary.entries(for: routine)
        #expect(uncounted.first?.measure == "3 sets, reps not counted")
        let counted = WhoopSummary.counted(for: routine, reps: [10, 10, 9] + Array(repeating: 0, count: 9),
                                           durations: [0: 40, 1: 44, 2: 47])
        #expect(counted.first?.seconds == [40, 44, 47])
        #expect(counted.first?.reps == [10, 10, 9])
    }
}
