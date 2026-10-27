#if os(macOS)
import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Existing devices and newly installed servers both join the same library.
/// One stack and one sheet size for every page; each page has a navigation title and Back.
struct ConnectDeviceView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var library: DeviceLibrary
    let onConfirm: (MacPairing) -> Void
    @State private var path: [Route] = []
    @State private var connectedClient: HomeClient?
    @State private var cloudWorking = false
    private enum Route: Hashable { case link, server, cloud, agentMetal }

    init(continueServerSetup: Bool = false, onConfirm: @escaping (MacPairing) -> Void) {
        self.onConfirm = onConfirm
        _path = State(initialValue: continueServerSetup ? [.server] : [])
    }

    var body: some View {
        Group {
            if let connectedClient {
                ServerAccountSetupView(onDone: { dismiss() }).environmentObject(connectedClient)
            } else {
                NavigationStack(path: $path) {
                    choices
                        .navigationDestination(for: Route.self) { route in
                            switch route {
                            case .link: ConnectionLinkPage(onConfirm: onConfirm, close: { dismiss() })
                            case .server: OwnServerSetupView(onConnected: completeInstallation)
                            case .cloud: ServerSetupView(working: $cloudWorking, onConnected: completeInstallation)
                            case .agentMetal: AgentMetalSetupView(working: $cloudWorking, onConnected: completeInstallation)
                            }
                        }
                }
                .toolbar {
                    // Cloud setup keeps going on the provider's side, so leaving it mid-way is not a cancel.
                    ToolbarItem(placement: .cancellationAction) {
                        Button(cloudWorking ? L("Продолжить позже") : L("Отмена")) { dismiss() }
                    }
                }
            }
        }
        // The account step replaces the stack at the same size, so finishing setup never resizes the sheet.
        .frame(width: Sheet.width, height: Sheet.height)
        .presentationSizing(.form)
        .tint(nil)
        .environmentObject(library)
        .modifier(InterfaceLanguage())
    }

    /// Device and provider routes share the same compact list.
    private var choices: some View {
        Form {
            Section {
                NavigationLink(value: Route.link) {
                    choice(L("Connect with a link"), detail: L("Add a device using its connection link."), symbol: "link")
                }.accessibilityIdentifier("connectDeviceLink")
                NavigationLink(value: Route.server) {
                    choice(ServerSetupFlow.shared.installation == nil ? L("Set up my server") : L("Continue server setup"),
                           detail: L("Already have a server? Enter its address and sign-in details."), symbol: "server.rack")
                }.accessibilityIdentifier("setUpOwnServer")
                NavigationLink(value: Route.cloud) {
                    choice(L("Get a server with DigitalOcean"), detail: L("Размещение оплачивается, пока вы не удалите его в DigitalOcean."), symbol: "cloud")
                }.accessibilityIdentifier("getCloudServer")
                NavigationLink(value: Route.agentMetal) {
                    choice(L("Get a server with AgentMetal"), detail: L("Pay by card. Setup is automatic."), symbol: "creditcard")
                }.accessibilityIdentifier("getAgentMetalServer")
            } footer: {
                Text(L("Use assistants from your other devices here."))
            }
        }
        .formStyle(.grouped)
        .navigationTitle(L("Добавить Mac или сервер"))
    }

    private func completeInstallation(_ client: HomeClient) {
        connectedClient = client
    }

    private func choice(_ title: String, detail: String, symbol: String) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail).font(AppTypography.meta).foregroundStyle(AppTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } icon: { Image(systemName: symbol).frame(width: 20) }
    }
}

/// Paste a connection link from another device. A web page link opens in the browser instead.
private struct ConnectionLinkPage: View {
    @Environment(\.openURL) private var openURL
    let onConfirm: (MacPairing) -> Void
    let close: () -> Void
    @State private var invitation = ""
    @State private var error: String?
    @State private var openingPage = false

    private var trimmed: String { invitation.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var connectionPage: URL? {
        guard let url = URL(string: trimmed), url.scheme?.lowercased() == "https",
              let host = url.host, !host.isEmpty, url.user == nil, url.password == nil,
              (try? MacPairing(url: url)) == nil else { return nil }
        return url
    }

    var body: some View {
        Form {
            Section {
                // The link field takes the row; Paste sits beside it at the same control size.
                HStack(spacing: 12) {
                SecureField(L("Ссылка подключения"), text: $invitation, prompt: Text(L("Ссылка подключения"))).labelsHidden()
                        .environment(\.layoutDirection, .leftToRight)
                        .frame(maxWidth: .infinity)
                        .accessibilityIdentifier("connectionInvitation")
                        .onSubmit(confirm)
                    PasteButton(payloadType: String.self) { values in
                        if let value = values.first { invitation = value; error = nil }
                    }.labelStyle(.titleOnly)
                }
                if let error {
                    Text(UserFacingError.text(error)).foregroundStyle(AppTheme.warning)
                        .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("invitationError")
                }
            } footer: {
                if let page = connectionPage {
                    Text(L("Откроется \(page.host ?? L("страница подключения")) в браузере. На странице нажмите «Открыть OpenStrudel»."))
                } else {
                    Text(L("На устройстве с сотрудниками откройте Настройки → Устройства → Поделиться доступом. Вставьте ссылку сюда."))
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(L("Connect with a link"))
        .onChange(of: invitation) { _, _ in error = nil }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(openingPage ? L("Открываем…") : connectionPage == nil ? L("Продолжить") : L("Открыть страницу"), action: confirm)
                    .disabled(openingPage || trimmed.isEmpty)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("continueConnection")
            }
        }
    }

    private func confirm() {
        guard !openingPage, !trimmed.isEmpty else { return }
        if let page = connectionPage {
            openingPage = true
            openURL(page) { accepted in
                openingPage = false
                if accepted { close() }
                else { error = L("Не удалось открыть браузер. Откройте ссылку в браузере на этом устройстве и нажмите «Открыть OpenStrudel».") }
            }
            return
        }
        do {
            guard let url = URL(string: trimmed) else { throw HomeClientError.invalidURL }
            onConfirm(try MacPairing(url: url)); close()
        } catch {
            self.error = L("Это не ссылка подключения OpenStrudel. Скопируйте новую из настроек на устройстве с сотрудниками.")
        }
    }
}

private struct OwnServerSetupView: View {
    @EnvironmentObject private var library: DeviceLibrary
    @StateObject private var flow = ServerSetupFlow.shared
    let onConnected: (HomeClient) -> Void
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
        case .connected: L("OpenStrudel is installed")
        case .paused: L("Continue server setup")
        case .failed: L("Setup needs attention")
        default: L("Set up my server")
        }
    }
    private func stageTitle(_ stage: String) -> String {
        switch stage {
        case "dependencies": L("Preparing the server")
        case "download": L("Downloading OpenStrudel")
        case "build": L("Installing OpenStrudel")
        case "verify": L("Checking the connection")
        case "ready": L("Opening your server")
        case "reconnecting": L("Reconnecting to the server")
        default: L("Connecting to the server")
        }
    }

    /// The one next step of the current phase. It sits in the confirmation placement.
    private struct Step { let title: String; let id: String; var enabled = true; let run: () -> Void }
    private var step: Step? {
        if !flow.recoveryLoaded && !busy { return Step(title: L("Повторить"), id: "retryServerSetup") { flow.unlockRecovery() } }
        if editing {
            return Step(title: L("Продолжить"), id: "checkOwnServer") {
                validate {
                    if flow.installation != nil { flow.confirm(access: access) }
                    else { flow.inspect(try ServerTarget(host: host, user: user, port: Int(port) ?? 0)) }
                }
            }
        }
        switch flow.phase {
        case .confirmIdentity: return Step(title: L("Confirm and connect"), id: "confirmSSHIdentity") { flow.confirm(access: access) }
        case .ready: return Step(title: flow.installation == nil ? L("Install OpenStrudel") : L("Continue setup"), id: "installOnServer") { flow.install(access: access) }
        case .failed where flow.installation != nil: return Step(title: L("Continue setup"), id: "retryInstallation") { localError = nil; flow.install(access: access) }
        case .connected: return Step(title: L("Продолжить"), id: "openNewServer", enabled: !saving) { Task { await finish() } }
        default: return nil
        }
    }

    var body: some View {
        Form {
            SheetTitleSection(title: title)
            if let error = localError ?? flow.error?.localizedDescription {
                Section {
                    Label { Text(error).fixedSize(horizontal: false, vertical: true) } icon: {
                        Image(systemName: "exclamationmark.triangle")
                    }
                    .foregroundStyle(AppTheme.warning).accessibilityIdentifier("serverSetupError")
                    if flow.phase == .failed, flow.installation == nil, let check = flow.preflight {
                        serverResources(check)
                    }
                }
            }
            if editing { addressForm }
            if flow.phase == .confirmIdentity, let target = flow.target, let identity = flow.hostKey {
                Section {
                    LabeledContent(L("Server address")) { Text(target.host).textSelection(.enabled) }
                    Text(identity.fingerprint).font(AppTypography.code).textSelection(.enabled)
                        .environment(\.layoutDirection, .leftToRight)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } footer: {
                    Text(L("Compare this fingerprint with the one in your server provider's control panel."))
                }
            }
            if flow.phase == .ready {
                Section {
                    LabeledContent(L("Server address")) { Text(flow.target?.host ?? "") }
                    if flow.installation == nil, let check = flow.preflight {
                        serverResources(check)
                        if check.recommendsMoreMemory {
                            Text(L("You can install on this server. With less than 4 GB of memory, large files or several assistants working at once may run out of memory."))
                                .foregroundStyle(AppTheme.warning).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                } footer: {
                    if flow.installation == nil {
                        Text(L("OpenStrudel will be installed on this server. Assistants and their files will stay here."))
                    }
                }
            }
            if flow.phase == .failed, flow.installation != nil { credentials }
            if flow.phase == .connected {
                Section {
                    Label { Text(flow.target?.host ?? "") } icon: { Image(systemName: "checkmark.circle.fill") }
                } footer: { Text(L("Next, connect your ChatGPT account.")) }
            }
            if busy {
                Section {
                    if flow.phase == .checkingIdentity || flow.phase == .checking {
                        Label {
                            Text(flow.phase == .checkingIdentity ? L("Checking the server's identity") : L("Checking your server"))
                                .fixedSize(horizontal: false, vertical: true)
                        } icon: { ProgressView().controlSize(.small).frame(width: 20) }
                            .accessibilityElement(children: .combine).accessibilityIdentifier("serverSetupProgress")
                    } else {
                        installationProgress
                    }
                } footer: {
                    if busy && flow.phase == .installing && flow.stage != "connecting" {
                        Text(L("This can take a few minutes. You can close this window; installation continues on the server."))
                    }
                }
            }
            if flow.installation != nil, !busy, flow.phase != .connected {
                Section { ForgetServerSetupButton(flow: flow) }
            }
        }
        .formStyle(.grouped)
        .sheetPageTitle(title)
        .toolbar {
            if let step {
                ToolbarItem(placement: .confirmationAction) {
                    Button(step.title, action: step.run).disabled(!step.enabled || busy)
                        .keyboardShortcut(.defaultAction).accessibilityIdentifier(step.id)
                }
            }
        }
        .onAppear {
            if let target = flow.target { host = target.host; user = target.user; port = String(target.port) }
            flow.resume()
        }
        .onDisappear { flow.pause(); password = ""; passphrase = ""; key = nil }
        .onChange(of: flow.phase, initial: true) { _, phase in
            if phase == .connected { Task { await finish() } }
        }
        .fileImporter(isPresented: $choosingKey, allowedContentTypes: [.item], allowsMultipleSelection: false) { result in
            do {
                guard let url = try result.get().first else { return }
                let scoped = url.startAccessingSecurityScopedResource(); defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size > 0, size <= 131072 else { throw ServerSetupFailure.credentials }
                key = try SSHPrivateKey.normalized(Data(contentsOf: url)); keyName = url.lastPathComponent; passphrase = ""; localError = nil
            } catch { key = nil; keyName = nil; localError = ServerSetupFailure.privateKey.localizedDescription }
        }
    }

    /// The bar keeps moving between status checks. Once the server answers,
    /// it is full while the server joins the device list.
    private var installationProgress: some View {
        var progress = flow.progress
        if flow.phase == .connected { progress.report("ready", at: .now) }
        return VStack(alignment: .leading, spacing: 8) {
            TimelineView(.periodic(from: .now, by: 0.5)) { context in
                ProgressView(value: progress.value(at: context.date))
            }
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(stageTitle(progress.stage)).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Text(L("Шаг \(progress.step) из \(ServerSetupProgress.steps)"))
                    .font(AppTypography.meta).monospacedDigit().foregroundStyle(AppTheme.secondaryText)
            }
        }
        .accessibilityElement(children: .combine).accessibilityIdentifier("serverSetupProgress")
    }

    @ViewBuilder private func serverResources(_ check: ServerPreflight) -> some View {
        LabeledContent(L("System")) { Text("\(check.os.capitalized) \(check.version)") }
        LabeledContent(L("Memory")) {
            Text(L("\((Double(check.memoryMiB) / 1024).formatted(.number.precision(.fractionLength(1)))) GB"))
                .monospacedDigit()
        }
        LabeledContent(L("Storage")) { Text(L("\(check.freeGiB) GB free of \(check.diskGiB) GB")).monospacedDigit() }
    }

    @ViewBuilder private var addressForm: some View {
        if flow.installation == nil {
            Section {
                TextField(L("Server address"), text: $host, prompt: Text(verbatim: "203.0.113.10"))
                    .accessibilityIdentifier("serverAddress")
                TextField(L("Sign-in name"), text: $user, prompt: Text(verbatim: "root"))
                    .accessibilityIdentifier("serverUser")
                TextField(L("SSH port"), text: $port, prompt: Text(verbatim: "22")).monospacedDigit()
            } footer: {
                Text(L("Use Ubuntu 24.04 LTS or newer with at least 8 GB free. We recommend 4 GB of memory; smaller servers can also be used."))
            }
        } else {
            Section {
                LabeledContent(L("Server address")) { Text(host) }
            } footer: {
                Text(L("Enter your server credentials again to continue. Your installation is saved."))
            }
        }
        credentials
    }

    private var credentials: some View {
        Section {
            Picker(L("Sign in with"), selection: $useKey) {
                Text(L("Пароль")).tag(false)
                Text(L("SSH key")).tag(true)
            }.pickerStyle(.segmented).accessibilityIdentifier("serverAccessMethod")
            if useKey {
                LabeledContent(L("SSH key")) {
                    HStack(spacing: 8) {
                        Button(L("Choose private key…")) { choosingKey = true }.accessibilityIdentifier("chooseSSHKey")
                        Button(L("Paste key")) {
                            do {
                                guard let text = NSPasteboard.general.string(forType: .string) else { throw ServerSetupFailure.privateKey }
                                key = try SSHPrivateKey.normalized(Data(text.utf8)); keyName = L("Pasted SSH key"); passphrase = ""; localError = nil
                            } catch { key = nil; keyName = nil; localError = ServerSetupFailure.privateKey.localizedDescription }
                        }.accessibilityIdentifier("pasteSSHKey")
                    }
                }
                if let keyName {
                    Label { Text(keyName).lineLimit(1).truncationMode(.middle) } icon: {
                        Image(systemName: "checkmark.circle").frame(width: 20)
                    }.accessibilityIdentifier("selectedSSHKey")
                }
                SecureField(L("Key passphrase, if any"), text: $passphrase, prompt: Text(L("Optional")))
                    .accessibilityIdentifier("sshKeyPassphrase")
            } else {
                SecureField(L("Пароль"), text: $password, prompt: Text(L("Required"))).accessibilityIdentifier("serverPassword")
            }
        } footer: {
            Text(L("Your SSH password and key are used only for this setup session."))
        }
    }

    private func validate(_ action: () throws -> Void) {
        do { if useKey && key == nil { throw ServerSetupFailure.credentials }; try access.validate(); localError = nil; try action() }
        catch { localError = error.localizedDescription }
    }
    private func finish() async {
        guard let connection = flow.connection, !saving else { return }
        saving = true; defer { saving = false }
        // The new device is not selected: that would replace this sheet's root before account setup.
        do { onConnected(try await library.adoptServer(connection, from: flow)) }
        catch { localError = error.localizedDescription }
    }
}

/// Abandons a pending own-server setup on this Mac after the person confirms.
/// Nothing is sent to the server.
struct ForgetServerSetupButton: View {
    @ObservedObject var flow: ServerSetupFlow
    @State private var confirming = false
    @State private var failure: String?
    var body: some View {
        if let pending = flow.installation {
            Button(L("Забыть настройку сервера…"), role: .destructive) { confirming = true }
                .foregroundStyle(AppTheme.destructive)
                .accessibilityIdentifier("forgetServerSetup")
                .confirmationDialog(L("Забыть настройку сервера?"), isPresented: $confirming, titleVisibility: .visible) {
                    Button(L("Забыть настройку"), role: .destructive) {
                        do { try flow.startOver() } catch { failure = error.localizedDescription }
                    }
                } message: {
                    Text(L("Этот Mac забудет незавершённую настройку \(pending.target.host). Сам сервер не изменится. Чтобы установить OpenStrudel снова, используйте новый сервер Ubuntu."))
                }
                .alert("OpenStrudel", isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
                    Button(L("Понятно"), role: .cancel) {}
                } message: { Text(failure ?? "") }
        }
    }
}
#endif
