import XCTest
@testable import Sliplet

final class FoundationTests: XCTestCase {
    func testVisionRecognizesImportedSyntheticPNG() async throws {
        let data = try SyntheticFixture.imageData()
        let result = try await VisionTextRecognizer().recognize(imageData: data)
        let text = result.lines.joined(separator: " ").uppercased()
        XCTAssertTrue(text.contains("SYNTHETIC"))
        XCTAssertTrue(text.contains("TOTAL"))
        XCTAssertTrue(text.contains("12.34"))
    }

    func testVisionRejectsMalformedImage() async {
        do {
            _ = try await VisionTextRecognizer().recognize(imageData: Data([0, 1, 2, 3]))
            XCTFail("Malformed image must throw")
        } catch {
            // Expected: invalid bytes must not become a successful empty receipt.
        }
    }

    @MainActor
    func testActualLocalModelAndDiagnosticReport() async throws {
        let diagnostics = SyntheticDiagnostics()
        await diagnostics.run()
        XCTAssertEqual(diagnostics.report.vision, "passed")
        XCTAssertFalse(diagnostics.reportWriteFailed)
        if diagnostics.report.modelAvailability == "available" {
            XCTAssertEqual(diagnostics.report.generation, "passed")
            XCTAssertGreaterThan(diagnostics.report.responseCharacterCount, 0)
        } else {
            XCTAssertTrue(["deviceNotEligible", "appleIntelligenceNotEnabled", "modelNotReady", "unknownUnavailableReason"].contains(diagnostics.report.modelAvailability))
            XCTAssertEqual(diagnostics.report.generation, "unavailable")
            throw XCTSkip("Actual local model unavailable: \(diagnostics.report.modelAvailability)")
        }
    }
}
