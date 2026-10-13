import CryptoKit
import Foundation

/// One multilingual data file. Downloading never runs code or opens another app.
enum ParakeetModel {
    static let bytes: Int64 = 739_508_576
    static let checksum = "5859f77944efcd8eafa23a6350731960b2b55b2203df51f319665c807d802cc7"
    static let downloadURL = URL(string: "https://huggingface.co/handy-computer/parakeet-tdt-0.6b-v3-gguf/resolve/85ac09ea12fc4b1112fa76810059364bc6adc9de/parakeet-tdt-0.6b-v3-Q8_0.gguf")!
    static var file: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "OpenStrudel/Dictation/parakeet-v3-q8.gguf")
    }

    enum Failure: Error { case invalidModel, storage, download }

    static func verify(_ url: URL, bytes: Int64 = bytes, checksum: String = checksum) throws {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true, Int64(values.fileSize ?? -1) == bytes else { throw Failure.invalidModel }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hash = SHA256()
        while let data = try handle.read(upToCount: 1024 * 1024), !data.isEmpty {
            try Task.checkCancellation()
            hash.update(data: data)
        }
        guard hash.finalize().map({ String(format: "%02x", $0) }).joined() == checksum else { throw Failure.invalidModel }
    }

    /// Validate before replacing anything; a partial or canceled download is never installed.
    static func install(_ download: URL, at destination: URL = file, bytes: Int64 = bytes, checksum: String = checksum) throws {
        try verify(download, bytes: bytes, checksum: checksum)
        try Task.checkCancellation()
        var directory = destination.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        var attributes = URLResourceValues(); attributes.isExcludedFromBackup = true
        try directory.setResourceValues(attributes)
        let staged = directory.appending(path: ".download-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: staged) }
        try FileManager.default.copyItem(at: download, to: staged)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: staged.path)
        try Task.checkCancellation()
        // rename is atomic, including when replacing an old or damaged model.
        guard rename(staged.path, destination.path) == 0 else { throw Failure.storage }
    }
}

/// Streaming URLSession downloads keep the 740 MB model out of process memory.
private final class ParakeetDownloadProgress: NSObject, URLSessionDownloadDelegate, Sendable {
    let report: @MainActor @Sendable (Double?) -> Void
    init(_ report: @escaping @MainActor @Sendable (Double?) -> Void) { self.report = report }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        let fraction = min(1, Double(totalBytesWritten) / Double(ParakeetModel.bytes))
        Task { @MainActor in report(fraction) }
    }
}

@MainActor final class ParakeetDictationAssets: DictationAssetBackend {
    private var verifiedModification: Date?
    func installed() async throws -> Bool {
        let file = ParakeetModel.file
        guard let info = try? file.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]), Int64(info.fileSize ?? -1) == ParakeetModel.bytes else { return false }
        if let verifiedModification, verifiedModification == info.contentModificationDate { return true }
        let check = Task.detached(priority: .utility) { try ParakeetModel.verify(file) }
        do {
            try await withTaskCancellationHandler { try await check.value } onCancel: { check.cancel() }
            try Task.checkCancellation()
            verifiedModification = info.contentModificationDate
            return true
        } catch is CancellationError { throw CancellationError() }
        catch { return false }
    }
    func install(progress: @escaping @MainActor @Sendable (Double?) -> Void) async throws {
        var request = URLRequest(url: ParakeetModel.downloadURL)
        request.timeoutInterval = 60
        let (temporary, response) = try await URLSession.shared.download(for: request, delegate: ParakeetDownloadProgress(progress))
        defer { try? FileManager.default.removeItem(at: temporary) }
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw ParakeetModel.Failure.download }
        try Task.checkCancellation()
        progress(1)
        let promotion = Task.detached(priority: .utility) { try ParakeetModel.install(temporary) }
        try await withTaskCancellationHandler { try await promotion.value } onCancel: { promotion.cancel() }
        try Task.checkCancellation()
        verifiedModification = try ParakeetModel.file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }
    // The caller cancels the Task; URLSession and verification inherit it.
    func cancel() {}
}
