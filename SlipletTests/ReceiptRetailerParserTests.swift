import XCTest
@testable import Sliplet

final class ReceiptRetailerParserTests: XCTestCase {
    private func source(_ text: String) -> [ReceiptOCRLine] {
        text.split(separator: "\n").map { .init(id: UUID(), text: String($0), engineConfidence: nil) }
    }
    private func box(_ text: String, x: Double, y: Double, width: Double = 0.3) throws -> ReceiptOCRLine {
        .init(id: UUID(), text: text, engineConfidence: nil,
              boundingBox: try ReceiptOCRBox(x: x, y: y, width: width, height: 0.02))
    }
    func testCanonicalHeadersAndFictionalIdentities() {
        for (header, expected) in [("FICTIONAL OWNER'S NOFRILLS", "FICTIONAL OWNER'S NOFRILLS"),
                                   ("OWNER'S NOFRILLS", "NOFRILLS"), ("COSTCO WHOLESALE", "COSTCO"),
                                   ("T & T SUPERMARKET", "T&T SUPERMARKET"), ("DEMO 12 · NO FRILLS", "DEMO 12 · NO FRILLS")] {
            XCTAssertEqual(ReceiptParser.parse(source(header + "\nBREAD 4.00")).merchant, expected)
        }
    }
    func testRetailerProductNamesArePurchasesAndNotHeaders() {
        let p = ReceiptParser.parse(source("COSTCO\nCOSTCO BAG 1.00\nTOTAL 1.00"))
        XCTAssertEqual(p.lines.map(\.description), ["COSTCO BAG"])
        XCTAssertNil(ReceiptParser.parse(source("MART\nCOSTCO BAG 1.00\nTOTAL 1.00")).merchant)
    }
    func testNoFrillsPrintedTransactionTimestampAndMonthFirstFallback() {
        let p = ReceiptParser.parse(source("NOFRILLS\n26/09/19 14:25:00\nBREAD 4.00"))
        XCTAssertEqual(p.date, try? ReceiptDate(year: 2026, month: 9, day: 19))
        XCTAssertTrue(p.issues.contains { $0.code == "date_order_check" })
        XCTAssertEqual(ReceiptParser.parse(source("NOFRILLS\n12/31/26")).date, try? ReceiptDate(year: 2026, month: 12, day: 31))
    }
    func testBareShortNoFrillsDatesStayAmbiguous() {
        let s = source("NOFRILLS\n03/04/26")
        let p = ReceiptParser.parse(s)
        XCTAssertNil(p.date)
        XCTAssertTrue(p.issues.contains { $0.code == "date_conflicting" && $0.sourceLineIDs.contains(s[1].id) })
    }
    func testConflictingAndInvalidDatesStayUnknown() {
        for text in ["COSTCO\n2026-03-01\n2026-03-02", "COSTCO\n2026-02-30"] {
            XCTAssertNil(ReceiptParser.parse(source(text)).date)
        }
    }
    func testConservativeUnknownRetailerKeepsPricesAndCurrencyUnknown() {
        let p = ReceiptParser.parse(source("UNKNOWN MART\nSTORE CA\n1045 TEA 1.50\nCOUPON 0.25-\nTOTAL 1.25"))
        XCTAssertNil(p.currency)
        XCTAssertEqual(p.lines.map(\.description), ["1045 TEA", "COUPON"])
        XCTAssertEqual(p.lines.map(\.amount), [150, -25])
        XCTAssertEqual(p.total, 125)
    }
    func testSKUsAndUnitWordPrefixesDoNotBecomeQuantities() {
        let p = ReceiptParser.parse(source("COSTCO\n1234 XTRA CEREAL 4.00\n2 XMAS BREAD 4.00\n8877 KGREEN TEA 2.00\nTOTAL 10.00"))
        XCTAssertEqual(p.lines.map(\.description), ["1234 XTRA CEREAL", "2 XMAS BREAD", "8877 KGREEN TEA"])
        XCTAssertTrue(p.lines.allSatisfy { $0.quantity == nil })
    }
    func testInlineRateAndPrintedExtensionMustAgree() {
        let p = ReceiptParser.parse(source("COSTCO\nSOAP 2 X 3.50 7.00\nTOTAL 7.00"))
        XCTAssertEqual(p.lines.first?.amount, 700)
        XCTAssertEqual(p.lines.first?.quantity, ExactInput.decimal("2"))
        for text in ["SOAP 2 X 3.50", "SOAP 2 X 3.50 4.00", "SOAP 4.00 2 X 3.50", "SOAP 3.50 7.00"] {
            let p = ReceiptParser.parse(source("COSTCO\n" + text))
            XCTAssertTrue(p.lines.isEmpty)
            XCTAssertTrue(p.issues.contains { ["extension_missing", "item_amount_ambiguous"].contains($0.code) })
        }
    }
    func testWeightedExtensionExactIntegerCheck() {
        let p = ReceiptParser.parse(source("NOFRILLS\nPEARS 0.375 KG @ 8.00 3.00\nTOTAL 3.00"))
        XCTAssertEqual(p.lines.first?.amount, 300)
        XCTAssertEqual(p.lines.first?.quantity, ExactInput.decimal("0.375"))
        XCTAssertEqual(ReceiptParser.parse(source("COSTCO\nPEARS 0.333 KG @ 1.00 0.33")).lines.first?.amount, 33)
        XCTAssertTrue(ReceiptParser.parse(source("COSTCO\nPEARS 0.333 KG @ 1.00 0.35")).lines.isEmpty)
    }
    func testUnrelatedOrGeometrylessRateNeverAttaches() throws {
        let p = ReceiptParser.parse(source("COSTCO\n2 X 3.50\nBREAD 4.00"))
        XCTAssertNil(p.lines.first?.quantity)
        let s = try [box("COSTCO", x: 0.1, y: 0.9), box("2 X 3.50", x: 0.1, y: 0.7), box("BREAD 4.00", x: 0.1, y: 0.67)]
        let q = ReceiptParser.parse(s)
        XCTAssertNil(q.lines.first?.quantity)
        XCTAssertEqual(q.lines.first?.sourceLineIDs, [s[2].id])
        XCTAssertTrue(q.issues.contains { $0.code == "quantity_association_uncertain" })
    }
    func testRateBoundaryClearsPendingAndTaxNeverGetsQuantity() {
        for boundary in ["DATE 2026-05-04", "MEMBER", "SUBTOTAL 7.00", "UNPRICED DIFFERENT ITEM"] {
            let p = ReceiptParser.parse(source("COSTCO\n2 X 3.50\n" + boundary + "\nBREAD 7.00\nHST 7.00"))
            XCTAssertTrue(p.lines.allSatisfy { $0.quantity == nil })
        }
    }
    func testGeometricRateWithMatchingPrintedExtensionLinksSources() throws {
        let s = try [box("COSTCO", x: 0.1, y: 0.9), box("0.375 KG @ 8.00", x: 0.1, y: 0.7), box("PEARS 3.00", x: 0.1, y: 0.67)]
        let p = ReceiptParser.parse(s)
        XCTAssertEqual(p.lines.first?.quantity, ExactInput.decimal("0.375"))
        XCTAssertEqual(p.lines.first?.sourceLineIDs, [s[1].id, s[2].id])
    }
    func testDetachedPrintedAmountPairsOnlyWithUniqueGeometry() throws {
        let s = try [box("T&T", x: 0.1, y: 0.9), box("TEA", x: 0.1, y: 0.7), box("4.00", x: 0.7, y: 0.685, width: 0.1)]
        let p = ReceiptParser.parse(s)
        XCTAssertEqual(p.lines.first?.description, "TEA")
        XCTAssertEqual(p.lines.first?.amount, 400)
        XCTAssertEqual(Set(p.lines.first?.sourceLineIDs ?? []), Set([s[1].id, s[2].id]))
        XCTAssertEqual(Set(ReceiptParser.interpretationRows(ReceiptParser.rows(s), knownRetailer: true).flatMap(\.ids)), Set(s.map(\.id)))
    }
    func testDetachedNumericDescriptionUnknownAndQuantityRemainUnpaired() throws {
        for name in ["1045 TEA", "2 X 3.00"] {
            let s = try [box("NOFRILLS", x: 0.1, y: 0.9), box(name, x: 0.1, y: 0.7), box("4.00", x: 0.7, y: 0.685, width: 0.1)]
            XCTAssertTrue(ReceiptParser.parse(s).lines.isEmpty)
        }
        let s = try [box("UNKNOWN MART", x: 0.1, y: 0.9), box("TEA", x: 0.1, y: 0.7), box("4.00", x: 0.7, y: 0.685, width: 0.1)]
        XCTAssertTrue(ReceiptParser.parse(s).lines.isEmpty)
    }
    func testAmbiguousNeighborPricesStayVisible() throws {
        let s = try [box("T&T", x: 0.1, y: 0.9), box("TEA", x: 0.1, y: 0.7), box("4.00", x: 0.7, y: 0.686, width: 0.1), box("5.00", x: 0.7, y: 0.714, width: 0.1)]
        XCTAssertTrue(ReceiptParser.parse(s).lines.isEmpty)
        XCTAssertEqual(ReceiptParser.interpretationRows(ReceiptParser.rows(s), knownRetailer: true).flatMap(\.ids).count, s.count)
    }
    func testWrappedAndRepeatedRowsDoNotStealPrices() {
        let s = source("COSTCO\nORGANIC\nALMOND MILK 5.00\nALMOND MILK 5.00\nTOTAL 10.00")
        let p = ReceiptParser.parse(s)
        XCTAssertEqual(p.lines.map(\.description), ["ALMOND MILK", "ALMOND MILK"])
        XCTAssertTrue(p.issues.contains { $0.code == "unpriced_source_row" && $0.sourceLineIDs == [s[1].id] })
        XCTAssertEqual(p.issues.last?.sourceLineIDs, s.map(\.id))
    }
    func testDiscountTaxDepositAndPrintedSignsRemainExact() {
        let p = ReceiptParser.parse(source("COSTCO\nTEA 7.00\nCOUPON 1.00-\nSUBTOTAL 6.00\nHST 0.78\nDEPOSIT 0.10\nTOTAL 6.88\nDEBIT 6.88\nCHANGE 0.00"))
        XCTAssertEqual(p.lines.map(\.kind), ["purchase", "discount", "tax", "deposit"])
        XCTAssertEqual(p.lines.map(\.amount), [700, -100, 78, 10])
        XCTAssertEqual(p.total, 688)
        XCTAssertEqual(ReceiptParser.parse(source("COSTCO\nCOUPON 1.00")).lines.first?.amount, 100)
        XCTAssertTrue(ReceiptParser.parse(source("COSTCO\nCOUPON 1.00")).issues.contains { $0.code == "adjustment_sign_check" })
    }
    func testContradictoryTotalsAndSubtotalsStayUnknown() {
        let s = source("COSTCO\nTEA 3.00\nSUBTOTAL 3.00\nSUBTOTAL 4.00\nTOTAL 3.00\nTOTAL 4.00")
        let p = ReceiptParser.parse(s)
        XCTAssertNil(p.total); XCTAssertNil(p.subtotal)
        XCTAssertTrue(p.issues.contains { $0.code == "total_conflicting" && Set($0.sourceLineIDs) == Set([s[4].id, s[5].id]) })
        XCTAssertEqual(ReceiptParser.parse(source("COSTCO\nTOTAL 3.00\nTOTAL 3.00")).total, 300)
    }
    func testMultipleAmountsInvalidateEvenAnEarlierClearTotal() {
        for text in ["TOTAL 4.00\nTOTAL 4.00 5.00", "SUBTOTAL 4.00\nSUBTOTAL 4.00 5.00"] {
            let p = ReceiptParser.parse(source("COSTCO\nTEA 4.00\n" + text))
            XCTAssertNil(p.total); XCTAssertNil(p.subtotal)
            XCTAssertTrue(p.issues.contains { $0.code == "summary_amount_ambiguous" })
        }
    }
    func testDecoratedDetachedTotalDoesNotUseTenderAsEvidence() throws {
        let s = try [box("T&T", x: 0.1, y: 0.9), box("TEA 4.00", x: 0.1, y: 0.7), box("** TOTAL", x: 0.1, y: 0.5), box("4.00", x: 0.7, y: 0.485, width: 0.1), box("DEBIT 4.00", x: 0.1, y: 0.3)]
        XCTAssertEqual(ReceiptParser.parse(s).total, 400)
        XCTAssertNil(ReceiptParser.parse(source("COSTCO\nTEA 4.00\nDEBIT 4.00")).total)
    }
    func testHeaderTotalWithoutAmountDoesNotEndPurchases() {
        let p = ReceiptParser.parse(source("COSTCO\nTOTAL\nTEA 4.00\nTOTAL 4.00\nTOTAL SAVINGS 1.00"))
        XCTAssertEqual(p.lines.count, 1); XCTAssertEqual(p.total, 400)
    }
    func testMatchingTotalNeverConfirmsSource() throws {
        let s = source("COSTCO CAD\n2026-10-08\nTEA 4.00\nTOTAL 4.00")
        let extraction = try ReceiptParser.extraction(OCRResult(lines: s, revision: 3))
        let draft = ReceiptReviewDraft(parsed: ReceiptParser.parse(s))
        XCTAssertFalse(draft.canFinalize)
        XCTAssertFalse(draft.sourceChecked)
        XCTAssertTrue(extraction.issues.contains { $0.code == "source_review_required" })
        XCTAssertEqual(extraction.rawOCR, s)
    }
}
