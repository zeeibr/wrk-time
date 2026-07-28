import UIKit

/// Interval cues you can feel without looking.
///
/// The pattern matters: work starting is a firm single tap, rest is a softer
/// one, and the last three seconds of work tick so you can brace for the change
/// with the phone face-down on the floor.
@MainActor
enum Haptics {
    private static let impactHeavy = UIImpactFeedbackGenerator(style: .heavy)
    private static let impactLight = UIImpactFeedbackGenerator(style: .light)
    private static let impactSoft = UIImpactFeedbackGenerator(style: .soft)
    private static let impactRigid = UIImpactFeedbackGenerator(style: .rigid)
    private static let notification = UINotificationFeedbackGenerator()

    static func prepare() {
        impactHeavy.prepare()
        impactLight.prepare()
        impactSoft.prepare()
        impactRigid.prepare()
        // The completion beat is the one that must not arrive late, so its
        // generator is warmed with the others rather than on first use.
        notification.prepare()
    }

    static func workBegan() {
        impactHeavy.impactOccurred()
        impactHeavy.prepare()
    }

    static func restBegan() {
        impactLight.impactOccurred(intensity: 0.7)
        impactLight.prepare()
    }

    /// A flow movement beginning. Softer than rest, because the practice is the
    /// one part of a session that should not feel like a boundary being
    /// crossed — the vocabulary says *carry on*, not *go*.
    static func flowBegan() {
        impactSoft.impactOccurred(intensity: 0.45)
        impactSoft.prepare()
    }

    static func countdownTick() {
        impactLight.impactOccurred(intensity: 0.45)
        // Re-warm, or the second and third ticks of a three-tick run arrive
        // noticeably later than the first.
        impactLight.prepare()
    }

    /// Held. One soft press — the lightest thing in the vocabulary, because
    /// nothing has happened to the workout except that it stopped.
    static func paused() {
        impactSoft.impactOccurred(intensity: 0.55)
        impactSoft.prepare()
    }

    /// Picked back up. The lead-in motif, foreshortened: two quick taps that
    /// say *starting again* rather than *stopping*.
    static func resumed() {
        impactLight.impactOccurred(intensity: 0.40)
        impactLight.prepare()
        Task {
            try? await Task.sleep(for: .milliseconds(85))
            impactLight.impactOccurred(intensity: 0.55)
            impactLight.prepare()
        }
    }

    /// Moved through time. Firm then light, in that order — a shove and a
    /// settle, which feels like travel rather than like a button.
    ///
    /// Pause and skip used to share one cue, so the two actions with the most
    /// different consequences felt identical under the thumb.
    static func skipped() {
        impactRigid.impactOccurred(intensity: 0.70)
        impactRigid.prepare()
        Task {
            try? await Task.sleep(for: .milliseconds(70))
            impactLight.impactOccurred(intensity: 0.35)
            impactLight.prepare()
        }
    }

    /// A plain acknowledgement, for controls with no consequence to describe.
    static func transport() {
        impactLight.impactOccurred(intensity: 0.6)
        impactLight.prepare()
    }

    static func sessionComplete() {
        notification.notificationOccurred(.success)
    }

}

/// The cue policy, in one place.
///
/// Felt and heard cues are the same vocabulary in two channels, so they are
/// bound together rather than by two different callers competing for the
/// engine's single-assignment closures. Which channel reaches you depends on
/// where the phone is: haptics while it is in your hand, sound once it is on
/// the floor with the screen off.
@MainActor
struct SessionCues {
    let audio: SessionAudio

    func bind(to engine: IntervalEngine) {
        Haptics.prepare()
        let lastRound = engine.routine.roundCount

        engine.onPhaseChange = { phase in
            guard let phase else { return }
            switch phase.kind {
            // The practice gets the quietest cue in the vocabulary. Announcing
            // a spinal wave with the same thud that starts a deadlift would
            // undo in one beat everything `MoveKind` exists to protect.
            case .flow:
                Haptics.flowBegan()
                audio.play(.rest)
            case .work:
                Haptics.workBegan()
                // Doubled on the last round. "This is the final one" said in
                // the cue language rather than in copy.
                audio.play(phase.round == lastRound ? .finalRound : .work)
            case .rest:
                Haptics.restBegan()
                audio.play(.rest)
            }
        }

        engine.onCountdownTick = {
            Haptics.countdownTick()
            audio.play(.tick)
        }

        // Silence is the right acknowledgement of a session you walked away
        // from. The register has already changed; that is acknowledgement
        // enough, and a success chime for quitting would be a small lie.
        engine.onFinish = { reason in
            guard reason == .completed else { return }
            Haptics.sessionComplete()
            audio.play(.complete)
        }
    }
}
