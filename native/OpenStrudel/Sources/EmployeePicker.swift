import SwiftUI

struct EmployeePicker: View {
    @EnvironmentObject private var library: DeviceLibrary
    @EnvironmentObject private var client: HomeClient
    @Environment(\.dismiss) private var dismiss
    @Binding var isPresented: Bool

    @State private var query = ""
    @State private var showingSettings = false
    @State private var showingHistory = false
    private var searchTerm: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var showsMain: Bool { searchTerm.isEmpty || "OpenStrudel".localizedCaseInsensitiveContains(searchTerm) }

    var body: some View {
        NavigationStack {
            List {
                if searchTerm.isEmpty {
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
                        if showsMain {
                            EmployeePickerRow(name: "OpenStrudel", subtitle: source.displayName, selected: source === client && source.selectedProfileID == nil, appearance: nil) {
                                Task { await library.select(source, profile: nil); dismiss() }
                            }
                        }
                        ForEach(people) { profile in
                            EmployeePickerRow(name: profile.name, subtitle: profile.previewText.isEmpty ? profile.roleText : profile.previewText, selected: source === client && source.selectedProfileID == profile.id, appearance: profile.resolvedAppearance) {
                                Task { await library.select(source, profile: profile.id); dismiss() }
                            }
                            .accessibilityIdentifier("employee-" + profile.id)
                            .contextMenu {
                                Button(L("Скрыть у меня"), systemImage: "eye.slash") { Task { await library.setHidden(true, profile: profile, on: source) } }
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(L("Скрыть"), systemImage: "eye.slash") { Task { await library.setHidden(true, profile: profile, on: source) } }.tint(.gray)
                            }
                        }
                    } header: { if library.hasOtherDevices { Text(source.displayName) } }
                    }
                    let groups = source.telegramGroups.filter { !searchTerm.isEmpty && $0.title.localizedCaseInsensitiveContains(searchTerm) }
                    if !groups.isEmpty {
                        Section(library.hasOtherDevices ? L("Conversations · \(source.displayName)") : L("Переписки")) {
                            ForEach(groups) { group in
                                EmployeePickerRow(name: group.title, subtitle: group.enabled == false ? L("Бот на паузе") : L("Группа в Telegram"),
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
            .scrollContentBackground(.hidden)
            .background(HomeBackground())
            .navigationTitle(L("Чаты"))
            .navigationDestination(isPresented: $showingHistory) { ConversationBrowser(isPresented: $isPresented, embedded: true) }
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
                        NewEmployeeControl(beforeCreate: { dismiss() }) {
                            Image(systemName: "plus").frame(minWidth: controlTarget, minHeight: controlTarget)
                        }
                    }
                }
                ToolbarItem(placement: .cancellationAction) { Button(L("Готово")) { dismiss() } }
            }
        }
        .sheet(isPresented: $showingSettings) { SettingsView().environmentObject(client) }
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
        .scrollContentBackground(.hidden)
        .background(HomeBackground())
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

struct EmployeePickerRow: View {
    @Environment(\.dynamicTypeSize) private var textSize
    let name: String
    let subtitle: String
    let selected: Bool
    let appearance: AgentAppearance?
    var symbol: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                if !textSize.isAccessibilitySize {
                    if let symbol { Image(systemName: symbol).font(.title2).foregroundStyle(AppTheme.accent).frame(width: 42, height: 42) }
                    else { AgentAvatar(appearance: appearance, size: 42) }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).font(.body.weight(.medium)).lineLimit(textSize.isAccessibilitySize ? nil : 2)
                        .foregroundStyle(Color.primary)
                    if !subtitle.isEmpty {
                        Text(subtitle).font(.caption).foregroundStyle(AppTheme.secondaryText)
                            .lineLimit(textSize.isAccessibilitySize ? nil : 1)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
                if selected { Image(systemName: "checkmark").foregroundStyle(AppTheme.secondaryText) }
            }
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.automatic)
        .accessibilityLabel(name)
        .accessibilityValue(subtitle)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct SearchEmptyState: View {
    let query: String
    let clear: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("Ничего не найдено")).font(.headline)
            Text(L("Нет совпадений для «\(query)». Проверьте название или очистите поиск."))
                .font(.callout).foregroundStyle(AppTheme.secondaryText).fixedSize(horizontal: false, vertical: true)
            Button(L("Очистить поиск"), action: clear).frame(minHeight: controlTarget)
        }.padding(.vertical, 16).accessibilityIdentifier("searchEmptyState")
    }
}
