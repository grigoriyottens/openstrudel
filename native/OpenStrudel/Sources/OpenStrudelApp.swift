import SwiftUI

@main
struct OpenStrudelApp: App {
    @StateObject private var library = DeviceLibrary()
    @Environment(\.scenePhase) private var scenePhase
    private var client: HomeClient { library.active }
    #if os(macOS)
    @StateObject private var updater = AppUpdater.shared
    #endif

    var body: some Scene {
        #if os(macOS)
        mainWindow
        .windowToolbarStyle(.unified(showsTitle: false))
        .defaultSize(width: 1120, height: 760)
        .commands {
            CommandGroup(replacing: .newItem) {
                NewEmployeeCommand(busy: client.isCreating)
                EmployeeDetailsCommand()
            }
            CommandGroup(after: .textEditing) { FindChatCommand() }
            // View › Show Sidebar / Hide Sidebar, the menu equivalent of the toolbar button.
            SidebarCommands()
            CommandGroup(after: .appInfo) {
                Button(L("Аккаунты и остатки")) {
                    Task { @MainActor in
                        await Task.yield()
                        HomeStatusItem.shared.showAccounts()
                    }
                }
                    .keyboardShortcut("u", modifiers: [.command, .shift])
                Button(L("Проверить обновления…"), action: updater.checkForUpdates)
                    .disabled(!updater.canCheckForUpdates)
            }
        }
        Window(L("Серверы"), id: "servers") {
            Group {
                if library.isErasing { LocalDataResetProgress().environmentObject(library) }
                else { HostingStoreView() }
            }.tint(AppTheme.accent)
            .modifier(InterfaceLanguage())
        }.defaultSize(width: 1000, height: 760)
        // It opens only from General's Servers row, which a build shows only when it has a hosting store.
        .commandsRemoved()
        .restorationBehavior(.disabled)
        Settings {
            Group {
                if library.isErasing { LocalDataResetProgress() }
                else { SettingsView(standalone: true) }
            }
                .environmentObject(client)
                .environmentObject(library)
                .tint(AppTheme.accent)
            .modifier(InterfaceLanguage())
        }.windowResizability(.contentSize)
        #else
        mainWindow
        #endif
    }

    @SceneBuilder private var mainWindow: some Scene {
        #if os(macOS)
        // The menu-bar Open action brings back the same workspace, including
        // its draft and reading position, instead of creating another window.
        Window("OpenStrudel", id: "home") { applicationContent }
        #else
        WindowGroup(id: "home") { applicationContent }
        #endif
    }

    private var applicationContent: some View {
        Group {
            #if os(macOS)
            if library.isErasing { LocalDataResetProgress() }
            else { OpenStrudelRootView() }
            #else
            OpenStrudelRootView()
            #endif
        }
            // Only an erase rebuilds the window; each device's conversation keeps its own identity.
            .id(library.viewGeneration)
            .tint(AppTheme.accent)
            .modifier(InterfaceLanguage())
            #if os(macOS)
            .modifier(AppIconAppearance())
            .modifier(HomeStatusItemAppearance())
            #endif
            .sheet(item: $library.invitation) { pairing in
                AddDeviceConfirmation(pairing: pairing)
                    .environmentObject(library)
            }
            .task(id: library.connectionListKey + (scenePhase == .background ? ":background" : ":visible")) {
                guard scenePhase != .background else { return }
                await library.watchCatalogues()
            }
            .onOpenURL { url in
                guard !library.isErasing else { return }
                if url.scheme == "openstrudel" && url.host == "oauth" && url.path == "/digitalocean" {
                    #if os(macOS)
                    DigitalOceanCloud.shared.acceptBrowserCallback(url)
                    #endif
                    return
                }
                if url.scheme == "openstrudel" && url.host == "oauth" && url.path.hasPrefix("/service/") {
                    _ = library.clients.first { $0.acceptServiceCallback(url) }
                    return
                }
                library.preparePairing(url)
            }
            .environmentObject(client)
            .environmentObject(library)
    }
}

#if os(macOS)
extension FocusedValues {
    /// Starts a new employee. Only the workspace publishes it, so the welcome screens disable ⌘N.
    @Entry var newEmployee: (() -> Void)?
    /// Opens the selected employee's details from the menu bar.
    @Entry var showEmployeeDetails: (() -> Void)?
    /// Shows the sidebar and focuses its search field.
    @Entry var findChat: (() -> Void)?
}

private struct NewEmployeeCommand: View {
    @FocusedValue(\.newEmployee) private var newEmployee
    let busy: Bool

    var body: some View {
        Button(L("Новый сотрудник")) { newEmployee?() }
            .keyboardShortcut("n", modifiers: .command)
            .disabled(newEmployee == nil || busy)
    }
}

private struct FindChatCommand: View {
    @FocusedValue(\.findChat) private var findChat

    var body: some View {
        Button(L("Найти чат")) { findChat?() }
            .keyboardShortcut("f", modifiers: .command)
            .disabled(findChat == nil)
    }
}

private struct EmployeeDetailsCommand: View {
    @FocusedValue(\.showEmployeeDetails) private var showDetails

    var body: some View {
        Button(L("Настройки сотрудника")) { showDetails?() }
            .keyboardShortcut("i", modifiers: .command)
            .disabled(showDetails == nil)
    }
}
#endif
