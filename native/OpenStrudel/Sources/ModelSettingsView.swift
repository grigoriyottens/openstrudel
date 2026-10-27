import SwiftUI

/// The device owns the choice; every client and Telegram use it on the next turn.
/// Choosing a model chooses its provider, so a provider and a model can never disagree.
struct ModelSettingsView: View {
    @EnvironmentObject private var client: HomeClient
    var agentID: String? = nil
    var conversationID: String? = nil
    private var inherits: Bool { agentID != nil || conversationID != nil }
    /// The employee card shows its OpenAI account only while the saved model runs on ChatGPT.
    var onLoad: (ModelSettings) -> Void = { _ in }
    @State private var settings: ModelSettings?
    /// Nil: as on the device, or automatic for the device itself.
    @State private var choice: ModelRef?
    @State private var speed = "default"
    @State private var reasoning = ""
    @State private var fallbacks: [ModelSelection] = []
    @State private var loading = true
    @State private var saving = false
    @State private var error: (any Error)?
    @State private var saved = false
    @State private var loadedFor = LoadedKey<String>()
    private var path: String { conversationID.map { "/v1/conversations/" + $0 + "/model" } ?? "/v1/settings/models" + (agentID.map { "?agentId=" + $0 } ?? "") }
    private var selected: ModelChoice? {
        guard let settings else { return nil }
        if choice == nil && !inherits { return settings.recommended }
        let ref = choice ?? settings.defaults.ref
        return settings.model(ref) ?? (settings.recommended?.ref == ref ? settings.recommended : nil)
    }
    private var selection: ModelSelection { ModelSelection(provider: choice?.provider, model: choice?.model, serviceTier: choice == nil && inherits ? nil : speed, reasoningEffort: choice == nil && inherits || reasoning.isEmpty ? nil : reasoning) }
    private var changed: Bool { selection != settings?.selection || !inherits && fallbacks != (settings?.fallbacks ?? []) }
    /// One speed needs no choice; an unavailable saved speed stays visible so it can be changed.
    private var showsSpeed: Bool {
        guard let selected else { return false }
        return selected.speeds.count > 1 || !selected.speeds.contains { $0.id == speed }
    }

    /// The first row: what an employee inherits, or what Automatic picks for the device.
    private func defaultTitle(_ settings: ModelSettings) -> String {
        if conversationID != nil { return L("Как у сотрудника · \(settings.model(settings.defaults.ref).map(settings.title) ?? settings.defaults.model ?? "")") }
        if inherits { return L("Как на устройстве · \(settings.model(settings.defaults.ref).map(settings.title) ?? settings.defaults.model ?? "")") }
        return settings.recommended.map { L("Автоматически · \(settings.title($0))") } ?? ""
    }
    /// Rows sit under their provider's header; the closed picker names the provider itself.
    private func choiceTitle(_ settings: ModelSettings) -> String {
        guard let choice else { return defaultTitle(settings) }
        return settings.model(choice).map(settings.title) ?? L("\(choice.model) · unavailable")
    }

    private var scope: String {
        conversationID != nil ? L("Только для этого чата · на «\(client.displayName)»") : !inherits ? L("По умолчанию для сотрудников на «\(client.displayName)»") : L("Для этого сотрудника · на «\(client.displayName)»")
    }

    /// Rows only: the caller wraps them in a Form section.
    var body: some View {
        Group {
            if let settings {
                Picker(selection: $choice) {
                    if inherits || settings.recommended != nil { Text(defaultTitle(settings)).tag(ModelRef?.none) }
                    if let choice, settings.model(choice) == nil { Text(L("\(choice.model) · unavailable")).tag(Optional(choice)) }
                    ForEach(settings.groups) { group in
                        if let provider = group.provider {
                            Section { options(group.models) } header: { Text(verbatim: provider.name) }
                        } else {
                            options(group.models)
                        }
                    }
                } label: {
                    Text(L("Модель"))
                    Text(scope)
                } currentValueLabel: {
                    Text(choiceTitle(settings))
                }
                .accessibilityIdentifier("modelChoice").disabled(saving || !settings.canManage)
                if !(selected?.reasoningEfforts ?? []).isEmpty || !reasoning.isEmpty {
                    Picker(L("Обдумывание"), selection: $reasoning) {
                        Text(L("Автоматически")).tag("")
                        ForEach(selected?.reasoningEfforts ?? []) { Text(L10n.text($0.name)).tag($0.id) }
                        if !reasoning.isEmpty && !(selected?.reasoningEfforts ?? []).contains(where: { $0.id == reasoning }) { Text(L("\(reasoning) · unavailable")).tag(reasoning) }
                    }
                    .accessibilityIdentifier("modelReasoning").disabled((choice == nil && inherits) || saving || !settings.canManage)
                }
                if showsSpeed {
                    Picker(L("Скорость"), selection: $speed) {
                        ForEach(selected?.speeds ?? []) { Text(L10n.text($0.name)).tag($0.id) }
                        if let selected, !selected.speeds.contains(where: { $0.id == speed }) { Text(L("\(speed) · unavailable")).tag(speed) }
                    }
                    .accessibilityIdentifier("modelSpeed").disabled((choice == nil && inherits) || saving || !settings.canManage)
                }
                if !inherits && settings.fallbacks != nil { reserves(settings) }
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        if choice == nil && !inherits, let recommended = settings.recommended {
                            Text(settings.recommendation(recommended))
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
                            .disabled(saving || selected == nil || ((!inherits || choice != nil) && (selected?.speeds.contains(where: { $0.id == speed }) != true || (!reasoning.isEmpty && selected?.reasoningEfforts?.contains(where: { $0.id == reasoning }) != true))))
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
        .task(id: path) { if loadedFor.claim(path) { await load() } }
        .onChange(of: choice) { _, value in
            guard let settings else { return }
            saved = false
            if value == nil && inherits { speed = settings.defaults.serviceTier ?? "default"; reasoning = settings.defaults.reasoningEffort ?? "" }
            else {
                fallbacks.removeAll { $0.ref == selected?.ref }
                if selected?.speeds.contains(where: { $0.id == speed }) != true { speed = "default" }
                if selected?.reasoningEfforts?.contains(where: { $0.id == reasoning }) != true { reasoning = "" }
            }
        }
    }
    private func options(_ models: [ModelChoice]) -> some View {
        ForEach(models, id: \.ref) { Text($0.name).tag(Optional($0.ref)) }
    }
    @ViewBuilder private func reserves(_ settings: ModelSettings) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L("Резервные модели")).font(AppTypography.meta)
            Text(L("При исчерпании лимита — следующая по порядку. Когда лимит вернётся — снова основная. Ключи API оплачиваются отдельно."))
                .font(AppTypography.meta).foregroundStyle(AppTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(fallbacks.indices, id: \.self) { index in
                HStack(spacing: 10) {
                    Text("\(index + 1).").foregroundStyle(AppTheme.secondaryText)
                    Text(settings.model(fallbacks[index].ref).map(settings.title) ?? fallbacks[index].model ?? "")
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Button { fallbacks.swapAt(index, index - 1) } label: { Image(systemName: "arrow.up") }
                        .accessibilityLabel(L("Выше")).disabled(index == 0)
                    Button { fallbacks.swapAt(index, index + 1) } label: { Image(systemName: "arrow.down") }
                        .accessibilityLabel(L("Ниже")).disabled(index == fallbacks.count - 1)
                    Button { fallbacks.remove(at: index) } label: { Image(systemName: "minus.circle") }
                        .accessibilityLabel(L("Удалить резерв"))
                }.buttonStyle(.borderless)
            }
            Menu(L("Добавить резерв")) {
                ForEach(settings.models.filter { model in model.ref != selected?.ref && !fallbacks.contains { $0.ref == model.ref } }, id: \.ref) { model in
                    Button(settings.title(model)) { fallbacks.append(ModelSelection(provider: model.provider, model: model.id, serviceTier: "default")) }
                }
            }.accessibilityIdentifier("addModelFallback")
        }.disabled(saving || !settings.canManage)
    }
    private func apply(_ value: ModelSettings) {
        settings = value; choice = value.selection.ref
        fallbacks = value.fallbacks ?? []
        speed = value.selection.serviceTier ?? value.defaults.serviceTier ?? "default"
        reasoning = value.selection.reasoningEffort ?? (value.selection.model == nil && inherits ? value.defaults.reasoningEffort : nil) ?? ""
        onLoad(value)
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
            var payload: [String: Any] = ["provider": selection.provider as Any? ?? NSNull(), "model": selection.model as Any? ?? NSNull(),
                                          "serviceTier": selection.serviceTier as Any? ?? NSNull(), "reasoningEffort": selection.reasoningEffort as Any? ?? NSNull()]
            if !inherits && settings?.fallbacks != nil {
                payload["fallbacks"] = fallbacks.map { ["provider": $0.provider as Any? ?? NSNull(), "model": $0.model as Any? ?? NSNull(), "serviceTier": $0.serviceTier ?? "default", "reasoningEffort": $0.reasoningEffort as Any? ?? NSNull()] }
            }
            let result: ModelSettings = try await client.management(path, method: "POST", payload: payload)
            apply(result); saved = true
            // Another provider can open or close the chat's account gate.
            await client.refreshConversation()
            await client.refreshOpenAIAccount()
        } catch is CancellationError { }
        catch { self.error = error }
    }
}
