import Foundation
import Testing

struct ScheduleTests {
    private func schedule(_ extra: String = "") throws -> ChatSchedule {
        try JSONDecoder().decode(ChatSchedule.self, from: Data("""
        {"id":"once","conversationId":"c","name":"Follow up","prompt":"Remind me",
         "cron":"@once 2030-01-15T09:30:00+03:00","timezone":"Europe/Moscow",
         "enabled":false,"nextRunAt":"2030-01-15T06:30:00.000Z"\(extra)}
        """.utf8))
    }

    @Test func oneTimeReminderUsesItsOwnZoneAndNeverOffersCompletedWorkAsPaused() throws {
        let value = try schedule(",\"lastRunStatus\":\"completed\"")
        #expect(value.isOneTime)
        #expect(value.oneTimeResult == L("Выполнено"))
        #expect(value.timing.contains("9:30") || value.timing.contains("09:30"))
        #expect(!value.timing.contains("6:30"))
        #expect(value.timing.hasPrefix(L("Разово · ")))
    }

    @Test func uncertainDeliveryStaysUncertainAndARealPauseHasNoCompletionClaim() throws {
        #expect(try schedule(",\"lastRunStatus\":\"uncertain\"").oneTimeResult == L("Проверьте результат"))
        #expect(try schedule().oneTimeResult == nil)
        #expect(try schedule(",\"lastRunStatus\":\"failed\"").oneTimeResult == L("Не выполнено"))
        #expect(try schedule(",\"lastRunStatus\":\"skipped\"").oneTimeResult == L("Пропущено"))
    }
}
