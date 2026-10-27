import Foundation
import Testing

@Suite("Server setup", .serialized)
struct ServerSetupTests {
    @Test func pastedKeysAndFilesShareNormalizationWithoutRetainingSecrets() throws {
        let payload = Data(repeating: 3, count: 64).base64EncodedString()
        let canonical = "-----BEGIN OPENSSH PRIVATE KEY-----\n\(payload)\n-----END OPENSSH PRIVATE KEY-----\n"
        let pasted = "\u{feff} \r\n" + canonical.replacingOccurrences(of: "\n", with: "\r\n") + "  "
        #expect(try SSHPrivateKey.normalized(Data(pasted.utf8)) == Data(canonical.utf8))
        let session = try SSHPrivateSession(access: ServerAccess(privateKey: Data(pasted.utf8), passphrase: "fixture-passphrase"))
        let keyFile = try #require(session.keyFile)
        #expect(try Data(contentsOf: URL(fileURLWithPath: keyFile)) == Data(canonical.utf8))
        #expect(try FileManager.default.attributesOfItem(atPath: keyFile)[.posixPermissions] as? Int == 0o600)
        #expect(!session.environment.values.contains("fixture-passphrase"))
        session.close()
        #expect(!FileManager.default.fileExists(atPath: keyFile))
    }

    @Test func rejectsPublicIncompleteAndOversizedKeysBeforeConnecting() {
        for value in ["ssh-ed25519 AAAA public@example", "-----BEGIN OPENSSH PRIVATE KEY-----\nAAAA", "-----BEGIN PRIVATE KEY-----\ninvalid!\n-----END PRIVATE KEY-----", String(repeating: "a", count: 131073)] {
            #expect(throws: ServerSetupFailure.self) { try SSHPrivateKey.normalized(Data(value.utf8)) }
        }
    }

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
        #expect(check.installationProblem == nil)
        check.memoryMiB = 3900; check.existing = true
        #expect(check.installationProblem == .existingInstallation)
        check.existing = false; check.portBusy = true
        #expect(check.installationProblem == .portBusy)
    }

    @Test func memoryAndTotalDiskAreRecommendationsButInstallationNeedsFreeSpace() {
        var check = ServerPreflight(os: "ubuntu", version: "26.04", architecture: "x86_64", memoryMiB: 3796, diskGiB: 37, freeGiB: 34, administrator: true, python: true, installationID: nil, existing: false, portBusy: false)
        #expect(check.installationProblem == nil)
        #expect(!check.recommendsMoreMemory)
        check.diskGiB = 16; check.freeGiB = 8
        for memory in [1024, 2048, 3072, 3584, 3796] {
            check.memoryMiB = memory
            #expect(check.installationProblem == nil)
            #expect(check.recommendsMoreMemory == (memory < 3584))
        }
        check.memoryMiB = 3796; check.freeGiB = 7
        #expect(check.installationProblem == .resources)
        check.freeGiB = 0
        #expect(check.installationProblem == .resources)
    }

    @Test func ubuntuLTSFrom2404IsAcceptedWithoutWeakeningOtherChecks() {
        var check = ServerPreflight(os: "ubuntu", version: "24.04", architecture: "x86_64", memoryMiB: 3900, diskGiB: 35, freeGiB: 20, administrator: true, python: true, installationID: nil, existing: false, portBusy: false)
        for version in ["24.04", "26.04"] {
            for architecture in ["x86_64", "aarch64"] {
                check.version = version; check.architecture = architecture
                #expect(check.installationProblem == nil)
            }
        }
        for version in ["22.04", "24.10", "25.04", "26.10", "", "26", "26.04-beta", "invalid"] {
            check.version = version
            #expect(check.installationProblem == .unsupportedSystem)
        }
        check.version = "26.04"; check.existing = true
        #expect(check.installationProblem == .existingInstallation)
        check.existing = false; check.runtimeCompatible = false
        #expect(check.installationProblem == .runtime)
    }

    @Test func bootstrapIsReplayedWithTheSameIdentityAndSecretsStayInStdin() throws {
        let target = try ServerTarget(host: "server.example.com", user: "root", port: 22)
        let key = try SSHHostKey(line: "server.example.com ssh-ed25519 " + Data(repeating: 1, count: 51).base64EncodedString(), target: target)
        var saved = try ServerInstallation(target: target, hostKey: key, releaseHash: String(repeating: "a", count: 64))
        // A recipe saved before archives were pinned leaves the file to the installer's alias.
        #expect(try !ServerSetupScripts.install(saved, installer: Data("#!/usr/bin/env bash\ntrue\n".utf8), script: "").contains("releaseFile"))
        saved.releaseFile = "OpenStrudel-Home-1.0-59.tar.gz"
        let input = try ServerSetupScripts.install(saved, installer: Data("#!/usr/bin/env bash\ntrue\n".utf8), script: "install_server() { :; }")
        #expect(input == (try ServerSetupScripts.install(saved, installer: Data("#!/usr/bin/env bash\ntrue\n".utf8), script: "install_server() { :; }")))
        #expect(!input.contains(saved.ownerToken))
        #expect(input.contains(saved.id))
        #expect(input.contains(#""releaseFile":"OpenStrudel-Home-1.0-59.tar.gz""#))
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

    @Test func oldRecoveryRecordsAndStatusRemainReadable() throws {
        var saved = try pendingInstallation()
        saved.releaseFile = "OpenStrudel-Home-1.0-59.tar.gz"
        var record = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(saved)) as? [String: Any])
        record.removeValue(forKey: "previousReleaseHash")
        record.removeValue(forKey: "releaseFile")
        let restored = try JSONDecoder().decode(ServerInstallation.self, from: JSONSerialization.data(withJSONObject: record))
        #expect(restored.id == saved.id)
        #expect(restored.ownerToken == saved.ownerToken)
        #expect(restored.previousReleaseHash == nil)
        #expect(restored.releaseFile == nil)
        let status = try JSONDecoder().decode(ServerInstallationStatus.self, from: Data(#"{"installationID":null,"state":"inactive","stage":"dependencies"}"#.utf8))
        #expect(status.canUpdateRelease == nil)
    }

    @Test func eachInstallerStageOwnsALaterPartOfTheBar() {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        var spans: [(first: Double, last: Double)] = []
        for (index, stage) in ["connecting", "dependencies", "download", "build", "verify"].enumerated() {
            var progress = ServerSetupProgress(at: start)
            progress.report(stage, at: start)
            #expect(progress.step == index + 1)
            spans.append((progress.value(at: start), progress.value(at: start + 86_400)))
        }
        #expect(ServerSetupProgress.steps == 5)
        #expect(spans[0].first == 0)
        // Even a day inside one stage never reaches the next stage's part.
        for (earlier, later) in zip(spans, spans.dropFirst()) { #expect(earlier.last < later.first) }
        // Building the image is most of the wait, so it owns most of the bar.
        #expect(spans[3].last - spans[3].first > 0.5)
    }

    @Test func progressEasesForwardInsideAStageWithoutCompletingIt() {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        var progress = ServerSetupProgress(at: start)
        progress.report("build", at: start)
        let values = stride(from: 0.0, through: 1200, by: 60).map { progress.value(at: start + $0) }
        for (earlier, later) in zip(values, values.dropFirst()) { #expect(later > earlier) }
        // Each minute adds less than the one before, so a slow build still moves.
        let steps = zip(values, values.dropFirst()).map { $1 - $0 }
        for (earlier, later) in zip(steps, steps.dropFirst()) { #expect(later < earlier) }
        var verify = ServerSetupProgress(at: start)
        verify.report("verify", at: start)
        #expect(verify.value(at: start + 86_400 * 365) < 1)
    }

    @Test func progressNeverMovesBackAndHoldsWhileReconnecting() {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        var progress = ServerSetupProgress(at: start)
        let reports: [(at: TimeInterval, stage: String)] = [
            (6, "dependencies"), (20, "reconnecting"), (45, "dependencies"), (50, "build"), (120, "reconnecting"),
            (150, "build"), (200, "dependencies"), (230, "build"), (420, "verify"), (430, "reconnecting"),
        ]
        var last = progress.value(at: start), second: TimeInterval = 0
        for report in reports {
            while second < report.at {
                second += 1
                let value = progress.value(at: start + second)
                #expect(value >= last, "\(second) s"); last = value
            }
            progress.report(report.stage, at: start + report.at)
            let value = progress.value(at: start + report.at)
            #expect(value >= last, "\(report.stage) at \(report.at) s"); last = value
        }
        // While SSH is away the bar keeps its place and its step.
        #expect(progress.stage == "reconnecting")
        #expect(progress.step == 5)
        #expect(progress.value(at: start + 900) == last)
        #expect(last < 1)
        progress.report("ready", at: start + 905)
        #expect(progress.value(at: start + 905) == 1)
        #expect(progress.step == 5)
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

    @Test @MainActor func interruptedBeforeRemoteIdentityReplaysTheSavedInstallation() async throws {
        let saved = try pendingInstallation()
        let transport = ServerSetupTestTransport(status: Data(#"{"installationID":null,"state":"inactive","stage":"dependencies","canUpdateRelease":true}"#.utf8))
        let store = ServerSetupMemoryStore(installation: saved)
        var releaseRequests = 0
        let connection = HomeConnection(url: "https://server.example.com:7789", token: "fixture", pin: String(repeating: "b", count: 64), name: "Server")
        let flow = ServerSetupFlow(store: store, probe: { _ in await transport.installInputs.isEmpty ? nil : connection }, transport: transport, release: {
            releaseRequests += 1
            return (String(repeating: "c", count: 64), "OpenStrudel-Home-1.0-60.tar.gz")
        })
        flow.confirm(access: ServerAccess(password: "fixture"))
        for _ in 0..<200 where flow.phase != .ready { try await Task.sleep(for: .milliseconds(5)) }
        #expect(flow.phase == .ready)
        flow.install(access: ServerAccess(password: "fixture"))
        for _ in 0..<200 where flow.phase == .ready || flow.phase == .installing { try await Task.sleep(for: .milliseconds(5)) }
        #expect(flow.phase == .connected)
        #expect(releaseRequests == 0, "An unstaged retry must retain its pinned release")
        #expect(store.installation?.id == saved.id)
        #expect(store.installation?.releaseHash == saved.releaseHash)
        #expect(store.installation?.ownerToken == saved.ownerToken)
        #expect(store.installation?.privateKeyPEM == saved.privateKeyPEM)
        let inputs = await transport.installInputs
        #expect(inputs.count == 1)
        #expect(inputs.first?.contains(saved.id) == true)
    }

    @Test @MainActor func changedRemoteIdentityCannotRunTheInstaller() async throws {
        let saved = try pendingInstallation()
        let transport = ServerSetupTestTransport(status: Data(#"{"installationID":"different","state":"failed","stage":"download","canUpdateRelease":true}"#.utf8))
        let store = ServerSetupMemoryStore(installation: saved)
        var releaseRequests = 0
        let flow = ServerSetupFlow(store: store, probe: { _ in nil }, transport: transport, release: {
            releaseRequests += 1
            return (String(repeating: "c", count: 64), "OpenStrudel-Home-1.0-60.tar.gz")
        })
        flow.confirm(access: ServerAccess(password: "fixture"))
        for _ in 0..<200 where flow.phase != .ready { try await Task.sleep(for: .milliseconds(5)) }
        flow.install(access: ServerAccess(password: "fixture"))
        for _ in 0..<200 where flow.phase == .ready || flow.phase == .installing { try await Task.sleep(for: .milliseconds(5)) }
        #expect(flow.phase == .failed)
        #expect(flow.error == .identity)
        #expect(releaseRequests == 0)
        #expect(await transport.installInputs.isEmpty)
        #expect(store.installation?.releaseHash == saved.releaseHash)
        #expect(store.installation?.previousReleaseHash == nil)
    }

    @Test @MainActor func failedOwnedReleaseCanBeUpdatedWithoutReplacingItsIdentity() async throws {
        let saved = try pendingInstallation()
        let status = try JSONSerialization.data(withJSONObject: ["installationID": saved.id, "state": "failed", "stage": "download", "canUpdateRelease": true])
        let transport = ServerSetupTestTransport(status: status)
        let store = ServerSetupMemoryStore(installation: saved)
        let connection = HomeConnection(url: "https://server.example.com:7789", token: "fixture", pin: String(repeating: "b", count: 64), name: "Server")
        let updatedHash = String(repeating: "c", count: 64)
        let flow = ServerSetupFlow(store: store, probe: { _ in await transport.installInputs.isEmpty ? nil : connection }, transport: transport,
                                   release: { (updatedHash, "OpenStrudel-Home-1.0-60.tar.gz") })
        flow.confirm(access: ServerAccess(password: "fixture"))
        for _ in 0..<200 where flow.phase != .ready { try await Task.sleep(for: .milliseconds(5)) }
        flow.install(access: ServerAccess(password: "fixture"))
        for _ in 0..<200 where flow.phase == .ready || flow.phase == .installing { try await Task.sleep(for: .milliseconds(5)) }
        #expect(flow.phase == .connected)
        #expect(store.installation?.releaseHash == updatedHash)
        #expect(store.installation?.releaseFile == "OpenStrudel-Home-1.0-60.tar.gz")
        #expect(store.installation?.previousReleaseHash == saved.releaseHash)
        #expect(store.installation?.id == saved.id)
        #expect(store.installation?.ownerToken == saved.ownerToken)
        #expect(store.installation?.privateKeyPEM == saved.privateKeyPEM)
        let inputs = await transport.installInputs
        #expect(inputs.count == 1)
        #expect(inputs.first?.contains("\"previousReleaseHash\":\"\(saved.releaseHash)\"") == true)
        #expect(inputs.first?.contains(#""releaseFile":"OpenStrudel-Home-1.0-60.tar.gz""#) == true)
    }

    @Test @MainActor func runningInstallationSurvivesALostStatusCheckWithoutReinstalling() async throws {
        let saved = try pendingInstallation()
        let status = try JSONSerialization.data(withJSONObject: ["installationID": saved.id, "state": "activating", "stage": "build"])
        let transport = ServerSetupTestTransport(status: status, statusFailure: .connection)
        let store = ServerSetupMemoryStore(installation: saved)
        let connection = HomeConnection(url: "https://server.example.com:7789", token: saved.ownerToken, pin: String(repeating: "b", count: 64), name: "Server")
        let flow = ServerSetupFlow(store: store, probe: { _ in
            await transport.statusRequests >= 2 ? connection : nil
        }, transport: transport)
        flow.confirm(access: ServerAccess(password: "fixture"))
        for _ in 0..<200 where flow.phase != .ready { try await Task.sleep(for: .milliseconds(5)) }
        flow.install(access: ServerAccess(password: "fixture"))
        for _ in 0..<1600 where flow.phase == .ready || flow.phase == .installing { try await Task.sleep(for: .milliseconds(5)) }
        #expect(flow.phase == .connected)
        #expect(flow.error == nil)
        #expect(await transport.installInputs.isEmpty)
        #expect(store.installation?.id == saved.id)
        #expect(flow.connection?.token == saved.ownerToken)
        flow.pause()
    }

    @Test @MainActor func lostInstallerAcknowledgementStillConnectsWhenTheServerIsReady() async throws {
        let saved = try pendingInstallation()
        let transport = ServerSetupTestTransport(status: Data(#"{"installationID":null,"state":"inactive","stage":"dependencies"}"#.utf8), installFailure: .connection)
        let connection = HomeConnection(url: "https://server.example.com:7789", token: saved.ownerToken, pin: String(repeating: "b", count: 64), name: "Server")
        let flow = ServerSetupFlow(store: ServerSetupMemoryStore(installation: saved), probe: { _ in
            await transport.installInputs.isEmpty ? nil : connection
        }, transport: transport)
        flow.confirm(access: ServerAccess(password: "fixture"))
        for _ in 0..<200 where flow.phase != .ready { try await Task.sleep(for: .milliseconds(5)) }
        flow.install(access: ServerAccess(password: "fixture"))
        for _ in 0..<200 where flow.phase == .ready || flow.phase == .installing { try await Task.sleep(for: .milliseconds(5)) }
        #expect(flow.phase == .connected)
        #expect(flow.error == nil)
        #expect(await transport.installInputs.count == 1)
    }

    @Test @MainActor func retryChecksTheReadyServerBeforeRequestingSSHCredentials() async throws {
        let saved = try pendingInstallation()
        let transport = ServerSetupTestTransport(status: Data())
        let connection = HomeConnection(url: "https://server.example.com:7789", token: saved.ownerToken, pin: String(repeating: "b", count: 64), name: "Server")
        let flow = ServerSetupFlow(store: ServerSetupMemoryStore(installation: saved), probe: { _ in connection }, transport: transport)
        flow.confirm(access: ServerAccess(password: "fixture"))
        for _ in 0..<200 where flow.phase != .ready { try await Task.sleep(for: .milliseconds(5)) }
        flow.install(access: ServerAccess())
        for _ in 0..<200 where flow.phase == .ready || flow.phase == .installing { try await Task.sleep(for: .milliseconds(5)) }
        #expect(flow.phase == .connected)
        #expect(await transport.statusRequests == 0)
        #expect(await transport.installInputs.isEmpty)
    }

    @Test @MainActor func authenticationAndIdentityFailuresDoNotBecomeConnectionRetries() async throws {
        for failure in [ServerSetupFailure.authentication, .hostKey, .identity] {
            let saved = try pendingInstallation()
            let status = try JSONSerialization.data(withJSONObject: ["installationID": saved.id, "state": "activating", "stage": "build"])
            let transport = ServerSetupTestTransport(status: status, statusFailure: failure)
            let flow = ServerSetupFlow(store: ServerSetupMemoryStore(installation: saved), probe: { _ in nil }, transport: transport)
            flow.confirm(access: ServerAccess(password: "fixture"))
            for _ in 0..<200 where flow.phase != .ready { try await Task.sleep(for: .milliseconds(5)) }
            flow.install(access: ServerAccess(password: "fixture"))
            for _ in 0..<200 where flow.phase == .ready || flow.phase == .installing { try await Task.sleep(for: .milliseconds(5)) }
            #expect(flow.phase == .failed)
            #expect(flow.error == failure)
            #expect(await transport.statusRequests == 2)
            flow.pause()
        }
    }

    @Test @MainActor func anInstallationThatNeverStartedPausesWithContinueInsteadOfWaiting() async throws {
        let saved = try pendingInstallation()
        let transport = ServerSetupTestTransport(status: Data(#"{"installationID":null,"state":"inactive","stage":"dependencies"}"#.utf8), installFailure: .connection)
        let store = ServerSetupMemoryStore(installation: saved)
        let flow = ServerSetupFlow(store: store, probe: { _ in nil }, transport: transport)
        flow.confirm(access: ServerAccess(password: "fixture"))
        for _ in 0..<200 where flow.phase != .ready { try await Task.sleep(for: .milliseconds(5)) }
        flow.install(access: ServerAccess(password: "fixture"))
        for _ in 0..<1600 where flow.phase == .ready || flow.phase == .installing { try await Task.sleep(for: .milliseconds(5)) }
        #expect(flow.phase == .paused)
        #expect(flow.error == .notStarted)
        #expect(await transport.installInputs.count == 1, "Pausing never starts a second job")
        #expect(store.installation?.id == saved.id)
        flow.pause()
    }

    @Test @MainActor func installingMovesTheProgressToTheServersStage() async throws {
        let saved = try pendingInstallation()
        let status = try JSONSerialization.data(withJSONObject: ["installationID": saved.id, "state": "activating", "stage": "build"])
        let transport = ServerSetupTestTransport(status: status)
        let flow = ServerSetupFlow(store: ServerSetupMemoryStore(installation: saved), probe: { _ in nil }, transport: transport)
        flow.confirm(access: ServerAccess(password: "fixture"))
        for _ in 0..<200 where flow.phase != .ready { try await Task.sleep(for: .milliseconds(5)) }
        flow.install(access: ServerAccess(password: "fixture"))
        for _ in 0..<400 where flow.stage != "build" { try await Task.sleep(for: .milliseconds(5)) }
        #expect(flow.phase == .installing)
        #expect(flow.stage == "build")
        #expect(flow.progress.step == 4)
        #expect(flow.progress.value(at: .now) > 0.1)
        flow.pause()
    }

    @Test @MainActor func aFinishedServerJoinsTheListWithoutOpeningSetup() async throws {
        let saved = try pendingInstallation()
        let store = ServerSetupMemoryStore(installation: saved)
        let key = String(repeating: "c", count: 64)
        let connection = HomeConnection(url: "https://127.0.0.1:9", token: key, pin: key, name: "Server")
        let busy = ServerSetupFlow(store: store, probe: { _ in try await Task.sleep(for: .milliseconds(50)); return nil })
        busy.resume()
        #expect(await busy.finishedConnection() == nil, "An open setup page owns its own check")
        busy.pause()

        let flow = ServerSetupFlow(store: store, probe: { _ in connection })
        #expect(flow.phase == .paused)
        let finished = try #require(await flow.finishedConnection())
        let suite = "OpenStrudel.finished-server." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(connection.url, forKey: "openstrudel.homeURL")
        let client = HomeClient(defaults: defaults, connectionID: suite, credentialReader: { _, _ in nil }, credentialWriter: { _, _ in })
        let library = DeviceLibrary(defaults: defaults, clients: [client])
        #expect(try await library.adoptServer(finished, from: flow) === client)
        #expect(client.hasToken && client.normalizedBaseURL == connection.url)
        #expect(store.installation == nil)
        #expect(flow.installation == nil)
        #expect(await flow.finishedConnection() == nil)
    }

    @Test @MainActor func theWatcherAndAnOpenSetupPageAdoptAFinishedServerOnce() async throws {
        let store = ServerSetupMemoryStore(installation: try pendingInstallation())
        let key = String(repeating: "c", count: 64)
        let connection = HomeConnection(url: "https://127.0.0.1:9", token: key, pin: key, name: "Server")
        let flow = ServerSetupFlow(store: store, probe: { _ in connection })
        let suite = "OpenStrudel.adopted-once." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(connection.url, forKey: "openstrudel.homeURL")
        let client = HomeClient(defaults: defaults, connectionID: suite, credentialReader: { _, _ in nil }, credentialWriter: { _, _ in })
        let library = DeviceLibrary(defaults: defaults, clients: [client])
        async let watcher = library.adoptServer(connection, from: flow)
        async let page = library.adoptServer(connection, from: flow)
        let (first, second) = try await (watcher, page)
        #expect(first === client && second === client, "Both get the one connection; no second client or credential")
        #expect(library.clients.count == 1)
        #expect(store.installation == nil)
    }

    @Test @MainActor func startingOverForgetsAPendingSetupOnThisMacWithoutContactingTheServer() async throws {
        let saved = try pendingInstallation()
        let store = ServerSetupMemoryStore(installation: saved)
        let transport = ServerSetupTestTransport(status: Data())
        var probes = 0
        let flow = ServerSetupFlow(store: store, probe: { _ in probes += 1; try await Task.sleep(for: .milliseconds(30)); return nil }, transport: transport)
        #expect(flow.phase == .paused)
        store.failSave = true
        #expect(throws: ServerSetupFailure.storage) { try flow.startOver() }
        #expect(flow.installation?.id == saved.id, "Keychain still holds the setup, so this Mac keeps showing it")
        #expect(store.installation?.id == saved.id)
        store.failSave = false
        flow.resume()
        try flow.startOver()
        try await Task.sleep(for: .milliseconds(80))
        #expect(store.installation == nil)
        #expect(flow.installation == nil && flow.target == nil && flow.hostKey == nil && flow.error == nil)
        #expect(flow.phase == .address, "A check that was under way does not bring the setup back")
        #expect(probes == 1)
        #expect(await transport.statusRequests == 0)
        #expect(await transport.installInputs.isEmpty)
        flow.inspect(try ServerTarget(host: "other.example.com", user: "root", port: 22))
        for _ in 0..<200 where flow.phase != .failed { try await Task.sleep(for: .milliseconds(5)) }
        #expect(flow.target?.host == "other.example.com", "Another server can be set up next")
    }

    private func pendingInstallation() throws -> ServerInstallation {
        let target = try ServerTarget(host: "server.example.com", user: "root", port: 22)
        let key = try SSHHostKey(line: "host ssh-ed25519 " + Data(repeating: 1, count: 51).base64EncodedString(), target: target)
        return try ServerInstallation(target: target, hostKey: key, releaseHash: String(repeating: "a", count: 64))
    }
}

private actor ServerSetupTestTransport: ServerSSHTransport {
    let status: Data
    let statusFailure: ServerSetupFailure?
    let installFailure: ServerSetupFailure?
    private(set) var statusRequests = 0
    private(set) var installInputs: [String] = []
    init(status: Data, statusFailure: ServerSetupFailure? = nil, installFailure: ServerSetupFailure? = nil) {
        self.status = status; self.statusFailure = statusFailure; self.installFailure = installFailure
    }
    func scan(_ target: ServerTarget) async throws -> SSHHostKey { throw ServerSetupFailure.hostKey }
    func run(target: ServerTarget, key: SSHHostKey, access: ServerAccess, input: Data, elevated: Bool) async throws -> Data {
        let script = String(decoding: input, as: UTF8.self)
        if script.hasSuffix("\ncheck_server\n") {
            return try JSONEncoder().encode(ServerPreflight(os: "ubuntu", version: "24.04", architecture: "x86_64", memoryMiB: 3900, diskGiB: 35, freeGiB: 20, administrator: true, python: true, installationID: nil, existing: false, portBusy: false))
        }
        if script.hasSuffix("\nserver_status\n") {
            statusRequests += 1
            if statusRequests == 2, let statusFailure { throw statusFailure }
            return status
        }
        if script.contains("\ninstall_server <<'OPENSTRUDEL_SETUP_INPUT'\n") {
            installInputs.append(script)
            if let installFailure { throw installFailure }
            return Data()
        }
        throw ServerSetupFailure.installer
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
    var failSave = false
    init(installation: ServerInstallation?) { self.installation = installation }
    func load() throws -> ServerInstallation? { installation }
    func save(_ installation: ServerInstallation?) throws {
        if failSave { throw ServerSetupFailure.storage }
        self.installation = installation
    }
}

@Suite("Real SSH setup", .serialized, .enabled(if: ProcessInfo.processInfo.environment["OPENSTRUDEL_SSH_INTEGRATION"] == "1"))
struct ServerSSHIntegrationTests {
    private struct Fixture: Decodable { let host: String; let port: Int; let user: String; let key: String; let wrongKey: String; let hostKey: String; let encryptedKey: String?; let passphrase: String? }
    private func configuration() throws -> Fixture {
        if let directory = ProcessInfo.processInfo.environment["OPENSTRUDEL_SSH_FIXTURE_DIRECTORY"] {
            return try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: URL(fileURLWithPath: directory).appending(path: "fixture.json")))
        }
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 { root.deleteLastPathComponent() }
        return try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: root.appending(path: ".data/remaining-work-2026-10-12/ssh/fixture.json")))
    }
    private func fixture() throws -> (ServerTarget, SSHHostKey, ServerAccess, ServerAccess) {
        let fixture = try configuration()
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
        let line = try String(contentsOfFile: configuration().wrongKey + ".pub", encoding: .utf8).split(whereSeparator: \.isWhitespace)
        let changed = try SSHHostKey(line: "\(target.knownHostsName) \(line[0]) \(line[1])", target: target)
        await #expect(throws: ServerSetupFailure.hostKey) {
            _ = try await SSHServerTransport().run(target: target, key: changed, access: access, input: Data("echo MUST_NOT_RUN\n".utf8))
        }
    }
    @Test(.enabled(if: ProcessInfo.processInfo.environment["OPENSTRUDEL_SSH_FIXTURE_DIRECTORY"] != nil))
    func pastedEncryptedKeyAuthenticatesWithoutSavingItsPassphrase() async throws {
        let config = try configuration()
        let raw = try String(contentsOfFile: #require(config.encryptedKey), encoding: .utf8)
        let normalized = try SSHPrivateKey.normalized(Data(("\n" + raw.replacingOccurrences(of: "\n", with: "\r\n") + "  ").utf8))
        let (target, hostKey, _, _) = try fixture()
        let access = ServerAccess(privateKey: normalized, passphrase: try #require(config.passphrase))
        let result = try await SSHServerTransport().run(target: target, key: hostKey, access: access, input: Data("printf 'authenticated'\n".utf8))
        #expect(String(decoding: result, as: UTF8.self) == "authenticated")
        await #expect(throws: ServerSetupFailure.authentication) {
            _ = try await SSHServerTransport().run(target: target, key: hostKey, access: ServerAccess(privateKey: normalized, passphrase: "wrong-fixture-passphrase"), input: Data("echo MUST_NOT_RUN\n".utf8))
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
