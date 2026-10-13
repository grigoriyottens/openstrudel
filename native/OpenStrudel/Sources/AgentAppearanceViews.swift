import SwiftUI

struct AgentAvatar: View {
    var appearance: AgentAppearance?
    let size: CGFloat
    var body: some View {
        // The main assistant is the app-icon bun without its tile, so every avatar is a character.
        let valid = appearance?.isValid == true
        Image(valid ? "Agent-" + appearance!.kind : "Agent-main")
            .renderingMode(.original).resizable().interpolation(.high).scaledToFit()
            .frame(width: size, height: size)
            .hueRotation(valid ? appearance!.hue : .zero)
            .clipped().accessibilityHidden(true)
    }
}

/// Six characters over eight tones. Both rows run edge to edge, so their outer edges meet the same lines.
struct AgentAppearancePicker: View {
    @Binding var selection: AgentAppearance

    var body: some View {
        VStack(spacing: 12) {
            SpreadGrid(cell: Metrics.character, wrapAt: 3) {
                ForEach(Array(AgentAppearance.kinds.enumerated()), id: \.element) { index, kind in
                    let selected = selection.kind == kind
                    Button { selection.kind = kind } label: {
                        AgentAvatar(appearance: .init(kind: kind, tone: selection.tone), size: Metrics.character - 2 * Metrics.characterInset)
                            .frame(width: Metrics.character, height: Metrics.character)
                            .background { PickerHighlight(shape: RoundedRectangle(cornerRadius: Radius.card, style: .continuous), selected: selected) }
                            .contentShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                    }
                    .buttonStyle(PressableStyle())
                    .accessibilityLabel(AgentAppearance.names[index])
                    .accessibilityAddTraits(selected ? .isSelected : [])
                    .accessibilityIdentifier("agentKind-" + kind)
                }
            }
            SpreadGrid(cell: Metrics.tone, wrapAt: 4) {
                ForEach(AgentAppearance.tones.indices, id: \.self) { tone in
                    let selected = selection.tone == tone
                    Button { selection.tone = tone } label: {
                        Circle().fill(Color(red: 0.96, green: 0.60, blue: 0.24))
                            .hueRotation(.degrees(AgentAppearance.angles[tone]))
                            .padding(Metrics.ringGap)
                            .frame(width: Metrics.tone, height: Metrics.tone)
                            .background { PickerHighlight(shape: Circle(), selected: selected) }
                            .contentShape(Circle())
                    }
                    .buttonStyle(PressableStyle())
                    .accessibilityLabel(AgentAppearance.tones[tone])
                    .accessibilityAddTraits(selected ? .isSelected : [])
                    .accessibilityIdentifier("agentTone-\(tone)")
                }
            }
        }
        .padding(.vertical, 4)
        .animation(.smooth(duration: 0.25), value: selection)
    }

    private enum Metrics {
        #if os(macOS)
        static let character: CGFloat = 56
        static let characterInset: CGFloat = 6
        static let tone: CGFloat = 32
        #else
        static let character: CGFloat = 48
        static let characterInset: CGFloat = 4
        static let tone: CGFloat = 44
        #endif
        /// The swatch sits 2 inside the 2-pt ring, so the ring and the swatch stay concentric.
        static let ringGap: CGFloat = 4
    }
}

/// The quiet control that deals a new character and tone.
struct AgentAppearanceShuffle: View {
    @Binding var selection: AgentAppearance

    var body: some View {
        Button { selection = selection.shuffled() } label: {
            Label(L("Другой"), systemImage: "shuffle")
        }
        .buttonStyle(.borderless)
        .font(AppTypography.interface)
        .foregroundStyle(AppTheme.secondaryText)
        .fixedSize()
        .accessibilityLabel(L("Случайный образ"))
        .accessibilityIdentifier("shuffleAgentAppearance")
        #if os(macOS)
        .help(L("Случайный образ"))
        #endif
    }
}

/// The selected cell wears a 2-pt accent ring; a hovered one gets a faint fill.
private struct PickerHighlight<S: InsettableShape>: View {
    let shape: S
    let selected: Bool
    @State private var hovering = false

    var body: some View {
        ZStack {
            shape.fill(Color.primary.opacity(hovering && !selected ? 0.06 : 0))
            shape.strokeBorder(AppTheme.accent, lineWidth: 2).opacity(selected ? 1 : 0)
        }
        #if os(macOS)
        .onHover { hovering = $0 }
        #endif
    }
}

private struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.smooth(duration: 0.15), value: configuration.isPressed)
    }
}

/// Equal square cells spread so the first and last touch the row's edges.
/// A row that would crowd its cells wraps into lines of `wrapAt`.
private struct SpreadGrid: SwiftUI.Layout {
    let cell: CGFloat
    let wrapAt: Int
    private let minimumGap: CGFloat = 4
    private let lineGap: CGFloat = 8

    private func columns(for width: CGFloat, count: Int) -> Int {
        let fits = CGFloat(count) * cell + CGFloat(count - 1) * minimumGap <= width
        return fits ? count : min(wrapAt, count)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let count = subviews.count
        guard count > 0 else { return .zero }
        let width = proposal.width ?? CGFloat(count) * cell + CGFloat(count - 1) * 12
        let lines = Int((Double(count) / Double(columns(for: width, count: count))).rounded(.up))
        return CGSize(width: width, height: CGFloat(lines) * cell + CGFloat(lines - 1) * lineGap)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let count = subviews.count
        guard count > 0 else { return }
        let perLine = columns(for: bounds.width, count: count)
        let gap = perLine > 1 ? (bounds.width - CGFloat(perLine) * cell) / CGFloat(perLine - 1) : 0
        for (index, subview) in subviews.enumerated() {
            let column = CGFloat(index % perLine), line = CGFloat(index / perLine)
            subview.place(at: CGPoint(x: bounds.minX + column * (cell + gap), y: bounds.minY + line * (cell + lineGap)),
                          proposal: ProposedViewSize(width: cell, height: cell))
        }
    }
}
