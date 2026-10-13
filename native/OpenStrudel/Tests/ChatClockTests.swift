import Foundation
import Testing

struct ChatClockTests {
    private func message(_ createdAt: String, imported: Bool? = nil, direction: String = "inbound") -> HomeMessage {
        HomeMessage(id: "m", conversationId: "c", channel: "api", direction: direction, replyToId: nil, text: "Привет",
                    externalId: nil, createdAt: createdAt, status: "completed", error: nil, kind: "text", imported: imported)
    }

    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    @Test func liveMessagesKeepTheirExactMoment() throws {
        let sent = message("2026-09-28T06:14:05.120Z")
        #expect(try #require(sent.sentAt).timeIntervalSince1970 == 1_790_576_045.12)
        #expect(try #require(sent.time).isEmpty == false)
    }

    @Test func dayOnlyHistoryShowsItsDayWithoutAnInventedTime() throws {
        let imported = message("2026-09-24T00:00:00.000Z", imported: true)
        #expect(imported.time == nil)
        #expect(Calendar.current.component(.day, from: try #require(imported.sentAt)) == 24)
    }

    @Test func daysReadAsPeopleSayThem() throws {
        #expect(ChatClock.day(.now) == L("Сегодня"))
        #expect(ChatClock.day(try #require(Calendar.current.date(byAdding: .day, value: -1, to: .now))) == L("Вчера"))
        let older = try Date.ISO8601FormatStyle().parse("2025-03-05T12:00:00Z")
        #expect(ChatClock.day(older).contains("2025"))
        #expect(ChatClock.day(older).contains(older.formatted(.dateTime.month(.wide).locale(L10n.locale))))
    }

    @Test func clustersReadAsTheDayAndTheTime() throws {
        #expect(ChatClock.cluster(.now, hasTime: true) == L("Сегодня") + ", " + ChatClock.time(.now))
        let imported = try #require(message("2026-09-24T00:00:00.000Z", imported: true).sentAt)
        #expect(ChatClock.cluster(imported, hasTime: false) == ChatClock.day(imported))
    }

    @Test func theExactMomentNeverInventsATime() throws {
        let live = try #require(message("2026-09-24T09:05:00Z").sentAt)
        #expect(ChatClock.exact(live, hasTime: true).contains(ChatClock.time(live)))
        let imported = try #require(message("2026-09-24T00:00:00.000Z", imported: true).sentAt)
        #expect(!ChatClock.exact(imported, hasTime: false).contains(ChatClock.time(imported)))
        #expect(ChatClock.exact(imported, hasTime: false).contains("2026"))
    }

    @Test func lazyTimeHeadingsKeepTheirConversationSnapshot() throws {
        var messages = [message("2026-10-07T12:00:00Z"), message("2026-10-07T12:01:00Z"), message("2026-10-08T12:00:00Z")]
        let rows = MessagePages.rows(messages, calendar: utc)
        // SwiftUI can render these rows after switching to a short or empty chat.
        messages = [message("2026-10-09T12:00:00Z")]
        #expect(rows[0].header == rows[0].message.sentAt)
        #expect(rows[1].header == nil)
        #expect(rows[2].header == rows[2].message.sentAt)
        messages.removeAll()
        #expect(MessagePages.rows(messages).isEmpty)
        #expect(rows[2].message.createdAt == "2026-10-08T12:00:00Z")
    }

    @Test func aPauseOfHalfAnHourOpensANewCluster() {
        let rows = MessagePages.rows([
            message("2026-10-07T12:00:00Z"),
            message("2026-10-07T12:29:59Z"), // 29:59 later
            message("2026-10-07T12:59:58Z"), // 29:59 after the previous message, not the first
            message("2026-10-07T13:29:58Z"), // exactly 30:00 later
        ], calendar: utc)
        #expect(rows.map { $0.header != nil } == [true, false, false, true])
        #expect(rows[3].header == rows[3].message.sentAt)
    }

    @Test func aNewDayOpensAClusterEvenAfterAShortPause() {
        let rows = MessagePages.rows([message("2026-10-07T23:50:00Z"), message("2026-10-08T00:05:00Z")], calendar: utc)
        #expect(rows.map { $0.header != nil } == [true, true])
    }

    @Test func prependingHistoryRecomputesTheBoundaryOfTheNewSnapshot() {
        let recent = message("2026-10-08T12:20:00Z")
        let before = MessagePages.rows([recent], calendar: utc)
        let close = MessagePages.rows([message("2026-10-08T12:00:00Z"), recent], calendar: utc)
        let distant = MessagePages.rows([message("2026-10-08T11:00:00Z"), recent], calendar: utc)
        #expect(before[0].header != nil)
        #expect(close[0].header != nil)
        #expect(close[1].header == nil)
        #expect(distant[1].header != nil)
    }

    @Test func dayOnlyHistorySharesOneHeaderPerDay() {
        let rows = MessagePages.rows([
            message("2026-09-24T00:00:00.000Z", imported: true),
            message("2026-09-24T00:00:00.000Z", imported: true),
            message("2026-09-25T00:00:00.000Z", imported: true),
        ])
        #expect(rows.map { $0.header != nil } == [true, false, true])
        #expect(rows.allSatisfy { !$0.message.hasTime })
    }

    @Test func turnsChangeWithTheSpeaker() {
        let rows = MessagePages.rows([
            message("2026-10-07T12:00:00Z"), message("2026-10-07T12:00:01Z"),
            message("2026-10-07T12:00:02Z", direction: "outbound"), message("2026-10-07T12:00:03Z", direction: "outbound"),
            message("2026-10-07T12:00:04Z"),
        ], calendar: utc)
        #expect(rows.map(\.startsTurn) == [false, false, true, false, true])
    }

    @Test func aPendingMessageOpensAClusterAfterAPause() throws {
        let last = try #require(message("2026-10-07T12:00:00Z").sentAt)
        #expect(MessagePages.opensCluster(last.addingTimeInterval(29 * 60 + 59), after: last, calendar: utc) == false)
        #expect(MessagePages.opensCluster(last.addingTimeInterval(30 * 60), after: last, calendar: utc))
        #expect(MessagePages.opensCluster(last, after: nil, calendar: utc))
    }
}
