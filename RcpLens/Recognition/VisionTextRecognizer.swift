import Foundation
import Vision

/// Accepts encoded image bytes. Does not persist or log input or recognized text.
actor VisionTextRecognizer {
    func recognize(imageData: Data) throws -> RecognizedText {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["en-US"]
        request.usesLanguageCorrection = false
        let handler = VNImageRequestHandler(data: imageData, options: [:])
        try handler.perform([request])
        return RecognizedText(lines: (request.results ?? []).compactMap {
            $0.topCandidates(1).first?.string
        })
    }
}
