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
                        .padding(.vertical, 48)
                }
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        // The asset accent colours the one prominent action; secondary glass stays clear.
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

/// Places its content so the content's centre sits at 40 % of the height, and scrolls from the
/// top when the content is taller than the space.
struct OpticalCentre: SwiftUI.Layout {
    let height: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let content = subviews.first?.sizeThatFits(.init(width: proposal.width, height: nil)) ?? .zero
        return CGSize(width: proposal.width ?? content.width, height: max(height, content.height))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let content = subviews.first else { return }
        let size = content.sizeThatFits(.init(width: bounds.width, height: nil))
        let top = min(max(0, bounds.height * 0.4 - size.height / 2), bounds.height - size.height)
        content.place(at: CGPoint(x: bounds.midX, y: bounds.minY + top), anchor: .top,
                      proposal: .init(width: bounds.width, height: size.height))
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

    init(_ paragraphs: String...) { self.paragraphs = paragraphs }

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

    var body: some View {
        WelcomePage {
            WelcomeHeader(title: reconnecting ? L("Нет связи с OpenStrudel") : client.isSignedOut ? L("Вы вышли на этом устройстве") : L("Помощники для ваших задач"))
            WelcomeText(reconnecting
                        ? L("Пока не удаётся подключиться к вашей команде. Ваши чаты сохранены. Подключимся автоматически.")
                        : client.isSignedOut ? L("Сотрудники сохранены на своих устройствах. Подключитесь снова, чтобы продолжить.") : L("Начните на этом Mac. Создайте сотрудников или восстановите их из копии. Другие устройства можно подключить позже."))
                .padding(.top, 12)
            VStack(spacing: 12) {
                if client.isConfigured && !client.isLocalConnection {
                    Button { Task { await client.load() } } label: {
                        SetupActionLabel(title: L("Попробовать ещё раз"))
                    }.buttonStyle(.glassProminent).controlSize(.large)
                    if let managementURL = DigitalOceanCloud.managementURL(for: client.normalizedBaseURL) {
                        Link(destination: managementURL) {
                            SetupActionLabel(title: L("Управлять облаком"), icon: "arrow.up.right")
                        }.buttonStyle(.glass).controlSize(.large)
                            .accessibilityIdentifier("manageCloudOffline")
                            .accessibilityHint(L("Открыть вашу установку в DigitalOcean"))
                    }
                } else if LocalHome.isAvailable {
                    VStack(spacing: 8) {
                        Button {
                            starting = true
                            Task { await client.startLocalHome(); starting = false }
                        } label: {
                            SetupActionLabel(title: starting ? L("Готовим ваш Mac…") : L("Начать на этом Mac"))
                        }.buttonStyle(.glassProminent).controlSize(.large)
                            .disabled(starting).accessibilityIdentifier("setupThisMac")
                        Text(L("Сотрудники и их файлы будут храниться здесь."))
                            .font(AppTypography.meta).foregroundStyle(AppTheme.secondaryText)
                            .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                    }.padding(.bottom, 4)
                }
                Button { showingInvitation = true } label: {
                    SetupActionLabel(title: L("Подключить другое устройство"))
                }.buttonStyle(.glass).controlSize(.large)
                    .disabled(starting).accessibilityIdentifier("setupExisting")
            }.padding(.top, 32)
            VStack(spacing: 8) {
                if client.isConfigured { DeviceSignOutButton {} }
                Link(L("Конфиденциальность"), destination: URL(string: "https://waiwai.is/openstrudel/privacy")!)
                    .buttonStyle(.plain).foregroundStyle(AppTheme.accentText)
            }
            .font(AppTypography.meta).padding(.top, 24)
        }
        .sheet(isPresented: $showingInvitation, onDismiss: {
            if let invitation { client.pendingPairing = invitation; client.pairingError = nil; self.invitation = nil }
        }) {
            ConnectDeviceView { invitation = $0 }
        }
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
            OpenAISettingsCard(showIdentity: false).padding(.top, 32)
        }
        .sheet(isPresented: .constant(UserDefaults.standard.bool(forKey: "qa.serverAccount"))) { ServerAccountSetupView(onDone: {}).environmentObject(client) } // QA-TEMP
        .onChange(of: client.openAILogin) { _, login in if let url = login?.url { openURL(url) } }
        .task(id: client.openAILogin?.loginId) {
            guard client.openAILogin != nil else { return }
            while !Task.isCancelled && client.openAILogin != nil {
                try? await Task.sleep(for: .seconds(1))
                await client.pollOpenAILogin()
            }
        }
    }
}
