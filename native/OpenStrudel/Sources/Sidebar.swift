import SwiftUI

#if os(macOS)
struct Sidebar: View {
    @EnvironmentObject private var library: DeviceLibrary
    @EnvironmentObject private var client: HomeClient
    @Binding var showSettings: Bool
    @State private var searching = false
    @State private var query = ""
    private var searchTerm: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    @FocusState private var searchFocused: Bool
    @FocusState private var focusedEmployee: String?
    @State private var deletion: EmployeeDeletion?
    @State private var confirmDeletion = false
    @State private var deleting = false

    private struct EmployeeDeletion {
        let client: HomeClient
        let id: String
        let name: String
        let device: String
    }

    private var showsMain: Bool { searchTerm.isEmpty || "OpenStrudel".localizedCaseInsensitiveContains(searchTerm) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                if searching {
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass").foregroundStyle(AppTheme.secondaryText)
                        TextField(L("Найти чат"), text: $query)
                            .textFieldStyle(.plain)
                            .focused($searchFocused)
                            .task {
                                // The field has to be in the window before it can take focus from the composer.
                                try? await Task.sleep(for: .milliseconds(50))
                                searchFocused = true
                            }
                            .onExitCommand(perform: closeSearch)
                        Button(action: closeSearch) { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.plain)
                            .foregroundStyle(.tertiary)
                            .accessibilityLabel(L("Закрыть поиск"))
                            .help(L("Закрыть поиск (Escape)"))
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 32)
                    .background(.primary.opacity(0.07), in: Capsule())
                } else {
                    Button { searching = true } label: {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 16, weight: .medium))
                            .frame(width: 36, height: 36)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(AppTheme.secondaryText)
                    .accessibilityLabel(L("Поиск чата"))
                    .help(L("Найти сотрудника (⌘F)"))
                    .keyboardShortcut("f", modifiers: .command)

                    Spacer()
                }

                NewEmployeeControl(beforeCreate: closeSearch) {
                    Image(systemName: "plus")
                        .font(.system(size: 17, weight: .medium))
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(AppTheme.secondaryText)
                .help(L("Новый сотрудник (⌘N)"))
            }
            .padding(.horizontal, 15)
            .padding(.top, 12)
            .padding(.bottom, 10)

            ScrollView {
                VStack(spacing: 3) {
                    if !showsMain && !library.visibleClients.contains(where: { source in library.visibleProfiles(on: source).contains { $0.name.localizedCaseInsensitiveContains(searchTerm) || $0.roleText.localizedCaseInsensitiveContains(searchTerm) } || source.telegramGroups.contains { $0.title.localizedCaseInsensitiveContains(searchTerm) } }) {
                        SearchEmptyState(query: query) { query = "" }
                    }
                    ForEach(library.visibleClients) { source in
                        let people = library.visibleProfiles(on: source).filter { searchTerm.isEmpty || $0.name.localizedCaseInsensitiveContains(searchTerm) || $0.roleText.localizedCaseInsensitiveContains(searchTerm) }
                        if showsMain || !people.isEmpty {
                            if library.hasOtherDevices {
                                HStack(spacing: 5) {
                                    Text(source.displayName)
                                    if source.connectionNeedsUnlock { Image(systemName: "lock").accessibilityLabel(L("Unlock connection")) }
                                    else if source.homeUnreachable { Image(systemName: "wifi.slash").accessibilityLabel(L("Нет связи")) }
                                }.font(.system(size: 11, weight: .medium)).foregroundStyle(AppTheme.secondaryText)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 12).padding(.top, 14).padding(.bottom, 5)
                            }
                            if showsMain {
                                SidebarRow(name: "OpenStrudel", subtitle: library.hasOtherDevices ? source.displayName : L("Помощник для ваших задач"),
                                           selected: source === client && source.selectedProfileID == nil, appearance: nil) {
                                    closeSearch(); Task { await library.select(source, profile: nil) }
                                }
                            }
                            if source.isEmployeeDraft && searchTerm.isEmpty {
                                SidebarRow(name: L("Новый сотрудник"), subtitle: L("Опишите его задачу"), selected: source === client, appearance: source.draftAppearance) { library.select(source) }
                            }
                            ForEach(people) { profile in
                                SidebarRow(name: profile.name, subtitle: profile.previewText.isEmpty ? profile.roleText : profile.previewText,
                                           selected: source === client && source.selectedProfileID == profile.id, appearance: profile.resolvedAppearance) {
                                    closeSearch()
                                    focusedEmployee = source.id + profile.id
                                    Task { await library.select(source, profile: profile.id) }
                                }
                                .focusable()
                                .focused($focusedEmployee, equals: source.id + profile.id)
                                .focusEffectDisabled()
                                #if os(macOS)
                                .onDeleteCommand {
                                    guard !deleting, source.canManageOpenAI else { return }
                                    requestDeletion(profile, from: source)
                                }
                                #endif
                                .contextMenu {
                                    Button(L("Скрыть у меня"), systemImage: "eye.slash") { Task { await library.setHidden(true, profile: profile, on: source) } }
                                    Divider()
                                    Button(L("Удалить сотрудника…"), role: .destructive) { requestDeletion(profile, from: source) }
                                        .disabled(deleting || !source.canManageOpenAI || source.homeUnreachable)
                                }
                            }
                        }
                        let groups = source.telegramGroups.filter { !searchTerm.isEmpty && $0.title.localizedCaseInsensitiveContains(searchTerm) }
                        if !groups.isEmpty {
                            Text(library.hasOtherDevices ? L("Conversations · \(source.displayName)") : L("Переписки"))
                                .font(.caption.weight(.medium)).foregroundStyle(AppTheme.secondaryText)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 12).padding(.top, 14).padding(.bottom, 5)
                            ForEach(groups) { group in
                                SidebarRow(name: group.title, subtitle: group.enabled == false ? L("Бот на паузе") : L("Группа в Telegram"),
                                           selected: source === client && source.selectedChatID == group.conversationId,
                                           appearance: source.profiles.first(where: { $0.id == group.profileId })?.resolvedAppearance,
                                           symbol: "person.2") {
                                    closeSearch(); Task { await library.select(source, group: group) }
                                }
                                .accessibilityIdentifier("telegramConversation-" + group.chatId)
                            }
                        }
                    }
                }
                .padding(.horizontal, 9)
            }
            .scrollIndicators(.hidden)

            Spacer(minLength: 12)

            HiddenEmployeesButton().padding(.horizontal, 22)

            Button { showSettings = true } label: {
                HStack(spacing: 10) {
                    Image(systemName: library.hasOtherDevices ? "desktopcomputer" : client.isLocalConnection ? "laptopcomputer" : "desktopcomputer")
                        .font(.system(size: 19)).frame(width: 30)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(library.hasOtherDevices ? L("Мои устройства") : client.displayName)
                            .font(.subheadline.weight(.medium)).lineLimit(1).truncationMode(.middle)
                        Text(L("Устройства и настройки")).font(.caption).foregroundStyle(AppTheme.secondaryText)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 10).padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L("Устройства и настройки"))
            .accessibilityValue(library.hasOtherDevices ? L("Мои устройства") : client.displayName)
            .accessibilityIdentifier("openDeviceSettings")
            .help(L("Устройства и настройки OpenStrudel (⌘,)"))
            .padding(.horizontal, 12)
            .padding(.bottom, 13)
        }
        .alert(L("Удалить «\(deletion?.name ?? L("сотрудника"))»?"), isPresented: $confirmDeletion) {
            Button(L("Отмена"), role: .cancel) {}
            Button(L("Удалить"), role: .destructive) {
                guard let target = deletion else { return }
                deleting = true
                Task {
                    defer { deleting = false }
                    do { try await target.client.deleteProfile(target.id) }
                    catch { client.errorMessage = error.localizedDescription }
                }
            }
        } message: {
            Text(L("Сотрудник, переписка и расписания будут удалены с устройства «\(deletion?.device ?? "OpenStrudel")». Отменить удаление нельзя."))
        }
    }

    private func requestDeletion(_ profile: EmployeeProfile, from source: HomeClient) {
        guard !deleting else { return }
        let device = profile.deviceId == source.health?.nodeId ? source.displayName
            : source.devices.first(where: { $0.id == profile.deviceId })?.name ?? source.displayName
        deletion = EmployeeDeletion(client: source, id: profile.id, name: profile.name, device: device)
        confirmDeletion = true
    }

    private func select(_ profileID: String?) {
        closeSearch()
        Task { await client.selectProfile(profileID) }
    }

    private func closeSearch() {
        searching = false
        query = ""
    }
}

struct SidebarRow: View {
    let name: String
    let subtitle: String
    let selected: Bool
    let appearance: AgentAppearance?
    var symbol: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                if let symbol {
                    Image(systemName: symbol).font(.title3).foregroundStyle(AppTheme.accent)
                        .frame(width: 36, height: 36).background(AppTheme.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
                } else { AgentAvatar(appearance: appearance, size: 36) }
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).font(AppTypography.sidebarTitle).lineLimit(1)
                    if !subtitle.isEmpty { Text(subtitle).font(AppTypography.sidebarDetail).foregroundStyle(AppTheme.secondaryText).lineLimit(1) }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 60)
            .contentShape(Rectangle())
            .background(selected ? Color.primary.opacity(0.10) : .clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(name)
        .accessibilityValue(subtitle)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .help(name + (subtitle.isEmpty ? "" : "\n" + subtitle))
    }
}
#endif

/// One destination chooser for the sidebar, the phone toolbar and the draft.
/// It uses the existing paired connections; it never grants owner privileges.
struct EmployeeDestinationChoices: View {
    @EnvironmentObject private var library: DeviceLibrary
    let choose: (DeviceLibrary.EmployeeDestination) -> Void

    var body: some View {
        ForEach(library.employeeDestinations) { destination in
            Button {
                choose(destination)
            } label: {
                Text(destination.available ? destination.name : L("\(destination.name) · unavailable"))
            }
            .disabled(!destination.available)
            .accessibilityIdentifier("employeeDestination-" + destination.id)
        }
    }
}

struct NewEmployeeControl<Label: View>: View {
    @EnvironmentObject private var library: DeviceLibrary
    var beforeCreate: () -> Void = {}
    @ViewBuilder let label: () -> Label

    var body: some View {
        Group {
            if library.employeeDestinations.count > 1 {
                Menu {
                    Section(L("Создать сотрудника на")) {
                        EmployeeDestinationChoices { destination in
                            beforeCreate()
                            library.beginEmployee(on: destination.client, deviceID: destination.deviceID)
                        }
                    }
                } label: { label() }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
            } else {
                Button {
                    beforeCreate()
                    library.beginEmployee()
                } label: { label() }
                .disabled(library.employeeDestinations.first?.available != true)
            }
        }
        .accessibilityLabel(L("Новый сотрудник"))
        .accessibilityIdentifier("newEmployee")
    }
}
