import Foundation
import Testing

@Suite("Account identity") struct AccountPresentationTests {
    @Test func workspacePlansAreRecognizedWithoutGuessingFromEmail() {
        let workspace = OpenAIAccount(connected: true, email: "person@gmail.com", planType: "self_serve_business_prolite", managed: false)
        #expect(workspace.isWorkspace == true)
        #expect(workspace.planLabel == "ChatGPT Business")
        let personal = OpenAIAccount(connected: true, email: "person@company.example", planType: "pro", managed: false)
        #expect(personal.isWorkspace == false)
        let unknown = OpenAIAccount(connected: true, email: "person@company.example", planType: "future_plan", managed: false)
        #expect(unknown.isWorkspace == nil)
    }
    @Test func creditsAndResetsRemainSeparate() throws {
        let json = #"{"checkedAt":"2026-10-12T00:00:00Z","windows":[],"credits":{"hasCredits":true,"unlimited":false,"balance":"25"},"resetCredits":{"availableCount":2,"nextExpiresAt":1792000000}}"#
        let usage = try JSONDecoder().decode(ManagedCodexAccount.Usage.self, from: Data(json.utf8))
        #expect(usage.credits?.balance == "25")
        #expect(usage.resetCredits?.availableCount == 2)
        #expect(usage.resetCredits?.nextExpiresAt == 1792000000)
    }
}
