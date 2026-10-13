import SwiftUI

/// The native surface is intentionally small: chats on the left, one calm
/// composer, and settings only for the two connections a person can act on.
struct OpenStrudelRootView: View {
    @EnvironmentObject private var library: DeviceLibrary
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var client: HomeClient
    @State private var showSettings = false
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
        ZStack {
            HomeBackground()
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
                HStack(spacing: 0) {
                    Sidebar(showSettings: $showSettings)
                        .frame(width: 280)
                    Rectangle().fill(.primary.opacity(0.08)).frame(width: 1)
                    ConversationView(showSettings: $showSettings)
                }
                #else
                NavigationStack { ConversationView(showSettings: $showSettings).background(HomeBackground()) }
                #endif
            }
        }
        .overlay(alignment: .topTrailing) {
            if client.health == nil || !aiConsent || client.openAIAccount?.connected == false && client.profiles.isEmpty {
                LanguagePicker(compact: true).padding(16)
            }
        }
        .task(id: pollingPhase) {
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
        .task(id: pollingPhase) {
            guard pollingPhase == .active else { return }
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(10)) } catch { break }
                await client.refreshOpenAIAccount()
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView().environmentObject(client)
        }
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
        .frame(minWidth: 940, minHeight: 620)
        #endif
    }
}
