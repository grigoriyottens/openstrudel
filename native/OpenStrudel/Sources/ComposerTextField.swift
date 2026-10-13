import SwiftUI

/// The direction of a block's first letter; digits, spaces and punctuation are neutral. English
/// stays left-aligned in the Hebrew interface, and Hebrew is right-aligned in English.
enum ReadingDirection {
    static func of(_ text: some StringProtocol) -> LayoutDirection? {
        for scalar in text.unicodeScalars where scalar.properties.isAlphabetic {
            switch scalar.value {
            // Hebrew, Arabic, Syriac, Thaana, NKo and their presentation forms.
            case 0x0590...0x08FF, 0xFB1D...0xFDFF, 0xFE70...0xFEFF: return .rightToLeft
            default: return .leftToRight
            }
        }
        return nil
    }
}

#if os(macOS)
import AppKit
import UniformTypeIdentifiers

/// NSTextView owns paste so images work from both Command-V and Edit > Paste.
/// Plain text, selection, undo, input methods and spelling stay native.
struct ComposerTextField: NSViewRepresentable {
    @Binding var text: String
    @Binding var focused: Bool
    let placeholder: String
    let paste: ([NSItemProvider]) -> Void
    let submit: () -> Void
    /// The field grows to this many lines, then scrolls.
    static let maximumLines = 8

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = false
        let editor = ComposerEditor()
        editor.isRichText = false
        editor.drawsBackground = false
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
        let font = Self.readingFont(in: context.environment.fontResolutionContext)
        let interface = context.environment.layoutDirection
        if editor.typingAttributes[.font] as? NSFont != font || editor.interfaceDirection != ComposerEditor.writingDirection(interface) {
            Self.style(editor, font: font, interface: interface)
        }
        editor.onPaste = paste; editor.onSubmit = submit
        editor.placeholder = placeholder
        editor.setAccessibilityLabel(L("Сообщение"))
        editor.toolTip = L("Return отправляет сообщение. Shift+Return добавляет новую строку.")
        if editor.string != text {
            editor.string = text
            Self.style(editor, font: font, interface: interface)
            editor.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
            // Dictation and restored drafts end at the caret; show it once SwiftUI has sized the field.
            DispatchQueue.main.async { [weak editor] in editor?.scrollRangeToVisible(editor?.selectedRange() ?? NSRange()) }
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

    /// The reading token as AppKit sees it, so the draft and the sent message share one face.
    static func readingFont(in context: Font.Context) -> NSFont {
        AppTypography.reading.resolve(in: context).ctFont as NSFont
    }

    /// SwiftUI sets a line as the rounded ascender plus the rounded descender (19 pt at 15 pt).
    /// TextKit sets the same font a point tighter, so the minimum height restores 15/22.
    static func lineHeight(for font: NSFont) -> CGFloat {
        ceil(font.ascender) + ceil(-font.descender) + font.leading
    }

    /// Each paragraph sits on the side its first letter reads from; AppKit's natural alignment
    /// would follow the app bundle's language instead of the interface language.
    static func paragraphStyle(for font: NSFont, direction: NSWritingDirection = .natural) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = AppTypography.readingLineSpacing
        style.minimumLineHeight = lineHeight(for: font)
        if direction != .natural {
            style.baseWritingDirection = direction
            style.alignment = direction == .rightToLeft ? .right : .left
        }
        return style
    }

    /// Typed, pasted and restored text all take the reading style.
    static func style(_ editor: NSTextView, font: NSFont, interface: LayoutDirection = .leftToRight) {
        let direction = ComposerEditor.writingDirection(interface)
        let style = paragraphStyle(for: font, direction: direction)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .paragraphStyle: style, .foregroundColor: NSColor.labelColor]
        editor.font = font
        editor.textColor = .labelColor
        editor.defaultParagraphStyle = style
        editor.typingAttributes = attributes
        if let storage = editor.textStorage, storage.length > 0, !editor.hasMarkedText() {
            storage.setAttributes(attributes, range: NSRange(location: 0, length: storage.length))
        }
        guard let editor = editor as? ComposerEditor else { return }
        editor.interfaceDirection = direction
        editor.alignParagraphs()
        editor.refreshPlaceholder()
    }

    /// Padding that sets one line on a control row. The odd point goes below, where TextKit
    /// has already placed the extra point of the line above the text.
    static func insets(for font: NSFont, controlHeight: CGFloat) -> (top: CGFloat, bottom: CGFloat) {
        let slack = max(0, controlHeight - lineHeight(for: font))
        let top = floor(slack / 2)
        return (top, slack - top)
    }

    static func fittingSize(for editor: NSTextView, width proposedWidth: CGFloat) -> CGSize {
        let width = proposedWidth.isFinite ? max(1, proposedWidth) : 400
        // SwiftUI probes several widths during layout. Measuring the live text
        // container resizes NSTextView and invalidates that same layout again.
        let measured = NSMutableAttributedString(attributedString: editor.attributedString())
        // A zero-width space in the typing style measures the empty field and a trailing blank line.
        measured.append(NSAttributedString(string: "\u{200B}", attributes: editor.typingAttributes))
        let storage = NSTextStorage(attributedString: measured)
        let layout = NSLayoutManager()
        let container = NSTextContainer(size: NSSize(width: width, height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = editor.textContainer?.lineFragmentPadding ?? 0
        layout.addTextContainer(container)
        storage.addLayoutManager(layout)
        layout.ensureLayout(for: container)
        let font = editor.typingAttributes[.font] as? NSFont ?? editor.font ?? .systemFont(ofSize: NSFont.systemFontSize)
        let line = lineHeight(for: font)
        let spacing = (editor.typingAttributes[.paragraphStyle] as? NSParagraphStyle)?.lineSpacing ?? 0
        let cap = CGFloat(maximumLines) * line + CGFloat(maximumLines - 1) * spacing
        return CGSize(width: width, height: min(cap, max(line, ceil(layout.usedRect(for: container).maxY))))
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ComposerTextField
        init(_ parent: ComposerTextField) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            guard let editor = notification.object as? NSTextView else { return }
            parent.text = editor.string
            // The field may grow with this change; keep the caret in view once SwiftUI has resized it.
            DispatchQueue.main.async { [weak editor] in editor?.scrollRangeToVisible(editor?.selectedRange() ?? NSRange()) }
        }
        func textDidBeginEditing(_ notification: Notification) { parent.focused = true }
        func textDidEndEditing(_ notification: Notification) { parent.focused = false }
    }
}

final class ComposerEditor: NSTextView {
    var pasteboard: NSPasteboard = .general
    var onPaste: (([NSItemProvider]) -> Void)?
    var onSubmit: (() -> Void)?
    var placeholder = "" {
        didSet { if placeholder != oldValue { refreshPlaceholder() } }
    }
    /// The side an empty field and the placeholder start from.
    var interfaceDirection: NSWritingDirection = .leftToRight

    static func writingDirection(_ layout: LayoutDirection) -> NSWritingDirection {
        layout == .rightToLeft ? .rightToLeft : .leftToRight
    }

    static func direction(of text: some StringProtocol) -> NSWritingDirection? {
        ReadingDirection.of(text).map(writingDirection)
    }

    /// Aligns every paragraph by its first letter. A paragraph without letters follows the one
    /// before it, and the first one follows the interface.
    func alignParagraphs() {
        guard let storage = textStorage, !hasMarkedText(), let readingFont = typingAttributes[.font] as? NSFont ?? font else { return }
        let text = storage.string as NSString
        let caret = min(selectedRange().location, text.length)
        var location = 0, previous = interfaceDirection, typing = interfaceDirection
        storage.beginEditing()
        while location < text.length {
            let range = text.paragraphRange(for: NSRange(location: location, length: 0))
            let direction = Self.direction(of: text.substring(with: range)) ?? previous
            let style = ComposerTextField.paragraphStyle(for: readingFont, direction: direction)
            if storage.attribute(.paragraphStyle, at: range.location, effectiveRange: nil) as? NSParagraphStyle != style {
                storage.addAttribute(.paragraphStyle, value: style, range: range)
            }
            if caret >= range.location { typing = direction }
            previous = direction
            location = NSMaxRange(range)
        }
        storage.endEditing()
        typingAttributes[.paragraphStyle] = ComposerTextField.paragraphStyle(for: readingFont, direction: typing)
    }
    /// Set in the typing style by TextKit, so the placeholder sits exactly where the first letter will.
    private(set) var placeholderString: NSAttributedString?
    private let placeholderStorage = NSTextStorage()
    private lazy var placeholderLayout: NSLayoutManager = {
        let layout = NSLayoutManager()
        let container = NSTextContainer()
        container.lineFragmentPadding = 0
        layout.addTextContainer(container)
        placeholderStorage.addLayoutManager(layout)
        return layout
    }()

    func refreshPlaceholder() {
        defer { needsDisplay = true }
        guard !placeholder.isEmpty else { placeholderString = nil; setAccessibilityPlaceholderValue(nil); return }
        var attributes = typingAttributes
        let base = (attributes[.font] as? NSFont).map { ComposerTextField.paragraphStyle(for: $0, direction: interfaceDirection) } ?? defaultParagraphStyle ?? .default
        let style = base.mutableCopy() as! NSMutableParagraphStyle
        style.lineBreakMode = .byTruncatingTail
        attributes[.paragraphStyle] = style
        attributes[.foregroundColor] = NSColor(named: "SecondaryText") ?? .secondaryLabelColor
        let placeholderString = NSAttributedString(string: placeholder, attributes: attributes)
        self.placeholderString = placeholderString
        placeholderStorage.setAttributedString(placeholderString)
        setAccessibilityPlaceholderValue(placeholder)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty, !hasMarkedText(), placeholderString != nil, let container = placeholderLayout.textContainers.first else { return }
        let origin = textContainerOrigin
        container.lineFragmentPadding = textContainer?.lineFragmentPadding ?? 0
        container.size = NSSize(width: max(1, bounds.width - 2 * origin.x), height: .greatestFiniteMagnitude)
        placeholderLayout.drawGlyphs(forGlyphRange: placeholderLayout.glyphRange(for: container), at: origin)
    }

    override func didChangeText() {
        alignParagraphs()
        super.didChangeText()
        // The placeholder spans the line; typing the first letter only invalidates that letter.
        needsDisplay = true
    }

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
