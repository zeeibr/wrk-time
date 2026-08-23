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

    /// Observed, so the sheet redraws the moment an opinion is recorded rather
    /// than reading a value it fetched once.
    @Query private var preferences: [MovePreference]
    /// What the last change did to the plan, so the consequence is visible
    /// instead of being taken on trust.
    @State private var repairNote: String?
    /// The load she just stepped up to from here, so the offer becomes an
    /// acknowledgement rather than repeating itself.
    @State private var appliedLoad: Double?

    private var verdict: MoveVerdict? {
        let matches = preferences.filter { $0.covers(move.name) }
        if matches.contains(where: { $0.verdict == .avoided }) { return .avoided }
        return matches.first?.verdict
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

                    if let form = CustomMoves.form(for: move.name, in: context) {
                        FormCard(form: form).padding(.top, 18)
                    }

                    if let verdict {
                        Text(note(for: verdict))
                            .almanacLabel(Palette.mute, small: true)
                            .padding(.top, 14)
                    }

                    history
                    progression
                    if let repairNote {
                        Text(repairNote)
                            .font(.almanacBodySmall)
                            .foregroundStyle(Palette.saffronInk)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 8)
                    }

                    Rule().padding(.top, 18)

                    opinion("See less of this", .disliked)
                    opinion("More of this", .liked)
                    opinion("This hurts — never program it", .avoided, destructive: true)
                    if verdict != nil {
                        Button("Forget what I said") {
                            MovePreferences.clear(move.name, in: context)
                            try? context.save()
                            repairNote = nil
                            Haptics.transport()
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

    // MARK: - What you have done

    /// The sessions this move was counted in, most recent first.
    ///
    /// A record, not a scoreboard. It states the sets in the order they were
    /// done and leaves the reading to her: a session that went down is shown
    /// exactly like one that went up, because a day with less in it is a fact
    /// about that day and not a verdict on her. The only interpretation
    /// offered is the plainest one — the best set, and when it was.
    @ViewBuilder
    private var history: some View {
        let logs = SetLogs.history(forMovementOf: move, in: context)
        if !logs.isEmpty {
            Rule().padding(.top, 18)
            HStack(alignment: .firstTextBaseline) {
                // The movement whole — this row and the same movement on
                // any other implement — so the ring and the bell read as
                // one line of progress rather than two strangers.
                Text(move.movement.map { "Counted · \($0.display.lowercased())" } ?? "Counted")
                    .almanacLabel(Palette.mute, small: true)
                Spacer(minLength: 8)
                Text(bestLine(logs)).almanacLabel(Palette.mute, small: true).tabular()
            }
            .padding(.top, 14)
            .padding(.bottom, 2)

            ForEach(logs.reversed().prefix(6)) { log in
                VStack(spacing: 0) {
                    Rule()
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(log.date.formatted(.dateTime.day().month(.abbreviated)))
                            .almanacLabel(Palette.mute, small: true)
                            .tabular()
                        Text(log.reps.map(String.init).joined(separator: ", "))
                            .font(.almanacBody)
                            .foregroundStyle(Palette.ink)
                        Spacer(minLength: 8)
                        // Another implement's row says which it was.
                        if MovePreference.key(log.moveName) != MovePreference.key(move.name) {
                            Text(log.moveName).almanacLabel(Palette.mute, small: true)
                        } else if let pounds = log.loadPounds, pounds > 0 {
                            Text("\(Int(pounds)) lb")
                                .almanacLabel(Palette.mute, small: true)
                                .tabular()
                        }
                    }
                    .padding(.vertical, 9)
                }
                .accessibilityElement(children: .combine)
            }
            Rule()

            Text(log(for: move))
                .font(.almanacBodySmall)
                .foregroundStyle(Palette.mute)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)
        }
    }

    /// The step up, when her counts have earned it. Offered, never urged: one
    /// sentence, one button, and declining it is just not tapping. The load
    /// change goes through `MoveOverrides` like any other, so it reaches
    /// sessions already written and the cue text corrects itself.
    @ViewBuilder
    private var progression: some View {
        if let suggestion = LoadProgression.suggestion(for: move, in: context),
           appliedLoad == nil {
            VStack(alignment: .leading, spacing: 0) {
                Rule().padding(.top, 16)
                Text(suggestion.line)
                    .font(.almanacBody)
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 12)
                Text("Two set sessions running with every counted set at twelve. Staying where you are is also a fine answer.")
                    .font(.almanacBodySmall)
                    .foregroundStyle(Palette.mute)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
                if let bridge = suggestion.bridge {
                    Text(bridge)
                        .font(.almanacBodySmall)
                        .foregroundStyle(Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 8)
                }
                Button("Move to \(Int(suggestion.nextPounds)) lb") {
                    MoveOverrides.set(suggestion.nextPounds, for: move, in: context)
                    appliedLoad = suggestion.nextPounds
                    Haptics.transport()
                }
                .font(.almanacBody)
                .foregroundStyle(Palette.moss)
                .padding(.vertical, 12)
            }
        } else if let pounds = appliedLoad {
            Text("\(move.name) now asks for \(Int(pounds)) lb — everywhere, including sessions already written.")
                .font(.almanacBodySmall)
                .foregroundStyle(Palette.saffronInk)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)
        }
    }

    /// "Best 12 · Aug 14", or nothing to say with one session behind it.
    private func bestLine(_ logs: [SetLog]) -> String {
        guard let best = logs.max(by: { $0.best < $1.best }), best.best > 0 else {
            return "\(logs.count) \(logs.count == 1 ? "session" : "sessions")"
        }
        return "Best \(best.best) · \(best.date.formatted(.dateTime.day().month(.abbreviated)))"
    }

    private func log(for move: Move) -> String {
        move.sided != nil
            ? "Sets in the order you did them, one entry per side. Counted during the rest after each set."
            : "Sets in the order you did them, counted during the rest after each set."
    }

    private func opinion(_ title: String, _ verdict: MoveVerdict,
                         destructive: Bool = false) -> some View {
        Button(title) {
            let summary = MovePreferences.set(verdict, for: move.name, in: context)
            try? context.save()
            repairNote = summary.note
            Haptics.transport()
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


/// The five lines of `MoveForm`, as a small document: a mono label, the
/// sentence beside it, a hairline between. Shared by the move sheet and the
/// timer's form sheet so the two never drift.
struct FormCard: View {
    let form: MoveForm
    /// On the field the card draws in the field's own colours.
    var foreground: Color = Palette.ink
    var secondary: Color = Palette.mute

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Form").almanacLabel(secondary, small: true)
                .padding(.bottom, 6)
            Rule(firm: true)
            line("Set up", form.setUp)
            line("Move", form.movement)
            line("Feel", form.feel)
            line("Watch", form.wrong)
            line("Stop if", form.stopIf)
        }
        .accessibilityElement(children: .combine)
    }

    private func line(_ label: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(label)
                    .almanacLabel(secondary, small: true)
                    .frame(width: 56, alignment: .leading)
                Text(text)
                    .font(.almanacBody)
                    .foregroundStyle(foreground)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 9)
            Rule()
        }
    }
}
