import Foundation

enum MessagePages {
    /// Half an hour of quiet, or a new day, opens a new time cluster.
    static let clusterPause: TimeInterval = 30 * 60

    struct Row: Identifiable {
        let message: HomeMessage
        /// The moment shown above this message when it opens a time cluster.
        let header: Date?
        /// The previous message came from the other side, so a new turn begins.
        let startsTurn: Bool
        var id: String { message.id }
    }

    static func opensCluster(_ date: Date, after previous: Date?, calendar: Calendar = .current) -> Bool {
        guard let previous else { return true }
        return !calendar.isDate(date, inSameDayAs: previous) || date.timeIntervalSince(previous) >= clusterPause
    }

    /// A lazy row may render after the selected conversation has changed.
    /// Derive its time heading and rhythm from the same snapshot as its message.
    static func rows(_ messages: [HomeMessage], calendar: Calendar = .current) -> [Row] {
        var previous: HomeMessage?
        return messages.map { message in
            let sentAt = message.sentAt
            let opens = sentAt.map { opensCluster($0, after: previous?.sentAt, calendar: calendar) } ?? false
            let startsTurn = previous.map { $0.direction != message.direction } ?? false
            previous = message
            return Row(message: message, header: opens ? sentAt : nil, startsTurn: startsTurn)
        }
    }

    /// Pages are ordered by the server, including messages with identical dates.
    static func merge(existing: [HomeMessage], page: [HomeMessage], updates: [HomeMessage] = [], prepend: Bool = false) -> [HomeMessage] {
        let existingIDs = Set(existing.map(\.id))
        let changes = Dictionary((page + updates).map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
        let current = existing.map { changes[$0.id] ?? $0 }
        let new = page.filter { !existingIDs.contains($0.id) }
        return prepend ? new + current : current + new
    }
}
