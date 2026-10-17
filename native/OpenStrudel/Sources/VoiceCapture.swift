import SwiftUI
import AVFoundation
import CryptoKit

/// One bounded recording on the viewing device. Recognition follows the selected
/// provider; the local draft survives a failure or a conversation switch.
@MainActor final class VoiceCapture: ObservableObject {
    enum Phase { case idle, preparing, recording, transcribing, saved }
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var levels: [Double] = []
    @Published private(set) var seconds = 0
    @Published private(set) var detail = ""
    private var recorder: AVAudioRecorder?
    private var work: Task<Void, Never>?
    private var meter: Task<Void, Never>?
    private var generation = UUID()
    private var file: URL?
    private var context = ""
    private var deliver: ((String, Bool) -> Void)?
    private var recognizer: ((URL) async throws -> String)?
    private var recognitionDetail = ""
    nonisolated static let maximumDuration: TimeInterval = 300
    static let maximumLevels = 64

    func attach(context: String, deliver: @escaping (String, Bool) -> Void) {
        detach()
        self.context = context
        self.deliver = deliver
        file = Self.draftURL(context: context)
        if let file, FileManager.default.fileExists(atPath: file.path) {
            phase = .saved
            detail = L("Сохранена голосовая запись. Можно распознать ещё раз.")
        }
    }

    func start() {
        guard phase == .idle else { return }
        phase = .preparing; detail = L("Разрешите доступ к микрофону…")
        let id = generation
        work = Task {
            do {
                guard recognizer != nil || DictationAssets.shared.state == .ready else { throw DictationFailure.modelNeeded }
                guard await AVCaptureDevice.requestAccess(for: .audio) else {
                    throw VoiceFailure(L("Разрешите доступ к микрофону в настройках системы."))
                }
                try Task.checkCancellation()
                guard id == generation else { return }
                detail = L("Подготавливаем распознавание…")
                try Task.checkCancellation()
                guard id == generation, let file else { return }
                #if os(iOS)
                try AVAudioSession.sharedInstance().setCategory(.record, mode: .default)
                try AVAudioSession.sharedInstance().setActive(true)
                #endif
                try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                let recorder = try AVAudioRecorder(url: file, settings: [
                    AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44100,
                    AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 64000
                ])
                recorder.isMeteringEnabled = true
                guard recorder.record(forDuration: Self.maximumDuration) else { throw VoiceFailure(L("Не удалось начать запись. Проверьте микрофон.")) }
                self.recorder = recorder
                phase = .recording; levels = []; seconds = 0; detail = ""
                meter = Task { [weak self] in
                    while !Task.isCancelled {
                        do { try await Task.sleep(for: .milliseconds(80)) } catch { return }
                        guard let self, id == self.generation, let recorder = self.recorder else { return }
                        guard recorder.isRecording else { self.finish(send: false); return }
                        recorder.updateMeters()
                        self.seconds = Int(recorder.currentTime)
                        self.levels.append(min(1, max(0, pow(10, Double(recorder.averagePower(forChannel: 0)) / 35))))
                        if self.levels.count > Self.maximumLevels { self.levels.removeFirst(self.levels.count - Self.maximumLevels) }
                    }
                }
            } catch {
                guard id == generation, !Task.isCancelled else { return }
                stopRecorder()
                phase = .idle; detail = (error as? VoiceFailure)?.message ?? (error as? DictationFailure)?.errorDescription ?? L("Dictation could not start. Check microphone access and try again.")
            }
        }
    }

    func finish(send: Bool) {
        guard phase == .recording || phase == .saved, let file else { return }
        stopRecorder()
        phase = .transcribing; detail = recognizer == nil ? L("Распознаём на устройстве…") : recognitionDetail
        let id = generation
        let recognize = recognizer
        work = Task {
            do {
                let result: String
                if let recognize { result = try await recognize(file) }
                else { result = try await ParakeetTranscriber.shared.transcribe(file: file) }
                try Task.checkCancellation()
                guard id == generation else { return }
                guard !result.isEmpty else { throw VoiceFailure(L("Не удалось разобрать речь. Попробуйте ещё раз или запишите новое сообщение.")) }
                // Deliver before deleting the recoverable audio draft.
                deliver?(result, send)
                try? FileManager.default.removeItem(at: file)
                phase = .idle; detail = ""; levels = []
            } catch {
                guard id == generation, !Task.isCancelled else { return }
                phase = .saved
                detail = (error as? VoiceFailure)?.message ?? L("Не удалось распознать. Запись сохранена, можно повторить.")
            }
        }
    }

    func cancel() {
        generation = UUID(); work?.cancel(); meter?.cancel(); stopRecorder()
        if let file { try? FileManager.default.removeItem(at: file) }
        phase = .idle; detail = ""; levels = []
    }

    func detach() {
        generation = UUID(); work?.cancel(); meter?.cancel(); stopRecorder()
        deliver = nil; recognizer = nil; phase = .idle; detail = ""; levels = []
    }

    /// Captured for this recording, never silently changes provider mid-flight.
    func useRecognizer(_ action: ((URL) async throws -> String)?, detail: String = "") {
        guard phase == .idle || phase == .saved else { return }
        recognizer = action
        recognitionDetail = detail.isEmpty ? L("Распознаём…") : detail
    }

    private func stopRecorder() {
        meter?.cancel(); meter = nil
        recorder?.stop(); recorder = nil
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }

    static func draftURL(context: String) -> URL {
        let name = SHA256.hash(data: Data(context.utf8)).map { String(format: "%02x", $0) }.joined()
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("OpenStrudel/VoiceDrafts", isDirectory: true).appendingPathComponent(name + ".m4a")
    }

}

private struct VoiceFailure: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

/// What the composer's microphone opens until dictation is ready: one page with one filled
/// action, Download model while the model is missing and Start dictating once it is ready.
struct DictationSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var assets = DictationAssets.shared
    @EnvironmentObject private var client: HomeClient
    @State private var settings: SpeechSettings?
    @State private var editingSettings = false
    let record: () -> Void

    var body: some View {
        NavigationStack {
            page
                .toolbar {
                    // Closing never stops a download, so the way out is Done.
                    ToolbarItem(placement: .cancellationAction) { Button(L("Done")) { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { primaryAction }
                }
        }
        #if os(macOS)
        // The window's graphite tint would draw Done's label in grey, as if disabled.
        .tint(nil)
        .presentationSizing(.fitted)
        #endif
        .task { await assets.check() }
    }

    @ViewBuilder private var page: some View {
        #if os(macOS)
        content.frame(width: 480, alignment: .leading)
        #else
        ScrollView { content }
            .navigationTitle(L("Dictation"))
            .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 12) {
                #if os(macOS)
                // On the Mac a single-page sheet carries its title in its content, on the text's edge.
                Text(L("Dictation")).font(AppTypography.title)
                #endif
                Text(L("Надиктуйте сообщение, проверьте текст и отправьте."))
                    .font(AppTypography.interface).foregroundStyle(AppTheme.secondaryText)
            }
            if client.health?.speechVersion == 1 {
                SpeechSettingsView(compact: true, onEditingChange: { editingSettings = $0 }, onLoad: { settings = $0 })
            }
            if !editingSettings && settings?.provider != "elevenlabs" { DictationModelStatus() }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(24)
    }

    /// One button whose title and action follow the model.
    private var primaryAction: some View {
        let cloud = settings?.provider == "elevenlabs" && settings?.connected == true
        let needsModel = !cloud && (assets.state == .available || assets.state == .failed)
        return Button(needsModel ? L("Download model") : L("Start dictating")) {
            if needsModel { assets.download(); return }
            UserDefaults.standard.set(true, forKey: "openstrudel.dictationIntroduced")
            dismiss(); record()
        }
        .disabled(editingSettings || (client.health?.speechVersion == 1 && settings == nil) || (!cloud && !needsModel && assets.state != .ready))
        .accessibilityIdentifier(needsModel ? "downloadDictationModel" : "startLocalDictation")
    }
}

/// The model's state in the words Settings › General uses; the actions live in the sheet's bar.
private struct DictationModelStatus: View {
    @ObservedObject private var assets = DictationAssets.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch assets.state {
            case .checking:
                waiting(L("Checking the local model…"))
            case .ready:
                Label {
                    Text(L("Ready for offline dictation"))
                } icon: {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(AppTheme.accentText)
                }
                .accessibilityIdentifier("dictationReady")
            case .downloading:
                if let progress = assets.progress {
                    ProgressView(value: progress) {
                        Text(progress < 1 ? L("Downloading the model…") : L("Checking the download…"))
                    } currentValueLabel: {
                        Text(progress, format: .percent.precision(.fractionLength(0)))
                            .font(AppTypography.meta).monospacedDigit().foregroundStyle(AppTheme.secondaryText)
                    }
                } else {
                    waiting(L("Preparing the download…"))
                }
                Button(L("Cancel download")) { assets.cancel() }.accessibilityIdentifier("cancelDictationDownload")
            case .available, .failed:
                if let error = assets.error { Text(L10n.serviceText(error)).foregroundStyle(AppTheme.warning) }
                Text(L("Download Parakeet once (740 MB). After that, dictation works offline."))
            }
        }
        .font(AppTypography.interface)
        .accessibilityElement(children: .contain)
    }

    private func waiting(_ title: String) -> some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text(title).foregroundStyle(AppTheme.secondaryText)
        }
    }
}
