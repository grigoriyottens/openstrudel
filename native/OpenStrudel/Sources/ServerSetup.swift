#if os(macOS)
import Foundation
import Combine
import CryptoKit
import Security
import Darwin

enum ServerSetupFailure: Error, LocalizedError, Equatable {
    case address, credentials, privateKey, hostKey, connection, localNetwork, authentication, unsupportedSystem, resources, administrator
    case existingInstallation, portBusy, storage, installer, installation, identity, waiting, runtime, serviceUnreachable, sharedServer, notStarted
    var errorDescription: String? {
        switch self {
        case .address: L("Enter a server address, sign-in name and a port between 1 and 65535.")
        case .credentials: L("Enter the password or add a private SSH key. Add its passphrase if it has one.")
        case .privateKey: L("Add the complete private key, including its BEGIN and END lines. Public keys cannot be used to sign in.")
        case .hostKey: L("The server's identity could not be verified. Check the address and its fingerprint with your provider.")
        case .connection: L("The server did not respond. Check its address, SSH port and internet connection, then try again.")
        case .localNetwork: L("Allow OpenStrudel to access the local network in System Settings → Privacy & Security → Local Network, then try again.")
        case .authentication: L("Sign-in was refused. Check the sign-in name, password or SSH key.")
        case .unsupportedSystem: L("Automatic setup supports Ubuntu 24.04 LTS or newer on a 64-bit Intel or ARM server.")
        case .resources: L("Free at least 8 GB on this server, then try again. Installation needs space for OpenStrudel and its build files.")
        case .administrator: L("Use root or an account with password-free administrator access to install OpenStrudel.")
        case .existingInstallation: L("OpenStrudel is already installed. Connect to it using a link from its device settings; its data will stay unchanged.")
        case .portBusy: L("Port 7789 is already in use. Choose another server or free that port before setup.")
        case .storage: L("OpenStrudel cannot access Keychain. Unlock this Mac, then try again and allow access if macOS asks.")
        case .installer: L("The verified installer could not be loaded. Check your connection and update OpenStrudel, then try again.")
        case .installation: L("Installation has stopped. Your progress is saved. Check the server, then retry the same installation.")
        case .identity: L("The server does not match this installation. No connection was added.")
        case .waiting: L("The server is still being prepared. You can close this window and check again later.")
        case .runtime: L("This server has an older or unavailable Docker installation. Update it to Docker 29 with Compose, or use a new Ubuntu server.")
        case .serviceUnreachable: L("OpenStrudel is installed, but this Mac cannot reach it. Allow incoming TCP connections on port 7789 in your server's firewall, then try again.")
        case .sharedServer: L("This server already hosts other apps. Use a new Ubuntu server so their settings and data stay unchanged.")
        case .notStarted: L("Установка на сервере не началась. Нажмите «Продолжить», чтобы запустить её; уже сохранённая настройка не потеряется.")
        }
    }
}

struct ServerInstallationStatus: Decodable {
    let installationID: String?
    let state: String
    let stage: String
    var canUpdateRelease: Bool? = nil
    var problemWhenUnreachable: ServerSetupFailure? {
        if state == "failed" { return .installation }
        if state == "complete" || stage == "ready" { return .serviceUnreachable }
        return nil
    }
}

struct ServerTarget: Codable, Equatable, Sendable {
    let host: String
    let user: String
    let port: Int
    init(host: String, user: String, port: Int) throws {
        let host = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let user = user.trimmingCharacters(in: .whitespacesAndNewlines)
        let numeric = host.allSatisfy { $0.isNumber || $0 == "." }
        let validIP = host.split(separator: ".", omittingEmptySubsequences: false).count == 4
            && host.split(separator: ".", omittingEmptySubsequences: false).allSatisfy { UInt8($0).map { String($0) } == String($0) }
        guard (1...65535).contains(port), !host.isEmpty, host.count <= 253,
              host.split(separator: ".", omittingEmptySubsequences: false).allSatisfy({ $0.range(of: "^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$", options: .regularExpression) != nil }),
              !numeric || validIP,
              user.range(of: "^[a-zA-Z_][a-zA-Z0-9_-]{0,31}$", options: .regularExpression) != nil
        else { throw ServerSetupFailure.address }
        self.host = host; self.user = user; self.port = port
    }
    var knownHostsName: String { port == 22 ? host : "[\(host)]:\(port)" }
}

struct SSHHostKey: Codable, Equatable, Sendable {
    let type: String
    let encoded: String
    let knownHosts: String
    let fingerprint: String
    init(line: String, target: ServerTarget) throws {
        let columns = line.split(whereSeparator: \.isWhitespace)
        guard columns.count == 3, ["ssh-ed25519", "ecdsa-sha2-nistp256", "ssh-rsa"].contains(String(columns[1])),
              let data = Data(base64Encoded: String(columns[2])), (32...16384).contains(data.count)
        else { throw ServerSetupFailure.hostKey }
        type = String(columns[1]); encoded = String(columns[2])
        knownHosts = "\(target.knownHostsName) \(type) \(encoded)\n"
        fingerprint = "SHA256:" + Data(SHA256.hash(data: data)).base64EncodedString().replacingOccurrences(of: "=", with: "")
    }
}

struct ServerAccess: Sendable {
    var password = ""
    var privateKey: Data?
    var passphrase = ""
    var secret: String { privateKey == nil ? password : passphrase }
    func validate() throws {
        guard secret.utf8.count < 2048, !secret.contains("\n"), !secret.contains("\r"), !secret.contains("\0"),
              privateKey.map({ !$0.isEmpty && $0.count <= 131072 }) ?? !password.isEmpty else { throw ServerSetupFailure.credentials }
        if let privateKey { _ = try SSHPrivateKey.normalized(privateKey) }
    }
}

enum SSHPrivateKey {
    /// Both clipboard and file imports use the same bounded PEM envelope.
    /// OpenSSH verifies the actual key and passphrase when connecting.
    static func normalized(_ data: Data) throws -> Data {
        guard data.count <= 131072, let raw = String(data: data, encoding: .utf8), !raw.contains("\0") else { throw ServerSetupFailure.privateKey }
        let text = raw.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\u{feff}")))
        let lines = text.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        let labels = ["OPENSSH PRIVATE KEY", "RSA PRIVATE KEY", "EC PRIVATE KEY", "DSA PRIVATE KEY", "PRIVATE KEY", "ENCRYPTED PRIVATE KEY"]
        guard lines.count >= 3, let label = labels.first(where: { lines.first == "-----BEGIN \($0)-----" }),
              lines.last == "-----END \(label)-----" else { throw ServerSetupFailure.privateKey }
        var payload: [String] = []
        for line in lines.dropFirst().dropLast() where !line.isEmpty {
            if payload.isEmpty && (line == "Proc-Type: 4,ENCRYPTED" || line.hasPrefix("DEK-Info: ")) { continue }
            guard line.range(of: "^[A-Za-z0-9+/=]+$", options: .regularExpression) != nil else { throw ServerSetupFailure.privateKey }
            payload.append(line)
        }
        guard let bytes = Data(base64Encoded: payload.joined()), bytes.count >= 32 else { throw ServerSetupFailure.privateKey }
        return Data((lines.joined(separator: "\n") + "\n").utf8)
    }
}

struct ServerPreflight: Codable, Equatable, Sendable {
    var os: String
    var version: String
    var architecture: String
    var memoryMiB: Int
    var diskGiB: Int
    var freeGiB: Int
    var administrator: Bool
    var python: Bool
    var installationID: String?
    var existing: Bool
    var portBusy: Bool
    var runtimeCompatible: Bool? = nil
    var sharedRuntime: Bool? = nil
    // Memory depends on the assistants' work. Recommend headroom, without
    // rejecting smaller machines or relying on a VM provider's advertised RAM.
    var recommendsMoreMemory: Bool { memoryMiB > 0 && memoryMiB < 3584 }
    var installationProblem: ServerSetupFailure? {
        if existing { return .existingInstallation }
        if sharedRuntime == true { return .sharedServer }
        // Ubuntu LTS releases use an even year and April version. Keep the
        // minimum version in step with the bundled cloud installer.
        let year = Int(version.prefix(2)) ?? 0
        let supportedUbuntu = version.range(of: "^[0-9]{2}\\.04$", options: .regularExpression) != nil && year >= 24 && year.isMultiple(of: 2)
        if os != "ubuntu" || !supportedUbuntu || !["x86_64", "aarch64"].contains(architecture) || !python { return .unsupportedSystem }
        if !administrator { return .administrator }
        // The installer builds a ~2.8 GB image and temporary build layers. Free
        // space matters; an arbitrary total disk size does not.
        if freeGiB < 8 { return .resources }
        if portBusy { return .portBusy }
        if runtimeCompatible == false { return .runtime }
        return nil
    }
}

struct ServerInstallation: Codable, Sendable {
    let id: String
    let target: ServerTarget
    let hostKey: SSHHostKey
    var releaseHash: String
    var previousReleaseHash: String?
    let privateKeyPEM: String
    let ownerToken: String
    var attempted = false
    init(target: ServerTarget, hostKey: SSHHostKey, releaseHash: String) throws {
        guard releaseHash.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil else { throw ServerSetupFailure.installer }
        id = UUID().uuidString.lowercased(); self.target = target; self.hostKey = hostKey; self.releaseHash = releaseHash
        privateKeyPEM = P256.Signing.PrivateKey().pemRepresentation
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw ServerSetupFailure.storage }
        ownerToken = bytes.map { String(format: "%02x", $0) }.joined()
    }
}

enum ServerSetupScripts {
    private final class Marker: NSObject {}
    static func resource(_ name: String) throws -> Data {
        guard let url = Bundle.main.url(forResource: name, withExtension: "sh")
                ?? Bundle(for: Marker.self).url(forResource: name, withExtension: "sh"),
              let data = try? Data(contentsOf: url), data.count < 60000 else { throw ServerSetupFailure.installer }
        return data
    }
    static func command(_ name: String) throws -> Data {
        guard ["check_server", "server_status"].contains(name) else { throw ServerSetupFailure.installer }
        return try resource("server-setup") + Data("\n\(name)\n".utf8)
    }
    static func install(_ saved: ServerInstallation, installer: Data, script: String) throws -> String {
        var values: [String: Any] = [
            "installationId": saved.id, "privateKeyPEM": saved.privateKeyPEM,
            "host": saved.target.host,
            "ownerTokenHash": SHA256.hash(data: Data(saved.ownerToken.utf8)).map { String(format: "%02x", $0) }.joined(),
            "releaseHash": saved.releaseHash, "installer": installer.base64EncodedString()
        ]
        if let previous = saved.previousReleaseHash { values["previousReleaseHash"] = previous }
        let payload = try JSONSerialization.data(withJSONObject: values, options: [.sortedKeys])
        // A JSON string cannot terminate the fixed heredoc. Secrets travel only
        // over the pinned SSH channel's stdin, never in command arguments.
        return script + "\ninstall_server <<'OPENSTRUDEL_SETUP_INPUT'\n" + String(decoding: payload, as: UTF8.self) + "\nOPENSTRUDEL_SETUP_INPUT\n"
    }
}

/// Passwords and key passphrases remain in memory: askpass reads one line from
/// a private FIFO. A selected key has a short-lived 0600 OpenSSH input file.
final class SSHPrivateSession {
    let directory: URL
    let environment: [String: String]
    let keyFile: String?
    private var descriptor: Int32 = -1
    private var closed = false
    init(access: ServerAccess) throws {
        try access.validate()
        directory = FileManager.default.temporaryDirectory.appending(path: "openstrudel-ssh-" + UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        let fifo = directory.appending(path: "answer")
        let helper = directory.appending(path: "askpass")
        keyFile = access.privateKey == nil ? nil : directory.appending(path: "identity").path
        environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "LC_ALL": "C", "SSH_ASKPASS_REQUIRE": "force", "SSH_ASKPASS": helper.path, "OPENSTRUDEL_ASKPASS_PIPE": fifo.path]
        do {
            guard mkfifo(fifo.path, 0o600) == 0 else { throw ServerSetupFailure.storage }
            descriptor = Darwin.open(fifo.path, O_RDWR | O_NONBLOCK | O_CLOEXEC)
            guard descriptor >= 0 else { throw ServerSetupFailure.storage }
            let bytes = Data((access.secret + "\n").utf8)
            guard bytes.withUnsafeBytes({ Darwin.write(descriptor, $0.baseAddress, bytes.count) }) == bytes.count else { throw ServerSetupFailure.storage }
            try Data("#!/bin/sh\nIFS= read -r -t 10 answer < \"$OPENSTRUDEL_ASKPASS_PIPE\" || exit 1\nprintf '%s\\n' \"$answer\"\n".utf8).write(to: helper)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: helper.path)
            if let key = access.privateKey, let keyFile {
                guard FileManager.default.createFile(atPath: keyFile, contents: try SSHPrivateKey.normalized(key), attributes: [.posixPermissions: 0o600]) else { throw ServerSetupFailure.storage }
            }
        } catch { close(); throw error }
    }
    func close() {
        guard !closed else { return }; closed = true
        if descriptor >= 0 { Darwin.close(descriptor); descriptor = -1 }
        try? FileManager.default.removeItem(at: directory)
    }
    deinit { close() }
}

private final class SSHProcess: @unchecked Sendable {
    struct Output: Sendable { let status: Int32; let data: Data }
    private let process = Process()
    private let lock = NSLock()
    private var canceled = false
    func cancel() {
        lock.lock(); canceled = true
        if process.isRunning { process.terminate() }
        lock.unlock()
    }
    func run(_ executable: String, arguments: [String], input: Data = Data(), environment: [String: String] = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "LC_ALL": "C"], timeout: TimeInterval = 30) async throws -> Output {
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async { [self] in
                    let output = Pipe(), stdin = Pipe()
                    process.executableURL = URL(fileURLWithPath: executable); process.arguments = arguments; process.environment = environment
                    process.standardOutput = output; process.standardError = output; process.standardInput = stdin
                    do {
                        lock.lock()
                        if canceled { lock.unlock(); throw CancellationError() }
                        do { try process.run() } catch { lock.unlock(); throw error }
                        lock.unlock()
                        let timer = DispatchWorkItem { [weak self] in self?.cancel() }
                        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timer)
                        defer { timer.cancel() }
                        DispatchQueue.global().async {
                            try? stdin.fileHandleForWriting.write(contentsOf: input)
                            try? stdin.fileHandleForWriting.close()
                        }
                        var data = Data()
                        while let part = try? output.fileHandleForReading.read(upToCount: 16384), !part.isEmpty {
                            if data.count + part.count > 262144 { cancel(); break }
                            data.append(part)
                        }
                        process.waitUntilExit()
                        lock.lock(); let stopped = canceled; lock.unlock()
                        if stopped { throw ServerSetupFailure.connection }
                        continuation.resume(returning: Output(status: process.terminationStatus, data: data))
                    } catch { continuation.resume(throwing: error) }
                }
            }
        } onCancel: { self.cancel() }
    }
}

protocol ServerSSHTransport: Sendable {
    func scan(_ target: ServerTarget) async throws -> SSHHostKey
    func run(target: ServerTarget, key: SSHHostKey, access: ServerAccess, input: Data, elevated: Bool) async throws -> Data
}

struct SSHServerTransport: ServerSSHTransport {
    static func arguments(target: ServerTarget, knownHosts: String, keyFile: String?, access: ServerAccess, command: String) -> [String] {
        var args = ["-T", "-F", "/dev/null", "-p", String(target.port), "-l", target.user,
            "-o", "StrictHostKeyChecking=yes", "-o", "UserKnownHostsFile=\(knownHosts)", "-o", "GlobalKnownHostsFile=/dev/null",
            "-o", "IdentityAgent=none", "-o", "IdentitiesOnly=yes", "-o", "ForwardAgent=no", "-o", "ClearAllForwardings=yes",
            "-o", "PermitLocalCommand=no", "-o", "ConnectTimeout=12", "-o", "ConnectionAttempts=1", "-o", "ServerAliveInterval=10",
            "-o", "ServerAliveCountMax=2", "-o", "NumberOfPasswordPrompts=1", "-o", "KbdInteractiveAuthentication=no",
            "-o", "LogLevel=ERROR", "-o", "PreferredAuthentications=\(keyFile == nil ? "password" : "publickey")"]
        if let keyFile { args += ["-i", keyFile] }
        args += ["--", target.host, command]
        return args
    }
    func scan(_ target: ServerTarget) async throws -> SSHHostKey {
        try await SSHConnectionReadiness(target: target).wait()
        let result = try await SSHProcess().run("/usr/bin/ssh-keyscan", arguments: ["-T", "10", "-p", String(target.port), "-t", "ed25519,ecdsa,rsa", target.host], timeout: 15)
        let keys = String(decoding: result.data, as: UTF8.self).split(whereSeparator: \.isNewline).compactMap { try? SSHHostKey(line: String($0), target: target) }
        guard let key = keys.first(where: { $0.type == "ssh-ed25519" }) ?? keys.first else { throw ServerSetupFailure.connection }
        return key
    }
    func run(target: ServerTarget, key: SSHHostKey, access: ServerAccess, input: Data, elevated: Bool = false) async throws -> Data {
        let privateSession = try SSHPrivateSession(access: access)
        defer { privateSession.close() }
        let hosts = privateSession.directory.appending(path: "known_hosts")
        try Data(key.knownHosts.utf8).write(to: hosts)
        let command = elevated && target.user != "root" ? "sudo -n /bin/bash -s" : "/bin/bash -s"
        let result = try await SSHProcess().run("/usr/bin/ssh", arguments: Self.arguments(target: target, knownHosts: hosts.path, keyFile: privateSession.keyFile, access: access, command: command), input: input, environment: privateSession.environment, timeout: 45)
        guard result.status == 0 else {
            let error = String(decoding: result.data, as: UTF8.self)
            if error.contains("HOST IDENTIFICATION") || error.contains("Host key verification") { throw ServerSetupFailure.hostKey }
            if error.contains("Permission denied") || error.contains("Load key") { throw ServerSetupFailure.authentication }
            if error.contains("sudo:") { throw ServerSetupFailure.administrator }
            if error.contains("OPENSTRUDEL_EXISTING") { throw ServerSetupFailure.existingInstallation }
            if error.contains("OPENSTRUDEL_SHARED") { throw ServerSetupFailure.sharedServer }
            throw ServerSetupFailure.connection
        }
        return result.data
    }
}

@MainActor protocol ServerSetupStore {
    func load() throws -> ServerInstallation?
    func unlock() async throws -> ServerInstallation?
    func save(_ installation: ServerInstallation?) throws
}

extension ServerSetupStore {
    func unlock() async throws -> ServerInstallation? { try load() }
}

@MainActor struct ServerSetupKeychain: ServerSetupStore {
    nonisolated private var query: [String: Any] { [kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: (Bundle.main.bundleIdentifier ?? "is.openstrudel.mac") + ".server-setup", kSecAttrAccount as String: "pending"] }
    func load() throws -> ServerInstallation? {
        // A locked or newly signed application's legacy Keychain item must not
        // block SwiftUI waiting for an authentication dialog at initialization.
        try KeychainInteraction.run { try read() }
    }
    func unlock() async throws -> ServerInstallation? {
        // Explicit recovery may request macOS authorization. Keep its wait off
        // the main thread so Back and the rest of the app remain responsive.
        try await Task.detached(priority: .userInitiated) { try KeychainInteraction.run(allowing: true) { try self.read() } }.value
    }
    nonisolated private func read() throws -> ServerInstallation? {
        var query = query; query[kSecReturnData as String] = true; query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?; let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw ServerSetupFailure.storage }
        return try JSONDecoder().decode(ServerInstallation.self, from: data)
    }
    func save(_ installation: ServerInstallation?) throws {
        try KeychainInteraction.run { try write(installation) }
    }
    private func write(_ installation: ServerInstallation?) throws {
        guard let installation else {
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw ServerSetupFailure.storage }; return
        }
        let attributes: [String: Any] = [kSecValueData as String: try JSONEncoder().encode(installation), kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound { status = SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil) }
        guard status == errSecSuccess else { throw ServerSetupFailure.storage }
    }
}

@MainActor final class ServerSetupFlow: ObservableObject {
    enum Phase { case address, checkingIdentity, confirmIdentity, checking, ready, installing, paused, connected, failed }
    static let shared = ServerSetupFlow()
    @Published private(set) var phase: Phase = .address
    @Published private(set) var target: ServerTarget?
    @Published private(set) var hostKey: SSHHostKey?
    @Published private(set) var preflight: ServerPreflight?
    @Published private(set) var stage = "connecting"
    @Published private(set) var error: ServerSetupFailure?
    @Published private(set) var connection: HomeConnection?
    @Published private(set) var installation: ServerInstallation?
    @Published private(set) var recoveryLoaded = false
    private let store: any ServerSetupStore
    private let probe: (ServerInstallation) async throws -> HomeConnection?
    private let transport: any ServerSSHTransport
    private let currentReleaseHash: () async throws -> String
    private var operation: Task<Void, Never>?
    private var generation = UUID()
    private var unlocking = false
    init(store: any ServerSetupStore = ServerSetupKeychain(), probe: ((ServerInstallation) async throws -> HomeConnection?)? = nil,
         transport: any ServerSSHTransport = SSHServerTransport(), releaseHash: (() async throws -> String)? = nil) {
        self.store = store
        self.probe = probe ?? Self.connect
        self.transport = transport
        self.currentReleaseHash = releaseHash ?? Self.releaseHash
        reloadRecovery()
    }
    func reloadRecovery() {
        guard !recoveryLoaded else { return }
        do {
            installation = try store.load()
            recoveryLoaded = true; error = nil; phase = .address
            if let saved = installation { target = saved.target; hostKey = saved.hostKey; phase = .paused }
        } catch { self.error = .storage; phase = .failed }
    }
    func unlockRecovery() {
        guard !recoveryLoaded else { resume(); return }
        guard !unlocking else { return }
        unlocking = true
        phase = .checking
        start {
            defer { self.unlocking = false }
            let saved = try await self.store.unlock()
            try Task.checkCancellation()
            self.installation = saved; self.recoveryLoaded = true
            self.target = saved?.target; self.hostKey = saved?.hostKey
            self.phase = saved == nil ? .address : .paused
            if let saved, let connection = try await self.probe(saved) {
                try Task.checkCancellation()
                self.connection = connection; self.phase = .connected
            }
        }
    }
    func resume() {
        guard phase == .paused, let saved = installation else { return }
        phase = .checking
        start {
            if let connection = try await self.probe(saved) {
                try Task.checkCancellation()
                self.connection = connection; self.phase = .connected
            } else {
                try Task.checkCancellation()
                self.phase = .paused
            }
        }
    }
    /// The pinned Home of a saved installation, checked without SSH while no
    /// setup page is working on it (an open page owns its operation).
    func finishedConnection() async -> HomeConnection? {
        guard phase == .paused, operation == nil, let saved = installation,
              let connection = try? await probe(saved),
              phase == .paused, operation == nil, installation?.id == saved.id else { return nil }
        return connection
    }
    func inspect(_ target: ServerTarget) {
        guard recoveryLoaded, installation == nil else { return }
        start {
            self.target = target; self.preflight = nil; self.phase = .checkingIdentity
            let key = try await self.transport.scan(target)
            try Task.checkCancellation()
            self.hostKey = key
            self.phase = .confirmIdentity
        }
    }
    func confirm(access: ServerAccess) {
        guard let target, let key = hostKey else { return }
        start {
            self.phase = .checking
            let data = try await self.transport.run(target: target, key: key, access: access, input: ServerSetupScripts.command("check_server"), elevated: false)
            try Task.checkCancellation()
            let check = try JSONDecoder().decode(ServerPreflight.self, from: data)
            self.preflight = check
            if let saved = self.installation {
                guard check.installationID == nil || check.installationID == saved.id else { throw ServerSetupFailure.identity }
                if check.installationID == saved.id { self.phase = .ready; return }
            }
            if let problem = check.installationProblem { throw problem }
            self.phase = .ready
        }
    }
    func install(access: ServerAccess) {
        guard let target, let key = hostKey, phase == .ready || (phase == .failed && installation != nil) else { return }
        start {
            self.phase = .installing; self.stage = "connecting"
            var saved: ServerInstallation
            if let pending = self.installation {
                saved = pending
                // The remote job can finish after a lost SSH reply. Check the
                // pinned Home first, before asking for SSH or replaying setup.
                if let connection = try await self.probe(saved) {
                    try Task.checkCancellation()
                    self.connection = connection; self.phase = .connected; return
                }
                let status: ServerInstallationStatus
                do {
                    let data = try await self.transport.run(target: target, key: key, access: access, input: ServerSetupScripts.command("server_status"), elevated: true)
                    status = try JSONDecoder().decode(ServerInstallationStatus.self, from: data)
                } catch ServerSetupFailure.connection {
                    try await self.waitForServer(saved, access: access)
                    return
                }
                // The connection can drop before staging writes its identity.
                // Replay the saved recipe; the remote script still refuses
                // unrelated data, ownership or an existing installation.
                guard status.installationID == nil || status.installationID == saved.id else { throw ServerSetupFailure.identity }
                if status.installationID == saved.id && ["activating", "active", "complete"].contains(status.state) {
                    try await self.waitForServer(saved, access: access)
                    return
                }
                if status.installationID == saved.id && status.canUpdateRelease == true {
                    let latest = try await self.currentReleaseHash()
                    if latest != saved.releaseHash {
                        saved.previousReleaseHash = saved.releaseHash
                        saved.releaseHash = latest
                    }
                }
            }
            else {
                let hash = try await self.currentReleaseHash()
                saved = try ServerInstallation(target: target, hostKey: key, releaseHash: hash)
            }
            try Task.checkCancellation()
            saved.attempted = true
            try self.store.save(saved); self.installation = saved
            let input = try ServerSetupScripts.install(saved, installer: ServerSetupScripts.resource("cloud-init"), script: String(decoding: ServerSetupScripts.resource("server-setup"), as: UTF8.self))
            do {
                _ = try await self.transport.run(target: target, key: key, access: access, input: Data(input.utf8), elevated: true)
            } catch ServerSetupFailure.connection {
                // A missing acknowledgement does not mean the remote job
                // failed. Observe the saved identity; never start a second job.
                try Task.checkCancellation()
            }
            try await self.waitForServer(saved, access: access)
        }
    }
    private static func releaseHash() async throws -> String {
        let session = DigitalOceanNoRedirects.session()
        defer { session.invalidateAndCancel() }
        let (data, response) = try await session.data(from: URL(string: "https://waiwai.is/openstrudel/downloads/SHA256SUMS")!)
        guard (response as? HTTPURLResponse)?.statusCode == 200, data.count < 16384 else { throw ServerSetupFailure.installer }
        return try DigitalOceanQuote.releaseHash(from: String(decoding: data, as: UTF8.self))
    }
    func pause() {
        generation = UUID(); operation?.cancel(); operation = nil
        phase = recoveryLoaded ? (installation != nil ? .paused : .address) : .failed
        if !recoveryLoaded { error = .storage }
    }
    func startOver() {
        guard recoveryLoaded, installation == nil else { return }
        pause(); target = nil; hostKey = nil; preflight = nil; error = nil
    }
    func finish() throws { try store.save(nil); installation = nil; connection = nil; target = nil; hostKey = nil; preflight = nil; phase = .address }
    func prepareForLocalErase() { pause() }
    func finishLocalErase() { installation = nil; connection = nil; target = nil; hostKey = nil; preflight = nil; error = nil; phase = .address }
    private func start(_ body: @escaping @MainActor () async throws -> Void) {
        operation?.cancel(); generation = UUID(); let id = generation; error = nil
        operation = Task {
            do { try await body() }
            catch {
                guard id == generation, !Task.isCancelled else { return }
                self.error = error as? ServerSetupFailure ?? .connection; phase = .failed
            }
        }
    }
    private func waitForServer(_ saved: ServerInstallation, access: ServerAccess) async throws {
        phase = .installing
        var readyChecks = 0, idleChecks = 0
        for _ in 0..<60 {
            try Task.checkCancellation()
            if let connection = try await probe(saved) {
                try Task.checkCancellation()
                self.connection = connection; phase = .connected; return
            }
            do {
                let data = try await transport.run(target: saved.target, key: saved.hostKey, access: access, input: ServerSetupScripts.command("server_status"), elevated: true)
                try Task.checkCancellation()
                let status = try JSONDecoder().decode(ServerInstallationStatus.self, from: data)
                guard status.installationID == nil || status.installationID == saved.id else { throw ServerSetupFailure.identity }
                if status.problemWhenUnreachable == .installation { throw ServerSetupFailure.installation }
                readyChecks = status.problemWhenUnreachable == .serviceUnreachable ? readyChecks + 1 : 0
                if readyChecks >= 3 { throw ServerSetupFailure.serviceUnreachable }
                // Nothing staged and nothing running: the install command never
                // arrived. Pause with Continue instead of waiting out every poll.
                idleChecks = status.installationID == nil && status.state == "inactive" ? idleChecks + 1 : 0
                if idleChecks >= 2 { phase = .paused; error = .notStarted; return }
                stage = ["connecting", "dependencies", "download", "build", "verify", "ready"].contains(status.stage) ? status.stage : "dependencies"
            } catch ServerSetupFailure.connection {
                // SSH may briefly disappear while packages/networking change.
                // Keep the same bounded polling loop and pinned HTTPS probe.
                try Task.checkCancellation()
                readyChecks = 0; idleChecks = 0
                stage = "reconnecting"
            }
            try await Task.sleep(for: .seconds(5))
        }
        phase = .paused; error = .waiting
    }
    private static func connect(_ saved: ServerInstallation) async throws -> HomeConnection? {
        let key = try P256.Signing.PrivateKey(pemRepresentation: saved.privateKeyPEM)
        let trust = DigitalOceanHomeTrust(host: saved.target.host, publicKey: key.publicKey.x963Representation)
        let session = trust.session(); defer { session.invalidateAndCancel() }
        let url = URL(string: "https://\(saved.target.host):7789")!
        var request = URLRequest(url: url.appending(path: "health")); request.timeoutInterval = 3
        request.setValue("Bearer " + saved.ownerToken, forHTTPHeaderField: "Authorization")
        do {
            let (data, response) = try await session.data(for: request)
            guard data.count <= 262144 else { throw ServerSetupFailure.identity }
            guard let response = response as? HTTPURLResponse, response.url == request.url else { throw ServerSetupFailure.identity }
            guard response.statusCode == 200 else {
                if [401, 403].contains(response.statusCode) { throw ServerSetupFailure.identity }; return nil
            }
            struct Health: Decodable { let ok: Bool; let service: String }
            let health = try JSONDecoder().decode(Health.self, from: data)
            guard health.ok, health.service == "openstrudel", let pin = trust.certificatePin else { throw ServerSetupFailure.identity }
            try Task.checkCancellation()
            return HomeConnection(url: url.absoluteString, token: saved.ownerToken, pin: pin, name: L("Server"))
        } catch {
            try Task.checkCancellation()
            if trust.identityRejected || error is ServerSetupFailure { throw ServerSetupFailure.identity }
            return nil
        }
    }
}
#endif
