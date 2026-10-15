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
    @Test func keyProviderAccountNamesItsProviderAndOlderHomesStayChatGPT() throws {
        let key = try JSONDecoder().decode(OpenAIAccountEnvelope.self, from: Data(#"{"account":{"connected":false,"email":null,"planType":null,"provider":"anthropic","providerName":"Anthropic"},"accountId":"provider-anthropic","loginPending":false,"canManage":true}"#.utf8))
        #expect(key.account.keyProviderName == "Anthropic")
        #expect(!key.account.connected && !key.account.isUnavailable)
        let chatgpt = try JSONDecoder().decode(OpenAIAccount.self, from: Data(#"{"connected":true,"email":"owner@example.com","planType":"plus","managed":true,"provider":"chatgpt","providerName":"ChatGPT"}"#.utf8))
        #expect(chatgpt.keyProviderName == nil)
        let older = try JSONDecoder().decode(OpenAIAccount.self, from: Data(#"{"connected":true,"email":null,"planType":"plus","managed":true}"#.utf8))
        #expect(older.keyProviderName == nil)
    }
    @Test func modelPickerGroupsModelsByConnectedProvider() throws {
        let speed = #"[{"id":"default","name":"Обычная","description":""}]"#
        let fable = #"{"id":"claude-fable-5-1","name":"Claude Fable 5.1","description":"","isDefault":true,"speeds":\#(speed),"provider":"anthropic"}"#
        let json = #"""
        {"models":[{"id":"gpt-6.1-sol","name":"GPT-6.1 Sol","description":"","isDefault":true,"defaultReasoningEffort":"medium","speeds":[{"id":"default","name":"Обычная","description":""},{"id":"priority","name":"Fast","description":""}],"provider":"chatgpt"},
          {"id":"gpt-6.1-sol","name":"GPT-6.1 Sol","description":"","isDefault":true,"speeds":\#(speed),"provider":"openai"},\#(fable)],
         "providers":[{"id":"chatgpt","name":"ChatGPT","auth":"signin","connected":true,"keyHint":null,"keysUrl":null,"usedBy":2},
          {"id":"openai","name":"OpenAI API","auth":"key","connected":true,"keyHint":"••••abc","keysUrl":"https://platform.openai.com/api-keys","usedBy":0},
          {"id":"anthropic","name":"Anthropic","auth":"key","connected":true,"keyHint":"••••7Qa","keysUrl":"https://platform.claude.com/settings/keys","usedBy":1}],
         "recommended":\#(fable),"selection":{"provider":"openai","model":"gpt-6.1-sol","serviceTier":"default"},
         "defaults":{"provider":"anthropic","model":"claude-fable-5-1","serviceTier":"default"},
         "effective":{"provider":"openai","model":"gpt-6.1-sol","serviceTier":"default"},"canManage":true}
        """#
        let settings = try JSONDecoder().decode(ModelSettings.self, from: Data(json.utf8))
        #expect(settings.groups.map { $0.provider?.name } == ["ChatGPT", "OpenAI API", "Anthropic"])
        // ChatGPT and an OpenAI key share model ids, yet each stays its own choice.
        let selected = try #require(settings.model(settings.selection.ref))
        #expect(selected.provider == "openai" && selected.speeds.count == 1)
        #expect(settings.model(ModelRef(provider: "chatgpt", model: "gpt-6.1-sol"))?.speeds.count == 2)
        #expect(settings.model(ModelRef(provider: "kimi", model: "kimi-k3")) == nil)
        // A closed picker shows one line, so the provider tells the subscription from the key.
        #expect(settings.title(selected) == "GPT-6.1 Sol · OpenAI API")
        #expect(settings.model(ModelRef(provider: "chatgpt", model: "gpt-6.1-sol")).map(settings.title) == "GPT-6.1 Sol · ChatGPT")
        // Only OpenAI's own catalog marks a default; the registry's pick for another provider is ours.
        #expect(settings.recommended.map(settings.recommendation) == L("Рекомендуем"))
        #expect(settings.model(ModelRef(provider: "chatgpt", model: "gpt-6.1-sol")).map(settings.recommendation) == L("Рекомендует OpenAI"))
        #expect(settings.recommended?.defaultReasoningEffort == nil)
        // The OpenAI account choice applies only to an employee that runs on ChatGPT.
        #expect(!settings.runsOnChatGPT)
    }
    @Test func oneConnectedProviderNeedsNoProviderInTheModelName() throws {
        let opus = #"{"id":"anthropic/claude-opus-5.5","name":"Claude Opus 5.5","description":"","isDefault":true,"speeds":[{"id":"default","name":"Обычная","description":""}],"provider":"openrouter"}"#
        let json = #"{"models":[\#(opus)],"providers":[{"id":"openrouter","name":"OpenRouter","auth":"key","connected":true,"keyHint":"••••7Qa","keysUrl":"https://openrouter.ai/settings/keys","usedBy":2}],"recommended":\#(opus),"selection":{"provider":null,"model":null,"serviceTier":"default"},"defaults":{"provider":"openrouter","model":"anthropic/claude-opus-5.5","serviceTier":"default"},"effective":{"provider":"openrouter","model":"anthropic/claude-opus-5.5","serviceTier":"default"},"canManage":true}"#
        let settings = try JSONDecoder().decode(ModelSettings.self, from: Data(json.utf8))
        #expect(settings.recommended.map(settings.title) == "Claude Opus 5.5")
        #expect(settings.recommended.map(settings.recommendation) == L("Рекомендуем"))
    }
    @Test func olderHomeModelSettingsKeepOneUnnamedList() throws {
        let json = #"{"models":[{"id":"gpt-6.1-sol","name":"GPT-6.1 Sol","description":"","isDefault":true,"defaultReasoningEffort":"medium","speeds":[{"id":"default","name":"Обычная","description":""}]}],"recommended":{"id":"gpt-6.1-sol","name":"GPT-6.1 Sol","description":"","isDefault":true,"defaultReasoningEffort":"medium","speeds":[{"id":"default","name":"Обычная","description":""}]},"selection":{"model":null,"serviceTier":"default"},"defaults":{"model":"gpt-6.1-sol","serviceTier":"default"},"effective":{"model":"gpt-6.1-sol","serviceTier":"default"},"canManage":true}"#
        let settings = try JSONDecoder().decode(ModelSettings.self, from: Data(json.utf8))
        #expect(settings.groups.count == 1 && settings.groups[0].provider == nil)
        #expect(settings.model(settings.defaults.ref)?.name == "GPT-6.1 Sol")
        #expect(settings.model(settings.defaults.ref).map(settings.title) == "GPT-6.1 Sol")
        #expect(settings.recommended.map(settings.recommendation) == L("Рекомендует OpenAI"))
        #expect(settings.runsOnChatGPT)
        // Automatic sends no provider, exactly as an older app did.
        #expect(settings.selection == ModelSelection(model: nil, serviceTier: "default"))
    }
    @Test func providerListSeparatesConnectedKeysFromAddableOnes() throws {
        let json = #"{"providers":[{"id":"chatgpt","name":"ChatGPT","auth":"signin","connected":false,"keyHint":null,"keysUrl":null,"usedBy":0},{"id":"xai","name":"xAI","auth":"key","connected":true,"keyHint":"••••7Qa","keysUrl":"https://console.x.ai","usedBy":3},{"id":"kimi","name":"Kimi","auth":"key","connected":false,"keyHint":null,"keysUrl":"https://platform.moonshot.ai/console/api-keys","usedBy":0}],"canManage":true}"#
        let list = try JSONDecoder().decode(ProviderList.self, from: Data(json.utf8))
        #expect(list.providers.filter(\.connectedKey).map(\.id) == ["xai"])
        #expect(list.providers.filter(\.canAddKey).map(\.id) == ["kimi"])
        #expect(list.providers[1].keyHint == "••••7Qa" && list.providers[1].usedBy == 3)
        // usedBy also counts the main chat and the device default, so it is never called a number of employees.
        #expect(list.providers[1].removalWarning == L("Сотрудников и настроек на этом ключе: \(3). Их модель станет «Как на устройстве» или «Автоматически»."))
    }
    @Test func aNewKeyClearsTheProvidersAnswerAboutTheOldOne() {
        var entry = ProviderKeyEntry()
        #expect(!entry.ready)
        entry.key = "sk-bad"; entry.error = "Anthropic не принял ключ."
        entry.key = "sk-bad"
        #expect(entry.error != nil)
        entry.key = "sk-good"
        #expect(entry.error == nil && entry.ready)
        entry.busy = true
        #expect(!entry.ready)
    }
    @Test func balancesBelongToASignedInChatGPTAccount() throws {
        func account(_ fields: String) throws -> ManagedCodexAccount {
            try JSONDecoder().decode(ManagedCodexAccount.self, from: Data(#"{"id":"a","name":"ChatGPT","account":{"connected":\#(fields)},"usage":{"checkedAt":"2026-10-14T00:00:00Z","windows":[]},"activeRuns":0,"loginPending":false}"#.utf8))
        }
        let signedOut = try account("false"), signedIn = try account("true"), unreachable = try account(#"false,"issue":"unavailable""#)
        #expect(![ManagedCodexAccount]().hasUsage)
        #expect(![signedOut].hasUsage)
        #expect([signedOut, signedIn].hasUsage)
        // OpenAI cannot confirm the account right now, so Refresh stays its way back.
        #expect([unreachable].hasUsage)
    }
    @Test func automaticReviewIsOfferedOnlyWhileAModelRunsOnChatGPT() throws {
        func list(chatgptUsers: Int) throws -> ProviderList {
            try JSONDecoder().decode(ProviderList.self, from: Data(#"{"providers":[{"id":"chatgpt","name":"ChatGPT","auth":"signin","connected":true,"keyHint":null,"keysUrl":null,"usedBy":\#(chatgptUsers)},{"id":"xai","name":"xAI","auth":"key","connected":true,"keyHint":"••••7Qa","keysUrl":"https://console.x.ai","usedBy":3}],"canManage":true}"#.utf8))
        }
        #expect(try !list(chatgptUsers: 0).reviewsAutomatically)
        #expect(try list(chatgptUsers: 1).reviewsAutomatically)
    }
}
