import Foundation
import Vision
import ImageIO

struct OCRResult: Sendable {
    let lines: [ReceiptOCRLine]
    let revision: Int
}

/// The request can be cancelled from the main actor while Vision runs off the UI thread.
final class ReceiptRecognitionJob: @unchecked Sendable {
    private let lock = NSLock()
    private var request: VNRecognizeTextRequest?
    private var cancelled = false
    func cancel() {
        lock.lock(); cancelled = true; let request = request; lock.unlock()
        request?.cancel()
    }
    func run(_ image: ReceiptImage) throws -> OCRResult {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        let supported = try request.supportedRecognitionLanguages()
        request.recognitionLanguages = ["en-US", "fr-FR", "zh-Hans", "zh-Hant"].filter(supported.contains)
        lock.lock()
        let stopped = cancelled
        if !stopped { self.request = request }
        lock.unlock()
        guard !stopped else { throw CancellationError() }
        defer { lock.lock(); self.request = nil; lock.unlock() }
        guard let source = CGImageSourceCreateWithData(image.bytes as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCache: false] as CFDictionary) else { throw ImportFailure.unsupportedImage }
        try VNImageRequestHandler(cgImage: cgImage, orientation: image.orientation).perform([request])
        lock.lock(); let nowCancelled = cancelled; lock.unlock()
        guard !nowCancelled else { throw CancellationError() }
        let lines = (request.results ?? []).compactMap { observation -> ReceiptOCRLine? in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            let b = observation.boundingBox
            // Clamp floating-point geometry at the unit boundary, without changing text/financial data.
            let x = max(0, min(1, b.minX)), y = max(0, min(1, b.minY))
            let box = try? ReceiptOCRBox(x: x, y: y, width: min(b.width, 1 - x), height: min(b.height, 1 - y))
            return ReceiptOCRLine(id: UUID(), text: candidate.string, engineConfidence: candidate.confidence, boundingBox: box)
        }
        return OCRResult(lines: lines, revision: request.revision)
    }
}

/// T01's synthetic recognition boundary remains available for diagnostics.
actor VisionTextRecognizer {
    func recognize(imageData: Data) throws -> RecognizedText {
        let result = try ReceiptRecognitionJob().run(ReceiptImage.decode(imageData))
        return RecognizedText(lines: result.lines.map(\.text))
    }
}
