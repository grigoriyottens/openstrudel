#if os(macOS)
import Foundation
import Security

/// AgentMetal's direct checkout. Card details never enter OpenStrudel.
enum AgentMetalFailure: Error, LocalizedError, Equatable {
    case unavailable, response, changedPrice, storage, busy, pendingOrder, missingKey, network, expired
    var errorDescription: String? {
        switch self {
        case .unavailable: L("No suitable servers are available. Try again later.")
        case .response: L("The provider returned an incomplete response. Your order has been kept.")
        case .changedPrice: L("The price has changed. Refresh the offer before paying.")
        case .storage: L("Could not save this order securely. Unlock your Mac and try again.")
        case .busy: L("An operation is already in progress.")
        case .pendingOrder: L("Finish your saved order before starting another.")
        case .missingKey: L("The server is paid for, but its access key is missing. Recover it from your AgentMetal payment receipt.")
        case .network: L("Could not reach AgentMetal. Your order is saved; try again.")
        case .expired: L("This server has expired. Check its status with AgentMetal before continuing.")
        }
    }
}

struct AgentMetalOffer: Codable, Equatable {
    let plan: String
    let location: String
    let days: Int
    let dailyPrice: Decimal
    var amount: Decimal { dailyPrice * Decimal(days) }

    static func catalog(_ data: Data, days: Int) throws -> Self {
        struct Catalog: Decodable {
            struct Plan: Decodable { let id: String; let memory_gb: Int; let disk_gb: Int; let usd_per_day: String }
            struct Location: Decodable { let code: String; let network: String? }
            struct Image: Decodable { let os: String }
            let plans: [Plan]; let locations: [Location]; let images: [Image]
        }
        guard (1...30).contains(days), let catalog = try? JSONDecoder().decode(Catalog.self, from: data),
              catalog.images.contains(where: { $0.os == "ubuntu-24.04" }) else { throw AgentMetalFailure.unavailable }
        // Mexico's shared-address servers cannot expose Home's HTTPS port.
        guard let location = ["ash", "hil"].first(where: { id in catalog.locations.contains { $0.code == id && $0.network == nil } }),
              let plan = catalog.plans.filter({ $0.memory_gb >= 4 && $0.disk_gb >= 30 && ["small", "medium"].contains($0.id) })
                .sorted(by: { $0.memory_gb < $1.memory_gb }).first,
              let price = Decimal(string: plan.usd_per_day, locale: Locale(identifier: "en_US_POSIX")), price > 0, price < 100
        else { throw AgentMetalFailure.unavailable }
        return Self(plan: plan.id, location: location, days: days, dailyPrice: price)
    }
}

struct AgentMetalCheckout: Codable, Equatable {
    let sessionID: String
    let url: URL
    static func decode(_ data: Data, offer: AgentMetalOffer) throws -> Self {
        struct Reply: Decodable {
            struct Card: Decodable { let session_id: String; let checkout_url: URL }
            struct Price: Decodable { let amount: String; let network: String; let asset: String }
            let card: Card; let accepts: [Price]
        }
        guard let value = try? JSONDecoder().decode(Reply.self, from: data),
              value.card.session_id.range(of: "^cs_live_[A-Za-z0-9_]{1,200}$", options: .regularExpression) != nil,
              let parts = URLComponents(url: value.card.checkout_url, resolvingAgainstBaseURL: false),
              parts.scheme == "https", parts.host == "checkout.stripe.com", parts.user == nil, parts.password == nil,
              parts.port == nil, parts.path == "/c/pay/" + value.card.session_id, parts.query == nil
        else { throw AgentMetalFailure.response }
        guard value.accepts.contains(where: { $0.network == "eip155:8453" && $0.asset.lowercased() == "0x833589fcd6edb6e08f4c7c32d4f71b54bda02913"
            && Decimal(string: $0.amount) == offer.amount * 1_000_000 }) else { throw AgentMetalFailure.changedPrice }
        return Self(sessionID: value.card.session_id, url: value.card.checkout_url)
    }
}

struct AgentMetalServer: Codable, Equatable {
    let id: String
    let ipv4: String
    let ssh_port: Int?
    let expires_at: String
    var expiry: Date? { ISO8601DateFormatter().date(from: expires_at) }
    func validate() throws {
        guard id.range(of: "^srv_[A-Za-z0-9_-]{1,100}$", options: .regularExpression) != nil,
              DigitalOceanHomeTrust.isPublicIPv4(ipv4), (ssh_port ?? 22) == 22, expiry != nil
        else { throw AgentMetalFailure.response }
    }
}

struct AgentMetalState: Codable {
    struct Intent: Codable { let id: String; let offer: AgentMetalOffer }
    var intent: Intent?
    var checkout: AgentMetalCheckout?
    // Save the one-time receipt in Keychain before interpreting it. A parser
    // failure or an app restart must not discard the provider's only SSH key.
    var receipt: Data?
    var server: AgentMetalServer?
    var privateKey: Data?
    var installation: ServerInstallation?
    var connection: HomeConnection?
}

@MainActor protocol AgentMetalStore {
    func load() throws -> Data?
    func save(_ value: Data) throws
}

@MainActor struct AgentMetalKeychain: AgentMetalStore {
    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: (Bundle.main.bundleIdentifier ?? "is.openstrudel.mac") + ".agentmetal",
         kSecAttrAccount as String: "orders"]
    }
    func load() throws -> Data? {
        var query = query; query[kSecReturnData as String] = true; query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIFail
        var value: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &value)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let value = value as? Data else { throw AgentMetalFailure.storage }
        return value
    }
    func save(_ value: Data) throws {
        var query = query; query[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIFail
        let attrs: [String: Any] = [kSecValueData as String: value, kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        var status = SecItemUpdate(query as CFDictionary, attrs as CFDictionary)
        if status == errSecItemNotFound { status = SecItemAdd(query.merging(attrs) { _, new in new } as CFDictionary, nil) }
        guard status == errSecSuccess else { throw AgentMetalFailure.storage }
    }
}

@MainActor protocol AgentMetalTransport {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}
@MainActor struct AgentMetalHTTP: AgentMetalTransport {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let session = DigitalOceanNoRedirects.session(); defer { session.invalidateAndCancel() }
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse, response.url == request.url, data.count <= 2_097_152 else { throw AgentMetalFailure.response }
        return (data, response)
    }
}

@MainActor final class AgentMetalClient {
    private let store: any AgentMetalStore
    private let transport: any AgentMetalTransport
    private(set) var state: AgentMetalState
    private var busy = false
    init(store: any AgentMetalStore = AgentMetalKeychain(), transport: any AgentMetalTransport = AgentMetalHTTP()) throws {
        self.store = store; self.transport = transport
        do { state = try store.load().map { try JSONDecoder().decode(AgentMetalState.self, from: $0) } ?? AgentMetalState() }
        catch { throw AgentMetalFailure.storage }
    }
    private func save(_ next: AgentMetalState) throws {
        do { try store.save(JSONEncoder().encode(next)); state = next }
        catch { throw AgentMetalFailure.storage }
    }
    private func request(_ path: String, body: Data? = nil, idempotency: String? = nil) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: URL(string: "https://api.agentmetal.dev" + path)!)
        request.timeoutInterval = 25; request.httpMethod = body == nil ? "GET" : "POST"
        request.httpBody = body; request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        if let idempotency { request.setValue(idempotency, forHTTPHeaderField: "Idempotency-Key") }
        do { return try await transport.send(request) }
        catch is CancellationError { throw CancellationError() }
        catch let error as AgentMetalFailure { throw error }
        catch { throw AgentMetalFailure.network }
    }
    func offer(days: Int) async throws -> AgentMetalOffer {
        let (data, response) = try await request("/v1/catalog")
        guard response.statusCode == 200 else { throw AgentMetalFailure.unavailable }
        return try AgentMetalOffer.catalog(data, days: days)
    }
    func checkout(_ offer: AgentMetalOffer) async throws -> AgentMetalCheckout {
        guard !busy else { throw AgentMetalFailure.busy }
        busy = true; defer { busy = false }
        guard (1...30).contains(offer.days), ["small", "medium"].contains(offer.plan), ["ash", "hil"].contains(offer.location), offer.dailyPrice > 0 else { throw AgentMetalFailure.unavailable }
        if let intent = state.intent, intent.offer != offer { throw AgentMetalFailure.pendingOrder }
        if let checkout = state.checkout { return checkout }
        if state.intent == nil {
            var next = state; next.intent = .init(id: UUID().uuidString, offer: offer); try save(next)
        }
        let body = try JSONSerialization.data(withJSONObject: ["plan": offer.plan, "days": offer.days,
            "os": "ubuntu-24.04", "location": offer.location, "managed_key": true], options: .sortedKeys)
        let (data, response) = try await request("/v1/servers", body: body, idempotency: state.intent!.id)
        guard response.statusCode == 402 else { throw AgentMetalFailure.response }
        let checkout = try AgentMetalCheckout.decode(data, offer: offer)
        var next = state; next.checkout = checkout; try save(next)
        return checkout
    }
    func poll() async throws -> AgentMetalServer? {
        guard !busy else { throw AgentMetalFailure.busy }
        busy = true; defer { busy = false }
        if let server = state.server { return server }
        if state.receipt == nil {
            guard let checkout = state.checkout else { throw AgentMetalFailure.pendingOrder }
            let (data, response) = try await request("/v1/orders/" + checkout.sessionID)
            guard response.statusCode == 200, let value = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw AgentMetalFailure.response }
            if value["status"] as? String == "pending" { return nil }
            var next = state; next.receipt = data; try save(next)
        }
        struct Ready: Decodable { let status: String; let server: AgentMetalServer; let ssh_private_key: String? }
        guard let receipt = state.receipt, let ready = try? JSONDecoder().decode(Ready.self, from: receipt), ready.status == "ready" else { throw AgentMetalFailure.response }
        try ready.server.validate()
        guard let key = ready.ssh_private_key else { throw AgentMetalFailure.missingKey }
        let normalized = try SSHPrivateKey.normalized(Data(key.utf8))
        var next = state; next.server = ready.server; next.privateKey = normalized; try save(next)
        return ready.server
    }
    func saveInstallation(_ installation: ServerInstallation?) throws {
        var next = state; next.installation = installation; try save(next)
    }
    func saveConnection(_ connection: HomeConnection) throws {
        var next = state; next.connection = connection; try save(next)
    }
}
#endif
