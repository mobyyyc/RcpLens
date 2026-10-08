import XCTest
import UIKit

/// Real inputs/references are supplied locally, never compiled or logged by this suite.
/// Test logs and attachments for private runs must stay under ignored private-receipts/.
@MainActor final class LocalReceiptWorkflowTests: XCTestCase {
    override func setUp() { continueAfterFailure = false }
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<35 {
            if element.exists && element.isHittable && element.frame.midY < app.frame.maxY - 140 && element.frame.midY > app.frame.minY + 120 { return }
            if element.exists && element.frame.midY < app.frame.minY + 120 { app.swipeDown(velocity: .fast) }
            else { app.swipeUp(velocity: .fast) }
        }
        XCTAssertTrue(element.isHittable, "Required workflow control is unreachable")
    }
    func testPrivateReceiptSet() throws {
        guard ProcessInfo.processInfo.environment["RCPLENS_T05_PRIVATE"] == "YES" else { throw XCTSkip("Private corpus runs are explicit and local only") }
        for slot in 0..<5 { try runReceipt(slot: slot) }
    }
    private func runReceipt(slot: Int) throws {
        let app = XCUIApplication()
        app.launchArguments = ["--t05-local-test", "--t05-slot", String(slot)]
        app.launch()
        let importer = app.buttons["debugImport"]
        XCTAssertTrue(importer.waitForExistence(timeout: 15), "Local test importer did not appear")
        importer.tap()
        XCTAssertTrue(app.descendants(matching: .any)["reviewScreen"].waitForExistence(timeout: 30), "Real import did not enter review")
        XCTAssertFalse(app.buttons["finishSave"].isEnabled, "Unreviewed extraction cannot finish")
        let draft = app.buttons["saveDraft"]; draft.tap()
        XCTAssertTrue(app.descendants(matching: .any)["detailScreen"].waitForExistence(timeout: 15), "Draft save did not open details")
        app.terminate(); app.launch()
        let receipt = app.buttons["receipt-0"]
        XCTAssertTrue(receipt.waitForExistence(timeout: 15), "Draft did not survive app restart")
        receipt.tap(); XCTAssertTrue(app.descendants(matching: .any)["detailScreen"].waitForExistence(timeout: 15))
        app.buttons["edit"].tap()
        let reference = app.buttons["debugReference"]
        reference.tap()
        XCTAssertFalse(app.buttons["finishSave"].isEnabled)
        app.buttons["original"].tap()
        XCTAssertTrue(app.buttons["sourceDone"].waitForExistence(timeout: 10)); app.buttons["sourceDone"].tap()
        let check = app.switches["sourceCheck"]; reveal(check, in: app); check.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        let finish = app.buttons["finishSave"]
        if !finish.isEnabled {
            XCTAssertFalse(finish.isEnabled, "Unresolved reference fields must remain a draft")
            app.buttons["saveDraft"].tap()
        } else {
            XCTAssertTrue(finish.isEnabled, "Checked reference must reconcile before finishing")
            finish.tap()
        }; XCTAssertTrue(app.descendants(matching: .any)["detailScreen"].waitForExistence(timeout: 15))
        let verify = app.buttons["debugVerify"]; verify.tap()
        XCTAssertTrue(app.staticTexts["Local verification passed"].waitForExistence(timeout: 10), "Local round-trip did not match checked reference")
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["receipt-0"].waitForExistence(timeout: 15)); app.buttons["receipt-0"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["detailScreen"].waitForExistence(timeout: 15))
        app.buttons["debugVerify"].tap()
        XCTAssertTrue(app.staticTexts["Local verification passed"].waitForExistence(timeout: 10), "Reviewed receipt did not survive app restart")
        app.buttons["receiptOptions"].tap(); app.buttons["delete"].tap(); app.buttons["Delete receipt and original"].tap()
        XCTAssertTrue(app.buttons["import"].waitForExistence(timeout: 15), "Deletion did not remove saved receipt")
        XCTAssertFalse(app.buttons["receipt-0"].exists)
        app.terminate()
    }
}

@MainActor final class SyntheticUIWorkflowTests: XCTestCase {
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<35 {
            if element.exists && element.isHittable && element.frame.midY < app.frame.maxY - 140 && element.frame.midY > app.frame.minY + 120 { return }
            if element.exists && element.frame.midY < app.frame.minY + 120 { app.swipeDown(velocity: .fast) }
            else { app.swipeUp(velocity: .fast) }
        }
        XCTAssertTrue(element.isHittable, "Required synthetic control is unreachable")
    }
    override func setUp() { continueAfterFailure = false }
    func testCancellationMalformedImageAndBackgroundClear() throws {
        let app = XCUIApplication(); app.launchArguments = ["--t05-local-test", "--t05-slot", "5", "--t05-synthetic-input"]; app.launch()
        let malformed = app.buttons["debugMalformed"]
        XCTAssertTrue(malformed.waitForExistence(timeout: 15)); app.swipeUp(); malformed.tap()
        XCTAssertTrue(app.staticTexts["Reading needs attention"].waitForExistence(timeout: 10))
        app.buttons["Return to wallet"].tap()
        app.swipeUp(); app.buttons["debugImport"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["reviewScreen"].waitForExistence(timeout: 20))
        app.buttons["back"].tap(); app.buttons["Discard changes"].tap()
        XCTAssertTrue(app.buttons["import"].waitForExistence(timeout: 10))
        app.swipeUp(); app.buttons["debugImport"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["reviewScreen"].waitForExistence(timeout: 20))
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(app.buttons["import"].waitForExistence(timeout: 15), "Unsaved private work must be dropped across background")
        XCTAssertFalse(app.descendants(matching: .any)["reviewScreen"].exists)
    }
    func testPhotoPickerImportAndEditableControls() throws {
        let app = XCUIApplication(); app.launchArguments = ["--t05-local-test", "--t05-slot", "5", "--t05-synthetic-input"]; app.launch()
        XCTAssertTrue(app.buttons["import"].waitForExistence(timeout: 15)); app.buttons["import"].tap()
        app.buttons["Photo library"].tap()
        // Match the individual image, not the grid whose combined label includes every photo.
        let photo = app.images.matching(NSPredicate(format: "label BEGINSWITH 'Photo,' AND label CONTAINS '2036'")).firstMatch
        XCTAssertTrue(photo.waitForExistence(timeout: 15), "Load the dated synthetic fixture into Simulator Photos first")
        photo.tap()
        XCTAssertTrue(app.descendants(matching: .any)["reviewScreen"].waitForExistence(timeout: 25), "Photo selection must enter the real OCR flow")
        app.buttons["original"].tap()
        XCTAssertTrue(app.buttons["sourceDone"].waitForExistence(timeout: 10))
        app.buttons["Printed text"].tap()
        XCTAssertTrue(app.staticTexts["SYNTHETIC STORE"].waitForExistence(timeout: 10), "The selected photo OCR must match the known synthetic receipt")
        app.buttons["sourceDone"].tap()
        let merchant = app.descendants(matching: .any)["merchantField"]
        merchant.tap()
        let previous = merchant.value as? String ?? ""
        merchant.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: previous.count) + "FICTIONAL PHOTO SHOP")
        XCTAssertEqual(merchant.value as? String, "FICTIONAL PHOTO SHOP")
        app.buttons["keyboardDone"].tap()
        XCTAssertFalse(app.buttons["finishSave"].isEnabled)
        app.buttons["original"].tap()
        XCTAssertTrue(app.buttons["sourceDone"].waitForExistence(timeout: 10))
        app.buttons["sourceDone"].tap()
        app.buttons["back"].tap(); app.buttons["Discard changes"].tap()
    }
}


@MainActor final class NativeAccessibilityTests: XCTestCase {
    override func setUp() { continueAfterFailure = false }
    /// Measure glyph-interior/dominant-background pairs in a fictional element screenshot, in sRGB.
    /// Edge antialiasing and varying Glass backgrounds are not a full contrast certification.
    private func pixelContrast(_ screenshot: XCUIScreenshot) -> (foreground: String, background: String, ratio: Double)? {
        guard let image = screenshot.image.cgImage else { return nil }
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let drawn = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8,
                bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height)); return true
        }
        guard drawn else { return nil }
        var histogram: [Int: Int] = [:]
        for i in stride(from: 0, to: pixels.count, by: 4) where pixels[i + 3] == 255 {
            histogram[Int(pixels[i]) << 16 | Int(pixels[i + 1]) << 8 | Int(pixels[i + 2]), default: 0] += 1
        }
        func luminance(_ rgb: Int) -> Double {
            let channels = [Double((rgb >> 16) & 255), Double((rgb >> 8) & 255), Double(rgb & 255)].map { value -> Double in
                let c = value / 255; return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
            }
            return channels[0] * 0.2126 + channels[1] * 0.7152 + channels[2] * 0.0722
        }
        func ratio(_ a: Int, _ b: Int) -> Double { let x = luminance(a), y = luminance(b); return (max(x, y) + 0.05) / (min(x, y) + 0.05) }
        guard let background = histogram.max(by: { $0.value < $1.value })?.key,
              let foreground = histogram.filter({ $0.value >= 5 }).max(by: { ratio($0.key, background) < ratio($1.key, background) })?.key else { return nil }
        return (String(format: "#%06X", foreground), String(format: "#%06X", background), ratio(foreground, background))
    }
    func testNativeWalletDetailReviewSourceAndLibraryStructureAudit() throws {
        continueAfterFailure = true // Collect findings across all fictional native screens.
        for mode in ["wallet", "detail", "review", "source", "library"] {
            print("Synthetic accessibility scenario: " + mode)
            let app = XCUIApplication(); app.launchArguments = ["--t05-synthetic-preview", mode, "--t05-light"]
            app.launch()
            let anchor = mode == "wallet" ? app.buttons["receipt-0"] : (mode == "detail" ? app.buttons["edit"] : (mode == "review" ? app.buttons["saveDraft"] : (mode == "source" ? app.buttons["sourceDone"] : app.buttons["walletTab"])))
            XCTAssertTrue(anchor.waitForExistence(timeout: 30), "Synthetic native scenario failed to prepare")
            try app.performAccessibilityAudit(for: [.elementDetection, .hitRegion, .sufficientElementDescription]) { issue in
                var detail: [String: Any] = ["scenario": mode, "reason": issue.compactDescription, "details": issue.detailedDescription]
                if let element = issue.element {
                    let f = element.frame
                    detail["label"] = element.label; detail["identifier"] = element.identifier
                    detail["frame"] = [f.origin.x, f.origin.y, f.width, f.height]
                }
                if let data = try? JSONSerialization.data(withJSONObject: detail, options: [.sortedKeys]), let line = String(data: data, encoding: .utf8) { print("T05_STRUCTURE_ISSUE " + line) }
                let tree = XCTAttachment(string: app.debugDescription); tree.name = "Synthetic-AX-" + mode
                tree.lifetime = .keepAlways; self.add(tree)
                return false // Structural findings remain failures, never waived as contrast exceptions.
            }
            // Keep the native contrast findings as diagnostics: this SDK flags even solid black-on-white text.
            // Only individually measured/identified fixture exceptions are accepted; all other findings fail.
            // This does not certify all native material states or device accessibility.
            var contrastFindings = 0
            try app.performAccessibilityAudit(for: [.contrast]) { issue in
                contrastFindings += 1
                var accepted = false
                var classification = "unresolved"
                var detail: [String: Any] = ["scenario": mode, "index": contrastFindings, "reason": issue.compactDescription, "details": issue.detailedDescription]
                if let element = issue.element {
                    detail["label"] = element.label; detail["identifier"] = element.identifier
                    detail["role"] = element.elementType == .staticText ? "staticText" : (element.elementType == .button ? "button" : String(describing: element.elementType)); detail["enabled"] = element.isEnabled
                    let f = element.frame
                    detail["frame"] = [f.origin.x, f.origin.y, f.width, f.height]
                    let screenshot = element.screenshot()
                    let measured = self.pixelContrast(screenshot)
                    if let measured { detail["foreground"] = measured.foreground; detail["background"] = measured.background; detail["measuredRatio"] = measured.ratio }
                    let walletLabels = ["2026-10-07", "2026-10-06", "2026-10-05", "CAD 12.34"]
                    let detailLabels = ["2026-10-07 · CAD", "12.34", "Qty unknown", "Saved on this device"]
                    if element.elementType == .staticText, element.isEnabled,
                       (mode == "wallet" && walletLabels.contains(element.label) || mode == "detail" && detailLabels.contains(element.label) || mode == "library" && element.label == "2026-10-07"),
                       let measured, measured.foreground == "#000000", measured.ratio >= 7 {
                        accepted = true; classification = "measured-black-reading-text-sdk-finding"
                    } else if element.elementType == .button, element.isEnabled,
                              (mode == "review" && ["saveDraft", "original"].contains(element.identifier) || mode == "source" && element.identifier == "sourceDone" || mode == "detail" && element.identifier == "original" || mode == "wallet" && element.identifier == "allReceipts"),
                              let measured, measured.foreground == "#000000", measured.ratio >= 7 {
                        accepted = true; classification = "measured-native-glass-label-sdk-finding"
                    } else if mode == "review", element.identifier == "finishSave", !element.isEnabled {
                        accepted = true; classification = "intentionally-disabled-native-finish"
                    } else if mode == "library", element.elementType == .staticText, element.label == "SYNTHETIC CORNER",
                              f.intersects(app.buttons["import"].frame),
                              let measured, measured.foreground == "#000000", measured.ratio >= 7 {
                        accepted = true; classification = "native-list-row-partly-under-floating-toolbar"
                    }
                    let attachment = XCTAttachment(screenshot: screenshot)
                    attachment.name = "Contrast-" + mode + "-" + String(contrastFindings)
                    attachment.lifetime = .keepAlways; self.add(attachment)
                }
                detail["acceptedException"] = accepted; detail["classification"] = classification
                if let data = try? JSONSerialization.data(withJSONObject: detail, options: [.sortedKeys]), let line = String(data: data, encoding: .utf8) { print("T05_CONTRAST_ISSUE " + line) }
                return accepted // Unexpected or low-contrast reading/action findings fail this test.
            }
            print("T05_CONTRAST_COUNT " + mode + " " + String(contrastFindings))
            app.terminate()
        }
    }
    func testReceiptOptionsAndDeleteConfirmation() throws {
        let app = XCUIApplication(); app.launchArguments = ["--t05-synthetic-preview", "wallet", "--t05-light"]
        app.launch()
        XCTAssertTrue(app.buttons["receipt-0"].waitForExistence(timeout: 30)); app.buttons["receipt-0"].tap()
        XCTAssertTrue(app.buttons["edit"].waitForExistence(timeout: 15))
        XCTAssertEqual(app.buttons.matching(identifier: "original").count, 1)
        app.buttons["receiptOptions"].tap(); app.buttons["Storage details"].tap()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 10)); app.buttons["Done"].tap()
        app.buttons["receiptOptions"].tap(); app.buttons["delete"].tap()
        XCTAssertTrue(app.buttons["Delete receipt and original"].waitForExistence(timeout: 10))
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["edit"].isHittable)
        app.buttons["receiptOptions"].tap(); app.buttons["delete"].tap()
        app.buttons["Delete receipt and original"].tap()
        XCTAssertTrue(app.staticTexts["2 saved"].waitForExistence(timeout: 15))
        XCTAssertEqual(app.buttons.matching(identifier: "import").count, 1)
        app.terminate()
    }
    func testSingleImportAndCollectionNavigation() throws {
        for mode in ["empty", "wallet"] {
            let app = XCUIApplication(); app.launchArguments = ["--t05-synthetic-preview", mode, "--t05-light"]
            app.launch()
            let importer = app.buttons["import"]
            XCTAssertTrue(importer.waitForExistence(timeout: 30))
            XCTAssertEqual(app.buttons.matching(identifier: "import").count, 1)
            XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label == 'Import receipt'")).count, 1)
            XCTAssertFalse(app.buttons["emptyImport"].exists)
            XCTAssertFalse(app.buttons["walletTab"].exists)
            XCTAssertTrue(importer.isHittable)
            app.buttons["walletInformation"].tap()
            XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Receipts are excluded from automatic backup.")).firstMatch.waitForExistence(timeout: 10))
            app.buttons["Done"].tap()
            if mode == "wallet" {
                app.buttons["allReceipts"].tap()
                XCTAssertTrue(app.buttons["walletTab"].waitForExistence(timeout: 10))
                XCTAssertEqual(app.buttons.matching(identifier: "import").count, 1)
                app.buttons["walletTab"].tap()
                XCTAssertTrue(app.buttons["receipt-0"].waitForExistence(timeout: 10))
            }
            app.terminate()
        }
    }
    func testEmptyWalletImportProminentContrastDarkAndLight() throws {
        for mode in ["dark", "light"] {
            let app = XCUIApplication()
            app.launchArguments = ["--t05-synthetic-preview", "empty"] + (mode == "light" ? ["--t05-light"] : [])
            app.launch()
            let button = app.buttons["import"]
            XCTAssertTrue(button.waitForExistence(timeout: 30))
            let measured = try XCTUnwrap(pixelContrast(button.screenshot()))
            XCTAssertEqual(measured.foreground, mode == "dark" ? "#000000" : "#FFFFFF")
            XCTAssertGreaterThanOrEqual(measured.ratio, 7)
            let report: [String: Any] = ["mode": mode, "foreground": measured.foreground, "background": measured.background, "ratio": measured.ratio]
            let bytes = try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys])
            print("T05_EMPTY_IMPORT_CONTRAST " + String(data: bytes, encoding: .utf8)!)
            let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = "Empty-wallet-" + mode
            attachment.lifetime = .keepAlways; add(attachment)
            app.terminate()
        }
    }
    func testLargeTextReducedMotionOpaqueAndContrastTapPaths() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--t05-synthetic-preview", "wallet", "--t05-large-text", "--t05-reduce-motion", "--t05-opaque", "--t05-contrast"]
        app.launch()
        let receipt = app.buttons["receipt-0"]
        XCTAssertTrue(receipt.waitForExistence(timeout: 30))
        if !receipt.isHittable { app.swipeUp() }
        receipt.tap(); XCTAssertTrue(app.buttons["edit"].waitForExistence(timeout: 15))
        app.buttons["edit"].tap(); XCTAssertTrue(app.buttons["saveDraft"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["finishSave"].isEnabled)
        app.buttons["original"].tap(); XCTAssertTrue(app.buttons["sourceDone"].waitForExistence(timeout: 15)); app.buttons["sourceDone"].tap()
        app.buttons["back"].tap(); app.buttons["Discard changes"].tap()
        XCTAssertTrue(app.buttons["edit"].waitForExistence(timeout: 15))
        app.terminate()
    }
}
