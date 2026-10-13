import SwiftUI

struct BotDetailsView: View {
    @EnvironmentObject private var client: HomeClient
    @Environment(\.dismiss) private var dismiss
    let profile: EmployeeProfile
    @State private var name: String
    @State private var instructions: String
    @State private var appearance: AgentAppearance
    @State private var showConnections = false
    @State private var showTelegram = false
    @State private var isSaving = false
    @State private var confirmDiscard = false
    @State private var saveError: String?
    private var hasChanges: Bool { name != profile.name || instructions != profile.instructions || appearance != profile.resolvedAppearance }

    init(profile: EmployeeProfile) {
        self.profile = profile
        _name = State(initialValue: profile.name)
        _instructions = State(initialValue: profile.instructions)
        _appearance = State(initialValue: profile.resolvedAppearance)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 12) {
                    AgentAvatar(appearance: appearance, size: 72)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(L("Имя")).font(.caption).foregroundStyle(AppTheme.secondaryText)
                        TextField(L("Имя сотрудника"), text: $name).textFieldStyle(.plain).font(.title2.weight(.semibold))
                    }
                }
                Button { showConnections = true } label: {
                    HStack {
                        Label(L("Сервисы и навыки"), systemImage: "link")
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                    }.frame(minHeight: controlTarget).contentShape(Rectangle())
                }.buttonStyle(.plain)
                Button { showTelegram = true } label: {
                    HStack {
                        Label("Telegram", systemImage: "paperplane")
                        Spacer()
                        Text((client.telegram?.chats ?? []).filter { $0.profileId == profile.id }.map(\.title).joined(separator: ", "))
                            .font(.caption).foregroundStyle(AppTheme.secondaryText).lineLimit(1)
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                    }.frame(minHeight: controlTarget).contentShape(Rectangle())
                }.buttonStyle(.plain)
                Divider()
                if client.health?.agentAppearanceVersion == 1 {
                    DisclosureGroup(L("Образ сотрудника")) {
                        AgentAppearancePicker(selection: $appearance).padding(.top, 12)
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text(L("Чем занимается сотрудник")).font(.subheadline.weight(.medium))
                    Text(L("Опишите задачи и правила, которым он должен следовать."))
                        .font(.caption).foregroundStyle(AppTheme.secondaryText)
                    TextEditor(text: $instructions).font(.body).scrollContentBackground(.hidden)
                        .frame(height: 180).padding(10)
                        .background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
                        .accessibilityLabel(L("Описание сотрудника"))
                }
                ModelSettingsView(agentID: profile.id)
                if client.health?.homeProtocol == 1 { AgentAccountPreference(profile: profile) }
                if !client.schedules.isEmpty {
                    Divider()
                    Text(L("Расписание")).font(.subheadline.weight(.medium))
                }
                ForEach(client.schedules.filter(\.enabled)) { schedule in
                    Toggle(isOn: Binding(get: { schedule.enabled }, set: { value in Task { await client.setSchedule(schedule, enabled: value) } })) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(schedule.name).font(.callout.weight(.medium))
                            Text(schedule.timing).font(.caption).foregroundStyle(AppTheme.secondaryText)
                        }
                    }
                }
                if client.schedules.contains(where: { !$0.enabled }) {
                    DisclosureGroup(L("Приостановленные")) {
                        ForEach(client.schedules.filter { !$0.enabled }) { schedule in
                            Toggle(schedule.name, isOn: Binding(get: { schedule.enabled }, set: { value in Task { await client.setSchedule(schedule, enabled: value) } })).font(.callout)
                        }
                    }
                }
                if let failed = client.scheduleRuns.first, let error = failed.error {
                    Text(UserFacingError.text(error)).font(.caption).foregroundStyle(AppTheme.warning)
                }
                if let saveError {
                    Text(L10n.serviceText(saveError)).font(.callout).foregroundStyle(AppTheme.warning)
                        .accessibilityIdentifier("employeeSaveError")
                }
            }
            .padding(24)
            }
            .background(HomeBackground())
            .navigationTitle(L("Сотрудник"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Отмена")) { if hasChanges { confirmDiscard = true } else { dismiss() } }
                        .disabled(isSaving).keyboardShortcut(.cancelAction)
                        .accessibilityIdentifier("cancelEmployeeChanges")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? L("Сохраняем…") : hasChanges ? L("Сохранить") : L("Готово")) {
                        guard hasChanges else { dismiss(); return }
                        isSaving = true
                        saveError = nil
                        Task {
                            let saved = await client.updateProfile(id: profile.id, name: name, instructions: instructions, appearance: appearance != profile.resolvedAppearance ? appearance : nil)
                            isSaving = false
                            if saved { dismiss() }
                            else { saveError = client.errorMessage ?? L("Не удалось сохранить изменения. Попробуйте ещё раз."); client.errorMessage = nil }
                        }
                    }.disabled(isSaving || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .keyboardShortcut(.defaultAction).accessibilityIdentifier("saveEmployeeChanges")
                }
            }
            .interactiveDismissDisabled(hasChanges || isSaving)
            .alert(L("Не сохранять изменения?"), isPresented: $confirmDiscard) {
                Button(L("Не сохранять"), role: .destructive) { dismiss() }
                Button(L("Продолжить редактирование"), role: .cancel) {}
            } message: { Text(L("Имя, образ и описание сотрудника останутся прежними.")) }
            .navigationDestination(isPresented: $showConnections) { ConnectionsView(embedded: true) }
            .navigationDestination(isPresented: $showTelegram) { TelegramChatsView(profile: profile, embedded: true) }
            .task { await client.loadChatSettings() }
        }
        #if os(macOS)
        .frame(width: 540, height: 640)
        #endif
    }
}

struct TelegramChatsView: View {
    @EnvironmentObject private var client: HomeClient
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var textSize
    var profile: EmployeeProfile? = nil
    var embedded = false
    @State private var busyGroup: String?
    @State private var error: String?
    @State private var showAccounts = false
    @State private var showConnections = false
    private var groups: [TelegramChat] { (client.telegram?.chats ?? []).filter(\.isGroup) }

    var body: some View {
        Group {
            if embedded { content }
            else { NavigationStack { content } }
        }
        #if os(macOS)
        .frame(minWidth: embedded ? nil : 520, minHeight: embedded ? nil : 520)
        #endif
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if let group = client.activeTelegramGroup {
                    VStack(alignment: .leading, spacing: 16) {
                        Label(L("Группа в Telegram"), systemImage: "person.2").foregroundStyle(AppTheme.secondaryText)
                        Text(groupDescription(group)).font(.headline)
                        if group.enabled != false {
                            Text(group.replies == "mentions" ? L("Отвечает на @упоминание и ответы боту") : L("Отвечает по правилам сотрудника"))
                                .font(.callout).foregroundStyle(AppTheme.secondaryText)
                        }
                        Divider()
                        Button { showConnections = true } label: { Label(L("Сервисы и навыки"), systemImage: "link") }
                            .accessibilityIdentifier("telegramGroupServices")
                        groupAction(group)
                    }
                } else { TelegramSetupView() }
                if client.telegram?.configured == true && client.openAIAccount?.connected == false {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(client.openAIAccount?.isUnavailable == true
                             ? L("Не удалось проверить OpenAI. Подключение Telegram сохранено.")
                             : L("Войдите в OpenAI, чтобы помощник мог отвечать."))
                            .font(.callout)
                        Button(L("Аккаунты OpenAI")) { showAccounts = true }
                            .accessibilityIdentifier("telegramOpenAIAccounts")
                    }.settingsCard()
                }
                if client.activeTelegramGroup == nil && !groups.isEmpty {
                    Divider()
                    VStack(alignment: .leading, spacing: 16) {
                        Text(L("Группы")).font(.headline)
                        ForEach(groups) { chat in
                            VStack(alignment: .leading, spacing: 10) {
                              HStack(alignment: .top, spacing: 12) {
                                Image(systemName: "person.2").foregroundStyle(AppTheme.accent).padding(.top, 3)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(chat.title).font(.body.weight(.medium))
                                    Text(groupDescription(chat)).font(.callout).foregroundStyle(AppTheme.secondaryText)
                                    if chat.enabled != false {
                                        Text(chat.replies == "mentions" ? L("Отвечает на @упоминание и ответы боту") : L("Отвечает по правилам сотрудника"))
                                            .font(.caption).foregroundStyle(AppTheme.secondaryText)
                                    }
                                }
                                Spacer(minLength: 8)
                                if !textSize.isAccessibilitySize { groupAction(chat) }
                              }
                              if textSize.isAccessibilitySize { groupAction(chat) }
                            }
                        }
                    }
                }
                if let error { Text(L10n.serviceText(error)).foregroundStyle(AppTheme.destructive).font(.callout) }
            }.padding(24)
        }
        .background(HomeBackground()).navigationTitle(client.activeTelegramGroup?.title ?? "Telegram")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                if !embedded { Button(L("Готово")) { dismiss() } }
            }
        }
        .navigationDestination(isPresented: $showAccounts) {
            ScrollView { DeviceAccountsView().padding(24) }.navigationTitle(L("Аккаунты OpenAI"))
        }
        .navigationDestination(isPresented: $showConnections) { ConnectionsView(embedded: true) }
    }

    @ViewBuilder private func groupAction(_ chat: TelegramChat) -> some View {
        if busyGroup == chat.chatId { ProgressView().controlSize(.small) }
        else {
            Button(chat.enabled == false ? L("Продолжить") : L("Приостановить")) { toggle(chat) }
                .disabled(busyGroup != nil)
                .accessibilityLabel((chat.enabled == false ? L("Продолжить в группе «") : L("Приостановить в группе «")) + chat.title + "»")
                .accessibilityIdentifier("toggleTelegramGroup-" + chat.chatId)
        }
    }

    private func groupDescription(_ chat: TelegramChat) -> String {
        if chat.enabled == false { return L("На паузе · переписка сохранена") }
        if let name = client.profiles.first(where: { $0.id == chat.profileId })?.name { return L("Отвечает «\(name)»") }
        return L("Помощник сам подбирает сотрудника по задаче")
    }

    private func toggle(_ chat: TelegramChat) {
        busyGroup = chat.chatId; error = nil
        Task {
            defer { busyGroup = nil }
            do { try await client.setTelegramGroupEnabled(chat.chatId, enabled: chat.enabled == false) }
            catch { self.error = UserFacingError.text(error.localizedDescription) }
        }
    }
}

struct ConnectionsView: View {
    @EnvironmentObject private var client: HomeClient
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var textSize
    var embedded = false
    @State private var query = ""
    @State private var loading = true
    @State private var error: String?
    @State private var connecting: String?
    @State private var waiting: ServiceConnection?
    @State private var authorizationURL: URL?
    @State private var notice: String?
    @State private var availableConnections: [ServiceConnection] = []
    @State private var extensions: [EmployeeExtension] = []
    @State private var contexts: [ExtensionContext] = []
    @State private var scopeID = ""
    @State private var showAdd = false
    @State private var extensionNotice: String?
    @State private var changing = false
    @State private var pendingRemoval: EmployeeExtension?
    @State private var pendingMCPRemoval: ServiceConnection?
    @State private var refreshID = UUID()
    private var scope: ExtensionContext? { contexts.first { $0.id == scopeID } }
    private var results: [ServiceConnection] {
        availableConnections.filter { $0.id != "mcp:cua_repl" && !$0.isAvailableToAdd && (query.isEmpty || $0.name.localizedCaseInsensitiveContains(query)) }
            .sorted { $0.connected != $1.connected ? $0.connected : $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    var body: some View {
        Group {
            if embedded { content }
            else { NavigationStack { content } }
        }
        #if os(macOS)
        .frame(minWidth: embedded ? nil : 560, minHeight: embedded ? nil : 570)
        #endif
    }

    private var servicesList: some View {
            ServiceList {
                connectionHeader
                if availableConnections.filter({ $0.id != "mcp:cua_repl" && !$0.isAvailableToAdd }).count > 6 {
                    TextField(L("Найти подключение"), text: $query)
                        .textFieldStyle(.roundedBorder).accessibilityLabel(L("Найти подключение"))
                }
                if !scopeID.isEmpty {
                    Section { ComputerUseSettingsView(conversationID: scopeID, isGroup: scope?.isGroup == true).id(scopeID) }
                }
                extensionRows
                connectionRows

            }
            .scrollContentBackground(.hidden)
            .background(HomeBackground()).navigationTitle(L("Сервисы и навыки"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if !embedded { Button(L("Готово")) { dismiss() } }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button { Task { await refresh() } } label: { Image(systemName: "arrow.clockwise") }
                        .accessibilityLabel(L("Обновить сервисы")).disabled(loading)
                }
            }

    }

    private var content: some View {
        servicesList
        .navigationDestination(isPresented: $showAdd) {
            if let scope { ConnectionCatalogView(scope: scope, isPresented: $showAdd) }
        }
        .onChange(of: showAdd) { wasPresented, isPresented in
            if wasPresented && !isPresented { Task { await refresh() } }
        }
        .confirmationDialog(L("Удалить расширение?"), isPresented: Binding(get: { pendingRemoval != nil || pendingMCPRemoval != nil }, set: { if !$0 { pendingRemoval = nil; pendingMCPRemoval = nil } }), titleVisibility: .visible) {
            if let item = pendingRemoval { Button(L("Удалить «\(item.name)»"), role: .destructive) { updateExtension(item); pendingRemoval = nil } }
            if let item = pendingMCPRemoval { Button(L("Удалить «\(item.name)»"), role: .destructive) { removeMCP(item); pendingMCPRemoval = nil } }
            Button(L("Отмена"), role: .cancel) { pendingRemoval = nil; pendingMCPRemoval = nil }
        } message: { Text(L("Переписка и файлы сотрудника сохранятся.")) }
        .task { await loadContexts() }
        .task(id: scopeID) { await loadScope() }
        .task(id: waiting?.id) { await pollAuthorization() }
        .onChange(of: scenePhase) { old, phase in
            if old != .active && phase == .active && !loading { Task { await refresh() } }
        }
    }

    private func loadContexts() async {
        do { contexts = try await client.extensionContexts(); scopeID = client.conversationID ?? "" }
        catch { self.error = L("Не удалось определить чат. Вернитесь к переписке и откройте сервисы снова."); loading = false }
    }

    private func loadScope() async {
        guard !scopeID.isEmpty else { return }
        availableConnections = []; extensions = []; waiting = nil; authorizationURL = nil; notice = nil
        await refresh(force: false)
    }

    private func pollAuthorization() async {
        guard waiting != nil else { return }
        for _ in 0..<30 {
            do { try await Task.sleep(for: .seconds(2)) } catch { return }
            if !loading { await refresh() }
            if waiting == nil { return }
        }
    }

    @ViewBuilder private var extensionRows: some View {
                if !extensions.isEmpty {
                    Section(L("Навыки и плагины")) {
                        ForEach(extensions.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }) { item in
                            VStack(alignment: .leading, spacing: 8) {
                                if item.removable && (client.canManageConnections || client.canManageOpenAI) {
                                    Toggle(item.name, isOn: Binding(get: { item.enabled }, set: { enabled in
                                        updateExtension(item, enabled: enabled)
                                    })).disabled(changing || loading)
                                } else { Label(item.name, systemImage: item.enabled ? "checkmark.circle" : "pause.circle") }
                                Text(item.description).font(.caption).foregroundStyle(AppTheme.secondaryText).lineLimit(3)
                                if item.removable && (client.canManageConnections || client.canManageOpenAI) {
                                    Button(L("Удалить…"), role: .destructive) { pendingRemoval = item }.buttonStyle(.borderless).font(.caption).disabled(changing)
                                }
                            }.padding(.vertical, 6)
                                .accessibilityElement(children: .contain)
                        }
                    }
                }

    }

    @ViewBuilder private var connectionRows: some View {
                ForEach(results) { connection in
                    serviceRow(connection)
                    .contextMenu {
                        if connection.removable == true && (client.canManageConnections || client.canManageOpenAI) {
                            Button(L("Удалить подключение…"), role: .destructive) { pendingMCPRemoval = connection }
                        }
                    }
                }
                if results.isEmpty && !query.isEmpty { SearchEmptyState(query: query) { query = "" } }
                else if results.isEmpty && !loading && error == nil {
                    Text(extensions.isEmpty && !availableConnections.contains(where: { $0.id == "mcp:cua_repl" }) ? L("Пока без подключений. Нажмите «Добавить», чтобы сотрудник мог работать с вашими сервисами.") : L("Другие сервисы можно подключить через «Добавить»."))
                        .foregroundStyle(AppTheme.secondaryText)
                }

    }

    private var connectionHeader: some View {
                VStack(alignment: .leading, spacing: 10) {
                    Text(L("Для «\(client.activeAgentName)» · \(client.executionDeviceName)"))
                        .font(.callout).foregroundStyle(AppTheme.secondaryText)
                    Label(scope?.isGroup == true ? "Telegram · " + (scope?.title ?? L("Группа")) : L("В приложении"), systemImage: scope?.isGroup == true ? "paperplane" : "bubble.left")
                        .font(.headline)
                    if scope?.isGroup == true { Text(L("Подключения для этой группы.")).font(.caption).foregroundStyle(AppTheme.secondaryText) }
                    if let shared = scope?.sharedNotice { Text(shared).font(.callout).foregroundStyle(AppTheme.secondaryText) }
                    if loading { HStack(spacing: 8) { ProgressView().controlSize(.small); Text(L("Проверяем доступ к сервисам…")).font(.callout) } }
                    if let waiting {
                        Text(L("Завершите подключение \(waiting.name) в браузере. Здесь появится подтверждение."))
                            .font(.callout).fixedSize(horizontal: false, vertical: true)
                        ViewThatFits(in: .horizontal) {
                            HStack { authorizationActions }.fixedSize(horizontal: true, vertical: false)
                            VStack(alignment: .leading, spacing: 12) { authorizationActions }
                        }
                    }
                    if let notice { Label(notice, systemImage: "checkmark.circle").font(.callout) }
                    if let error {
                        Text(UserFacingError.text(error)).font(.callout).foregroundStyle(AppTheme.warning)
                        Button(L("Повторить")) { Task { await refresh() } }.disabled(loading)
                    }
                    if let extensionNotice, !extensionNotice.hasPrefix(L("Каталог OpenAI")) { Text(extensionNotice).font(.caption).foregroundStyle(AppTheme.secondaryText) }
                    if client.canManageConnections || client.canManageOpenAI {
                        Button { query = ""; showAdd = true } label: { Label(L("Добавить…"), systemImage: "plus") }
                            .buttonStyle(.bordered).disabled(scope == nil || changing).padding(.top, 8).accessibilityIdentifier("addEmployeeExtension")
                    }
                }
                .padding(.vertical, 8)
                .accessibilityElement(children: .contain)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
    }

    @ViewBuilder private var authorizationActions: some View {
        if let authorizationURL { Link(L("Открыть ещё раз"), destination: authorizationURL) }
        Button(L("Проверить подключение")) { Task { await refresh() } }.disabled(loading)
    }

    private func serviceRow(_ connection: ServiceConnection) -> some View {
        Group {
            if textSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 12) {
                    connectionDetails(connection)
                    connectionAction(connection).adaptiveActionStyle(.bordered)
                }
            } else {
                HStack(spacing: 12) {
                    Image(systemName: connection.icon).foregroundStyle(AppTheme.secondaryText).frame(width: 26)
                    connectionDetails(connection)
                    connectionAction(connection).fixedSize()
                }
            }
        }.padding(.vertical, 8)
            .accessibilityElement(children: .contain)
    }

    private func connectionDetails(_ connection: ServiceConnection) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(connection.name)
            if let detail = connection.detail { Text(detail).font(.caption).foregroundStyle(AppTheme.secondaryText) }
            if let count = connection.toolCount, connection.connected { Text(L("Инструментов: \(count)")).font(.caption).foregroundStyle(AppTheme.secondaryText) }
            if connection.status == "unavailable" { Text(L("Нет связи с сервисом")).font(.caption).foregroundStyle(AppTheme.secondaryText) }
            if connection.status == "unknown" { Text(L("Не удалось проверить подключение")).font(.caption).foregroundStyle(AppTheme.secondaryText) }
            if connection.removable == true && (client.canManageConnections || client.canManageOpenAI) {
                Button(L("Удалить…"), role: .destructive) { pendingMCPRemoval = connection }.buttonStyle(.borderless).font(.caption).disabled(changing)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private func connectionAction(_ connection: ServiceConnection) -> some View {
        if connection.connected {
            Label(L("Подключён"), systemImage: "checkmark").font(.caption).foregroundStyle(AppTheme.secondaryText)
        } else {
            Button {
                Task { await connect(connection) }
            } label: {
                AdaptiveActionLabel(title: connecting == connection.id ? L("Проверяем…") : waiting?.id == connection.id ? L("Ожидаем входа") : connection.actionTitle)
            }.adaptiveActionStyle(.bordered).disabled(connecting != nil || waiting?.id == connection.id)
                .accessibilityLabel("\(connection.actionTitle) \(connection.name)")
                .accessibilityIdentifier("connect-service-" + connection.id)
        }
    }

    private func connect(_ connection: ServiceConnection) async {
        connecting = connection.id; error = nil; notice = nil
        defer { connecting = nil }
        do {
            if let url = try await client.connectService(connection.id, for: scopeID) {
                waiting = connection; authorizationURL = url
                openURL(url) { @Sendable accepted in
                    Task { @MainActor in
                        if !accepted { error = L("Не удалось открыть браузер. Используйте ссылку «Открыть ещё раз».") }
                    }
                }
            } else {
                await refresh()
                if availableConnections.contains(where: { $0.id == connection.id && $0.connected }) { notice = L("Connected: \(connection.name)") }
                else { error = L("Сервис ещё не подтвердил подключение. Нажмите «Обновить сервисы».") }
            }
        } catch is CancellationError { }
        catch { self.error = error.localizedDescription }
    }
    private func refresh(force: Bool = true) async {
        guard !scopeID.isEmpty else { return }
        let requestID = UUID(), scope = scopeID
        refreshID = requestID
        loading = true; error = nil
        defer { if refreshID == requestID { loading = false } }
        do {
            async let services = client.serviceConnections(for: scope, refresh: force)
            async let installed = try? client.loadExtensions(for: scope)
            let (result, packages) = try await (services, installed)
            guard refreshID == requestID, scope == scopeID else { return }
            availableConnections = result.connections; extensions = packages?.items ?? []
            extensionNotice = packages?.notice ?? result.notice ?? (packages == nil ? L("Не удалось загрузить навыки. Проверьте, что OpenStrudel на устройстве сотрудника обновлён.") : nil)
            if let waiting, availableConnections.contains(where: { $0.id == waiting.id && $0.connected }) {
                notice = L("Connected: \(waiting.name)"); self.waiting = nil; authorizationURL = nil
            }
        } catch is CancellationError { }
        catch { if refreshID == requestID { self.error = error.localizedDescription } }
    }
    private func updateExtension(_ item: EmployeeExtension, enabled: Bool? = nil) {
        changing = true; error = nil
        Task {
            defer { changing = false }
            do { try await client.changeExtension(item.id, enabled: enabled, for: scopeID); await refresh() }
            catch { self.error = error.localizedDescription }
        }
    }
    private func removeMCP(_ item: ServiceConnection) {
        changing = true; error = nil
        Task {
            defer { changing = false }
            do { try await client.removeMCP(item.id, for: scopeID); await refresh() }
            catch { self.error = error.localizedDescription }
        }
    }
}
