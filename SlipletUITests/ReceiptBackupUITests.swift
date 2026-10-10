import XCTest

/// Only the disposable Simulator and existing fictional preview store are used.
@MainActor final class ReceiptBackupUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }
    private func launch(light: Bool = true, large: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--t05-synthetic-preview", "wallet", "--t05-reduce-motion", "--p205-backup-fixture"]
        if light { app.launchArguments.append("--t05-light") }
        if large { app.launchArguments.append("--t05-large-text") }
        app.launch()
        XCTAssertTrue(app.buttons["walletSettings"].waitForExistence(timeout: 30)); app.buttons["walletSettings"].tap()
        XCTAssertTrue(app.buttons["exportBackup"].waitForExistence(timeout: 10)); return app
    }
    private func type(_ field: XCUIElement, _ value: String) { XCTAssertTrue(field.waitForExistence(timeout: 10)); field.tap(); field.typeText(value) }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot)
    }
    func testPasswordConfirmationExportPickerCancelAndUsableWallet() {
        let app = launch(); app.buttons["exportBackup"].tap()
        let choose = app.buttons["chooseBackupDestination"]
        XCTAssertTrue(choose.waitForExistence(timeout: 5)); XCTAssertFalse(choose.isEnabled)
        type(app.secureTextFields["backupPassword"], "fictional-backup-password")
        XCTAssertFalse(choose.isEnabled)
        type(app.secureTextFields["backupPasswordConfirmation"], "fictional-backup-password")
        XCTAssertTrue(choose.isEnabled)
        capture(app, "fictional-backup-export-form")
        choose.tap()
        XCTAssertTrue(app.buttons["DOCPicker.actionButton"].waitForExistence(timeout: 30))
        capture(app, "fictional-encrypted-export-files-picker")
        // The system's Cancel host is not exposed as a tappable AX button on this runtime.
        // Exercise the native sheet-dismiss gesture, which revokes the same export session.
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.085))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85))
        start.press(forDuration: 0.1, thenDragTo: end)
        XCTAssertTrue(app.staticTexts["backupMessage"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["backupMessage"].label.contains("cancelled"))
        let close = app.buttons["closeBackup"]; XCTAssertTrue(close.isEnabled); close.tap()
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["import"].waitForExistence(timeout: 10)); XCTAssertTrue(app.buttons["import"].isEnabled)
        app.terminate()
    }
    func testExplicitRestoreFilesPickerCancelAndDarkForm() {
        let app = launch(light: false); app.buttons["restoreBackup"].tap()
        let choose = app.buttons["chooseBackupFile"]
        XCTAssertTrue(choose.waitForExistence(timeout: 5)); XCTAssertFalse(choose.isEnabled)
        type(app.secureTextFields["backupPassword"], "fictional-backup-password")
        XCTAssertTrue(choose.isEnabled); capture(app, "fictional-backup-restore-dark")
        choose.tap()
        let cancel = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Cancel")).firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["confirmBackupRestore"].exists)
        capture(app, "fictional-explicit-restore-files-picker")
        cancel.tap()
        XCTAssertTrue(app.buttons["closeBackup"].waitForExistence(timeout: 5)); app.buttons["closeBackup"].tap()
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["import"].waitForExistence(timeout: 10)); XCTAssertTrue(app.buttons["import"].isEnabled)
        app.terminate()
    }
    func testNativeMergePreviewConfirmationAndWalletRemainUsable() {
        let app = launch(); app.buttons["restoreBackup"].tap()
        let fixture = app.buttons["useFictionalBackup"]
        XCTAssertTrue(fixture.waitForExistence(timeout: 10)); fixture.tap()
        let confirm = app.buttons["confirmBackupRestore"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 30)); XCTAssertTrue(confirm.isEnabled)
        XCTAssertTrue(app.staticTexts["Existing receipts skipped"].exists)
        XCTAssertTrue(app.staticTexts["Differing versions skipped"].exists)
        XCTAssertTrue(confirm.label.contains("1")); capture(app, "fictional-merge-preview")
        confirm.tap()
        let message = app.staticTexts["backupMessage"]
        XCTAssertTrue(message.waitForExistence(timeout: 20))
        XCTAssertTrue(message.label.contains("Restored 1 receipt")); XCTAssertTrue(message.label.contains("Kept 1"))
        let close = app.buttons["closeBackup"]; XCTAssertTrue(close.isEnabled); capture(app, "fictional-merge-complete")
        close.tap(); app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["import"].waitForExistence(timeout: 10)); XCTAssertTrue(app.buttons["import"].isEnabled)
        app.terminate()
        app.launchArguments = ["--t05-synthetic-preview", "resume", "--t05-light", "--t05-reduce-motion"]
        app.launch()
        XCTAssertTrue(app.buttons["receipt-3"].waitForExistence(timeout: 30))
        app.terminate()
    }
    func testCancelPreparedRestoreKeepsWalletUsable() {
        let app = launch(); app.buttons["restoreBackup"].tap()
        let fixture = app.buttons["useFictionalBackup"]
        XCTAssertTrue(fixture.waitForExistence(timeout: 10)); fixture.tap()
        XCTAssertTrue(app.buttons["confirmBackupRestore"].waitForExistence(timeout: 30))
        app.buttons["closeBackup"].tap(); app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["import"].waitForExistence(timeout: 10)); XCTAssertTrue(app.buttons["import"].isEnabled)
        XCTAssertFalse(app.buttons["receipt-3"].exists); app.terminate()
    }
    func testNativeLocalFileSaveAndExplicitSelectionProducesDuplicatePreview() {
        let app = launch(); app.buttons["exportBackup"].tap()
        type(app.secureTextFields["backupPassword"], "fictional-backup-password")
        type(app.secureTextFields["backupPasswordConfirmation"], "fictional-backup-password")
        app.buttons["chooseBackupDestination"].tap()
        let save = app.buttons["DOCPicker.actionButton"]
        XCTAssertTrue(save.waitForExistence(timeout: 30))
        XCTAssertTrue(app.staticTexts["On My iPhone"].exists)
        XCTAssertTrue(save.isEnabled)
        let name = "P205-fictional-" + String(UUID().uuidString.prefix(8))
        let filename = app.textFields["DOCPicker.filenameTextField"]
        XCTAssertTrue(filename.exists)
        let old = filename.value as? String ?? "Sliplet-backup"
        filename.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        filename.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: old.count) + name)
        capture(app, "fictional-local-export-destination")
        save.tap()
        let message = app.staticTexts["backupMessage"]
        XCTAssertTrue(message.waitForExistence(timeout: 15)); XCTAssertTrue(message.label.contains("Encrypted backup saved"))
        app.buttons["closeBackup"].tap()
        XCTAssertTrue(app.buttons["closeBackup"].waitForNonExistence(timeout: 10))
        XCTAssertTrue(app.buttons["restoreBackup"].isHittable); app.buttons["restoreBackup"].tap()
        XCTAssertTrue(app.buttons["chooseBackupFile"].waitForExistence(timeout: 10))
        type(app.secureTextFields["backupPassword"], "fictional-backup-password")
        app.buttons["chooseBackupFile"].tap()
        // New exports are not automatically in the system's Recents list. Browse the explicit local location.
        XCTAssertTrue(app.buttons["Browse"].waitForExistence(timeout: 10)); app.buttons["Browse"].tap()
        let file = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", name)).firstMatch
        if !file.waitForExistence(timeout: 3) {
            let location = app.staticTexts["On My iPhone"]
            XCTAssertTrue(location.waitForExistence(timeout: 10)); location.tap()
        }
        XCTAssertTrue(file.waitForExistence(timeout: 15)); capture(app, "fictional-explicit-local-backup-selection")
        file.tap()
        XCTAssertTrue(app.staticTexts["Restore preview"].waitForExistence(timeout: 30))
        let add = app.buttons["confirmBackupRestore"]
        XCTAssertTrue(add.exists); XCTAssertFalse(add.isEnabled); XCTAssertTrue(add.label.contains("0"))
        capture(app, "fictional-files-roundtrip-duplicate-preview")
        app.buttons["closeBackup"].tap(); app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["import"].waitForExistence(timeout: 10)); XCTAssertTrue(app.buttons["import"].isEnabled)
        app.terminate()
    }
    func testSwipeDismissPreparedRestoreClearsStateBeforeExportReopens() {
        let app = launch(); app.buttons["restoreBackup"].tap()
        let fixture = app.buttons["useFictionalBackup"]
        XCTAssertTrue(fixture.waitForExistence(timeout: 10)); fixture.tap()
        XCTAssertTrue(app.buttons["confirmBackupRestore"].waitForExistence(timeout: 30))
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8))
        start.press(forDuration: 0.1, thenDragTo: end)
        XCTAssertTrue(app.buttons["exportBackup"].waitForExistence(timeout: 10)); app.buttons["exportBackup"].tap()
        XCTAssertTrue(app.secureTextFields["backupPasswordConfirmation"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["confirmBackupRestore"].exists)
        XCTAssertFalse(app.buttons["chooseBackupDestination"].isEnabled)
        app.buttons["closeBackup"].tap(); app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["import"].isEnabled); app.terminate()
    }
    func testBackgroundWhileFilesPickerOpenRevokesOldSessionAndClearsPassword() {
        let app = launch(); app.buttons["restoreBackup"].tap()
        type(app.secureTextFields["backupPassword"], "fictional-backup-password")
        app.buttons["chooseBackupFile"].tap()
        XCTAssertTrue(app.buttons["Browse"].waitForExistence(timeout: 10))
        XCUIDevice.shared.press(.home); app.activate()
        XCTAssertTrue(app.buttons["walletSettings"].waitForExistence(timeout: 20))
        XCTAssertFalse(app.buttons["confirmBackupRestore"].exists)
        app.buttons["walletSettings"].tap(); app.buttons["restoreBackup"].tap()
        XCTAssertTrue(app.buttons["chooseBackupFile"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["chooseBackupFile"].isEnabled)
        app.buttons["closeBackup"].tap(); app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["import"].isEnabled); app.terminate()
    }
    func testBackgroundDiscardsPasswordAndReturnsToUsableWallet() {
        let app = launch(); app.buttons["exportBackup"].tap()
        type(app.secureTextFields["backupPassword"], "fictional-password-to-clear")
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(app.buttons["walletSettings"].waitForExistence(timeout: 20))
        app.buttons["walletSettings"].tap(); app.buttons["exportBackup"].tap()
        let field = app.secureTextFields["backupPassword"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["chooseBackupDestination"].isEnabled)
        capture(app, "fictional-backup-after-background-password-cleared")
        app.buttons["closeBackup"].tap(); app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["import"].isEnabled); app.terminate()
    }
}
