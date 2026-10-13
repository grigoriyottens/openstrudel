import AVFoundation
import CTranscribe
import Foundation

/// Adapted from OpenRamble's transcribe.cpp adapter (MIT). All model/session
/// access and result copying happens on one queue, outside the main actor.
final class ParakeetTranscriber: @unchecked Sendable {
    static let shared = ParakeetTranscriber()
    private let queue = DispatchQueue(label: "is.openstrudel.dictation", qos: .userInitiated)
    private let modelURL: URL
    private var model: OpaquePointer?
    private var session: OpaquePointer?
    private var idleRelease: DispatchWorkItem?
    init(modelURL: URL = ParakeetModel.file) { self.modelURL = modelURL }

    enum Failure: Error { case model, audio, recognition }

    func transcribe(file: URL) async throws -> String {
        let cancellation = Cancellation()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                queue.async { [self] in
                    do {
                        try cancellation.check()
                        idleRelease?.cancel()
                        defer { scheduleRelease() }
                        let samples = try Self.samples(file: file, cancellation: cancellation)
                        try load()
                        try cancellation.check()
                        guard let session else { throw Failure.model }
                        transcribe_set_abort_callback(session, { value in
                            guard let value else { return false }
                            return Unmanaged<Cancellation>.fromOpaque(value).takeUnretainedValue().isCanceled
                        }, Unmanaged.passUnretained(cancellation).toOpaque())
                        defer {
                            transcribe_set_abort_callback(session, nil, nil)
                            withExtendedLifetime(cancellation) {}
                        }
                        var params = transcribe_run_params()
                        transcribe_run_params_init(&params)
                        params.task = TRANSCRIBE_TASK_TRANSCRIBE
                        params.timestamps = TRANSCRIBE_TIMESTAMPS_NONE
                        // No language hint: Parakeet recognizes its 25 languages automatically.
                        let status = transcribe_run(session, samples, Int32(samples.count), &params)
                        try cancellation.check()
                        guard status == TRANSCRIBE_OK else { throw Failure.recognition }
                        let text = String(cString: transcribe_full_text(session)).trimmingCharacters(in: .whitespacesAndNewlines)
                        continuation.resume(returning: text)
                    } catch { continuation.resume(throwing: error) }
                }
            }
        } onCancel: { cancellation.cancel() }
    }

    private func load() throws {
        guard model == nil else { return }
        _ = Self.silenceLogs
        var options = transcribe_model_load_params()
        transcribe_model_load_params_init(&options)
        #if arch(arm64) && !targetEnvironment(simulator)
        options.backend = TRANSCRIBE_BACKEND_METAL
        #else
        options.backend = TRANSCRIBE_BACKEND_CPU
        #endif
        var loaded: OpaquePointer?
        let status = modelURL.path.withCString { transcribe_model_load_file($0, &options, &loaded) }
        guard status == TRANSCRIBE_OK, let loaded else { throw Failure.model }
        var settings = transcribe_session_params()
        transcribe_session_params_init(&settings)
        #if arch(arm64) && !targetEnvironment(simulator)
        settings.n_threads = 1
        #else
        settings.n_threads = 4
        #endif
        var opened: OpaquePointer?
        guard transcribe_session_init(loaded, &settings, &opened) == TRANSCRIBE_OK, let opened else {
            transcribe_model_free(loaded)
            throw Failure.model
        }
        model = loaded; session = opened
    }

    private func scheduleRelease() {
        let release = DispatchWorkItem { [weak self] in self?.unload() }
        idleRelease = release
        queue.asyncAfter(deadline: .now() + 60, execute: release)
    }
    private func unload() {
        if let session { transcribe_session_free(session) }; session = nil
        if let model { transcribe_model_free(model) }; model = nil
    }
    deinit {
        idleRelease?.cancel()
        // A running queue block retains self, so neither pointer can be in use here.
        if let session { transcribe_session_free(session) }
        if let model { transcribe_model_free(model) }
    }

    private static let silenceLogs: Void = { transcribe_log_set({ _, _, _ in }, nil) }()

    private final class Cancellation: @unchecked Sendable {
        private let lock = NSLock()
        private var canceled = false
        var isCanceled: Bool { lock.withLock { canceled } }
        func cancel() { lock.withLock { canceled = true } }
        func check() throws { if isCanceled { throw CancellationError() } }
    }

    /// Preserve resampler state, downmix every channel and drain its last samples.
    private static func samples(file url: URL, cancellation: Cancellation) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let source = file.processingFormat
        guard source.sampleRate > 0, file.length > 0,
              Double(file.length) / source.sampleRate <= VoiceCapture.maximumDuration + 1,
              let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: source, to: target),
              let input = AVAudioPCMBuffer(pcmFormat: source, frameCapacity: 16_384),
              let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: 16_384) else { throw Failure.audio }
        converter.downmix = true
        var samples: [Float] = []
        var readError: Error?
        while true {
            try cancellation.check()
            var error: NSError?
            let status = converter.convert(to: output, error: &error) { requested, state in
                guard file.framePosition < file.length else { state.pointee = .endOfStream; return nil }
                do {
                    let count = min(AVAudioFrameCount(requested), input.frameCapacity, AVAudioFrameCount(min(file.length - file.framePosition, Int64(UInt32.max))))
                    try file.read(into: input, frameCount: count)
                    state.pointee = input.frameLength == 0 ? .endOfStream : .haveData
                    return input
                } catch { readError = error; state.pointee = .endOfStream; return nil }
            }
            if let readError { throw readError }
            guard error == nil, status != .error, let channel = output.floatChannelData?[0] else { throw Failure.audio }
            samples.append(contentsOf: UnsafeBufferPointer(start: channel, count: Int(output.frameLength)))
            if status == .endOfStream { break }
        }
        // Parakeet's mel front-end needs at least 1.25 seconds, even for a short word.
        if samples.count < 20_000 { samples.append(contentsOf: repeatElement(0, count: 20_000 - samples.count)) }
        return samples
    }
}
