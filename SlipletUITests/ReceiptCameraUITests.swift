import XCTest

/// Capture UI uses fictional bytes only, in the existing isolated synthetic store.
/// Hardware capture, permission prompt and focus/sharpness still require a physical iPhone.
@MainActor final class ReceiptCameraUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }
    private func launch(_ fixture: String? = nil, extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--t05-synthetic-preview", "empty"] + extra
        if let fixture { app.launchArguments.append("--camera-fixture=" + fixture) }
        app.launch()
        XCTAssertTrue(app.buttons["import"].waitForExistence(timeout: 15))
        app.buttons["import"].tap(); app.buttons["Take a photo"].tap()
        XCTAssertTrue(app.buttons["cameraCancel"].waitForExistence(timeout: 10))
        return app
    }
    private func capture(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); attachment.name = name
        attachment.lifetime = .keepAlways; add(attachment)
    }
    func testRetakeUsePhotoOriginalAndSaveDraft() {
        let app = launch("live")
        XCTAssertTrue(app.staticTexts["Keep all four edges in view"].exists)
        XCTAssertTrue(app.buttons["cameraShutter"].isEnabled)
        capture("camera-guide", app: app)
        app.buttons["cameraShutter"].tap()
        XCTAssertTrue(app.buttons["cameraUse"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.descendants(matching: .any)["reviewScreen"].exists, "Capture must wait for explicit Use photo")
        capture("camera-photo-check", app: app)
        app.buttons["cameraRetake"].tap()
        XCTAssertTrue(app.buttons["cameraShutter"].waitForExistence(timeout: 10))
        app.buttons["cameraShutter"].tap()
        XCTAssertTrue(app.buttons["cameraUse"].waitForExistence(timeout: 10)); app.buttons["cameraUse"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["reviewScreen"].waitForExistence(timeout: 25), "Photo must use the real Vision/parser import")
        XCTAssertFalse(app.buttons["finishSave"].isEnabled)
        app.buttons["original"].tap()
        XCTAssertTrue(app.buttons["sourceDone"].waitForExistence(timeout: 10)); app.buttons["sourceDone"].tap()
        app.buttons["saveDraft"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["detailScreen"].waitForExistence(timeout: 15))
        app.buttons["back"].tap()
        XCTAssertTrue(app.buttons["receipt-0"].waitForExistence(timeout: 10))
        app.terminate(); app.launchArguments = ["--t05-synthetic-preview", "resume"]; app.launch()
        XCTAssertTrue(app.buttons["receipt-0"].waitForExistence(timeout: 15), "Camera draft and original must persist")
        app.buttons["receipt-0"].tap()
        XCTAssertTrue(app.buttons["original"].waitForExistence(timeout: 15)); app.buttons["original"].tap()
        XCTAssertTrue(app.buttons["sourceDone"].waitForExistence(timeout: 10))
    }
    func testCancelAndBackgroundDiscardUnacceptedPhoto() {
        let app = launch("live")
        app.buttons["cameraShutter"].tap()
        XCTAssertTrue(app.buttons["cameraUse"].waitForExistence(timeout: 10)); app.buttons["cameraCancel"].tap()
        XCTAssertTrue(app.buttons["import"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["receipt-0"].exists)
        app.buttons["import"].tap(); app.buttons["Take a photo"].tap()
        XCTAssertTrue(app.buttons["cameraShutter"].waitForExistence(timeout: 10)); app.buttons["cameraShutter"].tap()
        XCTAssertTrue(app.buttons["cameraUse"].waitForExistence(timeout: 10))
        XCUIDevice.shared.press(.home); app.activate()
        XCTAssertTrue(app.buttons["import"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["cameraUse"].exists)
        XCTAssertFalse(app.buttons["receipt-0"].exists)
    }
    func testDeniedRestrictedAndSimulatorFallback() {
        for fixture in ["denied", "restricted", "unavailable"] {
            let app = launch(fixture)
            XCTAssertEqual(app.buttons["cameraSettings"].exists, fixture == "denied")
            XCTAssertFalse(app.buttons["cameraShutter"].exists)
            capture("camera-" + fixture, app: app)
            app.buttons["cameraExisting"].tap()
            XCTAssertTrue(app.buttons["Photo library"].waitForExistence(timeout: 10))
            XCTAssertTrue(app.buttons["Files"].exists)
            app.terminate()
        }
        // Real Simulator hardware discovery, without any fixture override or permission request.
        let app = launch()
        XCTAssertTrue(app.staticTexts["No camera available"].waitForExistence(timeout: 10))
        app.buttons["cameraCancel"].tap()
        XCTAssertTrue(app.buttons["import"].waitForExistence(timeout: 10))
    }
    func testLandscapeCaptureAndStandardActionHeights() {
        let app = launch("live")
        XCUIDevice.shared.orientation = .landscapeLeft
        let rotated = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in app.frame.width > app.frame.height }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [rotated], timeout: 5), .completed)
        // Wait through UIKit’s rotation animation before taking the visual evidence.
        Thread.sleep(forTimeInterval: 1)
        defer { XCUIDevice.shared.orientation = .portrait }
        XCTAssertTrue(app.buttons["cameraShutter"].isHittable)
        XCTAssertTrue(app.buttons["cameraCancel"].isHittable)
        capture("camera-landscape", app: app)
        app.buttons["cameraShutter"].tap()
        XCTAssertTrue(app.buttons["cameraUse"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.buttons["cameraUse"].frame.height, 44, accuracy: 1)
        XCTAssertEqual(app.buttons["cameraRetake"].frame.height, 44, accuracy: 1)
        XCTAssertTrue(app.buttons["cameraUse"].isHittable)
        Thread.sleep(forTimeInterval: 0.5)
        capture("camera-landscape-photo-check", app: app)
        app.buttons["cameraCancel"].tap()
        XCTAssertTrue(app.buttons["import"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["receipt-0"].exists)
    }
    func testCaptureFailureRetryAndLargeText() {
        let app = launch("failure", extra: ["--t05-large-text", "--t05-opaque", "--t05-reduce-motion", "--t05-contrast"])
        XCTAssertTrue(app.buttons["cameraShutter"].isHittable)
        capture("camera-large-text", app: app)
        XCTAssertGreaterThan(app.staticTexts["Keep all four edges in view"].frame.height, 50, "Camera guidance must honor the large-text test environment")
        app.buttons["cameraShutter"].tap()
        XCTAssertTrue(app.buttons["cameraRetry"].waitForExistence(timeout: 10)); app.buttons["cameraRetry"].tap()
        XCTAssertTrue(app.buttons["cameraShutter"].waitForExistence(timeout: 10)); app.buttons["cameraCancel"].tap()
        XCTAssertTrue(app.buttons["import"].waitForExistence(timeout: 10))
    }
}
