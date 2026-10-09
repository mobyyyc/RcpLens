import Foundation

// Compile unchanged app recognition/parser/domain files. This storage limit shim
// avoids opening the store or Keychain; build.sh verifies it against ReceiptStore.
enum ReceiptStore { static let maximumAssetBytes = 32 * 1024 * 1024 }

struct AuditRequest: Decodable {
    var image: String?
    var observations: [ReceiptOCRLine]?
}

struct AuditResponse: Encodable {
    let groupedRowIDs: [[UUID]]
    let interpretedRowIDs: [[UUID]]
    let parserVersion: String
    let status: String
    let observations: [ReceiptOCRLine]
    let parsed: ParsedReceipt
    let revision: Int?
    let decodeMS: Double
    let ocrMS: Double
    let parserMS: Double
    let pixelWidth: Int?
    let pixelHeight: Int?
    let orientation: UInt32?
}

// Private captured stdin/stdout protocol. Never invoke on receipts in a terminal.
@main struct AuditWorker {
    static func main() {
        do {
            let request = try JSONDecoder().decode(AuditRequest.self, from: FileHandle.standardInput.readDataToEndOfFile())
            var decodeMS = 0.0, ocrMS = 0.0
            var revision: Int?, image: ReceiptImage?
            let observations: [ReceiptOCRLine]
            if let path = request.image {
                let start = Date()
                image = try ReceiptImage.decode(Data(contentsOf: URL(fileURLWithPath: path)))
                decodeMS = Date().timeIntervalSince(start) * 1000
                let ocrStart = Date()
                let ocr = try ReceiptRecognitionJob().run(image!)
                ocrMS = Date().timeIntervalSince(ocrStart) * 1000
                revision = ocr.revision
                observations = ocr.lines
            } else if let saved = request.observations {
                observations = saved
            } else { throw CocoaError(.fileReadCorruptFile) }
            let start = Date()
            let parsed = ReceiptParser.parse(observations)
            let response = AuditResponse(groupedRowIDs: ReceiptParser.rows(observations).map(\.ids),
                interpretedRowIDs: ReceiptParser.interpretationRows(ReceiptParser.rows(observations), knownRetailer: parsed.merchant != nil).map(\.ids),
                parserVersion: ReceiptParser.version, status: "ok", observations: observations, parsed: parsed,
                revision: revision, decodeMS: decodeMS, ocrMS: ocrMS,
                parserMS: Date().timeIntervalSince(start) * 1000,
                pixelWidth: image?.pixelWidth, pixelHeight: image?.pixelHeight,
                orientation: image?.orientation.rawValue)
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            FileHandle.standardOutput.write(try encoder.encode(response))
        } catch {
            // Framework stderr is captured/discarded by the runner.
            FileHandle.standardOutput.write(Data("{\"status\":\"failed\"}".utf8))
        }
    }
}
