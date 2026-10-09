import Foundation
import Vision
import ImageIO

enum ReceiptStore { static let maximumAssetBytes = 32 * 1024 * 1024 }
struct LayoutRequest: Decodable {
    var image: String?
    var observations: [ReceiptOCRLine]?
    var mode: String
    var tableRowIDs: [[UUID]]?
}
struct LayoutResponse: Encodable {
    var status: String
    var mode: String
    var observations: [ReceiptOCRLine]
    var parsed: ParsedReceipt
    var revision: String
    var decodeMS: Double
    var ocrMS: Double
    var parserMS: Double
    var pixelWidth: Int?
    var pixelHeight: Int?
    var orientation: UInt32?
    var documents: [DocumentObservation]
    var tableRowIDs: [[UUID]]
    var groupedRowIDs: [[UUID]]
    var supportedLanguages: [String]
    var selectedLanguages: [String]
    var tableMembershipValid: Bool
    var tableRowsApplied: Int
    var tableFallbackReason: String?
}

/// Captured private stdin/stdout only; errors never include receipt data.
@main struct LayoutWorker {
    static func main() async {
        do {
            let request = try JSONDecoder().decode(LayoutRequest.self, from: FileHandle.standardInput.readDataToEndOfFile())
            guard ["baseline", "text-association", "text-column-association", "document-lines", "document-tables", "document-association"].contains(request.mode) else { throw CocoaError(.coderInvalidValue) }
            LayoutExperiment.mode = request.mode
            LayoutExperiment.documentRows = request.tableRowIDs ?? []
            var image: ReceiptImage?, documents: [DocumentObservation] = []
            var decodeMS = 0.0, ocrMS = 0.0, revision = "replay", languages: [String] = [], selectedLanguages: [String] = []
            let observations: [ReceiptOCRLine]
            if let path = request.image {
                let start = Date()
                image = try ReceiptImage.decode(Data(contentsOf: URL(fileURLWithPath: path)))
                decodeMS = Date().timeIntervalSince(start) * 1000
                let ocrStart = Date()
                if request.mode.hasPrefix("document-") {
                    var documentRequest = RecognizeDocumentsRequest(.revision1)
                    let supported = documentRequest.supportedRecognitionLanguages
                    languages = supported.map(\.maximalIdentifier)
                    documentRequest.textRecognitionOptions.recognitionLanguages = ["en-US", "fr-FR", "zh-Hans", "zh-Hant"].map { Locale.Language(identifier: $0) }.filter { supported.contains($0) }
                    selectedLanguages = documentRequest.textRecognitionOptions.recognitionLanguages.map(\.maximalIdentifier)
                    documentRequest.textRecognitionOptions.useLanguageCorrection = false
                    documentRequest.textRecognitionOptions.automaticallyDetectLanguage = false
                    documentRequest.textRecognitionOptions.maximumCandidateCount = 1
                    documentRequest.barcodeDetectionOptions.enabled = false
                    // Decode raw pixels and pass orientation once, exactly as production.
                    guard let source = CGImageSourceCreateWithData(image!.bytes as CFData, nil),
                          let cgImage = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCache: false] as CFDictionary) else { throw ImportFailure.unsupportedImage }
                    documents = try await documentRequest.perform(on: cgImage, orientation: image!.orientation)
                    revision = "document-revision1"
                    var seen = Set<UUID>()
                    let rawLines = documents.flatMap { $0.document.text.lines }
                    observations = rawLines.filter { seen.insert($0.uuid).inserted }.map { line in
                        let xs = [line.topLeft.x, line.topRight.x, line.bottomRight.x, line.bottomLeft.x]
                        let ys = [line.topLeft.y, line.topRight.y, line.bottomRight.y, line.bottomLeft.y]
                        let x = max(0, min(1, xs.min()!)), y = max(0, min(1, ys.min()!))
                        let box = try? ReceiptOCRBox(x: x, y: y, width: min(1, xs.max()!) - x, height: min(1, ys.max()!) - y)
                        let candidate = line.topCandidates(1).first
                        return ReceiptOCRLine(id: line.uuid, text: candidate?.string ?? line.transcript, engineConfidence: candidate?.confidence, boundingBox: box)
                    }
                    // Cells refer to original line UUIDs; no financial values inferred.
                    LayoutExperiment.documentRows = documents.flatMap { doc in
                        doc.document.tables.flatMap { table in table.rows.map { cells in
                            // Spanning cells may repeat. Deduplicate within a single row;
                            // across rows they trigger the conservative membership fallback.
                            var rowSeen = Set<UUID>()
                            return cells.flatMap { $0.content.text.lines.map(\.uuid) }.filter { rowSeen.insert($0).inserted }
                        }.filter { !$0.isEmpty } }
                    }
                } else {
                    let result = try ReceiptRecognitionJob().run(image!)
                    observations = result.lines; revision = String(result.revision)
                }
                ocrMS = Date().timeIntervalSince(ocrStart) * 1000
            } else if let saved = request.observations {
                observations = saved
            } else { throw CocoaError(.fileReadCorruptFile) }
            let start = Date()
            let parsed = ReceiptParser.parse(observations)
            let parserMS = Date().timeIntervalSince(start) * 1000
            let tableIDs = LayoutExperiment.documentRows.flatMap { $0 }
            let known = Set(observations.map(\.id))
            let duplicate = Set(tableIDs).count != tableIDs.count
            let unknown = !tableIDs.allSatisfy(known.contains)
            let valid = !duplicate && !unknown
            let fallback: String? = unknown ? "unknown_cell_line_uuid" : (duplicate ? "spanning_or_duplicate_cell_line_uuid" : (tableIDs.isEmpty ? "no_native_table_rows" : nil))
            let response = LayoutResponse(status: "ok", mode: request.mode, observations: observations, parsed: parsed, revision: revision,
                decodeMS: decodeMS, ocrMS: ocrMS, parserMS: parserMS,
                pixelWidth: image?.pixelWidth, pixelHeight: image?.pixelHeight, orientation: image?.orientation.rawValue,
                documents: documents, tableRowIDs: LayoutExperiment.documentRows,
                groupedRowIDs: LayoutExperiment.rows(observations).map(\.ids), supportedLanguages: languages,
                selectedLanguages: selectedLanguages, tableMembershipValid: valid,
                tableRowsApplied: request.mode == "document-tables" && valid ? LayoutExperiment.documentRows.count : 0,
                tableFallbackReason: fallback)
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            FileHandle.standardOutput.write(try encoder.encode(response))
        } catch {
            FileHandle.standardOutput.write(Data("{\"status\":\"failed\"}".utf8))
        }
    }
}
