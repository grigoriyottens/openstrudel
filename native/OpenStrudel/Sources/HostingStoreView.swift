#if os(macOS)
import SwiftUI

/// The Servers window. It opens only from General's Servers row, which needs a hosting origin.
struct HostingStoreView: View {
    @State private var loading = true
    @State private var error: String?
    @State private var downloadError: String?
    @State private var reload = 0

    var body: some View {
        if let origin = HostingStore.origin {
            ZStack {
                HostingBrowser(origin: origin, reload: reload, loading: $loading, error: $error, downloadError: $downloadError)
                if loading && error == nil { ProgressView(L("Открываем серверы…")) }
                if let error {
                    // A welcome screen without the language menu: the character, one sentence, one action.
                    WelcomePage(languageMenu: false) {
                        WelcomeHeader(title: L("Не удалось открыть серверы"))
                        WelcomeText(L10n.serviceText(error)).padding(.top, 12)
                        Button {
                            self.error = nil; loading = true; reload += 1
                        } label: {
                            SetupActionLabel(title: L("Попробовать ещё раз"))
                        }
                        .primaryAction()
                        .padding(.top, 32)
                    }
                    .background(.background)
                }
            }
            .frame(minWidth: 780, minHeight: 650)
            .alert(L("Не удалось скачать файл"), isPresented: Binding(get: { downloadError != nil }, set: { if !$0 { downloadError = nil } })) {
            } message: {
                Text(downloadError ?? "")
            }
        }
    }
}
#endif
