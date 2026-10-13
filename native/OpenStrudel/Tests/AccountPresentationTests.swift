import Foundation
import Testing

@Suite("Account identity") struct AccountPresentationTests {
    @Test func accountNameIsConsistentAndEmailRemainsVisible() throws {
        let json = #"{"id":"work","name":"Studio","displayName":"Studio","account":{"connected":true,"email":"owner@example.com","planType":"plus","managed":true},"usage":{"checkedAt":"2026-10-13T00:00:00Z","windows":[]},"activeRuns":0,"loginPending":false}"#
        let account = try JSONDecoder().decode(ManagedCodexAccount.self, from: Data(json.utf8))
        #expect(account.title == "Studio")
        #expect(account.emailDetail == "owner@example.com")
        #expect(account.identityLabel == "Studio · ChatGPT Plus")
    }
    @Test func oldServerNamesAndCompletedDuplicateSignInDecode() throws {
        let json = #"{"id":"default","name":"Основной","account":{"connected":false,"email":"owner@example.com","planType":"plus","managed":true,"issue":"unavailable"},"usage":{"checkedAt":"2026-10-13T00:00:00Z","windows":[]},"activeRuns":0,"loginPending":false}"#
        let account = try JSONDecoder().decode(ManagedCodexAccount.self, from: Data(json.utf8))
        #expect(account.title == "owner@example.com")
        #expect(account.emailDetail == nil)
        #expect(account.account.isUnavailable)
        let status = try JSONDecoder().decode(OpenAILoginStatus.self, from: Data(#"{"loginId":"test","status":"completed","alreadyConnected":true}"#.utf8))
        #expect(status.alreadyConnected == true)
    }
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
