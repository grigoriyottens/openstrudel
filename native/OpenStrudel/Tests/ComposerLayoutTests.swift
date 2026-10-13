#if os(macOS)
import AppKit
import Testing

@MainActor
struct ComposerLayoutTests {
    @Test func proposedWidthsDoNotChangeTheLiveEditor() throws {
        let editor = NSTextView(frame: NSRect(x: 0, y: 0, width: 320, height: 60))
        editor.font = .systemFont(ofSize: 15)
        editor.string = "A draft with enough words to wrap at different widths.\nВторая строка."
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

    @Test func wrapsAndShrinksAfterSending() {
        let editor = NSTextView()
        editor.font = .systemFont(ofSize: 15)
        editor.string = "A longer draft. Ещё одна строка. שלום עולם. Une autre phrase. Un mensaje más."
        let narrow = ComposerTextField.fittingSize(for: editor, width: 140)
        let wide = ComposerTextField.fittingSize(for: editor, width: 760)
        #expect(narrow.height > wide.height)
        #expect(narrow.height <= 126)
        editor.string = ""
        #expect(ComposerTextField.fittingSize(for: editor, width: 140).height == 20)
        editor.string = Array(repeating: "line", count: 100).joined(separator: "\n")
        #expect(ComposerTextField.fittingSize(for: editor, width: 140).height == 126)
    }

    @Test func measuresTheBlankLineAndBoundsWidthProposals() {
        let editor = NSTextView()
        editor.font = .systemFont(ofSize: 15)
        editor.string = "First line"
        let first = ComposerTextField.fittingSize(for: editor, width: 320)
        editor.string += "\n"
        #expect(ComposerTextField.fittingSize(for: editor, width: 320).height > first.height)
        #expect(ComposerTextField.fittingSize(for: editor, width: 0).width == 1)
        #expect(ComposerTextField.fittingSize(for: editor, width: .infinity).width == 400)
        #expect(ComposerTextField.fittingSize(for: editor, width: .nan).width == 400)
    }
}
#endif
