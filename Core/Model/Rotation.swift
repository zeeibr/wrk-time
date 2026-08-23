import Foundation

/// Taking `n` things out of a list without the list's own order becoming the
/// answer.
///
/// This began inside `WarmUp`, where a morning practice was seven flow
/// movements taken as a **contiguous run** — `pool[(offset + step) % count]`
/// with `step` walking 0, 1, 2. The offset moved every day, so the test that
/// consecutive days differ passed and it looked correct for months. What never
/// moved was the order *inside* the window: Corkscrew followed Arm circles in
/// every practice either of them appeared in, because they sit four lines
/// apart in `Equipment.swift`. The library's declaration order was the
/// programme.
///
/// `MoveLibrary.rotation` had the same defect and a blunter version of it — it
/// took the first N of the pool and did not vary at all — so this lives here
/// rather than in either caller. A warm-up asking the strength library how to
/// pick moves, or the reverse, is how a question ends up with two spellings
/// that disagree.
///
/// Two properties are load-bearing:
///
/// **The spacing is coprime with the pool.** A walk then lands on `count`
/// different entries however far it steps, which is what lets a practice ask
/// for eight movements and get eight rather than five and a repeat.
///
/// **The spacing rotates as well as the start.** Rotating only the start
/// welds every entry to its neighbour for good — that was the bug. Rotating
/// only the spacing gives exactly one order per pool size. Both, and nothing
/// is fixed to anything.
///
/// Deterministic throughout: a seed in, the same answer out, no randomness
/// anywhere. `randomElement` here would change a session between her opening
/// Today and pressing begin.
enum Rotation {

    /// `count` entries out of `pool`, chosen for `seed`.
    static func walk<T>(_ pool: [T], taking count: Int, varying seed: Int) -> [T] {
        guard !pool.isEmpty, count > 0 else { return [] }
        let wanted = min(count, pool.count)
        let turn = abs(seed)
        let spacings = steps(for: pool.count)
        let step = spacings[turn % spacings.count]
        let offset = turn * stride(taking: wanted, from: pool.count)
        return (0..<wanted).map { pool[(offset + $0 * step) % pool.count] }
    }

    /// The spacings that can walk a pool of this size without landing twice.
    ///
    /// A step coprime with the pool visits every position before it repeats,
    /// so a walk can take any number of entries at any of them and never ask
    /// for the same one twice. 1 and `pool - 1` are dropped wherever there is
    /// anything else to pick: they are the list's own order forwards and
    /// backwards, which is the thing being fixed.
    static func steps(for pool: Int) -> [Int] {
        guard pool > 3 else { return [1] }
        let coprime = (1..<pool).filter { gcd($0, pool) == 1 }
        let varied = coprime.filter { $0 != 1 && $0 != pool - 1 }
        return varied.isEmpty ? coprime : varied
    }

    /// How far the window moves each turn.
    ///
    /// It has to be coprime with the pool, or the rotation closes early: a
    /// window of four stepping by four through twelve movements gives three
    /// distinct practices, so every Thursday opens like every Monday. A fixed
    /// `width + 1` fixed that for twelve and broke again at ten — dropping one
    /// movement from the library was enough. Chosen against the actual pool
    /// instead, so it cannot rot when the library changes size.
    static func stride(taking width: Int, from pool: Int) -> Int {
        guard pool > 1 else { return 1 }
        let preferred = max(width + 1, 2)
        // Walk outward from the preferred step to the first one that shares no
        // factor with the pool.
        for delta in 0..<pool {
            for candidate in [preferred + delta, preferred - delta] where candidate > 0 {
                if gcd(candidate % pool == 0 ? pool : candidate, pool) == 1 { return candidate }
            }
        }
        return 1
    }

    /// Days since the reference date, non-negative and stable across time zones
    /// because it counts calendar days rather than dividing seconds.
    static func dayIndex(_ date: Date, calendar: Calendar = .current) -> Int {
        let days = calendar.dateComponents([.day],
                                           from: Date(timeIntervalSinceReferenceDate: 0),
                                           to: calendar.startOfDay(for: date)).day ?? 0
        return abs(days)
    }

    private static func gcd(_ a: Int, _ b: Int) -> Int {
        b == 0 ? abs(a) : gcd(b, a % b)
    }
}
