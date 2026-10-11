import XCTest

@MainActor final class ModelSettingsUITests: XCTestCase {
    func testDeviceDefaultsEmployeeOverrideAndInheritance() async throws {
        continueAfterFailure = false
        guard let fixture = ProcessInfo.processInfo.environment["OPENSTRUDEL_MODEL_FIXTURE"] else { throw XCTSkip("Start model-settings.ts.") }
        let app = XCUIApplication()
        app.launch()
        let invite = try await read(fixture + "/invite")
        app.open(try XCTUnwrap(URL(string: XCTUnwrap(invite["url"] as? String))))
        let confirm = app.buttons["confirmMacPairing"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 15)); confirm.tap(); app.finishDevicePairing()
        let consent = app.buttons["acceptAIDataSharing"]
        if consent.waitForExistence(timeout: 4) { consent.tap() }
        let chats = app.buttons["Чаты"]
        XCTAssertTrue(chats.waitForExistence(timeout: 15)); chats.tap()
        app.buttons["teamSettings"].tap()
        app.buttons["settingsSection"].tap(); app.buttons["Приложение"].tap()
        let model = app.buttons["modelChoice"], speed = app.buttons["modelSpeed"]
        XCTAssertTrue(model.waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["Рекомендует OpenAI · Medium"].exists, app.debugDescription)
        capture("automatic-account-model", app)
        model.tap(); app.buttons["GPT-6 Astra"].tap()
        speed.tap()
        XCTAssertFalse(app.buttons["Ultra Fast"].exists)
        app.buttons["Fast"].tap()
        app.buttons["saveModelSelection"].tap()
        XCTAssertTrue(app.staticTexts["Сохранено. Применится со следующего поручения."].waitForExistence(timeout: 10))
        capture("device-model-and-fast", app)
        app.navigationBars["Настройки"].buttons["Готово"].tap()
        XCTAssertTrue(model.waitForNonExistence(timeout: 10), app.debugDescription)
        let state = try await read(fixture + "/state")
        let profile = try XCTUnwrap(state["profile"] as? [String:Any])
        app.buttons["employee-" + (try XCTUnwrap(profile["id"] as? String))].tap()
        let details = app.buttons["openEmployeeDetails"]
        XCTAssertTrue(details.waitForExistence(timeout: 10))
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "Редактор"), object: details)], timeout: 10), .completed, app.debugDescription)
        details.tap()
        reveal(model, in: app)
        XCTAssertTrue(model.exists, app.debugDescription)
        XCTAssertFalse(speed.isEnabled, app.debugDescription)
        model.tap(); app.buttons["GPT-6 Sol"].tap()
        speed.tap(); app.buttons["Ultra Fast"].tap()
        app.buttons["saveModelSelection"].tap()
        XCTAssertTrue(app.staticTexts["Сохранено. Применится со следующего поручения."].waitForExistence(timeout: 10))
        capture("employee-model-override", app)
        var updated = try await read(fixture + "/state")
        XCTAssertEqual((updated["profile"] as? [String:Any])?["serviceTier"] as? String, "ultra")
        model.tap(); app.buttons["Как на устройстве · GPT-6 Astra"].tap()
        app.buttons["saveModelSelection"].tap()
        XCTAssertTrue(app.staticTexts["Сохранено. Применится со следующего поручения."].waitForExistence(timeout: 10))
        XCTAssertFalse(speed.isEnabled)
        updated = try await read(fixture + "/state")
        XCTAssertTrue((updated["profile"] as? [String:Any])?["model"] is NSNull)
        capture("employee-inherits-device", app)
    }
    private func read(_ url: String) async throws -> [String:Any] {
        let (data,_) = try await URLSession.shared.data(from: XCTUnwrap(URL(string:url)))
        return try XCTUnwrap(JSONSerialization.jsonObject(with:data) as? [String:Any])
    }
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<6 where !element.isHittable { app.scrollViews.firstMatch.swipeUp() }
    }
    private func capture(_ name: String, _ app: XCUIApplication) {
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot)
    }
}
