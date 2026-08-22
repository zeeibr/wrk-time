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

    // MARK: How long a drawing stays up

    /// Ten, where it used to be a hard-coded five.
    ///
    /// The plate is a reminder of the shape rather than something to watch, so
    /// it retires partway through a work interval — the field's boundary
    /// sweeping down through a stick figure for the rest of the interval is
    /// what made the dissolve look wrong, and that is why it retires at all.
    /// Five turned out to be short for a move she had not done before, which
    /// is exactly the case the drawing exists for. Bounded at the top rather
    /// than free for the same reason: past twenty seconds it is back to
    /// fighting the boundary it was moved out of the way of.
    static let defaultPlateSeconds = 10
    static let plateRange = 3...20

    static var plateSeconds: Int {
        get { clamped(read(Key.plateSeconds) ?? defaultPlateSeconds, to: plateRange) }
        set { UserDefaults.standard.set(clamped(newValue, to: plateRange),
                                        forKey: Key.plateSeconds) }
    }

    // MARK: What she actually owns

    /// The kit she has to hand, by raw value.
    ///
    /// This is **not** a way to add equipment — `Equipment` stays a closed
    /// enum, and nothing outside it can ever be named. It is a way to say
    /// "not yet" about something already in it: the band was in the app
    /// before it was in the house, and a plan that programs a pull-apart she
    /// cannot do is worse than one that leaves the pull side to the rings.
    ///
    /// Stored as the *owned* set rather than the missing one, so a case added
    /// to the enum later is off until she says otherwise — the safe direction.
    /// Nil means she has never touched this, which reads as "everything",
    /// because that is what the app assumed for its whole life before now.
    /// Stored as one comma-joined string rather than an array, so a view can
    /// hold it in `@AppStorage` and redraw the moment it changes. `UserDefaults`
    /// does not publish, and the drawer she just switched off has to leave the
    /// Moves tab without waiting for a relaunch — `@AppStorage` supports a
    /// `String` and not a `[String]`, and that is the whole reason for the
    /// shape.
    static let ownedEquipmentKey = "ownedEquipmentList"

    static var ownedEquipment: Set<Equipment> {
        get { decodeOwned(UserDefaults.standard.string(forKey: ownedEquipmentKey)) }
        set {
            UserDefaults.standard.set(
                newValue.union(Equipment.alwaysOwned).map(\.rawValue).sorted().joined(separator: ","),
                forKey: ownedEquipmentKey)
        }
    }

    /// One reader for the stored string, so the view's `@AppStorage` copy and
    /// this one cannot disagree about what it means.
    static func decodeOwned(_ raw: String?) -> Set<Equipment> {
        guard let raw, !raw.isEmpty else { return Set(Equipment.allCases) }
        return Set(raw.split(separator: ",").compactMap { Equipment(rawValue: String($0)) })
            .union(Equipment.alwaysOwned)
    }

    /// Whether she has ever said anything about her kit. Used only to decide
    /// whether the one-time seed should speak.
    static var hasSetEquipment: Bool {
        UserDefaults.standard.string(forKey: ownedEquipmentKey) != nil
    }

    // MARK: -

    private enum Key {
        static let movesPerSession = "movesPerSession"
        static let practiceMovements = "practiceMovements"
        static let plateSeconds = "plateSeconds"
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
        UserDefaults.standard.removeObject(forKey: Key.plateSeconds)
        // Deliberately not the kit. This puts the three *numbers* back where
        // they started; what she owns is a fact about her house, not a setting
        // with a sensible default, and clearing it here made a test that
        // resets tuning silently hand the band back to every suite running
        // beside it.
    }
}
