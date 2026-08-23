import Foundation
#if canImport(WatchConnectivity)
import WatchConnectivity
#endif

/// Which device a session belongs to.
///
/// A device **owns** a session it started. The owner's engine is the one
/// whose `onEnded` writes the record, exactly as the phone does today; the
/// other device mirrors the running session and never writes a record for a
/// session it did not start. Counts made on the non-owner are sent to the
/// owner and filed by the owner through the same path its own stepper uses,
/// so there is still exactly one place a record is written.
enum DeviceRole: String, Codable, Sendable {
    case phone, watch
}

/// What a non-owner may ask the owner's engine to do.
enum TransportAction: String, Codable, Sendable {
    case pause, resume, skip, endSet, end
}

/// What the two devices say to each other about the running session.
///
/// Everything live goes over `WCSession`; CloudKit latency is minutes and
/// nothing here waits on it.
enum SessionLinkMessage: Codable, Sendable, Equatable {
    /// The owner announces a session it started or restored; sent on start,
    /// on every phase change, on pause/resume, and on request.
    case running(ActiveSession, owner: DeviceRole)
    /// The owner announces the session ended.
    case ended(subjectID: UUID?, completed: Bool)
    /// A non-owner counted reps for a set ordinal; the owner applies.
    case reps(setOrdinal: Int, count: Int)
    /// A non-owner asks the owner to pause, resume, skip, end a set, end.
    case transport(TransportAction)
    /// Either side asks "what is running?"; the owner answers `.running`.
    case whatIsRunning
}

// MARK: - The transport seam

/// The three ways one device can say something to the other.
///
/// A protocol rather than `WCSession` directly, for the reason every seam in
/// this app exists: the handoff rules are testable only if both ends can be
/// stood up in one process. The three methods are the three delivery
/// guarantees `WatchConnectivity` actually offers, named for what they
/// promise rather than for the API that provides them:
///
/// - `sendLive` — now, or not at all. Only worth calling when reachable.
/// - `queue` — eventually, once the counterpart is next running. A count made
///   with the phone in another room must still land.
/// - `publishContext` — the latest snapshot, kept for a counterpart that has
///   not woken yet. Newer replaces older; nothing accumulates.
@MainActor
protocol LinkTransport: AnyObject {
    var isReachable: Bool { get }
    func sendLive(_ data: Data)
    func queue(_ data: Data)
    func publishContext(_ data: Data)
    /// Called on the main actor with every payload that arrives, by any of
    /// the three channels.
    var onReceive: ((Data) -> Void)? { get set }
}

/// The one key the JSON travels under, shared by both ends of the wire.
enum SessionLinkWire {
    static let key = "link"
}

/// A transport for a device with nothing to talk to.
///
/// Not a stub for tests — this is what a phone with no paired watch, and a
/// simulator with no `WCSession`, actually gets. Sending is a no-op that
/// cannot throw, so every call site behaves exactly as the phone did before
/// the watch existed.
@MainActor
final class DisconnectedTransport: LinkTransport {
    var onReceive: ((Data) -> Void)?
    var isReachable: Bool { false }
    func sendLive(_ data: Data) {}
    func queue(_ data: Data) {}
    func publishContext(_ data: Data) {}
}

// MARK: - The wire

/// The link between the phone and the watch.
///
/// One type on both devices. It knows nothing about who owns the session —
/// that is `ActiveSession.owner`, and the consumers enforce it — and it holds
/// no session state beyond the one announcement described below. Its whole
/// job is choosing a delivery guarantee per message and dropping what has
/// gone stale on the way in.
@MainActor
final class SessionLink {
    /// Called on the main actor for every message that arrives, in the order
    /// it arrived. Deliberately not filtered: a consumer that wants to ignore
    /// a late `.reps` asks `isLive` (below) rather than being second-guessed
    /// here.
    var onMessage: ((SessionLinkMessage) -> Void)?

    private let transport: LinkTransport
    private let now: () -> Date
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    /// What both consumers would otherwise each have to remember.
    ///
    /// A `.reps` that arrives after the session ended must not be filed
    /// against the next one, and both the phone and the watch need to know
    /// that. Rather than the same three lines of state written twice — the
    /// shape this app has been bitten by — the link keeps them once.
    ///
    /// One session at a time, because one body runs one workout at a time: a
    /// `.running` replaces whatever was announced, an `.ended` marks it over.
    struct Announcement: Equatable, Sendable {
        /// Which device is recording it.
        let owner: DeviceRole
        /// The planned session, when it is one. Nil for a practice, a saved
        /// routine, an extra or a test — none of which carry an id.
        let subjectID: UUID?
        /// When the session began. The one identity an `ActiveSession` keeps
        /// across every snapshot of itself.
        let startedAt: Date?
        /// True once `.ended` has been seen for it.
        var ended: Bool
    }

    /// The session this device last heard about, sent or received.
    private(set) var announced: Announcement?

    /// Whether a session is believed to be running right now. The one
    /// question a consumer asks before acting on a `.reps` or a `.transport`.
    var isLive: Bool { announced.map { !$0.ended } ?? false }

    /// The one wire this process has.
    ///
    /// A device has a single `WCSession`, so it gets a single link. A view
    /// must take this rather than build its own: a SwiftUI view struct is
    /// re-initialised on every pass of its parent's body, and a link built in
    /// a property initialiser would activate `WCSession` again and hand it a
    /// new delegate each time — and `WCSession.delegate` is weak, so the
    /// delegate the last pass installed would be deallocated moments later
    /// and the device would go quiet. Exactly the shape in CLAUDE.md: the
    /// failure is silent and the send path still reports success.
    static let shared = SessionLink()

    /// - Parameters:
    ///   - transport: injectable so both ends can be stood up in one test
    ///     process. Defaults to `WatchConnectivity` where it exists and to a
    ///     transport that does nothing where it does not.
    ///   - now: injectable so staleness can be asserted without waiting two
    ///     hours for it.
    init(transport: LinkTransport? = nil, now: @escaping () -> Date = Date.init) {
        self.transport = transport ?? Self.systemTransport()
        self.now = now
        self.transport.onReceive = { [weak self] data in self?.receive(data) }
    }

    private static func systemTransport() -> LinkTransport {
        #if canImport(WatchConnectivity)
        return WatchConnectivityTransport()
        #else
        return DisconnectedTransport()
        #endif
    }

    // MARK: Sending

    /// Say it, by whichever guarantee the message deserves.
    ///
    /// The policy is the whole of the delivery design, so it is in one
    /// `switch` rather than at the call sites:
    ///
    /// - `.running` goes live when the counterpart is listening, and is
    ///   *always* published as the application context. A watch that wakes up
    ///   mid-session then reads the latest snapshot rather than an empty
    ///   screen, and a newer snapshot simply replaces an older one.
    /// - `.reps` and `.transport` go live when reachable and are queued when
    ///   not. A count made with the phone in the next room is the case this
    ///   exists for: it must arrive late rather than not at all.
    /// - `.ended` goes both ways. Missing the ending is what leaves a mirror
    ///   counting down a workout that is over.
    /// - `.whatIsRunning` goes live only. It is a question, and a question
    ///   delivered an hour late has already been answered by the snapshot.
    func send(_ message: SessionLinkMessage) {
        remember(message)
        guard let data = try? encoder.encode(message) else { return }
        switch message {
        case .running:
            if transport.isReachable { transport.sendLive(data) }
            transport.publishContext(data)
        case .reps, .transport:
            transport.isReachable ? transport.sendLive(data) : transport.queue(data)
        case .ended:
            if transport.isReachable { transport.sendLive(data) }
            transport.queue(data)
        case .whatIsRunning:
            if transport.isReachable { transport.sendLive(data) }
        }
    }

    // MARK: Receiving

    private func receive(_ data: Data) {
        guard let message = try? decoder.decode(SessionLinkMessage.self, from: data) else { return }
        // A snapshot that has been sitting in a queue is not news.
        //
        // `queue` and `publishContext` both deliver when the counterpart next
        // runs, which can be tomorrow. `ActiveSession` already knows what an
        // abandoned session looks like — the same two rules the phone's own
        // interrupted-session recovery uses — and a mirror must not restore a
        // workout that ended two hours ago, or offer to resume one whose
        // clock ran out while nobody was watching.
        if case .running(let session, _) = message {
            guard !session.isStale(now()), !session.ranOut(now()) else { return }
        }
        remember(message)
        onMessage?(message)
    }

    /// Keep the one fact both consumers share. Called on the way out as well
    /// as on the way in, because the owner sends `.ended` and must itself
    /// stop believing a session is live.
    private func remember(_ message: SessionLinkMessage) {
        switch message {
        case .running(let session, let owner):
            announced = Announcement(owner: owner,
                                     subjectID: session.sessionID,
                                     startedAt: session.startedAt,
                                     ended: false)
        case .ended:
            announced?.ended = true
        case .reps, .transport, .whatIsRunning:
            break
        }
    }
}

// MARK: - WatchConnectivity

#if canImport(WatchConnectivity)

/// `WCSession`, behind the seam.
///
/// Everything is guarded twice: once on `WCSession.isSupported()`, once on
/// the activation state. A phone with no paired watch therefore takes exactly
/// the path it took before the watch app existed — three no-ops that cannot
/// throw and cannot log.
@MainActor
final class WatchConnectivityTransport: LinkTransport {
    var onReceive: ((Data) -> Void)?

    private let session: WCSession?
    private let bridge = DelegateBridge()

    init() {
        guard WCSession.isSupported() else {
            session = nil
            return
        }
        let session = WCSession.default
        self.session = session
        bridge.owner = self
        session.delegate = bridge
        session.activate()
    }

    private var live: WCSession? {
        guard let session, session.activationState == .activated else { return nil }
        return session
    }

    var isReachable: Bool { live?.isReachable ?? false }

    func sendLive(_ data: Data) {
        // The error handler is what keeps this from throwing into a workout.
        // `sendMessage` fails whenever the counterpart stops listening
        // between the reachability check and the call, which on a wrist is
        // often; the message is live-or-nothing by design, so nothing is
        // retried here.
        live?.sendMessage([SessionLinkWire.key: data], replyHandler: nil, errorHandler: { _ in })
    }

    func queue(_ data: Data) {
        live?.transferUserInfo([SessionLinkWire.key: data])
    }

    func publishContext(_ data: Data) {
        try? live?.updateApplicationContext([SessionLinkWire.key: data])
    }

    /// Called by the bridge, already on the main actor.
    fileprivate func deliver(_ data: Data) {
        onReceive?(data)
    }

    /// The object `WCSession` actually calls, which it does off the main
    /// actor and on its own queue.
    ///
    /// It is deliberately tiny: pull the one `Data` out of the payload —
    /// `[String: Any]` is not `Sendable` and must not cross the hop — and
    /// hand it to the transport on the main actor. `owner` is written once,
    /// on the main actor, before `activate()` is called, and never again.
    private final class DelegateBridge: NSObject, WCSessionDelegate, @unchecked Sendable {
        weak var owner: WatchConnectivityTransport?

        private func forward(_ payload: [String: Any]) {
            guard let data = payload[SessionLinkWire.key] as? Data else { return }
            let owner = self.owner
            Task { @MainActor in owner?.deliver(data) }
        }

        func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
            forward(message)
        }

        func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
            forward(userInfo)
        }

        func session(_ session: WCSession,
                     didReceiveApplicationContext applicationContext: [String: Any]) {
            forward(applicationContext)
        }

        func session(_ session: WCSession,
                     activationDidCompleteWith activationState: WCSessionActivationState,
                     error: Error?) {}

        #if os(iOS)
        func sessionDidBecomeInactive(_ session: WCSession) {}

        // The watch was switched. Reactivate so the new one is talked to;
        // there is nothing of ours to migrate.
        func sessionDidDeactivate(_ session: WCSession) {
            session.activate()
        }
        #endif
    }
}

#endif
