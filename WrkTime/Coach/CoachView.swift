import SwiftUI
import SwiftData

/// The conversation with the coach. A document screen: her words and the
/// coach's in two registers of the same type, a proposal as a card with two
/// plain actions, the cost of the conversation in a mono line at the foot.
///
/// Every send is a request she is paying for, and she presses the button
/// herself — that is the approval, every time. Nothing here calls the API
/// on its own.
struct CoachView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \CoachMessage.date) private var turns: [CoachMessage]
    @Query private var blocks: [Block]

    @State private var draft = ""
    @State private var sending = false
    @State private var failure: String?
    @State private var keyIsStored = false
    /// The line shown after a proposal is acted on, by proposal id.
    @State private var outcomes: [String: String] = [:]
    @FocusState private var composing: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            header
                            if turns.isEmpty { opening }
                            ForEach(turns) { turn in
                                turnView(turn).id(turn.id)
                            }
                            if sending {
                                Text("Thinking it over.")
                                    .almanacLabel(Palette.mute, small: true)
                                    .padding(.vertical, 14)
                            }
                            if let failure {
                                Text(failure)
                                    .font(.almanacBodySmall)
                                    .foregroundStyle(Palette.saffronInk)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .padding(.vertical, 10)
                            }
                            Color.clear.frame(height: 1).id("end")
                        }
                        .padding(.horizontal, 22)
                        .padding(.bottom, 12)
                    }
                    .onChange(of: turns.count) { _, _ in
                        withAnimation { proxy.scrollTo("end", anchor: .bottom) }
                    }
                    .onAppear { proxy.scrollTo("end", anchor: .bottom) }
                }
                composer
            }
            .background(Palette.oat.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.foregroundStyle(Palette.ink)
                }
            }
        }
        .task { keyIsStored = KeychainStore.has(.claudeAPIKey) }
    }

    // MARK: - Parts

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("The coach")
                .font(.almanacTitle)
                .foregroundStyle(Palette.ink)
                .accessibilityAddTraits(.isHeader)
            Text(costLine).almanacLabel(Palette.mute, small: true)
            Rule(firm: true).padding(.top, 10)
        }
        .padding(.top, 4)
    }

    private var opening: some View {
        Text("The same coach that writes your week, with your numbers in front of it. Ask about a move, a load, a session that went badly, what the 35 is for. It can propose a load change or ruling a move out — as a card you tap, never on its own. Each message is one request, about a cent or two.")
            .font(.almanacBody)
            .foregroundStyle(Palette.mute)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, 16)
    }

    private func turnView(_ turn: CoachMessage) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(turn.isHers ? "You" : "Coach")
                .almanacLabel(turn.isHers ? Palette.mute : Palette.moss, small: true)
            if !turn.text.isEmpty {
                Text(turn.text)
                    .font(.almanacBody)
                    .foregroundStyle(turn.isHers ? Palette.mute : Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(turn.proposals) { proposal in
                proposalCard(proposal, in: turn)
            }
            Rule().padding(.top, 10)
        }
        .padding(.top, 14)
    }

    /// A proposal is offered, never applied: two plain actions, and once one
    /// is taken the card says what happened and stays as the record.
    private func proposalCard(_ proposal: CoachProposal, in turn: CoachMessage) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(proposal.title)
                .font(.almanacMoveName)
                .foregroundStyle(Palette.ink)
            switch proposal.outcome {
            case .pending:
                HStack(spacing: 10) {
                    Button("Do it") { act(on: proposal, in: turn, applied: true) }
                        .font(.almanacBody)
                        .foregroundStyle(Palette.oat)
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        .background(Palette.ink)
                    Button("Not now") { act(on: proposal, in: turn, applied: false) }
                        .font(.almanacBody)
                        .foregroundStyle(Palette.ink)
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        .overlay(Rectangle().strokeBorder(Palette.ruleFirm, lineWidth: 1))
                }
                .buttonStyle(.plain)
            case .applied:
                Text(outcomes[proposal.id] ?? "Done.")
                    .font(.almanacBodySmall)
                    .foregroundStyle(Palette.saffronInk)
                    .fixedSize(horizontal: false, vertical: true)
            case .declined:
                Text("Left as it was.").almanacLabel(Palette.mute, small: true)
            }
        }
        .padding(12)
        .overlay(Rectangle().strokeBorder(Palette.ruleFirm, lineWidth: 1))
        .padding(.top, 6)
    }

    private var composer: some View {
        VStack(spacing: 0) {
            Rule(firm: true)
            if !keyIsStored {
                Text("No API key is set. Add one in Settings to talk to the coach.")
                    .font(.almanacBodySmall)
                    .foregroundStyle(Palette.mute)
                    .padding(.vertical, 14)
                    .padding(.horizontal, 22)
            } else {
                HStack(alignment: .bottom, spacing: 12) {
                    TextField("Ask the coach", text: $draft, axis: .vertical)
                        .font(.almanacBody)
                        .foregroundStyle(Palette.ink)
                        .textFieldStyle(.plain)
                        .lineLimit(1...5)
                        .focused($composing)
                        .submitLabel(.send)
                        .onSubmit(send)
                    Button(action: send) {
                        Text("Send")
                            .font(.almanacBody)
                            .foregroundStyle(canSend ? Palette.oat : Palette.mute)
                            .padding(.horizontal, 14).padding(.vertical, 9)
                            .background(canSend ? Palette.ink : Color.clear)
                            .overlay(Rectangle().strokeBorder(canSend ? Palette.ink : Palette.ruleFirm,
                                                              lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSend)
                    .accessibilityHint("Sends one request")
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 12)
            }
        }
        .background(Palette.oat)
    }

    // MARK: - Behaviour

    private var canSend: Bool {
        !sending && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var costLine: String {
        let usage = turns.reduce(into: ClaudePlanner.Usage()) {
            $0.inputTokens += $1.inputTokens; $0.outputTokens += $1.outputTokens
        }
        let requests = turns.filter { !$0.isHers }.count
        guard requests > 0 else { return "Nothing asked yet" }
        return String(format: "%d %@ · $%.2f", requests, requests == 1 ? "request" : "requests", usage.dollars)
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !sending else { return }
        draft = ""
        failure = nil
        sending = true
        // Read off the model objects on the main actor before the request
        // leaves it: the wire shape is plain data, the rows are not Sendable.
        let wire = (try? JSONSerialization.data(withJSONObject: CoachChat.messages(from: turns))) ?? Data("[]".utf8)
        let planContext = currentContext()
        let hers = CoachMessage(role: "user", text: text)
        context.insert(hers)
        try? context.save()

        Task {
            do {
                let reply = try await CoachChat().reply(to: text, priorMessages: wire, context: planContext)
                let answer = CoachMessage(role: "assistant", text: reply.text)
                answer.proposals = reply.proposals
                answer.inputTokens = reply.usage.inputTokens
                answer.outputTokens = reply.usage.outputTokens
                context.insert(answer)
                try? context.save()
            } catch {
                failure = error.localizedDescription
            }
            sending = false
        }
    }

    /// What the planner would be told today, so the two coaches are one.
    private func currentContext() -> PlanContext {
        guard let block = blocks.first else {
            return PlanContext(weekNumber: 1, pace: .steady, recent: [], loggedSets: [])
        }
        return PlannerService.context(for: block, weekNumber: block.currentWeek, in: context)
    }

    private func act(on proposal: CoachProposal, in turn: CoachMessage, applied: Bool) {
        var proposals = turn.proposals
        guard let index = proposals.firstIndex(where: { $0.id == proposal.id }) else { return }
        if applied {
            outcomes[proposal.id] = CoachActions.apply(proposal, in: context)
            proposals[index].outcome = .applied
            Haptics.transport()
        } else {
            proposals[index].outcome = .declined
        }
        turn.proposals = proposals
        try? context.save()
    }
}
