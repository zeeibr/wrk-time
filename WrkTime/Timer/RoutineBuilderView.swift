import SwiftUI
import SwiftData

/// Saved routines, and the way into building one.
struct RoutineListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \SavedRoutine.createdAt, order: .reverse) private var saved: [SavedRoutine]

    @State private var building = false
    /// The saved routine, not just its decoded value — finishing one needs to
    /// write `lastRunAt` back to the record it came from.
    @State private var running: SavedRoutine?
    /// The one being changed. Same reason: an edit writes back to a record.
    @State private var editing: SavedRoutine?

    var body: some View {
        // The tab is one document: her routines first, then the whole library
        // — which used to live three modals deep behind Settings, holding rep
        // history and the step-up nudges it made no sense to bury. The
        // library owns the scroll and the selection bar; this view slots the
        // routines in above and keeps its own sheets and covers.
        MoveLibraryView(embedded: true, topSection: AnyView(routinesSection))
        .sheet(isPresented: $building) {
            RoutineBuilderView { routine in
                context.insert(SavedRoutine(routine: routine))
            }
        }
        .sheet(item: $editing) { item in
            RoutineBuilderView(editing: item.routine) { routine in
                item.update(to: routine)
                try? context.save()
            }
        }
        .fullScreenCover(item: $running) { item in
            if let routine = item.routine {
                // Marked as its own kind, so an interruption picked up from
                // Today cannot be mistaken for the day's planned session.
                WorkoutTimerView(routine: routine, subject: .routine) { outcome in
                    // Only a finished run counts as having run it.
                    guard case .completed = outcome else { return }
                    item.lastRunAt = .now
                    try? context.save()
                }
            }
        }
    }

    private var routinesSection: some View {
                VStack(alignment: .leading, spacing: 16) {
                    // Every document screen opens the same way.
                    Masthead(context: "Moves")
                        .padding(.top, 4)
                    Text("Your own routines")
                        .font(.almanacTitle)
                        .foregroundStyle(Palette.ink)
                        .accessibilityAddTraits(.isHeader)

                    PrimaryButton(title: "Build a routine",
                                  subtitle: "Moves optional · work caps at 60 s") {
                        building = true
                    }

                    if saved.isEmpty {
                        Text("Nothing saved yet. A routine is a name, a work and rest length, and — if you want them — the moves to cycle through. Leave the moves out and you have a plain interval timer.")
                            .font(.almanacBody)
                            .foregroundStyle(Palette.mute)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 4)
                    } else {
                        IndexedSection(number: "01", label: "Saved") {
                            Rule(firm: true)
                            ForEach(saved) { item in
                                if let routine = item.routine {
                                    // A real Button, not a tap gesture on a
                                    // stack: without the button role VoiceOver
                                    // reads this as static text, Switch Control
                                    // will not scan it, and Voice Control has
                                    // no name to match — so the main way into a
                                    // saved workout was unreachable by three
                                    // assistive technologies at once.
                                    Button { running = item } label: {
                                        savedRow(routine, lastRun: item.lastRunAt)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(routine.name)
                                    .accessibilityHint("Starts this routine")
                                    // Tapping runs it, which is what she wants
                                    // nine times in ten. Editing and deleting
                                    // live under a press rather than competing
                                    // for the row — but they exist now, which
                                    // they did not: a routine with one round
                                    // too many could only be replaced, and
                                    // since nothing deleted one either, the
                                    // wrong one stayed forever.
                                    .contextMenu {
                                        Button("Edit") { editing = item }
                                        Button("Delete", role: .destructive) {
                                            context.delete(item)
                                            try? context.save()
                                        }
                                    }
                                    .accessibilityAction(named: "Edit") { editing = item }
                                    .accessibilityAction(named: "Delete") {
                                        context.delete(item)
                                        try? context.save()
                                    }
                                }
                            }
                        }
                    }
                }
    }

    /// "3 moves", or "timer only" — which is a description, not an apology.
    ///
    /// The warm-up counts toward whether a routine is bare. A session that
    /// opens with four flow movements and then runs plain intervals is not a
    /// "timer only", and calling it one would be the app failing to notice the
    /// thing she just added.
    static func rotationNote(_ routine: IntervalRoutine) -> String {
        // A routine of movements and no rounds is a flow in its own right, not
        // a warm-up for something that never comes — that reading was what
        // stopped her building one.
        if routine.rounds == 0, routine.moves.isEmpty, !routine.warmUp.isEmpty {
            return routine.warmUp.count == 1 ? "1 movement" : "\(routine.warmUp.count) movements"
        }
        switch (routine.moves.count, routine.warmUp.count) {
        case (0, 0): return "timer only"
        case (0, let warm): return "\(warm) to warm up, then the timer"
        case (1, _): return "1 move"
        case (let count, _): return "\(count) moves"
        }
    }

    /// "8 × 40/45", or "6 intervals written out".
    ///
    /// Never `routine.rounds` — that field is the fixed shape's round count and
    /// means nothing once a sequence takes over, so a written-out routine used
    /// to advertise a shape it does not have. `roundCount` is true of both.
    static func shapeNote(_ routine: IntervalRoutine) -> String {
        if routine.rounds == 0, routine.moves.isEmpty, !routine.warmUp.isEmpty {
            return "\(Int(routine.warmUpSeconds))s each, held"
        }
        guard !routine.isSequence else {
            let written = "\(routine.sequence.count) intervals written out"
            return routine.sequenceRepeats > 1
                ? written + " × \(routine.sequenceRepeats)" : written
        }
        switch routine.mode {
        case .reps: return "\(routine.setsPerMove) sets each"
        case .emom: return "\(routine.rounds) min on the minute"
        case .intervals:
            return "\(routine.roundCount) × \(Int(routine.clampedWork))/\(Int(routine.rest))"
        }
    }

    private func savedRow(_ routine: IntervalRoutine, lastRun: Date?) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(routine.name).font(.almanacMoveName).foregroundStyle(Palette.ink)
                    Text("\(Self.shapeNote(routine)) · \(Self.rotationNote(routine))")
                        .almanacLabel(Palette.mute, small: true)
                        .tabular()
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 3) {
                    Text(routine.totalDuration.durationString)
                        .font(Face.ui(17)).tabular().foregroundStyle(Palette.ink)
                    if let lastRun {
                        Text("Last run \(lastRun.formatted(.dateTime.weekday(.abbreviated)))")
                            .almanacLabel(Palette.mute, small: true)
                    }
                }
            }
            .padding(.vertical, 11)
            Rule()
        }
        .contentShape(Rectangle())
    }
}

/// Compose an interval routine from the kit you own.
///
/// The two constraints that matter are enforced here rather than explained:
/// work cannot exceed sixty seconds, and the move picker only ever offers your
/// own equipment.
struct RoutineBuilderView: View {
    @Environment(\.dismiss) private var dismiss
    let onSave: (IntervalRoutine) -> Void

    /// What the routine is made of. One or the other, never both at once.
    ///
    /// It used to be inferred from whether `steps` was empty, and the two
    /// definitions sat on screen together as if they combined. They do not:
    /// `RoutineSchedule` ignores work, rest and rounds entirely the moment a
    /// sequence exists. So the builder showed three live steppers that changed
    /// nothing, which is the screen lying about what it does.
    enum Shape: String, CaseIterable, Identifiable {
        case sets, fixed, minute, written, flow
        var id: String { rawValue }

        var title: String {
            switch self {
            case .sets: "Sets, then the next move"
            case .fixed: "Every round the same"
            case .minute: "On the minute"
            case .written: "Write out each interval"
            case .flow: "All flow, no rounds"
            }
        }
        var note: String {
            switch self {
            case .sets: SessionMode.reps.note + " Rest comes from the move."
            case .fixed: "One work length, one rest length, so many rounds. " + SessionMode.intervals.note
            case .minute: SessionMode.emom.note
            case .written: "30 on, 30 rest, 20 on, 15 rest, 10 on, 10 on — each its own length, in the order you write them. Rests are optional."
            case .flow: "A warm-up, or a flow of your own. Movements held one after another with no work intervals and no rests — the field holds still and nothing counts down at you."
            }
        }
    }

    @State private var shape: Shape = .fixed
    @State private var name = ""
    @State private var work: TimeInterval = 60
    @State private var rest: TimeInterval = 45
    @State private var rounds = 8
    @State private var moves: [Move] = []
    @State private var warmUp: [Move] = []
    /// A written-out sequence, used only when `shape` is `.written`.
    @State private var steps: [IntervalStep] = []
    /// How many times the written-out cadence runs. One is a single pass.
    @State private var repeats = 1
    /// Sets per move, for the sets shape.
    @State private var sets = IntervalRoutine.defaultSets
    /// Minutes, for the on-the-minute shape.
    @State private var minutes = 12
    /// How long each movement is held in a flow routine.
    @State private var flowSeconds = Int(WarmUp.seconds)
    @State private var picking = false
    @Environment(\.displayScale) private var displayScale

    /// The routine being changed, when this is an edit rather than a new one.
    private let editing: IntervalRoutine?

    init(editing routine: IntervalRoutine? = nil, onSave: @escaping (IntervalRoutine) -> Void) {
        self.editing = routine
        self.onSave = onSave
        guard let routine else { return }
        _name = State(initialValue: routine.name)
        _work = State(initialValue: routine.work)
        _rest = State(initialValue: routine.rest)
        _rounds = State(initialValue: routine.rounds)
        _moves = State(initialValue: routine.moves)
        _warmUp = State(initialValue: routine.warmUp)
        _steps = State(initialValue: routine.sequence)
        _shape = State(initialValue: routine.isSequence ? .written
                                     : routine.mode == .reps ? .sets
                                     : routine.mode == .emom ? .minute : .fixed)
        _sets = State(initialValue: routine.setsPerMove)
        if routine.mode == .emom { _minutes = State(initialValue: routine.rounds) }
        _repeats = State(initialValue: routine.sequenceRepeats)
        _flowSeconds = State(initialValue: Int(routine.warmUpSeconds))
        // A routine with movements and no rounds is a flow, which is exactly
        // what the morning practice is. Recognised rather than stored as a
        // third flag.
        if routine.rounds == 0, routine.moves.isEmpty, !routine.warmUp.isEmpty {
            _shape = State(initialValue: .flow)
        }
    }

    /// Keeps the routine's identity across an edit, so running it still writes
    /// back to the record it came from.
    private var draft: IntervalRoutine {
        guard shape != .flow else { return flowDraft }
        var routine = IntervalRoutine(id: editing?.id ?? UUID(),
                                      name: name.isEmpty ? defaultName : name,
                                      work: work, rest: rest,
                                      rounds: shape == .minute ? minutes : rounds,
                                      moves: moves)
            .warmingUp(with: warmUp)
        switch shape {
        case .sets: routine = routine.inMode(.reps, sets: sets)
        case .minute: routine = routine.inMode(.emom)
        default: break
        }
        // Steps are kept in state while she is on the fixed shape, so switching
        // back and forth does not throw away what she wrote — but only the
        // chosen shape reaches the routine.
        routine = routine.following(shape == .written ? steps : [], repeats: repeats)
        return routine
    }

    /// A flow of her own: movements held in order, no work, no rest, no rounds.
    ///
    /// Her question: *"what if im trying to make a warm up routine?"* Picking a
    /// flow movement in the other two shapes sends it to the warm-up, which is
    /// right there — a spinal wave inside a work interval would be counted down
    /// at like a set, which is what `MoveKind` exists to prevent. But when the
    /// whole routine *is* flow it is not warming up for anything; it is the
    /// routine.
    ///
    /// `RoutineSchedule` already allows a routine of zero rounds — that is how
    /// the morning practice exists — so this needs no new machinery, only a way
    /// to ask for it.
    private var flowDraft: IntervalRoutine {
        IntervalRoutine(id: editing?.id ?? UUID(),
                        name: name.isEmpty ? defaultName : name,
                        work: 0, rest: 0, rounds: 0, moves: [])
            .warmingUp(with: warmUp, seconds: TimeInterval(flowSeconds))
    }

    /// A routine she does not name is named for what it is — "Rings · 8 ×
    /// 40/45", "Flow · 6 movements" — never "Untitled". An almanac names real
    /// things, and "Untitled routine" twice over in a list tells her nothing.
    private var defaultName: String {
        if shape == .flow {
            return warmUp.count == 1 ? "Flow · 1 movement" : "Flow · \(warmUp.count) movements"
        }
        let shapeText: String
        switch shape {
        case .sets: shapeText = "\(sets) sets × \(moves.count)"
        case .minute: shapeText = "EMOM \(minutes)"
        case .fixed: shapeText = "\(rounds) × \(Int(work))/\(Int(rest))"
        default: shapeText = "\(steps.count) \(steps.count == 1 ? "interval" : "intervals")"
        }
        guard let kit = moves.first?.equipment else { return "Timer · \(shapeText)" }
        let single = moves.allSatisfy { $0.equipment == kit }
        return "\(single ? kit.shortLabel : "Mixed") · \(shapeText)"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    IndexedSection(number: "01", label: "Setup") {
                        TextField("Name it", text: $name)
                            .font(Face.slab(23))
                            .foregroundStyle(Palette.ink)
                            .textFieldStyle(.plain)
                            .padding(.bottom, 8)
                            // The placeholder vanishes on the first keystroke,
                            // taking the field's only name with it.
                            .accessibilityLabel("Routine name")
                        Rule(firm: true)

                        ForEach(Shape.allCases) { option in
                            CheckRow(title: option.title, note: option.note,
                                     selected: shape == option) { shape = option }
                        }
                        .padding(.top, 4)
                    }

                    IndexedSection(number: "02", label: sectionTwoLabel) {
                        if shape == .flow {
                            SectionHead(title: "How long each",
                                        note: warmUp.isEmpty
                                            ? "add movements below"
                                            : draft.totalDuration.durationString)
                                .padding(.bottom, 4)
                            Text("Every movement is held for the same length, one after another. Add them in section 03 in the order you want them.")
                                .font(.almanacBodySmall)
                                .foregroundStyle(Palette.mute)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.vertical, 10)
                            stepper(title: "Each movement", value: flowSeconds, unit: "sec",
                                    note: "5 s steps",
                                    decrement: { flowSeconds = max(15, flowSeconds - 5) },
                                    increment: { flowSeconds = min(120, flowSeconds + 5) })
                            Rule().padding(.top, 12)
                        } else if shape == .sets {
                            SectionHead(title: "The sets",
                                        note: moves.isEmpty ? "add moves below"
                                            : draft.totalDuration.durationString)
                                .padding(.bottom, 4)
                            Text("Every set of a move, then the next. A set is open until you end it. Rest is the move's own — about 75 seconds after a big lift, 60 after an upper-body lift, 45 for the rest — and the timer adds time to fetch the next thing.")
                                .font(.almanacBodySmall)
                                .foregroundStyle(Palette.mute)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.vertical, 10)
                            stepper(title: "Sets per move", value: sets, unit: nil, note: "2 – 5",
                                    decrement: { sets = max(2, sets - 1) },
                                    increment: { sets = min(5, sets + 1) })
                            Rule().padding(.top, 12)
                        } else if shape == .minute {
                            SectionHead(title: "The minutes",
                                        note: moves.isEmpty ? "add moves below"
                                            : draft.totalDuration.durationString)
                                .padding(.bottom, 4)
                            Text("One move at the top of each minute, the rotation in turn. Twenty-five seconds to work, the rest of the minute to rest.")
                                .font(.almanacBodySmall)
                                .foregroundStyle(Palette.mute)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.vertical, 10)
                            stepper(title: "Minutes", value: minutes, unit: nil, note: "6 – 20",
                                    decrement: { minutes = max(6, minutes - 1) },
                                    increment: { minutes = min(20, minutes + 1) })
                            Rule().padding(.top, 12)
                        } else if shape == .fixed {
                            HStack(spacing: 0) {
                                stepper(title: "Work", value: Int(work), unit: "sec",
                                        note: work >= IntervalRoutine.workCeiling ? "At cap" : nil,
                                        decrement: { work = max(10, work - 5) },
                                        increment: { work = min(IntervalRoutine.workCeiling, work + 5) })
                                divider
                                stepper(title: "Rest", value: Int(rest), unit: "sec", note: "Step 5 s",
                                        decrement: { rest = max(0, rest - 5) },
                                        increment: { rest = min(180, rest + 5) })
                                divider
                                stepper(title: "Rounds", value: rounds, unit: nil, note: "1 – 20",
                                        decrement: { rounds = max(1, rounds - 1) },
                                        increment: { rounds = min(20, rounds + 1) })
                            }
                            .padding(.vertical, 12)
                            Rule()
                        } else {
                            SectionHead(title: "The intervals",
                                        note: steps.isEmpty ? "none yet"
                                            : "\(draft.roundCount) work · \(draft.totalDuration.durationString)")
                                .padding(.bottom, 4)

                            if steps.isEmpty {
                                Text("Nothing written yet. Add work and rest in the order you want them — three work intervals in a row is a thing you can ask for, and nothing here assumes they alternate.")
                                    .font(.almanacBodySmall)
                                    .foregroundStyle(Palette.mute)
                                    .padding(.vertical, 10)
                                    .fixedSize(horizontal: false, vertical: true)
                            } else {
                                ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                                    stepRow(index: index, step: step)
                                }
                                Rule()
                            }

                            HStack(spacing: 8) {
                                addStep("Add work", isWork: true)
                                addStep("Add rest", isWork: false)
                            }
                            .padding(.top, 12)

                            // Write the cadence once and say how many times.
                            // Her ask, and the arithmetic is obvious: six steps
                            // wanted four times over was twenty-four steppers.
                            if !steps.isEmpty {
                                Rule().padding(.top, 14)
                                stepper(title: "Repeat the cadence",
                                        value: repeats, unit: "×",
                                        note: repeats == 1
                                            ? "Once through"
                                            : "\(draft.roundCount) work intervals in all",
                                        decrement: { repeats = max(1, repeats - 1) },
                                        increment: { repeats = min(20, repeats + 1) })
                                    .padding(.top, 12)
                            }
                        }
                    }

                    IndexedSection(number: "03", label: "Moves") {
                        if !warmUp.isEmpty {
                            // Read from the draft, never from `WarmUp.seconds`.
                            // Both of these printed the 40-second constant, so
                            // setting the flow to 60 left every row still
                            // reading 40s — the routine was saved correctly and
                            // the screen contradicted it, which is worse than
                            // being wrong in one place.
                            //
                            // The heading was wrong too: in a flow routine these
                            // movements are not warming up for anything.
                            SectionHead(title: shape == .flow ? "The movements" : "Warm-up",
                                        note: "\(Int(draft.warmUpSeconds))s each")
                                .padding(.bottom, 4)
                            ForEach(Array(warmUp.enumerated()), id: \.element.id) { index, move in
                                BlockRow(index: index + 1, symbol: move.symbol,
                                         name: move.name, equipment: move.equipmentLabel,
                                         measure: "\(Int(draft.warmUpSeconds))s")
                                    .removable { warmUp.remove(at: index) }
                            }
                            Rule()
                            Spacer(minLength: 14)
                        }

                        // Says what is true. Reordering is not built, and a note
                        // promising a gesture that does not exist is worse than
                        // no note at all.
                        // Section 03 describes the rotation, and a flow has no
                        // rotation — the movements it collects are the routine.
                        // Left unchanged it read "In rotation · optional" over
                        // copy about work intervals taking moves in turn, none
                        // of which is true in this mode. The same class of
                        // untruth as printing the 40-second constant.
                        SectionHead(title: shape == .flow || shape == .sets ? "In order" : "In rotation",
                                    note: flowHeadNote)
                            .padding(.bottom, 4)

                        if moves.isEmpty {
                            // An empty rotation is a real answer, not a form
                            // left half-filled, and the copy has to say so —
                            // otherwise the one person who wants a bare timer
                            // reads this screen as refusing to give her one.
                            Text(rotationExplainer)
                                .font(.almanacBodySmall)
                                .foregroundStyle(Palette.mute)
                                .padding(.vertical, 10)
                                .fixedSize(horizontal: false, vertical: true)
                        } else {
                            ForEach(Array(moves.enumerated()), id: \.element.id) { index, move in
                                BlockRow(index: index + 1, symbol: move.symbol,
                                         name: move.name, equipment: move.equipmentLabel,
                                         // A written-out sequence has no single
                                         // work length, so printing one here
                                         // would name a duration this move may
                                         // never run for.
                                         measure: measure(forMoveAt: index))
                                    .removable { moves.remove(at: index) }
                            }
                            Rule()
                            if shape == .written, !steps.isEmpty {
                                Text(rotationExplanation)
                                    .font(.almanacBodySmall)
                                    .foregroundStyle(Palette.mute)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .padding(.top, 10)
                            }
                        }

                        Button {
                            picking = true
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "plus")
                                Text("Add a move").font(.almanacBody)
                                Spacer()
                                Text("From your kit").almanacLabel(Palette.mute, small: true)
                            }
                            .foregroundStyle(Palette.moss)
                            .padding(.vertical, 12)
                        }
                        .buttonStyle(.plain)
                    }

                    IndexedSection(number: "04", label: "Total") {
                        Rule(firm: true)
                        HStack(alignment: .lastTextBaseline) {
                            // An em dash rather than a number, because an empty
                            // sequence has no length. `following([])` clears the
                            // steps and the routine falls back to the fixed
                            // shape, so `draft` would confidently report the
                            // 13:15 of a shape she has just chosen not to use.
                            Text(isUnwritten ? "—" : draft.totalDuration.durationString)
                                .font(Face.ui(30, weight: .light))
                                .tabular()
                                .foregroundStyle(isUnwritten ? Palette.mute : Palette.ink)
                            Spacer()
                            Text(totalNote)
                                .almanacLabel(Palette.mute, small: true)
                                .multilineTextAlignment(.trailing)
                        }
                        .padding(.vertical, 10)

                        // No longer disabled on an empty rotation. A routine
                        // with no moves is a timer, which is a thing she asked
                        // to be able to save.
                        PrimaryButton(title: editing == nil ? "Save routine" : "Save changes",
                                      subtitle: RoutineListView.rotationNote(draft)) {
                            onSave(draft)
                            dismiss()
                        }
                        .disabled(isUnwritten)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 30)
            }
            .background(Palette.oat.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundStyle(Palette.mute)
                }
            }
        }
        // Where a picked move lands is decided by what it *is*. Adding the
        // spinal wave to the rotation would put a practice inside a
        // forty-second work interval and count it down — the one thing
        // `MoveKind` exists to prevent — so flow goes to the warm-up.
        .sheet(isPresented: $picking) {
            MovePicker { move in
                // In a flow routine everything picked is a held movement — a
                // strength move with no rounds is a hold, which is a legitimate
                // thing to want in a warm-up. In the other two shapes the old
                // rule stands: flow opens the session, strength joins the
                // rotation, because a spinal wave inside a work interval would
                // be counted down at like a set.
                if shape == .flow || move.kind == .flow {
                    warmUp.append(move)
                } else {
                    moves.append(move)
                }
            }
        }
    }

    /// What section 03 counts, which is a different thing in each shape.
    private var flowHeadNote: String {
        if shape == .flow {
            return warmUp.isEmpty ? "required" : "\(warmUp.count) movements"
        }
        if shape == .sets || shape == .minute {
            return moves.isEmpty ? "required" : "\(moves.count) in order"
        }
        return moves.isEmpty ? "optional" : "\(moves.count) in cycle"
    }

    private var rotationExplainer: String {
        switch shape {
        case .sets:
            "Add the moves in the order you want them — standing first, then the mat, so you go down once. Each gets all its sets before the next begins."
        case .minute:
            "Add moves and each minute takes the next one in the list, back to the top when it runs out."
        case .fixed:
            "Leave this empty for a plain interval timer — just work, rest and rounds. Add moves and each round takes the next one in the list."
        case .written:
            "Leave this empty for a plain interval timer. Add moves and the work intervals you wrote take them in turn — first move, second move, back to the first."
        case .flow:
            "Add the movements in the order you want them. Each is held for the length above, one after another — a flow needs at least one."
        }
    }

    private var sectionTwoLabel: String {
        switch shape {
        case .sets: "Sets"
        case .minute: "Minutes"
        case .fixed: "Shape"
        case .written: "Sequence"
        case .flow: "Flow"
        }
    }

    /// Chosen to write it out, and not written it yet.
    private var isUnwritten: Bool {
        (shape == .written && steps.isEmpty) || (shape == .flow && warmUp.isEmpty)
            || (shape == .sets && moves.isEmpty) || (shape == .minute && moves.isEmpty)
    }

    private var totalNote: String {
        guard !isUnwritten else {
            switch shape {
            case .flow: return "Add a movement to give this a length"
            case .sets, .minute: return "Add a move to give this a length"
            default: return "Add an interval to give this a length"
            }
        }
        if shape == .flow {
            return "\(warmUp.count) \(warmUp.count == 1 ? "movement" : "movements") · \(flowSeconds)s each"
        }
        // `draft.roundCount`, never the `rounds` stepper: a sided move doubles
        // its turns, and this line must agree with the saved list and the
        // timer about how many work intervals that is.
        let body: String
        switch shape {
        case .sets:
            body = moves.isEmpty ? "Add a move to give this a length"
                 : "\(draft.roundCount) \(draft.roundCount == 1 ? "set" : "sets") over \(moves.count) \(moves.count == 1 ? "move" : "moves")"
        case .minute:
            body = "\(minutes) minutes on the minute"
        case .fixed:
            body = "\(draft.roundCount) × \(Int(work))/\(Int(rest)) · final rest dropped"
        default:
            body = "\(draft.roundCount) work \(draft.roundCount == 1 ? "interval" : "intervals")"
                + " in \(steps.count) \(steps.count == 1 ? "step" : "steps")"
                + (repeats > 1 ? " × \(repeats)" : "")
        }
        guard !warmUp.isEmpty else { return body }
        return "\(warmUp.count) to warm up, then \(body)"
    }

    /// What a move in the rotation actually runs for.
    ///
    /// On the fixed shape every work interval is the same length, so the row
    /// can name it. In a written-out sequence it cannot: the same move may run
    /// for thirty seconds once and ten the next time round, and printing one
    /// number would be picking a favourite. So the row names the intervals it
    /// lands on instead.
    private func measure(forMoveAt index: Int) -> String {
        // The doubling has to be visible before the timer runs, or the number
        // silently changes meaning between this screen and the session.
        let sided = moves.indices.contains(index)
            ? moves[index].sided.map { $0 == .directions ? " · both ways" : " · each side" }
            : nil
        if shape == .sets { return "\(sets) sets × 8–12" + (sided ?? "") }
        if shape == .minute { return "\(Int(IntervalRoutine.emomWorkSeconds))s a minute" + (sided ?? "") }
        guard shape == .written, !steps.isEmpty else {
            return "\(Int(work))s" + (sided ?? "")
        }
        // Assignment follows the sided cycle exactly as `RoutineSchedule`
        // does — a sided move claims two written steps, so a plain modulo over
        // `moves` would label the rows with the wrong intervals.
        let cycle = RoutineSchedule.sidedCycle(of: moves)
        guard !cycle.isEmpty, moves.indices.contains(index) else { return "\(Int(work))s" }
        let lengths = steps.filter(\.isWork).enumerated()
            .filter { cycle[$0.offset % cycle.count].move.id == moves[index].id }
            .map { Int($0.element.clamped) }
        guard !lengths.isEmpty else { return "unused" }
        return Set(lengths).count == 1
            ? "\(lengths[0])s ×\(lengths.count)"
            : lengths.map { "\($0)" }.joined(separator: "/") + "s"
    }

    /// Spelled out rather than left to be inferred, because the cycling is
    /// invisible until it surprises you: five work intervals and two moves is
    /// the first move three times and the second twice.
    private var rotationExplanation: String {
        let work = draft.roundCount
        guard moves.count > 0, work > 0 else { return "" }
        if moves.count >= work {
            return "\(work) work \(work == 1 ? "interval" : "intervals"), taken in order from the top."
        }
        return "\(work) work intervals over \(moves.count) moves — the list repeats from the top when it runs out."
    }

    /// One step of a written-out sequence.
    private func stepRow(index: Int, step: IntervalStep) -> some View {
        VStack(spacing: 0) {
            Rule()
            HStack(spacing: 9) {
                Text(String(format: "%02d", index + 1))
                    .almanacLabel(Palette.mute, small: true)
                    .tabular()
                Text(step.isWork ? "Work" : "Rest")
                    .font(.almanacBody)
                    .foregroundStyle(step.isWork ? Palette.ink : Palette.mute)
                    .frame(width: 46, alignment: .leading)
                Spacer(minLength: 8)
                Figure(value: "\(Int(step.clamped))", unit: "sec", size: 19)
                HStack(spacing: 20) {
                    stepperButton("minus") { adjust(index, by: -5) }
                    stepperButton("plus") { adjust(index, by: 5) }
                }
                .padding(.leading, 6)
            }
            .padding(.vertical, 7)
        }
        .removable { steps.remove(at: index) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(index + 1), \(step.isWork ? "work" : "rest")")
        .accessibilityValue("\(Int(step.clamped)) seconds")
        .accessibilityAdjustableAction { direction in
            adjust(index, by: direction == .increment ? 5 : -5)
        }
    }

    private func adjust(_ index: Int, by delta: TimeInterval) {
        guard steps.indices.contains(index) else { return }
        let ceiling = steps[index].isWork ? IntervalRoutine.workCeiling : 300
        steps[index].seconds = min(max(steps[index].seconds + delta, 5), ceiling)
    }

    private func addStep(_ title: String, isWork: Bool) -> some View {
        Button {
            // Picks up where the last one of its kind left off, so writing
            // "30 on, 30 rest, 20 on" is three taps and two adjustments rather
            // than starting from the same number every time.
            let last = steps.last { $0.isWork == isWork }?.seconds
            steps.append(isWork ? .work(last ?? work) : .rest(last ?? rest))
        } label: {
            HStack(spacing: 20) {
                Image(systemName: "plus").font(.system(size: 11, weight: .semibold))
                Text(title).font(.almanacBodySmall)
            }
            .foregroundStyle(isWork ? Palette.ink : Palette.moss)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .overlay(Rectangle().strokeBorder(Palette.ruleFirm, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func stepper(title: String, value: Int, unit: String?, note: String?,
                         decrement: @escaping () -> Void,
                         increment: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).almanacLabel(small: true)
            Figure(value: "\(value)", unit: unit, size: 24)
            HStack(spacing: 20) {
                stepperButton("minus", action: decrement)
                stepperButton("plus", action: increment)
            }
            if let note {
                Text(note).almanacLabel(Palette.mute, small: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // One adjustable control, not two anonymous buttons. Left as-is,
        // VoiceOver reads "minus, plus" six times across this row with no way
        // to tell which field it is adjusting, and Voice Control gets six
        // identical matches.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(unit.map { "\(value) \($0)" } ?? "\(value)")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: increment()
            case .decrement: decrement()
            @unknown default: break
            }
        }
    }

    private func stepperButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Palette.moss)
                .frame(width: 24, height: 24)
                .overlay(Circle().strokeBorder(Palette.ruleFirm, lineWidth: 1))
                // The drawn circle stays 24pt — the design wants a small mark —
                // while the tappable area becomes the 44pt Apple asks for.
                // Insetting outward grows the hit region without touching
                // layout, so the two circles keep their 6pt gap instead of
                // being shoved apart by a larger frame.
                .contentShape(Rectangle().inset(by: -10))
        }
        .buttonStyle(.plain)
    }

    private var divider: some View {
        Rectangle().fill(Palette.rule).frame(width: 1 / displayScale, height: 62)
    }
}

private extension View {
    /// Long-press to take a row back out.
    ///
    /// The builder had no way to remove a move at all — the only fix for a
    /// mistyped rotation was to cancel and start the routine again. A context
    /// menu rather than a swipe because these rows live in a `VStack`, not a
    /// `List`, and it is the same gesture Today already uses on a move.
    func removable(_ remove: @escaping () -> Void) -> some View {
        contextMenu { Button("Remove", role: .destructive, action: remove) }
            // The context menu alone is invisible to VoiceOver, Switch Control
            // and Voice Control, and removing a row is the only fix for a
            // mistyped rotation. `RoutineListView` already pairs the two.
            .accessibilityAction(named: "Remove", remove)
    }
}

/// Only ever your own equipment.
struct MovePicker: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    let onPick: (Move) -> Void

    /// The working flow pool — built-ins plus her approved flow additions, the
    /// same set the practice and the warm-ups draw from.
    private var flowPool: [Move] { MoveLibrary.flow + CustomMoves.flow(in: context) }
    /// Her approved strength additions, offered under their own heading since
    /// they belong to no built-in equipment group's fixed list.
    private var customStrength: [Move] {
        CustomMoves.strength(in: context).map { $0.applyingLoad(from: loads) }
    }
    /// Her loads, so a picked move goes into the routine at the weight she
    /// actually uses.
    private var loads: [String: Double] { MoveOverrides.table(in: context) }

    /// The owned strength library in running order, one section per
    /// pattern, the mat's patterns after the standing ones.
    private var patternGroups: [(title: String, moves: [Move])] {
        let strength = MoveLibrary.ordered(
            MoveLibrary.available.filter { $0.kind == .strength }.map { $0.applyingLoad(from: loads) })
        var out: [(title: String, moves: [Move])] = []
        for move in strength {
            let position = MoveTaxonomy.position(for: move.name) ?? .standing
            let pattern = MoveTaxonomy.pattern(for: move.name)?.label ?? "Other"
            let title = switch position {
            case .standing: pattern
            case .kneeling: "Kneeling · \(pattern)"
            case .floor: "On the mat · \(pattern)"
            }
            if let index = out.firstIndex(where: { $0.title == title }) {
                out[index].moves.append(move)
            } else {
                out.append((title, [move]))
            }
        }
        return out
    }

    var body: some View {
        NavigationStack {
            List {
                // The morning practice first: it is what she reaches for most
                // often, and burying it under five equipment headings would
                // make the thing she does daily the hardest thing to find.
                if !flowPool.isEmpty {
                    SwiftUI.Section {
                        ForEach(flowPool) { move in
                            Button {
                                onPick(move)
                                dismiss()
                            } label: { row(move) }
                            .buttonStyle(.plain)
                            .listRowBackground(Palette.oat)
                            .listRowSeparatorTint(Palette.rule)
                        }
                    } header: {
                        Text("Flow · qi gong and lymphatic").almanacLabel(small: true)
                    } footer: {
                        Text("These open the session rather than joining the rotation — they are a practice, not a set.")
                            .font(.almanacBodySmall)
                            .foregroundStyle(Palette.mute)
                    }
                }

                // The strength library the way the Moves tab lists it now:
                // by pattern, standing before the mat, the implement a fact
                // on the row. Picking "a hinge" is the question a routine
                // asks; which drawer it came from is not.
                ForEach(patternGroups, id: \.title) { group in
                    SwiftUI.Section {
                        ForEach(group.moves) { move in
                            Button {
                                onPick(move)
                                dismiss()
                            } label: { row(move) }
                            .buttonStyle(.plain)
                            .listRowBackground(Palette.oat)
                            .listRowSeparatorTint(Palette.rule)
                        }
                    } header: {
                        Text(group.title).almanacLabel(small: true)
                    }
                }

                if !customStrength.isEmpty {
                    SwiftUI.Section {
                        ForEach(customStrength) { move in
                            Button {
                                onPick(move)
                                dismiss()
                            } label: { row(move) }
                            .buttonStyle(.plain)
                            .listRowBackground(Palette.oat)
                            .listRowSeparatorTint(Palette.rule)
                        }
                    } header: {
                        Text("Your additions").almanacLabel(small: true)
                    }
                }
            }
            .listStyle(.plain)
            // Without this the rows keep `systemBackground` — white in light
            // mode, black in dark — so the picker was the one screen not in
            // the document register, and in dark mode ink names sat on black.
            .scrollContentBackground(.hidden)
            .background(Palette.oat.ignoresSafeArea())
            .navigationTitle("Your kit")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    /// Name, cue, and the plate. The diagram is the point of the row here: a
    /// list of thirty-eight names is a vocabulary test, and she asked to be
    /// able to see the shape before choosing it.
    private func row(_ move: Move) -> some View {
        HStack(spacing: 12) {
            // A constant 66x66 cell whatever the facing. A front-facing
            // signature panel is square and a side one is half as wide; letting
            // the cell follow would give the list a ragged left edge on the
            // name column, in a document register built on things lining up.
            MoveStrip(move: move, style: .signature)
                .frame(width: 66, height: 66)
            VStack(alignment: .leading, spacing: 2) {
                Text(move.name).font(.almanacBody).foregroundStyle(Palette.ink)
                // The implement was the section heading; now the sections
                // are patterns, so the row says what to pick up.
                if move.kind == .strength {
                    Text(move.equipmentLabel).almanacLabel(Palette.mute, small: true)
                }
                Text(move.cue).font(.almanacBodySmall).foregroundStyle(Palette.mute)
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }
}
