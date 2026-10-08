import Foundation

let when = Date(timeIntervalSince1970: 1700000000)
func make(_ id: String, merchant: String, archive: Bool = false) -> ReceiptRecord {
    let sourceRows = ["ORG MLK 2%", "CREME OCR", "REMOVED AUBERGINE", "UNPARSED FENNEL 9.99"].map { ReceiptOCRLine(id: UUID(), text: $0, engineConfidence: nil) }
    let originalItems = sourceRows.prefix(3).enumerated().map { i, row in
        ReceiptLine(id: UUID(), description: row.text, sku: i == 0 ? "777" : nil, quantity: nil, unitPrice: nil,
                    amount: .init(minorUnits: Int64((i + 1) * 100), currency: .cad), taxMarker: nil, sourceLineIDs: [row.id])
    }
    let originalFields = ReceiptFields(merchant: merchant, purchaseDate: try! ReceiptDate(year: 2026, month: 10, day: 8), currency: .cad,
                                       items: originalItems, adjustments: [], subtotal: .init(minorUnits: 600, currency: .cad), total: .init(minorUnits: 600, currency: .cad))
    var corrected = originalFields
    corrected.items.removeLast(); corrected.items[0].description = "Organic milk"; corrected.items[0].sku = "999"
    corrected.items[1].description = "Crème fraîche 有机苹果"; corrected.total = .init(minorUnits: 300, currency: .cad); corrected.subtotal = corrected.total
    let extraction = ReceiptExtraction(capturedAt: when, recognizer: "Independent fictional fixture", recognizerVersion: "1", parser: "Independent fictional fixture", parserVersion: "1", rawOCR: sourceRows, rawParserOutput: Data("fictional".utf8), fields: originalFields, issues: [])
    return ReceiptRecord(id: UUID(uuidString: id)!, createdAt: when, updatedAt: when, original: extraction,
        asset: .init(id: UUID(), mediaType: "image/png", byteCount: 1, sha256: Data(repeating: 0, count: 32)),
        revisions: [.init(id: UUID(), createdAt: when, fields: originalFields, review: .draft), .init(id: UUID(), createdAt: when, fields: corrected, review: .sourceReviewed)],
        organization: .init(archived: archive, starred: archive))
}
let a = make("00000000-0000-0000-0000-000000000001", merchant: "No Frills")
let b = make("00000000-0000-0000-0000-000000000002", merchant: "Costco", archive: true)
try a.validate(); try b.validate()
let index = ReceiptSearchIndex([b, a])
var rows: [[String: Any]] = []
func check(_ name: String, _ condition: Bool) {
    rows.append(["case": name, "passed": condition])
}
for query in ["nofrills", "no-frills", "nO fRiLlS", "nofrills milk", "nofrills 777", "no-frills mlk", "milk", "mlk", "org milk", "creme", "苹果", "ＦＲＡÎＣＨＥ", "777", "999", "aubergine", "fennel"] {
    check("literal/current/source/Unicode coverage: " + query, index.results(query: query).map(\.id) == [a.id])
}
check("original SKU provenance", index.results(query: "777").first?.matches.first?.basis == .originalSKU)
check("current SKU provenance", index.results(query: "999").first?.matches.first?.basis == .sku)
check("removed evidence has no current purchase", index.results(query: "aubergine").first?.matches.allSatisfy { $0.itemID == nil && $0.originalOnly } == true)
check("unparsed evidence has no current purchase", index.results(query: "fennel").first?.matches.allSatisfy { $0.itemID == nil && $0.originalOnly } == true)
check("default excludes archive", index.results(query: "costco").isEmpty)
check("include archived finds archive", index.results(query: "costco", includeArchived: true).map(\.id) == [b.id])
check("Archive collection finds archive", index.results(query: "costco", collection: "Archive").map(\.id) == [b.id])
check("query punctuation produces no wildcard", index.results(query: "---").isEmpty)
check("unknown query produces no fabricated match", index.results(query: "neverprintedfictionalword").isEmpty)
check("ordering invariant under record permutation", ReceiptSearchIndex([a, b]).results(query: "milk", includeArchived: true).map(\.id) == index.results(query: "milk", includeArchived: true).map(\.id))
check("no cross-item composite purchase", index.results(query: "milk creme").isEmpty)
check("delete removes searchable current and source data", ReceiptSearchIndex([b]).results(query: "milk").isEmpty)
check("long query never silently truncates terms", index.results(query: String(repeating: "milk ", count: 120)).isEmpty)
check("combined merchant query preserves original SKU provenance", index.results(query: "nofrills 777").first?.matches.first?.basis == .originalSKU)
let report: [String: Any] = ["fictionalOnly": true, "actualSwiftMatcher": true, "cases": rows, "failed": rows.filter { $0["passed"] as? Bool == false }.count]
let encoded = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
try encoded.write(to: URL(fileURLWithPath: "/tmp/rcplens-t07-review/independent-search-results.json"))
print("Independent search checks: \(rows.count); failed: \(report["failed"]!)")
if rows.contains(where: { $0["passed"] as? Bool == false }) { exit(1) }
