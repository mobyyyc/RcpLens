#if DEBUG
import Foundation
import UIKit

/// Explicit fictional search previews; called only within the existing isolated preview store.
@MainActor enum SyntheticSearchPreview {
    static func fixture(_ index: Int) -> (Data, ReceiptExtraction, ReceiptReviewDraft) {
        let merchant = ["FICTIONAL CORNER MART", "FICTIONAL GROVE", "FICTIONAL HARBOR"][index % 3]
        let date = index % 3 == 2 ? "" : index % 3 == 1 ? "2026-09-14" : "2026-10-08"
        let content = [merchant, date, "ORG MLK 2% OLD-123456 1.23", "CREME OCR 2.00", "REMOVED APPLES 0.99", "UNPARSED FENNEL 9.99", "FICTIONAL SEARCH TEST — NOT A PURCHASE"]
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        let bytes = UIGraphicsImageRenderer(size: CGSize(width: 800, height: 700), format: format).pngData { _ in
            UIColor.white.setFill(); UIRectFill(CGRect(x: 0, y: 0, width: 800, height: 700))
            for (i, text) in content.enumerated() {
                (text as NSString).draw(at: CGPoint(x: 35, y: 35 + i * 75), withAttributes: [.font: UIFont.monospacedSystemFont(ofSize: 26, weight: .regular), .foregroundColor: UIColor.black])
            }
        }
        let rows = content.enumerated().map { i, text in ReceiptOCRLine(id: UUID(), text: text, engineConfidence: nil,
            boundingBox: try! .init(x: 0.04, y: 1 - Double(35 + i * 75 + 35) / 700, width: 0.90, height: 0.05)) }
        var draft = ReceiptReviewDraft(); draft.merchant = merchant; draft.date = date; draft.currency = "CAD"
        draft.lines = [
            .init(id: UUID(), kind: "purchase", name: "ORG MLK 2%", quantity: "", amount: "1.23", sourceLineIDs: [rows[2].id], sku: "OLD-123456"),
            .init(id: UUID(), kind: "purchase", name: "CREME OCR", quantity: "", amount: "2.00", sourceLineIDs: [rows[3].id]),
            .init(id: UUID(), kind: "purchase", name: "REMOVED APPLES", quantity: "", amount: "0.99", sourceLineIDs: [rows[4].id])]
        draft.total = "4.22"; draft.subtotal = "4.22"
        let original = ReceiptExtraction(capturedAt: Date(), recognizer: "Fictional search fixture", recognizerVersion: "1", parser: "Fictional search fixture", parserVersion: "1", rawOCR: rows,
            rawParserOutput: try! JSONEncoder().encode(draft.fields), fields: draft.fields, issues: [])
        draft.lines.removeLast(); draft.lines[0].name = "Organic milk"; draft.lines[0].sku = "NEW-654321"
        draft.lines[1].name = "Crème fraîche 有机苹果"; draft.total = "3.23"; draft.subtotal = "3.23"
        draft.sourceOpened = true; draft.sourceChecked = true
        return (bytes, original, draft)
    }
}
#endif
