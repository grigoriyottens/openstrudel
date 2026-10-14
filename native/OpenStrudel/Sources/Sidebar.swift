import SwiftUI

#if os(macOS)
/// One row of the sidebar. Each case names its device, so a selection spans devices.
enum SidebarItem: Hashable {
    case main(client: String)
    case draft(client: String)
    case employee(client: String, profile: String)
    case group(client: String, conversation: String)

    var client: String {
        switch self {
        case .main(let client), .draft(let client), .employee(let client, _), .group(let client, _): client
        }
    }
}

struct Sidebar: View {
    @EnvironmentObject private var library: DeviceLibrary
    @Environment(\.openSettings) private var openSettings
    /// The sidebar search text; the window owns the field so ⌘F can reveal a collapsed sidebar.
    @Binding var query: String
    /// The row the person just chose, shown until its device applies it.
    @State private var pendingSelection: SidebarItem?
    /// A chosen row keeps the keyboard, so arrows, Delete and the context menu act on it.
    @FocusState private var listFocused: Bool
    @State private var deletion: EmployeeDeletion?
    @State private var confirmDeletion = false
    @State private var deleting = false
    private var searchTerm: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var showsMain: Bool { searchTerm.isEmpty || "OpenStrudel".localizedCaseInsensitiveContains(searchTerm) }

    private struct EmployeeDeletion {
        let client: HomeClient
        let id: String
        let name: String
        let device: String
    }

    var body: some View {
        List(selection: selection) {
            ForEach(library.visibleClients) { source in
                let people = people(on: source)
                if showsMain || !people.isEmpty {
                    if library.hasOtherDevices {
                        Section { rows(source, people) } header: { deviceHeader(source) }
                    } else {
                        rows(source, people)
                    }
                }
                let groups = groups(on: source)
                if !groups.isEmpty {
                    Section {
                        ForEach(groups) { group in
                            let item = SidebarItem.group(client: source.id, conversation: group.conversationId ?? "")
                            SidebarRow(name: group.title, preview: group.enabled == false ? L("Бот на паузе") : L("Группа в Telegram"),
                                       appearance: source.profiles.first { $0.id == group.profileId }?.resolvedAppearance,
                                       selected: isSelected(item))
                                .tag(item)
                                .accessibilityIdentifier("telegramConversation-" + group.chatId)
                        }
                    } header: {
                        SidebarHeader { Text(library.hasOtherDevices ? L("Conversations · \(source.displayName)") : L("Переписки")) }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        // Over the list, so the system centres it in the empty sidebar.
        .overlay {
            if !showsMain && library.visibleClients.allSatisfy({ people(on: $0).isEmpty && groups(on: $0).isEmpty }) {
                ContentUnavailableView.search(text: searchTerm)
            }
        }
        .focused($listFocused)
        // The system leaves 9.5 between the search field and the first selection; the contract asks for 16.
        .safeAreaPadding(.top, 6.5)
        .contextMenu(forSelectionType: SidebarItem.self) { items in
            if items.count == 1, let target = employee(items.first) {
                Button(L("Скрыть у меня"), systemImage: "eye.slash") { Task { await library.setHidden(true, profile: target.profile, on: target.source) } }
                Divider()
                Button(L("Удалить сотрудника…"), role: .destructive) { requestDeletion(target.profile, from: target.source) }
                    .disabled(!canDelete(on: target.source))
            }
        }
        .onDeleteCommand {
            guard let target = employee(selection.wrappedValue), canDelete(on: target.source) else { return }
            requestDeletion(target.profile, from: target.source)
        }
        .onChange(of: currentItem) { _, item in
            if item == pendingSelection { pendingSelection = nil }
        }
        .safeAreaBar(edge: .bottom, spacing: 0) { footer }
        .toolbar {
            ToolbarItem {
                NewEmployeeControl(beforeCreate: { query = "" }) {
                    Label(L("Новый сотрудник"), systemImage: "plus")
                }
                .help(L("Новый сотрудник (⌘N)"))
            }
        }
        .alert(L("Удалить «\(deletion?.name ?? L("сотрудника"))»?"), isPresented: $confirmDeletion) {
            Button(L("Отмена"), role: .cancel) {}
            Button(L("Удалить"), role: .destructive) {
                guard let target = deletion else { return }
                deleting = true
                Task {
                    defer { deleting = false }
                    do { try await target.client.deleteProfile(target.id) }
                    catch { target.client.errorMessage = error.localizedDescription }
                }
            }
        } message: {
            Text(L("Сотрудник, переписка и расписания будут удалены с устройства «\(deletion?.device ?? "OpenStrudel")». Отменить удаление нельзя."))
        }
    }

    @ViewBuilder private func rows(_ source: HomeClient, _ people: [EmployeeProfile]) -> some View {
        if showsMain {
            let item = SidebarItem.main(client: source.id)
            SidebarRow(name: "OpenStrudel",
                       preview: library.hasOtherDevices ? source.displayName : L("Помощник для ваших задач"),
                       appearance: nil, offline: source.isOffline(nil), selected: isSelected(item))
                .tag(item)
        }
        if source.isEmployeeDraft && searchTerm.isEmpty {
            let item = SidebarItem.draft(client: source.id)
            SidebarRow(name: L("Новый сотрудник"), preview: L("Опишите его задачу"), appearance: source.draftAppearance,
                       selected: isSelected(item))
                .tag(item)
        }
        ForEach(people) { profile in
            let item = SidebarItem.employee(client: source.id, profile: profile.id)
            // Every row keeps two lines: the last message, the role, or the empty conversation's prompt.
            SidebarRow(name: profile.name,
                       preview: !profile.previewText.isEmpty ? profile.previewText : !profile.roleText.isEmpty ? profile.roleText : L("Напишите, что нужно."),
                       appearance: profile.resolvedAppearance, offline: source.isOffline(profile), selected: isSelected(item))
                .tag(item)
                .accessibilityIdentifier("employee-" + profile.id)
        }
    }

    private func deviceHeader(_ source: HomeClient) -> some View {
        SidebarHeader {
            HStack(spacing: 4) {
                Text(source.displayName)
                if source.connectionNeedsUnlock { Image(systemName: "lock").accessibilityLabel(L("Unlock connection")) }
                else if source.homeUnreachable { Image(systemName: "wifi.slash").accessibilityLabel(L("Нет связи")) }
            }
        }
    }

    /// The hidden employees and the device row stay under the list, on the row text edge.
    private var footer: some View {
        VStack(alignment: .leading, spacing: 4) {
            HiddenEmployeesButton()
            Button {
                UserDefaults.standard.set(SettingsView.Section.devices.rawValue, forKey: "openstrudel.settingsTab")
                openSettings()
            } label: {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(library.hasOtherDevices ? L("Мои устройства") : library.active.displayName)
                            .fontWeight(.medium).lineLimit(1).truncationMode(.middle)
                        Text(L("Устройства и настройки")).foregroundStyle(AppTheme.secondaryText).lineLimit(1)
                    }
                } icon: {
                    Image(systemName: !library.hasOtherDevices && library.active.isLocalConnection ? "laptopcomputer" : "desktopcomputer")
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L("Устройства и настройки"))
            .accessibilityValue(library.hasOtherDevices ? L("Мои устройства") : library.active.displayName)
            .accessibilityIdentifier("openDeviceSettings")
            .help(L("Устройства и настройки OpenStrudel (⌘,)"))
        }
        .labelStyle(SidebarAccessoryLabelStyle())
        // The symbols share the characters' column, so the words share the rows' text edge.
        .padding(.horizontal, SidebarMetrics.characterEdge)
        .padding(.vertical, 6)
    }

    // MARK: Selection

    /// The library's own selection, read in the order the rows are drawn.
    private var currentItem: SidebarItem {
        let source = library.active
        if !searchTerm.isEmpty, let chat = source.selectedChatID, groups(on: source).contains(where: { $0.conversationId == chat }) {
            return .group(client: source.id, conversation: chat)
        }
        if source.isEmployeeDraft { return .draft(client: source.id) }
        if let profile = source.selectedProfileID { return .employee(client: source.id, profile: profile) }
        return .main(client: source.id)
    }

    private func isSelected(_ item: SidebarItem) -> Bool { (pendingSelection ?? currentItem) == item }

    private var selection: Binding<SidebarItem?> {
        Binding {
            pendingSelection ?? currentItem
        } set: { item in
            guard let item, item != pendingSelection ?? currentItem,
                  let source = library.visibleClients.first(where: { $0.id == item.client }) else { return }
            query = ""
            pendingSelection = item
            listFocused = true
            Task {
                switch item {
                case .main: await library.select(source, profile: nil)
                case .draft: library.select(source)
                case .employee(_, let profile): await library.select(source, profile: profile)
                case .group(_, let conversation):
                    if let group = source.telegramGroups.first(where: { $0.conversationId == conversation }) {
                        await library.select(source, group: group)
                    }
                }
                if pendingSelection == item { pendingSelection = nil }
            }
        }
    }

    private func people(on source: HomeClient) -> [EmployeeProfile] {
        library.visibleProfiles(on: source).filter {
            searchTerm.isEmpty || $0.name.localizedCaseInsensitiveContains(searchTerm) || $0.roleText.localizedCaseInsensitiveContains(searchTerm)
        }
    }

    /// Telegram groups appear only as search results.
    private func groups(on source: HomeClient) -> [TelegramChat] {
        searchTerm.isEmpty ? [] : source.telegramGroups.filter { $0.title.localizedCaseInsensitiveContains(searchTerm) }
    }

    private func employee(_ item: SidebarItem?) -> (source: HomeClient, profile: EmployeeProfile)? {
        guard case .employee(let client, let id)? = item,
              let source = library.visibleClients.first(where: { $0.id == client }),
              let profile = source.profiles.first(where: { $0.id == id }) else { return nil }
        return (source, profile)
    }

    private func canDelete(on source: HomeClient) -> Bool {
        !deleting && source.canManageOpenAI && !source.homeUnreachable
    }

    private func requestDeletion(_ profile: EmployeeProfile, from source: HomeClient) {
        guard !deleting else { return }
        let device = profile.deviceId == source.health?.nodeId ? source.displayName
            : source.devices.first(where: { $0.id == profile.deviceId })?.name ?? source.displayName
        deletion = EmployeeDeletion(client: source, id: profile.id, name: profile.name, device: device)
        confirmDeletion = true
    }
}

/// A character, its name and one line of preview. The system draws selection.
struct SidebarRow: View {
    let name: String
    let preview: String
    let appearance: AgentAppearance?
    var offline = false
    var selected = false
    @Environment(\.appearsActive) private var appearsActive

    var body: some View {
        HStack(spacing: 12) {
            AgentAvatar(appearance: appearance, size: AvatarSize.row)
                .offlineCharacter(offline)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).fontWeight(.medium).lineLimit(1)
                let text = offline ? L("Нет связи") : preview
                if !text.isEmpty {
                    if selected {
                        // On the selection the preview takes the name's colour; weight alone carries the hierarchy.
                        Text(text).lineLimit(1)
                    } else {
                        // The list dims the system secondary below 4.5:1, so an active window uses the token.
                        // An inactive window dims the names, and the preview dims with them.
                        Text(text).lineLimit(1)
                            .foregroundStyle(appearsActive ? AnyShapeStyle(AppTheme.secondaryText) : AnyShapeStyle(.secondary))
                    }
                }
            }
        }
        // The list adds 4 above and below and 6 at each side, so each row is a 56-pt step
        // (the web's row) with 10 above and below the character and 12 inside the selection's sides.
        .padding(.vertical, 6)
        .padding(.horizontal, SidebarMetrics.leadingInset)
        .accessibilityElement(children: .combine)
    }
}

/// A section title on the characters' edge with 24 above it; the list draws its style.
private struct SidebarHeader<Content: View>: View {
    @ViewBuilder let content: () -> Content
    var body: some View {
        content()
            // The list starts titles 8 before the character column and 16 under the row above.
            .padding(.leading, 8)
            .padding(.top, 8)
    }
}

enum SidebarMetrics {
    /// Row content inset added to the list's own 6, so the character sits 12 inside the selection.
    static let leadingInset: CGFloat = 6
    /// The list's selection starts 10 from the sidebar edge and its content 6 inside that.
    static let characterEdge: CGFloat = 16 + leadingInset
}

/// Puts a symbol in the avatar column so text below the list starts on the row text edge.
struct SidebarAccessoryLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 12) {
            configuration.icon
                .imageScale(.large)
                .foregroundStyle(.secondary)
                .frame(width: AvatarSize.row, height: AvatarSize.row)
            configuration.title
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
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
