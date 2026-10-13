import SwiftUI

struct HiddenEmployeesButton: View {
    @EnvironmentObject private var library: DeviceLibrary
    @State private var showing = false
    private var count: Int { library.visibleClients.reduce(0) { $0 + library.hiddenProfiles(on: $1).count } }

    var body: some View {
        if count > 0 {
            Button { showing = true } label: {
                Label(L("Скрытые сотрудники · \(count)"), systemImage: "eye.slash")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
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
                                Button(L("Показать")) { Task { await library.setHidden(false, profile: profile, on: source) } }
                                    .buttonStyle(.borderless)
                                    .accessibilityLabel(L("Показать «\(profile.name)»"))
                            }.accessibilityElement(children: .contain)
                        }
                    } header: {
                        Text(source.displayName)
                    } footer: {
                        if source === sources.last {
                            Text(L("Скрыты только в этом приложении. Сотрудники продолжают работать и доступны на других устройствах."))
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(L("Скрытые сотрудники"))
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(L("Готово")) { dismiss() } } }
        }
        #if os(macOS)
        // A single page: as tall as its rows.
        .frame(width: 480)
        .presentationSizing(.fitted)
        #endif
    }
}
