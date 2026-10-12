import Foundation
import Speech

@MainActor protocol DictationAssetBackend {
    func installed(locale: String) async throws -> Bool
    func install(locale: String, progress: @escaping @MainActor (Double?) -> Void) async throws
    func cancel()
}

@MainActor final class AppleDictationAssets: DictationAssetBackend {
    private var installation: AssetInstallationRequest?
    static func module(locale: String) async throws -> DictationTranscriber {
        let requested = Locale(identifier: locale)
        guard let supported = await DictationTranscriber.supportedLocale(equivalentTo: requested) else {
            throw DictationFailure.unsupported
        }
        return DictationTranscriber(locale: supported, preset: .longDictation)
    }
    func installed(locale: String) async throws -> Bool {
        let module = try await Self.module(locale: locale)
        return await AssetInventory.status(forModules: [module]) == .installed
    }
    func install(locale: String, progress: @escaping @MainActor (Double?) -> Void) async throws {
        let module = try await Self.module(locale: locale)
        try Task.checkCancellation()
        try await AssetInventory.reserve(locale: module.selectedLocales[0])
        guard let request = try await AssetInventory.assetInstallationRequest(supporting: [module]) else { return }
        installation = request
        let meter = Task {
            while !Task.isCancelled {
                let value = request.progress
                progress(value.totalUnitCount > 0 ? min(1, max(0, value.fractionCompleted)) : nil)
                do { try await Task.sleep(for: .milliseconds(150)) } catch { break }
            }
        }
        defer { meter.cancel(); installation = nil }
        try await withTaskCancellationHandler {
            try await request.downloadAndInstall()
            try Task.checkCancellation()
        } onCancel: { request.progress.cancel() }
    }
    func cancel() { installation?.progress.cancel() }
}

enum DictationFailure: LocalizedError {
    case unsupported, modelNeeded
    var errorDescription: String? {
        switch self {
        case .unsupported: L("Local dictation is not available for this language on this device.")
        case .modelNeeded: L("Download the dictation model to continue.")
        }
    }
}

/// Checking never downloads anything. The first download is an explicit action.
@MainActor final class DictationAssets: ObservableObject {
    enum State: Equatable { case checking, available, downloading, ready, failed, unsupported }
    static let shared = DictationAssets()
    @Published private(set) var state: State = .checking
    @Published private(set) var progress: Double?
    @Published private(set) var error: String?
    private(set) var locale = ""
    private var generation = UUID()
    private var work: Task<Void, Never>?
    private let backend: any DictationAssetBackend
    init(backend: any DictationAssetBackend = AppleDictationAssets()) { self.backend = backend }

    static var selectedLocale: String {
        let stored = UserDefaults.standard.string(forKey: "openstrudel.dictationLocale")
        if let stored, stored != "interface", stored != "system" { return stored }
        return L10n.shared.language.speechLocale
    }
    func check(locale: String) async {
        if self.locale == locale && state == .downloading { return }
        cancel()
        self.locale = locale; state = .checking; error = nil
        let id = generation
        do {
            let ready = try await backend.installed(locale: locale)
            guard id == generation, !Task.isCancelled else { return }
            state = ready ? .ready : .available
        } catch {
            guard id == generation, !Task.isCancelled else { return }
            fail(error)
        }
    }
    func download() {
        guard [.available, .failed].contains(state), !locale.isEmpty else { return }
        state = .downloading; progress = nil; error = nil
        let id = generation, locale = locale
        work = Task {
            do {
                try await backend.install(locale: locale) { [weak self] progress in
                    guard let self, self.generation == id else { return }
                    self.progress = progress
                }
                try Task.checkCancellation()
                guard id == generation else { return }
                guard try await backend.installed(locale: locale) else { throw DictationFailure.modelNeeded }
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
        if case DictationFailure.unsupported = error { state = .unsupported; self.error = error.localizedDescription }
        else { state = .failed; self.error = L("The model could not be downloaded. Check your connection and available storage, then try again.") }
    }
}
