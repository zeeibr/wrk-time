import Foundation

/// What each built-in move works, in the same seven words the suggestion
/// chips use. Display only — nothing programs against it — and kept as a
/// lookup beside the library rather than a stored field, so no routine on
/// disk changes shape for the sake of a label.
///
/// Custom moves carry their own `muscles` string, written by the review.
enum MoveMuscles {
    static func groups(for name: String) -> String? {
        MovementCatalog.movement(for: name)?.muscles
    }
}
