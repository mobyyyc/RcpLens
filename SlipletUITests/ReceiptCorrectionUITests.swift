import XCTest

/// Every launch uses fictional fixtures in an isolated preview store on a task-created Simulator.
@MainActor final class ReceiptCorrectionUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }
    private func launch(_ mode: String, light: Bool = true, large: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--t05-synthetic-preview", mode, "--t05-reduce-motion"]
        if light { app.launchArguments.append("--t05-light") }
        if large { app.launchArguments.append("--t05-large-text") }
        app.launch()
        XCTAssertTrue(app.buttons["saveDraft"].waitForExistence(timeout: 30))
        return app
    }
    @discardableResult private func reveal(_ element: XCUIElement, app: XCUIApplication) -> Int {
        // Scroll gestures must start on the form, not on a keyboard covering its lower half.
        if app.keyboards.firstMatch.exists {
            let done = app.buttons["Done"]
            XCTAssertTrue(done.isHittable); done.tap()
            XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        }
        var swipes = 0
        var stationaryGestures = 0
        for _ in 0..<45 {
            if element.exists && element.isHittable && element.frame.midY > app.frame.minY + 125 && element.frame.midY < app.frame.maxY - 145 { return swipes }
            let surface: XCUIElement
            if app.buttons["cancelFocusedCorrection"].exists {
                surface = app.collectionViews["focusedCorrectionForm"]
            } else {
                XCTAssertFalse(app.buttons["sourceDone"].exists)
                XCTAssertFalse(app.buttons["closeExpandedOriginal"].exists)
                surface = app.collectionViews["reviewScreen"]
            }
            guard surface.exists && surface.isHittable else {
                XCTFail("Expected the explicitly identified visible correction form before scrolling"); return swipes
            }
            let targetFrame = element.exists ? element.frame : .null
            let positioned = !targetFrame.isNull && !targetFrame.isEmpty && targetFrame.midY.isFinite
            let downward = positioned && targetFrame.midY < app.frame.minY + 125
            print("P204_DRIVER target=\(targetFrame.isNull ? "notInHierarchy" : element.identifier) frame=\(targetFrame) direction=\(downward ? "towardTop" : "towardBottom")")
            let before = surface.cells.firstMatch.debugDescription
            let start = surface.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: downward ? 0.35 : 0.70))
            let end = surface.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: downward ? 0.70 : 0.35))
            start.press(forDuration: 0.05, thenDragTo: end)
            swipes += 1
            stationaryGestures = surface.cells.firstMatch.debugDescription == before ? stationaryGestures + 1 : 0
            if stationaryGestures >= 3 {
                capture(app, "driver-no-scroll-progress")
                XCTFail("Three gestures produced no observed correction-form scroll progress"); return swipes
            }
        }
        XCTFail("Fictional correction control could not be reached"); return swipes
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    func testFocusedNormalAndLongLightDarkCancelCompareApplyAndFinish() throws {
        for mode in ["correction-normal", "correction-long"] {
            for light in [true, false] {
                let app = launch(mode, light: light)
                capture(app, mode + (light ? "-light-review" : "-dark-review"))
                let check = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'reviewCheck-line-' ")).firstMatch
                XCTAssertTrue(check.exists); check.tap()
                XCTAssertTrue(app.buttons["cancelFocusedCorrection"].waitForExistence(timeout: 5))
                capture(app, mode + (light ? "-light-focused" : "-dark-focused"))
                let focusedPosition = app.descendants(matching: .any)["focusedSourceRaster"].value as? String
                XCTAssertNotNil(focusedPosition)
                app.buttons["expandFocusedOriginal"].tap()
                XCTAssertTrue(app.buttons["closeExpandedOriginal"].waitForExistence(timeout: 5))
                capture(app, mode + (light ? "-light-source" : "-dark-source"))
                app.buttons["expandedZoomReset"].tap(); app.buttons["expandedZoomIn"].tap(); app.buttons["expandedZoomOut"].tap()
                app.buttons["closeExpandedOriginal"].tap()
                XCTAssertTrue(app.buttons["closeExpandedOriginal"].waitForNonExistence(timeout: 5))
                XCTAssertEqual(app.descendants(matching: .any)["focusedSourceRaster"].value as? String, focusedPosition, "Expanded zoom must preserve focused photo context")
                let amount = app.textFields["focusedLineAmount"]
                reveal(amount, app: app); amount.tap(); amount.typeText("99.00")
                app.buttons["cancelFocusedCorrection"].tap()
                XCTAssertTrue(check.waitForExistence(timeout: 5)); check.tap()
                let swipes = reveal(app.textFields["focusedLineAmount"], app: app)
                let value = app.textFields["focusedLineAmount"].value as? String ?? ""
                XCTAssertTrue(value.isEmpty || value == "Missing", "Cancel must preserve the existing receipt")
                app.textFields["focusedLineAmount"].tap(); app.textFields["focusedLineAmount"].typeText("1.00")
                app.buttons["applyFocusedCorrection"].tap()
                XCTAssertTrue(app.buttons["cancelFocusedCorrection"].waitForNonExistence(timeout: 10))
                XCTAssertTrue(app.buttons["saveDraft"].waitForExistence(timeout: 5)); XCTAssertFalse(app.buttons["finishSave"].isEnabled)
                print("P204_SAFE_STEPS " + mode + " focused open=1 editTap=1 type=1 apply=1 editorSwipes=\(swipes)")
                app.buttons["original"].tap(); XCTAssertTrue(app.buttons["sourceDone"].waitForExistence(timeout: 5)); app.buttons["sourceDone"].tap()
                XCTAssertTrue(app.buttons["sourceDone"].waitForNonExistence(timeout: 5))
                XCTAssertTrue(app.descendants(matching: .any)["reviewScreen"].exists)
                let confirmation = app.switches["sourceCheck"]; reveal(confirmation, app: app)
                confirmation.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
                XCTAssertTrue(app.buttons["finishSave"].isEnabled)
                app.buttons["finishSave"].tap(); XCTAssertTrue(app.buttons["edit"].waitForExistence(timeout: 10))
                capture(app, mode + (light ? "-light-detail" : "-dark-detail"))
                app.buttons["back"].tap(); XCTAssertTrue(app.buttons["receipt-0"].waitForExistence(timeout: 10))
                app.buttons["receipt-0"].tap(); XCTAssertTrue(app.buttons["edit"].waitForExistence(timeout: 10))
                app.terminate()
            }
        }
    }
    /// Bounded diagnosis of the previously stalled long/dark full-review return, independently launched.
    func testFocusedLongDarkApplyOriginalReturnAndFinish() {
        let app = launch("correction-long", light: false)
        let check = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'reviewCheck-line-' ")).firstMatch
        check.tap()
        XCTAssertTrue(app.buttons["cancelFocusedCorrection"].waitForExistence(timeout: 5))
        let amount = app.textFields["focusedLineAmount"]; reveal(amount, app: app)
        amount.tap(); amount.typeText("1.00")
        XCTAssertEqual(amount.value as? String, "1.00")
        app.buttons["applyFocusedCorrection"].tap()
        XCTAssertTrue(app.buttons["cancelFocusedCorrection"].waitForNonExistence(timeout: 10))
        XCTAssertTrue(app.buttons["saveDraft"].exists); XCTAssertFalse(app.buttons["finishSave"].isEnabled)
        capture(app, "long-dark-after-apply")
        app.buttons["original"].tap(); XCTAssertTrue(app.buttons["sourceDone"].waitForExistence(timeout: 5))
        app.buttons["sourceDone"].tap(); XCTAssertTrue(app.buttons["sourceDone"].waitForNonExistence(timeout: 5))
        XCTAssertFalse(app.buttons["cancelFocusedCorrection"].exists)
        capture(app, "long-dark-after-original-return")
        let confirmation = app.switches["sourceCheck"]
        reveal(confirmation, app: app)
        capture(app, "long-dark-full-source-check")
        confirmation.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertTrue(app.buttons["finishSave"].isEnabled)
        app.buttons["finishSave"].tap(); XCTAssertTrue(app.buttons["edit"].waitForExistence(timeout: 10))
        capture(app, "long-dark-finished")
        app.terminate()
    }
    func testConventionalLongReviewNavigationCount() {
        let app = launch("correction-long")
        let lastName = app.descendants(matching: .any).matching(NSPredicate(format: "value == 'FICTIONAL ITEM 36' ")).firstMatch
        let swipes = reveal(lastName, app: app)
        let amountID = lastName.identifier.replacingOccurrences(of: "lineName-", with: "lineAmount-")
        let missingAmount = app.textFields[amountID]
        let amountSwipes = reveal(missingAmount, app: app)
        XCTAssertTrue(missingAmount.isHittable)
        capture(app, "long-full-form-last-amount")
        print("P204_SAFE_STEPS correction-long fullForm navigationOnly=true nameSwipes=\(swipes) amountSwipes=\(amountSwipes) totalNavigationSwipes=\(swipes + amountSwipes)")
        XCTAssertFalse(app.buttons["finishSave"].isEnabled)
        app.terminate()
    }
    func testDifficultSourceRowsAddCancelInvalidApplyDraftReopen() throws {
        for light in [true, false] {
            let app = launch("correction-difficult", light: light)
            let check = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Check unassigned amounts' ")).firstMatch
            reveal(check, app: app); check.tap()
            XCTAssertTrue(app.buttons["cancelFocusedCorrection"].waitForExistence(timeout: 5))
            capture(app, light ? "difficult-light-focused" : "difficult-dark-focused")
            let addPurchase = app.buttons["focusedAddPurchase"]; reveal(addPurchase, app: app); addPurchase.tap()
            reveal(app.descendants(matching: .any)["focusedLineName"], app: app)
            app.descendants(matching: .any)["focusedLineName"].tap(); app.descendants(matching: .any)["focusedLineName"].typeText("TEST OMITTED ITEM")
            reveal(app.textFields["focusedLineAmount"], app: app)
            app.textFields["focusedLineAmount"].tap(); app.textFields["focusedLineAmount"].typeText("bad")
            app.buttons["applyFocusedCorrection"].tap()
            XCTAssertTrue(app.descendants(matching: .any)["focusedError"].exists, "Malformed new values must not Apply")
            app.buttons["cancelFocusedCorrection"].tap(); XCTAssertFalse(app.buttons["finishSave"].isEnabled)
            reveal(check, app: app); check.tap(); reveal(app.buttons["focusedAddPurchase"], app: app); app.buttons["focusedAddPurchase"].tap()
            let name = app.descendants(matching: .any)["focusedLineName"]; reveal(name, app: app); name.tap(); name.typeText("TEST OMITTED ITEM")
            let quantity = app.textFields["focusedQuantity"]; reveal(quantity, app: app); quantity.tap(); quantity.typeText("2")
            let amount = app.textFields["focusedLineAmount"]; reveal(amount, app: app); amount.tap(); amount.typeText("2.00")
            XCTAssertEqual(name.value as? String, "TEST OMITTED ITEM")
            XCTAssertEqual(amount.value as? String, "2.00")
            XCTAssertEqual(quantity.value as? String, "2", "Moving description → quantity → amount must keep every edit in its intended field")
            app.buttons["applyFocusedCorrection"].tap()
            XCTAssertFalse(app.buttons["finishSave"].isEnabled, "A focused check must never approve the whole receipt")
            app.buttons["saveDraft"].tap(); XCTAssertTrue(app.buttons["edit"].waitForExistence(timeout: 10))
            app.buttons["splitOpen"].tap()
            XCTAssertTrue(app.staticTexts["Receipt needs review. Finish its corrections first."].waitForExistence(timeout: 5))
            XCTAssertFalse(app.buttons["splitFinalize"].isEnabled, "Drafts cannot finalize a split")
            app.buttons["splitDone"].tap()
            XCTAssertTrue(app.buttons["splitDone"].waitForNonExistence(timeout: 5))
            XCTAssertTrue(app.buttons["edit"].isEnabled)
            // Restart and reopen the persisted draft; do not rely on an immediate post-sheet tap.
            app.terminate()
            app.launchArguments = ["--t05-synthetic-preview", "resume"] + (light ? ["--t05-light"] : [])
            app.launch()
            XCTAssertTrue(app.buttons["receipt-0"].waitForExistence(timeout: 15)); app.buttons["receipt-0"].tap()
            XCTAssertTrue(app.buttons["edit"].waitForExistence(timeout: 10))
            app.buttons["edit"].tap(); XCTAssertTrue(app.buttons["saveDraft"].waitForExistence(timeout: 10))
            let checked = app.descendants(matching: .any)["checkedGuidance"]
            capture(app, light ? "difficult-light-reopened" : "difficult-dark-reopened")
            reveal(checked, app: app); XCTAssertTrue(checked.exists)
            XCTAssertFalse(app.buttons["finishSave"].isEnabled)
            capture(app, light ? "difficult-light-reopened" : "difficult-dark-reopened")
            app.terminate()
        }
    }
    func testSourceGroupHighlightNavigationMissingPositionAndExplicitGroupConfirmation() {
        let app = launch("correction-source", light: false)
        let check = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Check unassigned text' ")).firstMatch
        reveal(check, app: app); check.tap()
        XCTAssertTrue(app.buttons["cancelFocusedCorrection"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["applyFocusedCorrection"].isEnabled)
        capture(app, "group-first-highlight")
        reveal(app.buttons["Next row"], app: app); app.buttons["Next row"].tap()
        capture(app, "group-last-no-coordinate")
        XCTAssertTrue(app.staticTexts["No position is available for this check. Compare the full original."].exists)
        XCTAssertFalse(app.buttons["Next row"].isEnabled)
        let confirmation = app.switches["focusedGroupChecked"]; reveal(confirmation, app: app)
        confirmation.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertEqual(confirmation.value as? String, "1")
        XCTAssertTrue(app.buttons["applyFocusedCorrection"].isEnabled)
        capture(app, "group-dark-confirmed-switch")
        app.buttons["cancelFocusedCorrection"].tap(); reveal(check, app: app); check.tap()
        XCTAssertTrue(app.buttons["cancelFocusedCorrection"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["applyFocusedCorrection"].isEnabled, "Cancel must discard the grouped confirmation")
        app.buttons["cancelFocusedCorrection"].tap(); app.terminate()
    }
    func testFocusedLargeTextStructureAndSourceAccess() throws {
        let app = launch("correction-long", large: true)
        let check = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'reviewCheck-line-' ")).firstMatch
        reveal(check, app: app); check.tap()
        XCTAssertTrue(app.buttons["cancelFocusedCorrection"].waitForExistence(timeout: 5))
        try app.performAccessibilityAudit(for: [.elementDetection, .hitRegion, .sufficientElementDescription])
        capture(app, "long-accessibility-focused")
        reveal(app.textFields["focusedLineAmount"], app: app)
        try app.performAccessibilityAudit(for: [.elementDetection, .hitRegion, .sufficientElementDescription])
        capture(app, "long-accessibility-editor")
        reveal(app.buttons["expandFocusedOriginal"], app: app); app.buttons["expandFocusedOriginal"].tap()
        XCTAssertTrue(app.buttons["closeExpandedOriginal"].waitForExistence(timeout: 5)); app.buttons["closeExpandedOriginal"].tap()
        app.buttons["cancelFocusedCorrection"].tap(); app.terminate()
    }
}
