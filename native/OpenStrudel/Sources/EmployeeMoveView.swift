import SwiftUI

struct EmployeeMoveRequest: Identifiable {
    let source: HomeClient
    let profile: EmployeeProfile
    var targetID: String? = nil
    var id: String { source.id + ":" + profile.id }
}

struct EmployeeMoveButton: View {
    @EnvironmentObject private var client: HomeClient
    @EnvironmentObject private var library: DeviceLibrary
    @Environment(\.dismiss) private var dismissDetails
    let profile: EmployeeProfile
    var disabled = false
    @State private var showing = false
    var body: some View {
        Button(L("Перенести на другое устройство…"), systemImage: "arrow.right.square") { showing = true }
            .disabled(disabled || !client.canManageOpenAI)
            .accessibilityIdentifier("moveEmployee")
            .sheet(isPresented: $showing, onDismiss: {
                if !client.profiles.contains(where: { $0.id == profile.id }) { dismissDetails() }
            }) { EmployeeMoveView(request: EmployeeMoveRequest(source: client, profile: profile)) }
    }
}

struct EmployeeMoveStatusButton: View {
    @EnvironmentObject private var library: DeviceLibrary
    @State private var showing = false
    var body: some View {
        if let move = library.employeeMoves.operation, !move.phase.finished {
            Button { showing = true } label: {
                Label(L("Перенос: \(move.name)"), systemImage: "arrow.right.square")
                    .font(.callout).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
            }.buttonStyle(.plain).padding(12).accessibilityIdentifier("pendingEmployeeMove")
                .sheet(isPresented: $showing) { EmployeeMoveView() }
        }
    }
}

struct EmployeeMoveView: View {
    @EnvironmentObject private var library: DeviceLibrary
    @Environment(\.dismiss) private var dismiss
    var request: EmployeeMoveRequest? = nil
    @State private var targetID = ""
    @State private var error: String?

    private var moves: EmployeeMoves { library.employeeMoves }
    private var move: EmployeeMove? {
        guard let value = moves.operation else { return nil }
        return !value.phase.finished || request == nil || request?.id == value.sourceID + ":" + value.profileID ? value : nil
    }
    private var target: HomeClient? { library.clients.first { $0.id == targetID } }
    private var phaseText: String {
        switch move?.phase {
        case .preparing: L("Готовим сотрудника к переносу…")
        case .staging: L("Копируем и проверяем данные…")
        case .releasing: L("Завершаем работу на прежнем устройстве…")
        case .activating: L("Запускаем на новом устройстве…")
        case .finishing: L("Подтверждаем завершение…")
        case .completed: L("Сотрудник перенесён")
        case .canceling: L("Отменяем перенос…")
        case .canceled: L("Перенос отменён")
        case nil: ""
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let move {
                        Label(phaseText, systemImage: move.phase.finished ? "checkmark.circle" : "arrow.right.square")
                            .font(.title3.weight(.medium)).accessibilityIdentifier("employeeMovePhase")
                        Text("\(move.name)\n\(move.sourceName) → \(move.targetName)").font(.body)
                        if moves.busy { ProgressView().controlSize(.small) }
                        if move.phase == .completed {
                            Text(L("Переписка, файлы и расписания перенесены. Сотрудник работает на новом устройстве."))
                            Text(L("Используется аккаунт нового устройства. При необходимости подключите сервисы заново."))
                                .foregroundStyle(.secondary)
                            ForEach(move.warnings, id: \.self) { Text(L10n.serviceText($0)).font(.callout).foregroundStyle(.secondary) }
                            Button(L("Открыть сотрудника")) { Task { await library.refreshMovedEmployee(); dismiss() } }
                                .buttonStyle(.glassProminent).accessibilityIdentifier("openMovedEmployee")
                        } else if move.phase == .canceled {
                            Text(L("Сотрудник остался на прежнем устройстве."))
                            if request != nil { Button(L("Попробовать ещё раз")) { moves.dismissFinished() } }
                        } else {
                            Text(L("Можно продолжить пользоваться приложением. Если связь прервётся, перенос продолжится с сохранённого этапа."))
                                .font(.callout).foregroundStyle(.secondary)
                            if let failure = moves.error {
                                Text(L10n.serviceText(failure)).foregroundStyle(AppTheme.destructive)
                                    .accessibilityIdentifier("employeeMoveError")
                                Button(L("Продолжить перенос")) { moves.resume(using: library.moveTransport) }
                                    .buttonStyle(.glassProminent).disabled(moves.busy)
                            }
                            if move.phase.cancellable {
                                Button(L("Отменить перенос")) { moves.cancel(using: library.moveTransport) }
                                    .disabled(move.phase == .canceling).accessibilityIdentifier("cancelEmployeeMove")
                            }
                        }
                    } else if let request {
                        Text(request.profile.name).font(.title3.weight(.medium))
                        Text(L("Переписка, файлы и расписания переедут вместе с сотрудником."))
                            .font(.callout).foregroundStyle(.secondary)
                        let destinations = library.employeeMoveDestinations(from: request.source)
                        if destinations.isEmpty {
                            Text(L("Сначала подключите другое устройство в настройках."))
                        } else {
                            Picker(L("Куда перенести"), selection: $targetID) {
                                Text(L("Выберите устройство")).tag("")
                                ForEach(destinations) { destination in
                                    Text(destination.displayName).tag(destination.id)
                                }
                            }.accessibilityIdentifier("employeeMoveDestination")
                            if !request.source.canMoveEmployees || target != nil && target?.canMoveEmployees != true {
                                Text(L("Оба устройства должны быть на связи, обновлены и подключены с доступом владельца."))
                                    .font(.callout).foregroundStyle(.secondary)
                            }
                            Text(L("Аккаунты и доступ к сервисам остаются на прежнем устройстве. На новом используются его подключения."))
                                .font(.caption).foregroundStyle(.secondary)
                            Button(L("Перенести сотрудника")) {
                                guard let target else { return }
                                do { try moves.start(profile: request.profile, source: request.source, target: target, using: library.moveTransport) }
                                catch { self.error = error.localizedDescription }
                            }.buttonStyle(.glassProminent)
                                .disabled(!request.source.canMoveEmployees || target?.canMoveEmployees != true)
                                .accessibilityIdentifier("confirmEmployeeMove")
                        }
                        if let error { Text(L10n.serviceText(error)).foregroundStyle(AppTheme.destructive) }
                    }
                }.padding(24).frame(maxWidth: 520, alignment: .leading).frame(maxWidth: .infinity)
            }
            .navigationTitle(L("Перенос сотрудника"))
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(L("Готово")) { dismiss() } } }
            .task {
                guard let request else { return }
                let destinations = library.employeeMoveDestinations(from: request.source)
                targetID = request.targetID ?? (destinations.count == 1 ? destinations[0].id : "")
            }
            .onChange(of: moves.operation?.phase) { _, phase in
                if phase?.finished == true { Task { await library.refreshMovedEmployee(open: false) } }
            }
        }
        #if os(macOS)
        .frame(width: 520, height: 440)
        #endif
    }
}
