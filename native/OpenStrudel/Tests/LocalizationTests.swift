import Foundation
import Testing

@Suite("Interface language") struct LocalizationTests {
    @Test func defaultsToEnglishAndPersistsAnExplicitChoice() {
        let suite = "OpenStrudel-language-test-" + UUID().uuidString
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let preference = L10n(suiteName: suite)
        #expect(preference.language == .english)
        #expect(UserDefaults(suiteName: suite)?.stringArray(forKey: "AppleLanguages") == ["en"])
        #expect(UserDefaults(suiteName: suite)?.object(forKey: "AppleTextDirection") as? Bool == false)
        preference.language = .hebrew
        #expect(L10n(suiteName: suite).language == .hebrew)
        #expect(UserDefaults(suiteName: suite)?.stringArray(forKey: "AppleLanguages") == ["he"])
        // AppKit mirrors the window from this flag, not from the language alone.
        #expect(UserDefaults(suiteName: suite)?.object(forKey: "AppleTextDirection") as? Bool == true)
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
    @Test func hebrewNumbersStayInTheRunOfTheirPercentSign() {
        // An isolate around the digits would leave the % outside their run, so it would render as %66.
        #expect(L10n.text("{0}% осталось", arguments: ["66"], language: .hebrew) == "נותרו 66%")
        #expect(L10n.text("{0}% осталось · сброс {1}", arguments: ["39", "Fri 11:04 PM"], language: .hebrew)
                == "נותרו 39% · מתאפס ב-\u{2068}Fri 11:04 PM\u{2069}")
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
}
