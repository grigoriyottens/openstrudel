import SwiftUI

struct SectionTitle: View {
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.headline)
            Text(subtitle).font(.caption).foregroundStyle(AppTheme.secondaryText)
        }
        .padding(.top, 8)
    }
}

struct OpenAISettingsCard: View {
    @EnvironmentObject private var client: HomeClient
    @Environment(\.openURL) private var openURL
    @State private var copiedCode = false
    var showIdentity = true

    var body: some View {
        if showIdentity { content.settingsCard() }
        else { content }
    }

    private var content: some View {
        let connected = client.openAIAccount?.connected == true
        return VStack(alignment: .leading, spacing: 16) {
            if showIdentity {
            HStack(spacing: 12) {
                AccountBadge(email: client.openAIAccount?.email, size: 36)
                VStack(alignment: .leading, spacing: 3) {
                    if let account = client.openAIAccount, account.connected {
                        Text(account.email ?? "OpenAI").font(.subheadline.weight(.medium))
                            .accessibilityLabel(L("Аккаунт OpenAI")).accessibilityValue(account.email ?? "OpenAI").accessibilityIdentifier("openAIAccountIdentity")
                        Text([account.planLabel, account.categoryLabel].compactMap { $0 }.joined(separator: " · "))
                            .font(.caption).foregroundStyle(AppTheme.secondaryText)
                    } else if client.openAIAccount?.isUnavailable == true {
                        Text(L("Нет связи с OpenAI")).font(.subheadline.weight(.medium))
                        Text(L("Повторный вход пока не нужен")).font(.caption).foregroundStyle(AppTheme.secondaryText)
                    } else {
                        Text(L("Аккаунт не подключён")).font(.subheadline.weight(.medium))
                        Text(L("Войдите в свой аккаунт OpenAI")).font(.caption).foregroundStyle(AppTheme.secondaryText)
                    }
                    if client.openAIAccount?.isUnavailable != true { ConnectionStatus(connected: connected) }
                }
                Spacer()
            }
            }

            if let error = client.openAIErrorMessage {
                Text(UserFacingError.text(error)).font(.callout).foregroundStyle(AppTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if showIdentity && !connected && client.canManageOpenAI {
                Text(client.openAIRecoveryMessage).font(.callout).foregroundStyle(AppTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if client.openAIAccount?.isUnavailable == true && client.openAILogin == nil && !client.openAILoginPending {
                Button { Task { await client.refreshOpenAIAccount(force: true) } } label: {
                    SetupActionLabel(title: L("Проверить ещё раз"), icon: "arrow.clockwise")
                }.adaptiveActionStyle(.glass).controlSize(.large)
                    .accessibilityIdentifier("retryOpenAIAccount")
            } else if !client.canManageOpenAI {
                if showIdentity {
                Text(connected ? L("Используется аккаунт устройства, на котором работает сотрудник.")
                     : client.openAIRecoveryMessage)
                    .font(.callout).foregroundStyle(AppTheme.secondaryText).fixedSize(horizontal: false, vertical: true)
                }
            } else if let login = client.openAILogin {
                VStack(alignment: .leading, spacing: 8) {
                    if login.type == "device", let code = login.userCode {
                        Text(L("Введите этот код на сайте OpenAI")).font(.callout).foregroundStyle(AppTheme.secondaryText)
                        Text(code).font(.system(.title3, design: .monospaced).weight(.semibold)).textSelection(.enabled)
                            .accessibilityLabel(L("Sign-in code: \(code)"))
                            .accessibilityIdentifier("openAIDeviceCode")
                        Button {
                            #if os(macOS)
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(code, forType: .string)
                            #else
                            UIPasteboard.general.string = code
                            #endif
                            copiedCode = true
                        } label: { SetupActionLabel(title: copiedCode ? L("Код скопирован") : L("Скопировать код"), icon: copiedCode ? "checkmark" : "doc.on.doc") }
                            .adaptiveActionStyle(.glass).accessibilityIdentifier("copyOpenAICode")
                        DisclosureGroup(L("Не получается войти?")) {
                            Text(L("В ChatGPT откройте «Настройки», затем «Безопасность» и разрешите вход по коду устройства. Для рабочего аккаунта может понадобиться помощь администратора. Если код истёк, отмените вход здесь и начните снова."))
                                .font(.callout).foregroundStyle(AppTheme.secondaryText).fixedSize(horizontal: false, vertical: true)
                        }.padding(.vertical, 4)
                    } else {
                        Text(L("Откройте страницу OpenAI и завершите вход.")).font(.caption).foregroundStyle(AppTheme.secondaryText)
                    }
                    if let url = login.url {
                        Button { openURL(url) } label: { SetupActionLabel(title: L("Открыть OpenAI"), icon: "arrow.up.right") }
                            .adaptiveActionStyle(.glassProminent).accessibilityIdentifier("reopenOpenAILogin")
                    }
                    Button { Task { await client.cancelOpenAILogin() } } label: {
                        SetupActionLabel(title: L("Отменить вход"))
                    }.adaptiveActionStyle(.glass).controlSize(.large).accessibilityIdentifier("cancelOpenAILogin")
                }
            } else if client.openAILoginPending {
                Text(L("Вход открыт на другом устройстве. Завершите его на сайте OpenAI. Это окно обновится автоматически."))
                    .font(.callout).foregroundStyle(AppTheme.secondaryText).fixedSize(horizontal: false, vertical: true)
            } else if connected {
                Button { Task { await client.beginOpenAILogin() } } label: {
                    SetupActionLabel(title: client.isStartingOpenAILogin ? L("Открываем OpenAI…") : L("Сменить аккаунт"))
                }.adaptiveActionStyle(.glass).controlSize(.large).disabled(client.isStartingOpenAILogin)
            } else if client.canManageOpenAI {
                Button { Task { await client.beginOpenAILogin() } } label: {
                    SetupActionLabel(title: client.isStartingOpenAILogin ? L("Открываем OpenAI…") : L("Войти в OpenAI"), icon: "arrow.up.right")
                }.adaptiveActionStyle(.glassProminent).controlSize(.large)
                    .disabled(client.isStartingOpenAILogin)
                    .accessibilityIdentifier("signInOpenAI")
            }
        }
        .onChange(of: client.openAILogin?.id) { _, _ in copiedCode = false }
    }

}

struct TelegramSettingsCard: View {
    @EnvironmentObject private var client: HomeClient
    @Environment(\.dynamicTypeSize) private var textSize
    @State private var showChats = false
    @State private var confirmDisconnect = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "paperplane.fill").foregroundStyle(AppTheme.secondaryText)
                VStack(alignment: .leading, spacing: 4) {
                    Text(client.telegram?.botUsername.map { "@" + $0 } ?? "Telegram")
                        .font(.subheadline.weight(.medium))
                    if client.telegram?.configured == true { ConnectionStatus(connected: client.telegram?.running == true) }
                }
                Spacer()
            }
            if let telegram = client.telegram, telegram.configured {
                if let url = client.telegramLink?.url {
                    Link(destination: url) { AdaptiveActionLabel(title: L("Открыть Telegram")) }
                        .adaptiveActionStyle(.borderedProminent)
                    Text(L("В Telegram нажмите «Начать», чтобы продолжить разговор."))
                        .font(.callout).foregroundStyle(AppTheme.secondaryText)
                }
                if textSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 8) { telegramActions }
                } else {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 8) { telegramActions.fixedSize(horizontal: true, vertical: false) }
                        VStack(alignment: .leading, spacing: 8) { telegramActions }
                    }
                }
            } else {
                TelegramSetupView()
            }
        }
        .settingsCard()
        .sheet(isPresented: $showChats) { TelegramChatsView() }
        .confirmationDialog(L("Отключить Telegram?"), isPresented: $confirmDisconnect, titleVisibility: .visible) {
            Button(L("Отключить Telegram"), role: .destructive) { Task { await client.disconnectTelegram() } }
            Button(L("Отмена"), role: .cancel) {}
        } message: { Text(L("Сотрудники перестанут отвечать в Telegram. Переписка в OpenStrudel сохранится.")) }
    }

    @ViewBuilder private var telegramActions: some View {
        Button { Task { await client.createTelegramLink() } } label: {
            AdaptiveActionLabel(title: client.telegramLink == nil ? L("Продолжить в Telegram") : L("Обновить приглашение"))
        }
            .font(.body).adaptiveActionStyle(.bordered).controlSize(.large)
        if !(client.telegram?.chats ?? []).isEmpty {
            Button { showChats = true } label: { AdaptiveActionLabel(title: L("Чаты")) }
                .font(.body).adaptiveActionStyle(.bordered).controlSize(.large)
        }
        Button(role: .destructive) { confirmDisconnect = true } label: { AdaptiveActionLabel(title: L("Отключить")) }
            .font(.body).adaptiveActionStyle(.bordered).controlSize(.large)
            .tint(AppTheme.destructive)
    }
}

/// The same quiet status on every connection card.
struct ConnectionStatus: View {
    let connected: Bool

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(connected ? Color.green : Color.secondary.opacity(0.4)).frame(width: 7, height: 7)
                .accessibilityHidden(true)
            Text(connected ? L("Подключён") : L("Не подключён"))
        }
        .font(.caption)
        .foregroundStyle(AppTheme.secondaryText)
    }
}

struct AccountBadge: View {
    let email: String?
    let size: CGFloat

    var body: some View {
        Circle()
            .fill(.primary.opacity(0.14))
            .frame(width: size, height: size)
            .overlay {
                Text(String((email ?? "O").prefix(1)).uppercased())
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(AppTheme.secondaryText)
            }
            .accessibilityHidden(true)
    }
}

extension View {
    func settingsCard() -> some View {
        padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

struct OpenStrudelMark: View {
    @Environment(\.colorScheme) private var appearance
    let size: CGFloat

    var body: some View {
        Image(appearance == .dark ? "DockGraphite" : "DockCream")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

struct HomeBackground: View {
    var body: some View { AppTheme.canvas.ignoresSafeArea() }
}

/// One reading column for messages and the composer.
let chatColumn: CGFloat = 680

var controlTarget: CGFloat {
    #if os(iOS)
    44
    #else
    34
    #endif
}
