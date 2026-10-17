import Foundation
import Combine
import Testing

@Suite(.serialized)
@MainActor struct CatalogueTests {
    @Test func colleagueInvitationNeverGrantsOwnerAccess() async throws {
        let fixture = CatalogueFixture()
        let (client, session, defaults, suite) = makeClient(fixture)
        defer { session.invalidateAndCancel(); defaults.removePersistentDomain(forName: suite) }
        await client.inviteMobile(owner: false)
        #expect(fixture.invitationOwners == [false])
        #expect(client.mobileInvitation != nil)
        await client.inviteMobile()
        #expect(fixture.invitationOwners == [false, true])
    }
    @Test func olderWorkerKeepsItsChatPickerUntilItsTimelineIsAvailable() async throws {
        let fixture = CatalogueFixture(); fixture.timeline = true; fixture.timelineResponse = false
        let (client, session, defaults, suite) = makeClient(fixture)
        defer { session.invalidateAndCancel(); defaults.removePersistentDomain(forName: suite) }
        await client.load(); await client.selectProfile("employee")
        #expect(!client.usesEmployeeTimeline)
        fixture.timelineResponse = true
        await client.refreshConversation()
        #expect(client.usesEmployeeTimeline)
    }
    /// The private composer must never post into a group the employee's feed only remembers.
    @Test func leavingAnOlderWorkerNeverReopensARememberedGroupUnderTheFeed() async throws {
        let fixture = CatalogueFixture(); fixture.timeline = true; fixture.telegram = CatalogueFixture.boundGroup
        let (client, session, defaults, suite) = makeClient(fixture)
        defer { session.invalidateAndCancel(); defaults.removePersistentDomain(forName: suite) }
        await client.load(); await client.selectChat("group")
        await client.selectProfile("worker")
        #expect(!client.usesEmployeeTimeline)
        await client.selectProfile("employee")
        #expect(client.usesEmployeeTimeline)
        #expect(client.selectedChatID == nil)
    }
    @Test func aFeedFoundAfterAnOfflineUpgradeLaunchClosesTheOldGroup() async throws {
        let fixture = CatalogueFixture(); fixture.timeline = true; fixture.telegram = CatalogueFixture.boundGroup
        let (_, session, defaults, suite) = makeClient(fixture)
        defer { session.invalidateAndCancel(); defaults.removePersistentDomain(forName: suite) }
        defaults.set("employee", forKey: "openstrudel.profileID"); defaults.set("group", forKey: "openstrudel.selectedChatID")
        let upgraded = HomeClient(defaults: defaults, session: session, pendingDirectory: fixture.pendingDirectory, connectionID: suite, credentialReader: { _, _ in nil })
        #expect(upgraded.selectedChatID == "group")
        await upgraded.refreshCatalogue()
        #expect(upgraded.usesEmployeeTimeline)
        #expect(upgraded.selectedChatID == nil)
    }
    @Test func groupSchedulesStayInTheEmployeeCardUnderTheFeed() async throws {
        let fixture = CatalogueFixture(); fixture.timeline = true; fixture.telegram = CatalogueFixture.boundGroup
        fixture.schedules["app-conversation"] = #"{"schedules":[],"runs":[{"id":"ok","status":"completed","error":null},{"id":"old","status":"failed","error":"Old failure"}]}"#
        fixture.schedules["group"] = #"{"schedules":[{"id":"digest","conversationId":"group","name":"Digest","prompt":"Summarise","cron":"0 9 * * *","timezone":"UTC","enabled":true,"nextRunAt":"2026-10-15T09:00:00.000Z","delivery":"bound"}],"runs":[{"id":"run","status":"failed","error":"Model unavailable"}]}"#
        let (client, session, defaults, suite) = makeClient(fixture)
        defer { session.invalidateAndCancel(); defaults.removePersistentDomain(forName: suite) }
        await client.load(); await client.selectProfile("employee"); await client.loadChatSettings()
        #expect(client.conversationID == "app-conversation")
        #expect(client.schedules.map(\.id) == ["digest"])
        #expect(client.scheduleRuns.compactMap(\.error) == ["Model unavailable"])
    }
    @Test func aTelegramReplyTheHomeRefusesIsNotSentAndNeverOffersARetry() async throws {
        let fixture = CatalogueFixture(); fixture.timeline = true
        let (client, session, defaults, suite) = makeClient(fixture)
        defer { session.invalidateAndCancel(); defaults.removePersistentDomain(forName: suite) }
        await client.load(); await client.selectProfile("employee")
        let request = try #require(client.messages.first)
        fixture.replyStatus = 400; fixture.replyError = "Подключение этой группы изменилось. Откройте её в Telegram."
        try client.sendTelegramReply(to: request, text: "Reply for the group", files: [])
        for _ in 0..<100 where client.visiblePendingMessages.first?.error == nil { try await Task.sleep(for: .milliseconds(5)) }
        let pending = try #require(client.visiblePendingMessages.first)
        #expect(pending.error == fixture.replyError)
        #expect(pending.deliveryState == "not_sent")
        await client.retry(pending)
        #expect(fixture.replyBodies.count == 1)
        client.discardPending(pending)
        #expect(client.visiblePendingMessages.isEmpty)
        #expect(try PendingMessagesFile.read(directory: fixture.pendingDirectory, home: client.baseURLString).isEmpty)
    }
    @Test func anOfflineLaunchKeepsTheFeedItsHomeServedAndNeverReopensAnOldGroup() async throws {
        let fixture = CatalogueFixture(); fixture.timeline = true
        let (client, session, defaults, suite) = makeClient(fixture)
        defer { session.invalidateAndCancel(); defaults.removePersistentDomain(forName: suite) }
        await client.load(); await client.selectProfile("employee")
        #expect(client.usesEmployeeTimeline)
        defaults.set("group", forKey: "openstrudel.selectedChatID")
        let offline = HomeClient(defaults: defaults, session: session, pendingDirectory: fixture.pendingDirectory, connectionID: suite, credentialReader: { _, _ in nil })
        #expect(offline.health == nil)
        #expect(offline.usesEmployeeTimeline)
        #expect(offline.selectedChatID == nil)
    }
    @Test func anOfflineLaunchKeepsAGroupChosenOnAnOlderHome() async throws {
        let fixture = CatalogueFixture()
        let (client, session, defaults, suite) = makeClient(fixture)
        defer { session.invalidateAndCancel(); defaults.removePersistentDomain(forName: suite) }
        await client.load()
        #expect(!client.usesEmployeeTimeline)
        defaults.set("group", forKey: "openstrudel.selectedChatID")
        let offline = HomeClient(defaults: defaults, session: session, pendingDirectory: fixture.pendingDirectory, connectionID: suite, credentialReader: { _, _ in nil })
        #expect(!offline.usesEmployeeTimeline)
        #expect(offline.selectedChatID == "group")
    }
    @Test func explicitTelegramReplyKeepsItsAudienceAndIdentityAfterLostAcknowledgement() async throws {
        let fixture = CatalogueFixture(); fixture.timeline = true
        let (client, session, defaults, suite) = makeClient(fixture)
        defer { session.invalidateAndCancel(); defaults.removePersistentDomain(forName: suite) }
        await client.load(); await client.selectProfile("employee")
        let request = try #require(client.messages.first)
        fixture.replyStatus = 503
        try client.sendTelegramReply(to: request, text: "Reply for the group", files: [])
        for _ in 0..<100 where client.visiblePendingMessages.first?.error == nil { try await Task.sleep(for: .milliseconds(5)) }
        let pending = try #require(client.visiblePendingMessages.first)
        #expect(pending.error != nil)
        #expect(pending.telegramReplyToID == request.id)
        #expect(pending.conversationID == "group")
        let saved = try PendingMessagesFile.read(directory: fixture.pendingDirectory, home: client.baseURLString)
        #expect(saved.first?.id == pending.id)
        fixture.replyStatus = 200
        await client.retry(pending)
        #expect(client.visiblePendingMessages.isEmpty)
        #expect(fixture.replyBodies.count == 2)
        #expect(fixture.replyBodies.first == fixture.replyBodies.last)
        let body = try #require(fixture.replyBodies.first)
        let payload = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(payload["replyToId"] as? String == request.id)
        #expect(payload["externalId"] as? String == pending.id.uuidString)
        #expect(!fixture.requests.contains { $0.httpMethod == "POST" && $0.url?.path == "/v1/messages" })
        #expect(client.selectedChatID == nil)
    }

    @Test func employeeTimelinePagesAcrossSourcesAndRemovesDeclinedRequests() async throws {
        let fixture = CatalogueFixture()
        fixture.timeline = true
        let (client, session, defaults, suite) = makeClient(fixture)
        defer { session.invalidateAndCancel(); defaults.removePersistentDomain(forName: suite) }
        await client.load()
        await client.selectProfile("employee")
        #expect(fixture.requests.last(where: { $0.url?.path == "/v1/agents/employee/conversation" })?.url?.query?.contains("timeline=true") == true)
        #expect(client.messages.map(\.id) == ["accepted", "reply"])
        // Work in Telegram must not turn the private composer into Stop/Steer.
        #expect(!client.isSending)
        #expect(client.activeMessage == nil)
        await client.loadEarlierMessages()
        #expect(fixture.requests.last?.url?.path == "/v1/agents/employee/conversation")
        #expect(fixture.requests.last?.url?.query?.contains("timeline=true") == true)
        #expect(client.messages.map(\.id) == ["earlier", "accepted", "reply"])
        fixture.timelineFinished = true
        await client.refreshConversation()
        #expect(client.messages.map(\.id) == ["earlier", "reply"])
        #expect(client.messages.last?.text == "Delivery confirmed")
        #expect(client.conversationID == "app-conversation")
        #expect(client.selectedChatID == nil)
    }

    @Test func sharedDeviceNameRefreshesEvenWhenTheEmployeeCatalogueIsUnchanged() async throws {
        let fixture = CatalogueFixture()
        fixture.deviceOnline = true
        let (client, session, defaults, suite) = makeClient(fixture)
        defer { session.invalidateAndCancel(); defaults.removePersistentDomain(forName: suite) }
        defaults.set("Outdated invitation", forKey: "openstrudel.connectionName")
        await client.load()
        #expect(client.displayName == "Mini")
        try await client.renameDevice("  Рабочий сервер  ")
        #expect(fixture.requests.contains { $0.url?.path == "/v1/home" && $0.httpMethod == "PATCH" })
        #expect(client.displayName == "Рабочий сервер")
        fixture.deviceName = "Имя с iPhone"
        await client.refreshCatalogue()
        #expect(client.displayName == "Имя с iPhone")
        let reopened = HomeClient(defaults: defaults, session: session, connectionID: suite)
        #expect(reopened.displayName == "Имя с iPhone")
        #expect(reopened.normalizedBaseURL == client.normalizedBaseURL)
        fixture.renameStatus = 403
        var rejected = false
        do { try await client.renameDevice("Не сохранять") } catch { rejected = true }
        #expect(rejected)
        #expect(client.displayName == "Имя с iPhone")
    }

    @Test func telegramDiscoveryRemembersTheConversationPerEmployeeAndClearsReassignedChats() async throws {
        let fixture = CatalogueFixture()
        let (client, session, defaults, suite) = makeClient(fixture)
        defer { session.invalidateAndCancel(); defaults.removePersistentDomain(forName: suite) }
        await client.load()
        #expect(client.employeeTelegramChats.isEmpty)
        fixture.telegram = #"{"configured":true,"running":true,"linkedChats":["-42"],"chats":[{"chatId":"-42","title":"Team","conversationId":"group-chat","profileId":"employee","allowedSenders":[]}] }"#
        await client.refreshCatalogue()
        #expect(client.employeeTelegramChats.isEmpty) // Root and specialist audiences remain separate.
        await client.selectProfile("employee")
        #expect(client.employeeTelegramChats.map(\.title) == ["Team"])
        let previousRequests = fixture.requests.count
        await client.selectChat("group-chat")
        #expect(fixture.requests.dropFirst(previousRequests).contains { $0.url?.path == "/v1/conversations/group-chat" })
        #expect(client.selectedChatID == "group-chat")
        await client.selectProfile(nil)
        #expect(client.selectedChatID == nil)
        await client.selectProfile("employee")
        #expect(client.selectedChatID == "group-chat")
        await client.selectChat(nil)
        await client.selectProfile(nil)
        await client.selectProfile("employee")
        #expect(client.selectedChatID == nil) // Choosing the app chat is remembered too.
        await client.selectChat("group-chat")
        fixture.telegram = fixture.telegram?.replacingOccurrences(of: #""profileId":"employee""#, with: #""profileId":null"#)
        await client.refreshCatalogue()
        #expect(client.selectedChatID == nil)
        #expect(client.employeeTelegramChats.isEmpty)
        await client.selectProfile(nil)
        #expect(client.employeeTelegramChats.map(\.title) == ["Team"])
    }

    @Test func unchangedCatalogueDoesNotPublishAndADeletionOnTheHostClearsTheSelection() async throws {
        let fixture = CatalogueFixture()
        let (client, session, defaults, suite) = makeClient(fixture)
        defer { session.invalidateAndCancel(); defaults.removePersistentDomain(forName: suite) }
        await client.load()
        await client.selectProfile("employee")
        var changes = 0
        let observation = client.objectWillChange.sink { changes += 1 }
        await client.refreshCatalogue()
        #expect(fixture.requests.last?.value(forHTTPHeaderField: "If-None-Match") == "\"v1\"")
        #expect(changes == 0)
        fixture.deleted = true
        await client.refreshCatalogue()
        #expect(client.profiles.isEmpty)
        #expect(client.selectedProfileID == nil)
        #expect(client.messages.isEmpty)
        #expect(!client.homeUnreachable)
        let reopened = HomeClient(defaults: defaults, session: session, connectionID: suite)
        #expect(reopened.profiles.isEmpty)
        observation.cancel()
    }

    @Test func catalogueDoesNotWaitForSlowProviderLoading() async throws {
        let fixture = CatalogueFixture()
        fixture.accountDelay = .milliseconds(600)
        let (client, session, defaults, suite) = makeClient(fixture)
        defer { session.invalidateAndCancel(); defaults.removePersistentDomain(forName: suite) }
        let load = Task { await client.load() }
        for _ in 0..<100 where !fixture.requests.contains(where: { $0.url?.path == "/v1/account" }) { try await Task.sleep(for: .milliseconds(5)) }
        #expect(client.isLoading)
        #expect(client.profiles.count == 1)
        fixture.deleted = true
        await client.refreshCatalogue()
        #expect(client.isLoading)
        #expect(client.profiles.isEmpty)
        await load.value
        #expect(client.profiles.isEmpty)
    }

    @Test func publicHealthDoesNotMaskARevokedCatalogueCredential() async throws {
        let fixture = CatalogueFixture()
        let (client, session, defaults, suite) = makeClient(fixture)
        defer { session.invalidateAndCancel(); defaults.removePersistentDomain(forName: suite) }
        await client.load()
        fixture.catalogueStatus = 401
        await client.load(quiet: true)
        #expect(client.homeUnreachable)
        #expect(client.connectionNeedsPairing)
        #expect(client.health == nil)
        #expect(client.profiles.count == 1)
        fixture.catalogueStatus = nil
        await client.load(quiet: true)
        #expect(!client.homeUnreachable)
        #expect(!client.connectionNeedsPairing)
    }

    @Test func staleRefreshCannotResurrectALocalDeletion() async throws {
        let fixture = CatalogueFixture()
        let (client, session, defaults, suite) = makeClient(fixture)
        defer { session.invalidateAndCancel(); defaults.removePersistentDomain(forName: suite) }
        await client.load()
        fixture.ignoreETag = true; fixture.catalogueDelay = .milliseconds(150)
        let count = fixture.requests.count
        let oldRefresh = Task { await client.refreshCatalogue() }
        for _ in 0..<100 where fixture.requests.count == count { try await Task.sleep(for: .milliseconds(2)) }
        try await client.deleteProfile("employee")
        await oldRefresh.value
        #expect(client.profiles.isEmpty)
        fixture.catalogueDelay = nil
        await client.refreshCatalogue()
        #expect(fixture.requests.last?.value(forHTTPHeaderField: "If-None-Match") == nil)
        #expect(client.profiles.isEmpty)
    }

    @Test func hidingIsClientLocalReversibleAndSurvivesRelaunch() async throws {
        let fixture = CatalogueFixture()
        let (client, session, defaults, suite) = makeClient(fixture)
        defer { session.invalidateAndCancel(); defaults.removePersistentDomain(forName: suite) }
        await client.load()
        let profile = try #require(client.profiles.first)
        let library = DeviceLibrary(defaults: defaults, clients: [client])
        let otherSuite = suite + ".other"
        let otherDefaults = try #require(UserDefaults(suiteName: otherSuite))
        defer { otherDefaults.removePersistentDomain(forName: otherSuite) }
        let other = DeviceLibrary(defaults: otherDefaults, clients: [client])
        await library.setHidden(true, profile: profile, on: client)
        #expect(library.visibleProfiles(on: client).isEmpty)
        #expect(other.visibleProfiles(on: client).count == 1)
        #expect(client.profiles.count == 1)
        let reopened = DeviceLibrary(defaults: defaults, clients: [client])
        #expect(reopened.hiddenProfiles(on: client).count == 1)
        await reopened.setHidden(false, profile: profile, on: client)
        #expect(reopened.visibleProfiles(on: client).count == 1)
        #expect(fixture.requests.allSatisfy { $0.httpMethod == "GET" })
    }

    @Test func hidingDoesNotMixIdenticalEmployeeIDsOnDifferentHosts() async throws {
        let fixture = CatalogueFixture()
        let (first, session, defaults, suite) = makeClient(fixture)
        defer { session.invalidateAndCancel(); defaults.removePersistentDomain(forName: suite) }
        await first.load()
        let otherSuite = suite + ".host"
        let otherDefaults = try #require(UserDefaults(suiteName: otherSuite))
        defer { otherDefaults.removePersistentDomain(forName: otherSuite) }
        otherDefaults.set("http://127.0.0.1:57578", forKey: "openstrudel.homeURL")
        otherDefaults.set("another-home", forKey: "openstrudel.catalogueIdentity")
        otherDefaults.set(try JSONEncoder().encode(first.profiles), forKey: "openstrudel.employeeCatalog")
        let other = HomeClient(defaults: otherDefaults, session: session, connectionID: otherSuite)
        let library = DeviceLibrary(defaults: defaults, clients: [first, other])
        let profile = try #require(first.profiles.first)
        await library.setHidden(true, profile: profile, on: first)
        #expect(library.isHidden(profile, on: first))
        #expect(!library.isHidden(profile, on: other))
        #expect(library.visibleProfiles(on: other).count == 1)
    }

    @Test func removingAnOfflineConnectionPersistsAndSelectsTheRemainingDevice() async throws {
        let fixture = CatalogueFixture()
        let (first, session, defaults, suite) = makeClient(fixture)
        defer { session.invalidateAndCancel(); defaults.removePersistentDomain(forName: suite) }
        let remoteSuite = suite + ".remote"
        let remoteDefaults = try #require(UserDefaults(suiteName: remoteSuite))
        defer { remoteDefaults.removePersistentDomain(forName: remoteSuite) }
        remoteDefaults.set("http://127.0.0.1:57577", forKey: "openstrudel.homeURL")
        let remote = HomeClient(defaults: remoteDefaults, session: session, connectionID: remoteSuite)
        let library = DeviceLibrary(defaults: defaults, clients: [first, remote])
        library.select(remote)
        await library.removeConnection(remote)
        #expect(library.clients.count == 1)
        #expect(library.active === first)
        #expect(defaults.stringArray(forKey: "openstrudel.deviceConnections") == [first.id])
        #expect(remote.isSignedOut)
        #expect(!first.isSignedOut)
        #expect(fixture.requests.isEmpty)
        await library.removeConnection(first)
        #expect(library.clients.count == 1)
        #expect(!library.active.shouldRestoreConnection)
        #expect(library.visibleClients.isEmpty)
    }

    @Test func anOlderHealthFailureCannotUndoARecoveredCatalogue() async throws {
        let fixture = CatalogueFixture()
        let (client, session, defaults, suite) = makeClient(fixture)
        defer { session.invalidateAndCancel(); defaults.removePersistentDomain(forName: suite) }
        await client.load()
        fixture.healthFailureDelay = .milliseconds(180)
        let count = fixture.requests.filter { $0.url?.path == "/health" }.count
        let stale = Task { await client.load(quiet: true) }
        for _ in 0..<100 where fixture.requests.filter({ $0.url?.path == "/health" }).count == count {
            try await Task.sleep(for: .milliseconds(2))
        }
        await client.refreshCatalogue()
        await stale.value
        #expect(!client.homeUnreachable)
        #expect(client.connectionState == .connected)
    }

    @Test func unchangedEmployeeListStillRefreshesDevicePresence() async throws {
        let fixture = CatalogueFixture()
        fixture.deviceOnline = false
        let (client, session, defaults, suite) = makeClient(fixture)
        defer { session.invalidateAndCancel(); defaults.removePersistentDomain(forName: suite) }
        await client.load()
        #expect(client.devices.first?.online == false)
        fixture.deviceOnline = true
        await client.refreshCatalogue()
        #expect(client.devices.first?.online == true)
        #expect(!client.homeUnreachable)
    }

    private func makeClient(_ fixture: CatalogueFixture) -> (HomeClient, URLSession, UserDefaults, String) {
        let suite = "OpenStrudel.catalogue-test." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defaults.set("http://127.0.0.1:57577", forKey: "openstrudel.homeURL")
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [CatalogueProtocol.self]
        CatalogueProtocol.setHandler { request in await fixture.respond(request) }
        let session = URLSession(configuration: config)
        return (HomeClient(defaults: defaults, session: session, pendingDirectory: fixture.pendingDirectory, connectionID: suite), session, defaults, suite)
    }
}

@MainActor private final class CatalogueFixture {
    let pendingDirectory = FileManager.default.temporaryDirectory.appending(path: "timeline-pending-" + UUID().uuidString)
    deinit { try? FileManager.default.removeItem(at: pendingDirectory) }
    var requests: [URLRequest] = []
    var replyStatus = 200
    var replyBodies: [Data] = []
    var invitationOwners: [Bool] = []
    var deleted = false
    var ignoreETag = false
    var accountDelay: Duration?
    var catalogueDelay: Duration?
    var catalogueStatus: Int?
    var telegram: String?
    var healthFailureDelay: Duration?
    var deviceOnline: Bool?
    var deviceName = "Mini"
    var renameStatus = 200
    var timeline = false
    var timelineResponse = true
    var timelineFinished = false
    var replyError = "Lost acknowledgement"
    /// Schedules and runs per conversation.
    var schedules: [String: String] = [:]
    static let boundGroup = #"{"configured":true,"running":true,"linkedChats":["-42"],"chats":[{"chatId":"-42","title":"Team","conversationId":"group","profileId":"employee","allowedSenders":[]}] }"#
    func respond(_ request: URLRequest) async -> (Int, Data, [String: String]) {
        requests.append(request)
        let path = request.url!.path
        if path == "/v1/mobile" { return (200, Data(#"{"connections":0}"#.utf8), [:]) }
        if path == "/v1/mobile/pairing" {
            var body = request.httpBody ?? Data()
            if body.isEmpty, let stream = request.httpBodyStream {
                stream.open(); defer { stream.close() }
                var buffer = [UInt8](repeating: 0, count: 4096)
                while stream.hasBytesAvailable {
                    let count = stream.read(&buffer, maxLength: buffer.count)
                    if count <= 0 { break }
                    body.append(buffer, count: count)
                }
            }
            let payload = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
            invitationOwners.append(payload?["owner"] as? Bool ?? true)
            return (200, Data(#"{"url":"openstrudel://connect?host=fixture.local","expiresAt":"2026-10-14T20:00:00Z"}"#.utf8), [:])
        }
        if path == "/v1/conversations/group/telegram-reply" {
            var body = request.httpBody ?? Data()
            if body.isEmpty, let stream = request.httpBodyStream {
                stream.open(); defer { stream.close() }
                var buffer = [UInt8](repeating: 0, count: 4096)
                while stream.hasBytesAvailable {
                    let count = stream.read(&buffer, maxLength: buffer.count)
                    if count <= 0 { break }
                    body.append(buffer, count: count)
                }
            }
            replyBodies.append(body)
            return (replyStatus, replyStatus == 200 ? Data(#"{"messageId":"explicit-reply"}"#.utf8) : try! JSONSerialization.data(withJSONObject: ["error": replyError]), [:])
        }
        if path.hasPrefix("/v1/conversations/"), path.hasSuffix("/schedules") {
            return (200, Data((schedules[String(path.split(separator: "/")[2])] ?? #"{"schedules":[],"runs":[]}"#).utf8), [:])
        }
        if path == "/health", timeline { return (200, Data(#"{"ok":true,"employeeTimelineVersion":1}"#.utf8), [:]) }
        if path == "/v1/agents/employee/conversation", timeline, timelineResponse {
            let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
            let earlier = query.contains { $0.name == "before" }
            let delta = query.contains { $0.name == "after" }
            let message: (String, String, String) -> [String: Any] = { id, text, status in
                ["id": id, "conversationId": "group", "channel": "telegram", "direction": "inbound", "text": text,
                 "createdAt": "2026-10-14T00:00:00.000Z", "status": status, "origin": ["channel": "telegram", "title": "Team", "canReply": true]]
            }
            let payload: [String: Any] = [
                "conversation": ["id": "app-conversation", "channel": "api", "createdAt": "2026-10-14", "updatedAt": "2026-10-14"],
                "timeline": true,
                "messages": earlier ? [message("earlier", "Archive", "completed")] : delta ? [] : [message("accepted", "Pending", "running"), message("reply", "Waiting for delivery", "completed")],
                "updates": timelineFinished ? [message("reply", "Delivery confirmed", "completed")] : [],
                "removedIds": timelineFinished ? ["accepted"] : [],
                "pagination": ["olderCursor": earlier ? NSNull() : "accepted" as Any, "newerCursor": "reply", "hasMore": false],
            ]
            return (200, try! JSONSerialization.data(withJSONObject: payload), [:])
        }
        if path == "/v1/home", request.httpMethod == "PATCH" {
            if renameStatus != 200 { return (renameStatus, Data(#"{"error":"Owner access required"}"#.utf8), [:]) }
            deviceName = "Рабочий сервер"
            return (200, Data("{\"home\":{\"id\":\"home-fixture\",\"nodeId\":\"node\",\"primaryId\":\"node\",\"role\":\"primary\",\"name\":\"\(deviceName)\",\"epoch\":1},\"devices\":[]}".utf8), [:])
        }
        if path == "/health", let healthFailureDelay {
            try? await Task.sleep(for: healthFailureDelay)
            return (503, Data(#"{"error":"temporarily unavailable"}"#.utf8), [:])
        }
        if path == "/v1/devices", let deviceOnline {
            return (200, Data("{\"devices\":[{\"id\":\"node\",\"name\":\"\(deviceName)\",\"platform\":\"darwin\",\"primary\":true,\"online\":\(deviceOnline),\"agents\":1}],\"primaryId\":\"node\"}".utf8), [:])
        }
        if request.httpMethod == "DELETE" { deleted = true; return (200, Data(#"{"ok":true}"#.utf8), [:]) }
        if path == "/v1/profiles" {
            if let catalogueStatus { return (catalogueStatus, Data(#"{"error":"revoked"}"#.utf8), [:]) }
            let etag = telegram.map { "\"telegram-\($0.hashValue)\"" } ?? (deleted ? "\"v2\"" : "\"v1\"")
            var body = deleted ? #"{"profiles":[]}"# : #"{"profiles":[{"id":"employee","name":"Тест","instructions":"","capabilities":[],"createdAt":"2026-10-09T00:00:00Z"}]}"#
            if let telegram { body = String(body.dropLast()) + ",\"telegram\":" + telegram + "}" }
            if let catalogueDelay { try? await Task.sleep(for: catalogueDelay) }
            if !ignoreETag && request.value(forHTTPHeaderField: "If-None-Match") == etag { return (304, Data(), ["ETag": etag]) }
            return (200, Data(body.utf8), ["ETag": etag])
        }
        if path == "/v1/account", let accountDelay { try? await Task.sleep(for: accountDelay) }
        let body: String
        switch path {
        case "/health": body = deviceOnline == nil ? #"{"ok":true,"homeId":"home-fixture"}"# : #"{"ok":true,"homeId":"home-fixture","homeProtocol":1,"nodeId":"node","deviceRenameVersion":1}"#
        case "/v1/account": body = #"{"account":{"connected":true,"managed":true},"canManage":true}"#
        case "/v1/integrations": body = "{\"telegram\":" + (telegram ?? #"{"configured":false,"running":false,"linkedChats":[]}"#) + "}"
        default: body = #"{"conversation":{"id":"conversation","channel":"api","createdAt":"2026-10-09","updatedAt":"2026-10-09"},"messages":[],"interactions":[]}"#
        }
        return (200, Data(body.utf8), [:])
    }
}

private final class CatalogueProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var handler: (@Sendable (URLRequest) async -> (Int, Data, [String: String]))?
    private var operation: Task<Void, Never>?
    static func setHandler(_ value: @escaping @Sendable (URLRequest) async -> (Int, Data, [String: String])) { lock.lock(); defer { lock.unlock() }; handler = value }
    private static func getHandler() -> (@Sendable (URLRequest) async -> (Int, Data, [String: String]))? { lock.lock(); defer { lock.unlock() }; return handler }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        operation = Task { @Sendable [self] in
            guard let handler = Self.getHandler(), let url = request.url else { return }
            let (status, data, headers) = await handler(request)
            guard !Task.isCancelled else { return }
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        }
    }
    override func stopLoading() { operation?.cancel() }
}
