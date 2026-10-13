import Foundation
import Testing

@Suite("Optional local dictation") @MainActor struct DictationAssetsTests {
    @MainActor final class Backend: DictationAssetBackend {
        var ready = false
        var downloads = 0
        var canceled = false
        func installed() async throws -> Bool { ready }
        func install(progress: @escaping @MainActor @Sendable (Double?) -> Void) async throws {
            downloads += 1
            progress(0.25)
            try await Task.sleep(for: .milliseconds(100))
            ready = true
        }
        func cancel() { canceled = true }
    }
    @Test func checkingDoesNotDownloadOrAskForMicrophoneAccess() async {
        let backend = Backend()
        let assets = DictationAssets(backend: backend)
        await assets.check()
        #expect(assets.state == .available)
        #expect(backend.downloads == 0)
    }
    @Test func reusesAnInstalledModel() async {
        let backend = Backend(); backend.ready = true
        let assets = DictationAssets(backend: backend)
        await assets.check()
        #expect(assets.state == .ready)
        #expect(backend.downloads == 0)
    }
    @Test func cancellationCannotTurnIntoALateSuccess() async throws {
        let backend = Backend()
        let controlled = DictationAssets(backend: backend)
        await controlled.check()
        controlled.download()
        await Task.yield()
        controlled.cancel()
        try await Task.sleep(for: .milliseconds(150))
        #expect(controlled.state == .available)
        #expect(controlled.progress == nil)
        #expect(backend.canceled)
    }

    @Test func changingInterfaceLanguageKeepsTheSameDownloadedModel() async {
        let original = L10n.shared.language
        defer { L10n.shared.language = original }
        let backend = Backend(); backend.ready = true
        let assets = DictationAssets(backend: backend)
        for language in AppLanguage.allCases {
            L10n.shared.language = language
            await assets.check()
            #expect(assets.state == .ready)
        }
        #expect(backend.downloads == 0)
    }
}
