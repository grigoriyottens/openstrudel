#if os(macOS)
import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// NSTextView owns paste so images work from both Command-V and Edit > Paste.
/// Plain text, selection, undo, input methods and spelling stay native.
struct ComposerTextField: NSViewRepresentable {
    @Binding var text: String
    @Binding var focused: Bool
    let paste: ([NSItemProvider]) -> Void
    let submit: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = false
        let editor = ComposerEditor()
        editor.isRichText = false
        editor.drawsBackground = false
        editor.font = .systemFont(ofSize: 15)
        editor.textColor = .labelColor
        editor.textContainerInset = .zero
        editor.textContainer?.lineFragmentPadding = 0
        editor.textContainer?.widthTracksTextView = true
        editor.isVerticallyResizable = true
        editor.isHorizontallyResizable = false
        editor.autoresizingMask = [.width]
        editor.allowsUndo = true
        editor.delegate = context.coordinator
        editor.setAccessibilityIdentifier("messageComposer")
        scroll.documentView = editor
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let editor = scroll.documentView as? ComposerEditor else { return }
        editor.onPaste = paste; editor.onSubmit = submit
        editor.setAccessibilityLabel(L("Сообщение"))
        editor.toolTip = L("Return отправляет сообщение. Shift+Return добавляет новую строку.")
        if editor.string != text {
            editor.string = text
            editor.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
        }
        if focused, scroll.window?.firstResponder !== editor {
            DispatchQueue.main.async { [weak scroll, weak editor] in
                guard let editor, context.coordinator.parent.focused else { return }
                scroll?.window?.makeFirstResponder(editor)
            }
        }
    }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSScrollView, context: Context) -> CGSize? {
        guard let editor = nsView.documentView as? NSTextView else { return nil }
        return Self.fittingSize(for: editor, width: proposal.width ?? 400)
    }
    static func fittingSize(for editor: NSTextView, width proposedWidth: CGFloat) -> CGSize {
        let width = proposedWidth.isFinite ? max(1, proposedWidth) : 400
        // SwiftUI probes several widths during layout. Measuring the live text
        // container resizes NSTextView and invalidates that same layout again.
        let storage = NSTextStorage(attributedString: editor.attributedString())
        let layout = NSLayoutManager()
        let container = NSTextContainer(size: NSSize(width: width, height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = editor.textContainer?.lineFragmentPadding ?? 0
        layout.addTextContainer(container)
        storage.addLayoutManager(layout)
        layout.ensureLayout(for: container)
        let height = max(layout.usedRect(for: container).maxY, layout.extraLineFragmentUsedRect.maxY)
        return CGSize(width: width, height: min(126, max(20, ceil(height))))
    }
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ComposerTextField
        init(_ parent: ComposerTextField) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            guard let editor = notification.object as? NSTextView else { return }
            parent.text = editor.string
        }
        func textDidBeginEditing(_ notification: Notification) { parent.focused = true }
        func textDidEndEditing(_ notification: Notification) { parent.focused = false }
    }
}

final class ComposerEditor: NSTextView {
    var pasteboard: NSPasteboard = .general
    var onPaste: (([NSItemProvider]) -> Void)?
    var onSubmit: (() -> Void)?
    override func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(paste(_:)), isEditable, onPaste != nil,
           pasteboard.types?.contains(where: { $0 == .fileURL || UTType($0.rawValue)?.conforms(to: .image) == true }) == true {
            return true
        }
        return super.validateMenuItem(menuItem)
    }
    override func paste(_ sender: Any?) {
        let providers = AttachmentImport.pasteboardProviders(pasteboard)
        if !providers.isEmpty, let onPaste { onPaste(providers) }
        else { super.paste(sender) }
    }
    override func keyDown(with event: NSEvent) {
        if [36, 76].contains(event.keyCode), !event.modifierFlags.contains(.shift), !hasMarkedText() {
            onSubmit?()
        } else { super.keyDown(with: event) }
    }
}
#endif
