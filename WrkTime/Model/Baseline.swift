import Foundation
import SwiftData

/// Where she is, measured — `docs/COACH-BRIEF.md` §11.
///
/// Two tests, both **extras**: they earn no mark, never replace a session,
/// and are recorded as her own workouts so the planner sees them as volume.
/// That was her decision: *"the tests shouldnt be a session they shoudl just
/// be extra."*
///
/// - **The baseline** — six moves, one per pattern, a fixed load each, one
///   set to one or two reps in reserve. Run once at the start, then every
///   four weeks for the first block, then every six. Under twenty-five
///   minutes with the warm-up.
/// - **The weekly check** — two of the six, rotating, so every pattern has a
///   fresh number every three weeks. About eight minutes.
///
/// Both are rep-mode routines of one set per move, so the set is open until
/// she ends it and the count lands on the rest as it does anywhere else. A
/// hold — the side plank — is scored by how long the set ran, which the
/// engine keeps for every open set.
///
/// Scoring turns a count into a working load through the ladder, and the
/// result is **offered** through `MoveOverrides` like any load change. A
/// load no pattern uses is offered for retirement; one a score has earned
/// is offered for unlocking. Her tap, always.
enum Baseline {

    /// One pattern's test: the move, the load it is tested at, and whether
    /// the score is reps or seconds.
    struct Station: Equatable, Identifiable {
        var id: String { pattern.rawValue }
        let pattern: MovePattern
        let moveName: String
        let loadPounds: Double?
        /// A hold is scored in seconds; everything else in reps.
        let isHold: Bool

        var move: Move? {
            guard let move = MoveLibrary.all.first(where: {
                MovePreference.key($0.name) == MovePreference.key(moveName)
            }) else { return nil }
            guard let loadPounds else { return move }
            return move.applyingLoad(from: [MovePreference.key(move.name): loadPounds])
        }
    }

    /// The six, in running order. Loads are the brief's, on the kit she
    /// owns: the goblet squat is tested on the 13 lb bell because the single
    /// dumbbells have no goblet squat written for them, and 13 is the bell
    /// between the brief's 10 and the 18.
    static let stations: [Station] = [
        Station(pattern: .hinge, moveName: "Kettlebell deadlift", loadPounds: 18, isHold: false),
        Station(pattern: .squat, moveName: "Kettlebell goblet squat", loadPounds: 13, isHold: false),
        Station(pattern: .lunge, moveName: "Reverse lunge", loadPounds: nil, isHold: false),
        Station(pattern: .pullHorizontal, moveName: "Kettlebell row", loadPounds: 18, isHold: false),
        Station(pattern: .pushHorizontal, moveName: "Incline push-up", loadPounds: nil, isHold: false),
        Station(pattern: .coreAntiRotation, moveName: "Side plank", loadPounds: nil, isHold: true),
    ]

    static let name = "Baseline"
    static let checkName = "Weekly check"

    /// The score band that says the test load is the working load. Under it,
    /// the next load down; over it, the next load up or the move intensified.
    static let keepRange = 8...15
    /// A hold's band, in seconds: the side plank at thirty to sixty is where
    /// it should be for a beginner.
    static let holdRange = 30...60

    /// Every four weeks for the first block, then every six.
    static func retestAfterDays(baselinesSoFar count: Int) -> Int { count < 3 ? 28 : 42 }
    static let checkAfterDays = 7

    // MARK: - The routines

    /// The full test, one set per station, warmed up like any session.
    static func routine(warmUp: [Move] = []) -> IntervalRoutine {
        IntervalRoutine(name: name, work: 0, rest: 0, rounds: 0,
                        moves: stations.compactMap(\.move))
            .inMode(.reps, sets: 1)
            .warmingUp(with: warmUp)
    }

    /// Two stations, rotating by how many checks have been done, so the six
    /// come round every three weeks.
    static func check(turn: Int, warmUp: [Move] = []) -> IntervalRoutine {
        let first = (turn * 2) % stations.count
        let pair = [stations[first], stations[(first + 1) % stations.count]]
        return IntervalRoutine(name: checkName, work: 0, rest: 0, rounds: 0,
                               moves: pair.compactMap(\.move))
            .inMode(.reps, sets: 1)
            .warmingUp(with: warmUp)
    }

    // MARK: - Scoring

    /// What one station's score says about the load.
    enum Verdict: Equatable {
        /// The test load is the working load.
        case hold
        /// The next load down, or the easier variant.
        case down(to: Double?)
        /// The next load up, or the move made harder, when there is no load.
        case up(to: Double?)

        var isChange: Bool { self != .hold }
    }

    struct Result: Equatable, Identifiable {
        var id: String { station.id }
        let station: Station
        /// Reps, or seconds for a hold.
        let score: Int
        let verdict: Verdict
        /// The working rep target for the block: two thirds of the score,
        /// rounded down, floored at the bottom of the range.
        var repTarget: Int { max(LoadProgression.repTarget - 4, score * 2 / 3) }

        var line: String {
            let what = station.isHold ? "\(score) s" : "\(score) reps"
            let load = station.loadPounds.map { station.move?.equipment.label(forLoad: $0) ?? "" }
            let at = load.map { " at the \($0.lowercasedFirst)" } ?? ""
            switch verdict {
            case .hold:
                return "\(station.pattern.label): \(what)\(at). That is the working load."
            case .down(let to):
                if let to, let move = station.move {
                    return "\(station.pattern.label): \(what)\(at). Under eight, so the \(move.equipment.label(forLoad: to).lowercasedFirst) for now."
                }
                return "\(station.pattern.label): \(what). Under the range — the easier version for now, and that is the plan working."
            case .up(let to):
                if let to, let move = station.move {
                    return "\(station.pattern.label): \(what)\(at). Over fifteen — the \(move.equipment.label(forLoad: to).lowercasedFirst) is earned."
                }
                return station.isHold
                    ? "\(station.pattern.label): \(what). Past a minute — a harder version is earned."
                    : "\(station.pattern.label): \(what). Over fifteen — a harder version is earned."
            }
        }
    }

    /// Scores a finished test from the rows it wrote. Stations she did not
    /// count are left out rather than guessed.
    @MainActor
    static func results(for run: RoutineRun, in context: ModelContext) -> [Result] {
        let logs = ((try? context.fetch(FetchDescriptor<SetLog>())) ?? [])
            .filter { $0.sourceID == run.id }
        return stations.compactMap { station in
            guard let log = logs.first(where: {
                MovePreference.key($0.moveName) == MovePreference.key(station.moveName)
            }) else { return nil }
            let score: Int
            if station.isHold {
                // A hold is its length. Sided: the shorter side is the score,
                // because the weaker side is the one the plan is written for.
                guard let seconds = log.setSeconds, !seconds.isEmpty else { return nil }
                score = Int(seconds.min() ?? 0)
            } else {
                guard let reps = log.reps.filter({ $0 > 0 }).min() else { return nil }
                score = reps
            }
            return Result(station: station, score: score, verdict: verdict(for: station, score: score))
        }
    }

    static func verdict(for station: Station, score: Int) -> Verdict {
        let range = station.isHold ? holdRange : keepRange
        if range.contains(score) { return .hold }
        guard let move = station.move, let load = station.loadPounds else {
            return score < range.lowerBound ? .down(to: nil) : .up(to: nil)
        }
        let ladder = move.equipment.availableLoadsPounds.sorted()
        if score < range.lowerBound {
            return .down(to: ladder.last { $0 < load })
        }
        return .up(to: ladder.first { $0 > load })
    }

    // MARK: - When

    /// Which test, if any, Today should offer. Never on a day the recovery
    /// guidance says to hold, never before the day's session, and never
    /// more often than the cadence — a test that displaces training is the
    /// thing the coach argued against.
    enum Offer: Equatable { case baseline, check(turn: Int) }

    static func offer(runs: [RoutineRun], sessionDoneOrRestDay: Bool,
                      recoveryHolding: Bool, now: Date = .now) -> Offer? {
        guard sessionDoneOrRestDay, !recoveryHolding else { return nil }
        let tests = runs.filter { $0.source == .test }
        let baselines = tests.filter { $0.name == name }.sorted { $0.finishedAt < $1.finishedAt }
        guard let last = baselines.last else { return .baseline }
        let days = Calendar.current.dateComponents([.day], from: last.finishedAt, to: now).day ?? 0
        if days >= retestAfterDays(baselinesSoFar: baselines.count) { return .baseline }
        let checks = tests.filter { $0.name == checkName }
        let latest = checks.map(\.finishedAt).max() ?? last.finishedAt
        let sinceCheck = Calendar.current.dateComponents([.day], from: latest, to: now).day ?? 0
        guard sinceCheck >= checkAfterDays else { return nil }
        return .check(turn: checks.count)
    }
}

private extension String {
    var lowercasedFirst: String {
        guard let first = first else { return self }
        return first.lowercased() + dropFirst()
    }
}
