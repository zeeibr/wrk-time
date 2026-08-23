import Foundation

/// One movement on another implement borrows the movement's facts.
///
/// The library is still one row per (movement, implement) — the planner's
/// enum, the drawings and the stored routines all key on that name — but
/// the pattern, the muscles and the five form lines belong to the
/// *movement*, and typing them again for each implement is how the library
/// came to hold the same row five times over. This is the first step of the
/// August 2026 redesign (`docs/HANDOFF.md`): a variant names the entry it
/// shares, and the three lookups resolve through it. The forms are written
/// for the pair; where the single's grip differs, the cue says so.
enum MoveAliases {
    static func resolve(_ name: String) -> String {
        let key = MovePreference.key(name)
        return table[key] ?? key
    }

    private static let table: [String: String] = [
        "single-dumbbell row": "dumbbell row",
        "single-dumbbell goblet squat": "kettlebell goblet squat",
        "single-dumbbell floor press": "dumbbell floor press",
        "single-dumbbell overhead press": "dumbbell press",
        "single-dumbbell curl": "bicep curl",
    ]
}
