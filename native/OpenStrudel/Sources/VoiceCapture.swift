import SwiftUI
import AVFoundation
import CryptoKit

/// One bounded recording on the viewing device. Audio stays local; a draft is
/// retained if recognition fails or the user switches conversations.
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
                guard DictationAssets.shared.state == .ready else { throw DictationFailure.modelNeeded }
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
        phase = .transcribing; detail = L("Распознаём на устройстве…")
        let id = generation
        work = Task {
            do {
                let result = try await ParakeetTranscriber.shared.transcribe(file: file)
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
        deliver = nil; phase = .idle; detail = ""; levels = []
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

struct VoiceRecordingRow: View {
    @ObservedObject var voice: VoiceCapture
    @Environment(\.dynamicTypeSize) private var textSize
    let canSend: Bool
    var body: some View {
        let layout = textSize.isAccessibilitySize && voice.phase != .recording
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(spacing: 12))
        layout {
            Button { voice.cancel() } label: { Image(systemName: "xmark").font(.system(size: 18)).frame(width: 44, height: 44).contentShape(Rectangle()) }
                .buttonStyle(.plain).accessibilityLabel(L("Отменить запись"))
            if voice.phase == .recording {
                Canvas { context, size in
                    let count = min(VoiceCapture.maximumLevels, max(1, Int(size.width / 6)))
                    let samples = Array(voice.levels.suffix(count))
                    for index in 0..<count {
                        let sampleIndex = index - (count - samples.count)
                        let level = sampleIndex < 0 ? 0 : samples[sampleIndex]
                        let height = max(3, level * size.height)
                        let rect = CGRect(x: CGFloat(index) * size.width / CGFloat(count), y: (size.height - height) / 2, width: 3, height: height)
                        context.fill(Path(roundedRect: rect, cornerRadius: 2), with: .foreground)
                    }
                }.frame(height: 28).accessibilityHidden(true)
                Text(String(format: "%d:%02d", voice.seconds / 60, voice.seconds % 60)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                Button { voice.finish(send: false) } label: { Image(systemName: "stop.fill").font(.system(size: 18)).frame(width: 44, height: 44).contentShape(Rectangle()) }
                    .buttonStyle(.plain).accessibilityLabel(L("Остановить и проверить текст"))
                Button { voice.finish(send: true) } label: { Image(systemName: "arrow.up").font(.system(size: 18)).frame(width: 44, height: 44).contentShape(Rectangle()) }
                    .buttonStyle(.glassProminent).buttonBorderShape(.circle).disabled(!canSend).accessibilityLabel(L("Распознать и отправить"))
            } else {
                if voice.phase == .preparing || voice.phase == .transcribing { ProgressView().controlSize(.small) }
                Text(L10n.serviceText(voice.detail)).font(.callout).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                if voice.phase == .saved {
                    Button { voice.finish(send: false) } label: { AdaptiveActionLabel(title: L("Распознать")) }
                        .adaptiveActionStyle(.glass)
                }
            }
        }.padding(.horizontal, 8).padding(.vertical, 6)
        .accessibilityElement(children: .contain).accessibilityLabel(voice.phase == .recording ? L("Идёт запись") : L("Голосовой ввод"))
    }
}

struct DictationSettings: View {
    var showsTitle = true
    @ObservedObject private var assets = DictationAssets.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if showsTitle { Text(L("Dictation")).font(.headline) }
            Text(L("Speak naturally. Your language is recognized automatically, on this device."))
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Text(L("25 languages, including English, Russian, French and Spanish. Hebrew is not supported."))
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            DictationModelStatus()
        }
        .task { await assets.check() }
    }
}

private struct DictationModelStatus: View {
    @ObservedObject private var assets = DictationAssets.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch assets.state {
            case .checking:
                ProgressView(L("Checking the local model…"))
            case .ready:
                Label(L("Ready for offline dictation"), systemImage: "checkmark.circle")
                    .foregroundStyle(.secondary).accessibilityIdentifier("dictationReady")
            case .downloading:
                if let progress = assets.progress {
                    ProgressView(value: progress) {
                        Text(progress < 1 ? L("Downloading the model…") : L("Checking the download…"))
                    } currentValueLabel: { Text(progress, format: .percent.precision(.fractionLength(0))).monospacedDigit() }
                } else { ProgressView(L("Preparing the download…")) }
                Button(L("Cancel download")) { assets.cancel() }.accessibilityIdentifier("cancelDictationDownload")
            case .available, .failed:
                if let error = assets.error { Text(L10n.serviceText(error)).foregroundStyle(AppTheme.warning) }
                Text(L("Download Parakeet once (740 MB). After that, dictation works offline."))
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Button(L("Download · 740 MB")) { assets.download() }
                    .buttonStyle(.borderedProminent).accessibilityIdentifier("downloadDictationModel")

            }
        }.accessibilityElement(children: .contain)
    }
}

struct DictationSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var assets = DictationAssets.shared
    let record: () -> Void
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Image(systemName: "waveform").font(.system(size: 36, weight: .light)).foregroundStyle(AppTheme.accent).accessibilityHidden(true)
                    DictationSettings(showsTitle: false)
                    if assets.state == .ready {
                        Button(L("Start dictating")) {
                            UserDefaults.standard.set(true, forKey: "openstrudel.dictationIntroduced")
                            dismiss(); record()
                        }.buttonStyle(.glassProminent).accessibilityIdentifier("startLocalDictation")
                    }
                }.padding(24)
            }
            .navigationTitle(L("Dictation"))
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(L("Done")) { dismiss() } } }
        }
        #if os(macOS)
        .frame(width: 480, height: 340)
        #endif
    }
}
