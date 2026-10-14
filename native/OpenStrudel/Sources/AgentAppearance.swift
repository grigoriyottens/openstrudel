import SwiftUI

struct AgentAppearance: Codable, Hashable, Sendable {
    var version = 1
    var kind: String
    var tone: Int

    static let kinds = ["coil", "fold", "knot", "curl", "wave", "pillow"]
    static var names: [String] { [L("Завиток"), L("Конвертик"), L("Узелок"), L("Рогалик"), L("Волна"), L("Подушечка")] }
    static var tones: [String] { [L("Абрикос"), L("Мёд"), L("Фисташка"), L("Мята"), L("Небо"), L("Черника"), L("Сирень"), L("Малина")] }
    static let angles: [Double] = [0, 32, 72, 125, 180, 215, 255, 315]
    var isValid: Bool { version == 1 && Self.kinds.contains(kind) && Self.tones.indices.contains(tone) }
    var label: String { Self.names[Self.kinds.firstIndex(of: kind) ?? 0] }
    var hue: Angle { .degrees(Self.angles.indices.contains(tone) ? Self.angles[tone] : 0) }

    static func seeded(_ id: String) -> Self {
        let hash = id.utf8.reduce(UInt32(2166136261)) { ($0 ^ UInt32($1)) &* 16777619 }
        return Self(kind: kinds[Int(hash) % kinds.count], tone: Int(hash) / kinds.count % tones.count)
    }
    /// The seeded character, or the next one nobody wears yet; the seed's own when all 48 are taken.
    static func seeded(_ id: String, avoiding used: [AgentAppearance]) -> Self {
        let seed = seeded(id)
        let start = (kinds.firstIndex(of: seed.kind) ?? 0) * 8 + seed.tone
        for step in 0..<48 {
            let index = (start + step) % 48
            let candidate = Self(kind: kinds[index / 8], tone: index % 8)
            if !used.contains(candidate) { return candidate }
        }
        return seed
    }
    func shuffled() -> Self {
        let current = (Self.kinds.firstIndex(of: kind) ?? 0) * 8 + tone
        let next = (current + Int.random(in: 1..<48)) % 48
        return Self(kind: Self.kinds[next / 8], tone: next % 8)
    }
    var payload: [String: Any] { ["version": version, "kind": kind, "tone": tone] }
}

extension EmployeeProfile {
    var resolvedAppearance: AgentAppearance {
        if let appearance, appearance.isValid { return appearance }
        return .seeded(id)
    }
}
