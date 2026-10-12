import Foundation
import UniformTypeIdentifiers
import ImageIO
#if os(macOS)
import AppKit
#endif

/// Read outside the UI actor, with a hard limit even if the file changes while reading.
enum AttachmentImport {
    static let byteLimit = 25 * 1024 * 1024
    static let countLimit = 6

    enum Failure: LocalizedError, Equatable {
        case empty, tooLarge, tooMany, oversizedImage, notAFile, unreadableImage
        var errorDescription: String? {
            switch self {
            case .empty: L("Этот файл пуст. Выберите другой файл.")
            case .tooLarge: L("Файл больше 25 МБ. Выберите файл меньшего размера.")
            case .tooMany: L("Attach up to 6 files at a time.")
            case .oversizedImage: L("This image is too large. Choose one up to 40 megapixels.")
            case .notAFile: L("Выберите файл. Чтобы отправить папку, сначала сохраните её как ZIP-архив.")
            case .unreadableImage: L("This image couldn’t be opened. Try copying it again or choose the original file.")
            }
        }
    }

    static func isCancellation(_ error: Error) -> Bool {
        let value = error as NSError
        return error is CancellationError
            || (value.domain == NSCocoaErrorDomain && value.code == NSUserCancelledError)
            || (value.domain == NSURLErrorDomain && value.code == NSURLErrorCancelled)
    }

    #if os(macOS)
    @MainActor static func pasteboardProviders(_ pasteboard: NSPasteboard) -> [NSItemProvider] {
        (pasteboard.pasteboardItems ?? []).compactMap { item in
            if let value = item.string(forType: .fileURL), let url = URL(string: value), url.isFileURL {
                return NSItemProvider(item: url as NSURL, typeIdentifier: UTType.fileURL.identifier)
            }
            let preferred = [NSPasteboard.PasteboardType.png, .tiff]
            guard let type = (preferred.first { item.types.contains($0) }
                ?? item.types.first { UTType($0.rawValue)?.conforms(to: .image) == true }),
                  let data = item.data(forType: type) else { return nil }
            let provider = NSItemProvider()
            provider.registerDataRepresentation(forTypeIdentifier: type.rawValue, visibility: .all) { completion in
                completion(data, nil); return nil
            }
            return provider
        }
    }
    #endif

    static func files(at urls: [URL]) async throws -> [PickedFile] {
        let worker = Task.detached(priority: .userInitiated) {
            try urls.map { try read($0) }
        }
        return try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
    }

    /// File picker, drag/drop and paste share the same size and count limits.
    /// Provider temporary URLs are read inside their callback, before expiry.
    @MainActor static func providers(_ providers: [NSItemProvider]) async throws -> [PickedFile] {
        guard providers.count <= countLimit else { throw Failure.tooMany }
        var files: [PickedFile] = []
        for provider in providers {
            try Task.checkCancellation()
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                let path: String = try await withCheckedThrowingContinuation { continuation in
                    provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { value, error in
                        if let error { continuation.resume(throwing: error); return }
                        let url = (value as? URL) ?? (value as? Data).flatMap { URL(dataRepresentation: $0, relativeTo: nil) }
                        guard let url, url.isFileURL else { continuation.resume(throwing: Failure.notAFile); return }
                        continuation.resume(returning: url.path)
                    }
                }
                files += try await Self.files(at: [URL(fileURLWithPath: path)])
            } else if let type = ([UTType.png.identifier, UTType.jpeg.identifier, UTType.webP.identifier, UTType.gif.identifier]
                .first { provider.registeredTypeIdentifiers.contains($0) }
                ?? provider.registeredTypeIdentifiers.first(where: { UTType($0)?.conforms(to: .image) == true })) {
                let name = provider.suggestedName
                let file: PickedFile = try await withCheckedThrowingContinuation { continuation in
                    provider.loadFileRepresentation(forTypeIdentifier: type) { url, error in
                        if let error { continuation.resume(throwing: error); return }
                        guard let url else { continuation.resume(throwing: Failure.empty); return }
                        do {
                            let file = try read(url)
                            continuation.resume(returning: try image(file.data, name: name ?? L("Image")))
                        } catch { continuation.resume(throwing: error) }
                    }
                }
                files.append(file)
            } else { throw Failure.notAFile }
        }
        try Task.checkCancellation()
        return files
    }

    private static func read(_ url: URL) throws -> PickedFile {
        try Task.checkCancellation()
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let properties = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard properties.isRegularFile == true else { throw Failure.notAFile }
        guard (properties.fileSize ?? 0) <= byteLimit else { throw Failure.tooLarge }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var data = Data()
        while data.count <= byteLimit {
            try Task.checkCancellation()
            guard let part = try handle.read(upToCount: min(64 * 1024, byteLimit + 1 - data.count)), !part.isEmpty else { break }
            data.append(part)
        }
        guard data.count <= byteLimit else { throw Failure.tooLarge }
        guard !data.isEmpty else { throw Failure.empty }
        let mime = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        if mime.hasPrefix("image/") { return try image(data, name: url.lastPathComponent) }
        return PickedFile(name: url.lastPathComponent, mimeType: mime, data: data)
    }

    /// macOS screenshots and copied photos often arrive as TIFF or HEIC.
    /// Codex accepts PNG/JPEG/WebP/GIF as visual input; convert other formats
    /// at the import boundary so they never silently become ordinary files.
    private static func image(_ data: Data, name: String) throws -> PickedFile {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let typeID = CGImageSourceGetType(source) as String?, let type = UTType(typeID),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0 else { throw Failure.unreadableImage }
        guard Double(width) * Double(height) <= 40_000_000 else { throw Failure.oversizedImage }
        let stem = (name as NSString).deletingPathExtension
        if [UTType.png, .jpeg, .webP, .gif].contains(type) {
            return PickedFile(name: stem + "." + (type.preferredFilenameExtension ?? "png"),
                              mimeType: type.preferredMIMEType ?? "image/png", data: data)
        }
        try Task.checkCancellation()
        // Apply orientation, retaining the source resolution.
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                       kCGImageSourceCreateThumbnailWithTransform: true,
                                       kCGImageSourceThumbnailMaxPixelSize: max(width, height)]
        guard let bitmap = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { throw Failure.unreadableImage }
        let encoded = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(encoded, UTType.png.identifier as CFString, 1, nil) else { throw Failure.unreadableImage }
        CGImageDestinationAddImage(destination, bitmap, nil)
        guard CGImageDestinationFinalize(destination) else { throw Failure.unreadableImage }
        guard encoded.length <= byteLimit else { throw Failure.tooLarge }
        try Task.checkCancellation()
        return PickedFile(name: stem + ".png", mimeType: "image/png", data: encoded as Data)
    }
}
