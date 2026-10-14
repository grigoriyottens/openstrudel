import SwiftUI

/// The OpenAI account an employee uses, as a section of its details sheet.
struct AgentAccountPreference: View {
    @EnvironmentObject private var client: HomeClient
    let profile: EmployeeProfile
    @State private var accounts: [ManagedCodexAccount] = []
    @State private var selection = ""
    @State private var original = ""
    @State private var error: String?
    @State private var busy = false
    private var notes: [String] {
        var notes: [String] = []
        if let device = client.devices.first(where: { $0.id == profile.deviceId }) {
            notes.append(L("Работает на «\(device.id == client.health?.nodeId ? client.displayName : device.name)»"))
        }
        notes.append(L("Выбор изменит следующие поручения. Начатая работа продолжится с прежним аккаунтом."))
        return notes
    }

    var body: some View {
        Section {
            Picker(L("Использовать"), selection: $selection) {
                Text(L("По умолчанию")).tag("")
                ForEach(accounts) { Text($0.identityLabel).tag($0.id) }
            }
            .disabled(!client.canManageOpenAI || busy)
            .task { await load() }
            if selection != original {
                Button(L("Сохранить выбор аккаунта")) {
                    busy = true
                    Task { defer { busy = false }; do {
                        let _: HomeActionResult = try await client.management("/v1/agents/" + profile.id + "/accounts", method: "POST", payload: ["accountIds": selection.isEmpty ? NSNull() : [selection] as Any])
                        original = selection
                    } catch { self.error = error.localizedDescription } }
                }.disabled(busy)
            }
            if let error {
                Text(L10n.serviceText(error)).foregroundStyle(AppTheme.warning).fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            Text(L("Аккаунт OpenAI"))
        } footer: {
            Text(notes.joined(separator: "\n"))
        }
    }

    private func load() async {
        do {
            struct Policy: Decodable { let accountIds: [String]? }
            let result: ManagedCodexAccounts = try await client.management("/v1/accounts" + (profile.deviceId.map { "?deviceId=" + $0 } ?? ""))
            accounts = result.accounts
            let policy: Policy = try await client.management("/v1/agents/" + profile.id + "/accounts")
            if let ids = policy.accountIds, ids.count == 1 { selection = ids[0] }
            else if (policy.accountIds?.count ?? 0) > 1 { error = L("У сотрудника свой порядок аккаунтов. Новый выбор заменит его.") }
            original = selection
        } catch { self.error = error.localizedDescription }
    }
}
