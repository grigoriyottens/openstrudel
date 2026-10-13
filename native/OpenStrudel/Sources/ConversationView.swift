import SwiftUI

struct ConversationView: View {
    @EnvironmentObject private var library: DeviceLibrary
    @EnvironmentObject private var client: HomeClient
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var showSettings: Bool
    @State private var draft = ""
    @State private var pickedFiles: [PickedFile] = []
    @State private var showEmployees = false
    @State private var showBotDetails = false
    @State private var followsLatest = true
    @State private var userIsScrolling = false
    @State private var hasNewMessages = false
    @FocusState private var focused: Bool
    private var draftKey: String { HomeDrafts.key(home: client.baseURLString, profile: client.selectedProfileID, chat: client.selectedChatID) }

    var body: some View {
        VStack(spacing: 0) {
            #if os(macOS)
            ConversationHeader { showBotDetails = true }
            #endif

            if !client.isEmployeeDraft && !client.employeeTelegramChats.isEmpty {
                ConversationSources()
                    .padding(.horizontal, chatInset).padding(.vertical, 8)
            }

            if client.connectionNeedsPairing || client.homeUnreachable || client.health == nil {
                HStack(spacing: 10) {
                    if client.isConnecting { ProgressView().controlSize(.small) }
                    else { Image(systemName: client.connectionNeedsUnlock ? "lock" : "wifi.slash") }
                    Text(client.connectionNeedsUnlock ? L("Unlock the saved connection to continue. Your chats and drafts are safe.") : client.connectionNeedsPairing ? L("Подключите «\(client.displayName)» снова. Переписка сохранена на устройстве.") : client.isConnecting ? L("Подключаемся к «\(client.displayName)»…") : L("«\(client.displayName)» не на связи. Переписка и черновики сохранены. Подключимся автоматически."))
                        .font(.callout)
                    Spacer(minLength: 0)
                    if client.connectionNeedsUnlock {
                        SavedConnectionUnlockButton(client: client)
                    } else if client.connectionNeedsPairing { Button(L("Подключить")) { showSettings = true } }
                }.foregroundStyle(AppTheme.secondaryText).padding(.horizontal, chatInset).padding(.vertical, 10)
            }

            if client.openAIAccount?.connected == false && !client.homeUnreachable && client.health != nil {
                OpenAIRecoveryNotice()
                    .padding(.horizontal, chatInset).padding(.vertical, 8)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    if client.messages.isEmpty && client.visiblePendingMessages.isEmpty {
                        EmptyChat()
                            .frame(maxWidth: .infinity, minHeight: 430)
                    } else {
                        TranscriptRows(proxy: proxy, followsLatest: $followsLatest)
                        .frame(maxWidth: Layout.column, alignment: .leading)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.horizontal, chatInset)
                        .padding(.top, 18)
                        .padding(.bottom, 24)
                    }
                }
                .scrollIndicators(.hidden)
                .defaultScrollAnchor(.bottom, for: .initialOffset)
                #if os(macOS)
                .mask(EdgeFade())
                #endif
                .scrollDismissesKeyboard(.interactively)
                .onScrollPhaseChange { oldPhase, phase, context in
                    // A touch on an answer button also enters .tracking. Only an
                    // actual drag should change the transcript reading anchor.
                    if phase == .interacting {
                        userIsScrolling = true
                        followsLatest = false
                    }
                    if phase == .idle && userIsScrolling {
                        userIsScrolling = false
                        followsLatest = context.geometry.visibleRect.maxY >= context.geometry.contentSize.height - 60
                        if followsLatest { hasNewMessages = false }
                    }
                }
                .onChange(of: client.messages.last?.id) { _, _ in
                    if followsLatest { scrollToBottom(proxy, animated: true) }
                    else { hasNewMessages = true }
                }
                .onChange(of: client.visiblePendingMessages.map(\.id)) { old, new in
                    if new.contains(where: { !old.contains($0) }) {
                        followsLatest = true
                        hasNewMessages = false
                        scrollToBottom(proxy, animated: true)
                    }
                }
                .onChange(of: client.interactions) { _, _ in
                    if followsLatest { scrollToBottom(proxy, animated: true) }
                    else { hasNewMessages = true }
                }
                .onChange(of: draftKey) { _, _ in
                    followsLatest = true
                    hasNewMessages = false
                    scrollToBottom(proxy, animated: false)
                }
                // Animate scrolling, not pending-row replacement: an implicit
                // layout animation can loop while the iPad keyboard is visible.
                .overlay(alignment: .bottom) {
                    if hasNewMessages && !followsLatest {
                        Button(L("Новые сообщения"), systemImage: "arrow.down") {
                            followsLatest = true
                            hasNewMessages = false
                            scrollToBottom(proxy, animated: true)
                        }
                        .font(.subheadline).buttonStyle(.glass)
                        .padding(.bottom, 8)
                    }
                }
                .task {
                    await Task.yield()
                    await Task.yield()
                    scrollToBottom(proxy, animated: false)
                }
            }

            if client.activeTelegramChat != nil {
                Text(L("Здесь можно обсудить переписку с помощником. Ответ останется в OpenStrudel."))
                    .font(.caption).foregroundStyle(AppTheme.secondaryText)
                    .frame(maxWidth: Layout.column, alignment: .leading).padding(.horizontal, chatInset)
                    .accessibilityIdentifier("telegramReplyDestination")
            }
            Composer(draft: $draft, files: $pickedFiles, focused: $focused, contextID: draftKey, canSend: client.isConfigured && !client.connectionNeedsPairing && client.openAIAccount?.connected != false) { mode in
                guard client.openAIAccount?.connected != false else { return }
                let value = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !value.isEmpty || !pickedFiles.isEmpty else { return }
                let files = pickedFiles
                pickedFiles = []
                draft = ""
                focused = true
                Task { await client.sendMessage(value, files: files, mode: mode) }
            }
            .frame(maxWidth: Layout.column)
            .padding(.horizontal, chatInset)
        }
        .task { draft = library.draft(for: draftKey); pickedFiles = library.fileDrafts[draftKey] ?? [] }
        .onChange(of: client.openAIAccount?.connected) { _, connected in
            if connected == false { focused = false }
        }
        .onChange(of: pickedFiles) { _, value in
            guard library.active === client else { return }
            library.fileDrafts[draftKey] = value
        }
        .onChange(of: draft) { _, value in
            guard library.active === client else { return }
            library.saveDraft(value, for: draftKey)
        }
        .onChange(of: draftKey) { old, new in
            guard library.active === client else { return }
            library.saveDraft(draft, for: old)
            draft = library.draft(for: new)
            library.fileDrafts[old] = pickedFiles
            pickedFiles = library.fileDrafts[new] ?? []
            #if os(macOS)
            focused = client.isEmployeeDraft
            #else
            focused = false
            #endif
        }
        #if os(macOS)
        .padding(.horizontal, 13)
        .padding(.vertical, 9)
        #else
        .padding(.bottom, 8)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { focused = false; showEmployees = true } label: { Image(systemName: "line.3.horizontal") }
                    .foregroundStyle(.primary)
                    .accessibilityLabel(L("Чаты"))
            }
            ToolbarItem(placement: .principal) {
                ConversationTitle { focused = false; showBotDetails = true }
            }
            ToolbarItem(placement: .topBarTrailing) {
                if client.activeProfile == nil {
                    Button { focused = false; showSettings = true } label: { Image(systemName: "gearshape") }
                        .foregroundStyle(.primary).accessibilityLabel(L("Настройки"))
                }
            }
        }
        #endif
        .sheet(isPresented: $showEmployees) {
            EmployeePicker(isPresented: $showEmployees).environmentObject(client)
        }
        .sheet(isPresented: $showBotDetails) {
            if let profile = client.activeProfile {
                BotDetailsView(profile: profile).environmentObject(client)
            } else {
                NavigationStack {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            ModelSettingsView(agentID: "main")
                            Divider()
                            NavigationLink { ConnectionsView(embedded: true) } label: { Label(L("Сервисы и навыки"), systemImage: "link") }
                        }.padding(24)
                    }
                        .navigationTitle("OpenStrudel")
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button(L("Готово")) { showBotDetails = false } } }
                }
                #if os(macOS)
                .frame(width: 500, height: 400)
                #endif
            }
        }
    }

    /// Messages and the composer share one column.
    private var chatInset: CGFloat {
        #if os(macOS)
        24
        #else
        8
        #endif
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy, animated: Bool) {
        let conversation = draftKey
        Task { @MainActor in
            await Task.yield()
            guard conversation == draftKey, followsLatest else { return }
            if animated && !reduceMotion {
                withAnimation(.easeOut(duration: 0.22)) {
                    proxy.scrollTo("conversation-bottom", anchor: .bottom)
                }
            } else {
                proxy.scrollTo("conversation-bottom", anchor: .bottom)
            }
        }
    }
}

struct OpenAIRecoveryNotice: View {
    @EnvironmentObject private var client: HomeClient
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var showAccounts = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if dynamicTypeSize.isAccessibilitySize {
                Text(client.openAIAccount?.isUnavailable == true ? L("Связь с OpenAI") : L("Вход в OpenAI"))
                    .font(.callout.weight(.medium)).accessibilityIdentifier("openAIRecoveryNotice")
                Text(L("Чаты и черновики сохранены.")).font(.caption).foregroundStyle(AppTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                explanation
            }
            if client.openAIAccount?.isUnavailable == true {
                Button { Task { await client.refreshOpenAIAccount(force: true) } } label: { SetupActionLabel(title: L("Проверить ещё раз")) }
                    .adaptiveActionStyle(.glass).disabled(client.isLoading)
            } else if client.canManageOpenAI {
                Button { showAccounts = true } label: { SetupActionLabel(title: L("Войти в OpenAI")) }.adaptiveActionStyle(.glass)
                    .accessibilityIdentifier("recoverOpenAIAccount")
            } else if dynamicTypeSize.isAccessibilitySize {
                Button { showAccounts = true } label: { SetupActionLabel(title: L("Как восстановить вход")) }.adaptiveActionStyle(.glass)
            }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(12)
            .background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
            .fixedSize(horizontal: false, vertical: true)
            .sheet(isPresented: $showAccounts) { SettingsView(initialSection: .accounts) }
    }

    private var explanation: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(client.openAIAccount?.isUnavailable == true ? L("Не удалось проверить соединение с OpenAI.")
                 : L("Вход в OpenAI нужно восстановить.")).font(.callout.weight(.medium))
                .accessibilityIdentifier("openAIRecoveryNotice")
            Text(client.openAIRecoveryMessage).font(.caption).foregroundStyle(AppTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ConversationHeader: View {
    let openEmployee: () -> Void

    var body: some View {
        HStack {
            Spacer()
            ConversationTitle(openEmployee: openEmployee)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .glassEffect(.regular, in: .capsule)
            Spacer()
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
    }

}

struct ConversationTitle: View {
    @EnvironmentObject private var client: HomeClient
    let openEmployee: () -> Void
    var body: some View {
        VStack(spacing: 2) {
            if !client.isEmployeeDraft {
                Button(action: openEmployee) {
                    HStack(spacing: 7) {
                        identity
                        Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    }.frame(minHeight: controlTarget).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L("Настройки сотрудника"))
                .accessibilityValue(client.activeAgentName)
                .accessibilityIdentifier("openEmployeeDetails")
                .help(L("Открыть сотрудника «\(client.activeAgentName)»"))
            } else {
                HStack(spacing: 7) { identity }.frame(minHeight: controlTarget)
            }
            if let archive = client.importedConversations.first(where: { $0.id == client.selectedChatID }) {
                Label(L("Archive · \(archive.title)"), systemImage: "archivebox")
                    .labelStyle(.titleAndIcon)
                    .font(.caption).foregroundStyle(AppTheme.secondaryText).lineLimit(1)
            }
        }.frame(minHeight: controlTarget).contentShape(Rectangle())
    }

    @ViewBuilder private var identity: some View {
        AgentAvatar(appearance: client.activeAppearance, size: 30)
        Text(client.activeAgentName).font(.headline).lineLimit(1)
    }
}

/// These are views of existing conversations, not new employee bindings.
/// Keep each audience's transcript, tools and draft in its original scope.
struct ConversationSources: View {
    @EnvironmentObject private var client: HomeClient
    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                source(title: L("В приложении"), symbol: "bubble.left", conversation: nil)
                ForEach(client.employeeTelegramChats) { chat in
                    source(title: chat.title, symbol: "paperplane", conversation: chat.conversationId,
                           detail: chat.enabled == false ? L("Telegram · бот на паузе") : "Telegram")
                }
            }.padding(.horizontal, 2)
        }
        .scrollIndicators(.hidden)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityIdentifier("conversationSources")
    }

    private func source(title: String, symbol: String, conversation: String?, detail: String? = nil) -> some View {
        let selected = client.selectedChatID == conversation
        return Button { Task { await client.selectChat(conversation) } } label: {
            Label(title, systemImage: symbol)
                .font(.subheadline.weight(selected ? .semibold : .regular))
                .padding(.horizontal, 12)
                .frame(minHeight: controlTarget)
                .contentShape(Capsule())
                .background(selected ? Color.primary.opacity(0.10) : Color.clear, in: Capsule())
        }
        .buttonStyle(.plain)
        .foregroundStyle(selected ? Color.primary : AppTheme.secondaryText)
        .accessibilityLabel(detail.map { title + ", " + $0 } ?? title)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier(conversation.map { "conversationSource-" + $0 } ?? "conversationSource-app")
        .help(detail.map { title + " · " + $0 } ?? title)
    }
}
