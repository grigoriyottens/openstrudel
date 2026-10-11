import XCTest

@MainActor final class AppleReviewUITests: XCTestCase {
    func testPrivateReviewPageConnectsAndAnswers() async throws {
        continueAfterFailure = false
        guard let fixture = ProcessInfo.processInfo.environment["OPENSTRUDEL_REVIEW_PAGE_FIXTURE"],
              let endpoint = URL(string: fixture) else { throw XCTSkip("Provide the private review page fixture.") }
        let (data, response) = try await URLSession.shared.data(from: endpoint)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let page = try XCTUnwrap(URL(string: XCTUnwrap(payload["url"] as? String)))
        let app = XCUIApplication()
        app.launch()
        let safari = XCUIApplication(bundleIdentifier: "com.apple.mobilesafari")
        safari.open(page)
        let open = safari.links["Открыть OpenStrudel"]
        XCTAssertTrue(open.waitForExistence(timeout: 30), safari.debugDescription)
        open.tap()
        let confirmation = safari.buttons.matching(NSPredicate(format: "label IN %@", ["Open", "Открыть"])).firstMatch
        if confirmation.waitForExistence(timeout: 5) { confirmation.tap() }
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let systemOpen = springboard.alerts.buttons.matching(NSPredicate(format: "label IN %@", ["Open", "Открыть"])).firstMatch
        if systemOpen.waitForExistence(timeout: 2) { systemOpen.tap() }
        let connect = app.buttons["confirmMacPairing"]
        XCTAssertTrue(connect.waitForExistence(timeout: 20), app.debugDescription + safari.debugDescription)
        connect.tap()
        app.finishDevicePairing()
        let consent = app.buttons["acceptAIDataSharing"]
        if consent.waitForExistence(timeout: 5) { consent.tap() }
        let input = app.textFields["Сообщение"]
        XCTAssertTrue(input.waitForExistence(timeout: 30), app.debugDescription)
        let expected = "Review ready " + UUID().uuidString.prefix(6)
        input.tap()
        input.typeText("Reply exactly: " + expected)
        capture("review-composer-ready", app)
        let send = app.buttons["sendMessage"]
        XCTAssertTrue(send.isEnabled && send.isHittable)
        send.tap()
        let sent = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", ""), object: input)
        XCTAssertEqual(XCTWaiter.wait(for: [sent], timeout: 10), .completed, app.debugDescription)
        XCTAssertTrue(app.staticTexts[expected].waitForExistence(timeout: 120), app.debugDescription)
        capture("review-page-real-reply", app)
        app.terminate(); app.launch()
        XCTAssertTrue(app.staticTexts[expected].waitForExistence(timeout: 20), app.debugDescription)
        capture("review-page-relaunch", app)
    }

    private func capture(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
