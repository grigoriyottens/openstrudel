import SwiftUI

private struct ComputerUseSettings: Decodable {
    let available: Bool
    let configured: Bool
    let platform: String
}
struct ComputerUseSettingsView: View {
    @EnvironmentObject private var client: HomeClient
    let conversationID: String
    var isGroup = false
    @State private var settings: ComputerUseSettings?
    @State private var busy = false
    @State private var error: (any Error)?
    private var path: String { "/v1/extensions/computer?conversationId=" + conversationID }
    private var canManage: Bool { client.canManageConnections || client.canManageOpenAI }

    /// Rows only: the caller wraps them in a Form section.
    var body: some View {
        Group {
            LabeledContent {
                if busy || (settings == nil && error == nil) {
                    ProgressView().controlSize(.small).accessibilityLabel(settings == nil ? L("Проверяем Computer Use…") : L("Проверяем подключение…"))
                } else if let settings, settings.configured {
                    Label {
                        Text(L("Подключено через Codex")).foregroundStyle(AppTheme.secondaryText)
                    } icon: {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(AppTheme.accentText)
                    }
                } else if let settings, settings.platform == "darwin", settings.available {
                    Button(L("Подключить Computer Use")) { Task { await change("POST") } }
                        .buttonStyle(.borderedProminent).disabled(!canManage)
                        .accessibilityIdentifier("connectComputerUse")
                }
            } label: {
                Label(L("Управление компьютером"), systemImage: "desktopcomputer")
                if let settings { Text(summary(settings)) }
            }
            if let settings, !settings.configured, settings.platform == "darwin" {
                if isGroup { Text(L("Доступ будет у сотрудника в этой группе Telegram. Участники смогут поручать ему действия на компьютере.")) }
                if !settings.available {
                    Text(L("На этом Mac откройте ChatGPT и включите плагин Computer Use. Затем вернитесь сюда."))
                    Link(L("Как включить Computer Use"), destination: URL(string: "https://learn.chatgpt.com/docs/computer-use")!)
                        .foregroundStyle(AppTheme.accentText)
                    Button(L("Проверить снова")) { Task { await load() } }.disabled(busy)
                }
            }
            if let error {
                HStack(spacing: 12) {
                    Text(UserFacingError.text(error.localizedDescription)).foregroundStyle(AppTheme.warning)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Button(L("Повторить")) { Task { await load() } }.disabled(busy)
                }
            }
            if let settings, settings.configured, canManage {
                Button(L("Отключить"), role: .destructive) { Task { await change("DELETE") } }
                    .foregroundStyle(AppTheme.destructive).disabled(busy)
            }
        }
        .task(id: conversationID) { await load() }
    }

    private func summary(_ settings: ComputerUseSettings) -> String {
        if settings.configured { return L("Сотрудник может работать с окнами на «\(client.displayName)». Codex отдельно запрашивает доступ к нужным приложениям.") }
        if settings.platform == "darwin" { return L("Работа с окнами приложений на «\(client.displayName)» через официальный Computer Use в Codex.") }
        return L("Окнами приложений можно управлять у сотрудника на Mac. На этом устройстве доступны команды, файлы и подключённые сервисы.")
    }
    private func load() async {
        guard !conversationID.isEmpty else { return }
        busy = true; error = nil; settings = nil
        defer { busy = false }
        do { settings = try await client.management(path) }
        catch is CancellationError { }
        catch { self.error = error }
    }
    private func change(_ method: String) async {
        busy = true; error = nil
        defer { busy = false }
        do {
            let _: EmptyResponse = try await client.management(path, method: method, payload: method == "POST" ? ["conversationId":conversationID] : nil)
            settings = try await client.management(path)
        } catch is CancellationError { }
        catch { self.error = error }
    }
    private struct EmptyResponse: Decodable {}
}
