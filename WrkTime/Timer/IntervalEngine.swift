import Foundation
import Observation

/// Drives a routine against wall-clock time.
///
/// The engine never accumulates decrements. It records when the routine started
/// and how long it has been paused, then derives everything from
/// `elapsed = now - start - pausedTotal` against the precomputed schedule. A
/// dropped tick, a backgrounded app, or a slow frame therefore cannot make the
/// count wrong — the next tick simply reports the truth.
@Observable
final class IntervalEngine {
    enum Status: Equatable { case idle, running, paused, finished }

    private(set) var routine: IntervalRoutine
    private(set) var schedule: RoutineSchedule
    private(set) var status: Status = .idle

    /// Re-read on every tick so the view updates; derived, never stored state.
    private(set) var elapsed: TimeInterval = 0

    /// Injectable so tests can drive time without waiting for it.
    private let now: () -> Date
    /// Tests drive `refresh()` by hand; a live ticker would race the fake clock.
    private let autoTick: Bool

    private var startDate: Date?
    private var pausedTotal: TimeInterval = 0
    private var pauseBegan: Date?
    /// Seconds skipped forward past the natural schedule.
    private var skipOffset: TimeInterval = 0

    private var ticker: Task<Void, Never>?

    /// Fires once per phase boundary, for haptics and audio cues.
    var onPhaseChange: ((Phase?) -> Void)?
    var onFinish: (() -> Void)?

    private var lastNotifiedIndex: Int??

    init(routine: IntervalRoutine,
         now: @escaping () -> Date = Date.init,
         autoTick: Bool = true) {
        self.routine = routine
        self.schedule = routine.schedule
        self.now = now
        self.autoTick = autoTick
    }

    // MARK: - Derived state

    var currentIndex: Int? { schedule.index(atElapsed: elapsed) }

    var currentPhase: Phase? {
        currentIndex.map { schedule.phases[$0] }
    }

    /// Seconds left in the current phase, rounded up so the display shows
    /// "0:01" for the whole final second rather than flicking to zero early.
    var remainingInPhase: TimeInterval {
        guard let phase = currentPhase else { return 0 }
        return max(0, phase.end - elapsed)
    }

    var remainingInRoutine: TimeInterval {
        max(0, schedule.total - elapsed)
    }

    /// 0 at the start of the phase, 1 at its end. This is what the draining
    /// field is bound to.
    var phaseProgress: Double {
        guard let phase = currentPhase, phase.duration > 0 else { return 0 }
        return min(1, max(0, (elapsed - phase.start) / phase.duration))
    }

    /// The fraction of the phase still to come — the height of the field.
    var phaseRemainingFraction: Double { 1 - phaseProgress }

    var completedWorkRounds: Int {
        guard let phase = currentPhase else { return schedule.workPhaseCount }
        return max(0, phase.round - 1)
    }

    /// The phase after the current one, for the "up next" line.
    var nextPhase: Phase? {
        guard let index = currentIndex, schedule.phases.indices.contains(index + 1) else { return nil }
        return schedule.phases[index + 1]
    }

    // MARK: - Transport

    func start() {
        guard status == .idle || status == .finished else { return }
        startDate = now()
        pausedTotal = 0
        pauseBegan = nil
        skipOffset = 0
        elapsed = 0
        lastNotifiedIndex = nil
        status = .running
        notifyPhaseChangeIfNeeded()
        startTicking()
    }

    func pause() {
        guard status == .running else { return }
        pauseBegan = now()
        status = .paused
        stopTicking()
    }

    func resume() {
        guard status == .paused, let began = pauseBegan else { return }
        pausedTotal += now().timeIntervalSince(began)
        pauseBegan = nil
        status = .running
        startTicking()
    }

    func toggle() {
        switch status {
        case .running: pause()
        case .paused: resume()
        case .idle, .finished: start()
        }
    }

    /// Jump to the start of the next phase. Implemented as a shift in the
    /// elapsed origin rather than by mutating the schedule, so the schedule
    /// stays a pure function of the routine.
    func skip() {
        guard let index = currentIndex else { return }
        let target = schedule.start(of: index + 1)
        skipOffset += target - elapsed
        refresh()
    }

    func end() {
        stopTicking()
        status = .finished
        elapsed = schedule.total
        onFinish?()
    }

    // MARK: - Ticking

    private func startTicking() {
        stopTicking()
        guard autoTick else { return }
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                await MainActor.run { self?.refresh() }
                // 20 Hz is smooth for a draining field and cheap enough to run
                // for half an hour without meaningfully touching the battery.
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
    }

    private func stopTicking() {
        ticker?.cancel()
        ticker = nil
    }

    /// Recompute elapsed from the clock. Called by the ticker, and safe to call
    /// on returning to the foreground — that is the whole point of the design.
    func refresh() {
        guard let startDate else { return }
        var paused = pausedTotal
        if let pauseBegan { paused += now().timeIntervalSince(pauseBegan) }
        elapsed = now().timeIntervalSince(startDate) - paused + skipOffset

        if elapsed >= schedule.total {
            elapsed = schedule.total
            if status != .finished {
                stopTicking()
                status = .finished
                onFinish?()
            }
            return
        }
        notifyPhaseChangeIfNeeded()
    }

    private func notifyPhaseChangeIfNeeded() {
        let index = currentIndex
        if lastNotifiedIndex != .some(index) {
            lastNotifiedIndex = .some(index)
            onPhaseChange?(currentPhase)
        }
    }

    deinit { ticker?.cancel() }
}

// MARK: - Formatting

extension TimeInterval {
    /// `0:41`. Rounds up so a phase reads "0:01" for its whole final second.
    var clockString: String {
        let total = Int(rounded(.up))
        return "\(total / 60):\(String(format: "%02d", total % 60))"
    }

    /// `14:00` for durations stated in minutes and seconds.
    var durationString: String {
        let total = Int(rounded())
        return "\(total / 60):\(String(format: "%02d", total % 60))"
    }
}
