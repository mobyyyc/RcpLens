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
    static let version = "p2-03-deterministic-0.2.0"
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
    static let moneyPattern = #"(?<![\d.,])(-?\$?(?:\d{1,3}(?:,\d{3})+|\d{1,7})\.\d{2}-?)(?![\d.,])"#
    static let quantityPattern = #"\b\d+(?:\.\d+)?\s*(?:(?:KG|LB|LBS|X)\b|@)"#
    static let summaryPattern = #"^(?:(?:GRAND\s+)?TOTAL|SUB\s*TOTAL|SOUS[- ]?TOTAL)\b"#
    static let metadataPattern = #"^(?:CASH|VISA|MASTERCARD|DEBIT|CREDIT|CHANGE|TENDER|BALANCE|SAVINGS|YOU SAVED|MEMBER|REGISTER|AUTH|TRANSACTION|STORE|TERMINAL|TEL|PHONE|DATE|TIME|ITEMS SOLD|TOTAL ITEMS|TOTAL SAVINGS|TOTAL DISCOUNT)\b"#

    /// Strip decoration for field classification only; purchase descriptions/SKUs stay intact.
    static func fieldText(_ text: String) -> String {
        text.replacingOccurrences(of: #"^[\s*:=]+"#, with: "", options: .regularExpression).uppercased()
    }
    static func merchant(_ text: String) -> String? {
        guard let token = first(#"NO\s*FRILLS\b|\bCOSTCO\b|\bT\s*&\s*T\b"#, text) else { return nil }
        // Fictional test identities remain visibly fictional in the normal wallet.
        if first(#"\b(?:DEMO|SYNTHETIC|FICTIONAL)\b"#, text) != nil { return text }
        if first(#"NO\s*FRILLS"#, token) != nil { return "NOFRILLS" }
        if first("COSTCO", token) != nil { return "COSTCO" }
        return "T&T SUPERMARKET"
    }
    static func dateCandidates(_ text: String, noFrills: Bool = false) -> [(ReceiptDate, Bool)] {
        let pattern = #"\b(?:20\d{2}[-/]\d{2}[-/]\d{2}|\d{1,2}/\d{1,2}/(?:20)?\d{2}|\d{1,2}-[A-Za-z]{3}-20\d{2})\b"#
        return matches(pattern, text).flatMap { match -> [(ReceiptDate, Bool)] in
            guard let range = Range(match.range, in: text) else { return [] }
            let token = String(text[range])
            if token.hasPrefix("20"), token.count == 10 {
                return ExactInput.date(token.replacingOccurrences(of: "/", with: "-")).map { [($0, false)] } ?? []
            }
            if token.contains("/") {
                let parts = token.split(separator: "/").compactMap { Int($0) }
                guard parts.count == 3 else { return [] }
                let year = parts[2] < 100 ? 2000 + parts[2] : parts[2]
                let dayFirst = parts[0] > 12 && parts[1] <= 12
                let ordinary = try? ReceiptDate(year: year, month: dayFirst ? parts[1] : parts[0],
                                                day: dayFirst ? parts[0] : parts[1])
                if noFrills && token.split(separator: "/").last?.count == 2 {
                    let yearFirst = try? ReceiptDate(year: 2000 + parts[0], month: parts[1], day: parts[2])
                    // Audited No Frills transaction timestamps use YY/MM/DD with a printed clock.
                    // A bare short date does not establish that format; competing valid readings stay unknown.
                    if let yearFirst, first(#"\b\d{1,2}:\d{2}(?::\d{2})?\b|YY/MM/DD"#, text) != nil { return [(yearFirst, true)] }
                    if let yearFirst, let ordinary, yearFirst != ordinary { return [(yearFirst, true), (ordinary, true)] }
                    return (ordinary ?? yearFirst).map { [($0, true)] } ?? []
                }
                return ordinary.map { [($0, true)] } ?? []
            }
            let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0); formatter.dateFormat = "d-MMM-yyyy"; formatter.isLenient = false
            guard let date = formatter.date(from: token) else { return [] }
            var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
            let c = calendar.dateComponents([.year, .month, .day], from: date)
            return (try? ReceiptDate(year: c.year!, month: c.month!, day: c.day!)).map { [($0, false)] } ?? []
        }
    }

    /// Interpret an unpriced description and a separate single printed amount only when geometry
    /// gives a unique local pair. Existing priced rows and original grouping remain untouched.
    static func interpretationRows(_ input: [Row], knownRetailer: Bool) -> [Row] {
        guard knownRetailer, input.allSatisfy({ $0.height > 0 }) else { return input }
        func isPrice(_ r: Row) -> Bool {
            guard matches(moneyPattern, r.text).count == 1, let token = first(moneyPattern, r.text) else { return false }
            let rest = r.text.replacingOccurrences(of: token, with: "").trimmingCharacters(in: .whitespaces)
            return rest.isEmpty || first(#"^[AEHN]$"#, rest) != nil
        }
        func isDescription(_ r: Row) -> Bool {
            let t = fieldText(r.text)
            return matches(moneyPattern, r.text).isEmpty && first(#"\p{L}"#, t) != nil
                && first(quantityPattern, t) == nil && first(metadataPattern, t) == nil
                // A detached numeric-leading row can be a SKU, quantity or promotion code. Leave it uncertain.
                && first(#"^\d"#, t) == nil
                && merchant(r.text) == nil && dateCandidates(r.text).isEmpty
                && first(#"\bCAD\b|CA\$|^\d+\s+(?:ST|AVE|ROAD|RD)\b"#, t) == nil
        }
        let prices = input.indices.filter { isPrice(input[$0]) }
        let descriptions = input.indices.filter { isDescription(input[$0]) }
        func distance(_ d: Int, _ p: Int) -> Double? {
            let a = input[d], b = input[p]
            guard let right = a.parts.compactMap(\.boundingBox).map({ $0.x + $0.width }).max(),
                  let left = b.parts.compactMap(\.boundingBox).map(\.x).min(), left > right,
                  abs(a.center - b.center) <= min(a.height, b.height) else { return nil }
            if input.indices.contains(where: { $0 != d && $0 != p && input[$0].center > min(a.center, b.center)
                && input[$0].center < max(a.center, b.center) }) { return nil }
            return abs(a.center - b.center) / min(a.height, b.height)
        }
        func nearest(_ target: Int, _ choices: [Int], reversed: Bool) -> Int? {
            let candidates = choices.compactMap { i -> (Int, Double)? in
                (reversed ? distance(target, i) : distance(i, target)).map { (i, $0) }
            }.sorted { $0.1 < $1.1 }
            guard let best = candidates.first, candidates.count == 1 || candidates[1].1 - best.1 > 0.25 else { return nil }
            return best.0
        }
        var merged: [Int: Row] = [:], consumed = Set<Int>()
        for p in prices {
            guard let d = nearest(p, descriptions, reversed: false), nearest(d, prices, reversed: true) == p else { continue }
            var row = input[d]; row.text += " " + input[p].text; row.ids += input[p].ids; row.parts += input[p].parts
            merged[d] = row; consumed.insert(p)
        }
        return input.indices.compactMap { consumed.contains($0) ? nil : (merged[$0] ?? input[$0]) }
    }

    static func extensionMatches(_ quantity: ReceiptDecimal, rate: Int64, amount: Int64) -> Bool {
        guard rate >= 0, amount >= 0 else { return false }
        let (product, overflow) = rate.multipliedReportingOverflow(by: quantity.coefficient)
        let divisor = (0..<quantity.scale).reduce(Int64(1)) { value, _ in value * 10 }
        guard !overflow else { return false }
        // Check the printed extension using exact rational half-up cent rounding; never fill a missing price.
        let rounded = product / divisor + (2 * (product % divisor) >= divisor ? 1 : 0)
        return rounded == amount
    }
    static func linkedQuantity(_ rateRow: Row, purchase: Row, amount: Int64) -> ReceiptDecimal? {
        guard rateRow.height > 0, purchase.height > 0, rateRow.center > purchase.center,
              rateRow.center - purchase.center <= 2 * min(rateRow.height, purchase.height),
              let q = first(quantityPattern, rateRow.text).flatMap({ first(#"\d+(?:\.\d+)?"#, $0) }).flatMap(ExactInput.decimal),
              matches(moneyPattern, rateRow.text).count == 1,
              let rate = first(moneyPattern, rateRow.text).flatMap({ ExactInput.money($0) }),
              extensionMatches(q, rate: rate, amount: amount) else { return nil }
        return q
    }

    static func parse(_ observations: [ReceiptOCRLine]) -> ParsedReceipt {
        var result = ParsedReceipt()
        let grouped = rows(observations)
        result.merchant = grouped.prefix { matches(moneyPattern, $0.text).isEmpty }.compactMap { merchant($0.text) }.first
        var finished = false, pendingQuantity: Row?
        var totals: [(Int64, [UUID])] = [], subtotals: [(Int64, [UUID])] = []
        var totalAmbiguous = false, subtotalAmbiguous = false
        var dates: [(ReceiptDate, [UUID])] = []
        func issue(_ code: String, _ ids: [UUID]) { result.issues.append(.init(code: code, sourceLineIDs: ids, detail: nil)) }
        if observations.contains(where: { $0.boundingBox == nil }) {
            issue("geometry_incomplete", observations.filter { $0.boundingBox == nil }.map(\.id))
        }
        for row in interpretationRows(grouped, knownRetailer: result.merchant != nil) {
            let text = row.text.trimmingCharacters(in: .whitespacesAndNewlines), upper = fieldText(text)
            // Pending quantity belongs only to the next purchase; every intervening boundary clears it.
            let previousQuantity = pendingQuantity; pendingQuantity = nil
            var quantityLinked = false
            defer { if let previousQuantity, !quantityLinked { issue("quantity_association_uncertain", previousQuantity.ids) } }
            if result.currency == nil, first(#"\bCAD\b|CA\$"#, upper) != nil { result.currency = .cad }
            let candidates = dateCandidates(text, noFrills: result.merchant.map { first("NO\\s*FRILLS", $0) != nil } ?? false)
            for (date, orderCheck) in candidates {
                dates.append((date, row.ids)); if orderCheck { issue("date_order_check", row.ids) }
            }
            if (merchant(text) != nil && matches(moneyPattern, text).isEmpty) || !candidates.isEmpty { continue }
            let tokens = matches(moneyPattern, text)
            let summary = first(summaryPattern, upper) != nil && first(#"^TOTAL\s+(?:SAVINGS|ITEMS|DISCOUNT)"#, upper) == nil
            let tax = first(#"^(?:HST|GST|PST|QST|TPS|TVQ|TAX|TAXES)\b"#, upper) != nil
            let adjustment = first(#"^(?:DISCOUNT|COUPON|DEPOSIT|ADJUSTMENT)\b"#, upper) != nil
            if summary && !tokens.isEmpty { finished = true }
            if first(metadataPattern, upper) != nil { continue }
            if finished && !summary && !tax && !adjustment { continue }
            guard let last = tokens.last, let range = Range(last.range, in: text),
                  let amount = ExactInput.money(String(text[range])) else {
                if first(#"\d+[.,]\d+"#, text) != nil { issue("amount_unparsed_check_source", row.ids) }
                if first(#"^\d+(?:\.\d+)?\s*(?:(?:KG|LB|LBS|X)\b|@)"#, upper) != nil && !finished { pendingQuantity = row }
                else if !finished && !summary && first(#"\p{L}"#, text) != nil { issue("unpriced_source_row", row.ids) }
                continue
            }
            let prefix = String(text[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
            if summary {
                guard tokens.count == 1 else {
                    issue("summary_amount_ambiguous", row.ids)
                    if first(#"^(?:SUB\s*TOTAL|SOUS[- ]?TOTAL)\b"#, upper) != nil { subtotalAmbiguous = true }
                    else { totalAmbiguous = true }
                    continue
                }
                if first(#"^(?:SUB\s*TOTAL|SOUS[- ]?TOTAL)\b"#, upper) != nil { subtotals.append((amount, row.ids)) }
                else { totals.append((amount, row.ids)) }
                continue
            }
            // A standalone rate never supplies a purchase or a calculated extension.
            if first(#"^\d+(?:\.\d+)?\s*(?:(?:KG|LB|LBS|X)\b|@)"#, upper) != nil { pendingQuantity = row; continue }
            guard !prefix.isEmpty, first(#"\p{L}"#, prefix) != nil else { issue("unpaired_amount", row.ids); continue }
            let inlineQuantity = first(quantityPattern, prefix)
            let inlineRate = inlineQuantity.map { first(#"(?:\bX\b|@)"#, $0) != nil } ?? false
            if tokens.count > 1 {
                guard tokens.count == 2, let qText = inlineQuantity,
                      let q = first(#"\d+(?:\.\d+)?"#, qText).flatMap(ExactInput.decimal),
                      let qRange = prefix.range(of: qText), let rateRange = Range(tokens[0].range, in: text),
                      qRange.upperBound <= rateRange.lowerBound,
                      let rate = ExactInput.money(String(text[rateRange])), extensionMatches(q, rate: rate, amount: amount) else {
                    issue("item_amount_ambiguous", row.ids); continue
                }
            } else if inlineRate { issue("extension_missing", row.ids); continue }
            let suffix = String(text[range.upperBound...]).trimmingCharacters(in: .whitespaces)
            if !suffix.isEmpty && first(#"^[AEHN]$"#, suffix) == nil { issue("item_amount_ambiguous", row.ids); continue }
            var quantity = inlineQuantity.flatMap { first(#"\d+(?:\.\d+)?"#, $0) }.flatMap(ExactInput.decimal)
            var qIDs: [UUID] = []
            if let previousQuantity, inlineQuantity == nil, !tax, !adjustment, amount >= 0 {
                if let q = linkedQuantity(previousQuantity, purchase: row, amount: amount) {
                    quantity = q; qIDs = previousQuantity.ids; quantityLinked = true
                    issue("quantity_association_check", previousQuantity.ids + row.ids)
                }
            }
            var kind = tax ? "tax" : (amount < 0 ? "discount" : "purchase")
            if adjustment { kind = upper.hasPrefix("DEPOSIT") ? "deposit" : (amount < 0 ? "discount" : "other") }
            if adjustment && amount >= 0 && !upper.hasPrefix("DEPOSIT") { issue("adjustment_sign_check", row.ids) }
            result.lines.append(.init(kind: kind, description: prefix, amount: amount, quantity: quantity, sourceLineIDs: qIDs + row.ids))
        }
        if let pendingQuantity { issue("quantity_association_uncertain", pendingQuantity.ids) }
        func resolved(_ values: [(Int64, [UUID])], code: String) -> Int64? {
            guard let value = values.first?.0 else { return nil }
            guard values.allSatisfy({ $0.0 == value }) else { issue(code, Array(Set(values.flatMap { $0.1 })).sorted { $0.uuidString < $1.uuidString }); return nil }
            return value
        }
        result.subtotal = subtotalAmbiguous ? nil : resolved(subtotals, code: "subtotal_conflicting")
        result.total = totalAmbiguous ? nil : resolved(totals, code: "total_conflicting")
        if let date = dates.first?.0 {
            if dates.allSatisfy({ $0.0 == date }) { result.date = date } else { issue("date_conflicting", Array(Set(dates.flatMap { $0.1 })).sorted { $0.uuidString < $1.uuidString }) }
        }
        for (missing, code) in [(result.merchant == nil, "merchant_missing"), (result.date == nil, "date_missing"), (result.currency == nil, "currency_missing"), (result.total == nil, "total_missing")] where missing { issue(code, []) }
        issue("source_review_required", observations.map(\.id))
        return result
    }
    static func extraction(_ result: OCRResult) throws -> ReceiptExtraction {
        let parsed = parse(result.lines)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return ReceiptExtraction(capturedAt: Date(), recognizer: "Apple Vision accurate", recognizerVersion: String(result.revision),
            parser: "Deterministic retailer Swift parser", parserVersion: version, rawOCR: result.lines,
            rawParserOutput: try encoder.encode(parsed), fields: parsed.fields(), issues: parsed.issues)
    }
}
