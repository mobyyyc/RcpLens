#if DEBUG
import Foundation
import Darwin

/// Fixed fictional inputs, isolated from the eventual production store and Keychain account.
/// Launch arguments are one-shot development checks, not a user-content import boundary.
@MainActor
enum SyntheticStorageDiagnostics {
    private struct Report: Codable {
        var phase: String
        var passed = false
        var receiptCount = 0
        var revisionCount = 0
        var imageMatched = false
        var originalEvidenceMatched = false
        var unknownOriginalAmountPreserved = false
        var correctedAmountMatched = false
        var remainsDraft = false
        var failureCode: Int?
    }

    private static let instant = Date(timeIntervalSince1970: 1_700_000_000)
    private static func extraction() -> ReceiptExtraction {
        let sourceID = UUID(uuidString: "A0000000-0000-0000-0000-000000000001")!
        return ReceiptExtraction(capturedAt: instant, recognizer: "SyntheticFixture", recognizerVersion: "1",
            parser: "SyntheticFixture", parserVersion: "1",
            rawOCR: [ReceiptOCRLine(id: sourceID, text: "FICTIONAL ITEM UNKNOWN AMOUNT", engineConfidence: nil)],
            rawParserOutput: Data("{\"amount\":null}".utf8),
            fields: ReceiptFields(merchant: "FICTIONAL STORAGE DIAGNOSTIC", purchaseDate: nil, currency: .cad,
                items: [ReceiptLine(id: UUID(uuidString: "A0000000-0000-0000-0000-000000000002")!,
                    description: "FICTIONAL ITEM", sku: nil, quantity: nil, unitPrice: nil, amount: nil,
                    taxMarker: nil, sourceLineIDs: [sourceID])], adjustments: [], subtotal: nil, total: nil),
            issues: [ReceiptExtractionIssue(code: "unknown-amount", sourceLineIDs: [sourceID], detail: nil)])
    }

    static func runIfRequested() async {
        let args = ProcessInfo.processInfo.arguments
        let create = args.contains("--synthetic-storage-create")
        let reopen = args.contains("--synthetic-storage-reopen")
        let crash = args.contains("--synthetic-storage-crash")
        let delete = args.contains("--synthetic-storage-delete")
        let verifyDeleted = args.contains("--synthetic-storage-verify-deleted")
        guard create || reopen || crash || delete || verifyDeleted else { return }
        var report = Report(phase: create ? "created" : crash ? "crashRequested" : delete ? "deleted"
                            : verifyDeleted ? "deletionVerified" : "reopened")
        do {
            let root = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                  appropriateFor: nil, create: true)
                .appendingPathComponent("T04SyntheticStore", isDirectory: true)
            let provider = KeychainReceiptStoreKey(service: "com.mobyyyc.RcpLens.T04-diagnostics", account: "synthetic-only-v1")
            let store = try ReceiptStore(directory: root, keyProvider: provider, fault: { point in
                if crash && point == .beforeCommit {
                    // Abrupt process death after SQLite has spilled an uncommitted large asset.
                    // Only this explicitly requested, synthetic-only diagnostics process can exit here.
                    kill(getpid(), SIGKILL)
                }
            })
            let originalImage = try SyntheticFixture.imageData()
            if crash {
                try save(report)
                var largeSyntheticAsset = originalImage
                largeSyntheticAsset.append(Data(repeating: 0, count: 24 * 1024 * 1024))
                _ = try await store.create(extraction: extraction(), originalImage: largeSyntheticAsset,
                                           mediaType: "image/png", now: instant)
                throw ReceiptStoreError.injectedFailure // A returned commit would invalidate the crash check.
            }
            if create {
                try await store.purgeAllReceipts() // Only the dedicated fictional diagnostics database.
                let record = try await store.create(extraction: extraction(), originalImage: originalImage,
                                                    mediaType: "image/png", now: instant)
                var fields = record.current.fields
                fields.items[0].amount = ReceiptMoney(minorUnits: 1234, currency: .cad)
                fields.total = ReceiptMoney(minorUnits: 1234, currency: .cad)
                _ = try await store.revise(id: record.id, expectedRevision: record.current.id, fields: fields,
                                           now: instant.addingTimeInterval(1))
            }
            if delete {
                for record in try await store.receipts() { try await store.delete(id: record.id) }
            }
            let receipts = try await store.receipts()
            if delete || verifyDeleted {
                report.receiptCount = receipts.count
                report.passed = receipts.isEmpty
                try await store.close()
                try save(report)
                return
            }
            report.receiptCount = receipts.count
            if let record = receipts.first {
                let savedImage = try await store.originalImage(receiptID: record.id)
                report.revisionCount = record.revisions.count
                report.imageMatched = savedImage == originalImage
                report.originalEvidenceMatched = record.original == extraction()
                report.unknownOriginalAmountPreserved = record.original.fields.items[0].amount == nil
                report.correctedAmountMatched = record.current.fields.items[0].amount?.minorUnits == 1234
                report.remainsDraft = record.current.review == .draft
            }
            report.passed = report.receiptCount == 1 && report.revisionCount == 2 && report.imageMatched
                && report.originalEvidenceMatched && report.unknownOriginalAmountPreserved
                && report.correctedAmountMatched && report.remainsDraft
            try await store.close()
            try save(report)
        } catch {
            report.passed = false
            report.failureCode = (error as NSError).code
            try? save(report)
        }
    }

    private static func save(_ report: Report) throws {
        let cache = try FileManager.default.url(for: .cachesDirectory, in: .userDomainMask,
                                               appropriateFor: nil, create: true)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(report).write(to: cache.appendingPathComponent("synthetic-storage.json"), options: .atomic)
    }
}
#endif
