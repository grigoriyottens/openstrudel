import SwiftUI

enum EmployeeApprovalMode: String, Codable, CaseIterable, Identifiable {
    case ask, auto, approveAll = "approve_all"
    var id: String { rawValue }
    var title: String {
        switch self {
        case .ask: L("Спрашивать")
        case .auto: L("Автоматически проверять")
        case .approveAll: L("Без подтверждений")
        }
    }
    var explanation: String {
        switch self {
        case .ask: L("Вы подтверждаете действия, которым нужно разрешение.")
        case .auto: L("Codex проверяет такие действия и выполняет разрешённые.")
        case .approveAll: L("Сотрудники выполняют поручения без дополнительных разрешений.")
        }
    }
}

struct EmployeeApprovalSettings: Decodable {
    let mode: EmployeeApprovalMode
    let canManage: Bool
}

/// A whole Form section: the mode as a radio group, its explanation in the footer.
struct ApprovalSettingsView: View {
    @EnvironmentObject private var client: HomeClient
    @State private var settings: EmployeeApprovalSettings?
    @State private var choice: EmployeeApprovalMode?
    @State private var loading = true
    @State private var saving = false
    @State private var error: (any Error)?
    @State private var confirmAll = false

    var body: some View {
        Section { rows } header: {
            Text(L("Действия сотрудников"))
        } footer: {
            if let settings {
                Text((choice ?? settings.mode).explanation + "\n"
                     + (settings.canManage ? L("Режим меняется со следующего поручения. Доступ к сервисам и правила сотрудника сохраняются.") : L("Режим меняет владелец этого устройства.")))
            }
        }
    }

    private var rows: some View {
        Group {
            if let settings {
                let mode = choice ?? settings.mode
                Picker(selection: Binding(get: { mode }, set: choose)) {
                    ForEach(EmployeeApprovalMode.allCases) { option in
                        Text(option.title).tag(option)
                            .accessibilityIdentifier("approvalMode-" + option.rawValue)
                    }
                } label: {
                    Text(L("На «\(client.displayName)» · в приложении и Telegram"))
                }
                #if os(macOS)
                .pickerStyle(.radioGroup)
                #else
                .pickerStyle(.inline)
                #endif
                .disabled(!settings.canManage || saving)
            } else if loading {
                LabeledContent(L("Загружаем режим…")) { ProgressView().controlSize(.small) }
            }
            if let error {
                HStack(spacing: 12) {
                    Text(UserFacingError.text(error.localizedDescription)).foregroundStyle(AppTheme.warning)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Button(L("Повторить")) { Task { await load() } }.disabled(loading || saving)
                }
            }
        }
        .task { await load() }
        .alert(L("Выполнять без подтверждений?"), isPresented: $confirmAll) {
            Button(L("Включить для этого устройства")) { Task { await save(.approveAll) } }
            Button(L("Отмена"), role: .cancel) { }
        } message: {
            Text(L("Все сотрудники на «\(client.displayName)» смогут выполнять порученные действия в доступных сервисах, включая изменение и удаление данных. В Telegram это относится к запросам допущенных участников."))
        }
    }

    private func choose(_ mode: EmployeeApprovalMode) {
        guard let settings, mode != (choice ?? settings.mode) else { return }
        if mode == .approveAll { confirmAll = true }
        else { Task { await save(mode) } }
    }
    private func load() async {
        loading = true; error = nil
        defer { loading = false }
        do { settings = try await client.management("/v1/settings/approvals") }
        catch is CancellationError { }
        catch { self.error = error }
    }
    private func save(_ mode: EmployeeApprovalMode) async {
        saving = true; error = nil; choice = mode
        defer { saving = false; choice = nil }
        do { settings = try await client.management("/v1/settings/approvals", method: "POST", payload: ["mode": mode.rawValue, "confirm": mode == .approveAll]) }
        catch is CancellationError { }
        catch { self.error = error }
    }
}
