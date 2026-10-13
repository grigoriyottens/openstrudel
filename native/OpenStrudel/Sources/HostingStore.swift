#if os(macOS)
import SwiftUI
import WebKit

/// Commercial hosting is optional and receives no Home token or OpenAI session.
/// Set the exact origin in a release only after the separate purchase acceptance.
enum HostingStore {
    static var origin: URL? { approvedOrigin(Bundle.main.object(forInfoDictionaryKey: "OpenStrudelHostingOrigin") as? String) }
    static func approvedOrigin(_ value: String?, allowLocal: Bool = false) -> URL? {
        guard let value, let url = URL(string: value), let host = url.host,
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
              url.path.isEmpty || url.path == "/" else { return nil }
        #if DEBUG
        let local = allowLocal || Bundle.main.bundleIdentifier == "is.openstrudel.primary-qa"
        #else
        let local = false
        #endif
        guard url.scheme == "https" || local && url.scheme == "http" && ["127.0.0.1", "localhost", "[::1]", "::1"].contains(host) else { return nil }
        return url
    }
    static func sameOrigin(_ lhs: URL, _ rhs: URL) -> Bool {
        lhs.scheme == rhs.scheme && lhs.host?.lowercased() == rhs.host?.lowercased() && (lhs.port ?? 443) == (rhs.port ?? 443)
    }
}

/// A General settings section, shown only when this build has a hosting store.
struct HostingStoreSettings: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        if HostingStore.origin != nil {
            Section {
                LabeledContent {
                    Button(L("Открыть")) { openWindow(id: "servers") }
                } label: {
                    Text(L("Серверы"))
                    Text(L("Создание, доступ и продление. Для команды и других проектов."))
                }
            }
        }
    }
}

/// The Servers window. It opens only from General's Servers row, which needs a hosting origin.
struct HostingStoreView: View {
    @State private var loading = true
    @State private var error: String?
    @State private var reload = 0
    var body: some View {
        if let origin = HostingStore.origin {
            ZStack {
                HostingBrowser(origin: origin, reload: reload, loading: $loading, error: $error)
                if loading && error == nil { ProgressView(L("Открываем серверы…")) }
                if let error {
                    ServersMessage(title: L("Не удалось открыть серверы"), message: L10n.serviceText(error), action: L("Попробовать ещё раз")) {
                        self.error = nil; loading = true; reload += 1
                    }
                    .background(.background)
                }
            }
            .frame(minWidth: 780, minHeight: 650)
        }
    }
}

/// The character, one sentence and one action, optically centred at 40 % of the window.
private struct ServersMessage: View {
    let title: String
    let message: String
    let action: String
    let perform: () -> Void

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 16) {
                Image("Agent-main").resizable().scaledToFit()
                    .frame(width: AvatarSize.hero, height: AvatarSize.hero)
                    .accessibilityHidden(true)
                VStack(spacing: 8) {
                    Text(title).font(AppTypography.display)
                    Text(message).foregroundStyle(AppTheme.secondaryText).frame(maxWidth: 360)
                }
                .multilineTextAlignment(.center)
                // The ink primary action. Spelled out because the test target builds this file without SharedViews.
                Button(action, action: perform)
                    .buttonStyle(.borderedProminent).buttonBorderShape(.capsule).controlSize(.large)
                    .tint(AppTheme.accentText).foregroundStyle(AppTheme.canvas)
                    .padding(.top, 8)
            }
            .padding(24)
            .frame(maxWidth: .infinity)
            .position(x: proxy.size.width / 2, y: proxy.size.height * 0.4)
        }
    }
}

private struct HostingBrowser: NSViewRepresentable {
    let origin: URL
    let reload: Int
    @Binding var loading: Bool
    @Binding var error: String?
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        view.uiDelegate = context.coordinator
        view.allowsBackForwardNavigationGestures = true
        view.load(URLRequest(url: origin))
        return view
    }
    func updateNSView(_ view: WKWebView, context: Context) {
        context.coordinator.parent = self
        if context.coordinator.lastReload != reload {
            context.coordinator.lastReload = reload
            view.load(URLRequest(url: origin))
        }
    }
    @MainActor final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate {
        var parent: HostingBrowser
        var lastReload = 0
        private var downloads: [ObjectIdentifier: (temporary: URL, destination: URL)] = [:]
        init(_ parent: HostingBrowser) { self.parent = parent }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { parent.loading = false; parent.error = nil }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { failed(error) }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { failed(error) }
        private func failed(_ error: Error) {
            guard (error as NSError).code != NSURLErrorCancelled else { return }
            parent.loading = false
            parent.error = L("Проверьте соединение и повторите попытку. Это не прерывает работу агентов.")
        }
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
            guard let url = action.request.url else { decisionHandler(.cancel); return }
            if HostingStore.sameOrigin(url, parent.origin) || url.scheme == "blob" {
                decisionHandler(action.shouldPerformDownload ? .download : .allow)
            } else {
                decisionHandler(.cancel)
                // Payment and support open in the owner's browser. No Home or
                // store credential is copied into that navigation.
                if action.targetFrame?.isMainFrame != false && ["https", "mailto"].contains(url.scheme ?? "") { NSWorkspace.shared.open(url) }
            }
        }
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if let url = action.request.url, HostingStore.sameOrigin(url, parent.origin) { webView.load(action.request) }
            return nil
        }
        func webView(_ webView: WKWebView, decidePolicyFor response: WKNavigationResponse, decisionHandler: @escaping @MainActor @Sendable (WKNavigationResponsePolicy) -> Void) {
            let disposition = (response.response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Disposition") ?? ""
            decisionHandler(disposition.lowercased().hasPrefix("attachment") || !response.canShowMIMEType ? .download : .allow)
        }
        func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) { download.delegate = self }
        func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) { download.delegate = self }
        func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String, completionHandler: @escaping @MainActor @Sendable (URL?) -> Void) {
            let panel = NSSavePanel()
            panel.nameFieldStringValue = URL(fileURLWithPath: suggestedFilename).lastPathComponent
            panel.begin { [weak self] result in
                guard let self, result == .OK, let destination = panel.url else { completionHandler(nil); return }
                do {
                    let directory = FileManager.default.temporaryDirectory.appending(path: "openstrudel-download-" + UUID().uuidString, directoryHint: .isDirectory)
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
                    let temporary = directory.appending(path: "download")
                    self.downloads[ObjectIdentifier(download)] = (temporary, destination)
                    completionHandler(temporary)
                } catch { self.failed(error); completionHandler(nil) }
            }
        }
        func downloadDidFinish(_ download: WKDownload) {
            guard let item = downloads.removeValue(forKey: ObjectIdentifier(download)) else { return }
            defer { try? FileManager.default.removeItem(at: item.temporary.deletingLastPathComponent()) }
            do {
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: item.temporary.path)
                if FileManager.default.fileExists(atPath: item.destination.path) {
                    _ = try FileManager.default.replaceItemAt(item.destination, withItemAt: item.temporary, options: .usingNewMetadataOnly)
                } else { try FileManager.default.moveItem(at: item.temporary, to: item.destination) }
            } catch { parent.error = L("Не удалось сохранить файл. Выберите личную папку и повторите скачивание.") }
        }
        func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
            if let item = downloads.removeValue(forKey: ObjectIdentifier(download)) { try? FileManager.default.removeItem(at: item.temporary.deletingLastPathComponent()) }
            failed(error)
        }
    }
}
#endif
