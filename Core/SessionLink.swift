import Foundation

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

/// The wire between the phone and the watch.
///
/// Phase 0 stub: the types above are the interface every later phase builds
/// against; the transport is filled in by Phase 2. `send` drops the message
/// and `onMessage` is never called, so a device without a counterpart
/// behaves exactly as the phone does today.
@MainActor
final class SessionLink {
    /// Called on the main actor for every message that arrives.
    var onMessage: ((SessionLinkMessage) -> Void)?

    init() {}

    func send(_ message: SessionLinkMessage) {}
}
