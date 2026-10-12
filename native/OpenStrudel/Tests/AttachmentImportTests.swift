import Foundation
import Testing
import UniformTypeIdentifiers
import ImageIO
import CoreGraphics
import AppKit

@Suite("Attachment import")
struct AttachmentImportTests {
    @Test func preservesContentAndFileMetadata() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("Заметки.txt")
        let data = Data("Проверка вложения".utf8)
        try data.write(to: file)
        let files = try await AttachmentImport.files(at: [file])
        #expect(files.count == 1)
        #expect(files[0].name == "Заметки.txt")
        #expect(files[0].mimeType == "text/plain")
        #expect(files[0].data == data)
    }

    @Test func rejectsEmptyFilesAndDirectories() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("empty.txt")
        try Data().write(to: file)
        await #expect(throws: AttachmentImport.Failure.empty) { try await AttachmentImport.files(at: [file]) }
        await #expect(throws: AttachmentImport.Failure.notAFile) { try await AttachmentImport.files(at: [folder]) }
    }

    @Test func acceptsExactLimitAndRejectsOneByteMore() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("limit.dat")
        FileManager.default.createFile(atPath: file.path, contents: nil)
        let handle = try FileHandle(forWritingTo: file)
        defer { try? handle.close() }
        try handle.truncate(atOffset: UInt64(AttachmentImport.byteLimit))
        let files = try await AttachmentImport.files(at: [file])
        #expect(files[0].data.count == AttachmentImport.byteLimit)
        try handle.truncate(atOffset: UInt64(AttachmentImport.byteLimit + 1))
        await #expect(throws: AttachmentImport.Failure.tooLarge) { try await AttachmentImport.files(at: [file]) }
    }

    @Test func cancellationIsNotAFileError() {
        #expect(AttachmentImport.isCancellation(CancellationError()))
        #expect(AttachmentImport.isCancellation(CocoaError(.userCancelled)))
        #expect(AttachmentImport.isCancellation(URLError(.cancelled)))
        #expect(!AttachmentImport.isCancellation(CocoaError(.fileReadNoPermission)))
        #expect(!AttachmentImport.isCancellation(AttachmentImport.Failure.tooLarge))
    }

    @Test @MainActor func droppedFileAndPastedImagePreserveTheirBytes() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("Drop.txt")
        let bytes = Data("Dropped file".utf8)
        try bytes.write(to: file)
        let provider = NSItemProvider(item: file as NSURL, typeIdentifier: UTType.fileURL.identifier)
        let dropped = try await AttachmentImport.providers([provider])
        #expect(dropped.first?.data == bytes)
        #expect(dropped.first?.name == "Drop.txt")
        let image = NSItemProvider()
        let png = try imageData(type: .png)
        image.registerDataRepresentation(forTypeIdentifier: UTType.png.identifier, visibility: .all) { completion in
            completion(png, nil); return nil
        }
        let pasted = try await AttachmentImport.providers([image])
        #expect(pasted.first?.mimeType == "image/png")
        #expect(pasted.first?.data == png)
    }

    @Test @MainActor func clipboardTIFFBecomesReadablePNGWithoutDuplicateRepresentations() async throws {
        let provider = NSItemProvider()
        let tiff = try imageData(type: .tiff)
        provider.registerDataRepresentation(forTypeIdentifier: UTType.tiff.identifier, visibility: .all) { completion in
            completion(tiff, nil); return nil
        }
        let pasted = try await AttachmentImport.providers([provider])
        #expect(pasted.count == 1)
        let file = try #require(pasted.first)
        #expect(file.mimeType == "image/png")
        #expect(file.name.hasSuffix(".png"))
        let source = try #require(CGImageSourceCreateWithData(file.data as CFData, nil))
        #expect(CGImageSourceGetType(source) as String? == UTType.png.identifier)
        let decoded = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(decoded.width == 12 && decoded.height == 8)
    }

    @Test @MainActor func pasteboardKeepsTextNativeAndImportsOneImagePerItem() async throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        board.setString("Ordinary copied text", forType: .string)
        #expect(AttachmentImport.pasteboardProviders(board).isEmpty)
        board.clearContents()
        let item = NSPasteboardItem()
        item.setData(try imageData(type: .tiff), forType: .tiff)
        item.setData(try imageData(type: .png), forType: .png)
        board.writeObjects([item])
        let providers = AttachmentImport.pasteboardProviders(board)
        #expect(providers.count == 1)
        let imported = try await AttachmentImport.providers(providers)
        #expect(imported.count == 1 && imported[0].mimeType == "image/png")
    }

    @Test @MainActor func imageOnlyClipboardEnablesPasteAndReachesAttachments() throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        board.setData(try imageData(type: .png), forType: .png)
        let editor = ComposerEditor()
        editor.isRichText = false
        editor.pasteboard = board
        var attachments = 0
        editor.onPaste = { attachments += $0.count }
        let paste = NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        #expect(editor.validateMenuItem(paste))
        editor.paste(nil)
        #expect(attachments == 1)
        #expect(editor.string.isEmpty)
    }

    private func imageData(type: UTType) throws -> Data {
        let context = try #require(CGContext(data: nil, width: 12, height: 8, bitsPerComponent: 8, bytesPerRow: 48,
                                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 1, green: 0.2, blue: 0.1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 12, height: 8))
        let result = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(result, type.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try #require(context.makeImage()), nil)
        #expect(CGImageDestinationFinalize(destination))
        return result as Data
    }

    private func temporaryFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("OpenStrudel-attachments-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }
}
