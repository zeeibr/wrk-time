import Foundation

/// What a move *is*, independent of what it is held with.
///
/// The library is listed by implement because that is how it was bought, but
/// a session is not experienced that way: it is experienced as a hinge, then
/// a squat, then a row, then getting down on the floor and not getting back
/// up. These two lookups give the rotation builder and the screens that
/// vocabulary. See `docs/COACH-BRIEF.md` §9 for the shape they serve.
///
/// Since the August 2026 port the pattern and position live on the
/// `Movement` in `MovementCatalog`, once per movement rather than once per
/// implement; this is the lookup the rest of the app asks. Her own approved
/// additions are classified by the review and registered here. A name
/// nothing knows returns nil and the builder treats it as "free".

/// The movement pattern a move trains. Coverage is checked per pattern: a
/// rotation wants one lower, one pull, one push, one core, and a week wants
/// every pattern at least twice.
enum MovePattern: String, CaseIterable, Codable {
    case squat, hinge, lunge
    case pushHorizontal, pushVertical
    case pullHorizontal, pullVertical
    case carry
    case coreAntiRotation, coreFlexion, coreExtension
    /// Isolation work: curls, raises, extensions. Real, but it fills a slot
    /// rather than covering a pattern.
    case accessory

    var label: String {
        switch self {
        case .squat: "Squat"
        case .hinge: "Hinge"
        case .lunge: "Lunge"
        case .pushHorizontal: "Push"
        case .pushVertical: "Press"
        case .pullHorizontal: "Row"
        case .pullVertical: "Pull"
        case .carry: "Carry"
        case .coreAntiRotation: "Core · brace"
        case .coreFlexion: "Core · flex"
        case .coreExtension: "Core · extend"
        case .accessory: "Accessory"
        }
    }

    /// The coarse family the rotation builder reasons in.
    var family: Family {
        switch self {
        case .squat, .hinge, .lunge: .lower
        case .pushHorizontal, .pushVertical: .push
        case .pullHorizontal, .pullVertical: .pull
        case .carry, .coreAntiRotation, .coreFlexion, .coreExtension: .core
        case .accessory: .accessory
        }
    }

    enum Family: CaseIterable { case lower, push, pull, core, accessory }

    /// Rest between sets in reps mode, from the coach brief §7: about 75 s
    /// after a big lower lift, 60 after an upper compound, 45 for isolation
    /// and core. Shorter than a gym's barbell numbers because the loads are
    /// light; enough for form to come back, which is what rest is for here.
    var restSeconds: Int {
        switch family {
        case .lower: 75
        case .push, .pull: 60
        case .core: 45
        case .accessory: 45
        }
    }

    /// A lift the coach calls "big": the one after which the rest between
    /// moves is the full set rest rather than the flat 30 seconds.
    var isBigLift: Bool { family == .lower }
}

/// Where the body is for the move. The order is the order of a session:
/// standing first, then anything that starts on the floor — and kneeling is
/// a floor move that starts higher, so it sorts into the floor block, never
/// as a tier between.
enum MovePosition: Int, CaseIterable, Codable, Comparable {
    case standing = 0
    case kneeling = 1
    case floor = 2

    var label: String {
        switch self {
        case .standing: "Standing"
        case .kneeling: "Kneeling"
        case .floor: "On the mat"
        }
    }

    /// Whether moving from `self` to `next` is a change the timer should
    /// buy time for. Standing to anything lower is a change; kneeling to
    /// floor is not — she is already down.
    func changes(to next: MovePosition) -> Bool {
        (self == .standing) != (next == .standing)
    }

    static func < (a: MovePosition, b: MovePosition) -> Bool { a.rawValue < b.rawValue }
}

enum MoveTaxonomy {
    /// The catalog answers for every built-in; the registry for her own
    /// approved additions.
    static func pattern(for name: String) -> MovePattern? {
        if let movement = MovementCatalog.movement(for: name) { return movement.pattern }
        return registry.read(MovePreference.key(name))?.0
    }

    static func position(for name: String) -> MovePosition? {
        if let movement = MovementCatalog.movement(for: name) { return movement.position }
        return registry.read(MovePreference.key(name))?.1
    }

    /// Her own approved additions, classified by the review. The built-in
    /// table is typed; these arrive at approval and are re-registered from
    /// the store at launch, so an addition files into the body sections and
    /// the rotation builder like anything built in.
    static func register(_ name: String, pattern: MovePattern?, position: MovePosition?) {
        guard let pattern, let position else { return }
        registry.write(MovePreference.key(name), (pattern, position))
    }

    /// A small locked table: read from views on the main actor, written at
    /// approval and at launch.
    private static let registry = Registry()
    private final class Registry: @unchecked Sendable {
        private var table: [String: (MovePattern, MovePosition)] = [:]
        private let lock = NSLock()
        func read(_ key: String) -> (MovePattern, MovePosition)? {
            lock.lock(); defer { lock.unlock() }
            return table[key]
        }
        func write(_ key: String, _ value: (MovePattern, MovePosition)) {
            lock.lock(); defer { lock.unlock() }
            table[key] = value
        }
    }

    /// Setup seconds the timer adds between two moves, from the coach brief
    /// §8: 20 for a position change, 15 for an implement change, 30 for
    /// both, none when neither changes. Separate from rest on purpose —
    /// rest is physiology and this is logistics, and the number she is short
    /// of has to be tellable from the number she is not.
    static func setupSeconds(from a: Move, to b: Move) -> Int {
        let position = (position(for: a.name) ?? .standing)
            .changes(to: position(for: b.name) ?? .standing)
        // A change of implement is something to *fetch*: the next move wants
        // a thing the last one was not holding. Putting a bell down to do a
        // push-up costs nothing and is not counted.
        let implement = b.equipment != .bodyweight && a.equipment != b.equipment
        switch (position, implement) {
        case (true, true): return 30
        case (true, false): return 20
        case (false, true): return 15
        case (false, false): return 0
        }
    }
}
