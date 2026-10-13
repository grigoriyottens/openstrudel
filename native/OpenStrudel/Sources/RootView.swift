import SwiftUI

/// The native surface is intentionally small: chats on the left, one calm
/// composer, and settings only for the two connections a person can act on.
struct OpenStrudelRootView: View {
    @EnvironmentObject private var library: DeviceLibrary
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.layoutDirection) private var layoutDirection
    @EnvironmentObject private var client: HomeClient
    #if os(macOS)
    // Above the per-device identity, so switching devices keeps the sidebar as it is.
    @State private var columnVisibility = NavigationSplitViewVisibility.all
    @State private var sidebarQuery = ""
    @FocusState private var searchFocused: Bool
    /// The toolbar or title bar above this view; the window minimum includes it.
    @State private var titleBarHeight: CGFloat = 0
    #else
    @State private var showSettings = false
    #endif
    @AppStorage("openstrudel.aiConsent.v1") private var aiConsent = false

    private var pollingPhase: ScenePhase {
        #if os(iOS)
        scenePhase
        #else
        // A visible Mac window stays current even when another app has focus.
        .active
        #endif
    }

    var body: some View {
        screens
        .overlay(alignment: .topTrailing) {
            if client.health == nil || !aiConsent || client.openAIAccount?.connected == false && client.profiles.isEmpty {
                LanguagePicker().padding(OnboardingLayout.margin)
            }
        }
        .task(id: "\(pollingPhase)-\(client.id)") {
            guard pollingPhase == .active else { return }
            #if os(macOS)
            if Bundle.main.bundleIdentifier == "is.openstrudel.mac",
               client.normalizedBaseURL == "http://127.0.0.1:7788",
               client.hasToken && !client.isPairing && LocalHome.isAvailable {
                await client.startLocalHome()
            }
            #endif
            if client.shouldRestoreConnection && !client.isPairing { await client.load(quiet: true) }
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(client.health == nil ? 5 : 1)) } catch { break }
                if client.health != nil { await client.refreshConversation() }
                else if client.shouldRestoreConnection && !client.isPairing && !client.connectionNeedsPairing {
                    await client.load(quiet: true)
                }
            }
        }
        .task(id: "\(pollingPhase)-\(client.id)") {
            guard pollingPhase == .active else { return }
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(10)) } catch { break }
                await client.refreshOpenAIAccount()
            }
        }
        #if os(iOS)
        .sheet(isPresented: $showSettings) {
            SettingsView().environmentObject(client)
        }
        #endif
        .sheet(item: $client.pendingPairing) { pairing in
            AddDeviceConfirmation(pairing: pairing).environmentObject(library)
        }
        .alert(
            "OpenStrudel",
            isPresented: Binding(
                get: { client.errorMessage != nil },
                set: { if !$0 { client.errorMessage = nil } }
            )
        ) {
            Button(L("Понятно"), role: .cancel) {}
        } message: {
            Text(UserFacingError.text(client.errorMessage ?? ""))
        }
        #if os(macOS)
        // SwiftUI measures this view below the toolbar, so the window's 560 includes the toolbar.
        .frame(minWidth: 760, minHeight: 560 - titleBarHeight)
        .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.top } action: { titleBarHeight = $0 }
        .containerBackground(AppTheme.canvas, for: .window)
        #endif
    }

    @ViewBuilder private var screens: some View {
        #if os(macOS)
        state.frame(maxWidth: .infinity, maxHeight: .infinity)
        #else
        ZStack {
            HomeBackground()
            state
        }
        #endif
    }

    @ViewBuilder private var state: some View {
        if client.isConnecting && !library.hasOtherDevices {
            HomeConnectingView()
        } else if client.health == nil && !library.hasOtherDevices {
            #if os(iOS)
            MobileWelcomeView()
            #else
            HomeUnavailableView()
            #endif
        } else if !aiConsent {
            AIDataConsentView { aiConsent = true }
        } else if client.openAIAccount?.connected == false && !client.hasOpenedConversation && client.profiles.isEmpty && client.devices.count < 2 {
            OpenAIWelcomeView()
        } else {
            #if os(macOS)
            NavigationSplitView(columnVisibility: $columnVisibility) {
                Sidebar(query: $sidebarQuery)
                    .environment(\.layoutDirection, layoutDirection)
                    .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 340)
            } detail: {
                // Each device keeps its own draft, files and reading position.
                ConversationView().id(client.id)
                    .environment(\.layoutDirection, layoutDirection)
            }
            .searchable(text: $sidebarQuery, placement: .sidebar, prompt: L("Найти чат"))
            .searchFocused($searchFocused)
            // Edit › Find a chat (⌘F) opens a collapsed sidebar and focuses its search field.
            .focusedSceneValue(\.findChat) {
                columnVisibility = .all
                searchFocused = true
            }
            // A new employee (⌘N, the plus button or the menu) shows its draft row and takes the typing focus.
            .onChange(of: client.isEmployeeDraft) { _, draft in
                guard draft else { return }
                sidebarQuery = ""
                searchFocused = false
            }
            // The split view and the toolbar are AppKit's, so they follow AppKit's direction.
            // Mixing directions misplaces the columns; the content inside still reads in the chosen language.
            .environment(\.layoutDirection, NSApp.userInterfaceLayoutDirection == .rightToLeft ? .rightToLeft : .leftToRight)
            #else
            NavigationStack { ConversationView(showSettings: $showSettings).background(HomeBackground()) }
            #endif
        }
    }
}
