import SwiftUI

struct SpeechSettings: Decodable {
    struct Voice: Decodable, Identifiable { let id: String; let name: String }
    let provider: String
    let connected: Bool
    let voiceId: String?
    let voices: [Voice]
    let canManage: Bool
}

/// The same choice is used by dictation, attachments and this device's Telegram bot.
struct SpeechSettingsView: View {
    @EnvironmentObject private var client: HomeClient
    var compact = false
    var onEditingChange: (Bool) -> Void = { _ in }
    var onLoad: (SpeechSettings) -> Void = { _ in }
    var onProviderChange: (String) -> Void = { _ in }
    @State private var settings: SpeechSettings?
    @State private var provider = "local"
    @State private var key = ""
    @State private var voiceId = ""
    @State private var saving = false
    @State private var error: String?
    private var changed: Bool { provider != settings?.provider || !key.isEmpty || voiceId != (settings?.voiceId ?? "") }

    var body: some View {
        Group {
            if let settings {
                Picker(L("Распознавание"), selection: $provider) {
                    Text(L("На устройстве")).tag("local")
                    Text("ElevenLabs").tag("elevenlabs")
                }
                .disabled(saving || !settings.canManage).accessibilityIdentifier("speechProvider")
                if provider == "elevenlabs" {
                    Text(L("Аудио отправляется в ElevenLabs. Ключ хранится на устройстве сотрудника."))
                        .font(AppTypography.meta).foregroundStyle(AppTheme.secondaryText)
                    if settings.canManage {
                        SecureField(settings.connected ? L("Новый ключ ElevenLabs") : L("API-ключ ElevenLabs"), text: $key)
                            .textContentType(.password).autocorrectionDisabled()
                            .accessibilityIdentifier("speechAPIKey")
                    }
                    if settings.connected { Label(L("ElevenLabs подключён"), systemImage: "checkmark.circle").font(AppTypography.meta) }
                }
                if settings.connected && !compact && !settings.voices.isEmpty {
                    Picker(L("Голос для озвучивания"), selection: $voiceId) {
                        ForEach(settings.voices) { Text(verbatim: $0.name).tag($0.id) }
                    }
                    .disabled(saving || !settings.canManage).accessibilityIdentifier("speechVoice")
                    Text(L("Сотрудник озвучит ответ, когда вы попросите. Используется ElevenLabs."))
                        .font(AppTypography.meta).foregroundStyle(AppTheme.secondaryText)
                }
                if settings.canManage && changed {
                    Button(saving ? L("Сохраняем…") : L("Применить")) { Task { await save() } }
                        .disabled(saving || provider == "elevenlabs" && !settings.connected && key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("saveSpeechSettings")
                }
                if settings.connected && settings.canManage && !compact {
                    Button(L("Удалить ключ ElevenLabs"), role: .destructive) { Task { await save(removeKey: true) } }.disabled(saving)
                }
                if !settings.canManage { Text(L("Настройки меняет владелец устройства.")).font(AppTypography.meta).foregroundStyle(AppTheme.secondaryText) }
            } else if error == nil {
                ProgressView().controlSize(.small)
            }
            if let error {
                Text(error).foregroundStyle(AppTheme.warning).fixedSize(horizontal: false, vertical: true)
                if settings == nil { Button(L("Повторить")) { Task { await load() } } }
            }
        }
        .task(id: client.id) { await load() }
        .onChange(of: changed) { _, value in onEditingChange(value) }
        .onChange(of: provider) { _, value in onProviderChange(value) }
    }

    private func apply(_ value: SpeechSettings) {
        settings = value; provider = value.provider; voiceId = value.voiceId ?? ""; key = ""; error = nil; onLoad(value)
    }
    private func load() async {
        do { apply(try await client.management("/v1/settings/speech")) }
        catch { self.error = UserFacingError.text(error.localizedDescription) }
    }
    private func save(removeKey: Bool = false) async {
        saving = true; error = nil; defer { saving = false }
        var payload: [String: Any] = removeKey ? ["removeKey": true] : ["provider": provider]
        if !removeKey {
            if !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { payload["key"] = key.trimmingCharacters(in: .whitespacesAndNewlines) }
            if voiceId != settings?.voiceId && !voiceId.isEmpty { payload["voiceId"] = voiceId }
        }
        do { apply(try await client.management("/v1/settings/speech", method: "POST", payload: payload)) }
        catch { self.error = UserFacingError.text(error.localizedDescription) }
    }
}
