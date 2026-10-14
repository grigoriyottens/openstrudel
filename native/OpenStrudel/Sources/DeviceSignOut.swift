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
            VStack(alignment: .leading, spacing: 12) {
                Text(L("Убрать «\(client.displayName)» из приложения?")).font(AppTypography.title)
                Text(L("Сотрудники и переписка останутся на устройстве. Их работа продолжится, пока оно включено."))
                    .font(AppTypography.interface).foregroundStyle(AppTheme.secondaryText)
                if client.canTransferAgents {
                    Button(L("Сначала сохранить копию…")) { showingBackup = true }
                        .disabled(client.isSigningOut)
                        .padding(.top, 4)
                }
                if client.isSigningOut { ProgressView(L("Отключаемся…")).controlSize(.small) }
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(24)
            #if os(macOS)
            .frame(width: 440, alignment: .leading)
            #else
            .navigationTitle(L("Подключение устройства"))
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Отмена")) { dismiss() }.disabled(client.isSigningOut)
                }
                // Not the default button: Return must not remove a device.
                ToolbarItem(placement: .destructiveAction) {
                    Button(L("Убрать подключение"), role: .destructive) {
                        let source = client
                        Task { await library.removeConnection(source); completed() }
                    }
                    .disabled(client.isSigningOut)
                    .accessibilityIdentifier("confirmDeviceSignOut")
                }
            }
        }
        .interactiveDismissDisabled(client.isSigningOut)
        .presentationSizing(.fitted)
        .sheet(isPresented: $showingBackup) {
            NavigationStack {
                Form {
                    Section { AgentTransferSettings() }
                }
                .formStyle(.grouped)
                .navigationTitle(L("Резервная копия"))
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button(L("Готово")) { showingBackup = false } } }
            }
            #if os(macOS)
            .frame(width: 480, height: 320)
            #endif
            .presentationSizing(.fitted)
        }
    }
}
