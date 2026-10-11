import SwiftUI

struct ModelSelection: Codable, Equatable {
    let model: String?
    let serviceTier: String?
}
struct ModelChoice: Decodable, Identifiable {
    struct Speed: Decodable, Identifiable { let id: String; let name: String; let description: String }
    let id: String
    let name: String
    let description: String
    let isDefault: Bool
    let speeds: [Speed]
}
struct ModelSettings: Decodable {
    let models: [ModelChoice]
    let selection: ModelSelection
    let defaults: ModelSelection
    let effective: ModelSelection
    let canManage: Bool
}

/// The device owns the choice; every client and Telegram use it on the next turn.
struct ModelSettingsView: View {
    @EnvironmentObject private var client: HomeClient
    var agentID: String? = nil
    @State private var settings: ModelSettings?
    @State private var model = ""
    @State private var speed = "default"
    @State private var loading = true
    @State private var saving = false
    @State private var error: String?
    @State private var saved = false
    private var path: String { "/v1/settings/models" + (agentID.map { "?agentId=" + $0 } ?? "") }
    private var selected: ModelChoice? { settings?.models.first { $0.id == (model.isEmpty ? settings?.defaults.model : model) } }
    private var selection: ModelSelection { ModelSelection(model: model.isEmpty ? nil : model, serviceTier: model.isEmpty ? nil : speed) }
    private var changed: Bool { selection != settings?.selection }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Модель и скорость").font(.headline)
            Text(agentID == nil ? "По умолчанию для сотрудников на «\(client.displayName)»" : "Для этого сотрудника · на «\(client.displayName)»")
                .font(.caption).foregroundStyle(AppTheme.secondaryText).fixedSize(horizontal: false, vertical: true)
            if loading { ProgressView("Получаем доступные модели…").controlSize(.small) }
            if let settings {
                Picker("Модель", selection: $model) {
                    if agentID != nil {
                        Text("Как на устройстве · \(settings.models.first { $0.id == settings.defaults.model }?.name ?? settings.defaults.model ?? "")").tag("")
                    }
                    if !model.isEmpty && !settings.models.contains(where: { $0.id == model }) { Text(model + " · недоступна").tag(model) }
                    ForEach(settings.models) { Text($0.name).tag($0.id) }
                }.accessibilityIdentifier("modelChoice").disabled(saving || !settings.canManage)
                Picker("Скорость", selection: $speed) {
                    ForEach(selected?.speeds ?? []) { Text($0.name).tag($0.id) }
                    if let selected, !selected.speeds.contains(where: { $0.id == speed }) { Text(speed + " · недоступна").tag(speed) }
                }.accessibilityIdentifier("modelSpeed").disabled(model.isEmpty || saving || !settings.canManage)
                if speed != "default" {
                    Text("Ускоренный режим может расходовать больше лимита аккаунта.")
                        .font(.caption).foregroundStyle(AppTheme.secondaryText).fixedSize(horizontal: false, vertical: true)
                }
                if !settings.canManage {
                    Text("Настройки меняет владелец устройства.").font(.caption).foregroundStyle(AppTheme.secondaryText)
                } else if changed {
                    Button(saving ? "Сохраняем…" : "Применить") { Task { await save() } }
                        .buttonStyle(.borderedProminent).disabled(saving || selected == nil || (!model.isEmpty && selected?.speeds.contains(where: { $0.id == speed }) != true))
                        .accessibilityIdentifier("saveModelSelection")
                }
                Text(saved && !changed ? "Сохранено. Применится со следующего поручения." : "Начатая работа продолжится с прежними настройками.")
                    .font(.caption).foregroundStyle(AppTheme.secondaryText).fixedSize(horizontal: false, vertical: true)
            }
            if let error {
                Text(error).font(.callout).foregroundStyle(AppTheme.warning).accessibilityIdentifier("modelSettingsError")
                Button("Повторить") { Task { await load() } }.disabled(saving)
            }
        }
        .task(id: path) { await load() }
        .onChange(of: model) { _, value in
            guard let settings else { return }
            saved = false
            if value.isEmpty { speed = settings.defaults.serviceTier ?? "default" }
            else if selected?.speeds.contains(where: { $0.id == speed }) != true { speed = "default" }
        }
    }
    private func apply(_ value: ModelSettings) {
        settings = value; model = value.selection.model ?? ""
        speed = value.selection.serviceTier ?? value.defaults.serviceTier ?? "default"
    }
    private func load() async {
        loading = true; error = nil
        defer { loading = false }
        do { let result: ModelSettings = try await client.management(path); apply(result) }
        catch is CancellationError { }
        catch { self.error = UserFacingError.text(error.localizedDescription) }
    }
    private func save() async {
        saving = true; error = nil
        defer { saving = false }
        do {
            let payload: [String: Any] = ["model": selection.model as Any? ?? NSNull(), "serviceTier": selection.serviceTier as Any? ?? NSNull()]
            let result: ModelSettings = try await client.management(path, method: "POST", payload: payload)
            apply(result); saved = true
        } catch is CancellationError { }
        catch { self.error = UserFacingError.text(error.localizedDescription) }
    }
}
