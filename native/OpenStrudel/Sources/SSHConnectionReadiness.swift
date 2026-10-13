#if os(macOS)
import Foundation
import Network

/// Keep the app's connection to the requested SSH endpoint alive while macOS
/// asks for local-network access. A short-lived ssh-keyscan process can exit
/// before the system presents that prompt (Apple TN3179, FB16131937).
/// This sends no credentials; OpenSSH still verifies and authenticates the host.
final class SSHConnectionReadiness: @unchecked Sendable {
    private let connection: NWConnection
    private let queue = DispatchQueue(label: "is.openstrudel.ssh-readiness")
    private let timeout: TimeInterval
    // Access only on queue, including task cancellation and the deadline.
    private var continuation: CheckedContinuation<Void, Error>?
    private var deadline: DispatchWorkItem?
    private var cancelled = false
    private var localNetworkBlocked = false

    init(target: ServerTarget, timeout: TimeInterval = 30) {
        connection = NWConnection(host: .init(target.host), port: .init(rawValue: UInt16(target.port))!, using: .tcp)
        self.timeout = timeout
    }

    func wait() async throws {
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                queue.async { [self] in
                    guard !cancelled else { continuation.resume(throwing: CancellationError()); return }
                    self.continuation = continuation
                    connection.stateUpdateHandler = { [weak self] state in self?.update(state) }
                    let deadline = DispatchWorkItem { [weak self] in
                        guard let self else { return }
                        self.finish(.failure(self.localNetworkBlocked ? ServerSetupFailure.localNetwork : .connection))
                    }
                    self.deadline = deadline
                    queue.asyncAfter(deadline: .now() + timeout, execute: deadline)
                    connection.start(queue: queue)
                }
            }
        } onCancel: {
            self.queue.async { [self] in
                cancelled = true
                finish(.failure(CancellationError()))
            }
        }
    }

    private func update(_ state: NWConnection.State) {
        switch state {
        case .ready: finish(.success(()))
        case .waiting:
            // A denial and an unanswered permission prompt can both be waiting.
            // Keep waiting until ready, Back/cancellation, or the bounded deadline.
            localNetworkBlocked = connection.currentPath?.unsatisfiedReason == .localNetworkDenied
        case .failed:
            finish(.failure(localNetworkBlocked ? ServerSetupFailure.localNetwork : .connection))
        case .cancelled: finish(.failure(CancellationError()))
        default: break
        }
    }

    private func finish(_ result: Result<Void, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        deadline?.cancel(); deadline = nil
        connection.stateUpdateHandler = nil
        connection.cancel()
        continuation.resume(with: result)
    }
}
#endif
