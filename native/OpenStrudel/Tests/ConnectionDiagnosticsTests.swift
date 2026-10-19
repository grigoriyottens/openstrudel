import Foundation
import Testing

@Suite(.serialized) @MainActor struct ConnectionDiagnosticsTests {
    @Test func serverReportDecodesItsISOTimeWithTheNormalClientDecoder() throws {
        let body = #"{"level":"standard","speech":{"provider":"elevenlabs","connected":true},"events":[{"id":1,"time":"2026-10-19T04:22:00.123Z","event":"speech.completed","provider":"elevenlabs","durationMs":18040}]}"#
        let report = try JSONDecoder().decode(DeviceDiagnosticReport.self, from: Data(body.utf8))
        #expect(report.events.first?.date.timeIntervalSince1970 ?? 0 > 1_700_000_000)
        #expect(report.events.first?.durationMs == 18040)
    }
    @Test func historySurvivesRelaunchAndRemainsBounded() throws {
        let name = "OpenStrudel.diagnostics." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let journal = ConnectionJournal(defaults: defaults)
        for _ in 0..<120 { journal.record(.unavailable, category: .connection, code: -1009) }
        let restored = ConnectionJournal(defaults: defaults)
        #expect(restored.events.count == 100)
        #expect(restored.events.first?.code == -1009)
        #expect(restored.events.first?.kind == .unavailable)
    }

    @Test func ordinaryLoggingKeepsFailuresButSkipsSuccessfulRequests() throws {
        let name = "OpenStrudel.diagnostics-level." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let journal = ConnectionJournal(defaults: defaults)
        journal.record(.requestCompleted, category: .speech, status: 200)
        journal.record(.requestFailed, category: .speech, status: 401)
        #expect(journal.events.count == 1)
        journal.detailed = true
        journal.record(.requestCompleted, category: .speech, status: 200)
        #expect(ConnectionJournal(defaults: defaults).detailed)
        #expect(journal.events.count == 2)
    }
}
