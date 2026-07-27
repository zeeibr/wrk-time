import SwiftUI
import SwiftData

/// Saved routines, and the way into building one.
struct RoutineListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \SavedRoutine.createdAt, order: .reverse) private var saved: [SavedRoutine]

    @State private var building = false
    @State private var running: IntervalRoutine?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Your own routines")
                        .font(.almanacTitle)
                        .foregroundStyle(Palette.ink)
                        .padding(.top, 4)

                    PrimaryButton(title: "Build a routine",
                                  subtitle: "Work stays at 60 seconds or under") {
                        building = true
                    }

                    if saved.isEmpty {
                        Text("Nothing saved yet. A routine is a name, a work and rest length, and the moves you want in rotation.")
                            .font(.almanacBody)
                            .foregroundStyle(Palette.mute)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 4)
                    } else {
                        IndexedSection(number: "01", label: "Saved") {
                            Rule(firm: true)
                            ForEach(saved) { item in
                                if let routine = item.routine {
                                    savedRow(routine, lastRun: item.lastRunAt)
                                        .onTapGesture { running = routine }
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
        .fullScreenCover(item: $running) { WorkoutTimerView(routine: $0) }
    }

    private func savedRow(_ routine: IntervalRoutine, lastRun: Date?) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(routine.name).font(.almanacMoveName).foregroundStyle(Palette.ink)
                    Text("\(routine.rounds) × \(Int(routine.clampedWork))/\(Int(routine.rest)) · \(routine.moves.count) moves")
                        .almanacLabel(Palette.sage, small: true)
                        .tabular()
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 3) {
                    Text(routine.totalDuration.durationString)
                        .font(Face.ui(17)).tabular().foregroundStyle(Palette.ink)
                    if let lastRun {
                        Text("Last run \(lastRun.formatted(.dateTime.weekday(.abbreviated)))")
                            .almanacLabel(Palette.sage, small: true)
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
    @State private var picking = false
    @Environment(\.displayScale) private var displayScale

    private var draft: IntervalRoutine {
        IntervalRoutine(name: name.isEmpty ? "Untitled routine" : name,
                        work: work, rest: rest, rounds: rounds, moves: moves)
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
                        SectionHead(title: "In rotation", note: moves.isEmpty ? nil : "Drag to reorder")
                            .padding(.bottom, 4)

                        if moves.isEmpty {
                            Text("Add the moves you want to cycle through. Each round takes the next one in the list.")
                                .font(.almanacBodySmall)
                                .foregroundStyle(Palette.mute)
                                .padding(.vertical, 10)
                                .fixedSize(horizontal: false, vertical: true)
                        } else {
                            ForEach(Array(moves.enumerated()), id: \.element.id) { index, move in
                                BlockRow(index: index + 1, symbol: move.symbol,
                                         name: move.name, equipment: move.equipmentLabel,
                                         measure: "\(Int(work))s")
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
                                Text("From your kit").almanacLabel(Palette.sage, small: true)
                            }
                            .foregroundStyle(Palette.moss)
                            .padding(.vertical, 12)
                        }
                        .buttonStyle(.plain)
                    }

                    IndexedSection(number: "03", label: "Total") {
                        Rule(firm: true)
                        HStack(alignment: .lastTextBaseline) {
                            Text(draft.totalDuration.durationString)
                                .font(Face.ui(30, weight: .light))
                                .tabular()
                                .foregroundStyle(Palette.ink)
                            Spacer()
                            Text("\(rounds) × \(Int(work))/\(Int(rest)) · final rest dropped")
                                .almanacLabel(Palette.sage, small: true)
                                .multilineTextAlignment(.trailing)
                        }
                        .padding(.vertical, 10)

                        PrimaryButton(title: "Save routine",
                                      subtitle: "\(moves.count) moves") {
                            onSave(draft)
                            dismiss()
                        }
                        .disabled(moves.isEmpty)
                        .opacity(moves.isEmpty ? 0.45 : 1)
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
        .sheet(isPresented: $picking) {
            MovePicker { moves.append($0) }
        }
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
                Text(note).almanacLabel(Palette.sage, small: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func stepperButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Palette.moss)
                .frame(width: 24, height: 24)
                .overlay(Circle().strokeBorder(Palette.ruleFirm, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var divider: some View {
        Rectangle().fill(Palette.rule).frame(width: 1 / displayScale, height: 62)
    }
}

/// Only ever your own equipment.
struct MovePicker: View {
    @Environment(\.dismiss) private var dismiss
    let onPick: (Move) -> Void

    var body: some View {
        NavigationStack {
            List {
                ForEach(Equipment.allCases) { equipment in
                    let moves = MoveLibrary.moves(for: equipment)
                    if !moves.isEmpty {
                        SwiftUI.Section {
                            ForEach(moves) { move in
                                Button {
                                    onPick(move)
                                    dismiss()
                                } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(move.name).font(.almanacBody).foregroundStyle(Palette.ink)
                                        Text(move.cue).font(.almanacBodySmall).foregroundStyle(Palette.mute)
                                    }
                                }
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
}
