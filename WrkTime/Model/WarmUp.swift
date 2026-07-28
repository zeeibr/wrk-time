import Foundation

/// The flow practice that opens every session.
///
/// She already does a round of qi gong and lymphatic movement in the morning
/// and asked for it to sit in front of the session rather than replace part of
/// it — "in addition to the session … 3-5 at the start". So this is additive by
/// construction: it never removes a round, never shortens a work interval, and
/// never counts toward the rounds a session claims.
///
/// It is assembled **here rather than by the planner**, deliberately. Every
/// week gets a warm-up whether Claude wrote it or the offline planner did,
/// without another required field for a model to fill and get wrong, and
/// without spending schema budget on a decision that has one correct answer.
/// The one thing it has to respect is what she has said about moves, and it
/// reads that from the same place everything else does.
enum WarmUp {
    /// Three to five, aiming at four. Four movements at forty seconds is a
    /// touch under three minutes — long enough to be a practice, short enough
    /// that it never becomes the reason a session is skipped.
    static let target = 4
    static let minimum = 3
    static let maximum = 5
    static let seconds: TimeInterval = 40

    /// The practice for one day.
    ///
    /// Rotated by the date rather than shuffled, so the same day always
    /// produces the same practice — a plan you can look at twice and see the
    /// same thing — while consecutive days differ. `Set.randomElement` here
    /// would make a session change under her between opening Today and pressing
    /// begin.
    static func moves(on date: Date,
                      avoiding excluded: Set<String> = [],
                      count: Int = target,
                      library: [Move] = MoveLibrary.flow) -> [Move] {
        let wanted = min(max(count, minimum), maximum)
        let allowed = library.filter { move in
            !excluded.contains { !$0.isEmpty && MovePreference.key(move.name).contains($0) }
        }
        // If she has ruled out nearly the whole practice, honour that and open
        // with whatever is left rather than reaching past her to fill the slots.
        guard !allowed.isEmpty else { return [] }

        let offset = dayIndex(date) * stride(taking: wanted, from: allowed.count)
        return (0..<min(wanted, allowed.count)).map { step in
            allowed[(offset + step) % allowed.count]
        }
    }

    /// The movements this day's session should open with, given what the
    /// morning practice already used.
    ///
    /// She does the practice and the session on the same day, so repeating a
    /// movement between them would be the app failing to notice it had already
    /// asked for it. Twelve flow movements, eight in the morning, four left —
    /// which is exactly a warm-up.
    static func afterPractice(on date: Date,
                              avoiding excluded: Set<String> = [],
                              count: Int = target) -> [Move] {
        let used = Set(Practice.moves(on: date, avoiding: excluded).map { MovePreference.key($0.name) })
        let left = MoveLibrary.flow.filter { !used.contains(MovePreference.key($0.name)) }
        // If the practice took nearly everything, fall back to the whole
        // library rather than opening a session with one movement.
        guard left.count >= minimum else {
            return moves(on: date, avoiding: excluded, count: count)
        }
        return moves(on: date, avoiding: excluded, count: count, library: left)
    }

    /// How far the window moves each day.
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

    private static func gcd(_ a: Int, _ b: Int) -> Int {
        b == 0 ? abs(a) : gcd(b, a % b)
    }

    /// Days since the reference date, non-negative and stable across time zones
    /// because it counts calendar days rather than dividing seconds.
    static func dayIndex(_ date: Date, calendar: Calendar = .current) -> Int {
        let days = calendar.dateComponents([.day],
                                           from: Date(timeIntervalSinceReferenceDate: 0),
                                           to: calendar.startOfDay(for: date)).day ?? 0
        return abs(days)
    }
}
