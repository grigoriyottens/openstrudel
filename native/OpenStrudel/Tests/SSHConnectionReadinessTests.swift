#if os(macOS)
import Foundation
import Network
import Darwin
import Testing

@Suite("SSH connection readiness")
struct SSHConnectionReadinessTests {
    @Test func connectsToTheRequestedEndpointWithoutSendingCredentials() async throws {
        let listener = try NWListener(using: .tcp, on: .any)
        defer { listener.cancel() }
        listener.newConnectionHandler = { $0.cancel() }
        try await withCheckedThrowingContinuation { (ready: CheckedContinuation<Void, Error>) in
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready: listener.stateUpdateHandler = nil; ready.resume()
                case .failed(let error): listener.stateUpdateHandler = nil; ready.resume(throwing: error)
                default: break
                }
            }
            listener.start(queue: DispatchQueue(label: "readiness-test-listener"))
        }
        let port = try #require(listener.port)
        let target = try ServerTarget(host: "127.0.0.1", user: "fixture", port: Int(port.rawValue))
        // Exercise teardown near the ready callback. None of these handshakes
        // creates an SSH session or transmits authentication data.
        for _ in 0..<8 { try await SSHConnectionReadiness(target: target, timeout: 2).wait() }
    }

    @Test func unreachableEndpointHasABoundedWait() async throws {
        let endpoint = try ClosedLoopbackEndpoint()
        defer { endpoint.close() }
        let start = ContinuousClock.now
        await #expect(throws: ServerSetupFailure.connection) {
            try await SSHConnectionReadiness(target: endpoint.target, timeout: 0.05).wait()
        }
        #expect(start.duration(to: .now) < .seconds(2))
    }

    @Test func cancellingPendingConnectionReturnsPromptly() async throws {
        let endpoint = try ClosedLoopbackEndpoint()
        defer { endpoint.close() }
        let operation = Task { try await SSHConnectionReadiness(target: endpoint.target).wait() }
        try await Task.sleep(for: .milliseconds(20))
        let start = ContinuousClock.now
        operation.cancel()
        await #expect(throws: CancellationError.self) { try await operation.value }
        #expect(start.duration(to: .now) < .seconds(1))
    }

    @Test func cancellationBeforeStartingDoesNotWaitForTheNetwork() async throws {
        let target = try ServerTarget(host: "127.0.0.1", user: "fixture", port: 22)
        let operation = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            try await SSHConnectionReadiness(target: target).wait()
        }
        await #expect(throws: CancellationError.self) { try await operation.value }
    }
}

/// Reserve a loopback port without listening. Refusal is deterministic and no
/// external network or unrelated local service is involved in failure tests.
private struct ClosedLoopbackEndpoint {
    let descriptor: Int32
    let target: ServerTarget
    init() throws {
        let descriptor = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw POSIXError(.ENFILE) }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let named = withUnsafeMutablePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.getsockname(descriptor, $0, &length) }
        }
        guard bound == 0, named == 0 else { Darwin.close(descriptor); throw POSIXError(.EADDRNOTAVAIL) }
        self.descriptor = descriptor
        target = try ServerTarget(host: "127.0.0.1", user: "fixture", port: Int(UInt16(bigEndian: address.sin_port)))
    }
    func close() { Darwin.close(descriptor) }
}
#endif
