import Foundation

/// T03's geometric row grouping and deterministic parser, ported to Swift.
/// OCR observations and parser output are retained separately. No inferred tax arithmetic.
struct ParsedReceipt: Codable, Sendable {
    struct Line: Codable, Sendable {
        var kind: String
        var description: String
        var amount: Int64
        var quantity: ReceiptDecimal?
        var sourceLineIDs: [UUID]
        var id = UUID()
    }
    var merchant: String?
    var date: ReceiptDate?
    var currency: ReceiptCurrency?
    var subtotal: Int64?
    var total: Int64?
    var lines: [Line] = []
    var issues: [ReceiptExtractionIssue] = []

    func fields() -> ReceiptFields {
        func money(_ value: Int64?) -> ReceiptMoney? {
            guard let currency, let value else { return nil }
            return ReceiptMoney(minorUnits: value, currency: currency)
        }
        return ReceiptFields(merchant: merchant, purchaseDate: date, currency: currency,
            items: lines.filter { $0.kind == "purchase" }.map {
                ReceiptLine(id: $0.id, description: $0.description, quantity: $0.quantity,
                            amount: money($0.amount), sourceLineIDs: $0.sourceLineIDs)
            }, adjustments: lines.filter { $0.kind != "purchase" }.map {
                ReceiptAdjustment(id: $0.id, kind: ReceiptAdjustment.Kind(rawValue: $0.kind) ?? .other,
                                  label: $0.description, amount: money($0.amount), sourceLineIDs: $0.sourceLineIDs)
            }, subtotal: money(subtotal), total: money(total))
    }
}

enum ExactInput {
    static let maximumMinorUnits: Int64 = 100_000_000_000
    static func money(_ input: String, scale: UInt8 = 2) -> Int64? {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= 24 else { return nil }
        let negative = text.hasPrefix("-") || text.hasSuffix("-")
        guard !(text.hasPrefix("-") && text.hasSuffix("-")) else { return nil }
        if text.hasPrefix("-") { text.removeFirst() }
        if text.hasSuffix("-") { text.removeLast() }
        if text.hasPrefix("$") { text.removeFirst() }
        if text.contains(",") {
            guard ReceiptParser.first(#"^\d{1,3}(?:,\d{3})+(?:\.\d{1,6})?$"#, text) == text else { return nil }
            text = text.replacingOccurrences(of: ",", with: "")
        }
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count <= 2, !parts[0].isEmpty,
              parts.allSatisfy({ $0.utf8.allSatisfy { (48...57).contains($0) } }),
              parts.count == 1 || (!parts[1].isEmpty && parts[1].count <= Int(scale)),
              let whole = Int64(parts[0]), scale <= 6 else { return nil }
        let multiplier = (0..<scale).reduce(Int64(1)) { value, _ in value * 10 }
        let (base, overflow) = whole.multipliedReportingOverflow(by: multiplier)
        guard !overflow else { return nil }
        let fraction = parts.count == 2 ? String(parts[1]) : ""
        let tail = Int64(fraction + String(repeating: "0", count: Int(scale) - fraction.count)) ?? 0
        let (sum, addedOverflow) = base.addingReportingOverflow(tail)
        guard !addedOverflow, sum <= maximumMinorUnits else { return nil }
        return negative ? -sum : sum
    }
    static func decimal(_ input: String) -> ReceiptDecimal? {
        let parts = input.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ".", omittingEmptySubsequences: false)
        guard !parts.isEmpty, parts.count <= 2, !parts[0].isEmpty,
              parts.allSatisfy({ !$0.isEmpty && $0.utf8.allSatisfy { (48...57).contains($0) } }),
              (parts.count == 1 || parts[1].count <= 9), let coefficient = Int64(parts.joined()), coefficient > 0 else { return nil }
        return try? ReceiptDecimal(coefficient: coefficient, scale: UInt8(parts.count == 2 ? parts[1].count : 0))
    }
    static func format(_ value: Int64, scale: UInt8 = 2) -> String {
        let digits = String(value.magnitude)
        guard scale > 0 else { return (value < 0 ? "-" : "") + digits }
        let padded = String(repeating: "0", count: max(0, Int(scale) + 1 - digits.count)) + digits
        let index = padded.index(padded.endIndex, offsetBy: -Int(scale))
        return (value < 0 ? "-" : "") + padded[..<index] + "." + padded[index...]
    }
    static func quantity(_ value: ReceiptDecimal?) -> String {
        value.map { format($0.coefficient, scale: $0.scale) } ?? ""
    }
    static func date(_ text: String) -> ReceiptDate? {
        let p = text.split(separator: "-")
        guard p.count == 3, p[0].count == 4, let y = Int(p[0]), let m = Int(p[1]), let d = Int(p[2]) else { return nil }
        return try? ReceiptDate(year: y, month: m, day: d)
    }
    static func dateText(_ value: ReceiptDate?) -> String {
        value.map { String(format: "%04d-%02d-%02d", $0.year, $0.month, $0.day) } ?? ""
    }
    static let currencies: [String: UInt8] = ["CAD": 2, "USD": 2, "EUR": 2, "GBP": 2, "CNY": 2, "HKD": 2, "JPY": 0]
    static func currency(_ code: String) -> ReceiptCurrency? {
        guard let scale = currencies[code] else { return nil }
        return try? ReceiptCurrency(code: code, minorUnitScale: scale)
    }
}

enum ReceiptParser {
    static let version = "t05-swift-t03-0.1.1"
    struct Row { var text: String; var ids: [UUID]; var center: Double; var height: Double; var parts: [ReceiptOCRLine] }
    static func matches(_ pattern: String, _ text: String) -> [NSTextCheckingResult] {
        (try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]))?.matches(in: text, range: NSRange(text.startIndex..., in: text)) ?? []
    }
    static func first(_ pattern: String, _ text: String) -> String? {
        guard let match = matches(pattern, text).first, let range = Range(match.range, in: text) else { return nil }
        return String(text[range])
    }
    static func rows(_ lines: [ReceiptOCRLine]) -> [Row] {
        // Without complete geometry, input order is the only trustworthy ordering.
        if lines.contains(where: { $0.boundingBox == nil }) {
            return lines.enumerated().map { index, line in
                Row(text: line.text, ids: [line.id], center: -Double(index), height: 0, parts: [line])
            }
        }
        var groups: [Row] = []
        for line in lines.sorted(by: {
            let a = $0.boundingBox, b = $1.boundingBox
            if a == nil || b == nil { return false }
            let ay = a!.y + a!.height / 2, by = b!.y + b!.height / 2
            return ay == by ? a!.x < b!.x : ay > by
        }) {
            guard let box = line.boundingBox else {
                groups.append(Row(text: line.text, ids: [line.id], center: -Double(groups.count), height: 0, parts: [line])); continue
            }
            let center = box.y + box.height / 2
            if let index = groups.firstIndex(where: { abs($0.center - center) <= min($0.height, box.height) * 0.45 }) {
                groups[index].parts.append(line)
            } else { groups.append(Row(text: "", ids: [], center: center, height: box.height, parts: [line])) }
        }
        return groups.sorted { $0.center > $1.center }.map { group in
            var group = group
            let parts = group.parts.sorted { ($0.boundingBox?.x ?? 0) < ($1.boundingBox?.x ?? 0) }
            group.text = parts.map(\.text).joined(separator: " ")
            group.ids = parts.map(\.id)
            return group
        }
    }
    static func parse(_ observations: [ReceiptOCRLine]) -> ParsedReceipt {
        var result = ParsedReceipt()
        var inItems = false, finished = false
        var pending: Row?
        if observations.contains(where: { $0.boundingBox == nil }) {
            result.issues.append(.init(code: "geometry_incomplete", sourceLineIDs: observations.filter { $0.boundingBox == nil }.map(\.id), detail: nil))
        }
        let moneyPattern = #"(?<![\d.,])(-?\$?(?:\d{1,3}(?:,\d{3})+|\d{1,7})\.\d{2}-?)(?![\d.,])"#
        for row in rows(observations) {
            let text = row.text.trimmingCharacters(in: .whitespacesAndNewlines)
            let upper = text.uppercased()
            if result.merchant == nil, first(#"NO\s*FRILLS|COSTCO|T\s*&\s*T"#, upper) != nil { result.merchant = text }
            if result.currency == nil, first(#"\bCAD\b|CA\$"#, upper) != nil { result.currency = .cad }
            if result.date == nil, let token = first(#"\b(?:20\d{2}[-/]\d{2}[-/]\d{2}|\d{1,2}/\d{1,2}/(?:20)?\d{2}|\d{1,2}-[A-Za-z]{3}-20\d{2})\b"#, text) {
                if token.hasPrefix("20"), token.count == 10 {
                    result.date = ExactInput.date(token.replacingOccurrences(of: "/", with: "-"))
                } else {
                    let format = token.contains("-") ? "d-MMM-yyyy" : (token.split(separator: "/").last?.count == 2 ? "M/d/yy" : "M/d/yyyy")
                    let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
                    formatter.timeZone = TimeZone(secondsFromGMT: 0); formatter.dateFormat = format; formatter.isLenient = false
                    if let date = formatter.date(from: token) {
                        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
                        let c = calendar.dateComponents([.year, .month, .day], from: date)
                        result.date = try? ReceiptDate(year: c.year!, month: c.month!, day: c.day!)
                        if token.contains("/") { result.issues.append(.init(code: "date_order_check", sourceLineIDs: row.ids, detail: nil)) }
                    }
                }
            }
            guard let last = matches(moneyPattern, text).last, let range = Range(last.range, in: text), let amount = ExactInput.money(String(text[range])) else {
                if first(#"\d+[.,]\d+"#, text) != nil { result.issues.append(.init(code: "amount_unparsed_check_source", sourceLineIDs: row.ids, detail: nil)) }
                if inItems && !finished && first(#"\b(?:\d+(?:\.\d+)?\s*(?:KG|LB|X|@)|QTY)\b"#, upper) != nil { pending = row }
                continue
            }
            let prefix = String(text[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
            if first(#"^(?:SUB\s*TOTAL|SOUS[- ]?TOTAL)\b"#, upper) != nil { result.subtotal = amount; finished = true; continue }
            if first(#"^(?:GRAND\s+)?TOTAL\b"#, upper) != nil && first(#"^TOTAL\s+(?:SAVINGS|ITEMS|DISCOUNT)"#, upper) == nil {
                result.total = amount; finished = true; continue
            }
            let tax = first(#"^(?:HST|GST|PST|QST|TPS|TVQ|TAX|TAXES)\b"#, upper) != nil
            let adjustment = first(#"^(?:DISCOUNT|COUPON|SAVINGS|DEPOSIT|ADJUSTMENT)\b"#, upper) != nil
            if finished && !tax && !adjustment { continue }
            if first(#"^(?:CASH|VISA|MASTERCARD|DEBIT|CREDIT|CHANGE|TENDER|BALANCE|SAVINGS|YOU SAVED|MEMBER|REGISTER|AUTH|TRANSACTION)\b"#, upper) != nil { continue }
            guard !prefix.isEmpty, first(#"\p{L}"#, prefix) != nil else { continue }
            if first(#"^\d+(?:\.\d+)?\s*(?:KG|LB|X|@)\b"#, upper) != nil { pending = row; continue }
            var kind = tax ? "tax" : (amount < 0 ? "discount" : "purchase")
            if adjustment { kind = upper.hasPrefix("DEPOSIT") ? "deposit" : (amount < 0 ? "discount" : "other") }
            let qText = first(#"\b\d+(?:\.\d+)?\s*(?:KG|LB|X|@)\s*.*"#, prefix) ?? pending?.text
            let quantity = qText.flatMap { first(#"\d+(?:\.\d+)?"#, $0) }.flatMap(ExactInput.decimal)
            result.lines.append(.init(kind: kind, description: prefix, amount: amount, quantity: quantity, sourceLineIDs: (pending?.ids ?? []) + row.ids))
            pending = nil; inItems = true
        }
        for (missing, code) in [(result.merchant == nil, "merchant_missing"), (result.date == nil, "date_missing"), (result.currency == nil, "currency_missing"), (result.total == nil, "total_missing")] where missing {
            result.issues.append(.init(code: code, sourceLineIDs: [], detail: nil))
        }
        result.issues.append(.init(code: "source_review_required", sourceLineIDs: observations.map(\.id), detail: nil))
        return result
    }
    static func extraction(_ result: OCRResult) throws -> ReceiptExtraction {
        let parsed = parse(result.lines)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return ReceiptExtraction(capturedAt: Date(), recognizer: "Apple Vision accurate", recognizerVersion: String(result.revision),
            parser: "T03 deterministic Swift parser", parserVersion: version, rawOCR: result.lines,
            rawParserOutput: try encoder.encode(parsed), fields: parsed.fields(), issues: parsed.issues)
    }
}
