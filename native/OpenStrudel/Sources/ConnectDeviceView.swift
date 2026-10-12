#if os(macOS)
import SwiftUI
import UniformTypeIdentifiers

/// Existing devices and newly installed servers both join the same library.
struct ConnectDeviceView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var library: DeviceLibrary
    let onConfirm: (MacPairing) -> Void
    @State private var route: Route = .choice
    private enum Route { case choice, link, server, cloud }

    var body: some View {
        Group {
            switch route {
            case .link: ConnectionInvitationView(onConfirm: onConfirm, onBack: { route = .choice })
            case .server: OwnServerSetupView(onBack: { route = .choice }, onConnected: { dismiss() })
            case .cloud: ServerSetupView()
            case .choice:
                NavigationStack {
                    VStack(alignment: .leading, spacing: 28) {
                        Text(L("Connect a device"))
                            .font(.system(.largeTitle, design: .serif, weight: .medium))
                        Text(L("Use employees from your other devices here."))
                            .foregroundStyle(AppTheme.secondaryText)
                        VStack(spacing: 0) {
                            choice("Connect with a link", detail: "Add a device using its connection link.", icon: "desktopcomputer", route: .link)
                            Divider().padding(.leading, 52)
                            choice(ServerSetupFlow.shared.installation == nil ? "Set up a server" : "Continue server setup", detail: "Enter its address. OpenStrudel takes care of installation.", icon: "server.rack", route: .server)
                        }
                        Button { route = .cloud } label: {
                            Label(L("Get a server with DigitalOcean"), systemImage: "cloud")
                        }.buttonStyle(.plain).foregroundStyle(AppTheme.accent)
                            .accessibilityIdentifier("getCloudServer")
                        Spacer(minLength: 0)
                    }.padding(32)
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button(L("Отмена")) { dismiss() } } }
                }.frame(width: 520, height: 500)
            }
        }.environmentObject(library)
    }

    private func choice(_ title: String, detail: String, icon: String, route next: Route) -> some View {
        Button { route = next } label: {
            HStack(spacing: 16) {
                Image(systemName: icon).font(.title2).frame(width: 32).foregroundStyle(AppTheme.secondaryText)
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.text(title)).font(.headline)
                    Text(L10n.text(detail)).font(.callout).foregroundStyle(AppTheme.secondaryText).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right").foregroundStyle(AppTheme.secondaryText)
            }.padding(.vertical, 22).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityIdentifier(next == .server ? "setUpOwnServer" : "connectDeviceLink")
    }
}

private struct OwnServerSetupView: View {
    @EnvironmentObject private var library: DeviceLibrary
    @StateObject private var flow = ServerSetupFlow.shared
    let onBack: () -> Void
    let onConnected: () -> Void
    @State private var host = ""
    @State private var user = "root"
    @State private var port = "22"
    @State private var useKey = false
    @State private var password = ""
    @State private var key: Data?
    @State private var keyName: String?
    @State private var passphrase = ""
    @State private var choosingKey = false
    @State private var localError: String?
    @State private var saving = false

    private var access: ServerAccess { ServerAccess(password: useKey ? "" : password, privateKey: useKey ? key : nil, passphrase: passphrase) }
    private var busy: Bool { [.checkingIdentity, .checking, .installing].contains(flow.phase) || saving }
    private var editing: Bool { flow.recoveryLoaded && (flow.phase == .address || flow.phase == .paused || (flow.phase == .failed && flow.installation == nil)) }
    private var title: String {
        switch flow.phase {
        case .confirmIdentity: L("Confirm your server")
        case .ready: flow.installation == nil ? L("Ready to install") : L("Continue server setup")
        case .installing: L("Preparing your server")
        case .connected: L("Your server is ready")
        case .paused: L("Continue server setup")
        case .failed: flow.installation == nil ? L("Set up a server") : L("Setup needs attention")
        default: L("Set up a server")
        }
    }
    private var stageTitle: String {
        switch flow.stage {
        case "dependencies": L("Preparing the server")
        case "download": L("Downloading OpenStrudel")
        case "build": L("Installing OpenStrudel")
        case "verify": L("Checking the connection")
        case "ready": L("Opening your server")
        default: L("Connecting to the server")
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text(title).font(.system(.largeTitle, design: .serif, weight: .medium))
                        .fixedSize(horizontal: false, vertical: true)
                    if editing { addressForm }
                    if flow.phase == .confirmIdentity, let target = flow.target, let identity = flow.hostKey {
                        Text(target.host).font(.title3.weight(.semibold)).textSelection(.enabled)
                        Text(L("Compare this fingerprint with the one in your server provider's control panel."))
                            .foregroundStyle(AppTheme.secondaryText).fixedSize(horizontal: false, vertical: true)
                        Text(identity.fingerprint).font(.system(.callout, design: .monospaced))
                            .textSelection(.enabled).environment(\.layoutDirection, .leftToRight)
                            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                            .background(.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 14))
                        Button(L("Confirm and connect")) { flow.confirm(access: access) }
                            .buttonStyle(.glassProminent).controlSize(.large).keyboardShortcut(.defaultAction)
                            .accessibilityIdentifier("confirmSSHIdentity")
                    }
                    if flow.phase == .ready {
                        Text(flow.target?.host ?? "").font(.title3.weight(.semibold))
                        if flow.installation == nil {
                            Text(L("OpenStrudel will be installed on this server. Assistants and their files will stay here."))
                                .foregroundStyle(AppTheme.secondaryText).fixedSize(horizontal: false, vertical: true)
                            if let check = flow.preflight {
                                Text("Ubuntu \(check.version) · \(Int((Double(check.memoryMiB) / 1024).rounded())) GB · \(check.diskGiB) GB")
                                    .font(.callout).foregroundStyle(AppTheme.secondaryText)
                                    .environment(\.layoutDirection, .leftToRight)
                            }
                        }
                        Button(flow.installation == nil ? L("Install OpenStrudel") : L("Continue setup")) { flow.install(access: access) }
                            .buttonStyle(.glassProminent).controlSize(.large).keyboardShortcut(.defaultAction)
                            .accessibilityIdentifier("installOnServer")
                    }
                    if busy {
                        HStack(spacing: 12) {
                            ProgressView().controlSize(.small)
                            Text(flow.phase == .checkingIdentity ? L("Checking the server's identity") : flow.phase == .checking ? L("Checking your server") : stageTitle)
                                .font(.headline).fixedSize(horizontal: false, vertical: true)
                        }.accessibilityElement(children: .combine).accessibilityIdentifier("serverSetupProgress")
                        if flow.phase == .installing && flow.stage != "connecting" {
                            Text(L("This can take a few minutes. You can close this window; installation continues on the server."))
                                .foregroundStyle(AppTheme.secondaryText).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    if let error = localError ?? flow.error?.localizedDescription {
                        Text(error).font(.callout).foregroundStyle(AppTheme.destructive)
                            .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("serverSetupError")
                    }
                    if !flow.recoveryLoaded && !busy {
                        Button(L("Повторить")) { flow.unlockRecovery() }
                            .buttonStyle(.glassProminent).controlSize(.large)
                    }
                    if flow.phase == .failed, flow.installation != nil {
                        credentials
                        Button(L("Retry installation")) { validate { flow.install(access: access) } }
                            .buttonStyle(.glassProminent).controlSize(.large)
                    }
                    if flow.phase == .connected {
                        Label(flow.target?.host ?? "", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                        Text(L("Sign in to ChatGPT on this device to create your first employee."))
                            .foregroundStyle(AppTheme.secondaryText).fixedSize(horizontal: false, vertical: true)
                        Button(L("Open server")) { Task { await finish() } }
                            .buttonStyle(.glassProminent).controlSize(.large).disabled(saving)
                            .accessibilityIdentifier("openNewServer")
                    }
                }.padding(32).frame(maxWidth: 500).frame(maxWidth: .infinity)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(flow.installation == nil ? L("Назад") : L("Продолжить позже")) {
                        flow.pause(); password = ""; passphrase = ""; key = nil; onBack()
                    }.disabled(saving)
                }
            }
        }.frame(width: 540, height: 650)
        .onAppear {
            if let target = flow.target { host = target.host; user = target.user; port = String(target.port) }
            flow.resume()
        }
        .onDisappear { flow.pause(); password = ""; passphrase = ""; key = nil }
        .fileImporter(isPresented: $choosingKey, allowedContentTypes: [.item], allowsMultipleSelection: false) { result in
            do {
                guard let url = try result.get().first else { return }
                let scoped = url.startAccessingSecurityScopedResource(); defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size > 0, size <= 131072 else { throw ServerSetupFailure.credentials }
                key = try Data(contentsOf: url); keyName = url.lastPathComponent; localError = nil
            } catch { localError = ServerSetupFailure.credentials.localizedDescription }
        }
    }

    private var addressForm: some View {
        VStack(alignment: .leading, spacing: 20) {
            if flow.installation == nil {
                Text(L("Use an Ubuntu 24.04 server with 4 GB of memory and 30 GB of storage."))
                    .foregroundStyle(AppTheme.secondaryText).fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 8) {
                    Text(L("Server address")).font(.headline)
                    TextField("203.0.113.10", text: $host).textFieldStyle(.roundedBorder).accessibilityIdentifier("serverAddress")
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text(L("Sign-in name")).font(.headline)
                    TextField("root", text: $user).textFieldStyle(.roundedBorder).accessibilityIdentifier("serverUser")
                }
            } else {
                Text(host).font(.title3.weight(.semibold))
                Text(L("Enter your server credentials again to continue. Your installation is saved."))
                    .foregroundStyle(AppTheme.secondaryText).fixedSize(horizontal: false, vertical: true)
            }
            credentials
            if flow.installation == nil {
                DisclosureGroup(L("SSH port")) {
                    TextField("22", text: $port).textFieldStyle(.roundedBorder).frame(width: 100).padding(.top, 8)
                }.foregroundStyle(AppTheme.secondaryText)
            }
            Button(L("Продолжить")) {
                validate {
                    if flow.installation != nil { flow.confirm(access: access) }
                    else { flow.inspect(try ServerTarget(host: host, user: user, port: Int(port) ?? 0)) }
                }
            }.buttonStyle(.glassProminent).controlSize(.large).keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("checkOwnServer")
        }
    }

    private var credentials: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker(L("Sign in with"), selection: $useKey) {
                Text(L("Пароль")).tag(false)
                Text(L("SSH key")).tag(true)
            }.pickerStyle(.segmented).labelsHidden().accessibilityIdentifier("serverAccessMethod")
            if useKey {
                Button(keyName ?? L("Choose private key…")) { choosingKey = true }.buttonStyle(.glass)
                SecureField(L("Key passphrase, if any"), text: $passphrase).textFieldStyle(.roundedBorder)
            } else {
                SecureField(L("Пароль"), text: $password).textFieldStyle(.roundedBorder).accessibilityIdentifier("serverPassword")
            }
            Text(L("Your SSH password and key are used only for this setup session."))
                .font(.caption).foregroundStyle(AppTheme.secondaryText).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func validate(_ action: () throws -> Void) {
        do { if useKey && key == nil { throw ServerSetupFailure.credentials }; try access.validate(); localError = nil; try action() }
        catch { localError = error.localizedDescription }
    }
    private func finish() async {
        guard let connection = flow.connection, !saving else { return }
        saving = true; defer { saving = false }
        let client = library.clients.first { $0.savedBaseURL == connection.url } ?? library.newConnection()
        guard await client.connectToCloud(connection) else { localError = client.pairingError; return }
        library.add(client)
        do { try flow.finish(); onConnected() }
        catch { localError = error.localizedDescription }
    }
}
#endif
