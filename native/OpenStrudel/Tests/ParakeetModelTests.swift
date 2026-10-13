import CryptoKit
import Foundation
import Testing

@Suite("Parakeet model installation") struct ParakeetModelTests {
    @Test func damagedDownloadCannotReplaceTheInstalledModel() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let destination = root.appending(path: "installed.gguf"), download = root.appending(path: "download")
        let original = Data("original".utf8), expected = Data("new model".utf8)
        try original.write(to: destination)
        try Data("bad model".utf8).write(to: download)
        let hash = SHA256.hash(data: expected).map { String(format: "%02x", $0) }.joined()
        #expect(throws: ParakeetModel.Failure.self) {
            try ParakeetModel.install(download, at: destination, bytes: Int64(expected.count), checksum: hash)
        }
        #expect(try Data(contentsOf: destination) == original)
        try expected.write(to: download)
        try ParakeetModel.install(download, at: destination, bytes: Int64(expected.count), checksum: hash)
        #expect(try Data(contentsOf: destination) == expected)
        let names = try FileManager.default.contentsOfDirectory(atPath: root.path)
        #expect(!names.contains(where: { $0.hasPrefix(".download-") }))
        let permissions = try FileManager.default.attributesOfItem(atPath: destination.path)[.posixPermissions] as? Int
        #expect(permissions == 0o600)
    }

    @Test func truncatedModelIsNeverReady() throws {
        let file = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        try Data("truncated".utf8).write(to: file)
        #expect(throws: ParakeetModel.Failure.self) { try ParakeetModel.verify(file) }
    }
}
