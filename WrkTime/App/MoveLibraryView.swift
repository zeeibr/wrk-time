import SwiftUI
import SwiftData

/// The whole library, and what she thinks of each of it.
///
/// Opinions could already be recorded one at a time — long-press a move on
/// Today, or answer the question after skipping one — but both of those need
/// the move to turn up in a plan first. This is the place to say it about
/// anything, before it ever appears, and about several at once.
///
/// Selecting and then applying is deliberate rather than a control per row.
/// With thirty-seven moves, "these four all hurt" is one gesture and four taps
/// here; as a row control it is four separate menus.
struct MoveLibraryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    /// Observed, not fetched. The rows read a verdict per move, and without a
    /// query on the type SwiftUI has nothing to redraw against — so a mark was
    /// recorded and the list went on showing the old answer, which reads as the
    /// app ignoring her.
    @Query private var preferences: [MovePreference]

    @State private var selection: Set<String> = []
    /// What the last change did to the plan, said once and then cleared.
    @State private var repairNote: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header

                    ForEach(sections, id: \.title) { section in
                        IndexedSection(number: section.number, label: section.label) {
                            SectionHead(title: section.title,
                                        note: section.moves.count == 1 ? "1 move"
                                                                       : "\(section.moves.count) moves")
                                .padding(.bottom, 4)
                            ForEach(section.moves) { move in
                                row(move)
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, selection.isEmpty ? 28 : 150)
            }
            .background(Palette.oat.ignoresSafeArea())
            .safeAreaInset(edge: .bottom) { actions }
            .navigationTitle("Every move")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.foregroundStyle(Palette.ink)
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tap to select, then say what you think. Anything you rule out is taken out of the sessions already written, not just the next ones.")
                .font(.almanacBodySmall)
                .foregroundStyle(Palette.mute)
                .fixedSize(horizontal: false, vertical: true)
            if let repairNote {
                Text(repairNote)
                    .font(.almanacBodySmall)
                    .foregroundStyle(Palette.saffronInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, 4)
    }

    // MARK: - Rows

    private func row(_ move: Move) -> some View {
        let picked = selection.contains(move.name)
        let verdict = self.verdict(for: move.name)

        return VStack(spacing: 0) {
            Rule()
            HStack(spacing: 10) {
                // A filled square rather than a tick: the app has no checkmark
                // vocabulary, and a mark on a rule is what it does elsewhere.
                Rectangle()
                    .fill(picked ? Palette.ink : Color.clear)
                    .frame(width: 9, height: 9)
                    .overlay(Rectangle().strokeBorder(picked ? Palette.ink : Palette.ruleFirm,
                                                      lineWidth: 1))

                MoveStrip(move: move, style: .signature)
                    .frame(width: 42, height: 42)

                VStack(alignment: .leading, spacing: 1) {
                    Text(move.name).font(.almanacBody).foregroundStyle(Palette.ink)
                    Text(verdict.map(note(for:)) ?? move.equipmentLabel)
                        .almanacLabel(verdict == nil ? Palette.mute : Palette.saffronInk,
                                      small: true)
                }
                Spacer(minLength: 8)
            }
            .padding(.vertical, 7)
            .contentShape(Rectangle())
            .onTapGesture {
                if picked { selection.remove(move.name) } else { selection.insert(move.name) }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(move.name)
        .accessibilityValue(verdict.map(note(for:)) ?? "No opinion")
        .accessibilityAddTraits(picked ? [.isButton, .isSelected] : .isButton)
    }

    /// The standing opinion about a move, read from the observed query.
    ///
    /// Avoidance wins any tie, the same rule `MovePreferences.verdict` follows:
    /// if one opinion says a movement hurt, that outranks a milder verdict on
    /// an overlapping name.
    private func verdict(for name: String) -> MoveVerdict? {
        let matches = preferences.filter { $0.covers(name) }
        if matches.contains(where: { $0.verdict == .avoided }) { return .avoided }
        return matches.first?.verdict
    }

    private func note(for verdict: MoveVerdict) -> String {
        switch verdict {
        case .avoided: "Never programmed"
        case .disliked: "Seen rarely"
        case .hard: "Scaled down"
        case .liked: "Asked for"
        }
    }

    // MARK: - The bar

    @ViewBuilder
    private var actions: some View {
        if !selection.isEmpty {
            VStack(spacing: 0) {
                Rule(firm: true)
                HStack(alignment: .firstTextBaseline) {
                    Text(selection.count == 1 ? "1 selected" : "\(selection.count) selected")
                        .almanacLabel(Palette.mute, small: true)
                    Spacer()
                    Button("Clear") { selection.removeAll() }
                        .font(.almanacBodySmall)
                        .foregroundStyle(Palette.moss)
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)

                HStack(spacing: 8) {
                    action("More", .liked)
                    action("Less", .disliked)
                    action("Never", .avoided)
                    Button {
                        MovePreferences.clear(Array(selection), in: context)
                        finish(nil)
                    } label: {
                        Text("Forget")
                            .font(.almanacBodySmall)
                            .foregroundStyle(Palette.moss)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .overlay(Rectangle().strokeBorder(Palette.ruleFirm, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, 14)
            }
            .background(Palette.oat)
        }
    }

    private func action(_ title: String, _ verdict: MoveVerdict) -> some View {
        Button {
            let summary = MovePreferences.apply(verdict, to: Array(selection), in: context)
            finish(summary.note)
        } label: {
            Text(title)
                .font(.almanacBodySmall)
                .foregroundStyle(verdict == .avoided ? Palette.oat : Palette.ink)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(verdict == .avoided ? Palette.ink : Color.clear)
                .overlay(Rectangle().strokeBorder(verdict == .avoided ? Palette.ink
                                                                      : Palette.ruleFirm,
                                                  lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func finish(_ note: String?) {
        try? context.save()
        repairNote = note
        selection.removeAll()
        Haptics.transport()
    }

    // MARK: - Grouping

    private struct Group { let number, label, title: String; let moves: [Move] }

    /// Flow first, the way the picker does it: it is the thing she reaches for
    /// daily, and burying it under five equipment headings would make the most
    /// used part of the library the hardest to find.
    private var sections: [Group] {
        var out: [Group] = []
        if !MoveLibrary.flow.isEmpty {
            out.append(Group(number: "01", label: "Flow",
                             title: "Flow", moves: MoveLibrary.flow))
        }
        for equipment in Equipment.allCases {
            let moves = MoveLibrary.moves(for: equipment)
            guard !moves.isEmpty else { continue }
            out.append(Group(number: String(format: "%02d", out.count + 1),
                             label: equipment.shortLabel,
                             title: equipment.label, moves: moves))
        }
        return out
    }
}
