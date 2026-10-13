import SwiftUI
import UniformTypeIdentifiers

/// Connection rows contain controls, not selectable records. A macOS Form
/// exposes each button to keyboard navigation and assistive technologies.
struct ServiceList<Content: View>: View {
    @ViewBuilder let content: () -> Content
    var body: some View {
        #if os(macOS)
        Form(content: content).formStyle(.grouped)
        #else
        List(content: content)
        #endif
    }
}

/// A navigation destination owns its state instead of retaining the presenting view.
struct ConnectionCatalogView: View {
    @EnvironmentObject private var client: HomeClient
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var textSize
    let scope: ExtensionContext
    @Binding var isPresented: Bool
    @State private var connections: [ServiceConnection] = []
    @State private var query = ""
    @State private var loading = true
    @State private var connecting: String?
    @State private var waiting: ServiceConnection?
    @State private var authorizationURL: URL?
    @State private var notice: String?
    @State private var error: String?

    private var results: [ServiceConnection] {
        connections.filter { $0.isAvailableToAdd && (query.isEmpty || $0.name.localizedCaseInsensitiveContains(query)) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    var body: some View {
        ServiceList {
            if loading || error != nil || waiting != nil {
                Section {
                    if loading {
                        Label { Text(L("Загружаем сервисы…")).foregroundStyle(AppTheme.secondaryText) } icon: {
                            ProgressView().controlSize(.small).frame(width: 20)
                        }
                    }
                    if let error {
                        Text(UserFacingError.text(error)).foregroundStyle(AppTheme.warning)
                        Button(L("Повторить")) { Task { await refresh() } }.disabled(loading)
                    }
                    if let waiting {
                        Text(L("Завершите вход в \(waiting.name) в браузере."))
                        if let authorizationURL { Link(L("Открыть ещё раз"), destination: authorizationURL) }
                        Button(L("Проверить подключение")) { Task { await refresh() } }.disabled(loading)
                    }
                }
            }
            if !results.isEmpty || !query.isEmpty {
                Section {
                    if connections.filter(\.isAvailableToAdd).count > 6 {
                        TextField(L("Найти сервис"), text: $query, prompt: Text(L("Найти сервис"))).labelsHidden()
                    }
                    ForEach(results) { connection in
                        // Dynamic Type keeps both the service name and action visible.
                        let layout = textSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(spacing: 12))
                        layout {
                            Label { Text(connection.name) } icon: { Image(systemName: connection.icon).frame(width: 20) }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Button {
                                Task { await connect(connection) }
                            } label: {
                                AdaptiveActionLabel(title: connecting == connection.id ? L("Проверяем…") : waiting?.id == connection.id ? L("Ожидаем входа") : connection.actionTitle)
                            }.adaptiveActionStyle(.bordered).disabled(connecting != nil || waiting != nil)
                                .accessibilityLabel("\(connection.actionTitle) \(connection.name)")
                                .accessibilityIdentifier("connect-service-" + connection.id)
                        }
                        .accessibilityElement(children: .contain)
                    }
                    if results.isEmpty { Text(L("Ничего не найдено")).foregroundStyle(AppTheme.secondaryText) }
                } header: { Text(L("Из аккаунта OpenAI")) } footer: {
                    Text(L("«Добавить» разрешает сотруднику использовать сервис в этом чате."))
                }
            }
            Section {
                NavigationLink { ExtensionSetupView(scope: scope, source: .mcp, isPresented: $isPresented) } label: {
                    DetailsRow(title: L("Сервис по адресу MCP"), symbol: "link")
                }.accessibilityIdentifier("addMCPService")
                NavigationLink { ExtensionSetupView(scope: scope, source: .package, isPresented: $isPresented) } label: {
                    DetailsRow(title: L("Навык или плагин из файла"), symbol: "folder.badge.plus")
                }.accessibilityIdentifier("addExtensionFile")
            } header: { Text(L("Другие способы")) } footer: {
                let notes = [scope.groupNote, scope.sharedNotice, notice.map { L10n.serviceText($0) }].compactMap { $0 }
                if !notes.isEmpty { Text(notes.joined(separator: "\n")) }
            }
        }
        // A subtitle would grow the title bar and resize the sheet; a group's scope sits in the footer.
        .navigationTitle(L("Добавить"))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task { await refresh() }
        .task(id: waiting?.id) {
            guard waiting != nil else { return }
            for _ in 0..<30 {
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
                if !loading { await refresh() }
                if waiting == nil { return }
            }
        }
        .onChange(of: scenePhase) { old, phase in
            if old != .active && phase == .active && !loading { Task { await refresh() } }
        }
    }
    private func refresh() async {
        loading = true; error = nil
        defer { loading = false }
        do {
            let result = try await client.serviceConnections(for: scope.id, refresh: true)
            connections = result.connections; notice = result.notice
            if let waiting, connections.contains(where: { $0.id == waiting.id && $0.connected }) {
                self.waiting = nil; authorizationURL = nil; isPresented = false
            }
        } catch is CancellationError { }
        catch { self.error = error.localizedDescription }
    }
    private func connect(_ connection: ServiceConnection) async {
        connecting = connection.id; error = nil
        defer { connecting = nil }
        do {
            if let url = try await client.connectService(connection.id, for: scope.id) {
                waiting = connection; authorizationURL = url
                openURL(url) { @Sendable accepted in
                    Task { @MainActor in
                        if !accepted { error = L("Не удалось открыть браузер. Используйте ссылку «Открыть ещё раз».") }
                    }
                }
            } else {
                await refresh()
                if connections.contains(where: { $0.id == connection.id && $0.connected }) { isPresented = false }
                else { error = L("Сервис ещё не подтвердил подключение. Попробуйте ещё раз.") }
            }
        } catch is CancellationError { }
        catch { self.error = error.localizedDescription }
    }
}

struct ExtensionSetupView: View {
    enum Source { case mcp, package }
    enum Field: Hashable { case address, token, name }
    @EnvironmentObject private var client: HomeClient
    let scope: ExtensionContext
    var source: Source = .mcp
    @Binding var isPresented: Bool
    @State private var address = ""
    @State private var token = ""
    @State private var name = ""
    @State private var importing = false
    @State private var files: [ExtensionFile] = []
    @State private var preview: ExtensionPreview?
    @State private var busy = false
    @State private var error: String?
    @FocusState private var focusedField: Field?

    private var canAdd: Bool { !busy && !address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        Form {
            if let preview {
                Section {
                    LabeledContent {
                        Text(L("Файлов: \(preview.files) · \(ByteCountFormatter.string(fromByteCount: Int64(preview.bytes), countStyle: .file))"))
                            .foregroundStyle(AppTheme.secondaryText)
                    } label: {
                        Label { Text(preview.name) } icon: {
                            Image(systemName: preview.kind == "skill" ? "sparkles" : "puzzlepiece.extension").frame(width: 20)
                        }
                    }
                    Text(preview.description).fixedSize(horizontal: false, vertical: true)
                    ForEach(preview.services, id: \.self) { service in
                        Label { Text(service) } icon: { Image(systemName: "link").frame(width: 20) }
                    }
                    if preview.hasHooks {
                        Text(L("В пакете есть автоматические действия (hooks). Проверьте, что доверяете его автору."))
                            .foregroundStyle(AppTheme.warning).fixedSize(horizontal: false, vertical: true)
                    }
                    Button(L("Выбрать другой пакет")) { self.preview = nil; files = []; importing = true }.disabled(busy)
                } header: { Text(preview.kind == "skill" ? L("Навык") : L("Плагин")) } footer: {
                    if let note = scope.groupNote { Text(note) }
                }
            } else if source == .mcp {
                Section {
                    TextField(L("Адрес MCP"), text: $address, prompt: Text(verbatim: "https://example.com/mcp"))
                        .focused($focusedField, equals: .address)
                        .textContentType(.URL).autocorrectionDisabled()
                        .accessibilityLabel(L("Адрес MCP")).accessibilityIdentifier("mcpAddress")
                        #if os(iOS)
                        .textInputAutocapitalization(.never).keyboardType(.URL)
                        #endif
                    SecureField(L("Ключ, если сервис его требует"), text: $token)
                        .focused($focusedField, equals: .token)
                    DisclosureGroup(L("Название подключения")) {
                        TextField(L("Название латиницей"), text: $name, prompt: Text(verbatim: suggestedName)).autocorrectionDisabled()
                            .focused($focusedField, equals: .name)
                    }
                } header: { Text(L("Сервис по адресу")) } footer: {
                    Text(([L("Вставьте адрес MCP из настроек нужного сервиса. Если потребуется вход, продолжите его в браузере.")] + [scope.groupNote].compactMap { $0 }).joined(separator: "\n"))
                }
            } else {
                Section {
                    Button { importing = true } label: {
                        Label { Text(L("Выбрать навык или плагин…")) } icon: { Image(systemName: "folder.badge.plus").frame(width: 20) }
                    }.disabled(busy)
                } header: { Text(L("Из файла")) } footer: {
                    Text(([L("Выберите SKILL.md или папку пакета Codex. Сначала покажем, что будет добавлено.")] + [scope.groupNote].compactMap { $0 }).joined(separator: "\n"))
                }
            }
            if busy || error != nil || scope.sharedNotice != nil {
                Section {
                    if busy {
                        Label { Text(preview == nil ? L("Проверяем…") : L("Устанавливаем…")).foregroundStyle(AppTheme.secondaryText) } icon: {
                            ProgressView().controlSize(.small).frame(width: 20)
                        }.accessibilityElement(children: .combine)
                    }
                    if let error { Text(UserFacingError.text(error)).foregroundStyle(AppTheme.warning).fixedSize(horizontal: false, vertical: true) }
                } footer: {
                    if let shared = scope.sharedNotice { Text(shared) }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(source == .mcp ? L("Подключить сервис") : L("Установить из файла"))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        #endif
        .toolbar {
            if let preview {
                ToolbarItem(placement: .confirmationAction) {
                    Button(preview.replaces == nil ? L("Установить") : L("Обновить")) { perform {
                        try await client.installExtension(files, digest: preview.digest, replacing: preview.replaces, for: scope.id)
                        isPresented = false
                    } }.disabled(busy).keyboardShortcut(.defaultAction)
                }
            } else if source == .mcp {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Добавить сервис"), action: addService).disabled(!canAdd).keyboardShortcut(.defaultAction)
                }
            }
            #if os(iOS)
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button { focusedField = nil } label: { Image(systemName: "keyboard.chevron.compact.down") }
                    .accessibilityLabel(L("Скрыть клавиатуру"))
            }
            #endif
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.folder, UTType(filenameExtension: "md") ?? .plainText]) { result in
            switch result {
            case .success(let url):
                perform {
                    let granted = url.startAccessingSecurityScopedResource()
                    defer { if granted { url.stopAccessingSecurityScopedResource() } }
                    let bundle = try await Task.detached { try ExtensionBundleReader.read(url) }.value
                    let checked = try await client.previewExtension(bundle, for: scope.id)
                    files = bundle; preview = checked
                }
            case .failure(let failure): error = failure.localizedDescription
            }
        }
    }

    private func addService() {
        perform {
            try await client.addMCP(name: name.isEmpty ? suggestedName : name, url: address.trimmingCharacters(in: .whitespacesAndNewlines), token: token, for: scope.id)
            token = ""; isPresented = false
        }
    }
    private var suggestedName: String {
        let host = URL(string: address)?.host ?? "service"
        let cleaned = host.lowercased().map { $0.isASCII && ($0.isLetter || $0.isNumber) ? String($0) : "-" }.joined()
        return String(cleaned.prefix(64))
    }
    private func perform(_ action: @escaping @MainActor () async throws -> Void) {
        focusedField = nil; busy = true; error = nil
        Task { defer { busy = false }; do { try await action() } catch is CancellationError { } catch { self.error = error.localizedDescription } }
    }
}

private extension ExtensionContext {
    /// Where an addition applies, said only when it is not this conversation in the app.
    var groupNote: String? { isGroup ? L("Для Telegram-группы «\(title)»") : nil }
}

enum ExtensionBundleReader {
    nonisolated static func read(_ url: URL) throws -> [ExtensionFile] {
        let manager = FileManager.default
        var files: [ExtensionFile] = [], bytes = 0, entries = 0
        func visit(_ item: URL, path: String) throws {
            entries += 1
            guard entries <= 1000, path.count <= 240 else { throw HomeClientError.server(L("Слишком много файлов или вложенных папок.")) }
            let values = try item.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isRegularFileKey, .fileSizeKey])
            guard values.isSymbolicLink != true else { throw HomeClientError.server(L("Выберите пакет с обычными файлами, без символических ссылок.")) }
            if values.isDirectory == true {
                for child in try manager.contentsOfDirectory(at: item, includingPropertiesForKeys: nil) {
                    if [".git", ".DS_Store"].contains(child.lastPathComponent) { continue }
                    try visit(child, path: path.isEmpty ? child.lastPathComponent : path + "/" + child.lastPathComponent)
                }
            } else {
                bytes += values.fileSize ?? 0
                guard values.isRegularFile == true, bytes <= 10 * 1024 * 1024, files.count < 300 else {
                    throw HomeClientError.server(L("Пакет должен содержать не более 300 файлов и занимать до 10 МБ."))
                }
                let data = try Data(contentsOf: item)
                let mode = (try manager.attributesOfItem(atPath: item.path)[.posixPermissions] as? NSNumber)?.intValue ?? 0
                files.append(ExtensionFile(path: path, contentBase64: data.base64EncodedString(), executable: mode & 0o100 != 0))
            }
        }
        let directory = try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true
        try visit(url, path: directory ? "" : url.lastPathComponent)
        return files
    }
}
