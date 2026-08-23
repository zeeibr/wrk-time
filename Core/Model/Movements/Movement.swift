import Foundation

/// A movement, independent of what it is held with.
///
/// The library used to be a product table: one row per (movement,
/// implement), with the pattern, the muscles, the five form lines and the
/// drawing typed again for every implement the same movement could be done
/// on — a row ×5, a deadlift ×5, a curl ×4. A movement is the unit a coach
/// reasons in, so it is the unit here; the implement, the grip, the load
/// and the one-line cue are the **variant**, and a variant's name is
/// exactly the name the app has always used, so nothing on disk renames.
///
/// `Move` — the thing a routine stores and the timer runs — is unchanged.
/// `MoveLibrary.all` is built from the catalog below, and a test proves it
/// matches the hand-written library it replaced, move for move.
struct Movement: Sendable {
    /// Stable identity, never shown: "row", "deadlift", "goblet-squat".
    let id: String
    /// "Row", "Deadlift" — the noun every variant's name contains, so a
    /// refusal of the noun still covers the family (`MovePreference.anyCovers`).
    let display: String
    let pattern: MovePattern
    let position: MovePosition
    /// The seven words the chips speak.
    let muscles: String
    /// Written once, implement-neutral; a variant may override a line.
    let form: MoveForm
    var kind: MoveKind = .strength
    /// One per implement the movement is done on. Irregular by nature —
    /// "Dumbbell press" but "Ring overhead press" — so each names itself.
    let variants: [Variant]

    /// One movement on one implement, with one grip.
    struct Variant: Sendable {
        /// The stored name, exactly as the library has always had it.
        let name: String
        let equipment: Equipment
        let hold: Equipment.Hold
        /// The load the variant is written for; nil for bodyweight.
        var loadPounds: Double? = nil
        /// Set when the grip makes it one side at a time.
        var sided: Sided? = nil
        /// The one line the timer says. Per variant because it names the
        /// implement and the load.
        let cue: String
        /// A form line that differs for this implement, or nil to use the
        /// movement's.
        var form: MoveForm? = nil
    }

    /// The variants as the rest of the app sees them.
    var moves: [Move] {
        variants.map { v in
            var move = Move(name: v.name, equipment: v.equipment, kind: kind, cue: v.cue,
                            loadPounds: v.loadPounds, sided: v.sided)
            move.movementID = id
            return move
        }
    }
}

/// Every movement, by family. Each family is its own file under
/// `Movements/`, ported from the hand-written library one family at a time;
/// `MoveLibrary` reads this list and nothing else for a ported movement.
enum MovementCatalog {
    static var all: [Movement] { families.flatMap { $0 } }

    /// Registered here, one line per family file.
    static let families: [[Movement]] = [
        lowerBody, upperBody, coreAndCarry, accessory
    ]

    /// Lookups by the stored name, for the three tables to consult first.
    static let byVariantName: [String: (Movement, Movement.Variant)] = {
        var table: [String: (Movement, Movement.Variant)] = [:]
        for movement in all {
            for variant in movement.variants {
                table[MovePreference.key(variant.name)] = (movement, variant)
            }
        }
        return table
    }()

    static func movement(for name: String) -> Movement? {
        byVariantName[MovePreference.key(name)]?.0
    }

    static let byID: [String: Movement] = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })

    /// Every stored name of a movement's variants, for reading history
    /// across implements.
    static func variantNames(of id: String) -> Set<String> {
        Set(byID[id]?.variants.map { MovePreference.key($0.name) } ?? [])
    }
}
