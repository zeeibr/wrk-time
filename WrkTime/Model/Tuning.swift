import Foundation

/// The two numbers she wanted her hands on.
///
/// Everything else about a week is the planner's call — which moves, how many
/// rounds, how much rest. These two are shape rather than programming: how many
/// movements a session rotates through, and how long the morning practice runs.
/// Both were constants until she asked for them, and both are bounded rather
/// than free, because the things downstream of them are not infinitely elastic:
/// the response schema names a slot per move, and the practice cannot ask for
/// more movements than the flow library holds.
enum Tuning {
    // MARK: Moves in a session's rotation

    /// Five, where it used to be three.
    static let defaultMovesPerSession = 5
    /// The schema names a slot per move, and `ClaudePlanner.moveSlots` has six
    /// names. Below two it is not a rotation.
    static let movesPerSessionRange = 2...6

    static var movesPerSession: Int {
        get { clamped(read(Key.movesPerSession) ?? defaultMovesPerSession, to: movesPerSessionRange) }
        set { UserDefaults.standard.set(clamped(newValue, to: movesPerSessionRange),
                                        forKey: Key.movesPerSession) }
    }

    // MARK: Movements in the morning practice

    static let defaultPracticeMovements = 8
    /// Capped by the flow library itself: the practice cannot ask for more
    /// movements than exist, and asking for all of them leaves the session
    /// warm-up nothing of its own.
    static var practiceRange: ClosedRange<Int> { 3...max(4, MoveLibrary.flow.count) }

    static var practiceMovements: Int {
        get { clamped(read(Key.practiceMovements) ?? defaultPracticeMovements, to: practiceRange) }
        set { UserDefaults.standard.set(clamped(newValue, to: practiceRange),
                                        forKey: Key.practiceMovements) }
    }

    /// How long that practice runs, given the count.
    static var practiceDuration: TimeInterval {
        Practice.seconds * Double(practiceMovements)
    }

    // MARK: -

    private enum Key {
        static let movesPerSession = "movesPerSession"
        static let practiceMovements = "practiceMovements"
    }

    /// Nil rather than zero when nothing has been set, so a default is a
    /// default rather than a value she chose.
    private static func read(_ key: String) -> Int? {
        UserDefaults.standard.object(forKey: key) as? Int
    }

    private static func clamped(_ value: Int, to range: ClosedRange<Int>) -> Int {
        min(max(value, range.lowerBound), range.upperBound)
    }

    /// Puts both back where they started.
    static func reset() {
        UserDefaults.standard.removeObject(forKey: Key.movesPerSession)
        UserDefaults.standard.removeObject(forKey: Key.practiceMovements)
    }
}
