#if os(macOS)
import Foundation
import Combine

@MainActor private struct AgentMetalInstallationStore: ServerSetupStore {
    let client: AgentMetalClient
    func load() throws -> ServerInstallation? { client.state.installation }
    func save(_ installation: ServerInstallation?) throws { try client.saveInstallation(installation) }
}

/// Reuses the SSH installer, adding only the provider's instance identity and
/// network-edge firewall. AgentMetal supplies no host key fingerprint, so the
/// person confirms the scanned key; its first command pins it before any write.
@MainActor final class AgentMetalSSHTransport: ServerSSHTransport {
    let client: AgentMetalClient
    let base: any ServerSSHTransport
    private var prepared = false
    init(client: AgentMetalClient, base: any ServerSSHTransport = SSHServerTransport()) {
        self.client = client; self.base = base
    }
    private func server(for target: ServerTarget) throws -> AgentMetalServer {
        guard let server = client.state.server, target.host == server.ipv4, target.user == "root", target.port == 22 else { throw ServerSetupFailure.identity }
        try server.validate()
        return server
    }
    func scan(_ target: ServerTarget) async throws -> SSHHostKey {
        _ = try server(for: target)
        if let saved = client.state.hostKey { return saved }
        return try await base.scan(target)
    }
    func run(target: ServerTarget, key: SSHHostKey, access: ServerAccess, input: Data, elevated: Bool) async throws -> Data {
        let server = try server(for: target)
        guard access.privateKey == client.state.privateKey, access.privateKey != nil else { throw ServerSetupFailure.credentials }
        try client.saveHostKey(key)
        if !prepared {
            // Both interpolated values have bounded, shell-safe validation.
            let script = try ServerSetupScripts.resource("agentmetal-firewall")
                + Data("\nprepare_agentmetal '\(server.id)' '\(server.ipv4)'\n".utf8)
            let data = try await base.run(target: target, key: key, access: access, input: script, elevated: false)
            struct Result: Decodable { let ok: Bool; let problem: String?; let expiresAt: String? }
            let result = try JSONDecoder().decode(Result.self, from: data)
            guard result.ok else {
                if result.problem == "identity" { throw ServerSetupFailure.identity }
                if result.problem == "expired" { throw AgentMetalFailure.expired }
                throw ServerSetupFailure.serviceUnreachable
            }
            guard let expiry = result.expiresAt else { throw ServerSetupFailure.identity }
            try client.updateExpiry(expiry)
            try Task.checkCancellation()
            prepared = true
        }
        return try await base.run(target: target, key: key, access: access, input: input, elevated: elevated)
    }
}

@MainActor final class AgentMetalSetupFlow: ObservableObject {
    // Closing a sheet must not discard a one-time key awaiting a Keychain retry.
    static let shared = AgentMetalSetupFlow()
    @Published private(set) var order = AgentMetalState()
    @Published private(set) var offer: AgentMetalOffer?
    @Published private(set) var loading = false
    @Published private(set) var waiting = false
    @Published private(set) var installing = false
    @Published private(set) var error: String?
    @Published private(set) var installer: ServerSetupFlow?
    private var provider: AgentMetalClient?
    private var observer: AnyCancellable?
    private var resuming = false
    private var generation = UUID()
    private var erasing = false
    private let makeInstaller: (AgentMetalClient) -> ServerSetupFlow
    init(client: AgentMetalClient? = nil, installer: ((AgentMetalClient) -> ServerSetupFlow)? = nil) {
        provider = client
        makeInstaller = installer ?? { provider in
            ServerSetupFlow(store: AgentMetalInstallationStore(client: provider), transport: AgentMetalSSHTransport(client: provider))
        }
    }
    var connection: HomeConnection? { installer?.connection ?? order.connection }
    var busy: Bool { loading || waiting || installing }
    var working: Bool { (order.intent != nil && order.connection == nil) || busy }
    /// The scanned SSH key, waiting for the person to compare its fingerprint.
    var identityToConfirm: SSHHostKey? { installing && installer?.phase == .confirmIdentity ? installer?.hostKey : nil }

    func confirmIdentity() {
        guard let installer, let provider, identityToConfirm != nil else { return }
        installer.confirm(access: ServerAccess(privateKey: provider.state.privateKey))
    }

    func load(days: Int) async {
        guard !loading, !erasing else { return }
        let run = generation
        loading = true; error = nil
        defer { if generation == run { loading = false } }
        do {
            if provider == nil { provider = try AgentMetalClient() }
            guard let provider else { return }
            order = provider.state
            offer = order.intent?.offer
            if offer == nil {
                let value = try await provider.offer(days: days)
                guard generation == run else { return }
                offer = value
            }
        } catch { if generation == run { self.error = error.localizedDescription } }
    }
    func checkout() async -> URL? {
        guard !busy, !erasing, let provider, let offer else { return nil }
        let run = generation
        loading = true; error = nil
        defer { if generation == run { loading = false; order = provider.state } }
        do {
            let checkout = try await provider.checkout(offer)
            return generation == run ? checkout.url : nil
        }
        catch AgentMetalFailure.changedPrice {
            do {
                let updated = try await provider.refreshPrice()
                if generation == run { self.offer = updated; error = AgentMetalFailure.changedPrice.localizedDescription }
            } catch { if generation == run { self.error = error.localizedDescription } }
            return nil
        }
        catch { if generation == run { self.error = error.localizedDescription }; return nil }
    }
    func checkPayment() async {
        guard !busy, !erasing, let provider, order.connection == nil else { return }
        generation = UUID(); let run = generation
        waiting = true; error = nil
        defer { if generation == run { waiting = false } }
        do {
            for _ in 0..<60 {
                try Task.checkCancellation()
                guard generation == run else { return }
                let server = try await provider.poll()
                try Task.checkCancellation()
                guard generation == run else { return }
                if let server {
                    order = provider.state
                    try beginInstallation(server, provider: provider)
                    return
                }
                try await Task.sleep(for: .seconds(3))
            }
        } catch is CancellationError { }
        catch { if generation == run { self.error = error.localizedDescription; order = provider.state } }
    }
    private func beginInstallation(_ server: AgentMetalServer, provider: AgentMetalClient) throws {
        let flow = makeInstaller(provider)
        installer = flow; installing = true
        observer = flow.$phase.removeDuplicates().sink { [weak self] phase in
            Task { @MainActor [weak self, weak flow] in
                guard let self, let flow, self.installing, self.installer === flow, flow.phase == phase else { return }
                self.objectWillChange.send()
                self.advance(phase, flow: flow)
            }
        }
        if flow.installation != nil { resuming = true; flow.resume() }
        else { flow.inspect(try ServerTarget(host: server.ipv4, user: "root", port: 22)) }
    }
    private func advance(_ phase: ServerSetupFlow.Phase, flow: ServerSetupFlow) {
        guard let provider else { return }
        order = provider.state
        let access = ServerAccess(privateKey: order.privateKey)
        // .confirmIdentity waits for the person: see confirmIdentity().
        switch phase {
        case .ready: flow.install(access: access)
        case .paused where resuming && flow.error == nil:
            resuming = false; flow.confirm(access: access)
        case .failed, .paused:
            installing = false; error = flow.error?.localizedDescription
        case .connected: installing = false
        default: break
        }
    }
    func saveConnection(_ connection: HomeConnection) throws {
        guard let provider else { throw AgentMetalFailure.storage }
        try provider.saveConnection(connection)
        try installer?.finish()
        order = provider.state
    }
    func newOrder(days: Int) async {
        do {
            try provider?.newOrder()
            pause(); installer = nil; observer = nil; offer = nil
            await load(days: days)
        } catch { self.error = error.localizedDescription }
    }
    func pause() {
        generation = UUID(); loading = false; waiting = false; installing = false
        installer?.pause()
    }
    func prepareForLocalErase() {
        erasing = true; pause(); provider?.suspendForLocalErase()
        provider = nil; installer = nil; observer = nil; order = .init(); offer = nil; error = nil
    }
    func finishLocalErase() { erasing = false }
}
#endif
