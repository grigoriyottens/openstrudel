import Foundation
import Testing

@Suite("AgentMetal checkout", .serialized)
struct AgentMetalTests {
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

    static func checkout(host: String = "checkout.stripe.com", amount: String = "2200000", session: String = "cs_live_fixture") -> Data {
        Data("{\"accepts\":[{\"amount\":\"\(amount)\",\"network\":\"eip155:8453\",\"asset\":\"0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913\"}],\"card\":{\"checkout_url\":\"https://\(host)/c/pay/\(session)\",\"session_id\":\"\(session)\"}}".utf8)
    }
}

@MainActor private final class MetalTestStore: AgentMetalStore {
    var data: Data?; var failSave = false
    func load() throws -> Data? { data }
    func save(_ value: Data) throws { if failSave { throw AgentMetalFailure.storage }; data = value }
}

@MainActor private final class MetalTestHTTP: AgentMetalTransport {
    var requests: [URLRequest] = []; var failure = false
    var response = AgentMetalTests.checkout()
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        if failure { throw URLError(.networkConnectionLost) }
        return (response, HTTPURLResponse(url: request.url!, statusCode: request.httpMethod == "POST" ? 402 : 200, httpVersion: nil, headerFields: nil)!)
    }
}
