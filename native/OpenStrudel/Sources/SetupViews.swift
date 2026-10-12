import SwiftUI

/// A generous, wrapping label; native glass supplies the material and interaction.
struct SetupActionLabel: View {
    @Environment(\.dynamicTypeSize) private var textSize
    let title: String
    var icon: String? = nil

    var body: some View {
        let layout = textSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 8))
            : AnyLayout(HStackLayout(spacing: 10))
        layout {
            if let icon { Image(systemName: icon).accessibilityHidden(true) }
            Text(title).fixedSize(horizontal: false, vertical: true)
        }
        #if os(macOS)
        .font(.system(size: 16, weight: .semibold))
        #else
        .font(.body.weight(.semibold))
        #endif
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, minHeight: 32)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}

#if os(macOS)
/// Cloud setup keeps the provider's account and billing in the user's name.
struct ServerSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var library: DeviceLibrary
    @StateObject private var cloud = DigitalOceanCloud.shared
    @State private var connecting = false
    @State private var connectionError: String?
    var onBack: (() -> Void)? = nil
    var onConnected: ((HomeClient) -> Void)? = nil

    private var working: Bool {
        [.signingIn, .creating, .waitingForServer].contains(cloud.phase)
    }

    private var title: String {
        switch cloud.phase {
        case .idle: L("Сотрудники в облаке")
        case .signingIn: L("Войдите в DigitalOcean.")
        case .billingRequired: L("Подключите оплату.")
        case .readyToCreate: L("Всё готово к запуску.")
        case .creating, .waitingForServer: L("Готовим вашу команду.")
        case .connected: L("Всё готово.")
        case .failed: L("Настройка не завершена")
        }
    }

    private var explanation: String {
        switch cloud.phase {
        case .idle:
            L("Сотрудники смогут работать, когда Mac выключен. Размещение предоставляет DigitalOcean. Для начала войдите в свой аккаунт или создайте его.")
        case .signingIn:
            L("Завершите вход в открывшемся окне. Пароль получает только DigitalOcean.")
        case .billingRequired:
            L("Добавьте способ оплаты на сайте DigitalOcean, затем вернитесь сюда. Данные карты остаются у провайдера.")
        case .readyToCreate:
            L("OpenStrudel установится на отдельном сервере в вашем аккаунте DigitalOcean. Проверьте стоимость перед запуском.")
        case .creating, .waitingForServer:
            L("Обычно настройка занимает несколько минут. Можно закрыть окно и вернуться позже. Прогресс сохранится.")
        case .connected:
            L("Открываем OpenStrudel. Дальше останется войти в свой аккаунт OpenAI.")
        case .failed:
            L("Ваш прогресс сохранён. Продолжите настройку, когда будете готовы.")
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    Image(systemName: cloud.phase == .connected ? "checkmark" : "cloud")
                        .font(.system(size: 34, weight: .light))
                        .foregroundStyle(AppTheme.secondaryText).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 16) {
                        Text(title)
                            .font(.system(.largeTitle, design: .serif, weight: .medium))
                            .fixedSize(horizontal: false, vertical: true)
                        Text(explanation)
                            .font(.body).foregroundStyle(AppTheme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if cloud.phase == .readyToCreate, let quote = cloud.quote {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(quote.monthlyPrice.formatted(.currency(code: "USD")) + L(" / месяц"))
                                .font(.title2.weight(.semibold)).monospacedDigit()
                            Text(L("Оплата напрямую DigitalOcean. Подписка ChatGPT оплачивается отдельно."))
                                .font(.callout).foregroundStyle(AppTheme.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(L("Начисляется за время размещения, пока вы не удалите его в DigitalOcean. Налоги могут добавляться отдельно."))
                                .font(.footnote).foregroundStyle(AppTheme.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }.accessibilityElement(children: .combine)
                    }
                    if let message = connectionError ?? cloud.message {
                        Text(message).font(.callout).foregroundStyle(AppTheme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("cloudSetupMessage")
                    }
                    if working {
                        HStack(spacing: 12) {
                            ProgressView().controlSize(.small)
                            Text(cloud.phase == .signingIn ? L("Ожидаем входа") : L("Настраиваем OpenStrudel"))
                                .font(.callout).foregroundStyle(AppTheme.secondaryText)
                        }.accessibilityElement(children: .combine)
                    }
                    actions
                    if let url = cloud.managementURL, cloud.phase != .connected {
                        Link(L("Открыть в DigitalOcean"), destination: url)
                            .font(.callout)
                            .buttonStyle(.plain).foregroundStyle(AppTheme.accent)
                        Text(L("Размещение оплачивается, пока вы не удалите его в DigitalOcean."))
                            .font(.footnote).foregroundStyle(AppTheme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if cloud.phase == .idle {
                        Text(L("Понадобится аккаунт DigitalOcean и способ оплаты. Стоимость покажем до запуска."))
                            .font(.footnote).foregroundStyle(AppTheme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }.padding(32).frame(maxWidth: 480).frame(maxWidth: .infinity)
            }
            .defaultScrollAnchor(.center, for: .alignment)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(working ? L("Продолжить позже") : L("Закрыть")) {
                        cloud.cancel()
                        if let onBack { onBack() } else { dismiss() }
                    }
                }
            }
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
        }
        .task {
            await cloud.resume()
            await finishConnection()
        }
        .onChange(of: cloud.connection?.url) { _, _ in
            Task { await finishConnection() }
        }
        #if os(macOS)
        .frame(width: 520, height: 620)
        #else
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        #endif
    }

    @ViewBuilder private var actions: some View {
        switch cloud.phase {
        case .idle:
            Button { Task { await cloud.signIn() } } label: {
                SetupActionLabel(title: L("Продолжить с DigitalOcean"), icon: "arrow.up.right")
            }.buttonStyle(.glassProminent).controlSize(.large)
                .accessibilityIdentifier("cloudSignIn")
        case .billingRequired:
            VStack(spacing: 12) {
                Link(destination: URL(string: "https://cloud.digitalocean.com/account/billing")!) {
                    SetupActionLabel(title: L("Добавить способ оплаты"), icon: "arrow.up.right")
                }.buttonStyle(.glassProminent).controlSize(.large)
                Button { Task { await cloud.resume() } } label: {
                    SetupActionLabel(title: L("Продолжить"))
                }.buttonStyle(.glass).controlSize(.large)
            }
        case .readyToCreate:
            Button { Task { await cloud.confirmCreate() } } label: {
                SetupActionLabel(title: L("Подтвердить и запустить"), icon: "arrow.right")
            }.buttonStyle(.glassProminent).controlSize(.large)
                .accessibilityIdentifier("cloudConfirmCost")
        case .failed:
            Button { Task { await cloud.resume() } } label: {
                SetupActionLabel(title: L("Продолжить настройку"), icon: "arrow.clockwise")
            }.buttonStyle(.glassProminent).controlSize(.large)
        case .connected:
            if connectionError != nil {
                Button { Task { await finishConnection() } } label: {
                    SetupActionLabel(title: L("Открыть команду"), icon: "arrow.right")
                }.buttonStyle(.glassProminent).controlSize(.large).disabled(connecting)
            }
        case .signingIn:
            #if os(macOS)
            if let url = cloud.authorizationURL {
                Link(L("Открыть вход в браузере"), destination: url)
                    .buttonStyle(.glass).controlSize(.large)
            }
            #endif
        case .creating, .waitingForServer:
            EmptyView()
        }
    }

    private func finishConnection() async {
        guard let connection = cloud.connection, !connecting else { return }
        connecting = true
        defer { connecting = false }
        let client = library.clients.first { $0.savedBaseURL == connection.url } ?? library.newConnection()
        if await client.connectToCloud(connection) {
            library.add(client, select: onConnected == nil)
            if let onConnected { onConnected(client) } else { dismiss() }
        } else {
            connectionError = client.pairingError ?? L("Не удалось сохранить подключение. Разблокируйте устройство и попробуйте ещё раз.")
        }
    }
}

/// Both server routes finish with the same account step and first assistant.
struct ServerAccountSetupView: View {
    @EnvironmentObject private var client: HomeClient
    @EnvironmentObject private var library: DeviceLibrary
    @Environment(\.openURL) private var openURL
    let onDone: () -> Void
    private var connected: Bool { client.openAIAccount?.connected == true && !client.homeUnreachable }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    OpenStrudelMark(size: 64)
                    VStack(alignment: .leading, spacing: 12) {
                        Text(connected ? L("Your server is ready") : L("Connect ChatGPT"))
                            .font(.system(.largeTitle, design: .serif, weight: .medium))
                        Text(connected
                             ? L("Your assistants can now work here, even when your Mac is off.")
                             : L("OpenStrudel is installed. Sign in to ChatGPT to let your assistants work on this server."))
                            .foregroundStyle(AppTheme.secondaryText).fixedSize(horizontal: false, vertical: true)
                        Label(client.displayName, systemImage: "server.rack").font(.callout)
                    }
                    if connected {
                        if let account = client.openAIAccount {
                            VStack(alignment: .leading, spacing: 4) {
                                Label(account.email ?? "ChatGPT", systemImage: "checkmark.circle.fill")
                                    .font(.headline).textSelection(.enabled)
                                Text([account.planLabel, account.categoryLabel].compactMap { $0 }.joined(separator: " · "))
                                    .font(.callout).foregroundStyle(AppTheme.secondaryText)
                            }
                        }
                        Button {
                            onDone()
                            library.beginEmployee(on: client)
                        } label: { SetupActionLabel(title: L("Create an assistant here"), icon: "plus") }
                            .buttonStyle(.glassProminent).controlSize(.large)
                            .accessibilityIdentifier("createFirstServerAssistant")
                        Button(L("Open server")) { onDone(); library.select(client) }
                            .buttonStyle(.plain).foregroundStyle(AppTheme.secondaryText)
                    } else if client.homeUnreachable {
                        Text(L("The server did not respond. Your installation is saved."))
                            .foregroundStyle(AppTheme.secondaryText)
                        Button(L("Повторить")) { Task { await client.load(quiet: true) } }
                            .buttonStyle(.glassProminent)
                    } else {
                        OpenAISettingsCard(showIdentity: false)
                    }
                }.padding(32).frame(maxWidth: 470).frame(maxWidth: .infinity)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Продолжить позже")) { onDone(); library.select(client) }
                }
            }
        }.frame(width: 540, height: 650)
        .onChange(of: client.openAILogin) { _, login in if let url = login?.url { openURL(url) } }
        .task(id: client.openAILogin?.loginId) {
            await client.refreshOpenAIAccount()
            while !Task.isCancelled && !connected && (client.openAILogin != nil || client.openAILoginPending) {
                if client.openAILogin != nil { await client.pollOpenAILogin() }
                else { await client.refreshOpenAIAccount() }
                do { try await Task.sleep(for: .seconds(2)) } catch { break }
            }
        }
    }
}

#endif

struct AIDataConsentView: View {
    @Environment(\.dynamicTypeSize) private var textSize
    let accept: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                OpenStrudelMark(size: 76)
                Text(L("Ваши данные"))
                    .font(.system(.largeTitle, design: .serif, weight: .medium))
                Text(L("Чаты хранятся на вашем Mac или сервере. Для ответов OpenAI получает сообщения, нужную часть переписки и выбранные файлы."))
                    .font(.body).foregroundStyle(AppTheme.secondaryText)
                Text(L("Другие сервисы получают данные только при обращении к ним."))
                    .font(.callout).foregroundStyle(AppTheme.secondaryText)
                Link(destination: URL(string: "https://waiwai.is/openstrudel/privacy")!) {
                    Text(L("Подробнее о данных")).frame(minHeight: 44).contentShape(Rectangle())
                }
                    .font(.callout)
                    .buttonStyle(.plain).foregroundStyle(AppTheme.accent)
                Button(action: accept) {
                    SetupActionLabel(title: textSize.isAccessibilitySize ? L("Разрешить") : L("Разрешить и продолжить"))
                }
                    .adaptiveActionStyle(.glassProminent).controlSize(.large)
                    .accessibilityLabel(L("Разрешить и продолжить"))
                    .accessibilityIdentifier("acceptAIDataSharing")
            }.multilineTextAlignment(.center).padding(32).frame(maxWidth: 480)
                .frame(maxWidth: .infinity)
        }.defaultScrollAnchor(.center, for: .alignment)
    }
}
