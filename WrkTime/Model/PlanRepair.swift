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

    /// Resizes the rotation of every unfinished session to `count`.
    ///
    /// Changing how many moves a session cycles through used to apply only to
    /// the next week the planner wrote, so she had to spend a Claude request to
    /// see a number she had just set. Nothing about resizing needs a model:
    /// growing takes the next moves from the library that the session does not
    /// already hold and that she has not ruled out, and shrinking drops from
    /// the end. A finished session is left alone, as always.
    @discardableResult
    static func resize(to count: Int, in context: ModelContext,
                       from date: Date = .now) -> Summary {
        let refused = MovePreferences.lists(in: context)
        let barred = Set((refused.avoided + refused.disliked).map { MovePreference.key($0) })

        var summary = Summary()
        let today = Calendar.current.startOfDay(for: date)
        let sessions = ((try? context.fetch(FetchDescriptor<PlannedSession>())) ?? [])
            .filter { !$0.isComplete && $0.scheduledFor >= today }

        for session in sessions {
            guard var routine = session.routine, !routine.moves.isEmpty else { continue }
            guard routine.moves.count != count else { continue }

            if routine.moves.count > count {
                routine.moves = Array(routine.moves.prefix(count))
            } else {
                var used = Set(routine.moves.map { MovePreference.key($0.name) })
                // Prefer the kit the session already leans on, so a "beam" day
                // does not fill up with dumbbells.
                let preferred = Set(routine.moves.map(\.equipment))
                let pool = MoveLibrary.all.filter { $0.kind == .strength }
                    .sorted { preferred.contains($0.equipment) && !preferred.contains($1.equipment) }
                for move in pool where routine.moves.count < count {
                    let key = MovePreference.key(move.name)
                    // Containment for what she has ruled out, exact for what
                    // this rotation already holds. Two different questions:
                    // "push-up" should bar the incline variant, but a rotation
                    // holding "Beam row" has not thereby used "Beam row to
                    // hip". See `MovePreference.anyCovers`.
                    guard !used.contains(key), !MovePreference.anyCovers(barred, move.name)
                    else { continue }
                    used.insert(key)
                    routine.moves.append(move)
                }
            }

            guard routine.moves.count != (session.routine?.moves.count ?? 0) else { continue }
            // `??` rather than a bare `try?`: a failed encode used to leave
            // the session with its title and date and no routine at all, and
            // Today falls straight through that to the rest-day copy.
            session.routineData = (try? JSONEncoder().encode(routine)) ?? session.routineData
            summary.sessionsChanged += 1
            summary.slotsReplaced += abs(routine.moves.count - count)
        }
        return summary
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
            // Containment on the way in as well as on the way out. Detecting by
            // exact name meant ruling out "push-up" left every session that
            // named "Incline push-up" exactly as it was — the app agreeing with
            // her and changing nothing, which is the failure this whole file
            // was written to fix.
            guard routine.moves.contains(where: { MovePreference.anyCovers(unwanted, $0.name) })
            else { continue }

            var used = Set(routine.moves.map { MovePreference.key($0.name) })
            var replaced = 0
            var stuck = 0

            let repaired = routine.moves.map { move -> Move in
                guard MovePreference.anyCovers(unwanted, move.name) else { return move }
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
            session.routineData = (try? JSONEncoder().encode(updated)) ?? session.routineData
            session.title = routine.name
            summary.sessionsChanged += 1
        }
        return summary
    }
}
