import SwiftUI

/// First-run screens share one composition: the character, a display title, a short body and the
/// actions, in a 480-pt column whose centre sits at 40 % of the height (docs/design-system.md).
struct WelcomePage<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                OpticalCentre(height: proxy.size.height) {
                    VStack(spacing: 0) { content }
                        .frame(maxWidth: OnboardingLayout.column)
                        .padding(.horizontal, OnboardingLayout.margin)
                        // The top band stays clear of the language menu when the content fills the height.
                        .padding(.top, 64).padding(.bottom, 48)
                }
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        // Actions choose their own ink; glass inside shared cards stays clear.
        .tint(nil)
    }
}

enum OnboardingLayout {
    static let column: CGFloat = 480
    /// The window edge on the Mac, the screen margin on iOS.
    static var margin: CGFloat {
        #if os(macOS)
        20
        #else
        16
        #endif
    }
}

/// Wraps text to the narrowest width that keeps its number of lines, so centred lines come out even
/// and no word is left alone on the last one. Leading-aligned text keeps the full column.
struct BalancedLines: SwiftUI.Layout {
    var centred = true

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let text = subviews.first else { return .zero }
        let size = text.sizeThatFits(.init(width: proposal.width, height: nil))
        return CGSize(width: proposal.width ?? size.width, height: size.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let text = subviews.first else { return }
        let width = centred ? Self.balancedWidth(text, within: bounds.width) : bounds.width
        text.place(at: CGPoint(x: centred ? bounds.midX : bounds.minX, y: bounds.minY),
                   anchor: centred ? .top : .topLeading, proposal: .init(width: width, height: nil))
    }

    private static func balancedWidth(_ text: LayoutSubview, within available: CGFloat) -> CGFloat {
        let height = text.sizeThatFits(.init(width: available, height: nil)).height
        var narrow: CGFloat = 0, wide = available
        while wide - narrow > 0.5 {
            let width = (narrow + wide) / 2
            if text.sizeThatFits(.init(width: width, height: nil)).height > height + 0.5 { narrow = width } else { wide = width }
        }
        return wide
    }
}

extension String {
    /// Joins the last two words with a no-break space, so wrapped text never ends on a lone word.
    var withoutWidow: String {
        guard let space = lastIndex(of: " ") else { return self }
        return replacingCharacters(in: space...space, with: "\u{00A0}")
    }
}

/// The first-run language menu: the globe and the current language in the quiet colour. It follows
/// the interface direction, so in Hebrew it sits at the window's left.
struct LanguagePicker: View {
    var body: some View {
        let language = L10n.shared.language
        Menu {
            Picker(L("Language"), selection: Binding(get: { L10n.shared.language }, set: { L10n.shared.language = $0 })) {
                ForEach(AppLanguage.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            Label(language.title, systemImage: "globe")
                .labelStyle(.titleAndIcon)
                .font(AppTypography.interface)
                .foregroundStyle(AppTheme.secondaryText)
                .textTarget()
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel(L("Language"))
        .accessibilityValue(language.title)
        .accessibilityIdentifier("interfaceLanguage")
    }
}

/// The main character and the display title.
struct WelcomeHeader: View {
    let title: String

    var body: some View {
        VStack(spacing: 24) {
            AgentAvatar(appearance: nil, size: AvatarSize.hero)
            BalancedLines {
                Text(title)
                    .font(AppTypography.display)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
            }
        }
    }
}

/// Body copy: centred and balanced while every paragraph fits on two lines, leading-aligned once one
/// runs longer.
struct WelcomeText: View {
    let paragraphs: [String]
    @State private var long: Set<Int> = []

    init(_ paragraphs: String...) { self.paragraphs = paragraphs.map(\.withoutWidow) }

    var body: some View {
        VStack(spacing: 12) {
            ForEach(paragraphs.indices, id: \.self) { index in
                BalancedLines(centred: long.isEmpty) {
                    Text(paragraphs[index]).multilineTextAlignment(long.isEmpty ? .center : .leading)
                }
                .background {
                    GeometryReader { full in
                        Text(paragraphs[index]).lineLimit(2).hidden()
                            .onGeometryChange(for: Bool.self) { $0.size.height < full.size.height - 1 } action: { runsLonger in
                                if runsLonger { long.insert(index) } else { long.remove(index) }
                            }
                    }
                }
            }
        }
        .font(AppTypography.interface)
        .foregroundStyle(AppTheme.secondaryText)
    }
}

struct HomeConnectingView: View {
    @EnvironmentObject private var client: HomeClient
    var body: some View {
        WelcomePage {
            WelcomeHeader(title: client.isStartingLocalHome ? L("Запускаем OpenStrudel") : L("Подключаемся к вашей команде"))
            ProgressView().padding(.top, 32).accessibilityLabel(L("Подключение"))
        }
        .accessibilityIdentifier("homeConnecting")
    }
}

#if os(macOS)
/// Home runs beside the app. It is found again automatically once it starts.
struct HomeUnavailableView: View {
    @EnvironmentObject private var client: HomeClient
    @State private var showingInvitation = false
    @State private var invitation: MacPairing?
    @State private var starting = false
    private var reconnecting: Bool { client.shouldRestoreConnection && client.connectionState == .unavailable }
    private var remote: Bool { client.isConfigured && !client.isLocalConnection }
    /// Connecting another device leads only when there is nothing to retry or start here.
    private var connectingLeads: Bool { !remote && !LocalHome.isAvailable }

    var body: some View {
        WelcomePage {
            WelcomeHeader(title: reconnecting ? L("Нет связи с OpenStrudel") : client.isSignedOut ? L("Вы вышли на этом устройстве") : L("Помощники для ваших задач"))
            WelcomeText(reconnecting
                        ? L("Пока не удаётся подключиться к вашей команде. Ваши чаты сохранены. Подключимся автоматически.")
                        : client.isSignedOut ? L("Сотрудники сохранены на своих устройствах. Подключитесь снова, чтобы продолжить.") : L("Начните на этом Mac. Создайте сотрудников или восстановите их из копии. Другие устройства можно подключить позже."))
                .padding(.top, 12)
            VStack(spacing: 8) {
                if remote {
                    Button { Task { await client.load() } } label: {
                        SetupActionLabel(title: L("Попробовать ещё раз"))
                    }.primaryAction()
                } else if LocalHome.isAvailable {
                    Button {
                        starting = true
                        Task { await client.startLocalHome(); starting = false }
                    } label: {
                        SetupActionLabel(title: starting ? L("Готовим ваш Mac…") : L("Начать на этом Mac"))
                    }.primaryAction()
                        .disabled(starting).accessibilityIdentifier("setupThisMac")
                    // Only a first start needs to say where the work will live.
                    if !reconnecting {
                        Text(L("Сотрудники и их файлы будут храниться здесь."))
                            .font(AppTypography.meta).foregroundStyle(AppTheme.secondaryText)
                            .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    connectButton.primaryAction()
                }
            }.padding(.top, 32)
            if !connectingLeads {
                VStack(spacing: 16) {
                    if remote, let managementURL = DigitalOceanCloud.managementURL(for: client.normalizedBaseURL) {
                        Link(destination: managementURL) {
                            Label(L("Управлять облаком"), systemImage: "arrow.up.forward")
                        }.secondaryAction()
                            .accessibilityIdentifier("manageCloudOffline")
                            .accessibilityHint(L("Открыть вашу установку в DigitalOcean"))
                    }
                    connectButton.secondaryAction()
                }
                .font(AppTypography.interface).padding(.top, 16)
            }
            HStack(spacing: 24) {
                if client.isConfigured { DeviceSignOutButton {} }
                InkLink(L("Конфиденциальность"), destination: URL(string: "https://waiwai.is/openstrudel/privacy")!)
            }
            .font(AppTypography.meta).padding(.top, 24)
        }
        .sheet(isPresented: $showingInvitation, onDismiss: {
            if let invitation { client.pendingPairing = invitation; client.pairingError = nil; self.invitation = nil }
        }) {
            ConnectDeviceView { invitation = $0 }
        }
    }

    private var connectButton: some View {
        Button { showingInvitation = true } label: {
            if connectingLeads { SetupActionLabel(title: L("Подключить другое устройство")) }
            else { Text(L("Подключить другое устройство")) }
        }
        .disabled(starting).accessibilityIdentifier("setupExisting")
    }
}
#endif

struct OpenAIWelcomeView: View {
    @EnvironmentObject private var client: HomeClient
    @Environment(\.openURL) private var openURL
    var body: some View {
        WelcomePage {
            WelcomeHeader(title: client.openAIAccount?.isUnavailable == true ? L("Нет связи с OpenAI")
                          : !client.canManageOpenAI ? L("Нужен вход владельца")
                          : client.openAIAccount?.needsSignInAgain == true ? L("Войдите в OpenAI снова")
                          : L("Подключите OpenAI"))
            WelcomeText(client.openAIAccount?.isUnavailable == true
                        ? L("Проверьте подключение к интернету и попробуйте ещё раз. Ваши чаты и сотрудники сохранены.")
                        : !client.canManageOpenAI ? client.openAIRecoveryMessage
                        : client.openAIAccount?.needsSignInAgain == true
                        ? L("Сохранённый вход больше не действует. Войдите снова для сотрудников этого устройства.")
                        : L("Войдите на сайте OpenAI. Этот аккаунт будут использовать сотрудники на «\(client.displayName)»."))
                .padding(.top, 12)
            Group {
                if client.openAILogin != nil || client.openAILoginPending {
                    // The code, the browser link and cancelling live in the shared account card.
                    OpenAISettingsCard(showIdentity: false)
                } else if client.openAIAccount?.isUnavailable == true {
                    VStack(spacing: 12) {
                        error
                        Button { Task { await client.refreshOpenAIAccount(force: true) } } label: {
                            SetupActionLabel(title: L("Проверить ещё раз"))
                        }.primaryAction()
                            .accessibilityIdentifier("retryOpenAIAccount")
                    }
                } else if client.canManageOpenAI {
                    VStack(spacing: 12) {
                        error
                        Button { Task { await client.beginOpenAILogin() } } label: {
                            SetupActionLabel(title: client.isStartingOpenAILogin ? L("Открываем OpenAI…") : L("Войти в OpenAI"), icon: "arrow.up.forward")
                        }.primaryAction()
                            .disabled(client.isStartingOpenAILogin)
                            .accessibilityIdentifier("signInOpenAI")
                    }
                }
            }.padding(.top, 32)
        }
        #if os(macOS) // QA-TEMP
        .sheet(isPresented: .constant(UserDefaults.standard.bool(forKey: "qa.serverAccount"))) { ServerAccountSetupView(onDone: {}).environmentObject(client) } // QA-TEMP
        #endif // QA-TEMP
        .onChange(of: client.openAILogin) { _, login in if let url = login?.url { openURL(url) } }
        .task(id: client.openAILogin?.loginId) {
            guard client.openAILogin != nil else { return }
            while !Task.isCancelled && client.openAILogin != nil {
                try? await Task.sleep(for: .seconds(1))
                await client.pollOpenAILogin()
            }
        }
    }

    @ViewBuilder private var error: some View {
        if let error = client.openAIErrorMessage {
            Text(UserFacingError.text(error))
                .font(AppTypography.interface).foregroundStyle(AppTheme.secondaryText)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
        }
    }
}
