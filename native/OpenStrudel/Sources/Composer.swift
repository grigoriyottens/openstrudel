import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct Composer: View {
    @EnvironmentObject private var client: HomeClient
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var textSize
    @Binding var draft: String
    @Binding var files: [PickedFile]
    @FocusState.Binding var focused: Bool
    let contextID: String
    let canSend: Bool
    let send: (ComposerSendMode) -> Void
    @State private var sendMode: ComposerSendMode = .steer
    @State private var showFiles = false
    @State private var showPhotos = false
    @State private var photoSelection: [PhotosPickerItem] = []
    @State private var fileError: String?
    @State private var importTask: Task<Void, Never>?
    @State private var importID = UUID()
    @State private var importing = false
    @StateObject private var voice = VoiceCapture()
    @Environment(\.scenePhase) private var recordingScenePhase
    @ObservedObject private var dictationAssets = DictationAssets.shared
    @State private var showDictation = false
    @State private var editingMessage: HomeMessage?
    @State private var queuedContentHeight: CGFloat = 44
    @State private var dropTargeted = false
    private var hasContent: Bool { !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !files.isEmpty }

    var body: some View {
        composerContents
        .glassEffect(.regular, in: .rect(cornerRadius: 25))
        .overlay { RoundedRectangle(cornerRadius: 25).stroke(AppTheme.accent, lineWidth: dropTargeted ? 2 : 0).allowsHitTesting(false) }
        .onDrop(of: [.fileURL, .image], isTargeted: $dropTargeted) { providers in
            guard voice.phase == .idle else { return false }
            importProviders(providers); return true
        }
        .sheet(isPresented: $showDictation) { DictationSetupView { voice.start() } }
        .sheet(item: $editingMessage) { message in QueuedMessageEditor(message: message).environmentObject(client) }
        .photosPicker(isPresented: $showPhotos, selection: $photoSelection, maxSelectionCount: max(1, AttachmentImport.countLimit - files.count), matching: .images)
        .onChange(of: photoSelection) { _, selection in
            guard !selection.isEmpty else { return }
            let (id, context) = beginImport()
            importTask = Task {
                defer { if importID == id { importing = false; photoSelection = [] } }
                do {
                    var picked: [PickedFile] = []
                    for photo in selection {
                        guard let data = try await photo.loadTransferable(type: Data.self), !data.isEmpty else { throw AttachmentImport.Failure.empty }
                        guard data.count <= AttachmentImport.byteLimit else { throw AttachmentImport.Failure.tooLarge }
                        try Task.checkCancellation()
                        let type = photo.supportedContentTypes.first(where: { $0.conforms(to: .image) }) ?? .jpeg
                        picked.append(PickedFile(name: L("Фото") + "." + (type.preferredFilenameExtension ?? "jpg"), mimeType: type.preferredMIMEType ?? "image/jpeg", data: data))
                    }
                    completeImport(picked, id: id, context: context)
                } catch { reportImportError(error, id: id, context: context) }
            }
        }
        .fileImporter(isPresented: $showFiles, allowedContentTypes: [.data, .image, .pdf, .text, .audio], allowsMultipleSelection: true) { result in
            let (id, context) = beginImport()
            importTask = Task {
                defer { if importID == id { importing = false } }
                do {
                    let urls = try result.get()
                    guard files.count + urls.count <= AttachmentImport.countLimit else {
                        fileError = L("Можно прикрепить до шести файлов. Уберите лишние файлы и попробуйте ещё раз."); return
                    }
                    let selection = try await AttachmentImport.files(at: urls)
                    completeImport(selection, id: id, context: context)
                } catch { reportImportError(error, id: id, context: context) }
            }
        }
        .onAppear { attachVoice() }
        .onChange(of: contextID) { _, _ in editingMessage = nil; cancelImport(); attachVoice() }
        .onDisappear { cancelImport(); voice.detach() }
        .onChange(of: recordingScenePhase) { _, phase in
            #if os(iOS)
            if phase == .background && voice.phase == .recording { voice.finish(send: false) }
            #endif
        }
        .alert(L("Не удалось добавить файл"), isPresented: Binding(get: { fileError != nil }, set: { if !$0 { fileError = nil } })) { Button(L("Понятно"), role: .cancel) {} } message: { Text(fileError ?? "") }
    }

    private var composerContents: some View {
        VStack(alignment: .leading, spacing: 4) {
            if client.health?.turnControlVersion == 1 && !client.visibleQueuedMessages.isEmpty {
                Text(L("После ответа")).font(.caption).foregroundStyle(.secondary).padding(.horizontal, 16).padding(.top, 10)
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(client.visibleQueuedMessages) { queued in
                            HStack(spacing: 4) {
                                Button { editingMessage = queued } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(queued.text.isEmpty ? L("Вложение") : queued.text).lineLimit(2)
                                        if let files = queued.attachments, !files.isEmpty {
                                            Text(files.map(\.name).joined(separator: ", ")).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                        }
                                    }.font(.callout).frame(maxWidth: .infinity, minHeight: controlTarget, alignment: .leading).contentShape(Rectangle())
                                }.buttonStyle(.plain).disabled(client.health?.queueControlVersion != 1)
                                    .accessibilityLabel(L("Edit message: \(queued.text.isEmpty ? L("Вложение") : queued.text)"))
                                    .accessibilityIdentifier("editQueuedMessage-" + queued.id)
                                if client.health?.queueControlVersion == 1 && client.visibleQueuedMessages.count > 1 {
                                    Button { Task { await client.moveQueuedMessageFirst(queued) } } label: {
                                        Image(systemName: "arrow.up.to.line").font(.system(size: 18)).frame(width: controlTarget, height: controlTarget).contentShape(Rectangle())
                                    }.buttonStyle(.plain).disabled(client.visibleQueuedMessages.first?.id == queued.id)
                                        .accessibilityLabel(L("В начало очереди")).help(L("Отправить первым после текущего ответа"))
                                }
                                Button { Task { await client.cancelMessage(queued) } } label: {
                                    Image(systemName: "xmark").font(.system(size: 18)).frame(width: controlTarget, height: controlTarget).contentShape(Rectangle())
                                }.buttonStyle(.plain).accessibilityLabel(L("Убрать сообщение из очереди"))
                            }.padding(.horizontal, 16)
                        }
                    }
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { queuedContentHeight = $0 }
                }
                .frame(height: min(168, queuedContentHeight))
                .scrollBounceBehavior(.basedOnSize)
            }
            if !files.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(files) { file in
                            HStack(spacing: 8) {
                                if file.mimeType.hasPrefix("image/"), let image = ChatMedia.thumbnail(file.data) {
                                    Image(decorative: image, scale: 1).resizable().scaledToFill()
                                        .frame(width: 48, height: 48).clipShape(RoundedRectangle(cornerRadius: 8))
                                } else { Image(systemName: "doc").foregroundStyle(AppTheme.secondaryText).frame(width: 28) }
                                Text(file.name).font(.caption).lineLimit(1)
                                Button { files.removeAll { $0.id == file.id } } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(AppTheme.secondaryText).frame(width: controlTarget, height: controlTarget).contentShape(Rectangle()) }
                                    .buttonStyle(.plain).accessibilityLabel(L("Remove \(file.name)"))
                            }.padding(5).background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))
                        }
                    }.padding(.horizontal, 12).padding(.top, 9)
                }.scrollIndicators(.hidden)
            }
            if voice.phase != .idle {
                VoiceRecordingRow(voice: voice, canSend: canSend)
            } else {
                if !voice.detail.isEmpty { Text(L10n.serviceText(voice.detail)).font(.caption).foregroundStyle(.secondary).padding(.horizontal, 16).padding(.top, 8) }
                inputRow
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
            }
        }
    }

    @ViewBuilder private var inputRow: some View {
        if textSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 0) {
                draftField.padding(.horizontal, 7)
                HStack(spacing: 9) { attachmentMenu; Spacer(minLength: 0); inputActions }
            }
        } else {
            HStack(alignment: .bottom, spacing: 9) { attachmentMenu; draftField; inputActions }
        }
    }

    private var attachmentMenu: some View {
        Menu {
                Button(L("Фото"), systemImage: "photo") { showPhotos = true }
                Button(L("Прикрепить файл"), systemImage: "paperclip") { showFiles = true }
                Divider()
                Button(L("Голосовой ввод…"), systemImage: "mic") { showDictation = true }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(AppTheme.secondaryText)
                    .frame(width: controlTarget, height: controlTarget).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(AppTheme.secondaryText)
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: controlTarget, height: controlTarget)
            .accessibilityLabel(L("Прикрепить фото или файл"))
            .help(files.count >= AttachmentImport.countLimit ? L("Можно прикрепить до шести файлов") : L("Прикрепить фото или файл до 25 МБ"))
            .disabled(importing || files.count >= AttachmentImport.countLimit)
    }

    @ViewBuilder private var draftField: some View {
        #if os(macOS)
        ComposerTextField(text: $draft, focused: Binding(get: { focused }, set: { focused = $0 }), paste: { providers in
            guard voice.phase == .idle else { return }
            importProviders(providers)
        }, submit: { if canSend && hasContent && !importing { send(sendMode) } })
            .overlay(alignment: .leading) {
                if draft.isEmpty { Text(L("Сообщение")).font(ChatTypography.body).foregroundStyle(AppTheme.secondaryText).allowsHitTesting(false).accessibilityHidden(true) }
            }
            .padding(.vertical, 8).frame(minHeight: controlTarget)
        #else
        TextField(L("Сообщение"), text: $draft, axis: .vertical)
                .accessibilityLabel(L("Сообщение")).accessibilityIdentifier("messageComposer")
                .textFieldStyle(.plain)
                .font(ChatTypography.body)
                .lineLimit(1...(textSize.isAccessibilitySize ? 2 : 6))
                .padding(.vertical, 8)
                .frame(minHeight: controlTarget)
                .focused($focused)
                .onSubmit { if canSend && hasContent && !importing { send(sendMode) } }
        #endif
    }

    @ViewBuilder private var inputActions: some View {
            if client.isSending && client.health?.turnControlVersion == 1 {
                Menu {
                    Picker(L("Отправка во время ответа"), selection: $sendMode) {
                        ForEach(ComposerSendMode.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                } label: {
                    Image(systemName: sendMode == .steer ? "arrow.turn.down.right" : "clock")
                        .font(.system(size: 18))
                        .frame(width: controlTarget, height: controlTarget).contentShape(Rectangle())
                }.menuStyle(.borderlessButton).menuIndicator(.hidden)
                    .accessibilityLabel(sendMode.title).help(sendMode.title)
            }

            if importing {
                ProgressView().controlSize(.small).frame(width: controlTarget, height: controlTarget)
                    .accessibilityLabel(L("Добавляем файлы"))
            } else {
                Button {
                    focused = true
                    Task {
                        await dictationAssets.check()
                        if dictationAssets.state == .ready && UserDefaults.standard.bool(forKey: "openstrudel.dictationIntroduced") { voice.start() }
                        else { showDictation = true }
                    }
                } label: { Image(systemName: "mic").font(.system(size: 18)).frame(width: controlTarget, height: controlTarget).contentShape(Rectangle()) }
                    .buttonStyle(.plain).accessibilityLabel(L("Голосовой ввод")).accessibilityIdentifier("voiceInput")
                sendButton
            }
    }

    private var canStop: Bool { !hasContent && client.activeMessage != nil && client.health?.turnControlVersion == 1 }

    private var sendButton: some View {
        Button {
            if !hasContent, let active = client.activeMessage, client.health?.turnControlVersion == 1 { Task { await client.cancelMessage(active) } }
            else { send(sendMode) }
        } label: {
            Image(systemName: canStop ? "stop.fill" : "arrow.up")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(colorScheme == .dark ? Color.black : Color.white)
                .frame(width: 30, height: 30)
                .background(colorScheme == .dark ? Color.white : Color.black, in: Circle())
                .frame(width: controlTarget, height: controlTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!canSend || (!hasContent && !canStop))
        .opacity(canSend && (hasContent || canStop) ? 1 : 0.4)
        .accessibilityLabel(canStop ? L("Остановить ответ") : client.isSending ? sendMode.title : L("Отправить"))
        .accessibilityIdentifier("sendMessage")
        .help(canStop ? L("Остановить текущий ответ") : L("Отправить сообщение (⌘Return)"))
        .keyboardShortcut(hasContent ? KeyboardShortcut(.return, modifiers: .command) : nil)
    }

    private func attachVoice() {
        voice.attach(context: contextID) { text, sendNow in
            draft = draft.isEmpty ? text : draft + "\n" + text
            focused = true
            if sendNow && client.isConfigured && !client.connectionNeedsPairing && client.openAIAccount?.connected != false { send(sendMode) }
        }
    }

    private func importProviders(_ providers: [NSItemProvider]) {
        guard !providers.isEmpty, !importing, voice.phase == .idle else { return }
        guard files.count + providers.count <= AttachmentImport.countLimit else { fileError = L("Можно прикрепить до шести файлов."); return }
        let (id, context) = beginImport()
        importTask = Task {
            defer { if importID == id { importing = false } }
            do { completeImport(try await AttachmentImport.providers(providers), id: id, context: context) }
            catch { reportImportError(error, id: id, context: context) }
        }
    }

    private func beginImport() -> (UUID, String) {
        importTask?.cancel()
        importID = UUID()
        importing = true
        fileError = nil
        return (importID, contextID)
    }

    private func completeImport(_ selection: [PickedFile], id: UUID, context: String) {
        guard importID == id, contextID == context, !Task.isCancelled else { return }
        guard files.count + selection.count <= AttachmentImport.countLimit else {
            fileError = L("Можно прикрепить до шести файлов."); return
        }
        files.append(contentsOf: selection)
    }

    private func reportImportError(_ error: Error, id: UUID, context: String) {
        guard importID == id, contextID == context, !AttachmentImport.isCancellation(error), !Task.isCancelled else { return }
        fileError = (error as? AttachmentImport.Failure)?.errorDescription ?? L("Не удалось открыть файл. Проверьте, что он доступен на устройстве, и выберите его ещё раз.")
    }

    private func cancelImport() {
        importTask?.cancel()
        importID = UUID()
        importing = false
        photoSelection = []
        fileError = nil
        showFiles = false
        showPhotos = false
    }

}

struct QueuedMessageEditor: View {
    @EnvironmentObject private var client: HomeClient
    @Environment(\.dismiss) private var dismiss
    let message: HomeMessage
    @State private var text: String
    @State private var saving = false
    @State private var error: String?
    @FocusState private var focused: Bool

    init(message: HomeMessage) { self.message = message; _text = State(initialValue: message.text) }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                TextEditor(text: $text).font(.body).focused($focused)
                    .frame(minHeight: 160).accessibilityLabel(L("Текст сообщения в очереди"))
                    .accessibilityIdentifier("queuedMessageText")
                if let files = message.attachments, !files.isEmpty {
                    ForEach(files) { file in Label(file.name, systemImage: file.icon).font(.callout).foregroundStyle(.secondary) }
                }
                if let error { Text(L10n.serviceText(error)).font(.callout).foregroundStyle(AppTheme.warning).textSelection(.enabled) }
            }.padding(24).background(HomeBackground())
                .navigationTitle(L("Изменить сообщение"))
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button(L("Отмена")) { dismiss() }.disabled(saving).keyboardShortcut(.cancelAction) }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(saving ? L("Сохраняем…") : L("Сохранить")) {
                            saving = true; error = nil
                            Task {
                                do { try await client.editQueuedMessage(message, text: text); dismiss() }
                                catch { self.error = error.localizedDescription }
                                saving = false
                            }
                        }.disabled(saving || text == message.text || (text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && (message.attachments ?? []).isEmpty))
                    }
                }
        }
        #if os(macOS)
        .frame(minWidth: 420, idealWidth: 520, minHeight: 300, idealHeight: 380)
        #endif
        .interactiveDismissDisabled(saving)
        .onAppear { focused = true }
    }
}
