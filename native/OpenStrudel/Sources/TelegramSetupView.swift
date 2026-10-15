import SwiftUI

/// The Telegram section of Settings › Accounts and the details sheet. Until a bot is connected, the footer
/// says where its token is kept.
struct TelegramSetupSection: View {
    @EnvironmentObject private var client: HomeClient

    var body: some View {
        Section {
            TelegramSetupView()
        } header: {
            Text(L("Telegram на «\(client.executionDeviceName)»"))
        } footer: {
            if client.telegram?.configured != true {
                Text(L("Ключ хранится на устройстве сотрудника. Используйте отдельного бота для каждого устройства."))
            }
        }
    }
}

struct TelegramSetupView: View {
    @EnvironmentObject private var client: HomeClient
    @Environment(\.openURL) private var openURL
    var contextual = false
    @State private var token = ""
    @State private var busy = false
    @State private var error: String?
    @State private var linking = false
    @State private var checking = false
    @State private var checked = false
    @State private var confirmDisconnect = false
    private var privateChats: [TelegramChat] { (client.telegram?.chats ?? []).filter(\.isPairedOwner) }
    private var linked: Bool { !privateChats.isEmpty }
    /// The bot belongs to one device; its private chat can be answered only by that device's employees.
    private var deviceEmployees: [EmployeeProfile] {
        let device = client.activeProfile?.deviceId ?? client.health?.nodeId
        return client.profiles.filter { $0.deviceId == nil || $0.deviceId == device }
    }

    /// Rows only: TelegramSetupSection wraps them in a Form section.
    var body: some View {
        Group {
            if client.telegram?.configured == true { configuredRows } else { setupRows }
            if let error { Text(L10n.serviceText(error)).foregroundStyle(AppTheme.warning) }
            if client.telegram?.configured == true && !contextual {
                Button(L("Отключить бота…"), role: .destructive) { confirmDisconnect = true }
                    .foregroundStyle(AppTheme.destructive)
            }
        }
        .task { if !contextual { await client.loadChatSettings() } }
        .confirmationDialog(L("Отключить бота?"), isPresented: $confirmDisconnect, titleVisibility: .visible) {
            Button(L("Отключить"), role: .destructive) {
                Task {
                    await client.disconnectTelegram()
                    if let problem = client.errorMessage { error = UserFacingError.text(problem); client.errorMessage = nil }
                }
            }
            Button(L("Отмена"), role: .cancel) {}
        } message: { Text(L("Бот перестанет отвечать в личном чате и группах. Сотрудники и переписка сохранятся.")) }
        .task(id: client.normalizedBaseURL) {
            guard !contextual else { return }
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(5)) } catch { return }
                await client.loadChatSettings()
            }
        }
    }

    @ViewBuilder private var configuredRows: some View {
        let unavailable = client.telegram?.connectionError != nil
        LabeledContent {
            if let name = client.telegram?.botUsername {
                Text("@" + name).foregroundStyle(AppTheme.secondaryText).textSelection(.enabled)
            }
        } label: {
            Label {
                Text(unavailable ? L("Telegram недоступен") : L("Бот подключён"))
            } icon: {
                Image(systemName: unavailable ? "wifi.exclamationmark" : "checkmark.circle.fill")
                    .foregroundStyle(unavailable ? AppTheme.warning : AppTheme.accentText)
            }
        }
        if linked {
            ForEach(privateChats) { chat in
                // The owner chooses once the device has an employee; otherwise the row only says who answers.
                if client.canChooseTelegramResponder && !deviceEmployees.isEmpty {
                    Picker(L("Личный чат"), selection: Binding(get: { chat.profileId }, set: { bind(chat, to: $0) })) {
                        Text(L("Общий помощник")).tag(String?.none)
                        ForEach(deviceEmployees) { Text($0.name).tag(Optional($0.id)) }
                    }
                    .disabled(busy).accessibilityIdentifier("telegramResponder-" + chat.chatId)
                } else {
                    let name = client.profiles.first(where: { $0.id == chat.profileId })?.name ?? L("Общий помощник")
                    Text(L("В Telegram отвечает \(name)")).foregroundStyle(AppTheme.secondaryText)
                }
            }
        } else if !contextual {
            Text(L("Подтвердите свой Telegram, чтобы писать боту и добавлять его в группы."))
                .foregroundStyle(AppTheme.secondaryText)
        }
        if let problem = client.telegram?.lastError {
            Text(UserFacingError.text(problem)).foregroundStyle(AppTheme.warning)
        } else if client.telegram?.running != true {
            Text(L("Бот остановлен. Проверьте, что OpenStrudel работает на этом устройстве.")).foregroundStyle(AppTheme.secondaryText)
        }
        Button(linking ? L("Открываем Telegram…") : linked ? L("Написать боту") : L("Связать мой Telegram")) {
            linking = true; error = nil
            Task {
                if linked, let name = client.telegram?.botUsername, let url = URL(string: "https://t.me/" + name) {
                    openTelegram(url)
                } else {
                    await client.createTelegramLink()
                    if let url = client.telegramLink?.url { openTelegram(url) }
                    else { error = client.errorMessage; client.errorMessage = nil }
                }
                linking = false
            }
        }
        .disabled(linking).accessibilityIdentifier("openPersonalTelegram")
        if client.telegramLink != nil && !linked {
            Text(L("Нажмите «Начать» в Telegram. Здесь появится подтверждение подключения."))
                .font(AppTypography.meta).foregroundStyle(AppTheme.secondaryText)
        }
        if linked && !contextual, let name = client.telegram?.botUsername, let url = URL(string: "https://t.me/" + name + "?startgroup=choose") {
            LabeledContent {
                Button(L("Добавить бота в группу")) { openTelegram(url) }
                    .accessibilityIdentifier("addTelegramGroup")
            } label: {
                Text(L("Добавьте бота в группу и упомяните его. Он ответит сам или подключит подходящего сотрудника."))
            }
        }
        if !contextual {
            HStack(spacing: 8) {
                Button(checking ? L("Проверяем…") : L("Проверить связь"), action: checkConnection)
                    .disabled(checking).accessibilityIdentifier("checkTelegramConnection")
                Spacer(minLength: 0)
                if checking { ProgressView().controlSize(.small) }
                else if checked && client.telegram?.connectionError == nil {
                    Text(L("Telegram отвечает")).font(AppTypography.meta).foregroundStyle(AppTheme.secondaryText)
                }
            }
        }
    }

    @ViewBuilder private var setupRows: some View {
        LabeledContent {
            Button(L("Открыть BotFather")) { openTelegram(URL(string: "https://t.me/BotFather")!) }
        } label: {
            Text(L("1. Откройте BotFather и создайте бота командой /newbot."))
        }
        Text(L("2. Скопируйте выданный ключ и вставьте сюда."))
        // A labelled field, like the backup password: the label leads, the prompt sits in the field.
        SecureField(L("Ключ бота"), text: $token, prompt: Text(L("Из BotFather")))
            .accessibilityIdentifier("telegramBotToken")
        HStack(spacing: 8) {
            Button(busy ? L("Проверяем бота…") : L("Подключить бота")) {
                busy = true; error = nil
                Task {
                    do { try await client.configureTelegram(token: token); token = "" }
                    catch { self.error = UserFacingError.text(error.localizedDescription) }
                    busy = false
                }
            }
            .disabled(busy || token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityIdentifier("connectTelegramBot")
            Spacer(minLength: 0)
            if busy { ProgressView().controlSize(.small) }
        }
    }

    private func openTelegram(_ webURL: URL) {
        let openInBrowser: @MainActor @Sendable () -> Void = {
            openURL(webURL) { @Sendable accepted in
                Task { @MainActor in
                    if !accepted { error = L("Не удалось открыть Telegram. Попробуйте ещё раз.") }
                }
            }
        }
        if let nativeURL = TelegramLink.nativeURL(for: webURL) {
            // Launch Services calls back on its own queue on macOS. Keep the
            // callback nonisolated, then return to the UI actor explicitly.
            openURL(nativeURL) { @Sendable accepted in
                Task { @MainActor in if !accepted { openInBrowser() } }
            }
        } else {
            openInBrowser()
        }
    }

    private func bind(_ chat: TelegramChat, to profileID: String?) {
        busy = true; error = nil
        Task {
            await client.bindTelegram(chatID: chat.chatId, profileID: profileID)
            if let problem = client.errorMessage { error = UserFacingError.text(problem); client.errorMessage = nil }
            busy = false
        }
    }

    private func checkConnection() {
        checking = true; checked = false; error = nil
        Task {
            defer { checking = false }
            do { try await client.checkTelegramConnection(); checked = client.telegram?.connectionError == nil }
            catch { self.error = UserFacingError.text(error.localizedDescription) }
        }
    }
}
