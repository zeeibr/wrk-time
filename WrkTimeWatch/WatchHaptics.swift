import WatchKit

/// The interval cues, on the wrist.
///
/// The same vocabulary as the phone's `Haptics`, method for method, so the
/// engine's callbacks bind identically on both devices and neither can grow a
/// cue the other has never heard of. What changes is the instrument: the
/// phone shapes its own taps from impact generators at chosen intensities,
/// while watchOS offers a fixed set of named haptics and plays them through
/// the Taptic Engine. So each phone cue is matched to the watch haptic that
/// says the same thing, rather than to the one with the nearest name.
///
/// There is no audio on the watch. The phone sounds cues because it spends
/// the session on the floor with the screen off; the watch is on the arm that
/// is lifting, and a wrist tap is already the channel that reaches her.
@MainActor
enum WatchHaptics {
    private static func play(_ type: WKHapticType) {
        WKInterfaceDevice.current().play(type)
    }

    /// Nothing to warm. The phone prepares its impact generators because a
    /// cold one arrives late; watchOS owns the engine and its own warm-up.
    /// Kept so the two vocabularies are the same list, and so a caller can
    /// bind either without knowing which device it is on.
    static func prepare() {}

    /// Work starting. `.start` is watchOS's own "a timed thing begins" — the
    /// firmest single tap in the set, which is what the phone's heavy impact
    /// is for.
    static func workBegan() { play(.start) }

    /// Work ending. `.stop` is its pair, and pairing them is the point: the
    /// two boundaries of a round should feel like two ends of one thing.
    static func restBegan() { play(.stop) }

    /// A flow movement beginning. The quietest thing in the set, because the
    /// practice is the one part of a session that should not feel like a
    /// boundary being crossed — the vocabulary says *carry on*, not *go*.
    /// `.click` is the softest single tap watchOS offers.
    static func flowBegan() { play(.click) }

    /// Each of the last three seconds of work. `.directionUp` is the ascending
    /// tick, and the motif is the whole reason it is used here: three dry
    /// rising taps always mean *a boundary is three seconds away*, on the
    /// wrist exactly as in the hand.
    static func countdownTick() { play(.directionUp) }

    /// Held. A plain click: nothing has happened to the workout except that
    /// it stopped, and `.stop` is already spoken for by the end of a round.
    static func paused() { play(.click) }

    /// Picked back up. The lead-in motif foreshortened — two quick clicks
    /// that say *starting again* rather than *stopping*, as on the phone.
    static func resumed() {
        play(.click)
        Task {
            try? await Task.sleep(for: .milliseconds(85))
            play(.click)
        }
    }

    /// Moved through time. `.retry` is watchOS's "that went somewhere else"
    /// double beat, and skipping needs to feel unlike pausing under the
    /// thumb: the two actions with the most different consequences must not
    /// share a cue.
    static func skipped() { play(.retry) }

    /// A plain acknowledgement, for controls with no consequence to describe.
    static func transport() { play(.click) }

    /// The session run to the end. The one celebratory beat in the app, and
    /// the only place `.success` is used.
    static func sessionComplete() { play(.success) }
}

/// The cue policy on the watch, in one place.
///
/// The same shape as the phone's `SessionCues.bind(to:)` — one function that
/// owns every one of the engine's single-assignment cue closures — so the two
/// devices cue the same session the same way and no caller has to remember
/// which callbacks exist. There is no audio channel here, so this is the
/// haptic half of that vocabulary and nothing else.
@MainActor
struct WatchSessionCues {
    func bind(to engine: IntervalEngine) {
        WatchHaptics.prepare()

        engine.onPhaseChange = { phase in
            guard let phase else { return }
            switch phase.kind {
            case .flow: WatchHaptics.flowBegan()
            case .work: WatchHaptics.workBegan()
            case .rest: WatchHaptics.restBegan()
            }
        }

        engine.onCountdownTick = { WatchHaptics.countdownTick() }

        // Silence is the right acknowledgement of a session she walked away
        // from. The register has already changed; a success beat for quitting
        // would be a small lie told to her wrist.
        engine.onFinish = { reason in
            guard reason == .completed else { return }
            WatchHaptics.sessionComplete()
        }
    }
}
