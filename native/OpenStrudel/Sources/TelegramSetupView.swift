import SwiftUI

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

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                if !contextual { Text(L("Telegram на «\(client.executionDeviceName)»")).font(.headline) }
                Spacer()
                if client.telegram?.configured == true && !contextual {
                    Menu {
                        Button(L("Проверить связь"), action: checkConnection).disabled(checking)
                        Button(L("Отключить бота…"), role: .destructive) { confirmDisconnect = true }
                    } label: { Image(systemName: "ellipsis.circle") }.menuIndicator(.hidden).accessibilityLabel(L("Настройки бота Telegram"))
                }
            }
            if client.telegram?.configured == true {
                if !contextual {
                    Label(client.telegram?.connectionError != nil ? L("Telegram недоступен") : L("Бот подключён"), systemImage: client.telegram?.connectionError != nil ? "wifi.exclamationmark" : "checkmark.circle.fill").foregroundStyle(AppTheme.accent)
                }
                if let name = client.telegram?.botUsername { Text("@" + name).font(.callout).textSelection(.enabled) }
                if linked {
                    ForEach(privateChats) { chat in
                        let name = client.profiles.first(where: { $0.id == chat.profileId })?.name ?? L("Общий помощник")
                        Text(L("В Telegram отвечает \(name)")).font(.callout).foregroundStyle(AppTheme.secondaryText)
                    }
                } else if !contextual {
                    Text(L("Подтвердите свой Telegram, чтобы писать боту и добавлять его в группы."))
                        .font(.callout).foregroundStyle(AppTheme.secondaryText)
                }
                if let problem = client.telegram?.lastError {
                    Text(UserFacingError.text(problem)).font(.callout).foregroundStyle(AppTheme.destructive)
                } else if client.telegram?.running != true {
                    Text(L("Бот остановлен. Проверьте, что OpenStrudel работает на этом устройстве.")).font(.callout).foregroundStyle(AppTheme.secondaryText)
                }
                if !contextual && (checking || checked || client.telegram?.connectionError != nil || client.telegram?.lastError != nil || client.telegram?.running != true) { HStack {
                    Button(checking ? L("Проверяем…") : L("Проверить связь"), action: checkConnection)
                        .disabled(checking).accessibilityIdentifier("checkTelegramConnection")
                    if checking { ProgressView().controlSize(.small) }
                    else if checked && client.telegram?.connectionError == nil { Text(L("Telegram отвечает")).font(.caption).foregroundStyle(AppTheme.secondaryText) }
                } }
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
                }.buttonStyle(.borderedProminent).disabled(linking).accessibilityIdentifier("openPersonalTelegram")
                if linked && !contextual {
                    if let name = client.telegram?.botUsername, let url = URL(string: "https://t.me/" + name + "?startgroup=choose") {
                        Button { openTelegram(url) } label: { Label(L("Добавить бота в группу"), systemImage: "person.2.badge.plus") }
                            .buttonStyle(.bordered).accessibilityIdentifier("addTelegramGroup")
                    }
                    Text(L("Добавьте бота в группу и упомяните его. Он ответит сам или подключит подходящего сотрудника."))
                        .font(.callout).foregroundStyle(AppTheme.secondaryText).fixedSize(horizontal: false, vertical: true)
                }
                if client.telegramLink != nil && !linked {
                    Text(L("Нажмите «Начать» в Telegram. Здесь появится подтверждение подключения.")).font(.caption).foregroundStyle(AppTheme.secondaryText)
                }
            } else {
                Text(L("1. Откройте BotFather и создайте бота командой /newbot."))
                    .font(.callout).fixedSize(horizontal: false, vertical: true)
                Button(L("Открыть BotFather")) { openTelegram(URL(string: "https://t.me/BotFather")!) }
                Text(L("2. Скопируйте выданный ключ и вставьте сюда.")).font(.callout)
                SecureField(L("Ключ бота из BotFather"), text: $token).textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("telegramBotToken")
                Button {
                    busy = true; error = nil
                    Task {
                        do { try await client.configureTelegram(token: token); token = "" }
                        catch { self.error = UserFacingError.text(error.localizedDescription) }
                        busy = false
                    }
                } label: {
                    HStack { if busy { ProgressView().controlSize(.small) }; Text(busy ? L("Проверяем бота…") : L("Подключить бота")) }
                }.buttonStyle(.borderedProminent).disabled(busy || token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("connectTelegramBot")
                Text(L("Ключ хранится на устройстве сотрудника. Используйте отдельного бота для каждого устройства."))
                    .font(.caption).foregroundStyle(AppTheme.secondaryText).fixedSize(horizontal: false, vertical: true)
            }
            if let error { Text(L10n.serviceText(error)).font(.callout).foregroundStyle(AppTheme.destructive) }
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

    private func checkConnection() {
        checking = true; checked = false; error = nil
        Task {
            defer { checking = false }
            do { try await client.checkTelegramConnection(); checked = client.telegram?.connectionError == nil }
            catch { self.error = UserFacingError.text(error.localizedDescription) }
        }
    }
}
