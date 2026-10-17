import SwiftUI

struct EmployeePicker: View {
    @EnvironmentObject private var library: DeviceLibrary
    @EnvironmentObject private var client: HomeClient
    @Environment(\.dismiss) private var dismiss
    @Binding var isPresented: Bool

    @State private var query = ""
    @State private var showingSettings = false
    @State private var showingHistory = false
    @State private var movingEmployee: EmployeeMoveRequest?
    @State private var renaming: RenameTarget?
    @State private var addingDevice = false
    @State private var invitation: MacPairing?
    @State private var confirmingInvitation: MacPairing?
    private var searchTerm: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var showsMain: Bool { searchTerm.isEmpty || "OpenStrudel".localizedCaseInsensitiveContains(searchTerm) }

    var body: some View {
        NavigationStack {
            List {
                if searchTerm.isEmpty && library.visibleClients.contains(where: { !$0.usesEmployeeTimeline }) {
                    Button { showingHistory = true } label: {
                        Label(L("Переписки"), systemImage: "clock.arrow.circlepath")
                    }.accessibilityIdentifier("openConversations")
                }
                if !showsMain && !library.visibleClients.contains(where: { source in library.visibleProfiles(on: source).contains { $0.name.localizedCaseInsensitiveContains(searchTerm) || $0.roleText.localizedCaseInsensitiveContains(searchTerm) } || source.telegramGroups.contains { $0.title.localizedCaseInsensitiveContains(searchTerm) } }) {
                    SearchEmptyState(query: query) { query = "" }
                }
                ForEach(library.visibleClients) { source in
                    let people = library.visibleProfiles(on: source).filter { searchTerm.isEmpty || $0.name.localizedCaseInsensitiveContains(searchTerm) || $0.roleText.localizedCaseInsensitiveContains(searchTerm) }
                    if showsMain || !people.isEmpty {
                    Section {
                        if !searchTerm.isEmpty || !library.collapsedDeviceIDs.contains(source.id) {
                        if showsMain {
                            EmployeePickerRow(name: "OpenStrudel", subtitle: source.displayName, selected: source === client && source.selectedProfileID == nil,
                                              appearance: nil, offline: source.isOffline(nil)) {
                                Task { await library.select(source, profile: nil); dismiss() }
                            }
                        }
                        ForEach(people) { profile in
                            EmployeePickerRow(name: profile.name, subtitle: profile.previewText.isEmpty ? profile.roleText : profile.previewText, selected: source === client && source.selectedProfileID == profile.id,
                                              appearance: profile.resolvedAppearance, offline: source.isOffline(profile)) {
                                Task { await library.select(source, profile: profile.id); dismiss() }
                            }
                            .accessibilityIdentifier("employee-" + profile.id)
                            .contextMenu {
                                Button(L("Переименовать…"), systemImage: "pencil") { renaming = RenameTarget(client: source, profile: profile) }
                                    .disabled(source.isOffline(profile))
                                Button(L("Скрыть у меня"), systemImage: "eye.slash") { Task { await library.setHidden(true, profile: profile, on: source) } }
                                Button(L("Перенести на другое устройство…"), systemImage: "arrow.right.square") { movingEmployee = EmployeeMoveRequest(source: source, profile: profile) }
                                    .disabled(!source.ownsDevice)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(L("Скрыть"), systemImage: "eye.slash") { Task { await library.setHidden(true, profile: profile, on: source) } }.tint(.gray)
                            }
                        }
                        }
                    } header: {
                        HStack(spacing: 0) {
                        Button {
                            library.setCollapsed(!library.collapsedDeviceIDs.contains(source.id), client: source)
                        } label: {
                            HStack(spacing: 8) {
                                Text(source.displayName)
                                if source.connectionNeedsUnlock { Image(systemName: "lock") }
                                else if source.homeUnreachable { Image(systemName: "wifi.slash") }
                                Spacer(minLength: 0)
                                Image(systemName: !searchTerm.isEmpty || !library.collapsedDeviceIDs.contains(source.id) ? "chevron.down" : "chevron.right")
                                    .font(.caption.weight(.semibold))
                            }
                            .font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, minHeight: controlTarget, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                            .buttonStyle(.plain)
                            .accessibilityLabel(headerLabel(source))
                            .accessibilityValue(library.collapsedDeviceIDs.contains(source.id) && searchTerm.isEmpty ? L("Свёрнуто") : L("Развёрнуто"))
                            .accessibilityIdentifier("deviceHeader-" + source.id)
                        Menu {
                                Button(L("Переименовать…"), systemImage: "pencil") { renaming = RenameTarget(client: source) }
                                    .disabled(!source.canRenameDevice)
                        } label: {
                            Image(systemName: "ellipsis").frame(minWidth: controlTarget, minHeight: controlTarget)
                        }
                            .accessibilityLabel(L("Действия: \(source.displayName)"))
                            .accessibilityIdentifier("deviceMenu-" + source.id)
                            }
                    }
                    }
                    // A group found by name opens the feed of the employee who works there.
                    let groups = source.telegramGroups.filter { !searchTerm.isEmpty && $0.title.localizedCaseInsensitiveContains(searchTerm) }
                    if !groups.isEmpty {
                        Section(library.hasOtherDevices ? L("Группы в Telegram · \(source.displayName)") : L("Группы в Telegram")) {
                            ForEach(groups) { group in
                                EmployeePickerRow(name: group.title, subtitle: group.enabled == false ? L("Бот на паузе") : source.profiles.first { $0.id == group.profileId }?.name ?? "OpenStrudel",
                                                  selected: source === client && source.selectedChatID == group.conversationId,
                                                  appearance: nil, symbol: "person.2") {
                                    Task { await library.select(source, group: group); dismiss() }
                                }.accessibilityIdentifier("telegramConversation-" + group.chatId)
                            }
                        }
                    }
                }
                HiddenEmployeesButton()
            }
            .navigationTitle(L("Чаты"))
            .navigationDestination(isPresented: $showingHistory) { ConversationBrowser(isPresented: $isPresented, embedded: true) }
            .sheet(item: $movingEmployee) { EmployeeMoveView(request: $0) }
            .sheet(item: $renaming) { NameEditor(target: $0) }
            #if os(iOS)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: L("Найти чат"))
            #else
            .searchable(text: $query, prompt: L("Найти чат"))
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    HStack(spacing: 16) {
                        Button { showingSettings = true } label: { Image(systemName: "gearshape") }
                            .accessibilityLabel(L("Настройки")).accessibilityIdentifier("teamSettings")
                        Menu {
                            NewEmployeeControl(beforeCreate: { dismiss() }) {
                                Label(L("Новый сотрудник"), systemImage: "plus")
                            }
                            Button(L("Добавить Mac или сервер"), systemImage: "laptopcomputer.and.iphone") { addingDevice = true }
                                .accessibilityIdentifier("connectDevice")
                        } label: {
                            Image(systemName: "plus").frame(minWidth: controlTarget, minHeight: controlTarget)
                        }
                        .accessibilityLabel(L("Добавить"))
                        .accessibilityIdentifier("addMenu")
                    }
                }
                ToolbarItem(placement: .cancellationAction) { Button(L("Готово")) { dismiss() } }
            }
        }
        .sheet(isPresented: $showingSettings) { SettingsView().environmentObject(client) }
        .sheet(isPresented: $addingDevice, onDismiss: {
            if let invitation { confirmingInvitation = invitation; self.invitation = nil }
        }) {
            #if os(iOS)
            ConnectionInvitationView { invitation = $0 }
            #else
            ConnectDeviceView { invitation = $0 }
            #endif
        }
        .sheet(item: $confirmingInvitation) { AddDeviceConfirmation(pairing: $0).environmentObject(library) }
        .modifier(InterfaceLanguage())
    }

    /// The device's name and, as the Mac sidebar shows with a symbol, why it cannot be reached.
    private func headerLabel(_ source: HomeClient) -> String {
        if source.connectionNeedsUnlock { return source.displayName + ", " + L("Unlock connection") }
        return source.homeUnreachable ? source.displayName + ", " + L("Нет связи") : source.displayName
    }
}

/// Employees are the primary entry points. Channel history is a separate,
/// searchable destination; browsing it never changes bot routing or delivery.
struct ConversationBrowser: View {
    @EnvironmentObject private var library: DeviceLibrary
    @EnvironmentObject private var client: HomeClient
    @Binding var isPresented: Bool
    var embedded = false
    @State private var query = ""
    private var term: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var hasHistory: Bool {
        library.visibleClients.contains { source in
            source.telegram?.chats?.contains(where: { $0.conversationId != nil }) == true || !source.importedConversations.isEmpty
        }
    }

    var body: some View {
        Group {
            if embedded { content }
            else { NavigationStack { content } }
        }
        #if os(macOS)
        .frame(minWidth: 480, idealWidth: 560, minHeight: 420, idealHeight: 560)
        #endif
    }

    private var content: some View {
        List {
            if !hasHistory {
                ContentUnavailableView(L("Пока нет переписок"), systemImage: "bubble.left.and.bubble.right",
                    description: Text(L("Разговоры с ботом в Telegram появятся здесь автоматически.")))
            } else {
                ForEach(library.visibleClients) { source in
                    let chats = (source.telegram?.chats ?? []).filter { $0.conversationId != nil && (term.isEmpty || $0.title.localizedCaseInsensitiveContains(term)) }
                    let archives = source.importedConversations.filter { term.isEmpty || $0.title.localizedCaseInsensitiveContains(term) }
                    if !chats.isEmpty || !archives.isEmpty {
                        Section {
                            ForEach(chats) { chat in
                                EmployeePickerRow(name: chat.title,
                                    subtitle: (chat.isGroup ? L("Группа в Telegram") : L("Личный разговор в Telegram")) + (chat.enabled == false ? L(" · на паузе") : ""),
                                    selected: source === client && source.selectedChatID == chat.conversationId,
                                    appearance: nil, symbol: chat.isGroup ? "person.2" : "bubble.left") {
                                        open(source, conversation: chat.conversationId)
                                    }.accessibilityIdentifier("telegramConversation-" + chat.chatId)
                            }
                            ForEach(archives) { chat in
                                EmployeePickerRow(name: chat.title, subtitle: L("Из прежнего приложения"),
                                    selected: source === client && source.selectedChatID == chat.id,
                                    appearance: nil, symbol: "archivebox") {
                                        open(source, conversation: chat.id)
                                    }
                            }
                        } header: { if library.hasOtherDevices { Text(source.displayName) } }
                    }
                }
                if !term.isEmpty && !library.visibleClients.contains(where: { source in
                    (source.telegram?.chats ?? []).contains { $0.conversationId != nil && $0.title.localizedCaseInsensitiveContains(term) }
                        || source.importedConversations.contains { $0.title.localizedCaseInsensitiveContains(term) }
                }) { SearchEmptyState(query: query) { query = "" } }
            }
        }
        .navigationTitle(L("Переписки"))
        .searchable(text: $query, prompt: L("Найти переписку"))
        .toolbar {
            if !embedded {
                ToolbarItem(placement: .confirmationAction) { Button(L("Готово")) { isPresented = false } }
            }
        }
    }

    private func open(_ source: HomeClient, conversation: String?) {
        Task {
            library.select(source)
            await source.selectChat(conversation)
            isPresented = false
        }
    }
}

/// A row like the Mac sidebar: the character at 36, 12 to the name, the name over one line of preview.
/// An employee whose device is out of reach rests in grey and says so in words.
struct EmployeePickerRow: View {
    @Environment(\.dynamicTypeSize) private var textSize
    let name: String
    let subtitle: String
    let selected: Bool
    let appearance: AgentAppearance?
    var offline = false
    var symbol: String? = nil
    let action: () -> Void
    private var preview: String { offline ? L("Нет связи") : subtitle }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                if !textSize.isAccessibilitySize {
                    if let symbol {
                        Image(systemName: symbol).font(.title3).foregroundStyle(AppTheme.secondaryText)
                            .frame(width: AvatarSize.row, height: AvatarSize.row)
                    } else {
                        AgentAvatar(appearance: appearance, size: AvatarSize.row).offlineCharacter(offline)
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).font(AppTypography.interface.weight(.medium)).foregroundStyle(Color.primary)
                        .lineLimit(textSize.isAccessibilitySize ? nil : 1)
                    if !preview.isEmpty {
                        Text(preview).font(AppTypography.interface).foregroundStyle(AppTheme.secondaryText)
                            .lineLimit(textSize.isAccessibilitySize ? nil : 1)
                    }
                }
                Spacer(minLength: 0)
                if selected { Image(systemName: "checkmark").fontWeight(.semibold).foregroundStyle(AppTheme.accent) }
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.automatic)
        .accessibilityLabel(name)
        .accessibilityValue(preview)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct SearchEmptyState: View {
    let query: String
    let clear: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("Ничего не найдено")).font(AppTypography.interface.weight(.semibold))
            Text(L("Нет совпадений для «\(query)». Проверьте название или очистите поиск."))
                .font(AppTypography.interface).foregroundStyle(AppTheme.secondaryText).fixedSize(horizontal: false, vertical: true)
            Button(L("Очистить поиск"), action: clear).frame(minHeight: controlTarget)
        }.padding(.vertical, 16).accessibilityIdentifier("searchEmptyState")
    }
}
