import Foundation

/// The coach, read from the bundle.
///
/// `COACH-BRIEF.md` beside this file is the one document every model call
/// reads as its standing system prompt — the planner, the reviewer, the
/// chat. It lives inside the app folder so it ships in the bundle and the
/// prompt cannot drift from it; `docs/COACH-BRIEF.md` is a link to it so it
/// stays where the other documents are read.
///
/// Loaded once. A missing file is a build error in spirit, so it is loud:
/// the planner falls through to the offline week and the test suite fails.
enum CoachBrief {
    static let text: String = {
        guard let url = Bundle.main.url(forResource: "COACH-BRIEF", withExtension: "md"),
              let text = try? String(contentsOf: url, encoding: .utf8)
        else { return "" }
        return text
    }()

    static var isLoaded: Bool { !text.isEmpty }
}
