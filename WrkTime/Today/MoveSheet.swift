import SwiftUI
import SwiftData

/// One move, large enough to check yourself against.
///
/// The plates are small everywhere else — a row, a corner of the timer — and at
/// that size they say *which* movement rather than *how*. This is the screen
/// where a beginner can actually look at the shape before starting, which is
/// the whole reason she asked for diagrams.
struct MoveSheet: View {
    let move: Move
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    private var verdict: MoveVerdict? {
        MovePreferences.verdict(for: move.name, in: context)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(move.name)
                        .font(.almanacTitle)
                        .foregroundStyle(Palette.ink)
                        .accessibilityAddTraits(.isHeader)

                    HStack(spacing: 8) {
                        Image(systemName: move.symbol)
                            .font(.system(size: 12))
                        Text(move.equipmentLabel).almanacLabel(Palette.mute, small: true)
                        if move.kind == .flow {
                            Text("· flow").almanacLabel(Palette.mute, small: true)
                        }
                    }
                    .foregroundStyle(Palette.moss)
                    .padding(.top, 6)

                    Rule(firm: true).padding(.top, 14)

                    if MoveStrip.exists(for: move) {
                        MoveStrip(move: move, style: .full)
                            .frame(height: 236)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                        // Said out loud rather than implied. A drawing that
                        // claims more precision than it has is worse than one
                        // that admits what it is for.
                        Text("Read left to right. The shape and the order are what this shows — the line below is the form.")
                            .font(.almanacBodySmall)
                            .foregroundStyle(Palette.mute)
                            .fixedSize(horizontal: false, vertical: true)
                        Rule().padding(.vertical, 14)
                    }

                    Text(move.cue)
                        .font(.almanacBody)
                        .foregroundStyle(Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)

                    if let verdict {
                        Text(note(for: verdict))
                            .almanacLabel(Palette.mute, small: true)
                            .padding(.top, 14)
                    }

                    Rule().padding(.top, 18)

                    opinion("See less of this", .disliked)
                    opinion("More of this", .liked)
                    opinion("This hurts — never program it", .avoided, destructive: true)
                    if verdict != nil {
                        Button("Forget what I said") {
                            MovePreferences.clear(move.name, in: context)
                            dismiss()
                        }
                        .font(.almanacBody)
                        .foregroundStyle(Palette.mute)
                        .padding(.vertical, 12)
                    }
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 30)
            }
            .background(Palette.oat.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.foregroundStyle(Palette.ink)
                }
            }
        }
    }

    private func opinion(_ title: String, _ verdict: MoveVerdict,
                         destructive: Bool = false) -> some View {
        Button(title) {
            MovePreferences.set(verdict, for: move.name, in: context)
            dismiss()
        }
        .font(.almanacBody)
        .foregroundStyle(destructive ? Palette.ink : Palette.moss)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) { Rule() }
    }

    /// What the planner is currently doing about it, in her words not its own.
    private func note(for verdict: MoveVerdict) -> String {
        switch verdict {
        case .avoided: "You said this hurts. It is not being programmed."
        case .disliked: "You said you would rather do less of this."
        case .hard: "Kept in the plan, scaled down."
        case .liked: "You asked for more of this."
        }
    }
}
