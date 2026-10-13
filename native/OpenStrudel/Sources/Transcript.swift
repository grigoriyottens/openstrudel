import SwiftUI
import QuickLook

struct EmptyChat: View {
    @EnvironmentObject private var library: DeviceLibrary
    @EnvironmentObject private var client: HomeClient
    @Environment(\.dynamicTypeSize) private var textSize
    var body: some View {
        VStack(spacing: 12) {
            AgentAvatar(appearance: client.activeAppearance, size: 72)
            Text(client.isEmployeeDraft ? L("Создайте сотрудника") : client.activeProfile?.name ?? L("Напишите, что нужно"))
                .font(AppTypography.emptyTitle)
            if client.isEmployeeDraft {
                Text(L("Напишите, чем он должен заниматься. Например: «Редактор, который помогает писать короткие посты»."))
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.secondaryText)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 360)
                if library.employeeDestinations.count > 1 {
                    Menu {
                        EmployeeDestinationChoices { destination in
                            library.chooseEmployeeDevice(destination.client, deviceID: destination.deviceID)
                        }
                    } label: {
                        Label(L("Create on \(client.executionDeviceName)"), systemImage: "desktopcomputer")
                            .font(.callout).fixedSize(horizontal: false, vertical: true)
                            .frame(minHeight: controlTarget)
                    }
                    #if os(macOS)
                    .menuStyle(.borderedButton)
                    #else
                    .buttonStyle(.bordered)
                    #endif
                    .padding(.top, 8)
                    .accessibilityLabel(L("Где будет работать сотрудник"))
                    .accessibilityValue(client.executionDeviceName)
                    .accessibilityIdentifier("employeeCreationDevice")
                } else {
                    Text(L("Works on “\(client.executionDeviceName)”."))
                        .font(.callout).foregroundStyle(AppTheme.secondaryText)
                        .multilineTextAlignment(.center)
                }
            } else if client.homeUnreachable || client.connectionNeedsPairing {
                Text(L("История появится после подключения к устройству."))
                    .font(.subheadline).foregroundStyle(AppTheme.secondaryText).multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
            } else if let profile = client.activeProfile {
                Text(profile.roleText.isEmpty ? L("Напишите, что нужно.") : profile.roleText)
                    .font(.subheadline).foregroundStyle(AppTheme.secondaryText).multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Messages fade out under the header and above the composer instead of being cut.
struct EdgeFade: View {
    var body: some View {
        VStack(spacing: 0) {
            LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom).frame(height: 18)
            Color.black
            LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom).frame(height: 18)
        }
    }
}

struct DayDivider: View {
    let date: Date

    var body: some View {
        Text(ChatClock.day(date))
            .font(.caption.weight(.medium))
            .foregroundStyle(AppTheme.secondaryText)
            .frame(maxWidth: .infinity)
            .padding(.top, 6)
            .accessibilityAddTraits(.isHeader)
    }
}

struct MessageBubble: View {
    @EnvironmentObject private var client: HomeClient
    @State private var previewURL: URL?
    let message: HomeMessage
    private var isUser: Bool { message.direction == "inbound" }

    var body: some View {
        if let scheduleTitle = message.scheduleTitle {
            VStack(alignment: .leading, spacing: 4) {
                Label(withTime(scheduleTitle), systemImage: "clock")
                    .font(.caption).foregroundStyle(AppTheme.secondaryText)
                if let error = message.error { Text(UserFacingError.text(error)).font(.caption).foregroundStyle(AppTheme.warning) }
            }.padding(.vertical, 4)
        } else if message.kind == "notice" {
            Label(withTime(L10n.text(message.text)), systemImage: "checkmark")
                .font(.caption).foregroundStyle(AppTheme.secondaryText).padding(.vertical, 4)
        } else {
            HStack(alignment: .bottom) {
                if isUser { Spacer(minLength: 44) }
                VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                    if message.imported == true, let author = message.author {
                        Text(author).font(.caption).foregroundStyle(AppTheme.secondaryText).padding(.horizontal, 6)
                    }
                    VStack(alignment: .leading, spacing: 9) {
                        if isUser && !message.text.isEmpty {
                            if message.imported == true { ImportedMessageText(source: message.text) }
                            else {
                                Text(message.text).font(ChatTypography.body)
                                    .lineSpacing(4).textSelection(.enabled)
                            }
                        }
                        else if !isUser { MessageContent(source: message.text).equatable() }
                        ForEach(message.attachments ?? []) { file in
                            if file.mimeType.hasPrefix("image/") {
                                ChatImage(name: file.name, identity: file.id) { try await client.downloadFile(file) }
                            } else {
                            Button {
                                Task { previewURL = await client.previewFile(file) }
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: file.icon).font(.title3).foregroundStyle(AppTheme.secondaryText)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(file.name).font(.callout.weight(.medium)).lineLimit(2)
                                        Text(file.sizeLabel).font(.caption).foregroundStyle(AppTheme.secondaryText)
                                    }
                                    Spacer(minLength: 8)
                                    Image(systemName: "arrow.down").font(.caption).foregroundStyle(.tertiary)
                                }.padding(10).background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 11))
                            }.buttonStyle(.plain).accessibilityLabel(L("Open \(file.name)"))
                            }
                        }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 11)
                    .background(.primary.opacity(isUser ? 0.10 : 0.045), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    if let error = message.error { Text(UserFacingError.text(error)).font(.caption).foregroundStyle(AppTheme.warning).textSelection(.enabled) }
                    if !meta.isEmpty {
                        Text(meta).font(.caption2).foregroundStyle(AppTheme.secondaryText).monospacedDigit().padding(.horizontal, 6)
                    }
                }
                if !isUser { Spacer(minLength: 12) }
            }
            .fixedSize(horizontal: false, vertical: true)
            .quickLookPreview($previewURL)
            .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
        }
    }

    private var meta: String {
        [message.status == "queued" ? L("В очереди") : nil, message.time].compactMap { $0 }.joined(separator: " · ")
    }

    private func withTime(_ text: String) -> String {
        [text, message.time].compactMap { $0 }.joined(separator: " · ")
    }
}

struct PendingMessageBubble: View {
    let text: String
    var files: [PickedFile] = []

    var body: some View {
        HStack {
            Spacer(minLength: 44)
            VStack(alignment: .leading, spacing: 8) {
                if !text.isEmpty { Text(text) }
                ForEach(files) { file in
                    if file.mimeType.hasPrefix("image/"), let image = ChatMedia.thumbnail(file.data, maxPixels: 600) {
                        Image(decorative: image, scale: 1).resizable().scaledToFit().frame(maxWidth: 280, maxHeight: 220)
                            .clipShape(RoundedRectangle(cornerRadius: 12)).accessibilityLabel(file.name)
                    } else { Label(file.name, systemImage: "doc").font(.callout).lineLimit(2) }
                }
            }
                .font(ChatTypography.body)
                .lineSpacing(4)
                .foregroundStyle(.primary)
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
                .background(.primary.opacity(0.10), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

struct ThinkingBubble: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var textSize
    let name: String
    let appearance: AgentAppearance?

    var body: some View {
        HStack {
            HStack(spacing: 8) {
                AgentAvatar(appearance: appearance, size: 24)
                ProgressView().controlSize(.small).dynamicTypeSize(.medium).accessibilityHidden(true)
                Text(textSize.isAccessibilitySize ? L("Готовим ответ…") : L("\(name) is working"))
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.secondaryText)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            .accessibilityElement(children: .ignore).accessibilityLabel(L("\(name) is working"))
            Spacer(minLength: textSize.isAccessibilitySize ? 0 : 80)
        }
        .transition(.opacity)
    }
}

struct InteractionCard: View {
    @EnvironmentObject private var client: HomeClient
    @Environment(\.openURL) private var openURL
    let interaction: ChatInteraction
    @State private var answers: [String: String] = [:]
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(interaction.title).font(.headline)
            if let detail = interaction.detail, !detail.isEmpty {
                Text(detail).font(.subheadline).foregroundStyle(AppTheme.secondaryText).textSelection(.enabled)
            }
            if let raw = interaction.url, let url = URL(string: raw) {
                Button(L("Открыть подключение"), systemImage: "arrow.up.right") { openURL(url) }
                    .buttonStyle(.bordered)
            }
            ForEach(interaction.questions) { question in
                if !question.question.isEmpty { Text(question.question).font(.subheadline) }
                if question.options.isEmpty {
                    TextField(L("Ваш ответ"), text: Binding(get: { answers[question.id] ?? "" }, set: { answers[question.id] = $0 }))
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel(question.question.isEmpty ? L("Ваш ответ") : question.question)
                        .frame(minHeight: controlTarget)
                } else {
                    // Short choices sit side by side; long ones stack.
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 8) { options(for: question) }
                        VStack(alignment: .leading, spacing: 6) { options(for: question) }
                    }
                }
            }
            if interaction.questions.count > 1 || interaction.questions.first?.options.isEmpty == true {
                Button(L("Продолжить")) { submit() }
                    .disabled(busy || interaction.questions.contains { (answers[$0.id] ?? "").isEmpty })
            }
            if busy { ProgressView().controlSize(.small) }
            if let error { Text(UserFacingError.text(error)).font(.caption).foregroundStyle(AppTheme.warning) }
        }
        .padding(18).frame(maxWidth: 480, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))
        .overlay { RoundedRectangle(cornerRadius: 20).stroke(.primary.opacity(0.08)) }
        .padding(.vertical, 8)
    }
    private func options(for question: ChatQuestion) -> some View {
        ForEach(question.options, id: \.self) { option in
            Button {
                answers[question.id] = option
                if interaction.questions.count == 1 { submit() }
            } label: {
                HStack {
                    Text(option).fixedSize(horizontal: false, vertical: true)
                    if interaction.questions.count > 1 && answers[question.id] == option { Image(systemName: "checkmark") }
                }.frame(minHeight: controlTarget)
            }.buttonStyle(.bordered).disabled(busy)
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
