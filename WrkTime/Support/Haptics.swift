import UIKit

/// Interval cues you can feel without looking.
///
/// The pattern matters: work starting is a firm single tap, rest is a softer
/// one, and the last three seconds of work tick so you can brace for the change
/// with the phone face-down on the floor.
enum Haptics {
    private static let impactHeavy = UIImpactFeedbackGenerator(style: .heavy)
    private static let impactLight = UIImpactFeedbackGenerator(style: .light)
    private static let notification = UINotificationFeedbackGenerator()

    static func prepare() {
        impactHeavy.prepare()
        impactLight.prepare()
    }

    static func workBegan() {
        impactHeavy.impactOccurred()
        impactHeavy.prepare()
    }

    static func restBegan() {
        impactLight.impactOccurred(intensity: 0.7)
        impactLight.prepare()
    }

    static func countdownTick() {
        impactLight.impactOccurred(intensity: 0.45)
    }

    static func transport() {
        impactLight.impactOccurred(intensity: 0.6)
    }

    static func sessionComplete() {
        notification.notificationOccurred(.success)
    }

    /// Wire an engine's phase changes to the right cue.
    static func bind(to engine: IntervalEngine) {
        prepare()
        engine.onPhaseChange = { phase in
            guard let phase else { return }
            phase.isWork ? workBegan() : restBegan()
        }
        engine.onFinish = { sessionComplete() }
    }
}
