import SwiftData
import SwiftUI

/// Keeping a set you did off the plan.
///
/// Three decisions and a button. This is used standing in a kitchen with one
/// hand, so it opens on the move picker if nothing is chosen yet and defaults
/// everything else to something sensible.
struct LogSetView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @State private var move: Move?
    @State private var reps = 10
    @State private var load: Double?
    @State private var picking = false

    /// Only the loads that exist. The rings are 5, 8 and 10 — not a spinner
    /// from zero, and not a number field that would let you record a weight you
    /// do not own.
    private var loadOptions: [Double] {
        move.map { Equipment.loads(for: $0) } ?? []
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Masthead(context: "Keep a set")
                        .padding(.top, 4)

                    IndexedSection(number: "01", label: "Move") {
                        SectionHead(title: move?.name ?? "Nothing chosen",
                                    note: move == nil ? nil : "From your kit")
                            .padding(.bottom, 10)

                        if let move {
                            Text(move.cue)
                                .font(.almanacBodySmall)
                                .foregroundStyle(Palette.mute)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.bottom, 10)
                        }

                        Button { picking = true } label: {
                            HStack {
                                Image(systemName: "plus")
                                    .font(.system(size: 13, weight: .semibold))
                                Text(move == nil ? "Choose a move" : "Choose a different move")
                                    .font(.almanacBody)
                                Spacer()
                            }
                            .foregroundStyle(Palette.moss)
                            .padding(.vertical, 12)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Rule()
                    }

                    IndexedSection(number: "02", label: "Reps") {
                        SectionHead(title: "How many", note: "1 – 100")
                            .padding(.bottom, 12)
                        HStack(spacing: 14) {
                            Figure(value: "\(reps)", unit: "reps", size: 30)
                            Spacer()
                            stepButton("minus") { reps = max(1, reps - 1) }
                            stepButton("plus") { reps = min(100, reps + 1) }
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Reps")
                        .accessibilityValue("\(reps)")
                        .accessibilityAdjustableAction { direction in
                            switch direction {
                            case .increment: reps = min(100, reps + 1)
                            case .decrement: reps = max(1, reps - 1)
                            @unknown default: break
                            }
                        }
                        .padding(.bottom, 12)
                        Rule()
                    }

                    if !loadOptions.isEmpty {
                        IndexedSection(number: "03", label: "Load") {
                            SectionHead(title: "What you picked up",
                                        note: move?.equipment.shortLabel)
                                .padding(.bottom, 12)
                            HStack(spacing: 10) {
                                ForEach(loadOptions, id: \.self) { option in
                                    loadChip(option)
                                }
                            }
                            .padding(.bottom, 12)
                            Rule()
                        }
                    }

                    PrimaryButton(title: "Keep it", subtitle: summary) { save() }
                        .opacity(move == nil ? 0.45 : 1)
                        .disabled(move == nil)

                    if move == nil {
                        Text("Choose a move to keep the set.")
                            .font(.almanacBodySmall)
                            .foregroundStyle(Palette.mute)
                    } else {
                        Text("Kept as loose work. It counts toward what the plan sees, but a mark on the season is still one finished session.")
                            .font(.almanacBodySmall)
                            .foregroundStyle(Palette.mute)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 28)
            }
            .background(Palette.oat.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundStyle(Palette.mute)
                }
            }
        }
        .sheet(isPresented: $picking) {
            MovePicker { picked in
                move = picked
                // The weight the move is actually written for, so the chip and
                // the cue agree. A load carried over from a different implement
                // would be a lie.
                load = picked.loadPounds ?? Equipment.loads(for: picked).first
            }
        }
        .onAppear { if move == nil { picking = true } }
    }

    private var summary: String? {
        guard let move else { return nil }
        let load = load.map { " · \(Int($0)) lb" } ?? ""
        return "\(reps) × \(move.name)\(load)"
    }

    private func loadChip(_ option: Double) -> some View {
        let selected = load == option
        return Button { load = option } label: {
            Text("\(Int(option)) lb")
                .font(Face.ui(15, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? Palette.oat : Palette.ink)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background {
                    RoundedRectangle(cornerRadius: 9)
                        .fill(selected ? Palette.ink : Color.clear)
                        .overlay {
                            RoundedRectangle(cornerRadius: 9)
                                .strokeBorder(selected ? Color.clear : Palette.ruleFirm,
                                              lineWidth: 1)
                        }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(Int(option)) pounds")
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    private func stepButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Palette.moss)
                .frame(width: 30, height: 30)
                .overlay(Circle().strokeBorder(Palette.ruleFirm, lineWidth: 1))
                .contentShape(Rectangle().inset(by: -7))
        }
        .buttonStyle(.plain)
        .accessibilityHidden(true)   // the row above is the adjustable control
    }

    private func save() {
        guard let move else { return }
        context.insert(LoggedSet(move: move, reps: reps, loadPounds: load))
        try? context.save()
        Haptics.transport()
        dismiss()
    }
}
