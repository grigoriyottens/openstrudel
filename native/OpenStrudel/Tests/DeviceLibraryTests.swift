import Foundation
import Testing

@Suite(.serialized)
@MainActor struct DeviceLibraryTests {
    @Test func restoringLocalRuntimeDoesNotDependOnTheSelectedRemoteEmployee() throws {
        let name = "OpenStrudel.local-runtime-restore." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        // Construct away from the real local endpoint so the fixture never
        // reads this Mac's LocalConnection.json or uses its credentials.
        defaults.set("http://127.0.0.1:57106", forKey: "openstrudel.homeURL")
        let local = HomeClient(defaults: defaults, connectionID: name + "-local", credentialReader: { account, _ in
            account.hasSuffix("home-api-token") ? "fixture" : nil
        })
        local.baseURLString = "http://127.0.0.1:7788"
        let remote = HomeClient(defaults: defaults, connectionID: name + "-remote", credentialReader: { _, _ in nil })
        remote.baseURLString = "https://remote.example"
        let library = DeviceLibrary(defaults: defaults, clients: [local, remote])
        library.select(remote)
        #expect(library.localClientToRestore === local)
        #expect(library.active === remote)
        local.baseURLString = "http://127.0.0.1:57106"
        #expect(library.localClientToRestore == nil, "An unrelated loopback service is not the managed Home")
    }

    @Test func restoringLocalRuntimeDoesNotReconnectASignedOutDevice() async throws {
        let name = "OpenStrudel.local-runtime-signed-out." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set("http://127.0.0.1:57107", forKey: "openstrudel.homeURL")
        let local = HomeClient(defaults: defaults, connectionID: name, credentialReader: { account, _ in
            account.hasSuffix("home-api-token") ? "fixture" : nil
        })
        local.baseURLString = "http://127.0.0.1:7788"
        let library = DeviceLibrary(defaults: defaults, clients: [local])
        #expect(library.localClientToRestore === local)
        await local.signOutOnThisDevice()
        #expect(library.localClientToRestore == nil)
    }

    @Test func lockedCredentialsKeepTheDestinationAndRecoverWithoutPairingAgain() async throws {
        let name = "OpenStrudel.unlock-test." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let connection = HomeConnection(url: "https://server.example:7789", token: "fixture", pin: String(repeating: "b", count: 64), name: "My server")
        let saved = String(decoding: try JSONEncoder().encode(connection), as: UTF8.self)
        defaults.set(connection.url, forKey: "openstrudel.homeURL")
        let client = HomeClient(defaults: defaults, connectionID: name, credentialReader: { account, interactive in
            guard account.hasSuffix("home-connection") else { return nil }
            guard interactive else { throw URLError(.userAuthenticationRequired) }
            return saved
        })
        #expect(client.connectionNeedsUnlock)
        #expect(client.connectionNeedsPairing)
        #expect(!client.isConfigured)
        #expect(client.baseURLString == connection.url) // Same draft namespace while locked.
        await #expect(throws: HomeClientError.self) {
            let _: HomeHealth = try await client.management("/health")
        }
        #expect(await client.unlockSavedConnection())
        #expect(!client.connectionNeedsUnlock)
        #expect(!client.connectionNeedsPairing)
        #expect(client.isConfigured && client.hasToken)
        #expect(client.baseURLString == connection.url)
        #expect(client.connectionName == connection.name)
        #expect(!client.isUnlockingConnection)
    }

    @Test func aMissingCredentialStillNeedsANewConnectionLink() async throws {
        let name = "OpenStrudel.missing-credential-test." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set("https://server.example:7789", forKey: "openstrudel.homeURL")
        let client = HomeClient(defaults: defaults, connectionID: name, credentialReader: { _, _ in nil })
        #expect(client.connectionNeedsPairing)
        #expect(!client.connectionNeedsUnlock)
        #expect(!client.isConfigured)
        #expect(await client.unlockSavedConnection() == false)
    }

    @Test func aLockedPairingAttemptDoesNotReplaceTheAttemptOrLockTheExistingConnection() async throws {
        let name = "OpenStrudel.pairing-credential-test." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let pin = String(repeating: "b", count: 64)
        let connection = HomeConnection(url: "https://server.example:7789", token: "fixture", pin: pin, name: "My server")
        let saved = String(decoding: try JSONEncoder().encode(connection), as: UTF8.self)
        let client = HomeClient(defaults: defaults, connectionID: name, credentialReader: { account, _ in
            if account.contains("pair-attempt-") { throw HomeClientError.server("Keychain is locked") }
            return account.hasSuffix("home-connection") ? saved : nil
        })
        let link = try #require(URL(string: "openstrudel://connect?host=other.example&port=7789&key=\(String(repeating: "a", count: 64))&pin=\(pin)"))
        #expect(await client.connectToMac(try MacPairing(url: link)) == false)
        #expect(client.pairingError != nil)
        #expect(!client.connectionNeedsUnlock && !client.connectionNeedsPairing)
        #expect(client.isConfigured && client.hasToken)
        #expect(client.baseURLString == connection.url)
    }

    @Test func decliningKeychainAccessKeepsTheSavedConnectionForRetry() async throws {
        let name = "OpenStrudel.declined-credential-test." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set("https://server.example:7789", forKey: "openstrudel.homeURL")
        let client = HomeClient(defaults: defaults, connectionID: name, credentialReader: { _, _ in throw URLError(.userCancelledAuthentication) })
        #expect(await client.unlockSavedConnection() == false)
        #expect(client.connectionNeedsUnlock && client.connectionNeedsPairing)
        #expect(!client.hasToken && !client.isUnlockingConnection)
        #expect(client.errorMessage != nil)
        #expect(defaults.string(forKey: "openstrudel.homeURL") == "https://server.example:7789")
    }

    @Test func delayedKeychainAccessCannotReconnectAfterLocalErase() async throws {
        let name = "OpenStrudel.stale-credential-test." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set("https://server.example:7789", forKey: "openstrudel.homeURL")
        let gate = CredentialReadGate()
        defer { gate.finish.signal() }
        let saved = String(decoding: try JSONEncoder().encode(HomeConnection(url: "https://server.example:7789", token: "fixture", pin: String(repeating: "b", count: 64), name: "Server")), as: UTF8.self)
        let client = HomeClient(defaults: defaults, connectionID: name, credentialReader: { account, interactive in
            guard account.hasSuffix("home-connection") else { return nil }
            guard interactive else { throw URLError(.userAuthenticationRequired) }
            gate.markStarted()
            guard gate.finish.wait(timeout: .now() + 5) == .success else { throw URLError(.timedOut) }
            return saved
        })
        let operation = Task { await client.unlockSavedConnection() }
        var started = false
        for _ in 0..<200 {
            if gate.didStart { started = true; break }
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(started)
        client.suspendForLocalErase()
        gate.finish.signal()
        #expect(await operation.value == false)
        #expect(client.isSignedOut && !client.hasToken && !client.isConfigured)
        #expect(client.baseURLString.isEmpty)
    }

    @Test func aPairedTLSConnectionIsNotTheLocalRuntime() throws {
        let name = "OpenStrudel.paired-device-test." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set("https://127.0.0.1:57104", forKey: "openstrudel.homeURL")
        let client = HomeClient(defaults: defaults, connectionID: name)
        client.baseURLString = "https://127.0.0.1:57104"
        #expect(!client.isLocalConnection)
    }

    @Test func addingAnIndependentDeviceKeepsLocalEmployeesAndCredentialsSeparate() throws {
        let name = "OpenStrudel.devices-test." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set("http://127.0.0.1:57101", forKey: "openstrudel.homeURL")
        let local = HomeClient(defaults: defaults, connectionID: name + "-local")
        let remote = HomeClient(defaults: defaults, connectionID: name + "-remote")
        remote.baseURLString = "https://remote.example"
        let library = DeviceLibrary(defaults: defaults, clients: [local])
        library.add(remote)
        #expect(library.clients.count == 2)
        #expect(library.active === remote)
        #expect(local.normalizedBaseURL == "http://127.0.0.1:57101")
        #expect(remote.normalizedBaseURL == "https://remote.example")
        #expect(local.id != remote.id)
        library.beginEmployee()
        #expect(library.active === remote)
        #expect(remote.isEmployeeDraft)
        #expect(!local.isEmployeeDraft)
        #expect(!remote.canManageOpenAI)
        #expect(library.employeeDestinations.count == 2)
        #expect(library.employeeDestinations.allSatisfy { $0.available })
        library.beginEmployee(on: local)
        #expect(library.active === local)
        #expect(local.isEmployeeDraft)
    }

    @Test func choosingTheExecutionDevicePreservesTheUnsentCreationPrompt() throws {
        let name = "OpenStrudel.draft-device-test." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set("http://127.0.0.1:57102", forKey: "openstrudel.homeURL")
        let local = HomeClient(defaults: defaults, connectionID: name + "-local")
        let remote = HomeClient(defaults: defaults, connectionID: name + "-remote")
        remote.baseURLString = "https://remote.example"
        let library = DeviceLibrary(defaults: defaults, clients: [local, remote])
        library.beginEmployee(on: local)
        let appearance = local.draftAppearance
        let old = HomeDrafts.key(home: local.baseURLString, profile: local.selectedProfileID, chat: nil)
        library.saveDraft("Редактор моих текстов", for: old)
        let file = PickedFile(name: "Задача.txt", mimeType: "text/plain", data: Data("Сохрани смысл".utf8))
        library.fileDrafts[old] = [file]
        library.chooseEmployeeDevice(remote)
        let new = HomeDrafts.key(home: remote.baseURLString, profile: remote.selectedProfileID, chat: nil)
        #expect(library.active === remote)
        #expect((defaults.dictionary(forKey: "openstrudel.drafts") as? [String: String])?[new] == "Редактор моих текстов")
        #expect(!local.isEmployeeDraft)
        #expect(remote.draftAppearance == appearance)
        #expect(library.fileDrafts[new] == [file])
        #expect(library.fileDrafts[old] == nil)
        #expect((defaults.dictionary(forKey: "openstrudel.drafts") as? [String: String])?[old] == nil)
        // A different conversation saving after the move must not replace the
        // destination draft with an older copy of the entire draft dictionary.
        library.saveDraft("Другой разговор", for: "unrelated")
        #expect(library.draft(for: new) == "Редактор моих текстов")
        let draftID = remote.selectedProfileID
        library.chooseEmployeeDevice(remote, deviceID: "server")
        #expect(remote.selectedProfileID == draftID)
        #expect(remote.draftDeviceID == "server")
    }

    @Test func signedOutConnectionCannotReceiveANewDraftOrSilentlyCreateLocally() async throws {
        let name = "OpenStrudel.revoked-creation-test." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set("http://127.0.0.1:57105", forKey: "openstrudel.homeURL")
        let local = HomeClient(defaults: defaults, connectionID: name + "-local")
        let remote = HomeClient(defaults: defaults, connectionID: name + "-remote")
        remote.baseURLString = "https://remote.example"
        let library = DeviceLibrary(defaults: defaults, clients: [local, remote])
        library.beginEmployee(on: local)
        let draftID = local.selectedProfileID
        await remote.signOutOnThisDevice()
        #expect(!library.employeeDestinations.contains { $0.client === remote })
        library.chooseEmployeeDevice(remote)
        #expect(library.active === local)
        #expect(local.selectedProfileID == draftID)
        library.select(remote)
        library.beginEmployee()
        #expect(library.active === remote)
        #expect(!remote.isEmployeeDraft)
        #expect(local.selectedProfileID == draftID)
    }

    @Test func removingOneDeviceLeavesTheOtherDeviceUsable() async throws {
        let name = "OpenStrudel.remove-device-test." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set("http://127.0.0.1:57103", forKey: "openstrudel.homeURL")
        let first = HomeClient(defaults: defaults, connectionID: name + "-one")
        let second = HomeClient(defaults: defaults, connectionID: name + "-two")
        let library = DeviceLibrary(defaults: defaults, clients: [first, second])
        await second.signOutOnThisDevice()
        #expect(first.isConfigured)
        #expect(!first.isSignedOut)
        #expect(library.visibleClients.count == 1)
        #expect(library.visibleClients.first === first)
    }
}

private final class CredentialReadGate: @unchecked Sendable {
    private let lock = NSLock()
    private var started = false
    var didStart: Bool { lock.withLock { started } }
    func markStarted() { lock.withLock { started = true } }
    let finish = DispatchSemaphore(value: 0)
}
