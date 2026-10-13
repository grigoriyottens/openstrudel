import Foundation

@MainActor protocol DictationAssetBackend {
    func installed() async throws -> Bool
    func install(progress: @escaping @MainActor @Sendable (Double?) -> Void) async throws
    func cancel()
}

enum DictationFailure: LocalizedError {
    case modelNeeded
    var errorDescription: String? {
        switch self {
        case .modelNeeded: L("Download the dictation model to continue.")
        }
    }
}

/// Checking never downloads anything. The first download is an explicit action.
@MainActor final class DictationAssets: ObservableObject {
    enum State: Equatable { case checking, available, downloading, ready, failed }
    static let shared = DictationAssets()
    @Published private(set) var state: State = .checking
    @Published private(set) var progress: Double?
    @Published private(set) var error: String?
    private var generation = UUID()
    private var work: Task<Void, Never>?
    private let backend: any DictationAssetBackend
    init(backend: any DictationAssetBackend = ParakeetDictationAssets()) { self.backend = backend }

    func check() async {
        if state == .downloading { return }
        cancel()
        state = .checking; error = nil
        let id = generation
        do {
            let ready = try await backend.installed()
            guard id == generation, !Task.isCancelled else { return }
            state = ready ? .ready : .available
        } catch {
            guard id == generation, !Task.isCancelled else { return }
            fail(error)
        }
    }
    func download() {
        guard [.available, .failed].contains(state) else { return }
        state = .downloading; progress = nil; error = nil
        let id = generation
        work = Task {
            do {
                try await backend.install() { [weak self] progress in
                    guard let self, self.generation == id, self.state == .downloading,
                          let progress, progress.isFinite else { return }
                    self.progress = max(self.progress ?? 0, min(1, max(0, progress)))
                }
                try Task.checkCancellation()
                guard id == generation else { return }
                guard try await backend.installed() else { throw DictationFailure.modelNeeded }
                guard id == generation, !Task.isCancelled else { return }
                state = .ready; progress = nil
            } catch {
                guard id == generation, !Task.isCancelled else { return }
                fail(error)
            }
        }
    }
    func cancel() {
        generation = UUID(); work?.cancel(); work = nil; backend.cancel(); progress = nil
        if state == .downloading { state = .available }
    }
    private func fail(_ error: Error) {
        state = .failed; self.error = L("The model could not be downloaded. Check your connection and available storage, then try again.")
    }
}
