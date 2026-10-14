import SwiftUI

struct HiddenEmployeesButton: View {
    @EnvironmentObject private var library: DeviceLibrary
    /// A settings row: a standard push button like its neighbours. Otherwise the sidebar's quiet row.
    var prominent = false
    @State private var showing = false
    private var count: Int { library.visibleClients.reduce(0) { $0 + library.hiddenProfiles(on: $1).count } }

    var body: some View {
        if count > 0 {
            Group {
                if prominent {
                    // The count stays in the sidebar; beside an ellipsis it would read as cut off.
                    Button(L("Показать скрытых сотрудников…")) { showing = true }
                } else {
                    Button { showing = true } label: {
                        Label(L("Скрытые сотрудники · \(count)"), systemImage: "eye.slash")
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                    .buttonStyle(.plain)
                }
            }
            .accessibilityIdentifier("hiddenEmployees")
            .sheet(isPresented: $showing) { HiddenEmployeesView() }
        }
    }
}

private struct HiddenEmployeesView: View {
    @EnvironmentObject private var library: DeviceLibrary
    @Environment(\.dismiss) private var dismiss
    private var sources: [HomeClient] { library.visibleClients.filter { !library.hiddenProfiles(on: $0).isEmpty } }

    var body: some View {
        NavigationStack {
            Form {
                ForEach(sources) { source in
                    Section {
                        ForEach(library.hiddenProfiles(on: source)) { profile in
                            HStack(spacing: 12) {
                                AgentAvatar(appearance: profile.resolvedAppearance, size: AvatarSize.row)
                                Text(profile.name)
                                Spacer()
                                // A text action is ink; the accent is for selection, focus and switches.
                                Button(L("Показать")) { Task { await library.setHidden(false, profile: profile, on: source) } }
                                    .buttonStyle(.borderless)
                                    .tint(AppTheme.accentText)
                                    .accessibilityLabel(L("Показать «\(profile.name)»"))
                            }.accessibilityElement(children: .contain)
                        }
                    } header: {
                        // Device names only when there are several, as in the sidebar.
                        if showsTitle(source) || library.hasOtherDevices {
                            VStack(alignment: .leading, spacing: 16) {
                                if showsTitle(source) {
                                    // The Mac sheet carries its title in its content, on the rows' text edge.
                                    Text(L("Скрытые сотрудники")).font(AppTypography.title).foregroundStyle(Color.primary)
                                        .textCase(nil).accessibilityAddTraits(.isHeader)
                                }
                                if library.hasOtherDevices { Text(source.displayName) }
                            }
                        }
                    } footer: {
                        if source === sources.last {
                            Text(L("Скрыты только в этом приложении. Сотрудники продолжают работать и доступны на других устройствах."))
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(L("Скрытые сотрудники"))
            #if os(macOS)
            .toolbar(removing: .title)
            #endif
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(L("Готово")) { dismiss() } } }
        }
        #if os(macOS)
        // A single page: as tall as its rows.
        .frame(width: 480)
        .presentationSizing(.fitted)
        #endif
    }

    private func showsTitle(_ source: HomeClient) -> Bool {
        #if os(macOS)
        source === sources.first
        #else
        false
        #endif
    }
}
