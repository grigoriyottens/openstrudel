import Foundation

struct ConnectionDiagnosticEvent: Codable, Identifiable {
    enum Kind: String, Codable { case connecting, connected, unavailable, removed, requestFailed, requestCompleted }
    enum Category: String, Codable {
        case connection, catalogue, speech, request
        static func route(_ path: String) -> Self {
            if path == "/health" { return .connection }
            if path.hasPrefix("/v1/profiles") { return .catalogue }
            if path.hasPrefix("/v1/speech/") { return .speech }
            return .request
        }
    }
    let id: UUID
    let time: Date
    let kind: Kind
    let category: Category
    let status: Int?
    let code: Int?
    let durationMs: Int?
}

/// Per-connection history stays readable offline. Its schema cannot hold a URL, key or message body.
@MainActor final class ConnectionJournal {
    private let defaults: UserDefaults
    init(defaults: UserDefaults) { self.defaults = defaults }
    var detailed: Bool {
        get { defaults.bool(forKey: "openstrudel.diagnostics.detailed") }
        set { defaults.set(newValue, forKey: "openstrudel.diagnostics.detailed") }
    }
    var events: [ConnectionDiagnosticEvent] {
        guard let data = defaults.data(forKey: "openstrudel.diagnostics.events") else { return [] }
        return (try? JSONDecoder().decode([ConnectionDiagnosticEvent].self, from: data)) ?? []
    }
    func record(_ kind: ConnectionDiagnosticEvent.Kind, category: ConnectionDiagnosticEvent.Category = .connection, status: Int? = nil, code: Int? = nil, durationMs: Int? = nil) {
        guard kind != .requestCompleted || detailed else { return }
        let entry = ConnectionDiagnosticEvent(id: UUID(), time: Date(), kind: kind, category: category, status: status, code: code, durationMs: durationMs)
        let values = [entry] + events.prefix(99)
        if let data = try? JSONEncoder().encode(values) { defaults.set(data, forKey: "openstrudel.diagnostics.events") }
    }
}

struct DeviceDiagnosticReport: Decodable {
    struct Speech: Decodable { let provider: String; let connected: Bool }
    struct Event: Decodable, Identifiable {
        let id: Int
        let time: String
        let event: String
        let provider: String?
        let durationMs: Int?
        let bytes: Int?
        let status: Int?
        let reason: String?
        var date: Date {
            (try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(time)) ?? .distantPast
        }
    }
    let level: String
    let speech: Speech
    let events: [Event]
}

