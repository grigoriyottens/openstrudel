import Foundation
import Testing

@Suite("Interface language") struct LocalizationTests {
    @Test func defaultsToEnglishAndPersistsAnExplicitChoice() {
        let suite = "OpenStrudel-language-test-" + UUID().uuidString
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let preference = L10n(suiteName: suite)
        #expect(preference.language == .english)
        #expect(UserDefaults(suiteName: suite)?.stringArray(forKey: "AppleLanguages") == ["en"])
        preference.language = .hebrew
        #expect(L10n(suiteName: suite).language == .hebrew)
        #expect(UserDefaults(suiteName: suite)?.stringArray(forKey: "AppleLanguages") == ["he"])
    }
    @Test func localizesServiceCopyWithoutReplacingInterpolatedNames() {
        #expect(L10n.serviceText("Удалить «Работа {1}»?", language: .english) == "Delete “Работа {1}”?")
        #expect(L10n.serviceText("Обновите OpenStrudel на устройстве сотрудника, чтобы выбирать модель.", language: .english) == "Update OpenStrudel on this assistant’s device to choose a model.")
        #expect(L10n.serviceText("Сервис не ответил.", language: .english) == "Couldn’t get a response. Try again.")
    }
    @Test func interpolationDoesNotTreatUserContentAsAnotherPlaceholder() {
        #expect(L10n.text("{0} {1}", arguments: ["{1}", "actual"], language: .english) == "{1} actual")
        #expect(L10n.text("{0}", arguments: ["MacBook"], language: .hebrew) == "\u{2068}MacBook\u{2069}")
    }
    @Test func visibleServiceNoticeFollowsALanguageChange() {
        let key = "Разрешите доступ к микрофону в настройках системы."
        let english = L10n.text(key, language: .english)
        #expect(L10n.serviceText(english, language: .hebrew) == L10n.text(key, language: .hebrew))
    }

    @Test func savedSignInFailureKeepsItsRecoveryActionInEveryLanguage() {
        let key = "Вход в OpenAI истёк. Войдите ещё раз."
        for (language, action) in [(AppLanguage.english, "Sign in again"), (.russian, "Войдите ещё раз"),
                                   (.french, "Reconnectez-vous"), (.spanish, "Vuelve a iniciar sesión"), (.hebrew, "להתחבר שוב")] {
            #expect(L10n.serviceText(key, language: language).contains(action))
        }
    }

    @Test func serviceDiscoveryFailuresKeepTheirContextAndRecovery() {
        let messages = [
            "Каталог OpenAI сейчас недоступен. Можно добавить сервис по адресу MCP.",
            "Не удалось проверить подключения OpenAI. Обновите список.",
            "Не удалось проверить часть подключений. Нажмите «Обновить», чтобы проверить ещё раз.",
        ]
        for message in messages {
            let english = L10n.serviceText(message, language: .english)
            #expect(english.localizedCaseInsensitiveContains("refresh"))
            for language in AppLanguage.allCases {
                #expect(L10n.catalog[message]?[language.rawValue] != nil)
                #expect(L10n.serviceText(message, language: language) != L10n.text("Не удалось получить ответ. Попробуйте ещё раз.", language: language))
            }
        }
    }

    @Test func approvalControlsTranslateWithoutChangingProviderText() {
        #expect(L10n.text("Разрешить действие сервиса?", language: .english) == "Allow this service action?")
        #expect(L10n.text("Только это действие", language: .english) == "This action only")
        #expect(L10n.text("Отказать", language: .english) == "Deny")
        let providerText = "Send файл.txt to Работа {1}?"
        for language in AppLanguage.allCases {
            #expect(L10n.text(providerText, language: language) == providerText)
        }
    }
}
