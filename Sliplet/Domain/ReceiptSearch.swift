import Foundation

/// Memory-only index of decrypted records. Never serialized, logged or sent off device.
struct ReceiptSearchIndex {
    enum Basis: String, Sendable { case merchant, corrected, sku, originalSKU, original, rawText }
    struct Match: Identifiable, Equatable, Sendable {
        let id: String
        let itemID: UUID?
        let title: String
        let basis: Basis
        let matchedText: String
        let sourceLineIDs: [UUID]
        let originalOnly: Bool
        var unparsed = false
    }
    struct Result: Identifiable {
        let record: ReceiptRecord
        let matches: [Match]
        var id: UUID { record.id }
    }
    private struct Field {
        let text: String
        let basis: Basis
        let tokens: [String]
        let literalTokens: [String]
        init(_ text: String?, _ basis: Basis) {
            self.text = text ?? ""; self.basis = basis
            let raw = ReceiptSearchText.tokens(self.text, expand: false)
            literalTokens = raw + (basis == .merchant ? [raw.joined()] : [])
            let expanded = ReceiptSearchText.tokens(self.text)
            tokens = expanded + (basis == .merchant ? [raw.joined()] : [])
        }
        func contains(_ term: String, literal: Bool = false) -> Bool {
            (literal ? literalTokens : tokens).contains { basis == .merchant ? $0.contains(term) : ReceiptSearchText.matches($0, term) }
        }
    }
    private struct Item {
        let id: UUID
        let currentID: UUID?
        let title: String
        let fields: [Field]
        let sourceIDs: [UUID]
        var unparsed = false
    }
    private struct Document {
        let record: ReceiptRecord
        let merchants: [Field]
        let items: [Item]
    }
    private var documents: [Document] = []
    var count: Int { documents.count }

    init(_ records: [ReceiptRecord] = []) {
        documents = records.sorted(by: ReceiptHistory.newestFirst).map { record in
            let source = Dictionary(uniqueKeysWithValues: record.original.rawOCR.map { ($0.id, $0.text) })
            var linkedOriginals = Set<UUID>()
            var items: [Item] = record.current.fields.items.map { current in
                let ids = Set(current.sourceLineIDs)
                let originals = record.original.fields.items.filter {
                    $0.id == current.id || (!ids.isEmpty && !ids.isDisjoint(with: $0.sourceLineIDs))
                }
                linkedOriginals.formUnion(originals.map(\.id))
                let sourceIDs = Array(Set(current.sourceLineIDs + originals.flatMap(\.sourceLineIDs))).sorted { $0.uuidString < $1.uuidString }
                let fields = [Field(current.description, .corrected), Field(current.sku, .sku)]
                    + originals.flatMap { [Field($0.description, .original), Field($0.sku, .originalSKU)] }
                    + sourceIDs.compactMap { source[$0].map { Field($0, .rawText) } }
                return Item(id: current.id, currentID: current.id, title: current.description ?? "Description missing", fields: fields, sourceIDs: sourceIDs)
            }
            // Removed extraction lines remain evidence, never current purchases or current amounts.
            items += record.original.fields.items.filter { !linkedOriginals.contains($0.id) }.map { original in
                Item(id: original.id, currentID: nil, title: original.description ?? "Original description missing",
                     fields: [Field(original.description, .original), Field(original.sku, .originalSKU)]
                        + original.sourceLineIDs.compactMap { source[$0].map { Field($0, .rawText) } },
                     sourceIDs: original.sourceLineIDs)
            }
            let linkedRows = Set(items.flatMap(\.sourceIDs))
            items += record.original.rawOCR.filter { !linkedRows.contains($0.id) }.map { row in
                Item(id: row.id, currentID: nil, title: row.text, fields: [Field(row.text, .rawText)], sourceIDs: [row.id], unparsed: true)
            }
            return Document(record: record, merchants: [Field(record.current.fields.merchant, .merchant), Field(record.original.fields.merchant, .merchant)], items: items)
        }
    }

    func results(query: String, collection: String = "All receipts", includeArchived: Bool = false,
                 merchant: ReceiptHistoryChoice = .all, month: ReceiptHistoryChoice = .all) -> [Result] {
        guard query.count <= 512 else { return [] }
        let terms = ReceiptSearchText.tokens(query)
        let literalTerms = ReceiptSearchText.tokens(query, expand: false)
        let searching = !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if searching && terms.isEmpty { return [] }
        return documents.compactMap { document in
            let record = document.record
            guard (collection == "Archive" ? record.isArchived : collection == "Starred" ? record.isStarred && (includeArchived || !record.isArchived) : includeArchived || !record.isArchived),
                  merchant.accepts(record.current.fields.merchant), month.accepts(ReceiptHistory.monthKey(record)) else { return nil }
            if !searching { return Result(record: record, matches: []) }
            func matches(_ fields: [Field]) -> Bool {
                terms.allSatisfy { term in fields.contains { field in field.contains(term) } }
            }
            if matches(document.merchants) {
                let field = document.merchants.first { matches([$0]) } ?? document.merchants[0]
                return Result(record: record, matches: [.init(id: record.id.uuidString + "-merchant", itemID: nil,
                    title: record.current.fields.merchant ?? "Merchant missing", basis: .merchant, matchedText: field.text, sourceLineIDs: [], originalOnly: false)])
            }
            let hits: [Match] = document.items.compactMap { item in
                guard matches(document.merchants + item.fields) else { return nil }
                let literalField = item.fields.first { field in
                    literalTerms.contains { term in !document.merchants.contains { $0.contains(term, literal: true) }
                        && field.contains(term, literal: true) }
                }
                let field = literalField ?? item.fields.first { field in
                    terms.contains { term in !document.merchants.contains { $0.contains(term) }
                        && field.contains(term) }
                } ?? item.fields[0]
                return Match(id: record.id.uuidString + item.id.uuidString, itemID: item.currentID, title: item.title,
                             basis: field.basis, matchedText: field.text, sourceLineIDs: item.sourceIDs, originalOnly: item.currentID == nil, unparsed: item.unparsed)
            }
            return hits.isEmpty ? nil : Result(record: record, matches: hits)
        }
    }
}

enum ReceiptSearchText {
    // Finite, inspectable aliases. No rewrite of stored content, transliteration or model inference.
    static let abbreviations = ["mlk": "milk", "brd": "bread", "chkn": "chicken", "chk": "chicken", "org": "organic",
                                "og": "organic", "yog": "yogurt", "yoghurt": "yogurt", "strawb": "strawberry",
                                "strawberries": "strawberry", "tom": "tomato", "tomatoes": "tomato",
                                "pot": "potato", "potatoes": "potato", "grn": "green", "veg": "vegetable"]
    static func tokens(_ text: String, expand: Bool = true) -> [String] {
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX")).lowercased()
        return folded.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.map { expand ? abbreviations[$0] ?? $0 : $0 }
    }
    static func matches(_ token: String, _ term: String) -> Bool {
        // Continuous CJK text has no whitespace boundaries; permit script-preserving substrings.
        let cjk = term.unicodeScalars.contains { (0x3400...0x9FFF).contains($0.value) || (0x3040...0x30FF).contains($0.value) || (0xAC00...0xD7AF).contains($0.value) }
        return cjk ? token.contains(term) : token.hasPrefix(term)
    }
}

enum ReceiptHistoryChoice: Hashable { case all, missing, value(String)
    func accepts(_ value: String?) -> Bool {
        switch self { case .all: true; case .missing: value == nil; case .value(let expected): value == expected }
    }
}

enum ReceiptHistory {
    static func monthKey(_ record: ReceiptRecord) -> String? {
        record.current.fields.purchaseDate.map { String(format: "%04d-%02d", $0.year, $0.month) }
    }
    static func newestFirst(_ a: ReceiptRecord, _ b: ReceiptRecord) -> Bool {
        let x = ExactInput.dateText(a.current.fields.purchaseDate), y = ExactInput.dateText(b.current.fields.purchaseDate)
        if x != y { return x > y } // Missing civil dates stay after known dates, never become import dates.
        if a.createdAt != b.createdAt { return a.createdAt > b.createdAt }
        return a.id.uuidString < b.id.uuidString
    }
    static func monthTitle(_ key: String?) -> String {
        guard let key else { return "Date missing" }
        let components = key.split(separator: "-").compactMap { Int($0) }
        guard components.count == 2 else { return key }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        guard let date = calendar.date(from: DateComponents(year: components[0], month: components[1], day: 1, hour: 12)) else { return key }
        let format = DateFormatter(); format.calendar = calendar; format.timeZone = calendar.timeZone
        format.setLocalizedDateFormatFromTemplate("MMMM yyyy")
        return format.string(from: date)
    }
}
