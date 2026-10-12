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
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(L("Управление компьютером"), systemImage: "desktopcomputer").font(.headline)
            if let settings {
                if settings.configured {
                    Label(L("Подключено через Codex"), systemImage: "checkmark.circle.fill").foregroundStyle(AppTheme.accent)
                    Text(L("Сотрудник может работать с окнами на «\(client.displayName)». Codex отдельно запрашивает доступ к нужным приложениям."))
                        .font(.callout).foregroundStyle(AppTheme.secondaryText)
                    if client.canManageConnections || client.canManageOpenAI {
                        Button(L("Отключить"), role: .destructive) { Task { await change("DELETE") } }.disabled(busy)
                    }
                } else if settings.platform == "darwin" {
                    Text(L("Работа с окнами приложений на «\(client.displayName)» через официальный Computer Use в Codex."))
                        .font(.callout).foregroundStyle(AppTheme.secondaryText)
                    if isGroup { Text(L("Доступ будет у сотрудника в этой группе Telegram. Участники смогут поручать ему действия на компьютере.")).font(.callout) }
                    if settings.available {
                        Button(L("Подключить Computer Use")) { Task { await change("POST") } }
                            .buttonStyle(.borderedProminent).disabled(busy || !(client.canManageConnections || client.canManageOpenAI))
                            .accessibilityIdentifier("connectComputerUse")
                    } else {
                        Text(L("На этом Mac откройте ChatGPT и включите плагин Computer Use. Затем вернитесь сюда."))
                            .font(.callout)
                        Link(L("Как включить Computer Use"), destination: URL(string: "https://learn.chatgpt.com/docs/computer-use")!)
                        Button(L("Проверить снова")) { Task { await load() } }.disabled(busy)
                    }
                } else {
                    Text(L("Окнами приложений можно управлять у сотрудника на Mac. На этом устройстве доступны команды, файлы и подключённые сервисы."))
                        .font(.callout).foregroundStyle(AppTheme.secondaryText)
                }
            } else if !busy && error == nil { ProgressView(L("Проверяем Computer Use…")).controlSize(.small) }
            if busy { ProgressView(L("Проверяем подключение…")).controlSize(.small) }
            if let error {
                Text(UserFacingError.text(error.localizedDescription)).font(.callout).foregroundStyle(AppTheme.warning)
                Button(L("Повторить")) { Task { await load() } }.disabled(busy)
            }
        }.fixedSize(horizontal: false, vertical: true)
            .task(id: conversationID) { await load() }
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
