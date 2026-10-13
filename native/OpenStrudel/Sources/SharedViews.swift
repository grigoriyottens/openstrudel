import SwiftUI

struct OpenAISettingsCard: View {
    @EnvironmentObject private var client: HomeClient
    @Environment(\.openURL) private var openURL
    @State private var copiedCode = false
    var showIdentity = true

    var body: some View {
        let connected = client.openAIAccount?.connected == true
        VStack(alignment: .leading, spacing: 16) {
            if showIdentity {
                LabeledContent {
                    if client.openAIAccount?.isUnavailable != true { ConnectionStatus(connected: connected) }
                } label: {
                    if let account = client.openAIAccount, account.connected {
                        Text(account.email ?? "OpenAI")
                            .accessibilityLabel(L("Аккаунт OpenAI")).accessibilityValue(account.email ?? "OpenAI").accessibilityIdentifier("openAIAccountIdentity")
                        Text([account.planLabel, account.categoryLabel].compactMap { $0 }.joined(separator: " · "))
                    } else if client.openAIAccount?.isUnavailable == true {
                        Text(L("Нет связи с OpenAI"))
                        Text(L("Повторный вход пока не нужен"))
                    } else {
                        Text(L("Аккаунт не подключён"))
                        Text(L("Войдите в свой аккаунт OpenAI"))
                    }
                }
            }

            if let error = client.openAIErrorMessage {
                Text(UserFacingError.text(error)).foregroundStyle(AppTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if showIdentity && !connected && client.canManageOpenAI {
                Text(client.openAIRecoveryMessage).foregroundStyle(AppTheme.secondaryText)
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
                        .foregroundStyle(AppTheme.secondaryText).fixedSize(horizontal: false, vertical: true)
                }
            } else if let login = client.openAILogin {
                VStack(alignment: .leading, spacing: 8) {
                    if login.type == "device", let code = login.userCode {
                        Text(L("Введите этот код на сайте OpenAI")).foregroundStyle(AppTheme.secondaryText)
                        Text(code).font(AppTypography.title.monospaced()).textSelection(.enabled)
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
                                .foregroundStyle(AppTheme.secondaryText).fixedSize(horizontal: false, vertical: true)
                        }.padding(.vertical, 4)
                    } else {
                        Text(L("Откройте страницу OpenAI и завершите вход.")).font(AppTypography.meta).foregroundStyle(AppTheme.secondaryText)
                    }
                    if let url = login.url {
                        Button { openURL(url) } label: { SetupActionLabel(title: L("Открыть OpenAI"), icon: "arrow.up.right") }
                            .adaptiveActionStyle(.borderedProminent).buttonBorderShape(.capsule).controlSize(.large)
                            .tint(AppTheme.accentText).foregroundStyle(AppTheme.canvas)
                            .accessibilityIdentifier("reopenOpenAILogin")
                    }
                    Button { Task { await client.cancelOpenAILogin() } } label: {
                        SetupActionLabel(title: L("Отменить вход"))
                    }.adaptiveActionStyle(.glass).controlSize(.large).accessibilityIdentifier("cancelOpenAILogin")
                }
            } else if client.openAILoginPending {
                Text(L("Вход открыт на другом устройстве. Завершите его на сайте OpenAI. Это окно обновится автоматически."))
                    .foregroundStyle(AppTheme.secondaryText).fixedSize(horizontal: false, vertical: true)
            } else if connected {
                Button { Task { await client.beginOpenAILogin() } } label: {
                    SetupActionLabel(title: client.isStartingOpenAILogin ? L("Открываем OpenAI…") : L("Сменить аккаунт"))
                }.adaptiveActionStyle(.glass).controlSize(.large).disabled(client.isStartingOpenAILogin)
            } else if client.canManageOpenAI {
                Button { Task { await client.beginOpenAILogin() } } label: {
                    SetupActionLabel(title: client.isStartingOpenAILogin ? L("Открываем OpenAI…") : L("Войти в OpenAI"), icon: "arrow.up.right")
                }.adaptiveActionStyle(.borderedProminent).buttonBorderShape(.capsule).controlSize(.large)
                    .tint(AppTheme.accentText).foregroundStyle(AppTheme.canvas)
                    .disabled(client.isStartingOpenAILogin)
                    .accessibilityIdentifier("signInOpenAI")
            }
        }
        .onChange(of: client.openAILogin?.id) { _, _ in copiedCode = false }
    }
}

/// A connection's state as a word and a symbol; colour is never the only signal.
struct ConnectionStatus: View {
    let connected: Bool

    var body: some View {
        Label {
            Text(connected ? L("Подключён") : L("Не подключён")).foregroundStyle(AppTheme.secondaryText)
        } icon: {
            Image(systemName: connected ? "checkmark.circle.fill" : "circle.dashed")
                .foregroundStyle(connected ? AppTheme.accentText : AppTheme.secondaryText)
        }
    }
}

extension EnvironmentValues {
    /// A settings Form already groups its rows, so a card inside one drops its own surface.
    @Entry var settingsCardIsPlain = false
}

private struct SettingsCard: ViewModifier {
    @Environment(\.settingsCardIsPlain) private var plain
    func body(content: Content) -> some View {
        if plain {
            content.frame(maxWidth: .infinity, alignment: .leading)
        } else {
            content.padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        }
    }
}

extension View {
    func settingsCard() -> some View { modifier(SettingsCard()) }

    /// Settings switches: mini on the Mac, so a row with a switch is as tall as any other row.
    func settingsSwitch() -> some View {
        #if os(macOS)
        toggleStyle(.switch).controlSize(.mini)
        #else
        toggleStyle(.switch)
        #endif
    }

    /// The one primary action of a screen: an ink capsule with a canvas-coloured label.
    func inkButton() -> some View {
        buttonStyle(.borderedProminent).buttonBorderShape(.capsule).controlSize(.large)
            .tint(AppTheme.accentText).foregroundStyle(AppTheme.canvas)
    }
}

extension HomeClient {
    /// One symbol per device on every surface: this Mac, another Mac, or a server.
    var deviceSymbol: String {
        if isLocalConnection { return "laptopcomputer" }
        if let platform = health?.platform, platform != "darwin" { return "server.rack" }
        return "desktopcomputer"
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

/// A link in ink, underlined in the secondary colour at rest and in ink under the pointer.
struct InkLink: View {
    let title: String
    let destination: URL
    @State private var hovering = false

    init(_ title: String, destination: URL) {
        self.title = title
        self.destination = destination
    }

    init(title: String, destination: URL) { self.init(title, destination: destination) }

    var body: some View {
        Link(destination: destination) {
            Text(title)
                .underline(color: hovering ? AppTheme.accentText : AppTheme.secondaryText)
                .textTarget()
        }
        .buttonStyle(.plain)
        .foregroundStyle(AppTheme.accentText)
        .onHover { hovering = $0 }
    }
}

/// Places its content so the content's centre sits at 40 % of the height, and scrolls from the
/// top when the content is taller than the space.
struct OpticalCentre: SwiftUI.Layout {
    var height: CGFloat? = nil

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let content = subviews.first?.sizeThatFits(.init(width: proposal.width, height: nil)) ?? .zero
        return CGSize(width: proposal.width ?? content.width, height: max(height ?? proposal.height ?? content.height, content.height))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let content = subviews.first else { return }
        let size = content.sizeThatFits(.init(width: bounds.width, height: nil))
        let top = min(max(0, bounds.height * 0.4 - size.height / 2), bounds.height - size.height)
        content.place(at: CGPoint(x: bounds.midX, y: bounds.minY + top), anchor: .top,
                      proposal: .init(width: bounds.width, height: size.height))
    }
}
