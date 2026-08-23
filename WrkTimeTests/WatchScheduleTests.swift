import Testing
import Foundation
@testable import WrkTime

/// The watch and the phone are one session read on two devices, and the one
/// thing they must never do is disagree about it. `TimerFace` is where the
/// three questions a timer screen asks — where are we, what is the number,
/// what does the big control do — are answered once; these tests pin its
/// answers to the formats `WorkoutTimerView` has always shown, for every
/// `SessionMode` and for the shapes that are not a plain round: a sided move,
/// a flow warm-up, and the rest that names what comes next.
///
/// The expectations are spelled out as literal strings rather than computed
/// from the same expression the code uses. A test that re-derives the format
/// it is checking agrees with any bug in it.
///
/// Nothing here touches the planner. There is no `PlannerService` call and no
/// `ClaudePlanner`, so no run of this suite can cost anything.
@Suite("The watch's timer face")
@MainActor
struct WatchScheduleTests {

    // MARK: - Fixtures

    private func move(_ name: String) -> Move {
        MoveLibrary.all.first { $0.name == name } ?? MoveLibrary.all[0]
    }

    /// Two plain moves — neither sided, so a turn is one work interval.
    private var pair: [Move] { [move("Beam front squat"), move("Ring row")] }

    private func intervals(rounds: Int = 3) -> IntervalRoutine {
        IntervalRoutine(name: "Watch test", work: 60, rest: 45,
                        rounds: rounds, moves: pair)
    }

    /// The face at a given elapsed offset, driven the way `IntervalEngineTests`
    /// drives the engine: an injected clock and no ticker, so the assertions
    /// are exact and nothing waits on real time.
    private func face(_ routine: IntervalRoutine, at seconds: TimeInterval) -> TimerFace {
        let clock = TestClock()
        let engine = IntervalEngine(routine: routine, now: clock.provider, autoTick: false)
        engine.start()
        clock.advance(seconds)
        engine.refresh()
        return TimerFace(engine: engine)
    }

    /// The face a little way into a named phase, so a test does not have to
    /// restate the arithmetic of the schedule it is reading.
    private func face(_ routine: IntervalRoutine, inPhase index: Int,
                      offset: TimeInterval = 1) -> TimerFace {
        face(routine, at: routine.schedule.phases[index].start + offset)
    }

    // MARK: - Intervals

    @Test("Intervals count down, in rounds, with skip as the control")
    func intervalsMode() {
        let routine = intervals()
        #expect(routine.mode == .intervals)
        #expect(routine.roundCount == 3)

        let working = face(routine, at: 10)
        #expect(working.positionLine == "Round 1 / 3")
        #expect(working.countString == "0:50")
        #expect(working.control == .skip)
        #expect(working.isOpenSet == false)
        #expect(working.phaseWord == "Work")

        // The rest belongs to the round it followed, exactly as the phone's
        // header says: nothing advances until the next work interval does.
        let resting = face(routine, at: 70)
        #expect(resting.positionLine == "Round 1 / 3")
        #expect(resting.countString == "0:35")
        #expect(resting.control == .skip)
        #expect(resting.phaseWord == "Rest")

        let second = face(routine, at: 130)
        #expect(second.positionLine == "Round 2 / 3")
        #expect(second.countString == "0:35")
    }

    @Test("A count rounds up, so a phase reads 0:01 for its whole last second")
    func roundsUp() {
        #expect(face(intervals(), at: 59.4).countString == "0:01")
        #expect(face(intervals(), at: 59.99).countString == "0:01")
    }

    // MARK: - Sets

    @Test("A set counts up, in sets, with Done as the control")
    func repsMode() {
        let routine = intervals().inMode(.reps, sets: 3)
        #expect(routine.mode == .reps)
        // Two moves, three sets each, neither sided.
        #expect(routine.roundCount == 6)

        let working = face(routine, at: 20)
        // The number is how long she has been lifting, not how long until
        // something happens to her.
        #expect(working.countString == "0:20")
        #expect(working.positionLine == "Set 1 / 6")
        #expect(working.control == .done)
        #expect(working.isOpenSet)

        // The rest between two sets is a plain countdown again, and the
        // control goes back to skip.
        let resting = face(routine, inPhase: 1)
        #expect(resting.control == .skip)
        #expect(resting.isOpenSet == false)
        #expect(resting.positionLine == "Set 1 / 6")
        let rest = routine.schedule.phases[1]
        #expect(resting.countString == (rest.duration - 1).clockString)

        let third = face(routine, inPhase: 4)
        #expect(third.positionLine == "Set 3 / 6")
        #expect(third.countString == "0:01")
    }

    @Test("The rest before a new move names the move it is for")
    func nextUpOnRest() {
        let routine = intervals().inMode(.reps, sets: 3)
        // Phase 5 is the rest that closes the first move's three sets: it is
        // the one that carries the next move, which is what "Next up" reads.
        let phase = routine.schedule.phases[5]
        #expect(phase.isRest)
        #expect(phase.move?.name == "Ring row")

        let resting = face(routine, inPhase: 5)
        #expect(resting.phaseWord == "Rest")
        #expect(resting.control == .skip)
        // Still the third set's rest: the number does not advance until the
        // next set starts.
        #expect(resting.positionLine == "Set 3 / 6")

        // And on the minute, where the rest also names what follows it.
        let emom = intervals(rounds: 4).inMode(.emom)
        #expect(emom.schedule.phases[1].move?.name == "Ring row")
        #expect(face(emom, inPhase: 1).positionLine == "Minute 1 / 4")
    }

    // MARK: - On the minute

    @Test("On the minute counts down in minutes, and never opens a set")
    func emomMode() {
        let routine = intervals(rounds: 4).inMode(.emom)
        #expect(routine.mode == .emom)
        #expect(routine.roundCount == 4)

        let working = face(routine, at: 5)
        #expect(working.positionLine == "Minute 1 / 4")
        // Twenty-five seconds to work in, five gone.
        #expect(working.countString == "0:20")
        // The clock is the whole idea of the mode: no phase is open-ended, so
        // the prominent control is never Done.
        #expect(working.control == .skip)

        let resting = face(routine, at: 30)
        #expect(resting.positionLine == "Minute 1 / 4")
        #expect(resting.countString == "0:30")
        #expect(resting.control == .skip)

        let second = face(routine, at: 65)
        #expect(second.positionLine == "Minute 2 / 4")
    }

    // MARK: - A sided move

    @Test("A sided move is two work intervals, and both are counted")
    func sidedMove() {
        let curl = move("Ring bicep curl")
        #expect(curl.sided == .sides)
        let routine = IntervalRoutine(name: "Sided", work: 40, rest: 20,
                                      rounds: 2, moves: [curl])
        // Two turns, one interval per side: four work intervals, and every
        // surface counts against that.
        #expect(routine.roundCount == 4)

        let first = face(routine, at: 5)
        #expect(first.positionLine == "Round 1 / 4")
        #expect(first.phase?.side == "Left side")
        #expect(first.countString == "0:35")

        // The second side is added to the session, never carved out of the
        // first: it is a full interval of its own.
        let second = face(routine, inPhase: 2, offset: 5)
        #expect(second.positionLine == "Round 2 / 4")
        #expect(second.phase?.side == "Right side")
        #expect(second.countString == "0:35")
    }

    // MARK: - Flow

    @Test("A flow movement is not a round, and is named for what it is")
    func flowWarmUp() {
        let flow = MoveLibrary.all.filter { $0.kind == .flow }.prefix(3)
        let routine = intervals().warmingUp(with: Array(flow))
        #expect(routine.roundCount == 3)

        let first = face(routine, at: 5)
        #expect(first.positionLine == "Warm-up 1 / 3")
        #expect(first.phaseWord == "Warm-up")
        // The practice is timed so the session moves along, not so she races
        // it — but it is still a countdown, not an open set.
        #expect(first.control == .skip)
        #expect(first.countString == (routine.warmUpSeconds - 5).clockString)

        let second = face(routine, at: routine.warmUpSeconds + 5)
        #expect(second.positionLine == "Warm-up 2 / 3")

        // Round one is still round one: the warm-up added no rounds and took
        // none away.
        let working = face(routine, at: routine.schedule.workBegins + 10)
        #expect(working.positionLine == "Round 1 / 3")
        #expect(working.phaseWord == "Work")
    }

    @Test("A routine with no rounds is the practice, not a warm-up for anything")
    func practiceNames() {
        let flow = MoveLibrary.all.filter { $0.kind == .flow }.prefix(4)
        let practice = IntervalRoutine(name: "Morning practice", work: 0, rest: 0,
                                       rounds: 0, moves: [])
            .warmingUp(with: Array(flow), seconds: 60)
        #expect(practice.roundCount == 0)

        let first = face(practice, at: 5)
        // "Warm-up" would name it after work that is not coming.
        #expect(first.positionLine == "Movement 1 / 4")
        #expect(first.phaseWord == "Movement")
        #expect(first.countString == "0:55")
        #expect(first.control == .skip)
    }

    // MARK: - The end

    @Test("Past the end the face reads the last round at zero")
    func finished() {
        let routine = intervals()
        let over = face(routine, at: routine.schedule.total + 5)
        #expect(over.phase == nil)
        #expect(over.positionLine == "Round 3 / 3")
        #expect(over.countString == "0:00")
        #expect(over.control == .skip)
    }

    @Test("The face of a mirrored session reads like a local one")
    func builtWithoutAnEngine() {
        // The watch will one day be handed a phase and an elapsed over the
        // wire rather than reading its own engine. The face takes the pieces,
        // so that session reads identically.
        let routine = intervals().inMode(.reps, sets: 3)
        let phase = routine.schedule.phases[2]
        let mirrored = TimerFace(routine: routine, phase: phase,
                                 elapsed: phase.start + 42)
        #expect(mirrored.positionLine == "Set 2 / 6")
        #expect(mirrored.countString == "0:42")
        #expect(mirrored.control == .done)
    }
}
