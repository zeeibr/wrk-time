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

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Every document screen opens the same way.
                    Masthead(context: "Your own")
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
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 28)
            }
            .background(Palette.oat.ignoresSafeArea())
        }
        .sheet(isPresented: $building) {
            RoutineBuilderView { routine in
                context.insert(SavedRoutine(routine: routine))
            }
        }
        .fullScreenCover(item: $running) { item in
            if let routine = item.routine {
                WorkoutTimerView(routine: routine) { outcome in
                    // Only a finished run counts as having run it.
                    guard case .completed = outcome else { return }
                    item.lastRunAt = .now
                    try? context.save()
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
        switch (routine.moves.count, routine.warmUp.count) {
        case (0, 0): "timer only"
        case (0, let warm): "\(warm) to warm up, then the timer"
        case (1, _): "1 move"
        case (let count, _): "\(count) moves"
        }
    }

    private func savedRow(_ routine: IntervalRoutine, lastRun: Date?) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(routine.name).font(.almanacMoveName).foregroundStyle(Palette.ink)
                    Text("\(routine.rounds) × \(Int(routine.clampedWork))/\(Int(routine.rest)) · \(Self.rotationNote(routine))")
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

    @State private var name = ""
    @State private var work: TimeInterval = 60
    @State private var rest: TimeInterval = 45
    @State private var rounds = 8
    @State private var moves: [Move] = []
    @State private var warmUp: [Move] = []
    /// A written-out sequence. Empty means the routine is the fixed shape
    /// above; one step or more and the sequence takes over entirely.
    @State private var steps: [IntervalStep] = []
    @State private var picking = false
    @Environment(\.displayScale) private var displayScale

    private var draft: IntervalRoutine {
        IntervalRoutine(name: name.isEmpty ? "Untitled routine" : name,
                        work: work, rest: rest, rounds: rounds, moves: moves)
            .warmingUp(with: warmUp)
            .following(steps)
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
                    }

                    IndexedSection(number: "02", label: "Moves") {
                        if !warmUp.isEmpty {
                            SectionHead(title: "Warm-up",
                                        note: "\(Int(WarmUp.seconds))s each")
                                .padding(.bottom, 4)
                            ForEach(Array(warmUp.enumerated()), id: \.element.id) { index, move in
                                BlockRow(index: index + 1, symbol: move.symbol,
                                         name: move.name, equipment: move.equipmentLabel,
                                         measure: "\(Int(WarmUp.seconds))s")
                                    .removable { warmUp.remove(at: index) }
                            }
                            Rule()
                            Spacer(minLength: 14)
                        }

                        // Says what is true. Reordering is not built, and a note
                        // promising a gesture that does not exist is worse than
                        // no note at all.
                        SectionHead(title: "In rotation",
                                    note: moves.isEmpty ? "optional" : "\(moves.count) in cycle")
                            .padding(.bottom, 4)

                        if moves.isEmpty {
                            // An empty rotation is a real answer, not a form
                            // left half-filled, and the copy has to say so —
                            // otherwise the one person who wants a bare timer
                            // reads this screen as refusing to give her one.
                            Text("Leave this empty for a plain interval timer — just work, rest and rounds. Add moves and each round takes the next one in the list.")
                                .font(.almanacBodySmall)
                                .foregroundStyle(Palette.mute)
                                .padding(.vertical, 10)
                                .fixedSize(horizontal: false, vertical: true)
                        } else {
                            ForEach(Array(moves.enumerated()), id: \.element.id) { index, move in
                                BlockRow(index: index + 1, symbol: move.symbol,
                                         name: move.name, equipment: move.equipmentLabel,
                                         measure: "\(Int(work))s")
                                    .removable { moves.remove(at: index) }
                            }
                            Rule()
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

                    IndexedSection(number: "03", label: "Sequence") {
                        SectionHead(title: "Write it out",
                                    note: steps.isEmpty ? "optional" : draft.totalDuration.durationString)
                            .padding(.bottom, 4)

                        if steps.isEmpty {
                            Text("Leave this empty and the routine is the shape above — the same work and rest, every round. Add steps and it follows them instead, each its own length, in the order you write them. Rests are optional: three work intervals in a row is a thing you can ask for.")
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
                    }

                    IndexedSection(number: "04", label: "Total") {
                        Rule(firm: true)
                        HStack(alignment: .lastTextBaseline) {
                            Text(draft.totalDuration.durationString)
                                .font(Face.ui(30, weight: .light))
                                .tabular()
                                .foregroundStyle(Palette.ink)
                            Spacer()
                            Text(totalNote)
                                .almanacLabel(Palette.mute, small: true)
                                .multilineTextAlignment(.trailing)
                        }
                        .padding(.vertical, 10)

                        // No longer disabled on an empty rotation. A routine
                        // with no moves is a timer, which is a thing she asked
                        // to be able to save.
                        PrimaryButton(title: "Save routine",
                                      subtitle: RoutineListView.rotationNote(draft)) {
                            onSave(draft)
                            dismiss()
                        }
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
                if move.kind == .flow { warmUp.append(move) } else { moves.append(move) }
            }
        }
    }

    private var totalNote: String {
        let shape = steps.isEmpty
            ? "\(rounds) × \(Int(work))/\(Int(rest)) · final rest dropped"
            : "\(draft.roundCount) work intervals in \(steps.count) steps"
        guard !warmUp.isEmpty else { return shape }
        return "\(warmUp.count) to warm up, then \(shape)"
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
                HStack(spacing: 6) {
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
            HStack(spacing: 6) {
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
            HStack(spacing: 6) {
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
    }
}

/// Only ever your own equipment.
struct MovePicker: View {
    @Environment(\.dismiss) private var dismiss
    let onPick: (Move) -> Void

    var body: some View {
        NavigationStack {
            List {
                // The morning practice first: it is what she reaches for most
                // often, and burying it under five equipment headings would
                // make the thing she does daily the hardest thing to find.
                if !MoveLibrary.flow.isEmpty {
                    SwiftUI.Section {
                        ForEach(MoveLibrary.flow) { move in
                            Button {
                                onPick(move)
                                dismiss()
                            } label: { row(move) }
                            .buttonStyle(.plain)
                        }
                    } header: {
                        Text("Flow · qi gong and lymphatic").almanacLabel(small: true)
                    } footer: {
                        Text("These open the session rather than joining the rotation — they are a practice, not a set.")
                            .font(.almanacBodySmall)
                            .foregroundStyle(Palette.mute)
                    }
                }

                ForEach(Equipment.allCases) { equipment in
                    let moves = MoveLibrary.moves(for: equipment)
                    if !moves.isEmpty {
                        SwiftUI.Section {
                            ForEach(moves) { move in
                                Button {
                                    onPick(move)
                                    dismiss()
                                } label: { row(move) }
                                .buttonStyle(.plain)
                            }
                        } header: {
                            Text(equipment.label).almanacLabel(small: true)
                        }
                    }
                }
            }
            .listStyle(.plain)
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
                Text(move.cue).font(.almanacBodySmall).foregroundStyle(Palette.mute)
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }
}
