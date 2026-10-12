import Foundation
import Testing

@Suite("Server setup", .serialized)
struct ServerSetupTests {
    @Test func targetRejectsShellAndSSHOptions() throws {
        let target = try ServerTarget(host: "  server.example.com ", user: "ubuntu", port: 2222)
        #expect(target.host == "server.example.com")
        #expect(target.knownHostsName == "[server.example.com]:2222")
        for host in ["-oProxyCommand=bad", "user@server.example", "https://server.example", "server;whoami", "127.0.0.1\nother", "server.example:22", "999.1.2.3"] {
            #expect(throws: ServerSetupFailure.self) { try ServerTarget(host: host, user: "root", port: 22) }
        }
        #expect(throws: ServerSetupFailure.self) { try ServerTarget(host: "server.example", user: "root;pwd", port: 22) }
        #expect(throws: ServerSetupFailure.self) { try ServerTarget(host: "server.example", user: "root", port: 0) }
    }

    @Test func connectionNeverUsesAnUnconfirmedHostOrUnrelatedSSHConfig() throws {
        let target = try ServerTarget(host: "203.0.113.2", user: "root", port: 22)
        let access = ServerAccess(password: "private-test-password")
        let args = SSHServerTransport.arguments(target: target, knownHosts: "/private/host", keyFile: nil, access: access, command: "bash -s")
        #expect(args.contains("StrictHostKeyChecking=yes"))
        #expect(args.contains("IdentityAgent=none"))
        #expect(args.contains("ForwardAgent=no"))
        #expect(args.contains("/dev/null"))
        #expect(!args.joined().contains(access.password))
    }

    @Test func passwordUsesAnEphemeralPipeInsteadOfArgumentsOrAFile() throws {
        let access = ServerAccess(password: "p@ss' word with spaces")
        let session = try SSHPrivateSession(access: access)
        defer { session.close() }
        let directory = session.directory
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        for url in files where url.lastPathComponent != "answer" {
            let data = try Data(contentsOf: url)
            #expect(!String(decoding: data, as: UTF8.self).contains(access.password))
        }
        let attributes = try FileManager.default.attributesOfItem(atPath: directory.appending(path: "answer").path)
        #expect(attributes[.type] as? FileAttributeType != .typeRegular)
        #expect(session.environment.values.allSatisfy { !$0.contains(access.password) })
        session.close()
        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }

    @Test func incompatibleServersAndExistingDataAreNotInstallable() throws {
        var check = ServerPreflight(os: "ubuntu", version: "24.04", architecture: "x86_64", memoryMiB: 3900, diskGiB: 35, freeGiB: 20, administrator: true, python: true, installationID: nil, existing: false, portBusy: false)
        #expect(check.installationProblem == nil)
        check.os = "debian"
        #expect(check.installationProblem == .unsupportedSystem)
        check.os = "ubuntu"; check.memoryMiB = 2048
        #expect(check.installationProblem == .resources)
        check.memoryMiB = 3900; check.existing = true
        #expect(check.installationProblem == .existingInstallation)
        check.existing = false; check.portBusy = true
        #expect(check.installationProblem == .portBusy)
    }

    @Test func bootstrapIsReplayedWithTheSameIdentityAndSecretsStayInStdin() throws {
        let target = try ServerTarget(host: "server.example.com", user: "root", port: 22)
        let key = try SSHHostKey(line: "server.example.com ssh-ed25519 " + Data(repeating: 1, count: 51).base64EncodedString(), target: target)
        let saved = try ServerInstallation(target: target, hostKey: key, releaseHash: String(repeating: "a", count: 64))
        let input = try ServerSetupScripts.install(saved, installer: Data("#!/usr/bin/env bash\ntrue\n".utf8), script: "install_server() { :; }")
        #expect(input == (try ServerSetupScripts.install(saved, installer: Data("#!/usr/bin/env bash\ntrue\n".utf8), script: "install_server() { :; }")))
        #expect(!input.contains(saved.ownerToken))
        #expect(input.contains(saved.id))
        #expect(saved.target == target)
    }

    @Test func completedButUnreachableInstallationExplainsThePortInsteadOfWaitingForever() throws {
        let complete = ServerInstallationStatus(installationID: "owned", state: "complete", stage: "ready")
        #expect(complete.problemWhenUnreachable == .serviceUnreachable)
        let building = ServerInstallationStatus(installationID: "owned", state: "activating", stage: "build")
        #expect(building.problemWhenUnreachable == nil)
        let failed = ServerInstallationStatus(installationID: "owned", state: "failed", stage: "build")
        #expect(failed.problemWhenUnreachable == .installation)
    }

    @Test @MainActor func lockedRecoveryCannotStartAnotherInstallation() throws {
        let store = ServerSetupLockedStore()
        let flow = ServerSetupFlow(store: store)
        #expect(flow.phase == .failed)
        #expect(flow.error == .storage)
        #expect(!flow.recoveryLoaded)
        flow.inspect(try ServerTarget(host: "other.example.com", user: "root", port: 22))
        #expect(flow.target == nil)
        #expect(flow.phase == .failed)
        store.locked = false
        flow.reloadRecovery()
        #expect(flow.recoveryLoaded)
        #expect(flow.phase == .address)
    }

    @Test @MainActor func finishedServerResumesWithoutAskingForSSHAgain() async throws {
        let target = try ServerTarget(host: "server.example.com", user: "root", port: 22)
        let key = try SSHHostKey(line: "host ssh-ed25519 " + Data(repeating: 1, count: 51).base64EncodedString(), target: target)
        let saved = try ServerInstallation(target: target, hostKey: key, releaseHash: String(repeating: "a", count: 64))
        let store = ServerSetupMemoryStore(installation: saved)
        let connection = HomeConnection(url: "https://server.example.com:7789", token: "fixture", pin: String(repeating: "b", count: 64), name: "Server")
        let flow = ServerSetupFlow(store: store, probe: { pending in
            #expect(pending.id == saved.id)
            return connection
        })
        flow.resume()
        for _ in 0..<100 where flow.phase != .connected { await Task.yield() }
        #expect(flow.phase == .connected)
        #expect(flow.connection?.pin == connection.pin)
        #expect(store.installation?.id == saved.id, "Keep recovery until the device has been added")

        let offline = ServerSetupFlow(store: store, probe: { _ in nil })
        offline.resume()
        for _ in 0..<100 where offline.phase != .paused { await Task.yield() }
        #expect(offline.phase == .paused)
        #expect(offline.installation?.id == saved.id)
    }
}

@MainActor private final class ServerSetupLockedStore: ServerSetupStore {
    var locked = true
    func load() throws -> ServerInstallation? {
        if locked { throw ServerSetupFailure.storage }
        return nil
    }
    func save(_ installation: ServerInstallation?) throws { throw ServerSetupFailure.storage }
}

@MainActor private final class ServerSetupMemoryStore: ServerSetupStore {
    var installation: ServerInstallation?
    init(installation: ServerInstallation?) { self.installation = installation }
    func load() throws -> ServerInstallation? { installation }
    func save(_ installation: ServerInstallation?) throws { self.installation = installation }
}

@Suite("Real SSH setup", .serialized, .enabled(if: ProcessInfo.processInfo.environment["OPENSTRUDEL_SSH_INTEGRATION"] == "1"))
struct ServerSSHIntegrationTests {
    private struct Fixture: Decodable { let host: String; let port: Int; let user: String; let key: String; let wrongKey: String; let hostKey: String }
    private func fixture() throws -> (ServerTarget, SSHHostKey, ServerAccess, ServerAccess) {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 { root.deleteLastPathComponent() }
        let fixture = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: root.appending(path: ".data/remaining-work-2026-10-12/ssh/fixture.json")))
        let target = try ServerTarget(host: fixture.host, user: fixture.user, port: fixture.port)
        let line = try String(contentsOfFile: fixture.hostKey, encoding: .utf8).split(whereSeparator: \.isWhitespace)
        let key = try SSHHostKey(line: "\(target.knownHostsName) \(line[0]) \(line[1])", target: target)
        return (target, key, ServerAccess(privateKey: try Data(contentsOf: URL(fileURLWithPath: fixture.key))), ServerAccess(privateKey: try Data(contentsOf: URL(fileURLWithPath: fixture.wrongKey))))
    }
    @Test func scansAndAuthenticatesToAnActualSSHServer() async throws {
        let (target, key, access, _) = try fixture()
        let scanned = try await SSHServerTransport().scan(target)
        #expect(scanned == key)
        let data = try await SSHServerTransport().run(target: target, key: key, access: access, input: Data("printf 'authenticated'\n".utf8))
        #expect(String(decoding: data, as: UTF8.self) == "authenticated")
        let preflight = try await SSHServerTransport().run(target: target, key: key, access: access, input: ServerSetupScripts.command("check_server"))
        let result = try JSONDecoder().decode(ServerPreflight.self, from: preflight)
        #expect(result.installationProblem == .unsupportedSystem)
    }
    @Test func wrongCredentialsAndChangedIdentityFailBeforeRunningCommands() async throws {
        let (target, key, access, wrong) = try fixture()
        await #expect(throws: ServerSetupFailure.authentication) {
            _ = try await SSHServerTransport().run(target: target, key: key, access: wrong, input: Data("echo MUST_NOT_RUN\n".utf8))
        }
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 { root.deleteLastPathComponent() }
        let line = try String(contentsOf: root.appending(path: ".data/remaining-work-2026-10-12/ssh/wrong.pub"), encoding: .utf8).split(whereSeparator: \.isWhitespace)
        let changed = try SSHHostKey(line: "\(target.knownHostsName) \(line[0]) \(line[1])", target: target)
        await #expect(throws: ServerSetupFailure.hostKey) {
            _ = try await SSHServerTransport().run(target: target, key: changed, access: access, input: Data("echo MUST_NOT_RUN\n".utf8))
        }
    }
    @Test func passwordAndEncryptedKeyAuthenticateToActualUbuntu() async throws {
        struct AuthenticationFixture: Decodable {
            let host: String; let port: Int; let user: String; let key: String
            let password: String; let passphrase: String; let hostKey: String
        }
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 { root.deleteLastPathComponent() }
        let fixture = try JSONDecoder().decode(AuthenticationFixture.self, from: Data(contentsOf: root.appending(path: ".data/remaining-work-2026-10-12/ssh-auth/fixture.json")))
        let target = try ServerTarget(host: fixture.host, user: fixture.user, port: fixture.port)
        let parts = fixture.hostKey.split(whereSeparator: \.isWhitespace)
        let key = try SSHHostKey(line: "host \(parts[0]) \(parts[1])", target: target)
        let privateKey = try Data(contentsOf: URL(fileURLWithPath: fixture.key))
        let transport = SSHServerTransport()
        for access in [ServerAccess(password: fixture.password), ServerAccess(privateKey: privateKey, passphrase: fixture.passphrase)] {
            let output = try await transport.run(target: target, key: key, access: access, input: Data("printf 'authenticated'\n".utf8))
            #expect(String(decoding: output, as: UTF8.self) == "authenticated")
        }
        for access in [ServerAccess(password: "wrong-fixture-password"), ServerAccess(privateKey: privateKey, passphrase: "wrong-fixture-passphrase")] {
            await #expect(throws: ServerSetupFailure.authentication) {
                _ = try await transport.run(target: target, key: key, access: access, input: Data("echo MUST_NOT_RUN\n".utf8))
            }
        }
    }

    @Test func cancelReturnsPromptlyFromAWaitingSSHSession() async throws {
        let (target, key, access, _) = try fixture()
        let operation = Task { try await SSHServerTransport().run(target: target, key: key, access: access, input: Data("sleep 60\n".utf8)) }
        try await Task.sleep(for: .milliseconds(400))
        let start = ContinuousClock.now
        operation.cancel()
        do { _ = try await operation.value; Issue.record("Canceled SSH unexpectedly succeeded") } catch {}
        #expect(start.duration(to: .now) < .seconds(4))
    }
}

@Suite("Installed Ubuntu server", .serialized, .enabled(if: ProcessInfo.processInfo.environment["OPENSTRUDEL_VM_INTEGRATION"] == "1"))
@MainActor struct ServerVMIntegrationTests {
    @Test func resumesPinnedServerCreatesRemoteEmployeeAndRestoresItsBackup() async throws {
        struct Fixture: Decodable {
            struct Bootstrap: Decodable { let installationId: String; let privateKeyPEM: String }
            let bootstrap: Bootstrap; let ownerToken: String; let pin: String; let hostKey: String
            let host: String?; let user: String?; let sshPort: Int?
        }
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 { root.deleteLastPathComponent() }
        let fixtureURL = ProcessInfo.processInfo.environment["OPENSTRUDEL_VM_FIXTURE"].map { URL(fileURLWithPath: $0) }
            ?? root.appending(path: ".data/remaining-work-2026-10-12/vm-private.json")
        let fixture = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: fixtureURL))
        let target = try ServerTarget(host: fixture.host ?? "127.0.0.1", user: fixture.user ?? "mikwiseman", port: fixture.sshPort ?? 57423)
        let parts = fixture.hostKey.split(whereSeparator: \.isWhitespace)
        let key = try SSHHostKey(line: "host \(parts[0]) \(parts[1])", target: target)
        let payload: [String: Any] = ["id": fixture.bootstrap.installationId,
            "target": try JSONSerialization.jsonObject(with: JSONEncoder().encode(target)),
            "hostKey": try JSONSerialization.jsonObject(with: JSONEncoder().encode(key)),
            "releaseHash": String(repeating: "a", count: 64), "privateKeyPEM": fixture.bootstrap.privateKeyPEM,
            "ownerToken": fixture.ownerToken, "attempted": true]
        let saved = try JSONDecoder().decode(ServerInstallation.self, from: JSONSerialization.data(withJSONObject: payload))
        let flow = ServerSetupFlow(store: ServerSetupMemoryStore(installation: saved))
        flow.resume()
        for _ in 0..<200 where flow.phase == .checking { try await Task.sleep(for: .milliseconds(25)) }
        #expect(flow.phase == .connected)
        let connection = try #require(flow.connection)
        #expect(connection.pin == fixture.pin)
        let name = "OpenStrudel.real-vm." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set("http://127.0.0.1:57102", forKey: "openstrudel.homeURL")
        let local = HomeClient(defaults: defaults, connectionID: name + ".local")
        let remote = HomeClient(defaults: defaults, connectionID: name + ".remote")
        #expect(await remote.connectToCloud(connection))
        #expect(!remote.homeUnreachable)
        let library = DeviceLibrary(defaults: defaults, clients: [local])
        library.add(remote)
        #expect(library.active === remote)
        #expect(library.clients.count == 2)
        #expect(local.normalizedBaseURL == "http://127.0.0.1:57102")
        let employee = "Server acceptance " + UUID().uuidString.prefix(8)
        #expect(await remote.createProfile(name: employee, instructions: "This is a disposable server installation test."))
        #expect(remote.profiles.contains { $0.name == employee })
        #expect(local.profiles.isEmpty)
        let archive = try await remote.exportAgents()
        #expect(archive.count > 100)
        try archive.write(to: fixtureURL.deletingLastPathComponent().appending(path: "vm-employee-backup.strudel"))
        let originalIDs = Set(remote.profiles.map(\.id))
        let pending = try await remote.previewAgentImport(archive)
        #expect(pending.preview.employees.contains { $0.name == employee })
        let restored = try await remote.importAgents(pending)
        #expect(restored.profileIds.count == pending.preview.counts.employees)
        #expect(originalIDs.isSubset(of: Set(remote.profiles.map(\.id))))
        #expect(restored.profileIds.allSatisfy { id in remote.profiles.contains { $0.id == id } })
        let restoredIDs = Set(remote.profiles.map(\.id))
        let replayed = try await remote.importAgents(pending)
        #expect(replayed.profileIds == restored.profileIds)
        #expect(Set(remote.profiles.map(\.id)) == restoredIDs)
        try flow.finish()
        #expect(flow.installation == nil)
        remote.disconnectFromMac()
    }
}
