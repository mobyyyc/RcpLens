import Foundation

/// Evaluation-only alternatives. Never discard or rewrite source observations.
enum LayoutExperiment {
    static var mode = "baseline"
    static var documentRows: [[UUID]] = []
    static let money = #"(?<![\d.,])(-?\$?(?:\d{1,3}(?:,\d{3})+|\d{1,7})\.\d{2}-?)(?![\d.,])"#

    static func row(_ parts: [ReceiptOCRLine]) -> ReceiptParser.Row {
        let ordered = parts.sorted { ($0.boundingBox?.x ?? 0) < ($1.boundingBox?.x ?? 0) }
        let boxes = ordered.compactMap(\.boundingBox)
        return .init(text: ordered.map(\.text).joined(separator: " "), ids: ordered.map(\.id),
                     center: boxes.map { $0.y + $0.height / 2 }.max() ?? 0,
                     height: boxes.map(\.height).min() ?? 0, parts: ordered)
    }

    static func rows(_ lines: [ReceiptOCRLine]) -> [ReceiptParser.Row] {
        let baseline = ReceiptParser.rows(lines)
        guard lines.allSatisfy({ $0.boundingBox != nil }) else { return baseline }
        if mode == "text-column-association" { return columns(baseline) }
        if mode == "document-tables" {
            let indexed = Dictionary(uniqueKeysWithValues: lines.map { ($0.id, $0) })
            let ids = documentRows.flatMap { $0 }
            // Duplicated/unknown cell membership is ambiguous: retain line grouping.
            guard Set(ids).count == ids.count, ids.allSatisfy({ indexed[$0] != nil }) else { return baseline }
            let claimed = Set(ids)
            let structured = documentRows.map { row($0.compactMap { indexed[$0] }) }
            let remaining = ReceiptParser.rows(lines.filter { !claimed.contains($0.id) })
            return (structured + remaining).sorted { $0.center > $1.center }
        }
        guard mode == "text-association" || mode == "document-association" else { return baseline }
        // Consider only detached price-only rows and descriptions without a price.
        // All candidates must be horizontally disjoint and within one text height.
        let prices = baseline.indices.filter { i in
            let text = baseline[i].text.trimmingCharacters(in: .whitespaces)
            return ReceiptParser.first("^" + money + #"\s*[A-Z]?$"#, text) != nil
        }
        let descriptions = baseline.indices.filter { i in
            ReceiptParser.first(money, baseline[i].text) == nil &&
            ReceiptParser.first(#"\p{L}"#, baseline[i].text) != nil
        }
        func distance(_ p: Int, _ d: Int) -> Double? {
            let price = baseline[p], desc = baseline[d]
            let pb = price.parts.compactMap(\.boundingBox), db = desc.parts.compactMap(\.boundingBox)
            guard let left = pb.map(\.x).min(), let right = db.map({ $0.x + $0.width }).max(),
                  right < left, min(price.height, desc.height) > 0 else { return nil }
            let delta = abs(price.center - desc.center) / min(price.height, desc.height)
            return delta <= 1.0 ? delta : nil
        }
        func uniqueBest(_ options: [(Int, Double)]) -> Int? {
            let sorted = options.sorted { $0.1 < $1.1 }
            guard let first = sorted.first else { return nil }
            // Close alternatives are ambiguous even when one is slightly nearer.
            if sorted.count > 1 && sorted[1].1 - first.1 < 0.25 { return nil }
            return first.0
        }
        var attached: [Int: Int] = [:]
        for p in prices {
            let candidates = descriptions.compactMap { d in distance(p, d).map { (d, $0) } }
            guard let d = uniqueBest(candidates),
                  uniqueBest(prices.compactMap { q in distance(q, d).map { (q, $0) } }) == p else { continue }
            attached[p] = d
        }
        let removed = Set(attached.keys)
        return baseline.indices.filter { !removed.contains($0) }.map { i in
            guard let p = attached.first(where: { $0.value == i })?.key else { return baseline[i] }
            return row(baseline[i].parts + baseline[p].parts)
        }.sorted { $0.center > $1.center }
    }

    static func columns(_ baseline: [ReceiptParser.Row]) -> [ReceiptParser.Row] {
        func isPrice(_ line: ReceiptOCRLine) -> Bool {
            ReceiptParser.first("^" + money + #"\s*[A-Z]?$"#, line.text.trimmingCharacters(in: .whitespaces)) != nil
        }
        let prices = baseline.flatMap(\.parts).filter(isPrice)
        let owner = Dictionary(uniqueKeysWithValues: baseline.enumerated().flatMap { i, r in r.parts.map { ($0.id, i) } })
        let stripped = baseline.map { row($0.parts.filter { !isPrice($0) }) }
        func distance(_ price: ReceiptOCRLine, _ index: Int) -> Double? {
            let desc = stripped[index]
            guard !desc.parts.isEmpty, ReceiptParser.first(money, desc.text) == nil,
                  ReceiptParser.first(#"\p{L}"#, desc.text) != nil,
                  let pb = price.boundingBox,
                  let right = desc.parts.compactMap(\.boundingBox).map({ $0.x+$0.width }).max(), right < pb.x,
                  desc.height > 0 else { return nil }
            let delta = abs(pb.y + pb.height / 2 - desc.center) / min(pb.height, desc.height)
            return delta <= 1.0 ? delta : nil
        }
        func unique<T>(_ candidates: [(T, Double)]) -> T? {
            let sorted = candidates.sorted { $0.1 < $1.1 }
            guard let first = sorted.first else { return nil }
            if sorted.count > 1 && sorted[1].1-first.1 < 0.25 { return nil }
            return first.0
        }
        var assignment: [UUID: Int] = [:]
        for price in prices {
            guard let index = unique(stripped.indices.compactMap { i in distance(price, i).map { (i, $0) } }),
                  unique(prices.compactMap { p in distance(p, index).map { (p.id, $0) } }) == price.id else { continue }
            assignment[price.id] = index
        }
        // Unmatched prices retain their original group. If that conflicts with a
        // proposed move, fall back for the entire image rather than combine prices.
        var occupied = Set<Int>()
        for price in prices {
            let target = assignment[price.id] ?? owner[price.id]!
            if !occupied.insert(target).inserted { return baseline }
        }
        var parts = baseline.map { $0.parts.filter { !isPrice($0) } }
        for price in prices { parts[assignment[price.id] ?? owner[price.id]!].append(price) }
        return parts.filter { !$0.isEmpty }.map(row).sorted { $0.center > $1.center }
    }
}
