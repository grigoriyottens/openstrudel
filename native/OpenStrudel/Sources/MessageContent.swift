import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// A presentation of legacy imported attachments. The stored message and the
/// employee's context stay verbatim; this never fetches a path from the import.
enum ImportedTranscript {
    enum Part: Equatable {
        case text(String)
        case file(name: String, text: String)
    }

    private static let files = try! NSRegularExpression(pattern: #"<file name="([^"\r\n]+)" mime="[^"\r\n]+">\s*([\s\S]*?)\s*</file>"#)
    private static let envelope = try! NSRegularExpression(pattern: #"^\s*<<<EXTERNAL_UNTRUSTED_CONTENT id="([a-zA-Z0-9_-]+)">>>\r?\nSource: External\r?\n---\r?\n([\s\S]*?)\r?\n<<<END_EXTERNAL_UNTRUSTED_CONTENT id="\1">>>\s*$"#)

    static func parts(_ source: String) -> [Part] {
        let range = NSRange(source.startIndex..., in: source)
        let matches = files.matches(in: source, range: range)
        guard !matches.isEmpty else { return [.text(source)] }
        var parts: [Part] = []
        var start = source.startIndex
        for match in matches {
            guard let whole = Range(match.range, in: source),
                  let name = Range(match.range(at: 1), in: source),
                  let content = Range(match.range(at: 2), in: source) else { continue }
            let prefix = String(source[start..<whole.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !prefix.isEmpty { parts.append(.text(prefix)) }
            let raw = String(source[content])
            var text = raw
            if let wrapper = envelope.firstMatch(in: raw, range: NSRange(raw.startIndex..., in: raw)),
               let inner = Range(wrapper.range(at: 2), in: raw) { text = String(raw[inner]) }
            parts.append(.file(name: String(source[name]), text: text))
            start = whole.upperBound
        }
        let suffix = String(source[start...]).trimmingCharacters(in: .whitespacesAndNewlines)
        if !suffix.isEmpty { parts.append(.text(suffix)) }
        return parts
    }
}

/// Imported history from other people: each passage on the surface, each file as a chip.
struct ImportedMessageText: View {
    let source: String
    @State private var selected: Document?
    private struct Document: Identifiable {
        let id: Int
        let name: String
        let text: String
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(ImportedTranscript.parts(source).enumerated()), id: \.offset) { index, part in
                switch part {
                case .text(let text):
                    ChatBubble(text: text, fill: AppTheme.surface)
                case .file(let name, let text):
                    Button { selected = Document(id: index, name: name, text: text) } label: {
                        FileChip(icon: "doc.text", name: name, detail: L("Открыть текст из истории"))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L("Открыть текст файла «\(name)»"))
                }
            }
        }
        .sheet(item: $selected) { document in
            NavigationStack {
                ScrollView {
                    Text(document.text)
                        .font(AppTypography.reading).lineSpacing(AppTypography.readingLineSpacing)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .paragraphDirection(of: document.text)
                        .padding(24)
                }
                .navigationTitle(document.name)
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar { ToolbarItem(placement: .confirmationAction) {
                    Button(L("Готово")) { selected = nil }
                } }
            }
            #if os(macOS)
            .frame(width: 620, height: 540)
            #endif
        }
    }
}

/// A person's words on a rounded fill: the plum-tinted bubble for the owner, the surface
/// for other people in a shared conversation. One line is a 40-pt capsule.
struct ChatBubble: View {
    let text: String
    var fill: Color = AppTheme.userBubble

    var body: some View {
        Text(text)
            .font(AppTypography.reading)
            .lineSpacing(AppTypography.readingLineSpacing)
            .foregroundStyle(.primary)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            // A single 15-pt line is 19 tall; its 22-pt line box keeps the capsule at 40.
            .frame(minHeight: 22)
            .paragraphDirection(of: text)
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .chatSurface(fill, radius: Radius.bubble)
    }
}

/// Each block reads in the direction of its first strong letter, so English stays
/// left-aligned in the Hebrew interface and Hebrew is right-aligned in English.
enum ParagraphDirection {
    static func of(_ text: String) -> LayoutDirection? {
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

private struct BlockDirection: ViewModifier {
    @Environment(\.layoutDirection) private var interface
    let text: String

    func body(content: Content) -> some View {
        content.environment(\.layoutDirection, ParagraphDirection.of(text) ?? interface)
    }
}

private struct ChatSurface: ViewModifier {
    @Environment(\.colorSchemeContrast) private var contrast
    let fill: Color
    let radius: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .background(fill, in: shape)
            .overlay { if contrast == .increased { shape.strokeBorder(AppTheme.separator, lineWidth: 1) } }
    }
}

extension View {
    /// Lays a block out in its own reading direction; text without letters follows the interface.
    func paragraphDirection(of text: String) -> some View { modifier(BlockDirection(text: text)) }

    /// A transcript fill. Increased contrast adds a 1-pt separator edge, because a fill alone is too faint.
    func chatSurface(_ fill: Color, radius: CGFloat) -> some View { modifier(ChatSurface(fill: fill, radius: radius)) }
}

/// A one-pixel rule in the separator colour.
struct Hairline: View {
    @Environment(\.displayScale) private var scale
    var body: some View { Rectangle().fill(AppTheme.separator).frame(height: 1 / scale) }
}

/// Foundation handles Markdown syntax; SwiftUI lays out its native, selectable content.
struct MessageContent: View, Equatable {
    let source: String
    nonisolated static func == (lhs: Self, rhs: Self) -> Bool { lhs.source == rhs.source }

    struct Block: Identifiable {
        let id: Int
        var kind: String
        var content = AttributedString()
        var marker = ""
        var level = 0
        var quoteDepth = 0
        var language: String?
        var table: MarkdownTable?
        var imageURL: URL?
    }

    /// Only web and mail links open. An AI reply can carry a file, app or script link
    /// from content it read, so every other scheme keeps its words and loses its target.
    static func allowsLink(_ url: URL) -> Bool { ["https", "http", "mailto"].contains(url.scheme?.lowercased() ?? "") }

    static func safeLinks(_ text: AttributedString) -> AttributedString {
        var result = text
        for run in text.runs { if let url = run.link, !allowsLink(url) { result[run.range].link = nil } }
        return result
    }

    var blocks: [Block] {
        guard let document = try? AttributedString(markdown: source, options: .init(interpretedSyntax: .full)) else {
            return [Block(id: 0, kind: "paragraph", content: AttributedString(source))]
        }
        var result: [Block] = []
        var seenListItems: Set<Int> = []
        for run in document.runs {
            let components = run.presentationIntent?.components ?? []
            var text = AttributedString(document[run.range])
            text.presentationIntent = nil
            text = Self.safeLinks(text)
            if let table = components.first(where: { if case .table = $0.kind { return true }; return false }),
               case .table(let columns) = table.kind,
               let cell = components.first(where: { if case .tableCell = $0.kind { return true }; return false }),
               case .tableCell(let column) = cell.kind {
                if result.last?.id != table.identity {
                    result.append(Block(id: table.identity, kind: "table", table: MarkdownTable(columns: columns)))
                }
                let row = components.compactMap { component -> Int? in
                    switch component.kind {
                    case .tableHeaderRow: return 0
                    case .tableRow(let index): return index
                    default: return nil
                    }
                }.first ?? 0
                result[result.count - 1].table?.append(text, row: row, column: column)
                continue
            }
            let identity = components.first?.identity ?? 0
            if let url = run.imageURL, ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
               url.host != nil, url.user == nil, url.password == nil {
                result.append(Block(id: identity, kind: "image", content: text, imageURL: url))
                continue
            }
            if result.last?.id == identity && result.last?.kind != "image" {
                result[result.count - 1].content.append(text)
                continue
            }
            var block = Block(id: identity, kind: "paragraph", content: text)
            for component in components {
                switch component.kind {
                case .header(let level): block.kind = "heading"; block.level = level
                case .codeBlock(let language): block.kind = "code"; block.language = language
                case .thematicBreak: block.kind = "rule"
                case .blockQuote: block.quoteDepth += 1
                default: break
                }
            }
            if let itemIndex = components.firstIndex(where: { if case .listItem = $0.kind { return true }; return false }),
               case .listItem(let ordinal) = components[itemIndex].kind {
                let item = components[itemIndex]
                block.level = max(0, components.filter { $0.kind == .orderedList || $0.kind == .unorderedList }.count - 1)
                if seenListItems.insert(item.identity).inserted {
                    block.marker = components.dropFirst(itemIndex + 1).first?.kind == .orderedList ? "\(ordinal)." : "•"
                }
                if block.kind == "paragraph" { block.kind = "list" }
            } else if block.kind == "paragraph", block.quoteDepth > 0 {
                block.kind = "quote"
            }
            result.append(block)
        }
        return result
    }

    /// The reading rhythm: 12 between paragraphs, 6 between list items, 24 above and 8 below a heading.
    static func spacing(before block: Block, after previous: Block?) -> CGFloat {
        guard let previous else { return 0 }
        if block.kind == "heading" { return 24 }
        if previous.kind == "heading" { return 8 }
        if block.kind == "list" && previous.kind == "list" { return 6 }
        return 12
    }

    var body: some View {
        let document = blocks
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(document.enumerated()), id: \.offset) { index, block in
                let previous = index == 0 ? nil : document[index - 1]
                blockContent(block, after: previous)
                    .padding(.top, Self.spacing(before: block, after: previous))
            }
        }
        .font(AppTypography.reading)
        .lineSpacing(AppTypography.readingLineSpacing)
        .textSelection(.enabled)
        .tint(AppTheme.accentText)
        .environment(\.openURL, OpenURLAction { Self.allowsLink($0) ? .systemAction : .discarded })
    }

    @ViewBuilder private func blockContent(_ block: Block, after previous: Block?) -> some View {
        let words = String(block.content.characters)
        switch block.kind {
        case "heading":
            Text(Self.styled(block.content))
                .font(block.level <= 2 ? AppTypography.title : AppTypography.reading.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
                .frame(maxWidth: .infinity, alignment: .leading)
                .paragraphDirection(of: words)
        case "list":
            ListItem(marker: block.marker, level: block.level, content: Self.styled(block.content))
                .paragraphDirection(of: words)
        case "quote":
            Text(Self.styled(block.content))
                .foregroundStyle(AppTheme.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 2 + 12)
                .overlay(alignment: .leading) {
                    // Consecutive quote paragraphs share one unbroken rule.
                    Rectangle().fill(AppTheme.separator).frame(width: 2)
                        .padding(.top, previous?.kind == "quote" ? -Self.spacing(before: block, after: previous) : 0)
                }
                .paragraphDirection(of: words)
        case "code":
            CodeBlockView(code: words.trimmingCharacters(in: .newlines), language: block.language)
        case "table":
            if let table = block.table { MarkdownTableView(table: table) }
        case "image":
            if let url = block.imageURL {
                ChatImage(name: words, identity: url.absoluteString) {
                    try await ChatMedia.download(url)
                }
            }
        case "rule":
            Hairline()
        default:
            Text(Self.styled(block.content))
                .frame(maxWidth: .infinity, alignment: .leading)
                .paragraphDirection(of: words)
        }
    }

    /// Links read as links at rest: accent text with a 40 % accent underline. Inline code is SF Mono on the surface.
    static func styled(_ source: AttributedString) -> AttributedString {
        var text = source
        for run in source.runs {
            if run.inlinePresentationIntent?.contains(.code) == true {
                text[run.range].font = AppTypography.code
                text[run.range].backgroundColor = AppTheme.surface
            }
            if run.link != nil {
                text[run.range].foregroundColor = AppTheme.accentText
                text[run.range].underlineStyle = Text.LineStyle(pattern: .solid, color: AppTheme.accentText.opacity(0.4))
            }
        }
        return text
    }
}

enum ChatTypography {
    static var body: Font { AppTypography.reading }
    static var code: Font { AppTypography.code }
}

/// A list item with a fixed marker column: bullets and right-aligned tabular numbers end on one
/// edge, so every item's text starts on one line. Nested items start under their parent's text.
private struct ListItem: View {
    let marker: String
    let level: Int
    let content: AttributedString
    @ScaledMetric(relativeTo: .body) private var markerWidth: CGFloat = 20
    private let gap: CGFloat = 8

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: gap) {
            Text(marker)
                .foregroundStyle(AppTheme.secondaryText)
                .monospacedDigit()
                .fixedSize()
                .frame(width: markerWidth, alignment: .trailing)
            Text(content).frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.leading, CGFloat(level) * (markerWidth + gap))
        .accessibilityElement(children: .combine)
    }
}

/// A fenced block: SF Mono on the surface, scrolling sideways instead of wrapping.
/// Copy appears on hover on the Mac and stays visible on iOS.
struct CodeBlockView: View {
    let code: String
    let language: String?
    @State private var hovering = false
    @State private var buttonHovering = false
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let language, !language.isEmpty {
                Text(language)
                    .font(AppTypography.meta)
                    .foregroundStyle(AppTheme.secondaryText)
                    .padding([.horizontal, .top], 12)
            }
            // Padding lives inside the scroll view so lines scroll to the block's edge
            // and the Mac scroller sits in the bottom padding, not over the last line.
            ScrollView(.horizontal) {
                Text(code)
                    .font(AppTypography.code)
                    .lineSpacing(AppTypography.codeLineSpacing)
                    .fixedSize()
                    // The Mac button only shows on hover, so VoiceOver gets the same action here.
                    .accessibilityAction(named: L("Скопировать код"), copy)
                    .padding(.horizontal, 12)
                    .padding(.top, language?.isEmpty == false ? 8 : 12)
                    .padding(.bottom, 12)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .chatSurface(AppTheme.surface, radius: Radius.card)
        .overlay(alignment: .topTrailing) { copyButton }
        .onHover { hovering = $0 }
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityElement(children: .contain)
    }

    private var copyButton: some View {
        Button(action: copy) {
            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                .font(.system(size: 12, weight: .medium))
                .contentTransition(.symbolEffect(.replace))
                .foregroundStyle(buttonHovering ? AnyShapeStyle(.primary) : AnyShapeStyle(AppTheme.secondaryText))
                // 4 from the block's corner, so 8 is concentric with its 12.
                .frame(width: 28, height: 28)
                .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                .padding(4)
                .frame(width: controlTarget + 4, height: controlTarget + 4, alignment: .topTrailing)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { buttonHovering = $0 }
        .help(copied ? L("Код скопирован") : L("Скопировать код"))
        .accessibilityLabel(copied ? L("Код скопирован") : L("Скопировать код"))
        #if os(macOS)
        .opacity(hovering || copied ? 1 : 0)
        .allowsHitTesting(hovering || copied)
        .animation(.easeOut(duration: 0.15), value: hovering)
        #endif
    }

    private func copy() {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(code, forType: .string)
        #else
        UIPasteboard.general.string = code
        #endif
        copied = true
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            copied = false
        }
    }
}

struct MarkdownTable {
    let columns: [PresentationIntent.TableColumn]
    var rows: [[AttributedString]] = []

    mutating func append(_ text: AttributedString, row: Int, column: Int) {
        while rows.count <= row { rows.append(Array(repeating: AttributedString(), count: columns.count)) }
        guard rows[row].indices.contains(column) else { return }
        rows[row][column].append(text)
    }

    private static let number = try! NSRegularExpression(pattern: #"^[-+−]?\p{Sc}?\s?\d[\d\s.,']*\s?%?\s?\p{Sc}?$"#)

    /// A column whose filled body cells are all numbers: counts, prices, percentages.
    func isNumeric(_ column: Int) -> Bool {
        let cells = rows.dropFirst().compactMap { row in
            row.indices.contains(column) ? String(row[column].characters).trimmingCharacters(in: .whitespaces) : nil
        }.filter { !$0.isEmpty }
        return !cells.isEmpty && cells.allSatisfy { Self.number.firstMatch(in: $0, range: NSRange($0.startIndex..., in: $0)) != nil }
    }

    /// Explicit centre and right alignment win; otherwise numbers sit on the trailing edge.
    /// Foundation reports `:---` and `---` alike as left, so left reads as no preference.
    func alignment(_ column: Int) -> HorizontalAlignment {
        switch columns[column].alignment {
        case .center: .center
        case .right: .trailing
        default: isNumeric(column) ? .trailing : .leading
        }
    }

    var words: String { rows.joined().map { String($0.characters) }.joined(separator: " ") }
}

private struct MarkdownTableView: View {
    let table: MarkdownTable
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.colorSchemeContrast) private var contrast
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif
    @State private var availableWidth: CGFloat = Layout.column
    @State private var headerHeight: CGFloat = 0
    /// Below this, a column's text would break into single words, so the table scrolls instead.
    private let minimumColumn: CGFloat = 120

    private var isCompact: Bool {
        #if os(iOS)
        sizeClass == .compact || typeSize.isAccessibilitySize
        #else
        false
        #endif
    }

    var body: some View {
        let minimumWidth = CGFloat(table.columns.count) * minimumColumn
        Group {
            if isCompact {
                compact
            } else if minimumWidth <= availableWidth {
                grid
            } else {
                ScrollView(.horizontal) { grid.frame(width: minimumWidth) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { availableWidth = $0 }
        .paragraphDirection(of: table.words)
    }

    private var grid: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
        return Grid(alignment: .topLeading, horizontalSpacing: 0, verticalSpacing: 0) {
            ForEach(table.rows.indices, id: \.self) { row in
                if row > 1 { Hairline().gridCellUnsizedAxes(.horizontal) }
                GridRow {
                    ForEach(table.rows[row].indices, id: \.self) { column in
                        cell(row: row, column: column)
                    }
                }
            }
        }
        .background(alignment: .top) { AppTheme.surface.frame(height: headerHeight) }
        .clipShape(shape)
        .overlay { if contrast == .increased { shape.strokeBorder(AppTheme.separator, lineWidth: 1) } }
    }

    private func cell(row: Int, column: Int) -> some View {
        let alignment = table.alignment(column)
        return Text(MessageContent.styled(table.rows[row][column]))
            .font(row == 0 ? AppTypography.reading.weight(.semibold) : AppTypography.reading)
            .monospacedDigit()
            .lineSpacing(AppTypography.readingLineSpacing)
            .multilineTextAlignment(alignment == .trailing ? .trailing : alignment == .center ? .center : .leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            // Header cells fill the row's height, so the surface band behind them matches it.
            .frame(maxHeight: row == 0 ? .infinity : nil, alignment: .top)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                if row == 0 { headerHeight = height }
            }
            .gridColumnAlignment(alignment)
    }

    /// Narrow iPhones and accessibility sizes read a table as one card per row.
    private var compact: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(table.rows.dropFirst().enumerated()), id: \.offset) { index, row in
                if index > 0 { Hairline() }
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(row.indices, id: \.self) { column in
                        VStack(alignment: .leading, spacing: 4) {
                            if let header = table.rows.first?[column] {
                                Text(MessageContent.styled(header)).font(AppTypography.meta).foregroundStyle(AppTheme.secondaryText)
                            }
                            Text(MessageContent.styled(row[column]))
                                .font(column == 0 ? AppTypography.reading.weight(.semibold) : AppTypography.reading)
                                .monospacedDigit()
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .lineSpacing(AppTypography.readingLineSpacing)
    }
}
