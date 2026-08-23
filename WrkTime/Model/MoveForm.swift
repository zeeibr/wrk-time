import Foundation

/// How to do each move, for someone who has never been shown.
///
/// Her words, August 2026: *"im a beginner so i dont know much about form."*
/// The one-line `cue` on a move is what the timer says while she is in the
/// set; this is what she reads before the first one. Five lines, each one
/// sentence, in the app's voice:
///
/// - **set up** — where the feet, the hands and the implement are before
///   anything moves;
/// - **the movement** — what moves, in what order, how fast;
/// - **feel** — where the work should land, so she can tell a good rep from
///   a bad one without a mirror;
/// - **wrong** — the one or two mistakes a beginner actually makes on this
///   move, stated as what to do instead;
/// - **stop if** — the signal that means stop, as distinct from the signal
///   that means it is working. Pain is named by place; effort is never a
///   reason to stop.
///
/// A lookup beside the library, like `MoveMuscles` and `MoveTaxonomy`, so no
/// routine on disk changes shape. Custom moves carry their own notes from
/// the review. Educational, never medical: nothing here diagnoses, and
/// "stop if" points at a doctor only in the sense that any sharp pain does.
struct MoveForm: Equatable {
    var setUp: String
    var movement: String
    var feel: String
    var wrong: String
    var stopIf: String

    static func notes(for name: String) -> MoveForm? {
        guard let (movement, variant) = MovementCatalog.byVariantName[MovePreference.key(name)] else { return nil }
        return variant.form ?? movement.form
    }

    /// The line that is always true: effort is not the stop signal.
    static let effortIsNotPain = "Burning muscle and heavy breathing are the work. Sharp, pinching or joint pain is not — stop, rest, and come back lighter."
}
