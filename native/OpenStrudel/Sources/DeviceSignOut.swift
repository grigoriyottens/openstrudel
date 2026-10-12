import SwiftUI

struct DeviceSignOutButton: View {
    @EnvironmentObject private var client: HomeClient
    let completed: () -> Void
    @State private var showing = false
    var body: some View {
        Button(L("Убрать подключение…")) { showing = true }
            .buttonStyle(.plain).foregroundStyle(AppTheme.secondaryText)
            .accessibilityIdentifier("signOutThisDevice")
            .accessibilityLabel(L("Убрать подключение к «\(client.displayName)»"))
            .sheet(isPresented: $showing) { DeviceSignOutView { showing = false; completed() } }
    }
}

struct DeviceSignOutView: View {
    @EnvironmentObject private var client: HomeClient
    @EnvironmentObject private var library: DeviceLibrary
    @Environment(\.dismiss) private var dismiss
    let completed: () -> Void
    @State private var showingBackup = false
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Text(L("Убрать «\(client.displayName)» из приложения?")).font(.title2.weight(.semibold))
                Text(L("Сотрудники и переписка останутся на устройстве. Их работа продолжится, пока оно включено."))
                    .font(.callout).foregroundStyle(AppTheme.secondaryText).fixedSize(horizontal: false, vertical: true)
                if client.canTransferAgents {
                    Button(L("Сначала сохранить копию…")) { showingBackup = true }.disabled(client.isSigningOut)
                }
                if client.isSigningOut { ProgressView(L("Отключаемся…")).controlSize(.small) }
                HStack {
                    Spacer()
                    Button(L("Отмена")) { dismiss() }.keyboardShortcut(.cancelAction)
                    Button(L("Убрать подключение")) {
                        let source = client
                        Task { await library.removeConnection(source); completed() }
                    }.buttonStyle(.borderedProminent).accessibilityIdentifier("confirmDeviceSignOut")
                }.disabled(client.isSigningOut)
            }.padding(28).navigationTitle(L("Подключение устройства"))
        }.interactiveDismissDisabled(client.isSigningOut)
        .sheet(isPresented: $showingBackup) {
            NavigationStack {
                ScrollView { AgentTransferSettings().padding(24) }.navigationTitle(L("Резервная копия"))
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button(L("Готово")) { showingBackup = false } } }
            }
            #if os(macOS)
            .frame(width: 560, height: 450)
            #endif
        }
        #if os(macOS)
        .frame(width: 500)
        #endif
    }
}
