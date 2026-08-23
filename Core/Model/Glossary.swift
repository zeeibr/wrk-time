import Foundation

/// The app's words next to the gym's, for when she walks into one.
///
/// Her ask, 22 August 2026: she wants to go to an actual gym at the end of
/// the twelve weeks, so what the app calls things should be what a coach
/// on the floor calls them — or, where the app's own word is better for a
/// phone on the floor, the gym's word should be one tap away. Each entry is
/// the app's term, the term she will hear, and one plain line.
enum Glossary {
    struct Term: Identifiable {
        var id: String { app }
        let app: String
        let gym: String
        let line: String
    }

    static let terms: [Term] = [
        Term(app: "Move", gym: "Exercise, lift",
             line: "One movement — a deadlift, a row. At a gym it is an exercise; a loaded one is a lift."),
        Term(app: "Rotation", gym: "Circuit",
             line: "The moves a session cycles through. Working through them in turn with little rest is a circuit."),
        Term(app: "Sets", gym: "Straight sets",
             line: "All the sets of one exercise before moving to the next. The default way a gym programme is written."),
        Term(app: "Set", gym: "Set",
             line: "One stretch of reps without stopping. \"Three sets of ten\" is 3 × 10."),
        Term(app: "Rep", gym: "Rep, repetition",
             line: "One complete movement — down and up. Counted, never guessed."),
        Term(app: "Two short of failure", gym: "RIR 2, RPE 8",
             line: "Reps in reserve: how many more you could have done with good form. Two in reserve is RIR 2, or about an 8 out of 10 effort (RPE)."),
        Term(app: "Load", gym: "Weight, load",
             line: "What is in your hands. Going up a weight is progressing the load."),
        Term(app: "Step up", gym: "Progressive overload, double progression",
             line: "Building reps at a weight, then taking the next weight and dropping back to the bottom of the range. The rule every programme runs on."),
        Term(app: "Intervals", gym: "AMRAP, HIIT, EMOM",
             line: "Timed work against timed rest. \"As many reps as possible\" in the time is an AMRAP; hard timed rounds are HIIT."),
        Term(app: "On the minute", gym: "EMOM",
             line: "Every minute on the minute: one set at the top of each minute, rest until the next."),
        Term(app: "Round", gym: "Round",
             line: "One pass through the rotation in an interval session."),
        Term(app: "Rest", gym: "Rest, rest interval",
             line: "Time between sets. Big lifts get more; a coach will say \"rest ninety\"."),
        Term(app: "Setup", gym: "Transition",
             line: "Time to fetch and set up the next thing. Not rest — gyms call it a transition."),
        Term(app: "Hinge", gym: "Hip hinge, deadlift pattern",
             line: "Hips back, flat back, stand up. Deadlifts, good mornings, kettlebell swings."),
        Term(app: "Squat", gym: "Squat pattern",
             line: "Sit down between the hips and stand. Goblet squats, front squats, air squats."),
        Term(app: "Lunge", gym: "Single-leg, unilateral",
             line: "One leg does most of the work: lunges, split squats, step-ups."),
        Term(app: "Row", gym: "Horizontal pull",
             line: "Pulling toward the body: rows, face pulls."),
        Term(app: "Pull", gym: "Vertical pull",
             line: "Pulling from overhead: pull-downs, pull-ups, wall angels on a wall."),
        Term(app: "Push", gym: "Horizontal push",
             line: "Pushing away from the chest: push-ups, floor press, bench press."),
        Term(app: "Press", gym: "Vertical push, overhead press",
             line: "Pushing overhead: shoulder press, Arnold press."),
        Term(app: "Carry", gym: "Loaded carry",
             line: "Holding a weight and walking or standing still: farmer's carry, suitcase carry, rack hold."),
        Term(app: "Core · brace", gym: "Anti-rotation, anti-extension",
             line: "Holding the trunk still against something trying to move it: planks, dead bugs, Pallof presses."),
        Term(app: "Accessory", gym: "Accessory, isolation, single-joint",
             line: "Small-muscle work after the big lifts: curls, raises, extensions. A gym's \"isolation\" means one joint moving."),
        Term(app: "Kneeling", gym: "Tall-kneeling, half-kneeling",
             line: "Legs taken out of it so the trunk has to hold you up. Both knees down is tall-kneeling; one is half-kneeling."),
        Term(app: "Sided", gym: "Unilateral, each side",
             line: "One side at a time. A coach will say \"ten each side\"."),
        Term(app: "Tempo 3-1-1", gym: "Tempo",
             line: "Seconds for each part of a rep: three down, one pause, one up. Written as 3-1-1 or 3110."),
        Term(app: "Practice, flow", gym: "Mobility, warm-up",
             line: "Qi gong and mobility movements. A gym calls the morning practice mobility and the pre-session flow a warm-up."),
        Term(app: "Baseline", gym: "Assessment, testing",
             line: "Measuring where you are to set working loads. Gyms do it in an onboarding session."),
        Term(app: "Mark", gym: "Session, workout",
             line: "A finished planned session. A gym would just call it a workout."),
    ]
}
