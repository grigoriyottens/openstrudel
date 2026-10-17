import SwiftUI

/// A conversation choice uses the existing settings and the provider's own catalog.
/// Loading the catalog once on entry keeps it out of the transcript polling loop.
struct ConversationModelControl: View {
    @EnvironmentObject private var client: HomeClient
    let conversationID: String
    @State private var settings: ModelSettings?
    @State private var showingSettings = false

    private var title: String {
        guard let settings else { return L("Модель") }
        let model = settings.model(settings.effective.ref)
        let name = model.map(settings.title) ?? settings.effective.model ?? L("Автоматически")
        let speed = model?.speeds.first { $0.id == settings.effective.serviceTier }
        return name + (speed != nil && speed?.id != "default" ? " · " + L10n.text(speed!.name) : "")
    }

    var body: some View {
        Button { showingSettings = true } label: {
            HStack(spacing: 5) {
                Text(title).lineLimit(2).multilineTextAlignment(.trailing)
                Image(systemName: "chevron.down").imageScale(.small)
            }
            .font(AppTypography.meta)
            .foregroundStyle(AppTheme.secondaryText)
            .frame(minHeight: controlTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L("Модель и скорость"))
        .accessibilityValue(title)
        .accessibilityIdentifier("conversationModel")
        .task(id: client.conversationModel) {
            settings = try? await client.management("/v1/conversations/" + conversationID + "/model")
        }
        .sheet(isPresented: $showingSettings) {
            SheetStack {
                Form {
                    SheetTitleSection(title: L("Модель и скорость"))
                    Section {
                        ModelSettingsView(conversationID: conversationID, onLoad: { settings = $0 })
                    }
                }
                .formStyle(.grouped)
                .sheetPageTitle(L("Модель и скорость"))
            } bar: {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Готово")) { showingSettings = false }
                }
            }
        }
    }
}
