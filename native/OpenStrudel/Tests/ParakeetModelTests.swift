import CryptoKit
import Foundation
import Network
import Testing

@Suite("Parakeet model installation") struct ParakeetModelTests {
    @MainActor @Test func asyncDownloadReportsIntermediateProgress() async throws {
        let listener = try NWListener(using: .tcp, on: .any)
        defer { listener.cancel() }
        let queue = DispatchQueue(label: "dictation-download-fixture")
        listener.newConnectionHandler = { connection in
            connection.start(queue: queue)
            connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { _, _, _, _ in
                Task {
                    defer { connection.cancel() }
                    let header = Data("HTTP/1.1 200 OK\r\nContent-Length: 1048576\r\nConnection: close\r\n\r\n".utf8)
                    connection.send(content: header, completion: .idempotent)
                    for _ in 0..<16 {
                        try? await Task.sleep(for: .milliseconds(60))
                        await withCheckedContinuation { (sent: CheckedContinuation<Void, Never>) in
                            connection.send(content: Data(repeating: 42, count: 65536), completion: .contentProcessed { _ in sent.resume() })
                        }
                    }
                }
            }
        }
        try await withCheckedThrowingContinuation { (ready: CheckedContinuation<Void, Error>) in
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready: listener.stateUpdateHandler = nil; ready.resume()
                case .failed(let error): listener.stateUpdateHandler = nil; ready.resume(throwing: error)
                default: break
                }
            }
            listener.start(queue: queue)
        }
        let port = try #require(listener.port)
        var fractions: [Double] = []
        let delegate = ParakeetDownloadProgress { if let value = $0 { fractions.append(value) } }
        let request = URLRequest(url: URL(string: "http://127.0.0.1:\(port.rawValue)/model")!, timeoutInterval: 5)
        let (file, _) = try await URLSession.shared.download(for: request, delegate: delegate)
        defer { try? FileManager.default.removeItem(at: file) }
        #expect(try file.resourceValues(forKeys: [.fileSizeKey]).fileSize == 1048576)
        #expect(fractions.contains { $0 > 0 && $0 < 1 })
    }

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
