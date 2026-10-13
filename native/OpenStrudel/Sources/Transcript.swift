import SwiftUI
import QuickLook

/// An empty conversation: the character, its name and its role, optically centred at 40 %.
/// The focused composer is the action.
struct EmptyChat: View {
    @EnvironmentObject private var library: DeviceLibrary
    @EnvironmentObject private var client: HomeClient

    var body: some View {
        OpticalCentre {
            VStack(spacing: 0) {
                AgentAvatar(appearance: client.activeAppearance, size: AvatarSize.hero)
                Text(client.isEmployeeDraft ? L("Создайте сотрудника") : client.activeProfile?.name ?? L("Напишите, что нужно"))
                    .font(AppTypography.display)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .padding(.top, 16)
                detail
            }
            .frame(maxWidth: 360)
            .padding(.horizontal, 24)
        }
        .containerRelativeFrame(.vertical)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder private var detail: some View {
        if client.isEmployeeDraft {
            line(L("Напишите, чем он должен заниматься. Например: «Редактор, который помогает писать короткие посты»."), limit: nil)
            if library.employeeDestinations.count > 1 {
                // The composer is the action; choosing the device is a quiet text menu in the line's place.
                Menu {
                    EmployeeDestinationChoices { destination in
                        library.chooseEmployeeDevice(destination.client, deviceID: destination.deviceID)
                    }
                } label: {
                    Text(L("Create on \(client.executionDeviceName)"))
                        .font(AppTypography.interface.weight(.medium))
                        .foregroundStyle(AppTheme.accentText)
                }
                .menuStyle(.button)
                .buttonStyle(.borderless)
                .menuIndicator(.visible)
                .tint(AppTheme.accentText)
                .fixedSize()
                .frame(minHeight: controlTarget)
                .padding(.top, 8)
                .accessibilityLabel(L("Где будет работать сотрудник"))
                .accessibilityValue(client.executionDeviceName)
                .accessibilityIdentifier("employeeCreationDevice")
            } else {
                line(L("Works on “\(client.executionDeviceName)”."), limit: 2)
            }
        } else if client.homeUnreachable || client.connectionNeedsPairing {
            line(L("История появится после подключения к устройству."), limit: 2)
        } else if let profile = client.activeProfile {
            line(profile.roleText.isEmpty ? L("Напишите, что нужно.") : profile.roleText, limit: 2)
        }
    }

    private func line(_ text: String, limit: Int?) -> some View {
        Text(text)
            .font(AppTypography.interface)
            .foregroundStyle(AppTheme.secondaryText)
            .multilineTextAlignment(.center)
            .lineLimit(limit)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 8)
    }
}

/// A centred time heading where a new day starts or after half an hour of quiet.
struct ClusterHeader: View {
    let date: Date
    let hasTime: Bool

    var body: some View {
        Text(ChatClock.cluster(date, hasTime: hasTime))
            .font(AppTypography.meta)
            .foregroundStyle(AppTheme.secondaryText)
            .monospacedDigit()
            .frame(maxWidth: .infinity)
            .accessibilityAddTraits(.isHeader)
    }
}

/// One message. The person writes in a trailing bubble; the employee answers in open text
/// on the canvas; other people in imported history or a Telegram group write on the surface.
struct MessageBubble: View {
    @EnvironmentObject private var client: HomeClient
    @State private var previewURL: URL?
    let message: HomeMessage
    /// Other people write here too (a Telegram group or history from several people),
    /// so inbound messages sit on the surface under their author.
    let shared: Bool
    let bubbleWidth: CGFloat
    /// A time heading above already shows this message's time.
    var headed = false

    private var isInbound: Bool { message.direction == "inbound" }
    private var fromSomeoneElse: Bool { isInbound && shared }

    var body: some View {
        Group {
            if let scheduleTitle = message.scheduleTitle {
                VStack(alignment: .leading, spacing: 4) {
                    Label(withTime(scheduleTitle), systemImage: "clock").modifier(MetaLine())
                    if let error = message.error { warning(error) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else if message.kind == "notice" {
                Label(withTime(L10n.text(message.text)), systemImage: "checkmark").modifier(MetaLine())
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if fromSomeoneElse {
                someoneElse
            } else if isInbound {
                person
            } else {
                employee
            }
        }
        .quickLookPreview($previewURL)
    }

    private var person: some View {
        VStack(alignment: .trailing, spacing: 4) {
            VStack(alignment: .trailing, spacing: 8) {
                if message.text.isEmpty { EmptyView() }
                else if message.imported == true { ImportedMessageText(source: message.text, fill: AppTheme.userBubble, alignment: .trailing) }
                else { ChatBubble(text: message.text) }
                attachments
            }
            if message.status == "queued" { Text(L("В очереди")).modifier(MetaLine()).padding(.trailing, 16) }
            if let error = message.error { warning(error).multilineTextAlignment(.trailing).padding(.trailing, 16) }
        }
        .frame(maxWidth: bubbleWidth, alignment: .trailing)
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private var someoneElse: some View {
        let author = [message.author, headed ? nil : message.time].compactMap { $0 }.joined(separator: " · ")
        return VStack(alignment: .leading, spacing: 4) {
            if !author.isEmpty { Text(author).modifier(MetaLine()).padding(.leading, 16) }
            VStack(alignment: .leading, spacing: 8) {
                if message.text.isEmpty { EmptyView() }
                else if message.imported == true { ImportedMessageText(source: message.text) }
                else { ChatBubble(text: message.text, fill: AppTheme.surface) }
                attachments
            }
            if let error = message.error { warning(error).padding(.leading, 16) }
        }
        .frame(maxWidth: bubbleWidth, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var employee: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !message.text.isEmpty { MessageContent(source: message.text).equatable() }
            attachments
            if let error = message.error { warning(error) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var attachments: some View {
        ForEach(message.attachments ?? []) { file in
            if file.mimeType.hasPrefix("image/") {
                ChatImage(name: file.name, identity: file.id) { try await client.downloadFile(file) }
            } else {
                Button {
                    Task { previewURL = await client.previewFile(file) }
                } label: {
                    FileChip(icon: file.icon, name: file.name, detail: file.sizeLabel)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L("Open \(file.name)"))
            }
        }
    }

    private func warning(_ error: String) -> some View {
        Text(UserFacingError.text(error))
            .font(AppTypography.meta)
            .foregroundStyle(AppTheme.warning)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
    }

    private func withTime(_ text: String) -> String {
        [text, message.time].compactMap { $0 }.joined(separator: " · ")
    }
}

/// Status, captions and times: the meta size in the secondary colour with tabular figures.
private struct MetaLine: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(AppTypography.meta)
            .foregroundStyle(AppTheme.secondaryText)
            .monospacedDigit()
    }
}

/// A message on its way: the same bubble as a sent one, so delivery changes nothing on screen.
struct PendingMessageBubble: View {
    let text: String
    var files: [PickedFile] = []
    let bubbleWidth: CGFloat

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            if !text.isEmpty { ChatBubble(text: text) }
            ForEach(files) { file in
                if file.mimeType.hasPrefix("image/"), let image = ChatMedia.thumbnail(file.data, maxPixels: 640) {
                    ChatPicture(image: image).accessibilityLabel(file.name)
                } else {
                    FileChip(icon: "doc", name: file.name, detail: ByteCountFormatter.string(fromByteCount: Int64(file.data.count), countStyle: .file))
                }
            }
        }
        .frame(maxWidth: bubbleWidth, alignment: .trailing)
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

/// The helper: one character at the "now" edge of the conversation. Still while idle,
/// it proofs like rising dough while the employee works and plops once when a reply lands.
struct ConversationHelper: View {
    @EnvironmentObject private var client: HomeClient
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var textSize
    #if os(macOS)
    @Environment(\.appearsActive) private var appearsActive
    #else
    @Environment(\.scenePhase) private var scenePhase
    #endif
    @State private var awaitingReply = false
    @State private var landings = 0

    private var working: Bool { client.isSending && client.interactions.isEmpty }
    private var windowIsActive: Bool {
        #if os(macOS)
        appearsActive
        #else
        scenePhase == .active
        #endif
    }
    private var reply: ReplyMark {
        ReplyMark(conversation: HomeDrafts.key(home: client.baseURLString, profile: client.selectedProfileID, chat: client.selectedChatID),
                  id: client.messages.last { $0.direction == "outbound" }?.id)
    }

    var body: some View {
        let name = client.activeAgentName
        HStack(spacing: 12) {
            character
            if working {
                Text(textSize.isAccessibilitySize ? L("Готовим ответ…") : L("\(name) is working"))
                    .modifier(MetaLine())
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // The helper sits at the edge where the employee's replies start, so Russian or English
        // replies in the Hebrew interface keep it under their first letters.
        .paragraphDirection(of: client.messages.last { $0.direction == "outbound" }?.text ?? "")
        .animation(.easeInOut(duration: 0.15), value: working)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("\(name) is working"))
        .accessibilityHidden(!working)
        .onAppear { awaitingReply = working }
        .onChange(of: working) { _, now in if now { awaitingReply = true } }
        .onChange(of: reply) { old, new in
            defer { awaitingReply = working }
            guard old.conversation == new.conversation, new.id != old.id, new.id != nil, awaitingReply else { return }
            landings += 1
        }
        #if os(iOS)
        .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.5), trigger: landings)
        #endif
    }

    private var character: some View {
        let avatar = AgentAvatar(appearance: client.activeAppearance, size: AvatarSize.toolbar)
        let still = reduceMotion
        return Group {
            if working && windowIsActive && !still {
                avatar.phaseAnimator([false, true]) { view, risen in
                    view.scaleEffect(x: risen ? 1.03 : 1, y: risen ? 0.95 : 1, anchor: .bottom)
                } animation: { _ in .easeInOut(duration: 0.9) }
            } else {
                avatar
            }
        }
        .keyframeAnimator(initialValue: 1.0, trigger: landings) { view, height in
            view.scaleEffect(x: 1, y: still ? 1 : height, anchor: .bottom)
        } keyframes: { _ in
            LinearKeyframe(0.86, duration: 0.09)
            SpringKeyframe(1, spring: Spring(response: 0.35, dampingRatio: 0.55))
        }
        .offlineCharacter(client.isOffline(client.activeProfile))
    }
}

private struct ReplyMark: Equatable {
    let conversation: String
    let id: String?
}

/// An approval or question from the employee: a surface card with one prominent action.
struct InteractionCard: View {
    @EnvironmentObject private var client: HomeClient
    @Environment(\.openURL) private var openURL
    let interaction: ChatInteraction
    @State private var answers: [String: String] = [:]
    @State private var busy = false
    @State private var error: String?

    private var needsContinue: Bool {
        interaction.questions.count > 1 || interaction.questions.first?.options.isEmpty == true
    }

    var body: some View {
        // Groups 16 apart; a question sits 8 above its answer; the card's padding is 16.
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(interaction.title).font(AppTypography.interface.weight(.semibold))
                if let detail = interaction.detail, !detail.isEmpty {
                    Text(detail).font(AppTypography.interface).foregroundStyle(AppTheme.secondaryText).textSelection(.enabled)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            if let raw = interaction.url, let url = URL(string: raw) {
                Button(L("Открыть подключение"), systemImage: "arrow.up.forward") { openURL(url) }
                    .buttonStyle(CardButtonStyle(prominent: interaction.questions.isEmpty))
            }
            ForEach(interaction.questions) { question in
                VStack(alignment: .leading, spacing: 8) {
                    if !question.question.isEmpty { Text(question.question).font(AppTypography.interface) }
                    if question.options.isEmpty {
                        TextField(L("Ваш ответ"), text: Binding(get: { answers[question.id] ?? "" }, set: { answers[question.id] = $0 }))
                            .textFieldStyle(.roundedBorder)
                            .accessibilityLabel(question.question.isEmpty ? L("Ваш ответ") : question.question)
                            .frame(minHeight: controlTarget)
                    } else {
                        // Short choices sit side by side; long ones stack.
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 8) { options(for: question) }
                            VStack(alignment: .leading, spacing: 8) { options(for: question) }
                        }
                    }
                }
            }
            if needsContinue || busy || error != nil {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 12) {
                        if needsContinue {
                            Button(L("Продолжить")) { submit() }
                                .buttonStyle(CardButtonStyle(prominent: true))
                                .disabled(busy || interaction.questions.contains { (answers[$0.id] ?? "").isEmpty })
                        }
                        if busy { ProgressView().controlSize(.small) }
                    }
                    if let error { Text(UserFacingError.text(error)).font(AppTypography.meta).foregroundStyle(AppTheme.warning) }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .chatSurface(AppTheme.surface, radius: Radius.card)
    }

    private func options(for question: ChatQuestion) -> some View {
        ForEach(question.options, id: \.self) { option in
            let chosen = interaction.questions.count > 1 && answers[question.id] == option
            Button {
                answers[question.id] = option
                if interaction.questions.count == 1 { submit() }
            } label: {
                HStack(spacing: 8) {
                    if chosen { Image(systemName: "checkmark").font(AppTypography.meta.weight(.semibold)) }
                    Text(option).fixedSize(horizontal: false, vertical: true)
                }
            }
            .buttonStyle(CardButtonStyle(prominent: false))
            .accessibilityAddTraits(chosen ? .isSelected : [])
            .disabled(busy)
        }
    }

    private func submit() {
        busy = true; error = nil
        Task {
            do { try await client.answer(interaction, answers: answers) }
            catch { self.error = error.localizedDescription }
            busy = false
        }
    }
}

/// The transcript rows: earlier history, messages, pending sends, approvals, status and the helper.
/// Rhythm: 32 between turns, 12 between messages from the same side, 48 above a time heading
/// and 16 below it (none above the first), 12 above the helper.
struct TranscriptRows: View {
    @EnvironmentObject private var client: HomeClient
    let proxy: ScrollViewProxy
    @Binding var followsLatest: Bool
    @State private var columnWidth = Layout.column
    // Read live from the client so a history load notices a conversation switch.
    private var draftKey: String { HomeDrafts.key(home: client.baseURLString, profile: client.selectedProfileID, chat: client.selectedChatID) }

    private static let turn: CGFloat = 32
    private static let sameSide: CGFloat = 12
    private static let cluster: CGFloat = 48

    var body: some View {
        let rows = MessagePages.rows(client.messages)
        let pending = client.visiblePendingMessages
        let shared = client.activeTelegramGroup != nil || MessagePages.isMultiAuthor(client.messages)
        let bubbleWidth = (columnWidth * 0.75).rounded()
        let start: CGFloat = client.hasEarlierMessages ? Self.sameSide : 0
        // The side of the last item so far: person (inbound) or employee.
        let lastIsPerson = pending.isEmpty ? rows.last?.message.direction == "inbound" : true
        TranscriptStack {
            if client.hasEarlierMessages { loadEarlier }
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                // Keep one stable layout node per message, including its optional time heading.
                VStack(alignment: .leading, spacing: 16) {
                    if let header = row.header { ClusterHeader(date: header, hasTime: row.message.hasTime) }
                    MessageBubble(message: row.message, shared: shared, bubbleWidth: bubbleWidth, headed: row.header != nil)
                        #if os(macOS)
                        .help(exactTime(row.message))
                        #endif
                }
                .padding(.top, index == 0 ? start : row.header != nil ? Self.cluster : row.startsTurn ? Self.turn : Self.sameSide)
                .id(row.id)
                .accessibilityElement(children: .contain)
                .accessibilityValue(exactTime(row.message))
            }
            ForEach(Array(pending.enumerated()), id: \.element.id) { index, message in
                let afterPerson = index > 0 || rows.last?.message.direction == "inbound"
                let opens = index == 0 && MessagePages.opensCluster(.now, after: rows.last?.message.sentAt)
                VStack(alignment: .trailing, spacing: 4) {
                    if opens { ClusterHeader(date: .now, hasTime: true).padding(.bottom, 12) }
                    PendingMessageBubble(text: message.text, files: message.files, bubbleWidth: bubbleWidth)
                    if let error = message.error {
                        Text(UserFacingError.text(error)).modifier(MetaLine()).foregroundStyle(AppTheme.warning)
                            .multilineTextAlignment(.trailing).padding(.trailing, 16)
                        if message.operationID == nil {
                            Button(L("Проверить доставку и повторить")) { Task { await client.retry(message) } }
                                .modifier(StatusAction())
                        }
                    } else if let delivery = message.deliveryState {
                        Text(delivery == "waiting_for_device" ? L("Сообщение сохранено. Ждём подключения устройства.") : L("Сообщение сохранено. Передаём сотруднику."))
                            .modifier(MetaLine()).multilineTextAlignment(.trailing).padding(.trailing, 16)
                        if client.canManageOpenAI {
                            Button(L("Отменить доставку")) { Task { await client.cancelPending(message) } }
                                .modifier(StatusAction())
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.top, rows.isEmpty && index == 0 ? start : opens ? Self.cluster : afterPerson ? Self.sameSide : Self.turn)
                .id(message.id)
            }
            ForEach(Array(client.interactions.enumerated()), id: \.element.id) { index, interaction in
                InteractionCard(interaction: interaction)
                    .padding(.top, index == 0 && lastIsPerson ? Self.turn : Self.sameSide)
                    .id(interaction.id)
            }
            if let error = client.syncError {
                Text(UserFacingError.text(error)).modifier(MetaLine()).foregroundStyle(AppTheme.warning)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, Self.sameSide)
            }
            ConversationHelper()
                .padding(.top, 12)
                .id("conversation-helper")
            // Scrolling to the latest message keeps a turn's worth of room under the helper.
            Color.clear.frame(height: 24).id("conversation-bottom")
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { columnWidth = $0 }
    }

    private var loadEarlier: some View {
        Button {
            let anchor = client.messages.first?.id
            let conversation = draftKey
            followsLatest = false
            Task {
                await client.loadEarlierMessages()
                await Task.yield()
                guard conversation == draftKey, let anchor else { return }
                proxy.scrollTo(anchor, anchor: .top)
            }
        } label: {
            HStack(spacing: 8) {
                if client.isLoadingEarlier { ProgressView().controlSize(.mini) }
                Text(client.isLoadingEarlier ? L("Загружаем историю…") : L("Показать более ранние сообщения"))
            }
            .modifier(MetaLine())
            .frame(minHeight: controlTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(client.isLoadingEarlier)
        .frame(maxWidth: .infinity)
    }

    private func exactTime(_ message: HomeMessage) -> String {
        message.sentAt.map { ChatClock.exact($0, hasTime: message.hasTime) } ?? ""
    }
}

/// Card actions at one height and radius. The one prominent action is ink with a canvas-coloured
/// label; the others are a quiet tint of the text colour. Neither changes with window focus.
private struct CardButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    let prominent: Bool

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
        configuration.label
            .font(AppTypography.interface.weight(.medium))
            .labelStyle(CardButtonLabel())
            .foregroundStyle(label)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .frame(minHeight: controlTarget)
            .background(fill(pressed: configuration.isPressed), in: shape)
            .contentShape(shape)
    }

    private var label: AnyShapeStyle {
        guard isEnabled else { return AnyShapeStyle(.tertiary) }
        return prominent ? AnyShapeStyle(AppTheme.canvas) : AnyShapeStyle(.primary)
    }

    private func fill(pressed: Bool) -> AnyShapeStyle {
        guard isEnabled else { return AnyShapeStyle(.primary.opacity(0.06)) }
        if prominent { return AnyShapeStyle(pressed ? AppTheme.accentText.mix(with: AppTheme.canvas, by: 0.25) : AppTheme.accentText) }
        return AnyShapeStyle(.primary.opacity(pressed ? 0.14 : 0.08))
    }
}

/// An icon and its label: 8 apart.
private struct CardButtonLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) { configuration.icon; configuration.title }
    }
}

/// A quiet action under a pending message: retry or cancel delivery.
private struct StatusAction: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(AppTypography.meta.weight(.medium))
            .foregroundStyle(AppTheme.accentText)
            .buttonStyle(.plain)
            .frame(minHeight: controlTarget)
            .padding(.trailing, 16)
    }
}
