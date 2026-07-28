import Foundation
import SwiftData

/// Decides whether a week is worth asking Claude about.
///
/// The app used to call the model every single week, which is the expensive
/// habit and the least examined one. It is worth stating plainly what the model
/// is actually for here: **adaptation**. The progression itself — rest
/// shortening, rounds climbing, work lengthening toward the ceiling — is
/// arithmetic, and `OfflinePlanner` does it correctly and for nothing. What a
/// model adds is judgement about things that changed: sessions she missed,
/// recovery that dipped, a move she ruled out, a trend that turned.
///
/// So the rule is: **ask when there is something to adapt to.** A clean week
/// with nothing new to say produces the same shape either way, and paying
/// twenty to forty cents to be told the arithmetic is what the app already
/// knows is not thrift, it is inattention.
///
/// This is never a cap or a quota. Every reason below is a real signal, and if
/// one is present the model is asked without hesitation — a week that should be
/// adapted and is not is a much worse outcome than a week that cost money.
@MainActor
enum PlanTrigger {

    /// Why a week is being written the way it is, in words fit to show her.
    struct Decision {
        var asksClaude: Bool
        var reason: String
    }

    /// How often to ask regardless, so a long clean run cannot drift away from
    /// the model's judgement entirely.
    static let everyNWeeks = 4

    /// `hasKey` is a parameter rather than a lookup so this is testable: whether
    /// a Keychain happens to hold a key is not something a test should depend on.
    static func decide(week: Int, of block: Block, in context: ModelContext,
                       hasKey: Bool = KeychainStore.has(.claudeAPIKey)) -> Decision {
        guard hasKey else {
            return Decision(asksClaude: false, reason: "No key is set, so this week came from the plan's own rules.")
        }

        // Week one has nothing to progress from — it is the only week that is
        // written rather than stepped.
        if week <= 1 {
            return Decision(asksClaude: true, reason: "The first week of a block is always written fresh.")
        }

        if let missed = missedRecently(of: block), missed > 0 {
            return Decision(asksClaude: true,
                            reason: missed == 1
                                ? "A session went undone in the last fortnight, so this week was written around it."
                                : "\(missed) sessions went undone in the last fortnight, so this week was written around them.")
        }

        if changedPreferences(since: block, in: context) {
            return Decision(asksClaude: true,
                            reason: "You told the plan something new about a move, so this week was written again.")
        }

        if (week - 1) % everyNWeeks == 0 {
            return Decision(asksClaude: true,
                            reason: "A check-in week — the plan is looked at properly every \(everyNWeeks) weeks.")
        }

        return Decision(asksClaude: false,
                        reason: "Nothing changed, so this week steps on from the last rather than being written again.")
    }

    /// Sessions scheduled in the last fortnight that were never finished.
    private static func missedRecently(of block: Block) -> Int? {
        let fortnightAgo = Date.now.addingTimeInterval(-14 * 86_400)
        return (block.sessions ?? []).filter {
            $0.scheduledFor >= fortnightAgo && $0.scheduledFor < .now && !$0.isComplete
        }.count
    }

    /// Whether an opinion about a move was recorded since the last plan was
    /// written. Preferences carry `updatedAt`, so this is a lookup rather than
    /// a diff.
    private static func changedPreferences(since block: Block, in context: ModelContext) -> Bool {
        guard let lastPlanned = UserDefaults.standard.object(forKey: Memo.lastAsked) as? Date
        else { return true }
        return MovePreferences.all(in: context).contains { $0.updatedAt > lastPlanned }
    }

    enum Memo {
        static let lastAsked = "lastAskedClaudeAt"
        static let callsMade = "claudeCallsMade"
        static let inputTokens = "claudeInputTokens"
        static let outputTokens = "claudeOutputTokens"
    }

    /// Adds what a request actually cost, read from the response.
    ///
    /// Every number the app has shown about cost until now was an estimate off
    /// the back of an envelope. The response carries the real counts, so there
    /// is no reason to guess — and a decision about `effort` or a model tier is
    /// only worth making against measurements.
    static func record(_ usage: ClaudePlanner.Usage) {
        let defaults = UserDefaults.standard
        defaults.set(defaults.integer(forKey: Memo.inputTokens) + usage.inputTokens,
                     forKey: Memo.inputTokens)
        defaults.set(defaults.integer(forKey: Memo.outputTokens) + usage.outputTokens,
                     forKey: Memo.outputTokens)
    }

    /// Everything the app has spent on her key, from the responses themselves.
    static var spent: ClaudePlanner.Usage {
        ClaudePlanner.Usage(
            inputTokens: UserDefaults.standard.integer(forKey: Memo.inputTokens),
            outputTokens: UserDefaults.standard.integer(forKey: Memo.outputTokens))
    }

    /// Notes that a request was actually made, for the counter in Settings and
    /// so preference changes are measured against the right moment.
    static func recordCall() {
        let defaults = UserDefaults.standard
        defaults.set(Date.now, forKey: Memo.lastAsked)
        defaults.set(defaults.integer(forKey: Memo.callsMade) + 1, forKey: Memo.callsMade)
    }

    static var callsMade: Int { UserDefaults.standard.integer(forKey: Memo.callsMade) }
}
