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
    /// On the Moves tab this is the second half of the screen, under her own
    /// routines; from Settings it is still its own sheet. Embedded, it drops
    /// the navigation chrome and takes a slot above the library for the
    /// routines section, so the tab reads as one document.
    var embedded = false
    var topSection: AnyView?

    /// Embedded under the routines section, the margin numbers continue from
    /// it rather than starting a second "01" halfway down one document.
    private var numberOffset: Int { embedded ? 1 : 0 }
    private func number(_ position: Int) -> String {
        String(format: "%02d", position + numberOffset)
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    /// Observed, not fetched. The rows read a verdict per move, and without a
    /// query on the type SwiftUI has nothing to redraw against — so a mark was
    /// recorded and the list went on showing the old answer, which reads as the
    /// app ignoring her.
    @Query private var preferences: [MovePreference]
    /// Observed for the same reason: a review lands while this screen is open.
    @Query(sort: \CustomMove.addedAt) private var customs: [CustomMove]
    /// Observed so a load she changes redraws its rows at once.
    @Query private var overrides: [MoveOverride]
    /// Observed so a session counted an hour ago already shows on its row.
    @Query private var setLogs: [SetLog]

    /// Declared so this screen redraws when she switches a drawer on or off in
    /// Settings. The value is read through `Equipment.owned`; this property
    /// exists only to make `UserDefaults` publish, which it otherwise does not
    /// — the sections would have gone on listing a band until the next launch.
    @AppStorage(Tuning.ownedEquipmentKey) private var ownedRaw = ""

    @State private var selection: Set<String> = []
    /// The move whose sheet is open — its drawing, its cue, and what she has
    /// counted on it.
    @State private var inspecting: Move?
    /// Which sections are open. Collapsed by default — sixty-odd rows is a
    /// scroll of a list, and the headers are the overview.
    @State private var expandedSections: Set<String> = []
    /// The pattern the library is narrowed to, or nil for all of it. A
    /// filter on the list, not a section: the sections are where the body
    /// is, and a hinge is a hinge whether she is holding the bell or the beam.
    @State private var patternFilter: MovePattern?
    /// What the last change did to the plan, said once and then cleared.
    @State private var repairNote: String?

    // Her additions.
    @State private var newName = ""
    @State private var reviewing = false
    @State private var reviewNote: String?

    // The sampler.
    /// Observed so a finished flight advances the tried count on return.
    @Query private var runs: [RoutineRun]
    /// Observed for the same reason: a session finished today counts its
    /// moves as tried.
    @Query private var sessions: [PlannedSession]
    @State private var sampling: IntervalRoutine?

    // Suggestions by muscle.
    @State private var muscle: String?
    @State private var suggesting = false
    @State private var suggestions: [MoveReviewer.Entry] = []
    @State private var suggestNote: String?

    var body: some View {
        if embedded {
            document
        } else {
            NavigationStack {
                document
                    .navigationTitle("Every move")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { dismiss() }.foregroundStyle(Palette.ink)
                        }
                    }
            }
        }
    }

    private var document: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let topSection { topSection }
                    header

                    yoursSection
                    targetSection
                    samplerSection

                    ForEach(sections, id: \.title) { section in
                        // The chips sit above the first strength section,
                        // in its column: they narrow the strength library
                        // and say nothing about flow.
                        if section.subheaded, section.title == sections.first(where: \.subheaded)?.title {
                            patternChips
                        }
                        IndexedSection(number: section.number, label: section.label) {
                            let open = expandedSections.contains(section.title)
                            Button {
                                if open { expandedSections.remove(section.title) }
                                else { expandedSections.insert(section.title) }
                            } label: {
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    SectionHead(title: section.title,
                                                note: section.moves.count == 1 ? "1 move"
                                                                               : "\(section.moves.count) moves")
                                    Image(systemName: "chevron.down")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(Palette.mute)
                                        .rotationEffect(.degrees(open ? 0 : -90))
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(.isButton)
                            .accessibilityValue(open ? "Expanded" : "Collapsed")
                            .padding(.bottom, 4)

                            if open {
                                ForEach(Array(section.moves.enumerated()), id: \.element.id) { index, move in
                                    if section.subheaded, let head = subhead(at: index, in: section.moves) {
                                        Text(head)
                                            .almanacLabel(Palette.mute, small: true)
                                            .padding(.top, index == 0 ? 2 : 12)
                                            .padding(.bottom, 2)
                                    }
                                    row(move)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, selection.isEmpty ? 28 : 150)
            }
            .background(Palette.oat.ignoresSafeArea())
            .sheet(item: $inspecting) { MoveSheet(move: $0) }
            // The recording happens in `WorkoutTimerView.report`, like every
            // run — this cover only presents. A finished flight writes a
            // `RoutineRun`, which is exactly what marks its moves as tried.
            .fullScreenCover(item: $sampling) { routine in
                WorkoutTimerView(routine: routine, subject: .routine)
            }
            .safeAreaInset(edge: .bottom) { actions }
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

    // MARK: - Her additions

    /// The queue and what became of it. Names pile up locally and one send
    /// checks the whole batch — a request per name would spend a call on each
    /// of five moves she typed in one sitting.
    private var yoursSection: some View {
        IndexedSection(number: number(1), label: "Yours") {
            SectionHead(title: "Your additions", note: yoursNote)
                .padding(.bottom, 4)

            ForEach(customs) { custom in
                customRow(custom)
            }

            VStack(spacing: 0) {
                Rule()
                HStack(spacing: 10) {
                    TextField("Name a move to add", text: $newName)
                        .font(.almanacBody)
                        .foregroundStyle(Palette.ink)
                        .autocorrectionDisabled()
                        .onSubmit { queueName() }
                    Button("Queue") { queueName() }
                        .font(.almanacBodySmall)
                        .foregroundStyle(newName.trimmingCharacters(in: .whitespaces).isEmpty
                                         ? Palette.mute : Palette.moss)
                        .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(.vertical, 11)
                Rule()
            }

            if customs.contains(where: { $0.status == .queued }) {
                let waiting = customs.filter { $0.status == .queued }.count
                outlinedAction(reviewing ? "Checking…" : "Send for review",
                               meta: waiting == 1 ? "1 move" : "\(waiting) moves",
                               busy: reviewing) {
                    Task { await sendForReview() }
                }
                .padding(.top, 10)
            }

            if let reviewNote {
                Text(reviewNote)
                    .font(.almanacBodySmall)
                    .foregroundStyle(Palette.saffronInk)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
            }

            Text("Queue moves by name and send them together — a lift or a qi gong movement, no need to say which. Claude checks each against the kit, writes the cue, and decides what it is: strength joins the rotations, flow joins the morning practice and the warm-ups. It will not have a drawing.")
                .font(.almanacBodySmall)
                .foregroundStyle(Palette.mute)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)
        }
    }

    private var yoursNote: String {
        let approved = customs.filter { $0.status == .approved }.count
        let queued = customs.filter { $0.status == .queued }.count
        var parts: [String] = []
        if approved > 0 { parts.append(approved == 1 ? "1 added" : "\(approved) added") }
        if queued > 0 { parts.append(queued == 1 ? "1 waiting" : "\(queued) waiting") }
        return parts.isEmpty ? "None yet" : parts.joined(separator: " · ")
    }

    private func customRow(_ custom: CustomMove) -> some View {
        VStack(spacing: 0) {
            Rule()
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(custom.name).font(.almanacBody).foregroundStyle(Palette.ink)
                    Text(note(for: custom))
                        .almanacLabel(custom.status == .rejected ? Palette.saffronInk : Palette.mute,
                                      small: true)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Button(custom.status == .rejected ? "Clear" : "Remove") {
                    context.delete(custom)
                    try? context.save()
                }
                .font(.almanacBodySmall)
                .foregroundStyle(Palette.moss)
            }
            .padding(.vertical, 9)
        }
        .accessibilityElement(children: .combine)
    }

    private func note(for custom: CustomMove) -> String {
        switch custom.status {
        case .queued: "Waiting to be sent"
        case .approved:
            // A flow addition says where it went — the daily practice, not the
            // rotations — because that is the question she will ask.
            custom.kind == .flow
                ? "Flow · joins the morning practice"
                : [custom.move.equipmentLabel, custom.muscles].compactMap(\.self)
                    .joined(separator: " · ")
        case .rejected: custom.note ?? "Turned away"
        }
    }

    private func queueName() {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let key = MovePreference.key(trimmed)
        let known = MoveLibrary.all.map(\.name) + customs.map(\.name)
        guard !known.contains(where: { MovePreference.key($0) == key }) else {
            reviewNote = "\(trimmed) is already here."
            return
        }
        reviewNote = nil
        context.insert(CustomMove(name: trimmed))
        try? context.save()
        newName = ""
    }

    private func sendForReview() async {
        let queued = customs.filter { $0.status == .queued }
        guard !queued.isEmpty, !reviewing else { return }
        reviewing = true
        defer { reviewing = false }

        do {
            // The whole working library, flow included — `names` is strength
            // only, and a duplicate of a flow movement should be caught too.
            let existing = MoveLibrary.all.map(\.name)
                + customs.filter { $0.status == .approved }.map(\.name)
            let result = try await MoveReviewer().review(queued.map(\.name), existing: existing)
            // Counted in the same ledger as the planner's requests — money
            // spent that no surface counts is how spend drifts.
            PlanTrigger.record(result.usage)
            apply(result.entries, to: queued)
            let approved = queued.filter { $0.status == .approved }.count
            let rejected = queued.filter { $0.status == .rejected }.count
            var parts: [String] = []
            if approved > 0 { parts.append(approved == 1 ? "1 added to the library" : "\(approved) added to the library") }
            if rejected > 0 { parts.append(rejected == 1 ? "1 turned away" : "\(rejected) turned away") }
            reviewNote = parts.isEmpty ? "Nothing came back for the queue — it keeps; send again."
                                       : parts.joined(separator: ", ") + "."
        } catch {
            reviewNote = Self.failureNote(error)
        }
    }

    /// Writes what the review said onto the queued rows. A name the answer
    /// skipped stays queued rather than being guessed about.
    ///
    /// Matched by exact key, falling back to position only when the answer has
    /// one entry per queued name — the order the prompt asked for. Containment
    /// matching sat here briefly and is exactly the mistake the closed library
    /// exists to prevent: queue "curl" and "hammer curl" and both rows matched
    /// the one "Hammer curl" entry, approving the same name twice.
    private func apply(_ entries: [MoveReviewer.Entry], to queued: [CustomMove]) {
        let byPosition = entries.count == queued.count
        for (index, row) in queued.enumerated() {
            let key = MovePreference.key(row.name)
            let entry = entries.first(where: { MovePreference.key($0.name) == key })
                ?? (byPosition ? entries[index] : nil)
            guard let entry else { continue }

            if entry.isApproved {
                fill(row, from: entry)
            } else {
                row.statusRaw = CustomMove.Status.rejected.rawValue
                row.note = entry.note.isEmpty ? "Turned away without a reason." : entry.note
            }
        }
        try? context.save()
    }

    private func fill(_ row: CustomMove, from entry: MoveReviewer.Entry) {
        row.statusRaw = CustomMove.Status.approved.rawValue
        row.name = entry.name
        row.kindRaw = entry.kind
        row.equipmentRaw = entry.equipment
        row.cue = entry.cue
        row.loadPounds = entry.loadPounds > 0 ? entry.loadPounds : nil
        row.sidedRaw = entry.sided == "none" ? nil : entry.sided
        row.muscles = entry.muscles.isEmpty ? nil : entry.muscles
        row.note = entry.note.isEmpty ? nil : entry.note
        row.patternRaw = entry.movePattern?.rawValue
        row.positionRaw = entry.movePosition?.rawValue
        MoveTaxonomy.register(row.name, pattern: entry.movePattern, position: entry.movePosition)
        if let form = entry.form {
            row.formSetUp = form.setUp
            row.formMovement = form.movement
            row.formFeel = form.feel
            row.formWrong = form.wrong
            row.formStopIf = form.stopIf
        }
    }

    /// The sheet's two asks of Claude, drawn as outlined rows — label left,
    /// mono meta right — rather than ink fills. Two full-width ink slabs here
    /// read as competing primaries mimicking "Never" at the wrong scale; the
    /// one ink fill this screen owns is the selection bar's.
    private func outlinedAction(_ title: String, meta: String, busy: Bool,
                                action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.almanacBodySmall)
                    .foregroundStyle(busy ? Palette.mute : Palette.ink)
                Spacer(minLength: 8)
                Text(meta)
                    .almanacLabel(Palette.mute, small: true)
                    .tabular()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .overlay(Rectangle().strokeBorder(Palette.ruleFirm, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(busy)
    }

    /// The planner's error strings all end "…drawn from the plan's own rules",
    /// which is the wrong sentence here — nothing falls back. The queue keeps.
    private static func failureNote(_ error: Error) -> String {
        switch error {
        case PlannerError.noKey:
            "No API key is set. The queue keeps — add a key in Settings and send again."
        case PlannerError.http(let code, let detail):
            "Claude answered \(code)\(detail.isEmpty ? "" : ": \(detail)"). The queue keeps; try again in a while."
        case PlannerError.transport(let error):
            "\(PlannerError.transportPhrase(error)) The queue keeps; try again in a while."
        default:
            "The answer came back unusable. The queue keeps; send again."
        }
    }

    // MARK: - By muscle

    /// Suggestions for a muscle she wants more of, written out in full so an
    /// accepted offer needs no second review.
    private var targetSection: some View {
        IndexedSection(number: number(2), label: "Target") {
            SectionHead(title: "By muscle", note: muscle ?? "Pick one")
                .padding(.bottom, 8)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), spacing: 8)], spacing: 8) {
                ForEach(MoveReviewer.muscles, id: \.self) { name in
                    Button {
                        muscle = muscle == name ? nil : name
                        suggestions = []
                        suggestNote = nil
                    } label: {
                        Text(name)
                            .font(.almanacBodySmall)
                            .foregroundStyle(muscle == name ? Palette.oat : Palette.ink)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(muscle == name ? Palette.ink : Color.clear)
                            .overlay(Rectangle().strokeBorder(muscle == name ? Palette.ink
                                                                             : Palette.ruleFirm,
                                                              lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(muscle == name ? [.isButton, .isSelected] : .isButton)
                }
            }

            if let muscle {
                outlinedAction(suggesting ? "Asking…" : "Suggest moves",
                               meta: muscle,
                               busy: suggesting) {
                    Task { await requestSuggestions() }
                }
                .padding(.top, 10)
            }

            ForEach(suggestions, id: \.name) { entry in
                suggestionRow(entry)
            }

            if let suggestNote {
                Text(suggestNote)
                    .font(.almanacBodySmall)
                    .foregroundStyle(Palette.saffronInk)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
            }
        }
    }

    private func suggestionRow(_ entry: MoveReviewer.Entry) -> some View {
        VStack(spacing: 0) {
            Rule()
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.name).font(.almanacBody).foregroundStyle(Palette.ink)
                    Text(entry.cue)
                        .font(.almanacBodySmall)
                        .foregroundStyle(Palette.mute)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Button("Add") { add(entry) }
                    .font(.almanacBodySmall)
                    .foregroundStyle(Palette.moss)
            }
            .padding(.vertical, 9)
        }
        .accessibilityElement(children: .combine)
    }

    private func requestSuggestions() async {
        guard let muscle, !suggesting else { return }
        suggesting = true
        defer { suggesting = false }
        suggestNote = nil

        do {
            let existing = MoveLibrary.all.map(\.name) + customs.map(\.name)
            // Refusals travel with the ask: pain and dislike both bar a
            // suggestion, the same two verdicts every rotation builder honours.
            let refused = MovePreferences.lists(in: context)
            let ruledOut = Set((refused.avoided + refused.disliked).map { MovePreference.key($0) })
            let result = try await MoveReviewer().suggest(muscle: muscle, existing: existing,
                                                          avoiding: ruledOut)
            PlanTrigger.record(result.usage)
            suggestions = result.entries.filter(\.isApproved)
            if suggestions.isEmpty { suggestNote = "Nothing new to offer there." }
        } catch {
            suggestNote = Self.failureNote(error)
        }
    }

    /// A suggestion she takes was already written in full by the same review
    /// that vets her own queue, so it lands approved. Guarded by key against
    /// what is already here — tapping Add twice, or a suggestion colliding
    /// with an earlier addition, must not put the same name in the library and
    /// therefore twice into the planner's schema enum.
    private func add(_ entry: MoveReviewer.Entry) {
        let key = MovePreference.key(entry.name)
        let known = MoveLibrary.all.map(\.name) + customs.map(\.name)
        guard !known.contains(where: { MovePreference.key($0) == key }) else {
            suggestions.removeAll { $0.name == entry.name }
            suggestNote = "\(entry.name) is already here."
            return
        }
        let row = CustomMove(name: entry.name)
        fill(row, from: entry)
        context.insert(row)
        try? context.save()
        suggestions.removeAll { $0.name == entry.name }
    }

    // MARK: - The sampler

    /// The working strength pool: built-ins plus her approved additions,
    /// the same set every rotation builder sees.
    private var samplerPool: [Move] {
        MoveLibrary.available + CustomMoves.strength(in: context)
    }

    /// What she has already been through, derived from the records that
    /// already exist — completed sessions, her own runs, loose sets.
    private var triedKeys: Set<String> {
        MoveSampler.triedKeys(
            routines: sessions.filter { $0.completedAt != nil }.compactMap(\.routine),
            runMoveNames: runs.map(\.moveNames),
            logMoveNames: setLogs.map(\.moveName))
    }

    private var samplerSection: some View {
        let progress = MoveSampler.progress(library: samplerPool, tried: triedKeys)
        let flight = MoveSampler.build(
            from: samplerPool,
            tried: triedKeys,
            avoiding: Set(preferences.filter { $0.verdict == .avoided || $0.verdict == .disliked }
                .map(\.moveName).map { MovePreference.key($0) }),
            loads: overridesTable)

        return IndexedSection(number: number(3), label: "Sampler") {
            SectionHead(title: "The sampler",
                        note: "Tried \(progress.tried) of \(progress.total)")
                .padding(.bottom, 8)

            Text("Ten seconds on each of six moves you have not met yet, ten between — a taste, not a set. It counts them as tried and earns no mark.")
                .font(.almanacBodySmall)
                .foregroundStyle(Palette.mute)
                .fixedSize(horizontal: false, vertical: true)

            if !flight.moves.isEmpty {
                outlinedAction("Begin a flight",
                               meta: "\(flight.moves.count) moves · \(flight.totalDuration.clockString)",
                               busy: false) {
                    sampling = flight
                }
                .padding(.top, 10)
            }
        }
    }

    // MARK: - Rows

    private func row(_ raw: Move) -> some View {
        // Shown at her load, when she has set one.
        let move = raw.applyingLoad(from: overridesTable)
        let picked = selection.contains(move.name)
        let verdict = self.verdict(for: move.name)
        let muscles = MoveMuscles.groups(for: move.name)

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

                if MoveStrip.exists(for: move) {
                    MoveStrip(move: move, style: .signature)
                        .frame(width: 42, height: 42)
                } else {
                    // No drawing rather than a wrong one; the space holds so
                    // the name column stays a column.
                    Color.clear.frame(width: 42, height: 42)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(move.name).font(.almanacBody).foregroundStyle(Palette.ink)
                    // The best counted set rides on the row, so the list
                    // doubles as a glance at where she stands — the full
                    // history is one chevron away.
                    detailLine(for: move, verdict: verdict, muscles: muscles)
                        .almanacLabel(small: true)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
            }
            .padding(.vertical, 7)
            .contentShape(Rectangle())
            .onTapGesture {
                if picked { selection.remove(move.name) } else { selection.insert(move.name) }
            }
            .overlay(alignment: .trailing) {
                // A way *into* the move, alongside selecting it. Tapping a row
                // here says "I have an opinion about this one", which left the
                // drawing, the cue and the rep history — everything the move
                // sheet holds — reachable only from a session that happened to
                // program it.
                Button { inspecting = move } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Palette.mute)
                        .frame(width: 34, height: 34)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("See \(move.name)")
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(move.name)
        .accessibilityValue([verdict.map(note(for:)) ?? "No opinion", muscles]
            .compactMap(\.self).joined(separator: ", "))
        .accessibilityAddTraits(picked ? [.isButton, .isSelected] : .isButton)
    }

    /// The row's second line. Her opinion replaces the equipment fact, never
    /// the anatomy: the muscles stay on the row beside the verdict — in mute,
    /// so the saffron ink keeps meaning "something she said" — because a
    /// ruled-out move still saying what it worked is exactly what she needs
    /// when choosing its replacement.
    private func detailLine(for move: Move, verdict: MoveVerdict?, muscles: String?) -> Text {
        guard let verdict else {
            return Text([move.equipmentLabel, muscles,
                         bestByMove[MovePreference.key(move.name)].map { "best \($0)" }]
                .compactMap(\.self).joined(separator: " · "))
        }
        var line = Text(note(for: verdict)).foregroundStyle(Palette.saffronInk)
        if let muscles {
            line = line + Text(" · \(muscles)").foregroundStyle(Palette.mute)
        }
        return line
    }

    private var overridesTable: [String: Double] {
        Dictionary(overrides.map { (MovePreference.key($0.moveName), $0.loadPounds) },
                   uniquingKeysWith: { _, last in last })
    }

    /// Best counted set per move, built once per redraw rather than fetched
    /// per row — sixty rows each running their own query is a scroll hitch.
    private var bestByMove: [String: Int] {
        setLogs.reduce(into: [:]) { table, log in
            guard let best = log.reps.max(), best > 0 else { return }
            let key = MovePreference.key(log.moveName)
            table[key] = max(table[key] ?? 0, best)
        }
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

                // One move selected, and its equipment offers a choice: the
                // load is editable here. "Ring halo" on the 5 lb ring stops
                // being challenging long before the move does — the fix is
                // her load on the same move, never a duplicate in the library.
                if selection.count == 1, let name = selection.first,
                   let move = workingMove(named: name),
                   Equipment.loads(for: move).count > 1 {
                    loadBar(for: move)
                        .padding(.horizontal, 20)
                        .padding(.top, 10)
                }

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

    /// The move as the working library knows it — built-in or hers.
    private func workingMove(named name: String) -> Move? {
        let key = MovePreference.key(name)
        return (MoveLibrary.all + customs.filter { $0.status == .approved }.map(\.move))
            .first { MovePreference.key($0.name) == key }
    }

    private func loadBar(for move: Move) -> some View {
        let current = move.applyingLoad(from: overridesTable).loadPounds
        return HStack(spacing: 8) {
            Text("Load")
                .almanacLabel(Palette.mute, small: true)
            ForEach(Equipment.loads(for: move), id: \.self) { pounds in
                let chosen = current == pounds
                Button {
                    MoveOverrides.set(pounds, for: move, in: context)
                    let standard = pounds == move.loadPounds
                    repairNote = standard
                        ? "\(move.name) is back on its standard \(Int(pounds)) lb."
                        : "\(move.name) now asks for \(Int(pounds)) lb — everywhere, including sessions already written."
                } label: {
                    Text("\(Int(pounds)) lb")
                        .font(.almanacBodySmall)
                        .foregroundStyle(chosen ? Palette.oat : Palette.ink)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(chosen ? Palette.ink : Color.clear)
                        .overlay(Rectangle().strokeBorder(chosen ? Palette.ink : Palette.ruleFirm,
                                                          lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(Int(pounds)) pounds")
                .accessibilityAddTraits(chosen ? [.isButton, .isSelected] : .isButton)
            }
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

    private struct Group {
        let number, label, title: String
        let moves: [Move]
        /// Whether the rows carry pattern sub-heads. Flow has no patterns.
        var subheaded = true
    }

    /// Flow first, the way the picker does it: it is the thing she reaches for
    /// daily, and burying it would make the most used part of the library the
    /// hardest to find. Then the strength library by **position** — standing,
    /// then the mat — because that is how a session is lived and where the
    /// choppiness came from (`docs/COACH-BRIEF.md` §6, §8). Inside a
    /// section the rows run in the coach's order, hinge to accessory, with a
    /// sub-head where the pattern changes; the implement is a fact on the
    /// row, no longer a heading. It used to be one section per drawer, which
    /// listed four rows for one movement and said nothing about when in a
    /// session any of them happened.
    private var sections: [Group] {
        // Numbering continues past "Yours" (01), "Target" (02) and
        // "Sampler" (03) above.
        let offset = 3 + numberOffset
        var out: [Group] = []
        if !MoveLibrary.flow.isEmpty, patternFilter == nil {
            out.append(Group(number: String(format: "%02d", offset + 1), label: "Flow",
                             title: "Flow", moves: MoveLibrary.flow, subheaded: false))
        }
        // Her kit only. A drawer she does not have is not a row to scroll
        // past — Settings is where it comes back.
        // Her approved additions file in beside the built-ins once the
        // review has said where they go; one without a position stays in
        // "Your additions" alone.
        let additions = CustomMoves.strength(in: context)
            .filter { MoveTaxonomy.position(for: $0.name) != nil }
        let strength = (MoveLibrary.available + additions)
            .filter { $0.kind == .strength }
            .filter { patternFilter == nil || MoveTaxonomy.pattern(for: $0.name) == patternFilter }
        // Kneeling is its own section, not a sub-head of the mat: the
        // position exists to take the legs out so the trunk holds her up,
        // and that is a thing to be able to find. It still runs inside the
        // floor block of a session, so she goes down once.
        let blocks: [(String, String, (MovePosition) -> Bool)] = [
            ("Standing", "Standing", { $0 == .standing }),
            ("Kneeling", "Kneeling", { $0 == .kneeling }),
            ("Mat", "On the mat", { $0 == .floor }),
        ]
        for (label, title, holds) in blocks {
            let moves = strength.filter { holds(MoveTaxonomy.position(for: $0.name) ?? .standing) }
            guard !moves.isEmpty else { continue }
            out.append(Group(number: String(format: "%02d", offset + out.count + 1),
                             label: label, title: title,
                             moves: MoveLibrary.ordered(moves)))
        }
        return out
    }

    /// The pattern label to print above row `index`, when it begins a new
    /// pattern. Kneeling moves open the mat section and say so.
    private func subhead(at index: Int, in moves: [Move]) -> String? {
        func head(_ move: Move) -> String {
            MoveTaxonomy.pattern(for: move.name)?.label ?? "Hers"
        }
        let now = head(moves[index])
        guard index > 0 else { return now }
        return head(moves[index - 1]) == now ? nil : now
    }

    /// One chip per pattern, the same shape as the muscle chips above. A
    /// chip narrows every section to that pattern; tapping it again clears.
    private var patternChips: some View {
        // Indented to the content column: the marginal index is 18 wide
        // with a 12 gap, the same as `IndexedSection` lays out.
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(MovePattern.allCases, id: \.self) { pattern in
                    let on = patternFilter == pattern
                    Button {
                        patternFilter = on ? nil : pattern
                        // Narrowing to a pattern is asking to see it.
                        if !on { expandedSections.formUnion(["Standing", "Kneeling", "On the mat"]) }
                    } label: {
                        Text(pattern.label)
                            .font(.almanacBodySmall)
                            .foregroundStyle(on ? Palette.oat : Palette.ink)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(on ? Palette.ink : Color.clear)
                            .overlay(Rectangle().strokeBorder(on ? Palette.ink : Palette.ruleFirm,
                                                              lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
                }
            }
            .padding(.horizontal, 1)
        }
        .padding(.leading, 30)
        .padding(.bottom, -4)
    }
}
