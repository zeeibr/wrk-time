import Foundation
import SwiftData

/// Makes an opinion reach the plan that already exists.
///
/// Recording a preference used to change only what the planner wrote *next*.
/// So she could say "this hurts, never program it" and then open Today to find
/// the session she was about to do still asking for it — the app having agreed
/// with her and changed nothing. Her words: *"when i say not to include
/// something, any plans with it in it should replace it intelligently."*
///
/// Two rules govern what gets touched, and both are the same ones re-planning
/// already follows:
///
/// **A finished session is never rewritten.** It is a record of something that
/// happened. If she did the move on Monday and ruled it out on Tuesday, Monday
/// still says what she did.
///
/// **A session is repaired, never emptied.** If nothing suitable exists on the
/// same kit, the move stays — a rotation of two where there were three is a
/// worse artefact than one movement she would rather not do, and the skip
/// button still works. The same reasoning as `PlanValidator` rejecting a week
/// whole rather than trimming it.
@MainActor
enum PlanRepair {

    /// What one pass changed, so the caller can say so plainly.
    struct Summary: Equatable {
        var sessionsChanged = 0
        var slotsReplaced = 0
        var slotsLeft = 0

        var isEmpty: Bool { sessionsChanged == 0 && slotsLeft == 0 }

        /// One sentence, in the app's voice. Never implies she has broken
        /// anything by changing her mind.
        var note: String? {
            guard !isEmpty else { return nil }
            var parts: [String] = []
            if sessionsChanged > 0 {
                parts.append(sessionsChanged == 1
                             ? "One session was rewritten"
                             : "\(sessionsChanged) sessions were rewritten")
            }
            if slotsLeft > 0 {
                parts.append(parts.isEmpty
                             ? "Nothing else on that kit was free, so it stays for now"
                             : "one slot had nothing to swap to and stays for now")
            }
            return parts.joined(separator: ", ") + "."
        }
    }

    /// Rewrites every unfinished planned session that uses any of `names`.
    ///
    /// Substitutes from the same equipment, avoiding everything she has ruled
    /// out *and* everything already in that session — so a repair never
    /// produces a rotation with the same movement twice.
    @discardableResult
    static func replace(_ names: [String], in context: ModelContext,
                        from date: Date = .now) -> Summary {
        let unwanted = Set(names.map { MovePreference.key($0) })
        guard !unwanted.isEmpty else { return Summary() }

        let refused = MovePreferences.lists(in: context)
        let barred = unwanted.union((refused.avoided + refused.disliked)
            .map { MovePreference.key($0) })

        var summary = Summary()
        let today = Calendar.current.startOfDay(for: date)
        let sessions = ((try? context.fetch(FetchDescriptor<PlannedSession>())) ?? [])
            .filter { !$0.isComplete && $0.scheduledFor >= today }

        for session in sessions {
            guard let routine = session.routine else { continue }
            guard routine.moves.contains(where: { unwanted.contains(MovePreference.key($0.name)) })
            else { continue }

            var used = Set(routine.moves.map { MovePreference.key($0.name) })
            var replaced = 0
            var stuck = 0

            let repaired = routine.moves.map { move -> Move in
                guard unwanted.contains(MovePreference.key(move.name)) else { return move }
                guard let swap = MoveLibrary.substitute(for: move, avoiding: barred.union(used))
                else { stuck += 1; return move }
                used.remove(MovePreference.key(move.name))
                used.insert(MovePreference.key(swap.name))
                replaced += 1
                return swap
            }

            summary.slotsReplaced += replaced
            summary.slotsLeft += stuck
            guard replaced > 0 else { continue }

            var updated = routine
            updated.moves = repaired
            session.routineData = try? JSONEncoder().encode(updated)
            session.title = routine.name
            summary.sessionsChanged += 1
        }
        return summary
    }
}
