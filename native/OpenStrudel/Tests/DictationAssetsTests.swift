import Foundation
import Testing

@Suite("Optional local dictation") @MainActor struct DictationAssetsTests {
    @MainActor final class Backend: DictationAssetBackend {
        var ready = false
        var downloads = 0
        var canceled = false
        func installed(locale: String) async throws -> Bool { ready }
        func install(locale: String, progress: @escaping @MainActor (Double?) -> Void) async throws {
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
        await assets.check(locale: "en-US")
        #expect(assets.state == .available)
        #expect(backend.downloads == 0)
    }
    @Test func reusesAnInstalledModel() async {
        let backend = Backend(); backend.ready = true
        let assets = DictationAssets(backend: backend)
        await assets.check(locale: "he-IL")
        #expect(assets.state == .ready)
        #expect(backend.downloads == 0)
    }
    @Test func cancellationCannotTurnIntoALateSuccess() async throws {
        let backend = Backend()
        let controlled = DictationAssets(backend: backend)
        await controlled.check(locale: "en-US")
        controlled.download()
        await Task.yield()
        controlled.cancel()
        try await Task.sleep(for: .milliseconds(150))
        #expect(controlled.state == .available)
        #expect(controlled.progress == nil)
        #expect(backend.canceled)
    }
}
