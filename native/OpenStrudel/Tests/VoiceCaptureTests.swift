import Foundation
import Testing

@Suite("Voice drafts")
@MainActor struct VoiceCaptureTests {
    @Test func switchingConversationsRetainsOnlyThatConversationsRecording() throws {
        let first = "voice-test-" + UUID().uuidString, second = "voice-test-" + UUID().uuidString
        let file = VoiceCapture.draftURL(context: first)
        defer { try? FileManager.default.removeItem(at: file) }
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("test-only recording".utf8).write(to: file)
        let voice = VoiceCapture()
        voice.attach(context: first) { _, _ in Issue.record("A saved recording must not send itself") }
        #expect(voice.phase == .saved)
        voice.attach(context: second) { _, _ in Issue.record("Audio cannot move to another conversation") }
        #expect(voice.phase == .idle)
        #expect(FileManager.default.fileExists(atPath: file.path))
        voice.attach(context: first) { _, _ in Issue.record("No automatic replay") }
        #expect(voice.phase == .saved)
        voice.cancel()
        #expect(voice.phase == .idle)
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["OPENSTRUDEL_VOICE_FIXTURE"] != nil))
    func recognizesAnActualRussianRecordingLocally() async throws {
        let path = try #require(ProcessInfo.processInfo.environment["OPENSTRUDEL_VOICE_FIXTURE"])
        if ProcessInfo.processInfo.environment["OPENSTRUDEL_INSTALL_VOICE_FIXTURE"] == "1" {
            let assets = ParakeetDictationAssets()
            try await assets.install() { _ in }
        }
        let text = try await ParakeetTranscriber.shared.transcribe(file: URL(fileURLWithPath: path))
        #expect(text.localizedCaseInsensitiveContains("проверка"))
        #expect(text.localizedCaseInsensitiveContains("встреча"))
        #expect(text.contains("12") || text.localizedCaseInsensitiveContains("двенадцать"))
    }
}

@Suite("Actual local dictation", .serialized, .enabled(if: ProcessInfo.processInfo.environment["OPENSTRUDEL_VOICE_LANGUAGES"] != nil))
@MainActor struct DictationLanguageIntegrationTests {
    @Test(arguments: ["en-US", "ru-RU", "fr-FR", "es-ES"])
    func recognizesRecordedSpeechWithoutChoosingItsLanguage(locale: String) async throws {
        let directory = try #require(ProcessInfo.processInfo.environment["OPENSTRUDEL_VOICE_LANGUAGES"])
        let references: [String: [String]] = [
            "en-US": ["local", "meeting", "tomorrow"],
            "ru-RU": ["проверка", "встреча", "завтра"],
            "fr-FR": ["dictée", "réunion", "demain"],
            "es-ES": ["dictado", "reunión", "mañana"],
            "he-IL": ["בדיקה", "הפגישה", "מחר"]
        ]
        let assets = ParakeetDictationAssets()
        if try await !assets.installed() { try await assets.install() { _ in } }
        let started = ContinuousClock.now
        let text = try await ParakeetTranscriber.shared.transcribe(file: URL(fileURLWithPath: directory).appending(path: locale + ".aiff"))
        print("Local dictation \(locale): \(text) [\(started.duration(to: .now))]")
        for word in references[locale] ?? [] { #expect(text.localizedCaseInsensitiveContains(word), "Missing expected word: \(word)") }
    }
}
