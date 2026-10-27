import Foundation
import Testing

@Suite("AgentMetal checkout", .serialized)
struct AgentMetalTests {
    @Test @MainActor func cancelledPaymentCheckDoesNotBecomeANetworkError() async throws {
        let wire = MetalTestHTTP()
        let client = try AgentMetalClient(store: MetalTestStore(), transport: wire)
        _ = try await client.checkout(AgentMetalOffer(plan: "small", location: "ash", days: 1, dailyPrice: 2.2))
        wire.cancelled = true
        await #expect(throws: CancellationError.self) { try await client.poll() }
        let flow = AgentMetalSetupFlow(client: client)
        await flow.load(days: 1)
        await flow.checkPayment()
        #expect(flow.error == nil)
        #expect(flow.order.checkout != nil)
    }

    @Test func selectsOnlyACompatiblePublicServer() throws {
        let catalog = Data(#"{"plans":[{"id":"nano","memory_gb":2,"disk_gb":40,"usd_per_day":"1.20"},{"id":"small","memory_gb":4,"disk_gb":80,"usd_per_day":"2.20"}],"locations":[{"code":"cdmx-1","network":"shared public IPv4"},{"code":"ash"}],"images":[{"os":"ubuntu-24.04"}]}"#.utf8)
        let offer = try AgentMetalOffer.catalog(catalog, days: 1)
        #expect(offer.plan == "small")
        #expect(offer.location == "ash")
        #expect(offer.amount == Decimal(string: "2.20"))
        #expect(throws: AgentMetalFailure.self) { try AgentMetalOffer.catalog(catalog, days: 31) }
        #expect(throws: AgentMetalFailure.self) { try AgentMetalOffer.catalog(Data(#"{"plans":[],"locations":[]}"#.utf8), days: 1) }
    }

    @Test func checkoutRejectsForeignDestinationsAndChangedAmounts() throws {
        let offer = AgentMetalOffer(plan: "small", location: "ash", days: 1, dailyPrice: Decimal(string: "2.20")!)
        let accepted = Self.checkout()
        #expect(try AgentMetalCheckout.decode(accepted, offer: offer).sessionID == "cs_live_fixture")
        for bad in [Self.checkout(host: "checkout.stripe.com.evil.test"), Self.checkout(amount: "4400000"), Self.checkout(session: "../other")] {
            #expect(throws: AgentMetalFailure.self) { try AgentMetalCheckout.decode(bad, offer: offer) }
        }
    }

    @Test @MainActor func retryAfterUnknownResultReusesTheDurableRequest() async throws {
        let store = MetalTestStore()
        let wire = MetalTestHTTP()
        let client = try AgentMetalClient(store: store, transport: wire)
        let offer = AgentMetalOffer(plan: "small", location: "ash", days: 1, dailyPrice: Decimal(string: "2.20")!)
        wire.failure = true
        await #expect(throws: Error.self) { try await client.checkout(offer) }
        let original = try #require(wire.requests.first)
        wire.failure = false
        let resumed = try AgentMetalClient(store: store, transport: wire)
        _ = try await resumed.checkout(offer)
        #expect(wire.requests.last?.httpBody == original.httpBody)
        #expect(wire.requests.last?.value(forHTTPHeaderField: "Idempotency-Key") == original.value(forHTTPHeaderField: "Idempotency-Key"))
        let count = wire.requests.count
        _ = try await resumed.checkout(offer)
        #expect(wire.requests.count == count, "Reopening a saved checkout must not create a new order")
        await #expect(throws: AgentMetalFailure.self) {
            try await resumed.checkout(AgentMetalOffer(plan: "small", location: "ash", days: 7, dailyPrice: Decimal(string: "2.20")!))
        }
    }

    @Test @MainActor func storageFailurePreventsCheckoutAndPaymentDoesNotMeanReady() async throws {
        let store = MetalTestStore(); let wire = MetalTestHTTP()
        let client = try AgentMetalClient(store: store, transport: wire)
        store.failSave = true
        await #expect(throws: AgentMetalFailure.self) {
            try await client.checkout(AgentMetalOffer(plan: "small", location: "ash", days: 1, dailyPrice: 2.2))
        }
        #expect(wire.requests.isEmpty)
        store.failSave = false
        _ = try await client.checkout(AgentMetalOffer(plan: "small", location: "ash", days: 1, dailyPrice: 2.2))
        wire.response = Data(#"{"status":"pending"}"#.utf8)
        #expect(try await client.poll() == nil)
        #expect(client.state.server == nil)
    }

    @Test @MainActor func provisioningResponseDoesNotReplaceTheOneTimeReceipt() async throws {
        let store = MetalTestStore(); let wire = MetalTestHTTP()
        let client = try AgentMetalClient(store: store, transport: wire)
        _ = try await client.checkout(AgentMetalOffer(plan: "small", location: "ash", days: 1, dailyPrice: 2.2))
        wire.response = Data(#"{"status":"provisioning"}"#.utf8)
        #expect(try await client.poll() == nil)
        #expect(client.state.receipt == nil)
        let resumed = try AgentMetalClient(store: store, transport: wire)
        wire.response = try Self.receipt()
        let server = try #require(try await resumed.poll())
        #expect(server.expiry != nil)
        #expect(resumed.state.privateKey != nil)
        let requestCount = wire.requests.count
        let reopened = try AgentMetalClient(store: store, transport: wire)
        #expect(try await reopened.poll() == server)
        #expect(wire.requests.count == requestCount, "Never request a one-time key again after it was saved")
    }

    @Test @MainActor func invalidReceiptStillPreservesTheOnlyKey() async throws {
        let store = MetalTestStore(); let wire = MetalTestHTTP()
        let client = try AgentMetalClient(store: store, transport: wire)
        _ = try await client.checkout(AgentMetalOffer(plan: "small", location: "ash", days: 1, dailyPrice: 2.2))
        let receipt = try Self.receipt(ip: "127.0.0.1")
        wire.response = receipt
        await #expect(throws: Error.self) { try await client.poll() }
        #expect(try AgentMetalClient(store: store, transport: wire).state.receipt == receipt)
        #expect(client.state.server == nil)
    }

    @Test @MainActor func lockedKeychainRetriesSavingTheReceiptBeforePollingAgain() async throws {
        let store = MetalTestStore(); let wire = MetalTestHTTP()
        let client = try AgentMetalClient(store: store, transport: wire)
        _ = try await client.checkout(AgentMetalOffer(plan: "small", location: "ash", days: 1, dailyPrice: 2.2))
        wire.response = try Self.receipt()
        wire.onReply = { store.failSave = true } // Locks while the provider's one-time response is arriving.
        await #expect(throws: AgentMetalFailure.self) { try await client.poll() }
        let requests = wire.requests.count
        store.failSave = false
        wire.response = Data(#"{"status":"ready"}"#.utf8) // The provider no longer has the key.
        #expect(try await client.poll() != nil)
        #expect(wire.requests.count == requests)
    }

    @Test @MainActor func lockedKeychainDoesNotConsumeAOneTimeReceipt() async throws {
        let store = MetalTestStore(); let wire = MetalTestHTTP()
        let client = try AgentMetalClient(store: store, transport: wire)
        _ = try await client.checkout(AgentMetalOffer(plan: "small", location: "ash", days: 1, dailyPrice: 2.2))
        let count = wire.requests.count
        wire.response = try Self.receipt(); store.failSave = true
        await #expect(throws: AgentMetalFailure.self) { try await client.poll() }
        #expect(wire.requests.count == count)
    }

    @Test @MainActor func changedPriceRefreshesTheVisibleOfferWithoutChangingTheOrder() async throws {
        let store = MetalTestStore(); let wire = MetalTestHTTP()
        let client = try AgentMetalClient(store: store, transport: wire)
        let flow = AgentMetalSetupFlow(client: client)
        func catalog(_ price: String) -> Data {
            Data("{\"plans\":[{\"id\":\"small\",\"memory_gb\":4,\"disk_gb\":80,\"usd_per_day\":\"\(price)\"}],\"locations\":[{\"code\":\"ash\"}],\"images\":[{\"os\":\"ubuntu-24.04\"}]}".utf8)
        }
        wire.response = catalog("2.20")
        await flow.load(days: 1)
        wire.response = Self.checkout(amount: "4400000")
        wire.routeResponses["/v1/catalog"] = catalog("4.40")
        #expect(await flow.checkout() == nil)
        #expect(flow.offer?.amount == Decimal(string: "4.40"))
        #expect(flow.error != nil, "Explain the change before the user confirms the new amount")
        #expect(await flow.checkout() != nil)
        let requests = wire.requests.filter { $0.httpMethod == "POST" }
        #expect(requests.count == 2)
        #expect(requests.first?.httpBody == requests.last?.httpBody)
        #expect(requests.first?.value(forHTTPHeaderField: "Idempotency-Key") == requests.last?.value(forHTTPHeaderField: "Idempotency-Key"))
    }

    @Test func fractionalLeaseDatesAreAcceptedWithoutAcceptingPrivateAddresses() throws {
        let server = AgentMetalServer(id: "srv_fixture", ipv4: "8.8.4.4", ssh_port: 22, expires_at: "2026-10-15T12:34:56.789Z")
        try server.validate()
        #expect(server.expiry != nil)
    }

    @Test @MainActor func anotherOrderPreservesThePaidServersKeysAndConnection() async throws {
        let store = MetalTestStore(); let wire = MetalTestHTTP()
        let client = try AgentMetalClient(store: store, transport: wire)
        #expect(throws: AgentMetalFailure.self) { try client.newOrder() }
        _ = try await client.checkout(AgentMetalOffer(plan: "small", location: "ash", days: 1, dailyPrice: 2.2))
        wire.response = try Self.receipt()
        _ = try await client.poll()
        #expect(throws: AgentMetalFailure.self) { try client.newOrder() }
        let connection = HomeConnection(url: "https://8.8.4.4:7789", token: "test-owner", pin: "test-pin", name: "Server")
        try client.saveConnection(connection)
        try client.newOrder()
        let reopened = try AgentMetalClient(store: store, transport: wire)
        #expect(reopened.state.intent == nil)
        #expect(reopened.completedOrders.count == 1)
        #expect(reopened.completedOrders.first?.connection?.url == connection.url)
        #expect(reopened.completedOrders.first?.privateKey != nil)
        #expect(reopened.completedOrders.first?.receipt != nil)
    }

    @Test @MainActor func unknownStoredDataCannotStartAnotherPaidOrder() {
        let store = MetalTestStore(); store.data = Data(#"{"unexpected":"data"}"#.utf8)
        #expect(throws: AgentMetalFailure.self) { try AgentMetalClient(store: store, transport: MetalTestHTTP()) }
    }

    @Test @MainActor func installerPinsTheConfirmedSSHKeyAndChecksThePaidInstanceBeforeRunningCommands() async throws {
        let store = MetalTestStore(); let wire = MetalTestHTTP()
        let client = try AgentMetalClient(store: store, transport: wire)
        _ = try await client.checkout(AgentMetalOffer(plan: "small", location: "ash", days: 1, dailyPrice: 2.2))
        wire.response = try Self.receipt(); _ = try await client.poll()
        let target = try ServerTarget(host: "8.8.4.4", user: "root", port: 22)
        let base = MetalTestSSH()
        let ssh = AgentMetalSSHTransport(client: client, base: base)
        let key = try await ssh.scan(target)
        #expect(try AgentMetalClient(store: store, transport: wire).state.hostKey == nil, "A scanned key is trusted only after the person confirms it")
        let access = ServerAccess(privateKey: client.state.privateKey)
        // The first command runs only after confirmation, and pins the key.
        _ = try await ssh.run(target: target, key: key, access: access, input: Data("check_server".utf8), elevated: false)
        #expect(try AgentMetalClient(store: store, transport: wire).state.hostKey == key)
        #expect(await base.commandCount == 2)
        _ = try await ssh.run(target: target, key: key, access: access, input: Data("server_status".utf8), elevated: false)
        #expect(await base.commandCount == 3, "Do not repeatedly mutate the provider firewall")
        let changed = try SSHHostKey(line: "8.8.4.4 ssh-ed25519 " + Data(repeating: 9, count: 64).base64EncodedString(), target: target)
        await #expect(throws: ServerSetupFailure.self) {
            try await ssh.run(target: target, key: changed, access: access, input: Data(), elevated: false)
        }
        #expect(await base.commandCount == 3)
        let wrongInstance = AgentMetalSSHTransport(client: client, base: MetalTestSSH(wrongIdentity: true))
        await #expect(throws: ServerSetupFailure.self) {
            try await wrongInstance.run(target: target, key: key, access: access, input: Data("must-not-run".utf8), elevated: false)
        }
    }

    @Test @MainActor func paidServerWaitsForThePersonToConfirmItsSSHFingerprint() async throws {
        let store = MetalTestStore(); let wire = MetalTestHTTP()
        let client = try AgentMetalClient(store: store, transport: wire)
        _ = try await client.checkout(AgentMetalOffer(plan: "small", location: "ash", days: 1, dailyPrice: 2.2))
        wire.response = try Self.receipt()
        let ssh = MetalInstallationSSH()
        let flow = AgentMetalSetupFlow(client: client) { client in
            ServerSetupFlow(store: MetalInstallationStore(client: client), probe: { _ in nil },
                            transport: ssh, release: { (String(repeating: "a", count: 64), "OpenStrudel-Home-1.0-59.tar.gz") })
        }
        await flow.load(days: 1); await flow.checkPayment()
        for _ in 0..<200 where flow.installer?.hostKey == nil { try await Task.sleep(for: .milliseconds(5)) }
        try await Task.sleep(for: .milliseconds(50))
        #expect(flow.installer?.phase == .confirmIdentity)
        #expect(ssh.commands == 0, "The provider does not supply a fingerprint, so nothing runs over SSH before the person confirms it")
        let identity = try #require(flow.identityToConfirm)
        #expect(identity == flow.installer?.hostKey)
        flow.confirmIdentity()
        for _ in 0..<200 where ssh.installInputs.isEmpty { try await Task.sleep(for: .milliseconds(5)) }
        #expect(ssh.commands > 1)
        #expect(!ssh.installInputs.isEmpty)
        #expect(client.state.installation?.hostKey == identity, "The installation uses the confirmed key")
        flow.pause()
    }

    @Test @MainActor func interruptedSetupResumesTheSameInstallationWithoutAnotherPurchase() async throws {
        let store = MetalTestStore(); let wire = MetalTestHTTP()
        let client = try AgentMetalClient(store: store, transport: wire)
        _ = try await client.checkout(AgentMetalOffer(plan: "small", location: "ash", days: 1, dailyPrice: 2.2))
        wire.response = try Self.receipt()
        let ssh = MetalInstallationSSH()
        let first = AgentMetalSetupFlow(client: client) { client in
            ServerSetupFlow(store: MetalInstallationStore(client: client), probe: { _ in nil },
                            transport: ssh, release: { (String(repeating: "a", count: 64), "OpenStrudel-Home-1.0-59.tar.gz") })
        }
        await first.load(days: 1); await first.checkPayment()
        for _ in 0..<200 where first.identityToConfirm == nil { try await Task.sleep(for: .milliseconds(5)) }
        first.confirmIdentity()
        for _ in 0..<200 where ssh.installInputs.isEmpty { try await Task.sleep(for: .milliseconds(5)) }
        #expect(!ssh.installInputs.isEmpty)
        #expect(first.error == nil, "A lost SSH acknowledgement keeps observing the saved installation")
        let saved = try #require(client.state.installation)
        #expect(saved.attempted)
        #expect(saved.releaseFile == "OpenStrudel-Home-1.0-59.tar.gz")
        #expect(ssh.installInputs.first?.contains(#""releaseFile":"OpenStrudel-Home-1.0-59.tar.gz""#) == true)
        first.pause()
        let requestCount = wire.requests.count
        let reopened = try AgentMetalClient(store: store, transport: wire)
        ssh.failInstallation = false
        let second = AgentMetalSetupFlow(client: reopened) { client in
            ServerSetupFlow(store: MetalInstallationStore(client: client), probe: { pending in
                #expect(pending.id == saved.id)
                #expect(pending.ownerToken == saved.ownerToken)
                #expect(pending.privateKeyPEM == saved.privateKeyPEM)
                // Stay unavailable until the unstaged recipe has been replayed.
                return ssh.installInputs.count < 2 ? nil : HomeConnection(url: "https://8.8.4.4:7789", token: pending.ownerToken, pin: "fixture", name: "Server")
            }, transport: ssh, release: { Issue.record("Do not replace the pinned release"); return ("", "") })
        }
        await second.load(days: 1); await second.checkPayment()
        for _ in 0..<200 where second.connection == nil { try await Task.sleep(for: .milliseconds(5)) }
        let connection = try #require(second.connection)
        #expect(ssh.installInputs.count == 2)
        #expect(ssh.installInputs.allSatisfy { $0.contains(saved.id) })
        #expect(wire.requests.count == requestCount, "Do not request another checkout or one-time key")
        try second.saveConnection(connection)
        let final = try AgentMetalClient(store: store, transport: wire)
        #expect(final.state.connection?.token == saved.ownerToken)
        #expect(final.state.installation == nil)
        #expect(final.state.privateKey != nil)
    }

    @Test @MainActor func closingDuringPaymentCheckSavesTheReceiptWithoutStartingAnInstallation() async throws {
        let store = MetalTestStore(); let wire = MetalTestHTTP()
        let client = try AgentMetalClient(store: store, transport: wire)
        _ = try await client.checkout(AgentMetalOffer(plan: "small", location: "ash", days: 1, dailyPrice: 2.2))
        var installations = 0
        let flow = AgentMetalSetupFlow(client: client) { client in
            installations += 1
            return ServerSetupFlow(store: MetalInstallationStore(client: client))
        }
        await flow.load(days: 1)
        wire.delayed = true
        let checking = Task { await flow.checkPayment() }
        for _ in 0..<200 where wire.continuation == nil { await Task.yield() }
        let continuation = try #require(wire.continuation)
        flow.pause()
        continuation.resume(returning: try Self.receipt())
        await checking.value
        #expect(installations == 0)
        #expect(!flow.busy)
        #expect(try AgentMetalClient(store: store, transport: wire).state.privateKey != nil)
    }

    @Test @MainActor func eraseWhileCheckoutIsInFlightCannotRestoreDeletedCredentials() async throws {
        let store = MetalTestStore(); let wire = MetalTestHTTP()
        let client = try AgentMetalClient(store: store, transport: wire)
        _ = try await client.checkout(AgentMetalOffer(plan: "small", location: "ash", days: 1, dailyPrice: 2.2))
        let flow = AgentMetalSetupFlow(client: client)
        await flow.load(days: 1)
        wire.delayed = true
        let checking = Task { await flow.checkPayment() }
        for _ in 0..<200 where wire.continuation == nil { await Task.yield() }
        let continuation = try #require(wire.continuation)
        flow.prepareForLocalErase()
        store.data = nil // LocalDataReset has removed the provider's Keychain item.
        continuation.resume(returning: try Self.receipt())
        await checking.value
        #expect(store.data == nil)
        #expect(flow.order.intent == nil)
        #expect(flow.installer == nil)
        #expect(!flow.working)
    }

    static func receipt(ip: String = "8.8.4.4") throws -> Data {
        let key = "-----BEGIN OPENSSH PRIVATE KEY-----\n" + Data(repeating: 3, count: 64).base64EncodedString() + "\n-----END OPENSSH PRIVATE KEY-----\n"
        return try JSONSerialization.data(withJSONObject: ["status": "ready", "ssh_private_key": key,
            "server": ["id": "srv_fixture", "ipv4": ip, "ssh_port": 22, "expires_at": "2026-10-15T12:34:56.789Z"]])
    }

    static func checkout(host: String = "checkout.stripe.com", amount: String = "2200000", session: String = "cs_live_fixture") -> Data {
        Data("{\"accepts\":[{\"amount\":\"\(amount)\",\"network\":\"eip155:8453\",\"asset\":\"0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913\"}],\"card\":{\"checkout_url\":\"https://\(host)/c/pay/\(session)\",\"session_id\":\"\(session)\"}}".utf8)
    }
}

@MainActor private struct MetalInstallationStore: ServerSetupStore {
    let client: AgentMetalClient
    func load() throws -> ServerInstallation? { client.state.installation }
    func save(_ installation: ServerInstallation?) throws { try client.saveInstallation(installation) }
}

@MainActor private final class MetalInstallationSSH: ServerSSHTransport {
    var failInstallation = true
    var installInputs: [String] = []
    var commands = 0
    func scan(_ target: ServerTarget) async throws -> SSHHostKey {
        try SSHHostKey(line: target.host + " ssh-ed25519 " + Data(repeating: 1, count: 64).base64EncodedString(), target: target)
    }
    func run(target: ServerTarget, key: SSHHostKey, access: ServerAccess, input: Data, elevated: Bool) async throws -> Data {
        commands += 1
        let script = String(decoding: input, as: UTF8.self)
        if script.hasSuffix("\ncheck_server\n") {
            return try JSONEncoder().encode(ServerPreflight(os: "ubuntu", version: "24.04", architecture: "x86_64", memoryMiB: 3900,
                diskGiB: 80, freeGiB: 60, administrator: true, python: true, installationID: nil, existing: false, portBusy: false))
        }
        if script.hasSuffix("\nserver_status\n") { return Data(#"{"installationID":null,"state":"inactive","stage":"dependencies"}"#.utf8) }
        if script.contains("\ninstall_server <<'OPENSTRUDEL_SETUP_INPUT'\n") {
            installInputs.append(script)
            if failInstallation { throw ServerSetupFailure.connection }
            return Data()
        }
        throw ServerSetupFailure.installer
    }
}

private actor MetalTestSSH: ServerSSHTransport {
    let wrongIdentity: Bool
    var commandCount = 0
    init(wrongIdentity: Bool = false) { self.wrongIdentity = wrongIdentity }
    func scan(_ target: ServerTarget) async throws -> SSHHostKey {
        try SSHHostKey(line: target.host + " ssh-ed25519 " + Data(repeating: 1, count: 64).base64EncodedString(), target: target)
    }
    func run(target: ServerTarget, key: SSHHostKey, access: ServerAccess, input: Data, elevated: Bool) async throws -> Data {
        commandCount += 1
        if String(decoding: input, as: UTF8.self).contains("prepare_agentmetal") {
            return Data((wrongIdentity ? #"{"ok":false,"problem":"identity"}"# : #"{"ok":true,"expiresAt":"2026-10-16T12:00:00.000Z"}"#).utf8)
        }
        #expect(!wrongIdentity, "Never run installer commands on the wrong instance")
        return Data("{}".utf8)
    }
}

@MainActor private final class MetalTestStore: AgentMetalStore {
    var data: Data?; var failSave = false
    func load() throws -> Data? { data }
    func save(_ value: Data) throws { if failSave { throw AgentMetalFailure.storage }; data = value }
}

@MainActor private final class MetalTestHTTP: AgentMetalTransport {
    var requests: [URLRequest] = []; var failure = false
    var cancelled = false
    var response = AgentMetalTests.checkout()
    var delayed = false
    var continuation: CheckedContinuation<Data, Never>?
    var onReply: (() -> Void)?
    var routeResponses: [String: Data] = [:]
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        if cancelled { throw URLError(.cancelled) }
        if failure { throw URLError(.networkConnectionLost) }
        let data = delayed ? await withCheckedContinuation { continuation = $0 } : (routeResponses[request.url!.path] ?? response)
        onReply?()
        return (data, HTTPURLResponse(url: request.url!, statusCode: request.httpMethod == "POST" ? 402 : 200, httpVersion: nil, headerFields: nil)!)
    }
}
