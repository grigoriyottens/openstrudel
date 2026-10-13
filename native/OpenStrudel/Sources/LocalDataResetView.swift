#if os(macOS)
import SwiftUI

/// The last row of General settings; its explanation is the section footer.
struct LocalDataResetButton: View {
    @State private var showing = false
    var body: some View {
        Button(L("Стереть данные OpenStrudel на этом Mac…"), role: .destructive) { showing = true }
            .foregroundStyle(AppTheme.destructive)
            .accessibilityIdentifier("eraseLocalData")
            .sheet(isPresented: $showing) { LocalDataResetConfirmation() }
    }
}

struct LocalDataResetConfirmation: View {
    @EnvironmentObject private var library: DeviceLibrary
    @Environment(\.dismiss) private var dismiss
    @State private var acknowledged = false
    @State private var preparingBackup = false
    @State private var backup: HomeClient?
    @State private var backupError: String?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text(L("Стереть данные этого Mac?")).font(AppTypography.title)
                Text(L("Сотрудники, которые работают на этом Mac, их чаты, файлы и расписания будут удалены. С других устройств они тоже станут недоступны."))
                Text(L("Сохранённые входы и подключения будут сброшены. Сотрудники на других Mac и серверах продолжат работать. Оплата серверов не остановится."))
                    .foregroundStyle(AppTheme.secondaryText)
                HStack(spacing: 8) {
                    Button(L("Сначала сохранить копию…")) {
                        preparingBackup = true; backupError = nil
                        Task {
                            let local = library.clients.first(where: \.isLocalConnection) ?? library.newConnection()
                            if local.health == nil { await local.startLocalHome() }
                            if local.health != nil { backup = local }
                            else { backupError = local.errorMessage ?? L("Не удалось открыть сотрудников этого Mac для копии.") }
                            preparingBackup = false
                        }
                    }
                    .disabled(preparingBackup).accessibilityIdentifier("backupBeforeErase")
                    if preparingBackup { ProgressView().controlSize(.small) }
                }
                .padding(.top, 4)
                if let message = backupError ?? library.eraseError {
                    Text(message).foregroundStyle(AppTheme.destructive)
                }
                Toggle(L("Я понимаю, что удаление нельзя отменить"), isOn: $acknowledged)
                    .toggleStyle(.checkbox)
                    .padding(.top, 4)
                    .accessibilityIdentifier("acknowledgeLocalErase")
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(24)
            .frame(width: 440, alignment: .leading)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L("Отмена")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Стереть данные"), role: .destructive) { Task { await library.eraseThisMac() } }
                        .disabled(!acknowledged || preparingBackup)
                        .accessibilityIdentifier("confirmLocalErase")
                }
            }
        }
        .presentationSizing(.fitted)
        .sheet(item: $backup) { client in
            NavigationStack {
                Form {
                    Section { AgentTransferSettings(localBackupOnly: true).environmentObject(client) }
                }
                .formStyle(.grouped)
                .navigationTitle(L("Копия сотрудников этого Mac"))
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button(L("Готово")) { backup = nil } } }
            }
            .frame(width: 480, height: 320)
            .presentationSizing(.fitted)
        }
    }
}

/// Replaces every window while this Mac's data is erased: the character, one sentence, one action.
struct LocalDataResetProgress: View {
    @EnvironmentObject private var library: DeviceLibrary
    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 16) {
                Image("Agent-main").resizable().scaledToFit()
                    .frame(width: AvatarSize.hero, height: AvatarSize.hero)
                    .accessibilityHidden(true)
                VStack(spacing: 8) {
                    Text(library.erased ? L("Этот Mac готов к новому началу") : L("Сброс OpenStrudel"))
                        .font(AppTypography.display)
                    if let phase = library.erasePhase {
                        Text(phase).foregroundStyle(AppTheme.secondaryText)
                    } else if library.erased {
                        Text(L("Местные данные и сохранённые входы удалены.")).foregroundStyle(AppTheme.secondaryText)
                    } else {
                        Text(library.eraseError ?? L("Предыдущий сброс не завершился. Продолжите удаление данных этого Mac."))
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                }
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
                Group {
                    if library.erasePhase != nil {
                        VStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text(L("Это может занять некоторое время. Не закрывайте приложение."))
                                .font(AppTypography.meta).foregroundStyle(AppTheme.secondaryText)
                        }
                    } else if library.erased {
                        Button(L("Начать заново")) { library.startAfterErase() }
                            .buttonStyle(.borderedProminent).buttonBorderShape(.capsule).controlSize(.large)
                            .accessibilityIdentifier("startAfterErase")
                    } else {
                        HStack(spacing: 12) {
                            Button(L("Закрыть OpenStrudel")) { NSApp.terminate(nil) }.controlSize(.large)
                            Button(L("Продолжить сброс")) { Task { await library.eraseThisMac() } }
                                .buttonStyle(.borderedProminent).buttonBorderShape(.capsule).controlSize(.large)
                        }
                    }
                }
                .padding(.top, 8)
            }
            .padding(24)
            .frame(maxWidth: .infinity)
            .position(x: proxy.size.width / 2, y: proxy.size.height * 0.4)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("localEraseProgress")
    }
}
#endif
