import AVFoundation
import Foundation

/// Interval cues you can hear without looking, over whatever you're playing.
///
/// Audio matters more here than it looks. `UIFeedbackGenerator` and CoreHaptics
/// are both suppressed while the app is not foreground, so the moment the phone
/// is face-down on the floor with the screen off, **sound is the only cue
/// channel left**. It is also the only one that works if System Haptics are
/// switched off, which an app cannot detect.
///
/// ## Playing alongside Spotify
///
/// The session is `.playback` with `.mixWithOthers`, and it deliberately does
/// **not** take the Now Playing slot: nothing here sets `MPNowPlayingInfoCenter`
/// or claims `MPRemoteCommandCenter`. Two consequences, both wanted. Music from
/// Spotify, Apple Music or anything else keeps playing straight through a
/// session, and the Lock Screen, Control Centre and AirPods controls go on
/// controlling *that* app rather than this one.
///
/// `.duckOthers` is deliberately absent. It ducks for as long as this session is
/// active — not just while a cue sounds — so a whole workout would play under
/// dipped music. The cues are pitched and shaped to carry over a mix instead.
///
/// Tones are synthesised at launch rather than shipped as files: a handful of
/// decaying sines with a little second harmonic, which reads as wooden rather
/// than as an alarm. Nothing here should sound like a notification.
@MainActor
final class SessionAudio {
    /// The cue vocabulary. It is a language, not a set of one-offs: dry
    /// ascending ticks always mean *a boundary is three seconds away*, and a
    /// doubled tone always means *this is the last one*.
    enum Cue {
        case tick           // lead-in, and the last three seconds of work
        case work
        case rest
        case finalRound     // the work tone, doubled
        case complete
    }

    /// Off is a real setting. `.playback` plays through the silent switch, and
    /// doing that without a visible way to stop it is rude.
    var isEnabled = true

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
    private var buffers: [Cue: AVAudioPCMBuffer] = [:]
    private var running = false

    init() {
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        buffers = [
            // Quiet, dry, and high enough to sit above a mix without shouting.
            .tick: render([Hit(at: 0, hz: 880, seconds: 0.07, level: 0.30)]),
            // Low and firm — a thud with weight, not a bare click.
            .work: render([Hit(at: 0, hz: 196, seconds: 0.34, level: 0.75)]),
            // A fifth up, shorter and softer. Round, not sharp.
            .rest: render([Hit(at: 0, hz: 294, seconds: 0.22, level: 0.45)]),
            // Doubling says "last one" without a word of copy.
            .finalRound: render([Hit(at: 0, hz: 196, seconds: 0.34, level: 0.75),
                                 Hit(at: 0.10, hz: 196, seconds: 0.34, level: 0.75)]),
            // Three descending notes that settle. A fanfare would be the wrong
            // register for this app entirely.
            .complete: render([Hit(at: 0, hz: 392, seconds: 0.34, level: 0.50),
                               Hit(at: 0.22, hz: 330, seconds: 0.34, level: 0.50),
                               Hit(at: 0.44, hz: 262, seconds: 0.70, level: 0.50)])
        ]
    }

    // MARK: - Lifetime

    /// Open the audio session for the length of a workout.
    func begin() {
        guard !running else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
            try engine.start()
            player.play()
            running = true
        } catch {
            // No cues is a degraded session, not a broken one. The field, the
            // count and the haptics all still work.
            running = false
        }
    }

    func end() {
        guard running else { return }
        player.stop()
        engine.stop()
        // Tells Spotify it may return to full volume, if anything ever ducks it.
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        running = false
    }

    func play(_ cue: Cue) {
        guard isEnabled, running, let buffer = buffers[cue] else { return }
        player.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
    }

    // MARK: - Synthesis

    private struct Hit {
        let at: Double
        let hz: Double
        let seconds: Double
        let level: Double
    }

    private func render(_ hits: [Hit]) -> AVAudioPCMBuffer {
        let rate = format.sampleRate
        let span = (hits.map { $0.at + $0.seconds }.max() ?? 0) + 0.05
        let frames = AVAudioFrameCount(span * rate)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames

        let samples = buffer.floatChannelData![0]
        for index in 0..<Int(frames) { samples[index] = 0 }

        for hit in hits {
            let start = Int(hit.at * rate)
            let count = Int(hit.seconds * rate)
            for n in 0..<count {
                let t = Double(n) / rate
                // Exponential decay with a very short attack: struck, not swelled.
                let attack = min(1, t / 0.004)
                let decay = exp(-t / (hit.seconds * 0.26))
                let tone = sin(2 * .pi * hit.hz * t) * 0.82
                         + sin(4 * .pi * hit.hz * t) * 0.18
                let index = start + n
                if index < Int(frames) {
                    samples[index] += Float(tone * attack * decay * hit.level)
                }
            }
        }
        return buffer
    }
}
