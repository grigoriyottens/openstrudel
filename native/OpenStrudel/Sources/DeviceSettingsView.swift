import SwiftUI
#if os(macOS)
import AppKit
#endif

struct SavedConnectionUnlockButton: View {
    @ObservedObject var client: HomeClient
    var body: some View {
        HStack(spacing: 8) {
            Button(L("Unlock connection")) {
                Task { if await client.unlockSavedConnection() { await client.load(quiet: true) } }
            }
            .disabled(client.isUnlockingConnection)
            .accessibilityIdentifier("unlockSavedConnection")
            if client.isUnlockingConnection { ProgressView().controlSize(.small) }
        }
    }
}

/// The Settings window on the Mac (toolbar tabs) and the settings sheet on iOS (a section menu).
/// Every pane is a grouped Form made of the same rows on both platforms.
struct SettingsView: View {
    enum Section: String, CaseIterable {
        case devices, accounts, backups, application
        /// The iOS section menu keeps these names.
        var title: String {
            switch self { case .devices: L("Устройства"); case .accounts: L("Аккаунты"); case .backups: L("Копии"); case .application: L("Приложение") }
        }
        /// Mac tab names; the window title follows the selected tab.
        var tabTitle: String { self == .application ? L("Основные") : title }
        var symbol: String {
            switch self {
            case .devices: "laptopcomputer.and.iphone"
            case .accounts: "person.crop.circle"
            case .backups: "clock.arrow.circlepath"
            case .application: "gearshape"
            }
        }
    }
    /// Other screens open a pane by writing its raw value here and then calling `openSettings`.
    static let tabKey = "openstrudel.settingsTab"

    @EnvironmentObject private var library: DeviceLibrary
    @EnvironmentObject private var client: HomeClient
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsView.tabKey) private var tab: Section = .devices
    @State private var section: Section
    @State private var selectedID = ""
    private let initialSection: Section?
    private let standalone: Bool
    private var selected: HomeClient { library.clients.first { $0.id == selectedID } ?? client }

    init(initialSection: Section? = nil, standalone: Bool = false) {
        self.initialSection = initialSection
        self.standalone = standalone
        _section = State(initialValue: initialSection ?? .devices)
    }

    var body: some View {
        settings
            .modifier(InterfaceLanguage())
            .onAppear {
                selectedID = client.id
                if let initialSection { tab = initialSection }
            }
    }

    #if os(macOS)
    @ViewBuilder private var settings: some View {
        if standalone { tabs }
        else {
            // Presented as a sheet until every entry point opens the Settings window.
            tabs.toolbar { ToolbarItem(placement: .confirmationAction) { Button(L("Готово")) { dismiss() } } }
        }
    }

    private var tabs: some View {
        TabView(selection: $tab) {
            ForEach(Section.allCases, id: \.self) { section in
                Tab(section.tabTitle, systemImage: section.symbol, value: section) {
                    // Devices presents Connect a device, a 560 × 480 sheet with its bars.
                    SettingsPane(minHeight: section == .devices ? 560 : 360) { pane(section) }
                }
            }
        }
    }
    #else
    private var settings: some View {
        NavigationStack {
            Form {
                SwiftUI.Section {
                    Picker(L("Настройки"), selection: $section) {
                        ForEach(Section.allCases, id: \.self) { Text($0.title) }
                    }
                    .pickerStyle(.menu).labelsHidden()
                    .accessibilityIdentifier("settingsSection")
                }
                pane(section)
            }
            .navigationTitle(L("Настройки"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(L("Готово")) { dismiss() } } }
        }
    }
    #endif

    @ViewBuilder private func pane(_ section: Section) -> some View {
        switch section {
        case .devices:
            DevicesPane()
        case .accounts:
            DevicePickerSection(title: L("Устройство"), selection: $selectedID)
            DeviceAccountsView().environmentObject(selected).id(selected.id)
            SwiftUI.Section(L("Telegram на «\(selected.executionDeviceName)»")) {
                TelegramSetupView().environmentObject(selected)
            }.id("telegram-" + selected.id)
        case .backups:
            DevicePickerSection(title: L("Устройство"), selection: $selectedID)
            SwiftUI.Section(L("Резервная копия сотрудников")) {
                AgentTransferSettings().environmentObject(selected)
            }.id("backup-" + selected.id)
        case .application:
            GeneralPane(selectedID: $selectedID, selected: selected)
        }
    }
}

#if os(macOS)
/// A Settings window pane: a grouped Form 600 wide whose height follows its rows up to 720,
/// so the window fits each tab and scrolls only when a pane is long.
private struct SettingsPane<Content: View>: View {
    /// 360, or 560 for a pane whose sheets need the room: the window must hold its tallest sheet.
    var minHeight: CGFloat = 360
    @ViewBuilder let content: Content
    @State private var height: CGFloat = 360

    var body: some View {
        Form { content }
            .formStyle(.grouped)
            .tint(nil)
            // The content already holds the Form's top and bottom margins. The top inset is the
            // toolbar, which the window adds above the pane by itself.
            .onScrollGeometryChange(for: CGFloat.self) { $0.contentSize.height } action: { _, value in
                height = value
            }
            .frame(width: 600, height: min(max(height, minHeight), 720))
    }
}
#endif

/// The first section of a device-scoped pane when several devices are connected.
private struct DevicePickerSection: View {
    @EnvironmentObject private var library: DeviceLibrary
    let title: String
    @Binding var selection: String

    var body: some View {
        if library.visibleClients.count > 1 {
            Section {
                Picker(title, selection: $selection) {
                    ForEach(library.visibleClients) { Text($0.displayName).tag($0.id) }
                }
            }
        }
    }
}

private struct DevicesPane: View {
    @EnvironmentObject private var library: DeviceLibrary
    @State private var adding = false
    @State private var pairing: MacPairing?
    @State private var confirmingPairing: MacPairing?
    @State private var localStarting = false
    @State private var expandedDeviceID: String?
    @State private var removing: HomeClient?

    var body: some View {
        Group {
            ForEach(library.visibleClients) { device in
                Section {
                    DisclosureGroup(isExpanded: Binding(
                        get: { expandedDeviceID == device.id },
                        set: { expandedDeviceID = $0 ? device.id : nil }
                    )) {
                        if device.connectionNeedsUnlock {
                            LabeledContent {
                                SavedConnectionUnlockButton(client: device)
                            } label: {
                                Text(L("Unlock the saved connection to continue. Your chats and drafts are safe."))
                            }
                        } else {
                            MobilePairingSettings().environmentObject(device)
                        }
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(device.displayName)
                                Text(status(device)).font(AppTypography.meta).monospacedDigit().foregroundStyle(AppTheme.secondaryText)
                            }
                        } icon: {
                            Image(systemName: device.deviceSymbol)
                        }
                    }
                    .accessibilityIdentifier("deviceDetails")
                    Button(L("Убрать подключение…"), role: .destructive) { removing = device }
                        .foregroundStyle(AppTheme.destructive)
                        .accessibilityIdentifier("signOutThisDevice")
                        .accessibilityLabel(L("Убрать подключение к «\(device.displayName)»"))
                }
            }
            Section {
                Button(L("Подключить устройство…")) { adding = true }
                    .accessibilityIdentifier("addDevice")
                HiddenEmployeesButton(prominent: true)
                #if os(macOS)
                if !library.visibleClients.contains(where: \.isLocalConnection), LocalHome.isAvailable {
                    Button(localStarting ? L("Запускаем этот Mac…") : L("Работать также на этом Mac")) {
                        localStarting = true
                        Task { await library.openLocal(); localStarting = false }
                    }.disabled(localStarting)
                }
                #endif
            } footer: {
                Text(L("Сотрудники работают там, где вы их создали. Здесь можно подключить ещё один Mac или сервер."))
            }
        }
        .sheet(isPresented: $adding, onDismiss: {
            if let pairing { confirmingPairing = pairing; self.pairing = nil }
        }) {
            #if os(macOS)
            ConnectDeviceView { pairing = $0 }
            #else
            ConnectionInvitationView { pairing = $0 }
            #endif
        }
        .sheet(item: $confirmingPairing) { AddDeviceConfirmation(pairing: $0).environmentObject(library) }
        .sheet(item: $removing) { device in
            DeviceSignOutView { removing = nil }.environmentObject(device).environmentObject(library)
        }
    }

    private func status(_ device: HomeClient) -> String {
        if device.connectionNeedsUnlock { return L("Unlock connection") }
        if device.homeUnreachable || device.health == nil { return L("Нет связи · попробуем снова") }
        return L("На связи · сотрудников: \(device.profiles.count)")
    }
}

private struct GeneralPane: View {
    @Binding var selectedID: String
    let selected: HomeClient
    #if os(macOS)
    @AppStorage("openstrudel.showMenuBar") private var showMenuBar = true
    #endif
    @State private var relaunch = false

    var body: some View {
        Section {
            Picker(L("Language"), selection: LanguageChoice.binding(relaunch: $relaunch)) {
                ForEach(AppLanguage.allCases) { Text($0.title).tag($0) }
            }
            .accessibilityIdentifier("interfaceLanguage")
            .modifier(LanguageChoice.RelaunchAlert(isPresented: $relaunch))
            #if os(macOS)
            Toggle(L("Показывать в строке меню"), isOn: $showMenuBar).settingsSwitch()
            #endif
        }
        DevicePickerSection(title: L("Сотрудники на устройстве"), selection: $selectedID)
        Section(L("Модель и скорость")) {
            ModelSettingsView().environmentObject(selected)
        }.id("models-" + selected.id)
        ApprovalSettingsView().environmentObject(selected).id("approvals-" + selected.id)
        DictationSection()
        #if os(macOS)
        UpdatesSection()
        HostingStoreSettings()
        #endif
        Section {
            InkLink(title: L("Помощь"), destination: URL(string: "https://waiwai.is/openstrudel#help")!)
            InkLink(title: L("Конфиденциальность"), destination: URL(string: "https://waiwai.is/openstrudel/privacy")!)
        }
        #if os(macOS)
        Section {
            LocalDataResetButton()
        } footer: {
            Text(L("Удалить местных сотрудников, переписку и настройки и начать заново."))
        }
        #endif
    }
}

private struct DictationSection: View {
    @ObservedObject private var assets = DictationAssets.shared

    var body: some View {
        Section {
            switch assets.state {
            case .checking:
                LabeledContent(L("Checking the local model…")) { ProgressView().controlSize(.small) }
            case .ready:
                Label {
                    Text(L("Ready for offline dictation"))
                } icon: {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(AppTheme.accentText)
                }
                .accessibilityIdentifier("dictationReady")
            case .downloading:
                if let progress = assets.progress {
                    ProgressView(value: progress) {
                        Text(progress < 1 ? L("Downloading the model…") : L("Checking the download…"))
                    } currentValueLabel: {
                        Text(progress, format: .percent.precision(.fractionLength(0))).monospacedDigit()
                    }
                } else {
                    ProgressView(L("Preparing the download…"))
                }
                Button(L("Cancel download")) { assets.cancel() }
                    .accessibilityIdentifier("cancelDictationDownload")
            case .available, .failed:
                if let error = assets.error { Text(L10n.serviceText(error)).foregroundStyle(AppTheme.warning) }
                LabeledContent {
                    Button(L("Download model")) { assets.download() }
                        .accessibilityIdentifier("downloadDictationModel")
                } label: {
                    Text(L("Download Parakeet once (740 MB). After that, dictation works offline."))
                }
            }
        } header: {
            Text(L("Dictation"))
        } footer: {
            Text(L("Speak naturally. Your language is recognized automatically, on this device.") + " "
                 + L("25 languages, including English, Russian, French and Spanish. Hebrew is not supported."))
        }
        .task { await assets.check() }
    }
}

#if os(macOS)
private struct UpdatesSection: View {
    @ObservedObject private var updater = AppUpdater.shared
    private var version: String {
        let info = Bundle.main.infoDictionary
        return L("Версия \(info?["CFBundleShortVersionString"] as? String ?? "") (\(info?["CFBundleVersion"] as? String ?? ""))")
    }

    var body: some View {
        Section {
            LabeledContent("OpenStrudel") { Text(version).monospacedDigit().foregroundStyle(AppTheme.secondaryText) }
            Toggle(isOn: Binding(get: { updater.automaticChecksEnabled }, set: { updater.automaticChecksEnabled = $0 })) {
                Text(L("Проверять обновления автоматически"))
                Text(L("Сообщим о новой версии. Установка начнётся только после вашего подтверждения."))
            }
            .settingsSwitch()
            if let failure = updater.startupFailure {
                Text(L10n.serviceText(failure)).foregroundStyle(AppTheme.warning)
            }
            Button(L("Проверить обновления…"), action: updater.checkForUpdates)
                .disabled(!updater.canCheckForUpdates)
                .accessibilityIdentifier("checkForUpdates")
        }
    }
}
#endif

struct AddDeviceConfirmation: View {
    @EnvironmentObject private var library: DeviceLibrary
    @Environment(\.dismiss) private var dismiss
    let pairing: MacPairing
    @State private var candidate: HomeClient?
    @State private var busy = false
    @State private var error: String?
    @State private var connected = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Image(systemName: connected ? "checkmark.circle.fill" : "desktopcomputer")
                    .font(.system(size: 48)).foregroundStyle(AppTheme.secondaryText)
                    .padding(.bottom, 4)
                    .accessibilityHidden(true)
                Text(connected ? L("Устройство подключено") : L("Подключить «\(pairing.name)»?"))
                    .font(AppTypography.title)
                Text(connected ? (candidate?.homeUnreachable == true ? L("Подключение сохранено. Ждём ответа устройства — сотрудники появятся, когда оно выйдет на связь.") : L("Сотрудники этого устройства теперь доступны в списке чатов.")) : L("Вы сможете общаться с его сотрудниками и создавать новых. Они продолжат работать на «\(pairing.name)»."))
                    .foregroundStyle(AppTheme.secondaryText)
                if busy { ProgressView(L("Проверяем подключение…")).controlSize(.small) }
                if let error {
                    Text(L10n.serviceText(error)).foregroundStyle(AppTheme.warning).accessibilityIdentifier("pairingError")
                }
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(24)
            #if os(macOS)
            .frame(width: 440)
            #else
            .frame(maxWidth: 440)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(connected ? L("Готово") : L("Отмена")) { dismiss() }.disabled(busy)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(connected ? L("Открыть сотрудников") : L("Подключить")) {
                        if connected { if let candidate { library.select(candidate) }; dismiss(); return }
                        busy = true; error = nil
                        let target = candidate ?? library.connection(for: pairing); candidate = target
                        Task {
                            if await target.connectToMac(pairing) { library.add(target, select: false); connected = true }
                            else { error = target.pairingError }
                            busy = false
                        }
                    }
                    .disabled(busy)
                    .accessibilityIdentifier(connected ? "openDeviceEmployees" : "confirmMacPairing")
                }
            }
        }
        .interactiveDismissDisabled(busy)
        .presentationSizing(.fitted)
    }
}

/// Every account on the selected device, its limits and credits. Emits Form sections.
struct DeviceAccountsView: View {
    @EnvironmentObject private var client: HomeClient
    @Environment(\.openURL) private var openURL
    @State private var deviceID = ""
    @State private var loadedDeviceID: String?
    @State private var accounts: [ManagedCodexAccount] = []
    @State private var loading = true
    @State private var refreshing = false
    @State private var busy = false
    @State private var error: String?
    @State private var canManage = false
    @State private var login: OpenAILogin?
    @State private var loginAccount = ""
    @State private var logout: ManagedCodexAccount?
    @State private var copiedCode = false
    @State private var renaming: ManagedCodexAccount?
    @State private var accountName = ""
    @State private var notice: String?
    @State private var requestID = UUID()
    private var query: String { deviceID.isEmpty ? "" : "?deviceId=" + deviceID }
    private var deviceName: String { deviceID == client.health?.nodeId ? client.displayName : client.devices.first(where: { $0.id == deviceID })?.name ?? client.displayName }
    private func path(_ id: String, _ action: String) -> String { "/v1/accounts/" + id + "/" + action + query }

    var body: some View {
        Group {
            Section {
                if client.devices.count > 1 {
                    Picker(L("Устройство сотрудника"), selection: $deviceID) {
                        ForEach(client.devices) { Text($0.name).tag($0.id) }
                    }.disabled(login != nil || busy)
                }
                if loading && accounts.isEmpty {
                    LabeledContent(L("Загружаем аккаунты и лимиты…")) { ProgressView().controlSize(.small) }
                }
                if let error { Text(L10n.serviceText(error)).foregroundStyle(AppTheme.warning) }
                if let first = accounts.first { accountRows(first, index: 0) }
            } header: {
                Text(L("ChatGPT on \(deviceName)"))
            } footer: {
                if accounts.count > 1 { Text(L("По умолчанию для новых поручений")) }
            }
            ForEach(Array(accounts.enumerated()).dropFirst(), id: \.element.id) { index, account in
                Section { accountRows(account, index: index) }
            }
            if let login {
                Section {
                    if let code = login.userCode {
                        HStack {
                            Text(code).font(AppTypography.title.monospaced()).textSelection(.enabled)
                                .accessibilityIdentifier("openAIDeviceCode")
                            Spacer()
                            Button(copiedCode ? L("Код скопирован") : L("Скопировать код")) { copy(code) }
                                .accessibilityIdentifier("copyOpenAICode")
                        }
                    }
                    if let url = login.url {
                        InkLink(title: L("Открыть OpenAI"), destination: url)
                    }
                    Button(L("Отменить вход")) { perform {
                        let _: OpenAILoginStatus = try await client.management(path(loginAccount, "login/" + login.loginId), method: "DELETE")
                        self.login = nil
                    } }.accessibilityIdentifier("cancelOpenAILogin")
                } header: {
                    Text(L("Завершите вход на сайте OpenAI"))
                } footer: {
                    if login.userCode != nil { Text(L("Введите этот код на сайте OpenAI")) }
                }
            }
            Section {
                if let notice { Text(notice).foregroundStyle(AppTheme.secondaryText) }
                if login == nil && canManage && !accounts.isEmpty {
                    Button(L("Добавить аккаунт OpenAI")) { perform {
                        notice = nil
                        struct Added: Decodable { let id: String }
                        let result: Added = try await client.management("/v1/accounts" + query, method: "POST", payload: ["name": "OpenAI"])
                        try await signIn(result.id)
                    } }.disabled(busy)
                }
                HStack {
                    Button(L("Обновить остатки")) {
                        refreshing = true
                        Task { await refresh(force: true); refreshing = false }
                    }.disabled(loading)
                    Spacer()
                    if refreshing { ProgressView().controlSize(.small).accessibilityLabel(L("Обновляем остатки…")) }
                }
            } footer: {
                if let checked = accounts.compactMap({ UsageSummary.checked($0.usage) }).max() {
                    Text(UsageSummary.updated(checked) + "\n" + L("Лимиты относятся к подписке. Кредиты — отдельный баланс аккаунта."))
                } else {
                    Text(L("Лимиты относятся к подписке. Кредиты — отдельный баланс аккаунта."))
                }
            }
        }
        .task(id: deviceID) {
            if deviceID.isEmpty, let localDeviceID = client.health?.nodeId {
                deviceID = localDeviceID
            } else {
                while !Task.isCancelled {
                    if login == nil && !busy { await refresh() }
                    do { try await Task.sleep(for: .seconds(15)) } catch { break }
                }
            }
        }
        .task(id: login?.loginId) {
            copiedCode = false
            guard let current = login else { return }
            while !Task.isCancelled && login?.loginId == current.loginId {
                do {
                    try await Task.sleep(for: .seconds(2))
                    let status: OpenAILoginStatus = try await client.management(path(loginAccount, "login/" + current.loginId))
                    if status.status == "completed" {
                        // Clearing login cancels this .task. Finish both refreshes
                        // before changing its identity so their result is applied.
                        await refresh(force: true)
                        await client.refreshOpenAIAccount(force: true)
                        notice = status.alreadyConnected == true ? L("Already connected. Your account has been refreshed.") : L("Account connected.")
                        login = nil
                        break
                    }
                    if ["failed", "canceled"].contains(status.status) { login = nil; error = L("Вход не завершён. Попробуйте ещё раз.") }
                } catch is CancellationError { break }
                catch { self.error = L("Не удалось проверить вход. Повторим, когда появится связь.") }
            }
        }
        .confirmationDialog(L("Выйти из аккаунта OpenAI?"), isPresented: Binding(get: { logout != nil }, set: { if !$0 { logout = nil } })) {
            if let account = logout { Button(L("Выйти"), role: .destructive) { perform {
                let _: HomeActionResult = try await client.management(path(account.id, "logout"), method: "POST")
                logout = nil; await refresh()
            } } }
        } message: { Text(L("Сотрудники и переписка сохранятся. Для новых поручений понадобится вход.")) }
        .alert(L("Rename account"), isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField(L("Название аккаунта"), text: $accountName)
                .autocorrectionDisabled()
            Button(L("Отмена"), role: .cancel) { renaming = nil }
            Button(L("Сохранить")) {
                guard let account = renaming else { return }
                let name = accountName.trimmingCharacters(in: .whitespacesAndNewlines)
                perform {
                    let _: HomeActionResult = try await client.management("/v1/accounts/" + account.id + query, method: "POST", payload: ["name": name])
                    renaming = nil
                    await refresh()
                }
            }.disabled(accountName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || accountName.count > 80)
        } message: { Text(L("Choose a name you recognise. Your OpenAI account stays the same.")) }
    }

    @ViewBuilder private func accountRows(_ account: ManagedCodexAccount, index: Int) -> some View {
        LabeledContent {
            if canManage { accountMenu(account, index: index) }
        } label: {
            Text(account.title).textSelection(.enabled)
            let detail = accountDetail(account)
            if !detail.isEmpty { Text(detail).textSelection(.enabled) }
        }
        if account.account.connected {
            UsageSummary(usage: account.usage)
        } else if canManage && !account.account.isUnavailable {
            Button(L("Войти в OpenAI")) { perform { try await signIn(account.id) } }
                .disabled(login != nil || busy)
                .accessibilityIdentifier("signInOpenAI")
        }
    }

    private func accountDetail(_ account: ManagedCodexAccount) -> String {
        var parts = [account.emailDetail].compactMap { $0 }
        if account.account.connected {
            parts += [account.account.planLabel, account.account.categoryLabel].compactMap { $0 }
        } else if account.account.isUnavailable {
            parts.append(L("Не удалось проверить аккаунт"))
        } else if !canManage {
            parts.append(L("Нужен вход в OpenAI"))
        }
        if accounts.filter({ $0.title == account.title && $0.account.planType == account.account.planType }).count > 1 {
            parts.append(L("Connection \(String(account.id.suffix(6)))"))
        }
        return parts.joined(separator: " · ")
    }

    private func accountMenu(_ account: ManagedCodexAccount, index: Int) -> some View {
        Menu {
            Button(L("Rename account…")) { accountName = account.title; renaming = account }
            if index > 0 && account.account.connected {
                Button(L("Использовать по умолчанию")) { perform {
                    let _: HomeActionResult = try await client.management(path(account.id, "priority"), method: "POST", payload: [:])
                    await refresh()
                } }
            }
            if account.account.connected {
                Button(L("Выйти из аккаунта…"), role: .destructive) { logout = account }
                    .disabled(account.activeRuns > 0)
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .menuStyle(.button).buttonStyle(.borderless).menuIndicator(.hidden).fixedSize()
        .accessibilityLabel(L("Действия с аккаунтом"))
        .accessibilityIdentifier("accountActions-" + account.id)
    }

    private func copy(_ code: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(code, forType: .string)
        #else
        UIPasteboard.general.string = code
        #endif
        copiedCode = true
    }
    private func refresh(force: Bool = false) async {
        let selected = deviceID, token = UUID()
        requestID = token
        if loadedDeviceID != selected { accounts = []; canManage = false; loadedDeviceID = selected }
        loading = true; error = nil
        defer { if selected == deviceID && requestID == token { loading = false } }
        do {
            let result: ManagedCodexAccounts = try await client.management("/v1/accounts" + query + (query.isEmpty ? "?" : "&") + "refresh=" + String(force))
            guard selected == deviceID, requestID == token, !Task.isCancelled else { return }
            accounts = result.accounts; canManage = result.canManage
        } catch { if !Task.isCancelled && selected == deviceID && requestID == token { self.error = UserFacingError.text(error.localizedDescription) } }
    }
    private func signIn(_ id: String) async throws {
        loginAccount = id
        login = try await client.management(path(id, "login"), method: "POST")
        if let url = login?.url { openURL(url) }
    }
    private func perform(_ work: @escaping () async throws -> Void) {
        busy = true; error = nil
        Task { defer { busy = false }; do { try await work() } catch { self.error = error.localizedDescription } }
    }
}

/// An account's limits and credits as rows: in a Form each is a row, in the menu-bar popover they stack.
struct UsageSummary: View {
    let usage: ManagedCodexAccount.Usage

    var body: some View {
        if usage.unavailable == true {
            Label(L("Не удалось получить остатки. Попробуйте обновить."), systemImage: "exclamationmark.circle")
                .foregroundStyle(AppTheme.secondaryText)
        } else if usage.windows.isEmpty {
            Text(L("OpenAI не передал лимиты подписки.")).foregroundStyle(AppTheme.secondaryText)
        }
        ForEach(usage.windows) { UsageMeter(window: $0) }
        LabeledContent(L("Кредиты")) {
            Text(credits).monospacedDigit().foregroundStyle(AppTheme.secondaryText)
        }
        if let resets = usage.resetCredits {
            LabeledContent {
                Text(String(resets.availableCount)).monospacedDigit().foregroundStyle(AppTheme.secondaryText)
            } label: {
                Text(L("Extra limit resets"))
                if let expires = resets.nextExpiresAt {
                    Text(L("Next expiry: \(Date(timeIntervalSince1970: expires).formatted(.dateTime.day().month(.abbreviated).hour().minute().locale(L10n.locale)))"))
                        .font(AppTypography.meta).monospacedDigit().foregroundStyle(AppTheme.secondaryText)
                }
            }
        }
    }

    /// When OpenAI last reported these numbers.
    static func checked(_ usage: ManagedCodexAccount.Usage) -> Date? {
        ISO8601DateFormatter().date(from: usage.checkedAt) ?? DateFormatter.usageTimestamp.date(from: usage.checkedAt)
    }
    static func updated(_ date: Date) -> String {
        L("Updated \(date.formatted(.dateTime.hour().minute().locale(L10n.locale)))")
    }

    private var credits: String {
        usage.credits.map { $0.unlimited ? L("Без ограничений") : $0.balance ?? ($0.hasCredits ? L("Доступны · баланс не передан") : L("Нет кредитов")) } ?? L("Баланс не передан")
    }
}

/// One limit window: its name and what is left above a thin bar.
private struct UsageMeter: View {
    let window: ManagedCodexAccount.Usage.Window

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LabeledContent(window.displayName) {
                Text(caption).monospacedDigit().foregroundStyle(AppTheme.secondaryText)
            }
            if let remaining = window.remainingPercent {
                UsageBar(fraction: max(0, min(100, remaining)) / 100)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(window.displayName)
        .accessibilityValue(caption)
    }

    private var caption: String {
        guard let remaining = window.remainingPercent else { return L("Нет данных") }
        let percent = Int(remaining.rounded())
        guard let reset = window.resetsAt else { return L("\(percent)% осталось") }
        return L("\(percent)% осталось · сброс \(Self.resetTime(Date(timeIntervalSince1970: reset)))")
    }

    /// Today shows the time, this week the weekday and time, later the date.
    private static func resetTime(_ date: Date) -> String {
        let style: Date.FormatStyle = Calendar.current.isDateInToday(date) ? .dateTime.hour().minute()
            : date.timeIntervalSinceNow < 6 * 86_400 ? .dateTime.weekday(.abbreviated).hour().minute()
            : .dateTime.day().month(.abbreviated)
        return date.formatted(style.locale(L10n.locale))
    }
}

/// A 4-pt meter: accent for what is left on a hairline track.
private struct UsageBar: View {
    let fraction: Double

    var body: some View {
        RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(AppTheme.separator)
            .frame(height: 4)
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(AppTheme.accent)
                        .frame(width: proxy.size.width * fraction)
                }
            }
            .accessibilityHidden(true)
    }
}

private extension DateFormatter {
    static var usageTimestamp: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX"
        return formatter
    }
}
