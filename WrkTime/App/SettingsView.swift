import SwiftData
import SwiftUI

/// The document register, applied to the things you set once and forget.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @AppStorage("cueSoundEnabled") private var soundEnabled = true
    /// Seconds since the reference date; `Date` is not an `AppStorage` type.
    @AppStorage("lastBackupAt") private var lastBackupAt = 0.0

    @State private var apiKey = ""
    @State private var keyIsStored = false
    @State private var showingKey = false

    @Query(sort: \Block.startDate, order: .reverse) private var blocks: [Block]
    @State private var replanning = false
    @State private var planResult: String?
    @State private var planFailed = false

    @State private var exporting = false
    @State private var importing = false
    @State private var archive: ArchiveDocument?
    @State private var note: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Masthead(context: "Settings")
                        .padding(.top, 4)

                    IndexedSection(number: "01", label: "Cues") {
                        SectionHead(title: "Sound", note: soundEnabled ? "On" : "Off")
                            .padding(.bottom, 10)
                        Toggle(isOn: $soundEnabled) {
                            Text("Interval cues")
                                .font(.almanacBody)
                                .foregroundStyle(Palette.ink)
                        }
                        .tint(Palette.moss)
                        Text("Cues play over your music rather than pausing it, and they sound through the silent switch. Nothing here takes over the lock screen controls — those keep working for whatever you are listening to.")
                            .font(.almanacBodySmall)
                            .foregroundStyle(Palette.mute)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 8)
                    }

                    IndexedSection(number: "02", label: "Backup") {
                        SectionHead(title: "Your record", note: lastBackupNote)
                            .padding(.bottom, 10)
                        Text("Sync keeps this on your other devices, but it is a mirror, not a backup — a deletion syncs too. Save a copy you hold yourself. Restoring only ever adds; it never removes anything you have done since.")
                            .font(.almanacBodySmall)
                            .foregroundStyle(Palette.mute)
                            .fixedSize(horizontal: false, vertical: true)

                        PrimaryButton(title: "Save a backup", subtitle: nil) { beginExport() }
                            .padding(.top, 14)

                        Button { importing = true } label: {
                            HStack {
                                Text("Restore from a file")
                                    .font(.almanacButton)
                                    .foregroundStyle(Palette.ink)
                                Spacer()
                                Image(systemName: "arrow.down.doc")
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(Palette.moss)
                            }
                            .padding(.vertical, 14)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Rule()

                        if let note {
                            Text(note)
                                .font(.almanacBodySmall)
                                .foregroundStyle(Palette.mute)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.top, 10)
                        }
                    }

                    IndexedSection(number: "03", label: "Planner") {
                        SectionHead(title: "Claude API key",
                                    note: keyIsStored ? "Stored" : "Not set")
                            .padding(.bottom, 10)

                        HStack(spacing: 10) {
                            Group {
                                if showingKey {
                                    TextField("sk-ant-…", text: $apiKey)
                                } else {
                                    SecureField("sk-ant-…", text: $apiKey)
                                }
                            }
                            .font(Face.ui(15))
                            .foregroundStyle(Palette.ink)
                            .textFieldStyle(.plain)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .accessibilityLabel("Claude API key")

                            Button { showingKey.toggle() } label: {
                                Image(systemName: showingKey ? "eye.slash" : "eye")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(Palette.mute)
                                    .contentShape(Rectangle().inset(by: -10))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(showingKey ? "Hide key" : "Show key")
                        }
                        .padding(.vertical, 8)
                        Rule(firm: true)

                        Text("Kept in the Keychain on this device only. It is never written into a backup file, never synced, and never logged. Set a spend limit on the key in the Anthropic console — a key that leaks costs money rather than privacy.")
                            .font(.almanacBodySmall)
                            .foregroundStyle(Palette.mute)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 10)

                        HStack(spacing: 12) {
                            PrimaryButton(title: "Save key", subtitle: nil) { saveKey() }
                            if keyIsStored {
                                Button("Remove") { removeKey() }
                                    .font(.almanacButton)
                                    .foregroundStyle(Palette.mute)
                            }
                        }
                        .padding(.top, 14)
                    }

                    IndexedSection(number: "04", label: "Week") {
                        SectionHead(title: "Rewrite this week", note: planNote)
                            .padding(.bottom, 10)

                        Text("Writes this week again from your attendance so far. Sessions you have already finished are kept — only what is still ahead is replaced. With a key set this asks Claude and costs one request; without one it is written from the plan's own rules.")
                            .font(.almanacBodySmall)
                            .foregroundStyle(Palette.mute)
                            .fixedSize(horizontal: false, vertical: true)

                        PrimaryButton(title: replanning ? "Writing…" : "Rewrite the week",
                                      subtitle: nil) { replan() }
                            .padding(.top, 14)
                            .disabled(replanning)

                        if let planResult {
                            Text(planResult)
                                .font(.almanacBodySmall)
                                .foregroundStyle(planFailed ? Palette.saffronInk : Palette.mute)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.top, 12)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 28)
            }
            .background(Palette.oat.ignoresSafeArea())
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.foregroundStyle(Palette.ink)
                }
            }
        }
        .task { keyIsStored = KeychainStore.has(.claudeAPIKey) }
        .fileExporter(isPresented: $exporting,
                      document: archive,
                      contentType: .almanacArchive,
                      defaultFilename: archive?.archive.suggestedFilename) { result in
            switch result {
            case .success:
                lastBackupAt = Date.now.timeIntervalSinceReferenceDate
                note = "Backup saved."
            case .failure(let error): note = "Could not save the backup. \(error.localizedDescription)"
            }
        }
        .fileImporter(isPresented: $importing,
                      allowedContentTypes: [.almanacArchive, .json]) { result in
            handleImport(result)
        }
    }

    // MARK: - Actions

    /// Says when, and how long ago, without nagging. A backup you have not
    /// taken in two months is worth noticing; a banner about it is not.
    private var lastBackupNote: String {
        guard lastBackupAt > 0 else { return "Never saved" }
        let date = Date(timeIntervalSinceReferenceDate: lastBackupAt)
        let days = Calendar.current.dateComponents([.day],
                                                   from: Calendar.current.startOfDay(for: date),
                                                   to: Calendar.current.startOfDay(for: .now)).day ?? 0
        switch days {
        case 0: return "Saved today"
        case 1: return "Saved yesterday"
        default: return "Saved \(days) days ago"
        }
    }

    private func beginExport() {
        do {
            archive = ArchiveDocument(archive: try ArchiveService.export(from: context))
            exporting = true
        } catch {
            note = "Could not read the store to back it up."
        }
    }

    private func handleImport(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            // A file chosen from another app's container is security-scoped.
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }

            let decoded = try Archive.decoder.decode(Archive.self, from: try Data(contentsOf: url))
            let summary = try ArchiveService.restore(decoded, into: context)
            note = summary.added == 0
                ? "Nothing new in that file — everything in it was already here."
                : "Restored \(summary.added) \(summary.added == 1 ? "record" : "records")."
        } catch {
            note = "That file could not be read as an Almanac backup."
        }
    }

    private var planNote: String {
        guard let block = blocks.first else { return "No block" }
        return "Week \(block.currentWeek)"
    }

    /// Rewrites the current week. This is the one place the planner can be run
    /// on demand — everywhere else it runs only when a week is found empty,
    /// which is right for normal use and useless for finding out whether the
    /// key you just pasted actually works.
    private func replan() {
        guard let block = blocks.first, !replanning else { return }
        replanning = true
        planResult = nil

        Task {
            let outcome = await PlannerService.planWeek(block.currentWeek, of: block, in: context)
            replanning = false

            switch outcome.source {
            case .claude:
                planFailed = false
                planResult = "Claude wrote \(outcome.sessionsWritten) sessions. “\(outcome.explanation)”"
            case .offline(let reason):
                // Only a failure if she was expecting Claude to answer.
                planFailed = KeychainStore.has(.claudeAPIKey)
                planResult = reason ?? "Written from the plan's own rules."
            }
        }
    }

    private func saveKey() {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        KeychainStore.save(trimmed, for: .claudeAPIKey)
        keyIsStored = KeychainStore.has(.claudeAPIKey)
        // Cleared from the field once it is in the Keychain; the stored value
        // is never read back into the UI.
        apiKey = ""
        showingKey = false
    }

    private func removeKey() {
        KeychainStore.remove(.claudeAPIKey)
        keyIsStored = false
        apiKey = ""
    }
}
