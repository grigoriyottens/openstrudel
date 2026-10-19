import SwiftUI

struct DiagnosticsView: View {
    @ObservedObject var client: HomeClient
    @Environment(\.dismiss) private var dismiss
    @State private var report: DeviceDiagnosticReport?
    @State private var connectionEvents: [ConnectionDiagnosticEvent] = []
    @State private var detailed = false
    @State private var loading = false
    @State private var error: String?
    @State private var export = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent(L("Устройство"), value: client.displayName)
                    if let speech = report?.speech {
                        LabeledContent(L("Распознавание"), value: speech.provider == "elevenlabs" ? "ElevenLabs · Scribe v2" : L("На устройстве"))
                    }
                    Toggle(L("Подробный журнал"), isOn: Binding(get: { detailed }, set: { value in Task { await setDetailed(value) } }))
                        .settingsSwitch().disabled(loading).accessibilityIdentifier("detailedDiagnostics")
                    HStack {
                        Button(L("Обновить")) { Task { await load() } }.disabled(loading)
                        Spacer()
                        ShareLink(item: export) { Label(L("Экспорт журнала"), systemImage: "square.and.arrow.up") }.disabled(export.isEmpty)
                    }
                } footer: {
                    Text(L("Сохраняем состояния связи и результаты распознавания. Подробный режим добавляет начало операций и время запросов. Ключи, записи и текст разговоров в журнал не попадают."))
                }
                if let error { Section { Text(error).foregroundStyle(AppTheme.warning) } }
                if client.health != nil && client.health?.diagnosticsVersion != 1 {
                    Section { Text(L("Обновите OpenStrudel на этом устройстве, чтобы видеть журнал распознавания.")) }
                }
                if let events = report?.events, !events.isEmpty {
                    Section(L("События на устройстве")) {
                        ForEach(events.prefix(20)) { event in
                            eventRow(title(event.event), time: event.date,
                                     detail: [event.provider == "elevenlabs" ? "ElevenLabs" : event.provider == "local" ? L("На устройстве") : nil,
                                              event.durationMs.map { String(format: "%.1f s", Double($0) / 1000) },
                                              event.status.map { "HTTP \($0)" }, event.reason.map(reason)].compactMap { $0 }.joined(separator: " · "),
                                     failed: event.event.hasSuffix("failed") || event.event.hasSuffix("disconnected"))
                        }
                    }
                }
                Section(L("Связь с этого приложения")) {
                    if connectionEvents.isEmpty { Text(L("Событий пока нет.")).foregroundStyle(AppTheme.secondaryText) }
                    ForEach(connectionEvents.prefix(20)) { event in
                        eventRow(title(event.kind.rawValue), time: event.time,
                                 detail: [event.status.map { "HTTP \($0)" }, event.code.map { "URLSession \($0)" },
                                          event.durationMs.map { "\($0) ms" }].compactMap { $0 }.joined(separator: " · "),
                                 failed: event.kind == .requestFailed || event.kind == .unavailable)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(L("Диагностика"))
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(L("Готово")) { dismiss() } } }
        }
        #if os(macOS)
        .frame(width: 580, height: 560)
        #endif
        .task { detailed = client.connectionJournal.detailed; await load() }
    }

    private func eventRow(_ title: String, time: Date, detail: String, failed: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).foregroundStyle(failed ? AppTheme.warning : Color.primary)
                Spacer(minLength: 12)
                Text(time, format: .dateTime.day().month().hour().minute().second()).foregroundStyle(AppTheme.secondaryText)
            }
            if !detail.isEmpty { Text(detail).font(AppTypography.meta).foregroundStyle(AppTheme.secondaryText) }
        }
        .textSelection(.enabled)
    }

    private func load() async {
        loading = true; error = nil; defer { loading = false; snapshot() }
        guard client.health?.diagnosticsVersion == 1 else { return }
        do { report = try await client.management("/v1/diagnostics"); detailed = client.connectionJournal.detailed || report?.level == "detailed" }
        catch { self.error = UserFacingError.text(error.localizedDescription) }
    }

    private func setDetailed(_ value: Bool) async {
        loading = true; error = nil; defer { loading = false; snapshot() }
        do {
            if client.health?.diagnosticsVersion == 1 {
                report = try await client.management("/v1/diagnostics", method: "POST", payload: ["level": value ? "detailed" : "standard"])
            }
            client.connectionJournal.detailed = value; detailed = value
        } catch { self.error = UserFacingError.text(error.localizedDescription) }
    }

    private func snapshot() {
        connectionEvents = client.connectionJournal.events
        let version = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
        let local = (try? encoder.encode(connectionEvents)).map { String(decoding: $0, as: UTF8.self) } ?? "[]"
        let remote = report?.events.map { "\($0.time) \($0.event) provider=\($0.provider ?? "-") durationMs=\($0.durationMs ?? 0) status=\($0.status ?? 0) reason=\($0.reason ?? "-")" }.joined(separator: "\n") ?? ""
        export = "OpenStrudel \(version)\nConnection\n\(local)\nDevice\n\(remote)"
    }

    private func title(_ value: String) -> String {
        switch value {
        case "speech.started": L("Распознавание началось")
        case "speech.completed": L("Запись распознана")
        case "speech.failed": L("Не удалось распознать запись")
        case "telegram.connected": L("Связь с Telegram восстановлена")
        case "telegram.disconnected": L("Нет связи с Telegram")
        case "service.started": L("OpenStrudel запущен")
        case "connected": L("Связь установлена")
        case "connecting": L("Подключаемся…")
        case "unavailable": L("Нет связи · попробуем снова")
        case "removed": L("Подключение удалено на этом устройстве")
        case "requestFailed": L("Запрос не выполнен")
        case "requestCompleted": L("Запрос выполнен")
        default: value
        }
    }
    private func reason(_ value: String) -> String {
        switch value {
        case "provider_auth": L("Проверьте ключ ElevenLabs")
        case "provider_limit": L("Лимит ElevenLabs")
        case "network": L("Ошибка сети")
        case "timeout": L("Время ожидания истекло")
        case "cancelled": L("Отменено")
        case "invalid_audio", "empty_audio": L("Не удалось прочитать речь")
        case "file_too_large": L("Файл больше 20 МБ")
        case "local_recognition": L("Ошибка распознавания на устройстве")
        default: L("Сервис временно недоступен")
        }
    }
}
