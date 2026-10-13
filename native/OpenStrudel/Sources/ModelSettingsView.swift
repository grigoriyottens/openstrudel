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
    let defaultReasoningEffort: String?
    let speeds: [Speed]
}
struct ModelSettings: Decodable {
    let models: [ModelChoice]
    let selection: ModelSelection
    let defaults: ModelSelection
    let effective: ModelSelection
    let recommended: ModelChoice?
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
    @State private var error: (any Error)?
    @State private var saved = false
    private var path: String { "/v1/settings/models" + (agentID.map { "?agentId=" + $0 } ?? "") }
    private var selected: ModelChoice? {
        guard let settings else { return nil }
        if model.isEmpty && agentID == nil { return settings.recommended }
        let id = model.isEmpty ? settings.defaults.model : model
        return settings.models.first { $0.id == id } ?? (settings.recommended?.id == id ? settings.recommended : nil)
    }
    private var selection: ModelSelection { ModelSelection(model: model.isEmpty ? nil : model, serviceTier: model.isEmpty && agentID != nil ? nil : speed) }
    private var changed: Bool { selection != settings?.selection }

    private var scope: String {
        agentID == nil ? L("По умолчанию для сотрудников на «\(client.displayName)»") : L("Для этого сотрудника · на «\(client.displayName)»")
    }

    /// Rows only: the caller wraps them in a Form section.
    var body: some View {
        Group {
            if let settings {
                Picker(selection: $model) {
                    if agentID != nil {
                        Text(L("Как на устройстве · \(settings.models.first { $0.id == settings.defaults.model }?.name ?? settings.defaults.model ?? "")")).tag("")
                    } else if let recommended = settings.recommended {
                        Text(L("Автоматически · \(recommended.name)")).tag("")
                    }
                    if !model.isEmpty && !settings.models.contains(where: { $0.id == model }) { Text(L("\(model) · unavailable")).tag(model) }
                    ForEach(settings.models) { Text($0.name).tag($0.id) }
                } label: {
                    Text(L("Модель"))
                    Text(scope)
                }
                .accessibilityIdentifier("modelChoice").disabled(saving || !settings.canManage)
                Picker(L("Скорость"), selection: $speed) {
                    ForEach(selected?.speeds ?? []) { Text(L10n.text($0.name)).tag($0.id) }
                    if let selected, !selected.speeds.contains(where: { $0.id == speed }) { Text(L("\(speed) · unavailable")).tag(speed) }
                }
                .accessibilityIdentifier("modelSpeed").disabled((model.isEmpty && agentID != nil) || saving || !settings.canManage)
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        if model.isEmpty && agentID == nil, let recommended = settings.recommended {
                            Text((recommended.isDefault ? L("Рекомендует OpenAI") : L("Модель по умолчанию")) + " · " + (recommended.defaultReasoningEffort ?? "medium").capitalized)
                        }
                        if speed != "default" { Text(L("Ускоренный режим может расходовать больше лимита аккаунта.")) }
                        if !settings.canManage { Text(L("Настройки меняет владелец устройства.")) }
                        Text(saved && !changed ? L("Сохранено. Применится со следующего поручения.") : L("Начатая работа продолжится с прежними настройками."))
                    }
                    .font(AppTypography.meta).foregroundStyle(AppTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    if settings.canManage && changed {
                        Button(saving ? L("Сохраняем…") : L("Применить")) { Task { await save() } }
                            .buttonStyle(.borderedProminent)
                            .disabled(saving || selected == nil || ((agentID == nil || !model.isEmpty) && selected?.speeds.contains(where: { $0.id == speed }) != true))
                            .accessibilityIdentifier("saveModelSelection")
                    }
                }
            } else if loading {
                LabeledContent {
                    ProgressView().controlSize(.small).accessibilityLabel(L("Получаем доступные модели…"))
                } label: {
                    Text(L("Модель"))
                    Text(scope)
                }
            }
            if let error {
                HStack(spacing: 12) {
                    Text(UserFacingError.text(error.localizedDescription)).foregroundStyle(AppTheme.warning)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("modelSettingsError")
                    Spacer(minLength: 0)
                    Button(L("Повторить")) { Task { await load() } }.disabled(saving)
                }
            }
        }
        .task(id: path) { await load() }
        .onChange(of: model) { _, value in
            guard let settings else { return }
            saved = false
            if value.isEmpty && agentID != nil { speed = settings.defaults.serviceTier ?? "default" }
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
        catch { self.error = error }
    }
    private func save() async {
        saving = true; error = nil
        defer { saving = false }
        do {
            let payload: [String: Any] = ["model": selection.model as Any? ?? NSNull(), "serviceTier": selection.serviceTier as Any? ?? NSNull()]
            let result: ModelSettings = try await client.management(path, method: "POST", payload: payload)
            apply(result); saved = true
        } catch is CancellationError { }
        catch { self.error = error }
    }
}
