import Foundation
import Testing

@Suite("Readable operational errors")
struct UserFacingErrorTests {
    @Test func transportFailuresHaveAnActionableMessage() {
        for source in ["fetch failed", "The operation was aborted due to timeout"] {
            let message = UserFacingError.text(source)
            #expect(message == L("Не удалось связаться с сервисом. Проверьте подключение к интернету и попробуйте ещё раз."))
            #expect(!message.contains("fetch"))
        }
    }
    @Test func fullStorageDoesNotExposeInternalPathsOrPromiseSafeReplay() {
        for source in ["ENOSPC: no space left on device, open '/private/history.jsonl.tmp'",
                       "SQLITE_FULL: database or disk is full"] {
            let message = UserFacingError.text(source)
            #expect(message == UserFacingError.storageFull)
            #expect(!message.contains("/private"))
            #expect(message == L("На устройстве сотрудника закончилось место. Освободите место. Перед повторной отправкой проверьте, успел ли сотрудник выполнить задачу."))
            #expect(HomeClientError.server(source).localizedDescription == message)
        }
    }

    @Test func preservesSpecificRecoveryInstructions() {
        let message = "Вход в OpenAI истёк. Войдите ещё раз."
        #expect(UserFacingError.text(message) == L10n.text(message))
    }

    @Test func previousReleaseErrorsRemainUnderstandableInSavedHistory() {
        let timeout = UserFacingError.text("Codex не ответил на thread/start")
        #expect(timeout == L("Сотрудник не ответил вовремя. Перед повторной отправкой проверьте, успел ли он выполнить задачу."))
        #expect(!timeout.contains("thread/start"))
        let lost = UserFacingError.text("Связь с Codex прервалась. Результат последнего действия нужно проверить.")
        #expect(lost == L("Связь с сотрудником прервалась. Перед повторной отправкой проверьте результат последней задачи."))
        let expired = UserFacingError.text("workspace routing discovery unauthorized (401)")
        #expect(expired == L("Нужно восстановить вход в OpenAI. Откройте настройки OpenStrudel. Ваши чаты и сотрудники сохранены."))
        #expect(!expired.contains("401"))
    }
}
