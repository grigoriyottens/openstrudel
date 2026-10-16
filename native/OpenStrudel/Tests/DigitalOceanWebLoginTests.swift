import AuthenticationServices
import Foundation
import Testing

@Suite(.serialized)
@MainActor struct BrowserSignInTests {
    @Test func externalBrowserWaitsForTheValidatedAppCallback() async throws {
        var opened: [URL] = []
        let browser = BrowserSignIn(openExternal: { opened.append($0); return true }) { _, _ in
            Issue.record("External browser sign-in started a second browser session")
            return ControlledWebSession(url: URL(string: "https://unused.example")!, completion: { _, _ in })
        }
        let destination = URL(string: "https://service.example/authorize")!
        let expected = URL(string: "openstrudel://oauth/service/test?state=test&code=test")!
        let result = Task { try await browser.open(destination) }
        while opened.isEmpty { await Task.yield() }
        #expect(opened == [destination])
        browser.complete(expected)
        #expect(try await result.value == expected)
    }

    @Test func externalBrowserFailureAndCancellationAllowAnotherSignIn() async throws {
        var accepted = false
        var count = 0
        let browser = BrowserSignIn(openExternal: { _ in count += 1; return accepted })
        let destination = URL(string: "https://service.example/authorize")!
        do { _ = try await browser.open(destination); Issue.record("Failed browser opening succeeded") }
        catch { #expect(!(error is CancellationError)) }
        accepted = true
        let canceled = Task { try await browser.open(destination) }
        while count < 2 { await Task.yield() }
        canceled.cancel()
        do { _ = try await canceled.value; Issue.record("Canceled sign-in succeeded") }
        catch { #expect(error is CancellationError) }
        let retry = Task { try await browser.open(destination) }
        while count < 3 { await Task.yield() }
        let expected = URL(string: "openstrudel://oauth/service/retry?state=test&code=test")!
        browser.complete(expected)
        #expect(try await retry.value == expected)
    }

    @Test func externalBrowserCannotLaunchAFileOrAnotherApplication() async {
        var opened = false
        let browser = BrowserSignIn(openExternal: { _ in opened = true; return true })
        for address in ["file:///tmp/example", "other-app://action", "https://user:password@example.com/"] {
            do { _ = try await browser.open(URL(string: address)!); Issue.record("Unsafe browser URL accepted") }
            catch { }
        }
        #expect(!opened)
    }

    @Test func acceptsCompletionFromBackgroundQueue() async throws {
        var sessions: [ControlledWebSession] = []
        let login = BrowserSignIn(openExternal: nil) { url, completion in
            let session = ControlledWebSession(url: url, completion: completion)
            sessions.append(session)
            return session
        }
        let destination = URL(string: "https://cloud.digitalocean.com/")!
        let callback = URL(string: "openstrudel://oauth/digitalocean?code=test&state=test")!
        let result = Task { try await login.open(destination) }
        while sessions.isEmpty { await Task.yield() }
        let completion = sessions[0].reply
        await Task.detached { completion(callback, nil) }.value
        #expect(try await result.value == callback)
    }

    @Test func canceledSessionCannotCompleteTheNextSignIn() async throws {
        var sessions: [ControlledWebSession] = []
        let login = BrowserSignIn(openExternal: nil) { url, completion in
            let session = ControlledWebSession(url: url, completion: completion)
            sessions.append(session)
            return session
        }
        let destination = URL(string: "https://cloud.digitalocean.com/")!
        let first = Task { try await login.open(destination) }
        while sessions.isEmpty { await Task.yield() }
        // Starting a second sign-in cancels and resumes the previous caller.
        let second = Task { try await login.open(destination) }
        while sessions.count < 2 { await Task.yield() }
        do { _ = try await first.value; Issue.record("Canceled login returned a URL") }
        catch { #expect(error is CancellationError) }
        #expect(sessions[0].canceled)
        let oldCompletion = sessions[0].reply
        let staleURL = URL(string: "openstrudel://oauth/digitalocean?code=stale")!
        await Task.detached { oldCompletion(staleURL, nil) }.value
        for _ in 0..<10 { await Task.yield() }
        let newCompletion = sessions[1].reply
        let expected = URL(string: "openstrudel://oauth/digitalocean?code=current")!
        await Task.detached { newCompletion(expected, nil) }.value
        #expect(try await second.value == expected)
    }

    @Test func externalBrowserCompletionWinsOverSessionCancellation() async throws {
        var sessions: [ControlledWebSession] = []
        let login = BrowserSignIn(openExternal: nil) { url, completion in
            let session = ControlledWebSession(url: url, completion: completion)
            sessions.append(session)
            return session
        }
        let destination = URL(string: "https://cloud.digitalocean.com/")!
        let expected = URL(string: "openstrudel://oauth/digitalocean?code=external&state=test")!
        let result = Task { try await login.open(destination) }
        while sessions.isEmpty { await Task.yield() }
        login.complete(expected)
        #expect(try await result.value == expected)
        #expect(sessions[0].canceled)
        let completion = sessions[0].reply
        await Task.detached {
            completion(nil, ASWebAuthenticationSessionError(.canceledLogin))
        }.value

        let next = Task { try await login.open(destination) }
        while sessions.count < 2 { await Task.yield() }
        login.cancel()
        do { _ = try await next.value; Issue.record("Canceled login returned a URL") }
        catch { #expect(error is CancellationError) }
    }

    @Test func anUnansweredBrowserSessionExpiresAndAllowsRetry() async throws {
        var sessions: [ControlledWebSession] = []
        let login = BrowserSignIn(timeout: .milliseconds(30), openExternal: nil) { url, completion in
            let session = ControlledWebSession(url: url, completion: completion)
            sessions.append(session)
            return session
        }
        let url = URL(string: "https://service.example/login")!
        do { _ = try await login.open(url); Issue.record("An unanswered session completed") }
        catch { #expect(!(error is CancellationError)) }
        #expect(sessions[0].canceled)
        let retried = Task { try await login.open(url) }
        while sessions.count < 2 { await Task.yield() }
        let callback = URL(string: "openstrudel://oauth/service/retry")!
        login.complete(callback)
        #expect(try await retried.value == callback)
    }

    @Test func cancelingServiceSignInReleasesTheHomeBeforeRetry() async throws {
        var sessions: [ControlledWebSession] = []
        let browser = BrowserSignIn(openExternal: nil) { url, completion in
            let session = ControlledWebSession(url: url, completion: completion)
            sessions.append(session); return session
        }
        let suite = "OpenStrudel.service-oauth." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.set("http://127.0.0.1:57574", forKey: "openstrudel.homeURL")
        defer { defaults.removePersistentDomain(forName: suite) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ServiceSignInURLProtocol.self]
        let transport = URLSession(configuration: configuration)
        defer { transport.invalidateAndCancel() }
        let id = String(repeating: "a", count: 48)
        var requests: [String] = []
        ServiceSignInURLProtocol.respond = { request in
            await MainActor.run {
                requests.append((request.httpMethod ?? "GET") + " " + request.url!.path)
                let value: [String: Any] = request.url!.path.hasSuffix("/connect")
                    ? ["url": "https://service.example/authorize", "signInId": id] : ["ok": true]
                return try! JSONSerialization.data(withJSONObject: value)
            }
        }
        let client = HomeClient(defaults: defaults, session: transport,
                                credentialReader: { _, _ in nil }, credentialWriter: { _, _ in }, serviceBrowser: browser)
        let first = Task { try await client.connectService("mcp:qa", for: "chat") }
        while sessions.isEmpty { await Task.yield() }
        first.cancel()
        do { _ = try await first.value; Issue.record("Canceled sign-in succeeded") }
        catch { #expect(error is CancellationError) }
        #expect(requests == ["POST /v1/connections/connect", "DELETE /v1/connections/oauth/" + id])
        let retry = Task { try await client.connectService("mcp:qa", for: "chat") }
        while sessions.count < 2 { await Task.yield() }
        #expect(!client.acceptServiceCallback(URL(string: "openstrudel://oauth/service/" + String(repeating: "b", count: 48))!))
        #expect(client.acceptServiceCallback(URL(string: "openstrudel://oauth/service/" + id + "?state=test&code=test")!))
        #expect(try await retry.value == nil)
        #expect(requests.last == "POST /v1/connections/oauth/" + id)
    }

    @Test func serviceCallbackStaysWithTheDeviceThatStartedIt() {
        let id = String(repeating: "a", count: 48)
        let base = "openstrudel://oauth/service/" + id
        #expect(ServiceOAuthCallback.accepts(URL(string: base + "/notion?state=test&code=test")!, signInID: id))
        for address in [base + "other?code=test", base + "#fragment", base.replacingOccurrences(of: "oauth/", with: "other/"),
                        base.replacingOccurrences(of: "oauth/", with: "oauth:443/"), "https://example.com/service/" + id,
                        "openstrudel://oauth/service/" + String(repeating: "b", count: 48)] {
            #expect(!ServiceOAuthCallback.accepts(URL(string: address)!, signInID: id))
        }
    }
}

private final class ControlledWebSession: ASWebAuthenticationSession {
    let reply: BrowserSignIn.Completion
    var canceled = false
    init(url: URL, completion: @escaping BrowserSignIn.Completion) {
        reply = completion
        super.init(url: url, callbackURLScheme: "openstrudel", completionHandler: completion)
    }
    override func start() -> Bool { true }
    override func cancel() { canceled = true }
}

private final class ServiceSignInURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var respond: (@Sendable (URLRequest) async -> Data)?
    private var operation: Task<Void, Never>?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        operation = Task { @Sendable [self] in
            guard let respond = Self.respond else { return }
            let data = await respond(request)
            guard !Task.isCancelled else { return }
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        }
    }
    override func stopLoading() { operation?.cancel() }
}
