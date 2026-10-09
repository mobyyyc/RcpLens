import XCTest

@MainActor final class ReceiptAppLockUITests: XCTestCase {
    private func launch(_ fixture: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--t05-synthetic-preview", "wallet", "--t05-light", "--app-lock-fixture=" + fixture]
        app.launch(); return app
    }
    func testFailedAuthenticationHidesWalletAndRetryReleasesIt() {
        let app = launch("retry")
        XCTAssertTrue(app.buttons["unlockApp"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["import"].exists)
        XCTAssertFalse(app.buttons["receipt-0"].exists)
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); shot.name = "Fictional-app-lock"; shot.lifetime = .keepAlways; add(shot)
        app.buttons["unlockApp"].tap()
        XCTAssertTrue(app.buttons["import"].waitForExistence(timeout: 20))
        app.terminate()
    }
    func testCancellationStaysLockedWithoutErrorAlarm() {
        let app = launch("cancel")
        XCTAssertTrue(app.buttons["unlockApp"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["import"].exists)
        app.buttons["unlockApp"].tap()
        XCTAssertTrue(app.buttons["unlockApp"].exists)
        XCTAssertFalse(app.buttons["import"].exists)
        app.terminate()
    }
    func testSettingsEnableAndFiveMinuteDefault() {
        let app = launch("settings")
        XCTAssertTrue(app.buttons["walletSettings"].waitForExistence(timeout: 30)); app.buttons["walletSettings"].tap()
        let toggle = app.switches["appLockSetting"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 10))
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        let tree = XCTAttachment(string: app.debugDescription); tree.name = "Fictional-lock-settings-tree"; tree.lifetime = .keepAlways; add(tree)
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); shot.name = "Fictional-lock-settings"; shot.lifetime = .keepAlways; add(shot)
        XCTAssertTrue(app.buttons["appLockDelay"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["After 5 minutes"].exists)
        app.terminate()
    }
    func testCompletedReceiptUsesCornerCheckWithoutStatusText() {
        let app = launch("settings")
        XCTAssertTrue(app.buttons["receipt-0"].waitForExistence(timeout: 30))
        app.buttons["receipt-0"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.07)).tap()
        XCTAssertTrue(app.buttons["edit"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.images["receiptReviewedMark"].exists)
        XCTAssertFalse(app.staticTexts["Reviewed"].exists)
        XCTAssertFalse(app.staticTexts["Saved on this device"].exists)
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); shot.name = "Fictional-receipt-checkmark"; shot.lifetime = .keepAlways; add(shot)
        app.buttons["back"].tap()
        XCTAssertTrue(app.buttons["allReceipts"].waitForExistence(timeout: 10)); app.buttons["allReceipts"].tap()
        let result = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "searchReceipt-")).firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 10)); result.tap()
        XCTAssertTrue(app.images["receiptReviewedMark"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["Reviewed"].exists)
        XCTAssertFalse(app.staticTexts["Saved on this device"].exists)
        app.terminate()
    }

    private func enableLock(_ app: XCUIApplication) {
        XCTAssertTrue(app.buttons["walletSettings"].waitForExistence(timeout: 30)); app.buttons["walletSettings"].tap()
        let toggle = app.switches["appLockSetting"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 10))
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertTrue(app.buttons["appLockDelay"].waitForExistence(timeout: 10))
    }
    func testReturnInsideGraceDoesNotAuthenticateAgain() {
        let app = launch("settings"); enableLock(app)
        app.buttons["Done"].tap()
        XCUIDevice.shared.press(.home); app.activate()
        // The fixture rejects any second authentication; a grace return must still open.
        XCTAssertTrue(app.buttons["import"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["unlockApp"].exists)
        app.terminate()
    }
    func testImmediateReturnLocksAndHidesReceiptContent() {
        let app = launch("settings"); enableLock(app)
        app.buttons["appLockDelay"].tap(); app.buttons["Immediately"].tap()
        app.buttons["Done"].tap()
        XCUIDevice.shared.press(.home); app.activate()
        XCTAssertTrue(app.buttons["unlockApp"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["import"].exists)
        XCTAssertFalse(app.buttons["receipt-0"].exists)
        app.terminate()
    }

}
