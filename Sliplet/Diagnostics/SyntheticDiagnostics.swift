#if DEBUG
import Foundation
import FoundationModels
import Observation

/// Fixed synthetic inputs only. This is not the production receipt pipeline.
enum SyntheticFixture {
    static func imageData() throws -> Data {
        guard let url = Bundle.main.url(forResource: "synthetic-receipt", withExtension: "png") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try Data(contentsOf: url)
    }
}

struct DiagnosticReport: Codable {
    var modelAvailability = "notChecked"
    var generation = "notRun"
    var responseCharacterCount = 0
    var vision = "notRun"
    var recognizedLineCount = 0
    var syntheticTextMatched = false
    var modelFailureDomain: String?
    var modelFailureCode: Int?
    var visionFailureDomain: String?
    var visionFailureCode: Int?
}

@MainActor @Observable
final class SyntheticDiagnostics {
    private(set) var report = DiagnosticReport()
    private(set) var syntheticResponse = ""
    private(set) var isRunning = false
    private(set) var reportWriteFailed = false

    func run() async {
        guard !isRunning else { return }
        isRunning = true
        defer { isRunning = false }
        report = DiagnosticReport()
        syntheticResponse = ""
        reportWriteFailed = false

        do {
            let recognized = try await VisionTextRecognizer().recognize(imageData: SyntheticFixture.imageData())
            report.recognizedLineCount = recognized.lines.count
            let text = recognized.lines.joined(separator: " ").uppercased()
            report.syntheticTextMatched = text.contains("SYNTHETIC") && text.contains("TOTAL") && text.contains("12.34")
            report.vision = report.syntheticTextMatched ? "passed" : "syntheticTextMismatch"
        } catch {
            report.vision = "failed"
            let failure = error as NSError
            report.visionFailureDomain = failure.domain
            report.visionFailureCode = failure.code
        }

        // Explicit local model; no provider, Private Cloud Compute or cloud fallback.
        let model = SystemLanguageModel.default
        switch model.availability {
        case .available:
            report.modelAvailability = "available"
            report.generation = "running"
            saveReport()
            do {
                let session = LanguageModelSession(model: model)
                let response = try await session.respond(
                    to: "Write one short friendly greeting for a fictional robot named Pip. Respond in English.",
                    options: GenerationOptions(samplingMode: .greedy, maximumResponseTokens: 48)
                )
                syntheticResponse = response.content
                report.responseCharacterCount = response.content.count
                report.generation = response.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "emptyResponse" : "passed"
            } catch {
                report.generation = "failed"
                let failure = error as NSError
                report.modelFailureDomain = failure.domain
                report.modelFailureCode = failure.code
            }
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible: report.modelAvailability = "deviceNotEligible"
            case .appleIntelligenceNotEnabled: report.modelAvailability = "appleIntelligenceNotEnabled"
            case .modelNotReady: report.modelAvailability = "modelNotReady"
            @unknown default: report.modelAvailability = "unknownUnavailableReason"
            }
            report.generation = "unavailable"
        }
        saveReport()
    }

    /// Only aggregate synthetic check results; never OCR, prompt, response or error descriptions.
    private func saveReport() {
        do {
            let directory = try FileManager.default.url(for: .cachesDirectory, in: .userDomainMask,
                                                       appropriateFor: nil, create: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(report).write(to: directory.appendingPathComponent("synthetic-diagnostics.json"), options: .atomic)
        } catch {
            reportWriteFailed = true
        }
    }
}
#endif
