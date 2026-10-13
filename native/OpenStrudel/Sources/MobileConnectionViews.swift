import SwiftUI
import CoreImage.CIFilterBuiltins
#if os(iOS)
import VisionKit
import AVFoundation
#endif

/// Rows for a device's section in Settings → Devices: a one-use connection link and, on this Mac,
/// disconnecting the other devices. The section footer can use `explanation`.
struct MobilePairingSettings: View {
    @EnvironmentObject private var client: HomeClient
    @State private var showingCode = false
    @State private var creating = false
    @State private var revokeConfirmation = false

    static var explanation: String { L("Чтобы открыть сотрудников этого устройства на другом, создайте ссылку подключения.") }

    var body: some View {
        // Always present: this row also learns whether the device lets this app create links.
        Button(creating ? L("Готовим ссылку…") : L("Получить ссылку подключения")) {
            creating = true
            Task {
                await client.inviteMobile()
                showingCode = client.mobileInvitation != nil
                creating = false
            }
        }
        .disabled(creating || !(client.isLocalConnection || client.canManageConnections))
        .task { await client.refreshMobileStatus() }
        .sheet(isPresented: $showingCode, onDismiss: { Task { await client.cancelMobileInvitation() } }) {
            MobileQRCodeView().environmentObject(client)
        }
        if client.isLocalConnection && client.mobileConnections > 0 {
            Button(L("Отключить"), role: .destructive) { revokeConfirmation = true }
                .confirmationDialog(L("Отключить другие устройства? Чаты и сотрудники сохранятся."), isPresented: $revokeConfirmation) {
                    Button(L("Отключить"), role: .destructive) { Task { await client.revokeMobile() } }
                }
        }
    }
}

private struct MobileQRCodeView: View {
    @EnvironmentObject private var client: HomeClient
    @Environment(\.dismiss) private var dismiss
    @State private var initialCount = 0
    @State private var refreshing = false

    var body: some View {
        NavigationStack {
        ScrollView {
        VStack(spacing: 16) {
            Text(L("Продолжите на другом устройстве")).font(AppTypography.title).multilineTextAlignment(.center)
            Text(L("Отсканируйте QR в OpenStrudel\nили откройте ссылку на другом устройстве."))
                .font(AppTypography.interface).foregroundStyle(AppTheme.secondaryText).multilineTextAlignment(.center)
            if let invitation = client.mobileInvitation {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let remaining = invitation.remainingSeconds(at: context.date)
                    VStack(spacing: 16) {
                        if remaining > 0, let code = qr(invitation.url.absoluteString) {
                            Image(decorative: code, scale: 1).interpolation(.none).resizable()
                                .scaledToFit().frame(width: 236, height: 236)
                                .padding(16).background(.white, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                                .accessibilityLabel(L("Одноразовая ссылка подключения OpenStrudel"))
                            Text(L("Ссылка действует ещё \(remaining / 60):\(String(format: "%02d", remaining % 60))"))
                                .font(AppTypography.meta).monospacedDigit().foregroundStyle(AppTheme.secondaryText)
                            ShareLink(item: invitation.url) { AdaptiveActionLabel(title: L("Поделиться ссылкой")) }
                                .adaptiveActionStyle(.glass)
                        } else {
                            ContentUnavailableView(L("Срок ссылки истёк"), systemImage: "qrcode",
                                description: Text(L("Получите новую, чтобы подключить устройство.")))
                                .frame(height: 300)
                        }
                        Button {
                            refreshing = true
                            Task { await client.inviteMobile(); refreshing = false }
                        } label: {
                            Text(refreshing ? L("Обновляем…") : L("Новая ссылка"))
                        }.secondaryAction().disabled(refreshing)
                    }
                }
            }
            Text(L("Ссылка открывает чаты и настройки сотрудников.\nИспользуйте её только на своих устройствах."))
                .font(AppTypography.meta).foregroundStyle(AppTheme.secondaryText).multilineTextAlignment(.center)
        }
        .padding(24).frame(maxWidth: 420).frame(maxWidth: .infinity)
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(L("Готово")) { dismiss() }.keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("closeMobileInvitation")
            }
        }
        }
        .tint(nil)
        #if os(macOS)
        .frame(width: 420, height: 620)
        #endif
        .task {
            initialCount = client.mobileConnections
            while !Task.isCancelled {
                await client.refreshMobileStatus()
                if client.mobileConnections > initialCount { dismiss(); break }
                do { try await Task.sleep(for: .seconds(1)) } catch { break }
            }
        }
    }

    private func qr(_ value: String) -> CGImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(value.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        return CIContext().createCGImage(output, from: output.extent)
    }
}
#if os(iOS)
struct MobileWelcomeView: View {
    @EnvironmentObject private var client: HomeClient
    @Environment(\.dynamicTypeSize) private var textSize
    @State private var scanning = false
    @State private var enteringInvitation = false
    @State private var invitation: MacPairing?
    @State private var cameraError: String?
    @State private var showingHelp = false
    private var reconnecting: Bool { client.isConfigured && !client.connectionNeedsPairing }

    var body: some View {
        WelcomePage {
            WelcomeHeader(title: client.connectionNeedsPairing ? L("Подключитесь снова.") : client.isConfigured ? L("Нет связи с OpenStrudel") : client.isSignedOut ? L("Устройство отключено") : L("Ваши AI-помощники"))
            WelcomeText(client.connectionNeedsPairing ? L("Подключение отозвано. Получите новую ссылку на устройстве с сотрудниками.") : client.isConfigured
                        ? L("«\(client.connectionName)» пока не на связи. Подключимся автоматически.")
                        : L("Пишите, планируйте и обсуждайте идеи. Подключите свой Mac или сервер с OpenStrudel, чтобы продолжить те же чаты здесь."))
                .padding(.top, 12)
            if reconnecting {
                ProgressView().padding(.top, 24).accessibilityLabel(L("Восстанавливаем связь"))
            }
            Group {
                if reconnecting {
                    Button { Task { await client.load(quiet: true) } } label: {
                        SetupActionLabel(title: L("Проверить соединение"))
                    }.primaryAction()
                        .disabled(client.isLoading).accessibilityIdentifier("retryHomeConnection")
                } else {
                    // Scanning the code another device shows is the way in, so it leads unless a retry does.
                    scanButton.primaryAction()
                }
            }.padding(.top, 32)
            VStack(spacing: 0) {
                if reconnecting { scanButton.secondaryAction() }
                Button { enteringInvitation = true } label: {
                    SetupActionLabel(title: L("Вставить ссылку"), icon: "link")
                }.secondaryAction()
                    .accessibilityLabel(L("Вставить ссылку подключения")).accessibilityIdentifier("pasteInvitation")
                if let cameraError {
                    Text(L10n.serviceText(cameraError)).font(AppTypography.meta).foregroundStyle(AppTheme.secondaryText)
                        .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                }
            }
            // Text actions are as tall as the capsule; the gaps subtract that, so the words sit 16 below it.
            .padding(.top, 16 - TextAction.inset)
            VStack(spacing: 0) {
                if client.isConfigured { DeviceSignOutButton {}.frame(minHeight: controlTarget) }
                Button { showingHelp = true } label: {
                    Text(L("Как начать?"))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity)
                }.buttonStyle(TextActionStyle(quiet: true))
                    .accessibilityIdentifier("invitationHelp")
            }
            .font(AppTypography.interface).padding(.top, 32 - 2 * TextAction.inset)
        }
        .sheet(isPresented: $enteringInvitation, onDismiss: confirmInvitation) {
            ConnectionInvitationView { invitation = $0 }
        }
        .sheet(isPresented: $showingHelp) {
            MobileConnectionHelpView()
        }
        .fullScreenCover(isPresented: $scanning, onDismiss: confirmInvitation) {
            NavigationStack {
                QRScanner { value in
                    if let url = URL(string: value), let pairing = try? MacPairing(url: url) {
                        invitation = pairing; scanning = false
                    }
                } failed: {
                    cameraError = L("Камера недоступна. Вставьте ссылку подключения.")
                    scanning = false
                }
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle(L("Сканируйте QR подключения"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button(L("Отмена")) { scanning = false } } }
            }
        }
    }

    private var scanButton: some View {
        Button { Task { await openScanner() } } label: {
            SetupActionLabel(title: textSize.isAccessibilitySize ? L("QR-код") : L("Сканировать QR"), icon: "qrcode.viewfinder")
        }
        .accessibilityLabel(L("Сканировать QR")).accessibilityIdentifier("scanInvitation")
    }

    private func confirmInvitation() {
        guard let invitation else { return }
        client.pendingPairing = invitation
        client.pairingError = nil
        self.invitation = nil
    }

    private func openScanner() async {
        cameraError = nil
        guard DataScannerViewController.isSupported else {
            cameraError = L("На этом устройстве вставьте ссылку подключения.")
            return
        }
        let granted = await AVCaptureDevice.requestAccess(for: .video)
        guard granted, DataScannerViewController.isAvailable else {
            cameraError = L("Разрешите доступ к камере в настройках устройства или вставьте ссылку.")
            return
        }
        scanning = true
    }
}

/// Connection help stays in the companion app and has no signup or payment route.
struct MobileConnectionHelpView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    topic(L("Начните на своём Mac"),
                          L("Установите бесплатный OpenStrudel с waiwai.is/openstrudel. Войдите в свой аккаунт OpenAI и создайте AI-помощника для личных или рабочих задач."),
                          L("Регистрация в OpenStrudel не нужна. Ссылку для своего iPhone или iPad вы создаёте сами."))
                    topic(L("Где получить ссылку"),
                          L("На Mac с сотрудниками откройте OpenStrudel → Настройки → Устройства. Нажмите на устройство, затем «Получить ссылку подключения»."),
                          L("Для сервера откройте его веб-интерфейс → Настройки → Устройства."))
                    topic(L("Как подключиться"),
                          L("Отсканируйте QR или вставьте ссылку в OpenStrudel на этом устройстве."),
                          L("Ссылка одноразовая и действует пять минут. Если срок истёк, получите новую."))
                    topic(L("Если нет связи"),
                          L("Устройство с сотрудниками должно быть включено и доступно по сети. Для подключения по локальной сети используйте один Wi-Fi."),
                          L("Связь восстановится автоматически. Новая ссылка нужна, только если подключение отозвано."))
                }
                .padding(.horizontal, OnboardingLayout.margin).padding(.vertical, 24)
                .frame(maxWidth: OnboardingLayout.column, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle(L("Подключение устройства"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Готово")) { dismiss() }.accessibilityIdentifier("closeConnectionHelp")
                }
            }
        }
        .sheetTint()
    }

    private func topic(_ title: String, _ paragraphs: String...) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.headline).foregroundStyle(Color.primary).accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: 12) {
                ForEach(paragraphs, id: \.self) { Text($0) }
            }
            .font(AppTypography.interface).foregroundStyle(AppTheme.secondaryText)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct QRScanner: UIViewControllerRepresentable {
    let found: (String) -> Void
    let failed: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(found: found, failed: failed) }
    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(recognizedDataTypes: [.barcode(symbologies: [.qr])], qualityLevel: .balanced,
            recognizesMultipleItems: false, isHighFrameRateTrackingEnabled: false, isPinchToZoomEnabled: true, isGuidanceEnabled: true, isHighlightingEnabled: true)
        scanner.delegate = context.coordinator
        do { try scanner.startScanning() }
        catch { Task { @MainActor in failed() } }
        return scanner
    }
    func updateUIViewController(_ controller: DataScannerViewController, context: Context) {}
    static func dismantleUIViewController(_ controller: DataScannerViewController, coordinator: Coordinator) { controller.stopScanning() }
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let found: (String) -> Void
        let failed: () -> Void
        private var used = false
        init(found: @escaping (String) -> Void, failed: @escaping () -> Void) { self.found = found; self.failed = failed }
        func dataScanner(_ dataScanner: DataScannerViewController, becameUnavailableWithError error: DataScannerViewController.ScanningUnavailable) { failed() }
        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            guard !used else { return }
            for item in addedItems {
                if case .barcode(let barcode) = item, let value = barcode.payloadStringValue,
                   let url = URL(string: value), (try? MacPairing(url: url)) != nil {
                    used = true; dataScanner.stopScanning(); found(value); break
                }
            }
        }
    }
}
#endif

struct ConnectionInvitationView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    let onConfirm: (MacPairing) -> Void
    var onBack: (() -> Void)? = nil
    @State private var invitation = UserDefaults.standard.string(forKey: "qa.invitation") ?? "" // QA-TEMP
    @State private var error: String?
    @State private var openingPage = false
    @FocusState private var focused: Bool

    private var connectionPage: URL? {
        guard let url = URL(string: invitation.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme?.lowercased() == "https", let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil else { return nil }
        return url
    }

    private var continueTitle: String {
        openingPage ? L("Открываем…") : connectionPage == nil ? L("Продолжить") : L("Открыть страницу")
    }

    private var canContinue: Bool {
        !openingPage && !invitation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 8) {
                        SecureField(L("Ссылка подключения"), text: $invitation, prompt: Text(L("Ссылка подключения")))
                            .labelsHidden()
                            .focused($focused).accessibilityIdentifier("connectionInvitation")
                            #if os(iOS)
                            .textInputAutocapitalization(.never).autocorrectionDisabled().submitLabel(.continue)
                            .frame(minHeight: controlTarget)
                            #endif
                            .onSubmit(confirm)
                        PasteButton(payloadType: String.self) { values in
                            if let value = values.first { invitation = value; error = nil }
                        }.labelStyle(.titleOnly)
                    }
                } header: {
                    SetupHeader(title: L("Подключить устройство"), paragraphs: L("1. На другом Mac откройте OpenStrudel → Настройки → Устройства. Нажмите на устройство, затем «Получить ссылку подключения».\n\n2. Вставьте ссылку сюда. Для сервера получите её в его веб-интерфейсе: Настройки → Устройства.").components(separatedBy: "\n\n"))
                } footer: {
                    if let error {
                        Text(UserFacingError.text(error)).foregroundStyle(AppTheme.destructive)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("invitationError")
                    } else if let page = connectionPage {
                        Text(L("Откроется \(page.host ?? L("страница подключения")) в браузере. На странице нажмите «Открыть OpenStrudel»."))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .formStyle(.grouped)
            #if os(iOS)
            .safeAreaInset(edge: .bottom) {
                Button(action: confirm) { SetupActionLabel(title: continueTitle) }
                    .primaryAction()
                    .disabled(!canContinue)
                    .accessibilityIdentifier("continueConnection")
                    .keyboardShortcut(.defaultAction)
                    .padding(.horizontal, OnboardingLayout.margin).padding(.bottom, 8)
            }
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(onBack == nil ? L("Отмена") : L("Назад")) { if let onBack { onBack() } else { dismiss() } }
                }
                #if os(macOS)
                ToolbarItem(placement: .confirmationAction) {
                    Button(continueTitle, action: confirm)
                        .disabled(!canContinue)
                        .accessibilityIdentifier("continueConnection")
                        .keyboardShortcut(.defaultAction)
                }
                #endif
            }
        }
        .sheetTint()
        #if os(macOS)
        .frame(width: SetupSheet.size.width, height: SetupSheet.size.height)
        #else
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        #endif
        .onChange(of: invitation) { _, _ in error = nil }
    }

    private func confirm() {
        guard !openingPage else { return }
        focused = false
        if let page = connectionPage {
            openingPage = true
            openURL(page) { accepted in
                openingPage = false
                if accepted { dismiss() }
                else { error = L("Не удалось открыть браузер. Откройте ссылку в браузере на этом устройстве и нажмите «Открыть OpenStrudel».") }
            }
            return
        }
        do {
            guard let url = URL(string: invitation.trimmingCharacters(in: .whitespacesAndNewlines)) else { throw HomeClientError.invalidURL }
            let pairing = try MacPairing(url: url)
            onConfirm(pairing); dismiss()
        } catch {
            self.error = L("Это не ссылка подключения OpenStrudel. Скопируйте новую из настроек на устройстве с сотрудниками.")
        }
    }
}
