import Foundation
import Darwin
import Testing

@Suite("Voice drafts")
@MainActor struct VoiceCaptureTests {
    @Test func selectedRecognizerDeliversAnEditablePreviewAndRetainsFailedAudio() async throws {
        let context = "speech-preview-" + UUID().uuidString
        let file = VoiceCapture.draftURL(context: context)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("test recording".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let voice = VoiceCapture()
        var delivered: String?, sent = false
        voice.attach(context: context) { text, send in delivered = text; sent = send }
        voice.useRecognizer { _ in throw URLError(.notConnectedToInternet) }
        voice.finish(send: false)
        for _ in 0..<100 where voice.phase == .transcribing { try await Task.sleep(for: .milliseconds(5)) }
        #expect(voice.phase == .saved)
        #expect(delivered == nil)
        #expect(FileManager.default.fileExists(atPath: file.path))
        voice.useRecognizer { url in #expect(url == file); return "Встреча завтра в 12" }
        voice.finish(send: false)
        for _ in 0..<100 where voice.phase == .transcribing { try await Task.sleep(for: .milliseconds(5)) }
        #expect(delivered == "Встреча завтра в 12")
        #expect(!sent)
        #expect(voice.phase == .idle)
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    @Test func switchingChatsDuringCloudRecognitionNeverDeliversIntoTheNewChat() async throws {
        let context = "speech-switch-" + UUID().uuidString, file = VoiceCapture.draftURL(context: context)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("test recording".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let voice = VoiceCapture()
        var resume: CheckedContinuation<String, Never>?
        voice.attach(context: context) { _, _ in Issue.record("A detached recording must not be delivered") }
        voice.useRecognizer { _ in await withCheckedContinuation { resume = $0 } }
        voice.finish(send: true)
        for _ in 0..<100 where resume == nil { try await Task.sleep(for: .milliseconds(5)) }
        let continuation = try #require(resume)
        voice.attach(context: context + "-new") { _, _ in Issue.record("The old recording must not cross audiences") }
        continuation.resume(returning: "Old transcript")
        try await Task.sleep(for: .milliseconds(20))
        #expect(voice.phase == .idle)
        #expect(FileManager.default.fileExists(atPath: file.path))
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["OPENSTRUDEL_VOICE_LONG_FIXTURE"] != nil), .timeLimit(.minutes(3)))
    func recognizesFiveMinutesWithoutDroppingTheEnd() async throws {
        let path = try #require(ProcessInfo.processInfo.environment["OPENSTRUDEL_VOICE_LONG_FIXTURE"])
        let started = ContinuousClock.now
        let transcriber = ParakeetTranscriber()
        let text = try await transcriber.transcribe(file: URL(fileURLWithPath: path))
        let meetings = text.lowercased().components(separatedBy: "meeting").count - 1
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        print("Long local dictation: \(text.count) characters, \(meetings) meetings, \(started.duration(to: .now)), peak resident \(usage.ru_maxrss / 1_048_576) MiB")
        // The real English fixture is repeated throughout all five minutes.
        #expect(meetings >= 25, "Long recordings must not silently truncate")
    }

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
