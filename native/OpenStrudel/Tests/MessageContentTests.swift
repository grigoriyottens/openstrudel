import Testing
import SwiftUI
import AppKit

@MainActor
struct MessageContentTests {
    @Test func importedFileKeepsCaptionAndReadableText() {
        let text = "До\n<file name=\"Пример.pdf\" mime=\"application/pdf\">\n<<<EXTERNAL_UNTRUSTED_CONTENT id=\"abc\">>>\nSource: External\n---\nПервая строка\nВторая строка\n<<<END_EXTERNAL_UNTRUSTED_CONTENT id=\"abc\">>>\n</file>\nПосле"
        #expect(ImportedTranscript.parts(text) == [.text("До"), .file(name: "Пример.pdf", text: "Первая строка\nВторая строка"), .text("После")])
    }

    @Test func importedMultipleFilesStayInOrderAndDoNotFetchPaths() {
        let text = "<file name=\"/private/example.txt\" mime=\"text/plain\">Один</file>\nПодпись\n<file name=\"Второй.txt\" mime=\"text/plain\">Два</file>"
        #expect(ImportedTranscript.parts(text) == [.file(name: "/private/example.txt", text: "Один"), .text("Подпись"), .file(name: "Второй.txt", text: "Два")])
    }

    @Test func malformedImportAndOrdinaryTextAreNotLost() {
        for text in ["Обычный текст", "<file name=\"test\">незакрытый файл", "<<<EXTERNAL_UNTRUSTED_CONTENT>>> Текст"] {
            #expect(ImportedTranscript.parts(text) == [.text(text)])
        }
        let raw = "<<<EXTERNAL_UNTRUSTED_CONTENT id=\"a\">>>\nSource: External\n---\nТекст\n<<<END_EXTERNAL_UNTRUSTED_CONTENT id=\"b\">>>"
        #expect(ImportedTranscript.parts("<file name=\"test.txt\" mime=\"text/plain\">\(raw)</file>") == [.file(name: "test.txt", text: raw)])
    }

    @Test func imagesRemainVisibleBetweenText() {
        let blocks = MessageContent(source: "До ![Стул](https://example.com/chair.jpg) после").blocks
        #expect(blocks.map(\.kind) == ["paragraph", "image", "paragraph"])
        #expect(blocks.first(where: { $0.kind == "image" }).map { String($0.content.characters) } == "Стул")
    }

    @Test func consecutiveImagesRemainSeparate() {
        let blocks = MessageContent(source: "![Первый](https://example.com/a.jpg) ![Второй](https://example.com/b.jpg)").blocks
        #expect(blocks.filter { $0.kind == "image" }.count == 2)
    }

    /// A web picture named in a reply waits for a click, so its address cannot carry data out unseen.
    /// Attachments keep loading on sight.
    @Test func webImagesWaitForAClick() async throws {
        final class Loads { var count = 0 }
        func show(autoload: Bool) async throws -> Int {
            let loads = Loads()
            let view = NSHostingView(rootView: ChatImage(name: "Chart", identity: "https://example.com/a.png", autoload: autoload) {
                loads.count += 1
                throw URLError(.cancelled)
            })
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 240), styleMask: .borderless, backing: .buffered, defer: false)
            window.contentView = view
            view.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(300))
            window.contentView = nil
            return loads.count
        }
        #expect(try await show(autoload: false) == 0)
        #expect(try await show(autoload: true) == 1)
    }

    @Test func imageMarkupInCodeDoesNotLoad() {
        let blocks = MessageContent(source: "`![Фото](https://example.com/a.jpg)`\n\n![Закрытый файл](file:///private/secret.jpg)").blocks
        #expect(!blocks.contains { $0.kind == "image" })
    }

    @Test func comparisonsAreTables() {
        let blocks = MessageContent(source: "| Модель | Ограничение |\n| --- | --- |\n| **LongCat** | Preview |\n| Exa | До трёх часов |").blocks
        #expect(blocks.count == 1)
        #expect(blocks.first?.kind == "table")
    }

    @Test func nestedPrioritiesKeepTheirHierarchy() {
        let blocks = MessageContent(source: "1. Исследование\n   - Проверить источники\n   - Оценить стоимость\n2. Разработка").blocks
        #expect(blocks.map(\.level) == [0, 1, 1, 0])
    }

    @Test func multilineQuotesStayTogether() {
        let blocks = MessageContent(source: "> Первая строка\n> продолжение мысли").blocks
        #expect(blocks.count == 1)
        #expect(blocks.first?.kind == "quote")
    }

    @Test func tildeFencesStayCode() {
        let blocks = MessageContent(source: "~~~swift\nlet value = \"**literal**\"\n~~~").blocks
        #expect(blocks.count == 1)
        #expect(blocks.first?.kind == "code")
    }

    @Test func emphasisAndCanonicalLinksSurvive() {
        let block = MessageContent(source: "**Важное** — [первоисточник](https://openai.com/index/proaction/), `код` и *оговорка*.").blocks[0]
        #expect(String(block.content.characters) == "Важное — первоисточник, код и оговорка.")
        #expect(block.content.runs.contains { $0.inlinePresentationIntent?.contains(.stronglyEmphasized) == true })
        #expect(block.content.runs.contains { $0.link?.absoluteString == "https://openai.com/index/proaction/" })
        #expect(block.content.runs.contains { $0.inlinePresentationIntent?.contains(.code) == true })
    }

    @Test func codeFencesPreserveLiteralMarkup() {
        let block = MessageContent(source: "````markdown\n# **Literal**\n```swift\nlet x = 1\n```\n````").blocks[0]
        #expect(block.kind == "code")
        #expect(String(block.content.characters).contains("```swift"))
        #expect(String(block.content.characters).contains("# **Literal**"))
    }

    @Test func listContinuationsDoNotInventExtraItems() {
        let blocks = MessageContent(source: "3. Первый абзац\n\n   Второй абзац того же пункта\n4. Следующий пункт").blocks
        #expect(blocks.map(\.marker) == ["3.", "", "4."])
    }

    @Test func tablesKeepCellsLinksAndAlignment() throws {
        let block = MessageContent(source: "| Модель | Источник |\n| :--- | ---: |\n| **Astra** | [OpenAI](https://openai.com) |").blocks[0]
        let table = try #require(block.table)
        #expect(table.rows.count == 2)
        #expect(table.rows[1].count == 2)
        #expect(String(table.rows[1][0].characters) == "Astra")
        #expect(table.rows[1][1].runs.first?.link?.host() == "openai.com")
        #expect(table.columns[1].alignment == .right)
    }

    @Test func horizontalRulesAndEscapedMarkupRemainDistinct() {
        let blocks = MessageContent(source: "\\*\\*Буквальные звёздочки\\*\\*\n\n---\n\n## Заголовок").blocks
        #expect(blocks.map(\.kind) == ["paragraph", "rule", "heading"])
        #expect(String(blocks[0].content.characters) == "**Буквальные звёздочки**")
    }
    @Test func onlyWebAndMailLinksStayLinks() {
        let source = "[a](file:///Applications/Calculator.app) [b](openstrudel://pair?code=1) [c](javascript:alert(1)) [d](x-apple.systempreferences:com.apple.preference.security) [e](relative/path) [f](https://example.com) [g](http://example.com) [h](mailto:team@example.com) [i](HTTPS://EXAMPLE.COM/A)"
        let block = MessageContent(source: source).blocks[0]
        #expect(String(block.content.characters) == "a b c d e f g h i")
        #expect(block.content.runs.compactMap { $0.link?.absoluteString } == ["https://example.com", "http://example.com", "mailto:team@example.com", "HTTPS://EXAMPLE.COM/A"])
    }

    @Test func unsafeLinksInTablesKeepTheirText() throws {
        let block = MessageContent(source: "| Файл | Сайт |\n| --- | --- |\n| [отчёт](file:///private/report.pdf) | [OpenAI](https://openai.com) |").blocks[0]
        let table = try #require(block.table)
        #expect(String(table.rows[1][0].characters) == "отчёт")
        #expect(table.rows[1][0].runs.allSatisfy { $0.link == nil })
        #expect(table.rows[1][1].runs.first?.link?.host() == "openai.com")
    }

    @Test func openingALinkAllowsOnlyWebAndMail() throws {
        for allowed in ["https://example.com", "http://example.com", "mailto:team@example.com"] {
            #expect(MessageContent.allowsLink(try #require(URL(string: allowed))))
        }
        for blocked in ["file:///Applications/Calculator.app", "openstrudel://pair?code=1", "javascript:alert(1)",
                        "x-apple.systempreferences:com.apple.preference.security", "relative/path", "ftp://example.com"] {
            #expect(!MessageContent.allowsLink(try #require(URL(string: blocked))))
        }
    }

    @Test func linksAreInkWithAQuietUnderlineAtRest() throws {
        let block = MessageContent(source: "Read [the guide](https://example.com) and [this](file:///private/x).").blocks[0]
        let styled = MessageContent.styled(block.content)
        let link = try #require(styled.runs.first { $0.link != nil })
        #expect(link.foregroundColor == AppTheme.accentText)
        #expect(link.underlineStyle == Text.LineStyle(pattern: .solid, color: AppTheme.secondaryText))
        #expect(styled.runs.filter { $0.underlineStyle != nil }.count == 1)
    }

    @Test func blocksFollowTheDirectionOfTheirFirstStrongLetter() {
        #expect(ParagraphDirection.of("שלום world") == .rightToLeft)
        #expect(ParagraphDirection.of("Hello שלום") == .leftToRight)
        #expect(ParagraphDirection.of("1. «مرحبا» again") == .rightToLeft)
        #expect(ParagraphDirection.of("Привет, שלום") == .leftToRight)
        #expect(ParagraphDirection.of("2026 — 15% (!)") == nil)
        #expect(ParagraphDirection.of("") == nil)
    }

    @Test func numberColumnsAlignToTheirFigures() throws {
        let source = "| Venue | Capacity | Price | Share | Distance | Note |\n| --- | --- | --- | --- | --- | --- |\n| Hangar 9 | 120 | €4,200 | 12.5% | 12 min | |\n| Glasshouse | 1 200 | $3,100.50 | −3% | 25 min | |\n| Mill | | 5 600 ₽ | +0.1 % | — | |"
        let table = try #require(MessageContent(source: source).blocks[0].table)
        #expect((0..<6).map(table.isNumeric) == [false, true, true, true, false, false])
        #expect((0..<6).map(table.alignment) == [.leading, .trailing, .trailing, .trailing, .leading, .leading])
    }

    @Test func explicitTableAlignmentWins() throws {
        let table = try #require(MessageContent(source: "| Name | Count | Code |\n| :---: | ---: | --- |\n| 10 | x | 42 |").blocks[0].table)
        #expect((0..<3).map(table.alignment) == [.center, .trailing, .trailing])
    }

    @Test func blocksKeepTheReadingRhythm() {
        let blocks = MessageContent(source: "Intro\n\nSecond\n\n## Heading\n\n- One\n- Two\n\nAfter\n\n```\ncode\n```").blocks
        #expect(blocks.map(\.kind) == ["paragraph", "paragraph", "heading", "list", "list", "paragraph", "code"])
        let gaps = blocks.indices.map { MessageContent.spacing(before: blocks[$0], after: $0 == 0 ? nil : blocks[$0 - 1]) }
        #expect(gaps == [0, 12, 24, 8, 6, 12, 12])
    }

    @Test func separateListsKeepParagraphSpacing() {
        let blocks = MessageContent(source: "1. One\n2. Two\n\n- Other\n  - Nested").blocks
        #expect(blocks.map(\.kind) == ["list", "list", "list", "list"])
        let gaps = blocks.indices.map { MessageContent.spacing(before: blocks[$0], after: $0 == 0 ? nil : blocks[$0 - 1]) }
        #expect(gaps == [0, 6, 12, 6])
    }
}
