// Recognition-boundary type only; the independent matcher check does not run OCR.
struct OCRResult: Sendable {
    let lines: [ReceiptOCRLine]
    let revision: Int
}
