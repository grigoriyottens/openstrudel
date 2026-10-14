import Foundation
import Testing

@Suite(.serialized) @MainActor struct EmployeeMoveTests {
    private func journal() throws -> (UserDefaults, String, EmployeeMove) {
        let name = "OpenStrudel.move-test." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: name))
        let value = EmployeeMove(id: UUID().uuidString, proof: String(repeating: "a", count: 64), profileID: "employee", name: "Editor",
                                 sourceID: "source", sourceHome: "home-a", sourceName: "Laptop",
                                 targetID: "target", targetHome: "home-b", targetName: "Mini")
        defaults.set(try JSONEncoder().encode(value), forKey: "openstrudel.employeeMove")
        return (defaults, name, value)
    }

    @Test func aLostReleaseReplyResumesAfterRelaunchWithoutEnablingTwoCopies() async throws {
        let (defaults, name, _) = try journal()
        defer { defaults.removePersistentDomain(forName: name) }
        let server = MoveEndpoints()
        server.lose = "release"
        let first = EmployeeMoves(defaults: defaults)
        first.resume(using: server.call); await first.waitUntilPaused()
        #expect(first.error != nil)
        #expect(first.operation?.phase == .releasing)
        #expect(server.sourceReleased && !server.targetActive)
        first.cancel(using: server.call)
        #expect(first.operation?.phase == .releasing)
        let reopened = EmployeeMoves(defaults: defaults)
        reopened.resume(using: server.call); await reopened.waitUntilPaused()
        #expect(reopened.error == nil)
        #expect(reopened.operation?.phase == .completed)
        #expect(server.targetActive && server.sourceReleased)
        #expect(server.calls.filter { $0 == "source:release" }.count == 2)
        #expect(server.calls.filter { $0 == "target:activate" }.count == 1)
    }

    @Test func cancelAfterLostStageReplyInstallsTheBarrierBeforeUnfreezingSource() async throws {
        let (defaults, name, _) = try journal()
        defer { defaults.removePersistentDomain(forName: name) }
        let server = MoveEndpoints(); server.lose = "stage"
        let first = EmployeeMoves(defaults: defaults)
        first.resume(using: server.call); await first.waitUntilPaused()
        #expect(first.operation?.phase == .staging && server.targetStaged)
        first.cancel(using: server.call)
        for _ in 0..<100 where first.operation?.phase != .canceled { try await Task.sleep(for: .milliseconds(10)) }
        #expect(first.operation?.phase == .canceled)
        #expect(server.calls.suffix(2) == ["target:cancel", "source:cancel"])
        #expect(!server.sourceReleased && !server.targetActive && !server.targetStaged)
    }

    @Test func lostActivationReplyOnlyReplaysActivationAndNeverReleasesAgain() async throws {
        let (defaults, name, _) = try journal()
        defer { defaults.removePersistentDomain(forName: name) }
        let server = MoveEndpoints(); server.lose = "activate"
        let first = EmployeeMoves(defaults: defaults)
        first.resume(using: server.call); await first.waitUntilPaused()
        #expect(first.operation?.phase == .activating && server.targetActive)
        let reopened = EmployeeMoves(defaults: defaults)
        reopened.resume(using: server.call); await reopened.waitUntilPaused()
        #expect(reopened.operation?.phase == .completed)
        #expect(server.calls.filter { $0 == "source:release" }.count == 1)
        #expect(server.calls.filter { $0 == "target:activate" }.count == 2)
    }

    @Test func aChangedDestinationReceiptNeverReleasesTheSource() async throws {
        let (defaults, name, _) = try journal()
        defer { defaults.removePersistentDomain(forName: name) }
        let server = MoveEndpoints(); server.badDigest = true
        let moves = EmployeeMoves(defaults: defaults)
        moves.resume(using: server.call); await moves.waitUntilPaused()
        #expect(moves.error != nil && moves.operation?.phase == .staging)
        #expect(!server.sourceReleased && !server.targetActive)
    }
}

@MainActor private final class MoveEndpoints {
    var calls: [String] = []
    var sourceReleased = false, targetStaged = false, targetActive = false, badDigest = false
    var lose: String?
    let digest = String(repeating: "b", count: 64)
    func call(_ endpoint: String, _ action: String, _ data: Data) async throws -> Data {
        let payload = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(payload["homeId"] as? String == (endpoint == "source" ? "home-a" : "home-b"))
        #expect(payload["token"] == nil)
        calls.append(endpoint + ":" + action)
        let response: [String: Any]
        switch action {
        case "prepare": response = ["ready": true, "digest": digest, "bundle": ["fixture": true]]
        case "stage": targetStaged = true; response = ["ready": true, "digest": badDigest ? "wrong" : digest]
        case "release": #expect(targetStaged); sourceReleased = true; response = ["released": true, "digest": digest]
        case "activate": #expect(sourceReleased); targetActive = true; response = ["active": true, "warnings": []]
        case "cancel": if endpoint == "target" { targetStaged = false }; response = ["canceled": true]
        default: response = ["ok": true]
        }
        if lose == action { lose = nil; throw URLError(.networkConnectionLost) }
        return try JSONSerialization.data(withJSONObject: response)
    }
}
