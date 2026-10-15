import Foundation
import SwiftUI
import Security

/// A small durable journal on the viewing device. Neither home's sign-in
/// credentials nor the employee archive are copied into the other home.
struct EmployeeMove: Codable, Identifiable {
    enum Phase: String, Codable {
        case preparing, staging, releasing, activating, finishing, completed, canceling, canceled
        var finished: Bool { self == .completed || self == .canceled }
        var cancellable: Bool { self == .preparing || self == .staging || self == .canceling }
    }
    let id: String
    let proof: String
    let profileID: String
    let name: String
    let sourceID: String
    let sourceHome: String
    let sourceName: String
    let targetID: String
    let targetHome: String
    let targetName: String
    var phase: Phase = .preparing
    var digest: String?
    var warnings: [String] = []
}

@MainActor final class EmployeeMoves: ObservableObject {
    typealias Transport = @MainActor (String, String, Data) async throws -> Data
    @Published private(set) var operation: EmployeeMove?
    @Published private(set) var busy = false
    @Published private(set) var error: String?
    private let defaults: UserDefaults
    private let key = "openstrudel.employeeMove"
    private var work: Task<Void, Never>?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: key) { operation = try? JSONDecoder().decode(EmployeeMove.self, from: data) }
    }

    func start(profile: EmployeeProfile, source: HomeClient, target: HomeClient, using transport: @escaping Transport) throws {
        guard operation?.phase.finished != false,
              source !== target, source.canMoveEmployees, target.canMoveEmployees,
              let sourceHome = source.health?.homeId, let targetHome = target.health?.homeId,
              sourceHome != targetHome,
              profile.deviceId == nil || profile.deviceId == source.health?.nodeId else {
            throw HomeClientError.server(L("Подключите оба устройства с доступом владельца и завершите предыдущий перенос."))
        }
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw HomeClientError.invalidResponse }
        try save(EmployeeMove(id: UUID().uuidString.lowercased(), proof: bytes.map { String(format: "%02x", $0) }.joined(),
                              profileID: profile.id, name: profile.name,
                              sourceID: source.id, sourceHome: sourceHome, sourceName: source.displayName,
                              targetID: target.id, targetHome: targetHome, targetName: target.displayName))
        resume(using: transport)
    }

    func resume(using transport: @escaping Transport) {
        guard work == nil, operation?.phase.finished == false else { return }
        error = nil; busy = true
        work = Task {
            defer { busy = false; work = nil }
            do { try await advance(using: transport) }
            catch is CancellationError { /* The journal, source and staged copy remain recoverable. */ }
            // Service text is translated once, where it is shown, so a device name stays intact.
            catch HomeClientError.server(let message) { self.error = message }
            catch { self.error = UserFacingError.text(error.localizedDescription) }
        }
    }

    func cancel(using transport: @escaping Transport) {
        guard var value = operation, value.phase.cancellable else { return }
        do { value.phase = .canceling; try save(value) }
        catch { self.error = error.localizedDescription; return }
        let running = work
        running?.cancel()
        Task { await running?.value; resume(using: transport) }
    }

    func waitUntilPaused() async { await work?.value }

    func dismissFinished() {
        guard operation?.phase.finished == true, !busy else { return }
        defaults.removeObject(forKey: key); operation = nil; error = nil
    }

    private func save(_ value: EmployeeMove) throws {
        defaults.set(try JSONEncoder().encode(value), forKey: key)
        // Flush before an irreversible release. The next launch must know
        // whether cancellation is still safe, even if the reply was lost.
        guard defaults.synchronize() else { throw HomeClientError.server(L("Не удалось сохранить этап переноса. Освободите место и повторите.")) }
        operation = value
    }

    private func advance(using transport: Transport) async throws {
        while var value = operation, !value.phase.finished {
            try Task.checkCancellation()
            switch value.phase {
            case .preparing, .staging:
                let prepared = try await call("prepare", onSource: true, value: value, extra: ["agent": value.profileID, "agentId": value.profileID], using: transport)
                guard let digest = prepared["digest"] as? String, prepared["ready"] as? Bool == true,
                      digest.count == 64, value.digest == nil || value.digest == digest,
                      let bundle = prepared["bundle"] as? [String: Any] else { throw HomeClientError.invalidResponse }
                value.digest = digest; value.phase = .staging
                try Task.checkCancellation(); try save(value)
                let staged = try await call("stage", onSource: false, value: value, extra: ["digest": digest, "bundle": bundle], using: transport)
                guard staged["ready"] as? Bool == true, staged["digest"] as? String == digest else { throw HomeClientError.invalidResponse }
                value.phase = .releasing
            case .releasing:
                let reply = try await call("release", onSource: true, value: value, using: transport)
                guard reply["released"] as? Bool == true, reply["digest"] as? String == value.digest else { throw HomeClientError.invalidResponse }
                value.phase = .activating
            case .activating:
                guard let digest = value.digest else { throw HomeClientError.invalidResponse }
                let reply = try await call("activate", onSource: false, value: value, extra: ["digest": digest], using: transport)
                guard reply["active"] as? Bool == true else { throw HomeClientError.invalidResponse }
                value.warnings = reply["warnings"] as? [String] ?? []
                value.phase = .finishing
            case .finishing:
                _ = try await call("finish", onSource: true, value: value, using: transport)
                _ = try await call("finish", onSource: false, value: value, using: transport)
                value.phase = .completed
            case .canceling:
                // Install the cancellation barrier at the destination before
                // unfreezing the source. A late stage request cannot activate it.
                _ = try await call("cancel", onSource: false, value: value, using: transport)
                _ = try await call("cancel", onSource: true, value: value, using: transport)
                value.phase = .canceled
            case .completed, .canceled: return
            }
            try Task.checkCancellation(); try save(value)
        }
    }

    private func call(_ action: String, onSource: Bool, value: EmployeeMove, extra: [String: Any] = [:], using transport: Transport) async throws -> [String: Any] {
        var body = extra
        body["id"] = value.id; body["proof"] = value.proof
        body["homeId"] = onSource ? value.sourceHome : value.targetHome
        let data = try JSONSerialization.data(withJSONObject: body)
        let device = onSource ? value.sourceName : value.targetName
        let response: Data
        do { response = try await transport(onSource ? value.sourceID : value.targetID, action, data) }
        catch let failure as URLError where failure.code == .timedOut {
            throw HomeClientError.server(L10n.text("«{0}» не ответил за 5 минут. Перенос можно продолжить: «Продолжить перенос».", arguments: [device], language: .russian))
        } catch let failure as URLError where [.networkConnectionLost, .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed, .notConnectedToInternet].contains(failure.code) {
            throw HomeClientError.server(L10n.text("Нет связи с «{0}». Когда связь появится, нажмите «Продолжить перенос».", arguments: [device], language: .russian))
        }
        try Task.checkCancellation()
        guard let result = try JSONSerialization.jsonObject(with: response) as? [String: Any] else { throw HomeClientError.invalidResponse }
        return result
    }
}

extension HomeClient {
    /// Owning the device, not its ChatGPT account, decides who moves its employees.
    var ownsDevice: Bool { canManageOpenAI || canManageConnections }
    var canMoveEmployees: Bool { employeeMoveBlocker == nil }
    /// Why this device cannot take part in a move right now.
    var employeeMoveBlocker: String? {
        if connectionNeedsPairing { return L("Подключите «\(displayName)» снова. Переписка сохранена на устройстве.") }
        if health == nil || homeUnreachable { return L("«\(displayName)» пока не на связи. Подключимся автоматически.") }
        if !ownsDevice { return L("Подключение к «\(displayName)» без доступа владельца. Переносить сотрудников может только владелец.") }
        if health?.employeeTransferVersion != 1 { return L("Обновите OpenStrudel на «\(displayName)», чтобы переносить сотрудников.") }
        return nil
    }
}
