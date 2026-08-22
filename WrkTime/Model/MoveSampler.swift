import Foundation

/// A tasting flight through the library: ten seconds on each of six moves she
/// has not tried, ten seconds between them. Her ask, in her words: a mode "to
/// try all the moves — keep track of what weve tried and what we havent".
///
/// Two deliberate shapes:
///
/// **"Tried" is derived, never stored.** A move counts as tried when it has
/// appeared in anything she finished — a completed planned session's routine,
/// a `RoutineRun`'s move names, a loose `SetLog`. Deriving it from the records
/// that already exist means the history she has counts retroactively, and
/// there is no second ledger that could disagree with the first. Finishing a
/// sampler records a `RoutineRun` like any routine, which is exactly what
/// advances the tracking — no special path, per the app's own bug-shape rule.
///
/// **It earns no mark.** Ten-second tastes are not a session; the sampler is
/// a `RoutineRun` like any of her own workouts, and at two minutes it stays
/// under the substantial floor, so it does not even earn a tick. That is
/// right: it is a browse, not a workout.
enum MoveSampler {
    /// Ten seconds is a taste: enough to feel the shape of a movement, not
    /// enough to be a set. Below the planner's 20-second floor on purpose —
    /// this routine is never planned, only composed here.
    static let work: TimeInterval = 10
    static let rest: TimeInterval = 10
    static let count = 6

    /// Every move that has been part of something she finished, as comparison
    /// keys. Pure values in, so the tests need no store.
    static func triedKeys(routines: [IntervalRoutine],
                          runMoveNames: [[String]],
                          logMoveNames: [String]) -> Set<String> {
        var keys: Set<String> = []
        for routine in routines {
            for move in routine.moves { keys.insert(MovePreference.key(move.name)) }
        }
        for names in runMoveNames {
            for name in names { keys.insert(MovePreference.key(name)) }
        }
        for name in logMoveNames { keys.insert(MovePreference.key(name)) }
        return keys
    }

    /// The next flight: six strength moves she has not tried, in library
    /// order, honouring refusals the same way every rotation builder does.
    /// When fewer than six remain untried, tried moves fill the flight rather
    /// than shortening it — the mode stays useful after the library is
    /// exhausted, as a re-taste.
    static func build(from library: [Move],
                      tried: Set<String>,
                      avoiding ruledOut: Set<String> = [],
                      loads: [String: Double] = [:]) -> IntervalRoutine {
        let pool = library.filter {
            $0.kind == .strength && !MovePreference.anyCovers(ruledOut, $0.name)
        }
        var rotation = Array(pool.filter { !tried.contains(MovePreference.key($0.name)) }
            .prefix(count))
        if rotation.count < count {
            let taken = Set(rotation.map { MovePreference.key($0.name) })
            rotation += pool.filter { !taken.contains(MovePreference.key($0.name)) }
                .prefix(count - rotation.count)
        }
        return IntervalRoutine(name: "Sampler",
                               work: work, rest: rest,
                               rounds: rotation.count,
                               moves: rotation.map { $0.applyingLoad(from: loads) })
    }

    /// How many of the pool she has tried, for the section note. Counted
    /// against the same pool `build` draws from, so the note and the flight
    /// cannot disagree.
    static func progress(library: [Move], tried: Set<String>) -> (tried: Int, total: Int) {
        let pool = library.filter { $0.kind == .strength }
        let done = pool.count { tried.contains(MovePreference.key($0.name)) }
        return (done, pool.count)
    }
}
