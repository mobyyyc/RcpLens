#if DEBUG
import UIKit

/// Deterministic fictional review cases: no private corpus, OCR request or normal installed store.
@MainActor enum SyntheticCorrectionPreview {
    static func fixture(_ mode: String) throws -> (Data, ReceiptExtraction, ReceiptReviewDraft) {
        let count = mode == "correction-long" ? 36 : 1
        var text = ["FICTIONAL NO FRILLS CORRECTION CAD", "2026-10-09"]
        text += (0..<count).map { "FICTIONAL ITEM \($0 + 1) 1.00" }
        if mode == "correction-difficult" { text += ["TEST OMITTED ITEM", "2.00"] }
        if mode == "correction-source" { text += ["TEST WRAPPED FIRST", "TEST WRAPPED LAST"] }
        text += ["SUBTOTAL " + ExactInput.format(Int64(count * 100 + (mode == "correction-difficult" ? 200 : 0))),
                 "TOTAL " + ExactInput.format(Int64(count * 100 + (mode == "correction-difficult" ? 200 : 0)))]
        let width: CGFloat = 800, height = CGFloat(text.count * 72 + 80)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        let data = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).pngData { _ in
            UIColor.white.setFill(); UIRectFill(CGRect(x: 0, y: 0, width: width, height: height))
            for (i, line) in text.enumerated() {
                (line as NSString).draw(at: CGPoint(x: 35, y: CGFloat(40 + i * 72)), withAttributes: [.font: UIFont.monospacedSystemFont(ofSize: 25, weight: .regular), .foregroundColor: UIColor.black])
            }
        }
        let observations = try text.enumerated().map { i, line in
            ReceiptOCRLine(id: UUID(), text: line, engineConfidence: 0.7,
                boundingBox: mode == "correction-source" && line == "TEST WRAPPED LAST" ? nil : try ReceiptOCRBox(x: 35 / Double(width), y: 1 - Double(40 + i * 72 + 32) / Double(height), width: 0.88, height: 32 / Double(height)))
        }
        let extraction = try ReceiptParser.extraction(OCRResult(lines: observations, revision: 3))
        var draft = ReceiptReviewDraft(fields: extraction.fields)
        if !["correction-difficult", "correction-source"].contains(mode), !draft.lines.isEmpty { draft.lines[draft.lines.count - 1].amount = "" }
        return (data, extraction, draft)
    }
}
#endif
