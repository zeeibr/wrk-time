import Foundation
import Testing
@testable import WrkTime

/// The one line Signals draws from a session's heart rate.
///
/// A wrist sensor does not know a heart rate to a tenth of a beat, so the row
/// rounds — and the rounding is the only arithmetic in the feature, which
/// makes it the only part worth a test. The query itself belongs to Health.
@Suite("Session heart rate reads as one line")
struct SessionHeartRateTests {

    @Test("Average and peak read in that order, rounded")
    func summary() {
        let reading = SessionHeartRate(average: 121.4, peak: 148.2)
        #expect(reading.summary == "121 avg · 148 peak")
    }

    @Test("A half beat rounds up rather than truncating")
    func rounding() {
        // Truncation would report 120 for a session that averaged 120.6 — a
        // reading the app never took, quietly one beat low all session.
        let reading = SessionHeartRate(average: 120.6, peak: 147.5)
        #expect(reading.summary == "121 avg · 148 peak")
    }

    @Test("A flat session says the same number twice rather than hiding one")
    func flat() {
        let reading = SessionHeartRate(average: 96, peak: 96)
        #expect(reading.summary == "96 avg · 96 peak")
    }
}
