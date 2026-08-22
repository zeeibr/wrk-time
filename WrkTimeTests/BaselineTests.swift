import Testing
import Foundation
import SwiftData
@testable import WrkTime

/// The baseline and the weekly check, `docs/COACH-BRIEF.md` §11.
@Suite("Where you are")
@MainActor
struct BaselineTests {

    @Test("Every station is a real move at a load the kit has")
    func stationsResolve() {
        for station in Baseline.stations {
            let move = station.move
            #expect(move != nil, "\(station.moveName)")
            if let load = station.loadPounds, let move {
                #expect(move.equipment.availableLoadsPounds.contains(load), "\(station.moveName)")
                #expect(move.loadPounds == load)
            }
            #expect(MoveTaxonomy.pattern(for: station.moveName) == station.pattern, "\(station.moveName)")
        }
        #expect(Set(Baseline.stations.map(\.pattern)).count == 6)
    }

    @Test("The baseline is one open set per station, standing first, under twenty-five minutes")
    func routineShape() {
        let routine = Baseline.routine(warmUp: Array(MoveLibrary.flow.prefix(4)))
        #expect(routine.mode == .reps)
        #expect(routine.setsPerMove == 1)
        #expect(routine.moves.count == 6)
        let positions = routine.moves.map { MoveTaxonomy.position(for: $0.name) ?? .standing }
        let down = positions.firstIndex { $0 != .standing } ?? positions.count
        #expect(positions[down...].allSatisfy { $0 != .standing })
        #expect(routine.schedule.total <= 25 * 60, "\(routine.schedule.total)")
        #expect(routine.schedule.phases.filter(\.isWork).allSatisfy { $0.openEnded })
    }

    @Test("The weekly check rotates through the six in pairs")
    func checkRotates() {
        let turns = (0..<3).map { Baseline.check(turn: $0).moves.map(\.name) }
        #expect(turns.allSatisfy { $0.count == 2 })
        #expect(Set(turns.flatMap { $0 }).count == 6, "\(turns)")
        #expect(Baseline.check(turn: 3).moves.map(\.name) == turns[0])
    }

    @Test("Eight to fifteen holds; under goes down the ladder; over goes up")
    func verdicts() {
        let hinge = Baseline.stations[0]
        #expect(Baseline.verdict(for: hinge, score: 10) == .hold)
        #expect(Baseline.verdict(for: hinge, score: 6) == .down(to: 13))
        #expect(Baseline.verdict(for: hinge, score: 16) == .up(to: 35))
        let push = Baseline.stations.first { $0.pattern == .pushHorizontal }!
        #expect(Baseline.verdict(for: push, score: 20) == .up(to: nil))
        let plank = Baseline.stations.first { $0.isHold }!
        #expect(Baseline.verdict(for: plank, score: 45) == .hold)
        #expect(Baseline.verdict(for: plank, score: 20) == .down(to: nil))
    }

    @Test("Never before a session, never on a held day, then every four weeks and weekly between")
    func cadence() {
        func run(_ name: String, daysAgo: Int) -> RoutineRun {
            let run = RoutineRun(name: name, roundsCompleted: 6, seconds: 900, moveNames: [],
                                 source: .test,
                                 finishedAt: Calendar.current.date(byAdding: .day, value: -daysAgo, to: .now)!)
            return run
        }
        #expect(Baseline.offer(runs: [], sessionDoneOrRestDay: false, recoveryHolding: false) == nil)
        #expect(Baseline.offer(runs: [], sessionDoneOrRestDay: true, recoveryHolding: true) == nil)
        #expect(Baseline.offer(runs: [], sessionDoneOrRestDay: true, recoveryHolding: false) == .baseline)

        let fresh = [run(Baseline.name, daysAgo: 2)]
        #expect(Baseline.offer(runs: fresh, sessionDoneOrRestDay: true, recoveryHolding: false) == nil)

        let weekOn = [run(Baseline.name, daysAgo: 8)]
        #expect(Baseline.offer(runs: weekOn, sessionDoneOrRestDay: true, recoveryHolding: false) == .check(turn: 0))

        let checked = [run(Baseline.name, daysAgo: 15), run(Baseline.checkName, daysAgo: 8)]
        #expect(Baseline.offer(runs: checked, sessionDoneOrRestDay: true, recoveryHolding: false) == .check(turn: 1))

        let month = [run(Baseline.name, daysAgo: 29), run(Baseline.checkName, daysAgo: 3)]
        #expect(Baseline.offer(runs: month, sessionDoneOrRestDay: true, recoveryHolding: false) == .baseline)
    }

    @Test("Scoring reads the rows the run wrote; a hold is its shortest side")
    func scoring() throws {
        let container = try ModelContainer(for: RoutineRun.self, SetLog.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        let routine = Baseline.routine()
        let run = RoutineRuns.record(routine, source: .test, seconds: 900, in: context)
        // Deadlift 10, goblet 7, lunge 12/12, row 9/9, push-up 16, plank 40 s / 35 s.
        let reps = [10, 7, 12, 12, 9, 9, 16, 0, 0]
        let durations: [Int: TimeInterval] = [7: 40, 8: 35]
        SetLogs.record(routine, reps: reps, durations: durations, sourceID: run.id, in: context)
        let results = Baseline.results(for: run, in: context)
        #expect(results.count == 6, "\(results.map(\.station.moveName))")
        #expect(results.first { $0.station.pattern == .hinge }?.verdict == .hold)
        #expect(results.first { $0.station.pattern == .squat }?.verdict == .down(to: 9))
        #expect(results.first { $0.station.pattern == .pushHorizontal }?.verdict == .up(to: nil))
        // The plank has no count — a hold — but she ended both sides herself,
        // so its seconds are the record, and the shorter side is the score.
        let plank = results.first { $0.station.isHold }
        #expect(plank?.score == 35)
        #expect(plank?.verdict == .hold)
        // The hold's zero-rep row stays out of the move sheet's history.
        let move = Baseline.stations.first { $0.isHold }!.move!
        #expect(SetLogs.history(for: move, in: context).isEmpty)
    }
}
