#if os(macOS)
import SwiftUI

/// A direct provider payment followed by the existing server/account setup.
/// The saved order remains available when the browser or this sheet is closed.
struct AgentMetalSetupView: View {
    @EnvironmentObject private var library: DeviceLibrary
    @Environment(\.openURL) private var openURL
    @StateObject private var setup = AgentMetalSetupFlow.shared
    @Binding var working: Bool
    let onConnected: (HomeClient) -> Void
    @State private var days = 7
    @State private var saving = false
    @State private var localError: String?
    @State private var paymentCheck = 0

    private var price: String {
        guard let offer = setup.offer else { return "" }
        return offer.amount.formatted(.currency(code: "USD").locale(L10n.locale))
    }
    var body: some View {
        Form {
            Section {
                if let server = setup.order.server {
                    LabeledContent(L("Server address"), value: server.ipv4)
                    if let expiry = server.expiry {
                        LabeledContent(L("Paid until")) { Text(expiry, format: .dateTime.day().month().year().hour().minute()) }
                    }
                } else if let offer = setup.offer {
                    if let memory = offer.memoryGB, let disk = offer.diskGB {
                        Text(L("\(memory) GB memory · \(disk) GB storage"))
                    }
                    if setup.order.intent == nil {
                        Picker(L("Rental period"), selection: $days) {
                            Text(L("1 day")).tag(1)
                            Text(L("7 days")).tag(7)
                            Text(L("30 days")).tag(30)
                        }.disabled(setup.busy).accessibilityIdentifier("agentMetalDuration")
                    } else {
                        LabeledContent(L("Rental period"), value: offer.days == 1 ? L("1 day") : L("\(offer.days) days"))
                    }
                    LabeledContent(L("Total"), value: price)
                }
            } header: {
                SheetTitle(title: L("Get a server with AgentMetal"))
            } footer: {
                Text(L("Pay AgentMetal directly by card. No provider account is needed. OpenStrudel installs and connects your server after payment."))
            }

            if setup.loading {
                Section { ProgressView(L("Loading the offer…")) }
            } else if let identity = setup.identityToConfirm {
                // The address is in the section above.
                ServerFingerprintSection(identity: identity)
            } else if setup.installing, let installer = setup.installer {
                AgentMetalInstallationProgress(installer: installer)
            } else if setup.order.server != nil && setup.connection == nil {
                Section { Text(L("Your server is saved. Continue setup when you are ready.")) }
            } else if setup.order.checkout != nil && setup.connection == nil {
                Section {
                    if setup.waiting { ProgressView(L("Waiting for payment and your server…")) }
                    else { Text(L("Your order is saved. Complete payment in the browser, then check again here.")) }
                    Button(L("Open payment page")) {
                        if let url = setup.order.checkout?.url { openURL(url) }
                    }.accessibilityIdentifier("agentMetalReopenCheckout")
                }
            } else if setup.connection != nil {
                Section {
                    Label(L("OpenStrudel is installed"), systemImage: "checkmark.circle")
                    if setup.order.connection != nil {
                        Button(L("Get another server")) { Task { await setup.newOrder(days: days) } }
                            .disabled(saving).accessibilityIdentifier("agentMetalNewOrder")
                    }
                }
            }

            Section {
                Text(L("Prepaid, with no automatic renewal. AgentMetal deletes the server two hours after the paid period ends. Save a backup or extend the rental before it expires."))
                    .font(AppTypography.meta).foregroundStyle(AppTheme.secondaryText)
                Link(L("AgentMetal rental and renewal details"), destination: URL(string: "https://agentmetal.dev/docs/#expiry")!)
            }
            if let error = localError ?? setup.error {
                Section { Text(error).foregroundStyle(AppTheme.warning).fixedSize(horizontal: false, vertical: true) }
            }
        }
        .formStyle(.grouped)
        .sheetPageTitle("AgentMetal")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if setup.connection != nil {
                    Button(L("Продолжить")) { Task { await finish() } }
                        .disabled(saving).accessibilityIdentifier("agentMetalOpenServer")
                } else if setup.identityToConfirm != nil {
                    Button(L("Confirm and connect")) { setup.confirmIdentity() }
                        .accessibilityIdentifier("confirmSSHIdentity")
                } else if setup.order.checkout != nil {
                    Button(setup.order.server == nil ? L("Check payment") : L("Continue setup")) { paymentCheck += 1 }
                        .disabled(setup.busy).accessibilityIdentifier("agentMetalCheckPayment")
                } else if setup.offer != nil {
                    Button(L("Pay \(price) to AgentMetal")) {
                        Task {
                            if let url = await setup.checkout() { openURL(url); paymentCheck += 1 }
                        }
                    }.disabled(setup.busy).accessibilityIdentifier("agentMetalPay")
                } else {
                    Button(L("Повторить")) { Task { await setup.load(days: days) } }.disabled(setup.busy)
                }
            }
        }
        .task(id: days) {
            await setup.load(days: days)
            if !Task.isCancelled, setup.order.checkout != nil && setup.connection == nil { paymentCheck += 1 }
        }
        .task(id: paymentCheck) { [check = paymentCheck] in
            if check > 0, setup.order.checkout != nil && setup.connection == nil { await setup.checkPayment() }
        }
        .onChange(of: setup.working, initial: true) { _, value in working = value }
        .onDisappear { setup.pause(); working = false }
    }

    private func finish() async {
        guard let connection = setup.connection, !saving else { return }
        saving = true; localError = nil; defer { saving = false }
        let client = library.clients.first { $0.savedBaseURL == connection.url } ?? library.newConnection()
        guard await client.connectToCloud(connection) else { localError = client.pairingError; return }
        library.add(client, select: false)
        do { try setup.saveConnection(connection); onConnected(client) }
        catch { localError = error.localizedDescription }
    }
}

private struct AgentMetalInstallationProgress: View {
    @ObservedObject var installer: ServerSetupFlow
    private var title: String {
        switch installer.stage {
        case "dependencies": L("Preparing the server")
        case "download": L("Downloading OpenStrudel")
        case "build": L("Installing OpenStrudel")
        case "verify": L("Checking the connection")
        default: L("Connecting to the server")
        }
    }
    var body: some View {
        Section { ProgressView(title) } footer: {
            Text(L("You can close this window. Your order and setup progress are saved."))
        }
    }
}
#endif
