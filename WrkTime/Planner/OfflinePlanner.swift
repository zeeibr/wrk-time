import Foundation

/// A week, written without a network, a key, or a model.
///
/// This is not a degraded mode — it is the floor the app stands on. Almanac
/// promises a plan on a phone in a basement gym with no signal and no API key
/// set, so the deterministic planner is required rather than a nicety, and
/// every failure path in `ClaudePlanner` lands here.
///
/// It progresses the way the brief says to: not by adding weight, which the kit
/// cannot do past 15 lb, but by density (rest shortens), volume (rounds climb),
/// and time under tension (work lengthens toward the ceiling).
enum OfflinePlanner {
    /// Where week one starts. Deliberately conservative — the person this is
    /// for is new to this, and a first week she finishes is worth more than a
    /// first week she abandons.
    static let baseWork = 40
    static let baseRest = 45
    static let baseRounds = 8

    static let restFloor = 30
    static let roundCeiling = 12

    /// Names to keep out of the week, lowercased. Empty by default so the
    /// deterministic planner stays a pure function when nobody has an opinion.
    /// A week's work, rest and rounds — the progression itself.
    ///
    /// Lifted out of `week` so `ExtraSession` can compose a second workout in
    /// the same shape as the plan without copying the arithmetic. Two versions
    /// of this would drift the first time the progression changed, and the extra
    /// session would start feeling like a different app.
    struct Shape: Equatable {
        var work: TimeInterval
        var rest: TimeInterval
        var rounds: Int
        /// How many progression steps have been taken, which is what the
        /// explanation reports on.
        var step: Int
    }

    static func shape(week weekNumber: Int, pace: Pace) -> Shape {
        let step = max(weekNumber - 1, 0) / max(pace.progressionWeeks, 1)
        return Shape(
            // Work climbs half as often as the other two, so a session gains
            // duration slowly and its short shape survives the block.
            work: TimeInterval(min(Int(IntervalRoutine.workCeiling), baseWork + 5 * (step / 2))),
            // Five-second steps, matching `ClaudePlanner.restSeconds`.
            //
            // These two grids have to agree: a test asserts every offline week
            // is expressible in the schema, because a fallback week the model
            // could not have written is a fallback that quietly means something
            // different from the plan it replaces. Coarsening the schema to fit
            // the grammar limit moved this too. 45, 40, 35, 30 — same span, and
            // it lands on the floor a week later than before.
            rest: TimeInterval(max(restFloor, baseRest - 5 * step)),
            rounds: min(roundCeiling, baseRounds + pace.roundStep * step),
            step: step)
    }

    static func week(_ weekNumber: Int, pace: Pace,
                     avoiding excluded: Set<String> = [],
                     moves rotation: Int = Tuning.movesPerSession) -> PlanDraft {
        let shape = shape(week: weekNumber, pace: pace)
        let step = shape.step
        let rest = Int(shape.rest)
        let rounds = shape.rounds
        let work = Int(shape.work)

        let days = dayPattern(for: pace)
        let sessions = days.enumerated().map { position, day in
            let template = Template.rotation[position % Template.rotation.count]
            return DraftSession(dayOffset: day,
                                title: template.title,
                                work: work,
                                rest: rest,
                                rounds: rounds,
                                moves: substituting(
                                    template.rotation(of: rotation, avoiding: excluded,
                                                      varying: position),
                                    avoiding: excluded))
        }

        return PlanDraft(explanation: explanation(week: weekNumber, step: step,
                                                  rest: rest, rounds: rounds, pace: pace),
                         sessions: sessions,
                         walkMinutes: walkMinutes(week: weekNumber))
    }

    /// Swaps out anything she has rejected for another move on the same kit.
    ///
    /// If nothing suitable exists the original stays: a session of three moves
    /// with a rotation of two is a worse outcome than one move she would rather
    /// not do, and the skip button still works.
    static func substituting(_ moves: [DraftMove], avoiding excluded: Set<String>) -> [DraftMove] {
        guard !excluded.isEmpty else { return moves }
        var used = Set(moves.map { $0.name.lowercased() })

        return moves.map { draft in
            // One predicate for "ruled out" everywhere — see
            // `MovePreference.anyCovers`. This was one of four spellings of
            // the same question, and the four did not agree.
            guard MovePreference.anyCovers(excluded, draft.name) else { return draft }
            guard let equipment = Equipment(rawValue: draft.equipment),
                  let replacement = MoveLibrary.substitute(
                    for: Move(name: draft.name, equipment: equipment, cue: draft.cue,
                              loadPounds: draft.loadPounds),
                    avoiding: excluded.union(used))
            else { return draft }

            used.insert(replacement.name.lowercased())
            return DraftMove(name: replacement.name,
                             equipment: replacement.equipment.rawValue,
                             cue: replacement.cue,
                             loadPounds: replacement.loadPounds ?? 0)
        }
    }

    /// A walking target that climbs slowly and then holds.
    ///
    /// Offline there is no Health data to build from, so this cannot react to
    /// what she actually walked — it starts at something a beginner will finish
    /// and adds ten minutes a week to a ceiling. Deliberately below
    /// `PlanValidator.walkCeiling`: the deterministic planner should never be
    /// the one pushing a number to its limit.
    static let baseWalkMinutes = 90
    static let walkStep = 10
    static let walkCap = 180

    static func walkMinutes(week: Int) -> Int {
        min(walkCap, baseWalkMinutes + walkStep * max(week - 1, 0))
    }

    /// Rest days spread rather than stacked, which the brief asks for by name.
    static func dayPattern(for pace: Pace) -> [Int] {
        switch pace.sessionsPerWeek {
        case 3: [0, 2, 4]
        case 4: [0, 2, 4, 6]
        case 5: [0, 1, 3, 4, 6]
        default: [0, 2, 4]
        }
    }

    /// The app's voice, not a template with a number dropped in. States the
    /// change and the reason, in one sentence, and says nothing when nothing
    /// changed rather than inventing a milestone.
    static func explanation(week: Int, step: Int, rest: Int, rounds: Int, pace: Pace) -> String {
        guard week > 1 else {
            return "Week one, written from your kit and a \(pace.label.lowercased()) pace. \(rounds) rounds of \(baseWork) seconds with \(rest) between — enough to finish, with room to grow into."
        }
        let progressed = (week - 1) % max(pace.progressionWeeks, 1) == 0 && step > 0
        guard progressed else {
            return "Same shape as last week. Repeating a week is how the movement gets easier before the numbers do."
        }
        if pace.roundStep > 0 {
            return "Rest drops to \(rest) seconds and the week gains a round, at \(rounds). The load has not changed — the density has."
        }
        return "Rest drops to \(rest) seconds. Same rounds, same weight, less recovery between them; that is the progression this kit has."
    }

    // MARK: - Templates

    /// The sessions that rotate through the week: a title and the implement
    /// the session is built around. Every move comes from the one rotation
    /// builder, so the loads and cues are the library's by construction —
    /// these used to carry three hard-coded moves each, and their cue text
    /// had drifted from the library's before anyone noticed.
    ///
    /// Every session is full body, in the coach's shape (`docs/COACH-BRIEF.md`
    /// §9): one bell standing, then the floor to close. What varies by day is
    /// which bell, so the week spends the whole kit without any one session
    /// asking her to fetch more than one thing.
    private struct Template {
        let title: String
        let kit: Set<Equipment>

        /// `turn` is the session's place in the week, and is what tells one
        /// session's hinge from the next one's. The week number is
        /// deliberately *not* in it: repeating a week is how a movement gets
        /// easier before the numbers do, so the same session next week asks
        /// for the same moves and a shorter rest.
        func rotation(of count: Int, avoiding excluded: Set<String> = [],
                      varying turn: Int = 0) -> [DraftMove] {
            // `preferring` is a sort, never a filter: a drawer she has
            // switched off simply stops being preferred, and the builder
            // walks `available`, so a template named for kit she no longer
            // owns still writes a session she can do.
            MoveLibrary.rotation(of: count, preferring: kit,
                                 avoiding: excluded, varying: turn)
                .map { DraftMove(name: $0.name, equipment: $0.equipment.rawValue,
                                 cue: $0.cue, loadPounds: $0.loadPounds ?? 0) }
        }

        static let rotation: [Template] = [
            Template(title: "Full body · kettlebell", kit: [.kettlebell]),
            Template(title: "Full body · beam", kit: [.beam]),
            Template(title: "Full body · single dumbbell", kit: [.singleDumbbell]),
            Template(title: "Full body · rings", kit: [.rings]),
            Template(title: "Full body · dumbbells", kit: [.dumbbells]),
        ]
    }
}
