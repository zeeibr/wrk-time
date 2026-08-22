import Testing
import Foundation
@testable import WrkTime

/// A clock the tests move by hand, so none of this waits on real time.
final class TestClock {
    var now: Date
    init(_ start: Date = Date(timeIntervalSince1970: 1_700_000_000)) { now = start }
    func advance(_ seconds: TimeInterval) { now += seconds }
    var provider: () -> Date { { [unowned self] in self.now } }
}

/// Two named moves rather than two indices.
///
/// This used to reach for `MoveLibrary.all[0]` and `[4]`, so adding a move to
/// the middle of the library silently changed what the rotation test was
/// asserting about.
private func named(_ name: String) -> Move {
    MoveLibrary.all.first { $0.name == name } ?? MoveLibrary.all[0]
}

// "Ring row" rather than "Ring halo" deliberately: the halo is a sided move
// and expands to two intervals a turn, which is its own suite's business —
// these tests want two plain moves.
private func routine(rounds: Int = 3, work: TimeInterval = 60, rest: TimeInterval = 45,
                     dropsFinalRest: Bool = true) -> IntervalRoutine {
    IntervalRoutine(name: "Test", work: work, rest: rest, rounds: rounds,
                    moves: [named("Beam front squat"), named("Ring row")],
                    dropsFinalRest: dropsFinalRest)
}

// MARK: - Schedule

@Suite("Routine schedule")
struct RoutineScheduleTests {

    @Test("Work and rest alternate, and the final rest is dropped")
    func phaseOrder() {
        let schedule = routine(rounds: 3).schedule
        #expect(schedule.phases.map(\.kind) == [.work, .rest, .work, .rest, .work])
        #expect(schedule.workPhaseCount == 3)
    }

    @Test("Total is the honest sum, with no trailing rest")
    func total() {
        #expect(routine(rounds: 3).totalDuration == 60 * 3 + 45 * 2)
        #expect(routine(rounds: 3, dropsFinalRest: false).totalDuration == 60 * 3 + 45 * 3)
    }

    @Test("Work is clamped to the sixty second ceiling")
    func ceiling() {
        let over = routine(rounds: 1, work: 90)
        #expect(over.clampedWork == 60)
        #expect(over.totalDuration == 60)
    }

    @Test("Moves cycle through the rounds in order")
    func moveRotation() {
        let schedule = routine(rounds: 3).schedule
        let workMoves = schedule.phases.filter(\.isWork).map(\.move?.name)
        #expect(workMoves == ["Beam front squat", "Ring row", "Beam front squat"])
    }

    @Test("A sided move takes a full work interval per side, added not carved")
    func sidedExpansion() {
        // The halo is `.directions`; the front squat is plain. Two turns.
        let sided = IntervalRoutine(name: "Sided", work: 40, rest: 20, rounds: 2,
                                    moves: [named("Beam front squat"), named("Ring halo")])
        let work = sided.schedule.phases.filter(\.isWork)

        // Three work intervals from two turns: the halo got one per direction.
        #expect(work.map(\.move?.name) == ["Beam front squat", "Ring halo", "Ring halo"])
        #expect(work.map(\.side) == [nil, "One way", "Other way"])
        // Each side is the full forty seconds — nothing halved.
        #expect(work.allSatisfy { $0.duration == 40 })
        // Every surface counts against `roundCount`, so it must agree.
        #expect(sided.roundCount == 3)
        #expect(sided.schedule.workPhaseCount == 3)
        #expect(work.map(\.round) == [1, 2, 3])
    }

    @Test("A sided move in a sequence claims two written work steps, one per side")
    func sidedSequence() {
        let base = IntervalRoutine(name: "Seq", work: 0, rest: 0, rounds: 0,
                                   moves: [named("Split squat"), named("Ring row")])
        let sequence = base.following([.work(30), .work(30), .work(30)])
        let work = sequence.schedule.phases.filter(\.isWork)

        // Her three steps stay three steps; the split squat takes the first
        // two — left then right — and the row takes the third.
        #expect(work.map(\.move?.name) == ["Split squat", "Split squat", "Ring row"])
        #expect(work.map(\.side) == ["Left side", "Right side", nil])
        #expect(sequence.roundCount == 3)
    }

    @Test("Phase boundaries are half-open, so no elapsed value lands in two phases")
    func boundaries() {
        let schedule = routine(rounds: 2).schedule
        #expect(schedule.index(atElapsed: 0) == 0)
        #expect(schedule.index(atElapsed: 59.999) == 0)
        #expect(schedule.index(atElapsed: 60) == 1)      // first rest
        #expect(schedule.index(atElapsed: 104.999) == 1)
        #expect(schedule.index(atElapsed: 105) == 2)     // second work
    }

    @Test("Elapsed past the end belongs to no phase")
    func pastEnd() {
        let schedule = routine(rounds: 1).schedule
        #expect(schedule.index(atElapsed: 60) == nil)
        #expect(schedule.index(atElapsed: 999) == nil)
        #expect(schedule.index(atElapsed: -1) == nil)
    }

    @Test("A single round with no rest is still a valid routine")
    func degenerate() {
        let single = IntervalRoutine(name: "One", work: 30, rest: 0, rounds: 1, moves: [])
        #expect(single.schedule.phases.count == 1)
        #expect(single.totalDuration == 30)
        #expect(single.schedule.phases[0].move == nil)
    }
}

// MARK: - Engine

/// Main-actor isolated to match the engine, which drives the timer view.
@Suite("Interval engine")
@MainActor
struct IntervalEngineTests {

    @Test("Counts down from the clock, not by accumulating ticks")
    func countdown() {
        let clock = TestClock()
        let engine = IntervalEngine(routine: routine(), now: clock.provider, autoTick: false)
        engine.start()

        #expect(engine.remainingInPhase == 60)
        clock.advance(20); engine.refresh()
        #expect(engine.remainingInPhase == 40)
        #expect(engine.currentPhase?.isWork == true)
    }

    @Test("A gap in ticking cannot make the count wrong")
    func noDriftAcrossAGap() {
        let clock = TestClock()
        let engine = IntervalEngine(routine: routine(), now: clock.provider, autoTick: false)
        engine.start()

        // Simulate the app being backgrounded for two whole phases.
        clock.advance(130)
        engine.refresh()

        // 130s in: 60 work + 45 rest = 105, so we are 25s into round two's work.
        #expect(engine.currentPhase?.round == 2)
        #expect(engine.currentPhase?.isWork == true)
        #expect(engine.remainingInPhase == 35)
    }

    @Test("Pausing freezes the count and resuming does not lose the pause")
    func pauseResume() {
        let clock = TestClock()
        let engine = IntervalEngine(routine: routine(), now: clock.provider, autoTick: false)
        engine.start()

        clock.advance(10); engine.refresh()
        engine.pause()
        #expect(engine.status == .paused)

        clock.advance(300)              // a long interruption
        engine.refresh()
        #expect(engine.remainingInPhase == 50, "paused time must not count")

        engine.resume()
        clock.advance(10); engine.refresh()
        #expect(engine.remainingInPhase == 40)
        #expect(engine.status == .running)
    }

    @Test("Skip jumps to the start of the next phase and keeps the clock honest")
    func skip() {
        let clock = TestClock()
        let engine = IntervalEngine(routine: routine(), now: clock.provider, autoTick: false)
        engine.start()

        clock.advance(5); engine.refresh()
        engine.skip()

        #expect(engine.currentPhase?.kind == .rest)
        #expect(engine.remainingInPhase == 45)

        clock.advance(10); engine.refresh()
        #expect(engine.remainingInPhase == 35, "time keeps running normally after a skip")
    }

    @Test("The field drains from full to empty across a work phase")
    func drainFraction() {
        let clock = TestClock()
        let engine = IntervalEngine(routine: routine(), now: clock.provider, autoTick: false)
        engine.start()

        #expect(engine.phaseRemainingFraction == 1)
        clock.advance(30); engine.refresh()
        #expect(abs(engine.phaseRemainingFraction - 0.5) < 0.0001)
        clock.advance(29); engine.refresh()
        #expect(engine.phaseRemainingFraction < 0.02)
    }

    @Test("Finishing is reported once and the count settles at zero")
    func finish() {
        let clock = TestClock()
        let engine = IntervalEngine(routine: routine(rounds: 1), now: clock.provider, autoTick: false)
        var finishes = 0
        engine.onFinish = { _ in finishes += 1 }
        engine.start()

        clock.advance(75); engine.refresh()
        #expect(engine.status == .finished)
        #expect(engine.remainingInRoutine == 0)

        engine.refresh()
        #expect(finishes == 1, "finish must not fire again on later refreshes")
    }

    @Test("Running to the end completes; ending early does not")
    func endReason() {
        let clock = TestClock()
        let run = IntervalEngine(routine: routine(rounds: 1), now: clock.provider, autoTick: false)
        var reasons: [IntervalEngine.EndReason] = []
        run.onFinish = { reasons.append($0) }
        run.start()
        clock.advance(75); run.refresh()
        #expect(reasons == [.completed])
        #expect(run.endReason == .completed)

        let quit = IntervalEngine(routine: routine(rounds: 3), now: clock.provider, autoTick: false)
        var quitReasons: [IntervalEngine.EndReason] = []
        quit.onFinish = { quitReasons.append($0) }
        quit.start()
        clock.advance(20); quit.refresh()
        quit.end()
        #expect(quitReasons == [.abandoned], "walking away is not a completed session")
        #expect(quit.endReason == .abandoned)

        // A second end must not report again — the session is already over.
        quit.end()
        #expect(quitReasons.count == 1)
    }

    @Test("The last three seconds of work tick once each")
    func countdownCues() {
        let clock = TestClock()
        let engine = IntervalEngine(routine: routine(rounds: 2, work: 60, rest: 45),
                                    now: clock.provider, autoTick: false)
        var ticks = 0
        engine.onCountdownTick = { ticks += 1 }
        engine.start()

        // Quarter-second steps through the first work phase only.
        for _ in 0..<240 {
            clock.advance(0.25)
            engine.refresh()
        }
        #expect(ticks == 3, "exactly one tick at three, two and one seconds left")
    }

    @Test("Rest does not tick — only work announces its ending")
    func restDoesNotTick() {
        let clock = TestClock()
        let engine = IntervalEngine(routine: routine(rounds: 1, work: 10, rest: 10,
                                                     dropsFinalRest: false),
                                    now: clock.provider, autoTick: false)
        var tickTimes: [TimeInterval] = []
        engine.onCountdownTick = { tickTimes.append(engine.elapsed) }
        engine.start()

        for _ in 0..<100 {
            clock.advance(0.25)
            engine.refresh()
        }
        // Work is 0–10s, rest is 10–20s. Every tick must fall inside work.
        #expect(tickTimes.allSatisfy { $0 < 10 }, "got ticks at \(tickTimes)")
        #expect(tickTimes.count == 3)
    }

    @Test("Phase changes are announced exactly once each")
    func phaseChangeCues() {
        let clock = TestClock()
        let engine = IntervalEngine(routine: routine(rounds: 2), now: clock.provider, autoTick: false)
        var kinds: [Phase.Kind] = []
        engine.onPhaseChange = { if let phase = $0 { kinds.append(phase.kind) } }
        engine.start()

        for _ in 0..<400 {              // half-second steps, past the end of the routine
            clock.advance(0.5)
            engine.refresh()
        }
        #expect(kinds == [.work, .rest, .work])
    }
}

// MARK: - Formatting

@Suite("Clock formatting")
struct FormattingTests {

    @Test("A phase reads 0:01 for the whole of its final second")
    func roundsUp() {
        #expect(TimeInterval(0.4).clockString == "0:01")
        #expect(TimeInterval(1.0).clockString == "0:01")
        #expect(TimeInterval(0).clockString == "0:00")
    }

    @Test("Minutes and seconds are zero padded")
    func padding() {
        #expect(TimeInterval(41).clockString == "0:41")
        #expect(TimeInterval(65).clockString == "1:05")
        #expect(TimeInterval(840).durationString == "14:00")
    }
}

@Suite("An ending is always heard")
@MainActor
struct EndingReportTests {

    /// The one a session run to the end depends on, and the one that was
    /// silently missing. It used to be reported from a view modifier hanging
    /// on the running screen — and finishing swaps that screen out in the same
    /// update, so SwiftUI never ran the handler. Sessions completed properly
    /// wrote nothing; sessions abandoned early reported fine, because the
    /// screen stayed. Nothing in the app noticed for a fortnight.
    @Test("Running to the end reports completed")
    func naturalEndReports() {
        let clock = TestClock()
        let engine = IntervalEngine(routine: routine(), now: clock.provider, autoTick: false)
        var heard: [IntervalEngine.EndReason] = []
        engine.onEnded = { heard.append($0) }

        engine.start()
        clock.advance(engine.schedule.total + 1)
        engine.refresh()

        #expect(heard == [.completed])
        #expect(engine.endReason == .completed)
    }

    @Test("Ending early reports abandoned")
    func earlyEndReports() {
        let clock = TestClock()
        let engine = IntervalEngine(routine: routine(), now: clock.provider, autoTick: false)
        var heard: [IntervalEngine.EndReason] = []
        engine.onEnded = { heard.append($0) }

        engine.start()
        clock.advance(30)
        engine.end()

        #expect(heard == [.abandoned])
    }

    @Test("Skipping to the end is finishing, not abandoning")
    func skippingToTheEndCompletes() {
        // How a short practice actually gets finished when she is ahead of the
        // clock, and the exact path that reproduced the lost session.
        let clock = TestClock()
        let engine = IntervalEngine(routine: routine(), now: clock.provider, autoTick: false)
        var heard: [IntervalEngine.EndReason] = []
        engine.onEnded = { heard.append($0) }

        engine.start()
        while engine.status != .finished { engine.skip() }

        #expect(heard == [.completed])
    }

    @Test("An ending is reported once, however it arrives")
    func reportedOnce() {
        let clock = TestClock()
        let engine = IntervalEngine(routine: routine(), now: clock.provider, autoTick: false)
        var heard: [IntervalEngine.EndReason] = []
        engine.onEnded = { heard.append($0) }

        engine.start()
        clock.advance(engine.schedule.total + 1)
        engine.refresh()
        engine.refresh()
        engine.end()

        #expect(heard.count == 1)
    }

    @Test("The cue layer and the recorder both hear it")
    func bothCallbacksFire() {
        // They are separate on purpose: `onFinish` belongs to the haptics and
        // audio, and a recorder that shared it would silently replace them.
        let clock = TestClock()
        let engine = IntervalEngine(routine: routine(), now: clock.provider, autoTick: false)
        var cued = false
        var recorded = false
        engine.onFinish = { _ in cued = true }
        engine.onEnded = { _ in recorded = true }

        engine.start()
        clock.advance(engine.schedule.total + 1)
        engine.refresh()

        #expect(cued)
        #expect(recorded)
    }
}

@Suite("A saved routine reads as what it is")
@MainActor
struct SavedRoutineCopyTests {

    @Test("A fixed shape names its work, rest and rounds")
    func fixedShape() {
        let routine = IntervalRoutine(name: "Beam", work: 40, rest: 45, rounds: 8, moves: [])
        #expect(RoutineListView.shapeNote(routine) == "8 × 40/45")
    }

    @Test("A written-out routine never advertises a shape it does not have")
    func writtenOut() {
        // `rounds` is 8 here and means nothing: the sequence overrides it
        // entirely. The row used to print it anyway, so a six-interval routine
        // read "8 × 60/45".
        let routine = IntervalRoutine(name: "Ladder", work: 60, rest: 45, rounds: 8, moves: [])
            .following([.work(30), .rest(30), .work(20), .rest(15), .work(10), .work(10)])
        #expect(RoutineListView.shapeNote(routine) == "6 intervals written out")
        #expect(routine.roundCount == 4)
    }

    @Test("Moves cycle through a written-out sequence's work intervals")
    func movesCycleThroughASequence() {
        // What "add moves with our custom work" already does, asserted so it
        // stays true: the rotation is taken in turn by the work intervals, and
        // the rests take none of it.
        let squat = Move(name: "Beam front squat", equipment: .beam, cue: "")
        let press = Move(name: "Beam overhead press", equipment: .beam, cue: "")
        let routine = IntervalRoutine(name: "Ladder", work: 60, rest: 45, rounds: 1,
                                      moves: [squat, press])
            .following([.work(30), .rest(30), .work(20), .rest(15), .work(10)])

        let working = routine.schedule.phases.filter(\.isWork)
        #expect(working.map(\.move?.name) == ["Beam front squat", "Beam overhead press",
                                              "Beam front squat"])
        #expect(working.map(\.duration) == [30, 20, 10])
        #expect(routine.schedule.phases.filter(\.isRest).allSatisfy { $0.move == nil })
    }
}

@Suite("A clock that moves backwards")
@MainActor
struct BackwardClockTests {

    @Test("A backward clock adjustment cannot strand the session with no phase")
    func elapsedNeverGoesNegative() {
        // `Date.now` is not monotonic. Turn off "Set Automatically" mid-session
        // and move the clock back, and `elapsed` went negative:
        // `index(atElapsed:)` guards `elapsed >= 0` and returned nil, so the
        // count read 0:00, the caption read "Finished", the field held full,
        // and the session never finished until real time caught up.
        let clock = TestClock()
        let engine = IntervalEngine(routine: routine(), now: clock.provider, autoTick: false)
        engine.start()
        clock.advance(30)
        engine.refresh()
        #expect(engine.currentPhase != nil)

        clock.advance(-300)
        engine.refresh()

        #expect(engine.elapsed == 0)
        #expect(engine.currentPhase != nil, "the session lost its phase entirely")
        #expect(engine.status == .running)
    }
}

@Suite("A cadence written once and repeated")
@MainActor
struct SequenceRepeatTests {

    private let cadence: [IntervalStep] = [
        .work(30), .rest(30), .work(20), .rest(20), .work(10), .rest(10)
    ]

    @Test("Repeating multiplies the intervals without rewriting them")
    func repeatsTheCadence() {
        // Her ask: six steps wanted four times over was twenty-four steppers.
        let once = IntervalRoutine(name: "Ladder", work: 60, rest: 45, rounds: 1, moves: [])
            .following(cadence)
        let four = once.following(cadence, repeats: 4)

        #expect(once.roundCount == 3)
        #expect(four.roundCount == 12)
        #expect(four.totalDuration == once.totalDuration * 4)
        #expect(four.schedule.phases.count == once.schedule.phases.count * 4)
    }

    @Test("Rounds keep counting across passes rather than restarting")
    func roundsRunOn() {
        let four = IntervalRoutine(name: "Ladder", work: 60, rest: 45, rounds: 1, moves: [])
            .following(cadence, repeats: 4)
        let work = four.schedule.phases.filter(\.isWork)
        #expect(work.map(\.round) == Array(1...12))
    }

    @Test("A missing or absurd repeat count reads as one pass")
    func defaultsToOnce() {
        // Optional on disk, so a routine saved by the previous build decodes
        // with nil — which must mean one, not zero.
        var routine = IntervalRoutine(name: "Ladder", work: 60, rest: 45, rounds: 1, moves: [])
            .following(cadence)
        #expect(routine.sequenceRepeats == 1)
        routine.sequenceRepeatsRaw = 0
        #expect(routine.sequenceRepeats == 1)
    }

}

@Suite("A flow of her own")
@MainActor
struct FlowRoutineTests {

    @Test("Movements with no rounds schedule as flow, not as sets")
    func flowRoutineSchedules() {
        // Her question: "what if im trying to make a warm up routine?" A flow
        // movement inside a work interval would be counted down at like a set,
        // which is what `MoveKind` exists to prevent — but when the whole
        // routine is flow it is not warming up for anything.
        let movements = Array(MoveLibrary.flow.prefix(5))
        let routine = IntervalRoutine(name: "My warm-up", work: 0, rest: 0, rounds: 0, moves: [])
            .warmingUp(with: movements, seconds: 45)

        let schedule = routine.schedule
        #expect(schedule.phases.count == 5)
        #expect(schedule.phases.allSatisfy { $0.isFlow })
        #expect(schedule.phases.allSatisfy { $0.duration == 45 })
        #expect(schedule.total == 225)
        // Not a round anywhere in it, so nothing counts down at her.
        #expect(routine.roundCount == 0)
        #expect(schedule.workPhaseCount == 0)
    }

    @Test("A flow is recognisable as one from the routine alone")
    func flowIsRecognisable() {
        // What the row copy keys off: no rounds, no rotation, but movements.
        // Asserted on the routine rather than through `RoutineListView`, whose
        // statics are main-actor isolated and read badly from a test.
        let routine = IntervalRoutine(name: "My warm-up", work: 0, rest: 0, rounds: 0, moves: [])
            .warmingUp(with: Array(MoveLibrary.flow.prefix(4)), seconds: 40)
        #expect(routine.rounds == 0)
        #expect(routine.moves.isEmpty)
        #expect(routine.warmUp.count == 4)
        #expect(routine.warmUpSeconds == 40)
    }
}

@Suite("A flow holds for as long as she said")
struct FlowLengthTests {

    @Test("The length she sets is the length every movement gets")
    func flowUsesTheSetLength() {
        // The builder printed `WarmUp.seconds` — the 40-second constant — in
        // both the section note and every row, so setting the flow to 60 left
        // the screen reading 40s over a routine that was actually saved at 60.
        let movements = Array(MoveLibrary.flow.prefix(3))
        for seconds in [15, 40, 60, 90] {
            let routine = IntervalRoutine(name: "Mine", work: 0, rest: 0, rounds: 0, moves: [])
                .warmingUp(with: movements, seconds: TimeInterval(seconds))
            #expect(routine.warmUpSeconds == TimeInterval(seconds))
            #expect(routine.totalDuration == TimeInterval(seconds * 3))
            #expect(routine.schedule.phases.allSatisfy { $0.duration == TimeInterval(seconds) })
        }
    }

    @Test("A routine with no stated length falls back to the warm-up default")
    func absentLengthFallsBack() {
        // Nil is legitimate: routines saved before the flow shape existed have
        // no stored length, and their warm-ups really are the default.
        var routine = IntervalRoutine(name: "Old", work: 40, rest: 45, rounds: 8, moves: [])
        routine.warmUpMoves = Array(MoveLibrary.flow.prefix(2))
        #expect(routine.warmUpSeconds == WarmUp.seconds)
    }
}

// MARK: - Pasting a session into Whoop

@Suite("The session, written out for Whoop")
struct WhoopSummaryTests {

    @Test("A sided move reports the turns she did, not the intervals it took")
    func sidedCountsTurns() {
        // Three turns on the split squat is six work intervals — the schedule's
        // number, not hers. Whoop is being told what she lifted.
        let routine = IntervalRoutine(name: "Lower", work: 40, rest: 20, rounds: 3,
                                      moves: [named("Split squat")])
        let entry = try! #require(WhoopSummary.entries(for: routine).first)
        #expect(entry.name == "Split squat")
        #expect(entry.measure == "3 × 40s each side")
    }

    @Test("A move done one way and then the other says so in its own words")
    func directionsReadAsWays() {
        let routine = IntervalRoutine(name: "Upper", work: 45, rest: 20, rounds: 2,
                                      moves: [named("Ring halo")])
        let entry = try! #require(WhoopSummary.entries(for: routine).first)
        #expect(entry.measure == "2 × 45s each way")
    }

    @Test("Every move carries the load it is written for")
    func loadsAreNamed() {
        let routine = IntervalRoutine(name: "Mixed", work: 40, rest: 20, rounds: 4,
                                      moves: [named("Ring goblet squat"), named("Dumbbell press")])
        let entries = WhoopSummary.entries(for: routine)
        #expect(entries.count == 2)
        #expect(entries[0].equipment.contains("10 lb"))
        #expect(entries[1].equipment.contains("2 lb"))
        #expect(entries.allSatisfy { $0.measure == "2 × 40s" })
    }

    @Test("The text opens with the session and closes with the warm-up")
    func wholeText() {
        let routine = IntervalRoutine(name: "Full · mixed", work: 40, rest: 20, rounds: 2,
                                      moves: [named("Beam row")])
            .warmingUp(with: Array(MoveLibrary.flow.prefix(4)))
        let text = WhoopSummary.text(for: routine)
        #expect(text.hasPrefix("Full · mixed · "))
        #expect(text.contains("Beam row — 15 lb Bala Beam, 2 × 40s"))
        #expect(text.contains("Warm-up: 4 mobility movements, 40s each"))
    }

    @Test("A plain interval timer has nothing to tell Whoop")
    func noMoves() {
        let bare = IntervalRoutine(name: "Timer", work: 30, rest: 30, rounds: 4, moves: [])
        #expect(WhoopSummary.entries(for: bare).isEmpty)
    }
}

// MARK: - Counting the reps

@Suite("Reps she counted")
struct RepCountingTests {

    @Test("A rest knows which set it follows, and work and warm-up know they are not one")
    func setsAreFiledInOrder() {
        let routine = IntervalRoutine(name: "Test", work: 40, rest: 20, rounds: 3,
                                      moves: [named("Beam row")])
            .warmingUp(with: Array(MoveLibrary.flow.prefix(2)))
        let schedule = routine.schedule

        // Warm-up movements are not sets and file nothing.
        #expect(schedule.setOrdinal(of: 0) == nil)
        #expect(schedule.setEnding(before: 1) == nil)

        let workIndices = schedule.phases.indices.filter { schedule.phases[$0].isWork }
        #expect(workIndices.map { schedule.setOrdinal(of: $0) } == [0, 1, 2])

        // Each rest files against the set it just followed. The first rest is
        // the setup pause after the warm-up — no set precedes it, so it files
        // nothing.
        let restIndices = schedule.phases.indices.filter { schedule.phases[$0].isRest }
        #expect(restIndices.map { schedule.setEnding(before: $0) } == [nil, 0, 1])
    }

    @Test("Counted reps replace the clock; an uncounted move keeps it")
    func repsReplaceTime() {
        let routine = IntervalRoutine(name: "Mixed", work: 40, rest: 20, rounds: 4,
                                      moves: [named("Beam row"), named("Dumbbell press")])
        // Sets run row, press, row, press. Only the rows were counted.
        let entries = WhoopSummary.entries(for: routine, reps: [12, 0, 10, 0])
        #expect(entries[0].measure == "12, 10 reps")
        #expect(entries[1].measure == "2 × 40s")
    }

    @Test("Sets with the same count read as sets, and a sided move counts turns")
    func evenSetsAndSides() {
        let plain = IntervalRoutine(name: "Row", work: 40, rest: 20, rounds: 3,
                                    moves: [named("Beam row")])
        #expect(WhoopSummary.entries(for: plain, reps: [10, 10, 10]).first?.measure
                == "3 sets × 10 reps")

        // Six intervals, one per side of three turns.
        let sided = IntervalRoutine(name: "Lower", work: 40, rest: 20, rounds: 3,
                                    moves: [named("Split squat")])
        #expect(sided.schedule.workPhaseCount == 6)
        #expect(WhoopSummary.entries(for: sided, reps: [8, 8, 8, 8, 8, 8]).first?.measure
                == "3 sets × 8 reps each side")
    }

    @Test("Counting nothing leaves the summary exactly as it was")
    func noneCounted() {
        let routine = IntervalRoutine(name: "Row", work: 40, rest: 20, rounds: 2,
                                      moves: [named("Beam row")])
        #expect(WhoopSummary.entries(for: routine, reps: [0, 0]).first?.measure == "2 × 40s")
        #expect(WhoopSummary.entries(for: routine).first?.measure == "2 × 40s")
    }
}

// MARK: - The rep history

@Suite("What a session leaves for the history")
struct SetHistoryTests {

    @Test("Only the moves she counted are remembered, with their loads")
    func onlyCountedMoves() {
        let routine = IntervalRoutine(name: "Mixed", work: 40, rest: 20, rounds: 4,
                                      moves: [named("Ring goblet squat"), named("Dumbbell press")])
        // Sets run squat, press, squat, press; only the squats were counted.
        let counted = WhoopSummary.counted(for: routine, reps: [10, 0, 8, 0])
        #expect(counted.count == 1)
        #expect(counted[0].move.name == "Ring goblet squat")
        #expect(counted[0].reps == [10, 8])
        #expect(counted[0].move.loadPounds == 10)
    }

    @Test("A sided move keeps one entry per side, and reports the turns")
    func sidedKeepsBothSides() {
        let routine = IntervalRoutine(name: "Lower", work: 40, rest: 20, rounds: 2,
                                      moves: [named("Split squat")])
        let counted = WhoopSummary.counted(for: routine, reps: [8, 7, 6, 6])
        #expect(counted[0].reps == [8, 7, 6, 6])

        let log = SetLog(sourceID: UUID(), move: counted[0].move, reps: counted[0].reps)
        #expect(log.turns == 2, "four intervals is two turns, both sides")
        #expect(log.best == 8)
        #expect(log.total == 27)
    }

    @Test("Counting nothing leaves no history behind")
    func nothingCounted() {
        let routine = IntervalRoutine(name: "Row", work: 40, rest: 20, rounds: 2,
                                      moves: [named("Beam row")])
        #expect(WhoopSummary.counted(for: routine, reps: [0, 0]).isEmpty)
        #expect(WhoopSummary.counted(for: routine, reps: []).isEmpty)
    }
}
