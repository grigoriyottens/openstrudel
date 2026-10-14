import Foundation
import Testing

@Suite struct AgentAppearanceTests {
    @Test func portableIdentitiesAndOlderProfiles() throws {
        #expect(AgentAppearance.seeded("main") == AgentAppearance(kind: "coil", tone: 4))
        #expect(AgentAppearance.seeded("Редактор") == AgentAppearance(kind: "coil", tone: 0))
        #expect(AgentAppearance.seeded("🍊") == AgentAppearance(kind: "pillow", tone: 3))
        let data = Data(#"{"id":"main","name":"Имя","instructions":"Правила","capabilities":[],"model":null,"tokenLimit":null,"createdAt":"2026-10-06"}"#.utf8)
        let old = try JSONDecoder().decode(EmployeeProfile.self, from: data)
        #expect(old.resolvedAppearance == .seeded("main"))
        var chosen = old
        chosen.appearance = AgentAppearance(kind: "wave", tone: 7)
        let copy = try JSONDecoder().decode(EmployeeProfile.self, from: JSONEncoder().encode(chosen))
        #expect(copy.resolvedAppearance == chosen.resolvedAppearance)
        #expect(copy.instructions == old.instructions)
    }
    @Test func aDraftNeverWearsACharacterAlreadyTaken() {
        let seed = AgentAppearance.seeded("draft:one")
        #expect(AgentAppearance.seeded("draft:one", avoiding: []) == seed)
        let next = AgentAppearance.seeded("draft:one", avoiding: [seed])
        #expect(next != seed)
        #expect(next.isValid)
        let all = AgentAppearance.kinds.flatMap { kind in (0..<8).map { AgentAppearance(kind: kind, tone: $0) } }
        #expect(AgentAppearance.seeded("draft:one", avoiding: all.filter { $0 != next }) == next)
        #expect(AgentAppearance.seeded("draft:one", avoiding: all) == seed)
    }
    @Test func shuffleChangesOnlyTheVisualIdentity() {
        for kind in AgentAppearance.kinds {
            for tone in 0..<8 {
                let original = AgentAppearance(kind: kind, tone: tone)
                let next = original.shuffled()
                #expect(next != original)
                #expect(next.isValid)
            }
        }
    }
}
