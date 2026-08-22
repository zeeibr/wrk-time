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

    /// The pause between the last flow movement and round one — time to get
    /// the kit out. The schedule used to step straight from a bare-handed
    /// spinal wave into a loaded work interval, which left fetching the beam
    /// or threading a ring to happen *during* the set. Half a minute: enough
    /// to pick the weight up, not enough to cool down.
    static let setupSeconds: TimeInterval = 30

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

        return Rotation.walk(allowed, taking: wanted, varying: Rotation.dayIndex(date))
    }

    /// The movements this day's session should open with, given what the
    /// morning practice already used.
    ///
    /// She does the practice and the session on the same day, so repeating a
    /// movement between them would be the app failing to notice it had already
    /// asked for it. Twelve flow movements, eight in the morning, four left —
    /// which is exactly a warm-up.
    /// `library` is the whole flow pool for the day — built-ins plus her
    /// approved flow additions where the caller has a store to read them from.
    /// It is used for both halves of the question, deliberately: what the
    /// practice used this morning and what is left must be answered against
    /// the same pool or a custom movement could appear in both.
    static func afterPractice(on date: Date,
                              avoiding excluded: Set<String> = [],
                              count: Int = target,
                              practiceCount: Int? = nil,
                              library: [Move] = MoveLibrary.flow) -> [Move] {
        let used = Set(Practice.moves(on: date, avoiding: excluded, count: practiceCount,
                                      library: library)
            .map { MovePreference.key($0.name) })
        let left = library.filter { !used.contains(MovePreference.key($0.name)) }
        // If the practice took nearly everything, fall back to the whole
        // library rather than opening a session with one movement.
        guard left.count >= minimum else {
            return moves(on: date, avoiding: excluded, count: count, library: library)
        }
        return moves(on: date, avoiding: excluded, count: count, library: left)
    }
}
