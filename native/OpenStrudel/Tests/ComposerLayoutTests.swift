#if os(macOS)
import AppKit
import SwiftUI
import Testing

@MainActor
struct ComposerLayoutTests {
    /// The composer reads the same 15/22 reading style as the transcript.
    private func readingEditor(_ text: String = "", interface: LayoutDirection = .leftToRight) -> ComposerEditor {
        let editor = ComposerEditor(frame: NSRect(x: 0, y: 0, width: 320, height: 60))
        editor.string = text
        ComposerTextField.style(editor, font: ComposerTextField.readingFont(in: EnvironmentValues().fontResolutionContext), interface: interface)
        return editor
    }

    private func alignments(_ editor: NSTextView) -> [NSTextAlignment] {
        let text = editor.string as NSString
        var result: [NSTextAlignment] = [], location = 0
        while location < text.length {
            let paragraph = text.paragraphRange(for: NSRange(location: location, length: 0))
            result.append((editor.textStorage?.attribute(.paragraphStyle, at: paragraph.location, effectiveRange: nil) as? NSParagraphStyle)?.alignment ?? .natural)
            location = NSMaxRange(paragraph)
        }
        return result
    }

    private func typingAlignment(_ editor: NSTextView) -> NSTextAlignment? {
        (editor.typingAttributes[.paragraphStyle] as? NSParagraphStyle)?.alignment
    }

    @Test func readsTheReadingToken() {
        let font = ComposerTextField.readingFont(in: EnvironmentValues().fontResolutionContext)
        #expect(font.pointSize == 15)
        let editor = readingEditor()
        let style = editor.typingAttributes[.paragraphStyle] as? NSParagraphStyle
        #expect(style?.lineSpacing == AppTypography.readingLineSpacing)
        #expect(editor.defaultParagraphStyle == style)
        #expect(editor.typingAttributes[.font] as? NSFont == font)
    }

    @Test func proposedWidthsDoNotChangeTheLiveEditor() throws {
        let editor = readingEditor("A draft with enough words to wrap at different widths.\nВторая строка.")
        editor.setSelectedRange(NSRange(location: 4, length: 5))
        let container = try #require(editor.textContainer)
        let originalContainerSize = container.containerSize
        let originalFrame = editor.frame
        let originalSelection = editor.selectedRange()
        for width: CGFloat in [1, 140, 760, 320, 140, 760] {
            _ = ComposerTextField.fittingSize(for: editor, width: width)
            #expect(container.containerSize == originalContainerSize)
            #expect(editor.frame == originalFrame)
            #expect(editor.selectedRange() == originalSelection)
        }
    }

    @Test func linesMatchTheTranscriptLeading() {
        // SwiftUI renders 15-pt reading text as 19-pt lines 22 apart (15/22).
        let editor = readingEditor()
        #expect(ComposerTextField.fittingSize(for: editor, width: 320).height == 19)
        editor.string = "One"
        #expect(ComposerTextField.fittingSize(for: editor, width: 320).height == 19)
        editor.string = "One\nTwo"
        #expect(ComposerTextField.fittingSize(for: editor, width: 320).height == 41)
        editor.string = Array(repeating: "line", count: 8).joined(separator: "\n")
        #expect(ComposerTextField.fittingSize(for: editor, width: 320).height == 173)
    }

    @Test func growsToEightLinesThenScrolls() {
        let editor = readingEditor("A longer draft. Ещё одна строка. שלום עולם. Une autre phrase. Un mensaje más.")
        let narrow = ComposerTextField.fittingSize(for: editor, width: 140)
        let wide = ComposerTextField.fittingSize(for: editor, width: 760)
        #expect(narrow.height > wide.height)
        #expect(narrow.height <= 173)
        editor.string = Array(repeating: "line", count: 9).joined(separator: "\n")
        #expect(ComposerTextField.fittingSize(for: editor, width: 140).height == 173)
        editor.string = Array(repeating: "line", count: 100).joined(separator: "\n")
        #expect(ComposerTextField.fittingSize(for: editor, width: 140).height == 173)
        editor.string = ""
        #expect(ComposerTextField.fittingSize(for: editor, width: 140).height == 19)
    }

    @Test func measuresTheBlankLineAndBoundsWidthProposals() {
        let editor = readingEditor("First line")
        let first = ComposerTextField.fittingSize(for: editor, width: 320)
        editor.string += "\n"
        #expect(ComposerTextField.fittingSize(for: editor, width: 320).height == first.height + 22)
        #expect(ComposerTextField.fittingSize(for: editor, width: 0).width == 1)
        #expect(ComposerTextField.fittingSize(for: editor, width: .infinity).width == 400)
        #expect(ComposerTextField.fittingSize(for: editor, width: .nan).width == 400)
    }

    @Test func oneLineFillsTheControlRow() {
        let font = ComposerTextField.readingFont(in: EnvironmentValues().fontResolutionContext)
        let insets = ComposerTextField.insets(for: font, controlHeight: 32)
        #expect(insets.top + ComposerTextField.lineHeight(for: font) + insets.bottom == 32)
        #expect(abs(insets.top - insets.bottom) <= 1)
    }

    @Test func eachParagraphAlignsByItsFirstLetter() {
        let mixed = readingEditor("שלום, מה שלומך?\nHello there\n123 שלום", interface: .leftToRight)
        #expect(alignments(mixed) == [.right, .left, .right])
        let english = readingEditor("Plain English in the Hebrew interface", interface: .rightToLeft)
        #expect(alignments(english) == [.left])
        let blankLine = readingEditor("שלום\n\nHello", interface: .leftToRight)
        #expect(alignments(blankLine) == [.right, .right, .left])
    }

    @Test func anEmptyFieldStartsOnTheInterfaceSide() throws {
        let hebrew = readingEditor(interface: .rightToLeft)
        hebrew.placeholder = "הודעה ל־Launch Manager"
        #expect(typingAlignment(hebrew) == .right)
        let placeholder = try #require(hebrew.placeholderString?.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)
        #expect(placeholder.alignment == .right)
        #expect(typingAlignment(readingEditor(interface: .leftToRight)) == .left)
    }

    @Test func typingRealignsTheParagraph() {
        let editor = readingEditor(interface: .leftToRight)
        editor.insertText("שלום", replacementRange: NSRange(location: 0, length: 0))
        #expect(alignments(editor) == [.right])
        #expect(typingAlignment(editor) == .right)
        editor.insertText("\nNext line", replacementRange: editor.selectedRange())
        #expect(alignments(editor) == [.right, .left])
    }

    @Test func placeholderSitsWhereTypedTextStarts() throws {
        let editor = readingEditor()
        editor.placeholder = "Message Launch Manager"
        let placeholder = try #require(editor.placeholderString)
        let attributes = placeholder.attributes(at: 0, effectiveRange: nil)
        #expect(attributes[.font] as? NSFont == editor.typingAttributes[.font] as? NSFont)
        let style = try #require(attributes[.paragraphStyle] as? NSParagraphStyle)
        let typing = try #require(editor.typingAttributes[.paragraphStyle] as? NSParagraphStyle)
        #expect(style.lineSpacing == typing.lineSpacing)
        #expect(style.minimumLineHeight == typing.minimumLineHeight)
        #expect(style.lineBreakMode == .byTruncatingTail)
        editor.placeholder = ""
        #expect(editor.placeholderString == nil)
    }
}
#endif
