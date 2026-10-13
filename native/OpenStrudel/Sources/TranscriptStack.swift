import SwiftUI

/// Rows set their own top spacing, so the transcript keeps its rhythm of turns and messages.
struct TranscriptStack<Content: View>: View {
    @ViewBuilder let content: () -> Content
    var body: some View {
        #if os(macOS)
        LazyVStack(alignment: .leading, spacing: 0, content: content)
        #else
        // Avoid the iPad keyboard/lazy-layout loop when a pending row becomes a reply.
        VStack(alignment: .leading, spacing: 0, content: content)
        #endif
        // ScrollViewReader owns navigation. Combining scrollTargetLayout,
        // a bound reading position and a size-change anchor can recursively
        // invalidate lazy row estimates when an approval replaces a pending row.
    }
}
