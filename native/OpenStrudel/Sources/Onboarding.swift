import SwiftUI

struct HomeConnectingView: View {
    @EnvironmentObject private var client: HomeClient
    var body: some View {
        VStack(spacing: 24) {
            OpenStrudelMark(size: 76)
            Text(client.isStartingLocalHome ? L("Запускаем OpenStrudel") : L("Подключаемся к вашей команде"))
                .font(.system(.title, design: .serif, weight: .medium))
                .multilineTextAlignment(.center)
            ProgressView().controlSize(.large).accessibilityLabel(L("Подключение"))
        }
        .padding(28).frame(maxWidth: 620)
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
        ScrollView {
        VStack(spacing: 28) {
            OpenStrudelMark(size: 76)
            VStack(spacing: 12) {
                Text(reconnecting ? L("Нет связи с OpenStrudel") : client.isSignedOut ? L("Вы вышли на этом устройстве") : L("Помощники для ваших задач"))
                    .font(AppTypography.welcome)
                    .multilineTextAlignment(.center)
                Text(reconnecting
                     ? L("Пока не удаётся подключиться к вашей команде. Ваши чаты сохранены. Подключимся автоматически.")
                     : client.isSignedOut ? L("Сотрудники сохранены на своих устройствах. Подключитесь снова, чтобы продолжить.") : L("Начните на этом Mac. Создайте сотрудников или восстановите их из копии. Другие устройства можно подключить позже."))
                    .font(.body).foregroundStyle(AppTheme.secondaryText)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            }
            VStack(spacing: 12) {
                if client.isConfigured && !client.isLocalConnection {
                    Button { Task { await client.load() } } label: {
                        SetupActionLabel(title: L("Попробовать ещё раз"), icon: "arrow.clockwise")
                    }.buttonStyle(.glassProminent).controlSize(.large)
                    if let managementURL = DigitalOceanCloud.managementURL(for: client.normalizedBaseURL) {
                        Link(destination: managementURL) {
                            SetupActionLabel(title: L("Управлять облаком"), icon: "arrow.up.right.square")
                        }.buttonStyle(.glass).controlSize(.large)
                            .accessibilityIdentifier("manageCloudOffline")
                            .accessibilityHint(L("Открыть вашу установку в DigitalOcean"))
                    }
                } else if LocalHome.isAvailable {
                    Button {
                        starting = true
                        Task { await client.startLocalHome(); starting = false }
                    } label: {
                        SetupChoiceLabel(title: starting ? L("Готовим ваш Mac…") : L("Начать на этом Mac"), subtitle: L("Сотрудники и их файлы будут храниться здесь."), icon: "desktopcomputer")
                    }.buttonStyle(.glassProminent).controlSize(.large)
                        .buttonBorderShape(.roundedRectangle(radius: 22))
                        .disabled(starting).accessibilityIdentifier("setupThisMac")
                }
                Button { showingInvitation = true } label: {
                    SetupActionLabel(title: L("Подключить другое устройство"), icon: "link")
                }.buttonStyle(.plain).foregroundStyle(AppTheme.secondaryText)
                    .disabled(starting).accessibilityIdentifier("setupExisting")
            }
            if client.isConfigured { DeviceSignOutButton {} }
            Link(L("Конфиденциальность"), destination: URL(string: "https://waiwai.is/openstrudel/privacy")!)
                .font(.caption).buttonStyle(.plain).foregroundStyle(AppTheme.secondaryText)
        }
        .padding(40).frame(maxWidth: 520).frame(maxWidth: .infinity)
        }.defaultScrollAnchor(.center, for: .alignment)
        .sheet(isPresented: $showingInvitation, onDismiss: {
            if let invitation { client.pendingPairing = invitation; client.pairingError = nil; self.invitation = nil }
        }) {
            #if os(macOS)
            ConnectDeviceView { invitation = $0 }
            #else
            ConnectionInvitationView { invitation = $0 }
            #endif
        }
    }
}

struct SetupChoiceLabel: View {
    let title: String
    let subtitle: String
    let icon: String
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon).font(.title3).frame(width: 28).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 16, weight: .semibold))
                Text(subtitle).font(.system(size: 13)).opacity(0.8)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }.padding(.horizontal, 8).padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 62).contentShape(Rectangle())
    }
}
#endif

struct OpenAIWelcomeView: View {
    @EnvironmentObject private var client: HomeClient
    @Environment(\.openURL) private var openURL
    var body: some View {
        ScrollView {
        VStack(spacing: 24) {
            OpenStrudelMark(size: 76)
            VStack(spacing: 12) {
                Text(client.openAIAccount?.isUnavailable == true ? L("Нет связи с OpenAI")
                     : !client.canManageOpenAI ? L("Нужен вход владельца")
                     : client.openAIAccount?.needsSignInAgain == true ? L("Войдите в OpenAI снова")
                     : L("Подключите OpenAI"))
                    .font(AppTypography.welcome).multilineTextAlignment(.center)
                Text(client.openAIAccount?.isUnavailable == true
                     ? L("Проверьте подключение к интернету и попробуйте ещё раз. Ваши чаты и сотрудники сохранены.")
                     : !client.canManageOpenAI ? client.openAIRecoveryMessage
                     : client.openAIAccount?.needsSignInAgain == true
                     ? L("Сохранённый вход больше не действует. Войдите снова для сотрудников этого устройства.")
                     : L("Войдите на сайте OpenAI. Этот аккаунт будут использовать сотрудники на «\(client.displayName)»."))
                    .font(.body).foregroundStyle(AppTheme.secondaryText).multilineTextAlignment(.center)
            }
            OpenAISettingsCard(showIdentity: false)
        }.padding(32).frame(maxWidth: 480).frame(maxWidth: .infinity)
        }.defaultScrollAnchor(.center, for: .alignment)
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
