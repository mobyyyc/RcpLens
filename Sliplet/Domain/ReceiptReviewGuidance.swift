import Foundation

/// Presentation guidance only. Arithmetic and final source confirmation remain separate gates.
struct ReceiptReviewGuidance: Identifiable, Equatable, Sendable {
    enum Target: Equatable, Sendable { case receipt, date, subtotal, total, line(UUID), source }
    let id: String
    let title: String
    let message: String
    let target: Target
    let sourceLineIDs: [UUID]
    let requiresCorrection: Bool

    private static var encoder: JSONEncoder { let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys; return encoder }
    func signature(in draft: ReceiptReviewDraft) -> String {
        switch target {
        case .date: return draft.date
        case .subtotal: return draft.subtotal + "|" + String(draft.subtotalNotPrinted) + "|" + draft.total
        case .total: return draft.total + "|" + draft.subtotal + "|" + String(draft.subtotalNotPrinted)
        case .receipt: return draft.merchant + "|" + draft.date + "|" + draft.currency
        case .line(let id):
            return draft.lines.first { $0.id == id }.flatMap { try? Self.encoder.encode($0).base64EncodedString() } ?? "removed"
        case .source:
            // An unassigned row could be added or attached to any purchase. Any line edit reopens its check.
            return (try? Self.encoder.encode(draft.lines).base64EncodedString()) ?? ""
        }
    }
    func isChecked(in draft: ReceiptReviewDraft) -> Bool {
        guard !requiresCorrection, let saved = draft.guidanceChecks?[id] else { return false }
        return saved == signature(in: draft)
    }
    static func checks(draft: ReceiptReviewDraft, extraction: ReceiptExtraction?) -> [Self] {
        var result: [Self] = []
        func append(_ id: String, _ title: String, _ message: String, _ target: Target, _ ids: [UUID] = [], required: Bool = true) {
            result.append(Self(id: id, title: title, message: message, target: target, sourceLineIDs: ids, requiresCorrection: required))
        }
        if draft.merchant.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || ExactInput.currency(draft.currency) == nil {
            append("receipt", "Complete receipt details", "Check the merchant and currency against the original.", .receipt)
        }
        if ExactInput.date(draft.date) == nil { append("date", "Choose the printed date", "Use the purchase date, including the printed year.", .date) }
        if (!draft.subtotal.isEmpty && draft.fields.subtotal == nil) || (draft.subtotal.isEmpty && !draft.subtotalNotPrinted) {
            append("subtotal", "Check the subtotal", "Enter the printed subtotal, or confirm it is not printed.", .subtotal)
        }
        if draft.fields.total == nil { append("total", "Enter the printed total", "Use the receipt total, not tender, change or savings.", .total) }
        let scale = ExactInput.currency(draft.currency)?.minorUnitScale ?? 2
        for (index, line) in draft.lines.enumerated() {
            let amount = ExactInput.money(line.amount, scale: scale)
            if line.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || amount == nil
                || (!line.quantity.isEmpty && ExactInput.decimal(line.quantity) == nil)
                || (line.kind == "discount" && (amount ?? 0) > 0) {
                append("line-" + line.id.uuidString, "Check line \(index + 1)", "Check the description, printed amount and any quantity. Discounts are negative; unknown quantities stay blank.", .line(line.id), line.sourceLineIDs)
            }
        }
        if draft.lines.isEmpty { append("purchases", "Add missing purchases", "Read each purchase from the original; recognition may have missed lines.", .source) }
        // Group warnings by action and linked line, conserving every issue source ID while avoiding header-by-header alerts.
        var groups: [Self] = []
        for issue in extraction?.issues ?? [] {
            let title: String, message: String, target: Target
            switch issue.code {
            case "date_order_check", "date_conflicting", "date_ambiguous":
                title = "Verify the printed date"; message = "Check the year and month/day order. Recognition found uncertain date evidence."; target = .date
            case "subtotal_conflicting":
                title = "Verify the printed subtotal"; message = "More than one subtotal was read. Compare the printed subtotal."; target = .subtotal
            case "total_conflicting", "summary_amount_ambiguous":
                title = "Verify printed totals"; message = "The summary amounts are uncertain. Compare subtotal and total with the original."; target = .total
            case "quantity_association_check", "quantity_association_uncertain":
                title = "Check quantity and line amount"; message = "Check which item this quantity belongs to. Use the printed extension; leave unknown quantities blank."; target = .source
            case "adjustment_sign_check":
                title = "Check the adjustment"; message = "Verify whether this is a discount, tax or fee and check its printed sign."; target = .source
            case "unpriced_source_row":
                title = "Check unassigned text"; message = "Some text has no linked amount. Check for a missing purchase or wrapped description; store headers need no purchase."; target = .source
            case "unpaired_amount", "amount_unparsed_check_source", "item_amount_ambiguous", "extension_missing":
                title = "Check unassigned amounts"; message = "Check the printed item and its full line amount. A unit price must not replace a missing line amount."; target = .source
            case "geometry_incomplete": continue // Source viewer truthfully explains missing coordinates.
            default: continue
            }
            let originalLines = (extraction?.fields.items.map { ($0.id, $0.sourceLineIDs) } ?? [])
                + (extraction?.fields.adjustments.map { ($0.id, $0.sourceLineIDs) } ?? [])
            let linked = originalLines.first { !Set($0.1).isDisjoint(with: issue.sourceLineIDs) }
            // Corrections can attach previously unassigned evidence. Keep its group identity stable.
            let linkedID = linked?.0
            let eligibleID = linkedID.flatMap { id in draft.lines.contains { $0.id == id } ? id : nil }
            let actualTarget = target == .source && issue.code != "unpriced_source_row" ? eligibleID.map { Target.line($0) } ?? target : target
            let targetKey = target == .source && issue.code != "unpriced_source_row" ? linkedID?.uuidString ?? "source" : "source"
            let key = "evidence-" + title + "-" + targetKey
            if let i = groups.firstIndex(where: { $0.id == key }) {
                let old = groups[i]
                groups[i] = Self(id: key, title: title, message: message, target: actualTarget,
                    sourceLineIDs: Array(Set(old.sourceLineIDs + issue.sourceLineIDs)).sorted { $0.uuidString < $1.uuidString }, requiresCorrection: false)
            } else {
                groups.append(Self(id: key, title: title, message: message, target: actualTarget,
                    sourceLineIDs: issue.sourceLineIDs, requiresCorrection: false))
            }
        }
        result += groups
        if let difference = draft.reconciliation.difference, difference != 0 {
            append("difference", "Check the difference", "Compare every purchase and adjustment with the original. Matching totals alone never confirms accuracy.", .total)
        }
        return result
    }
}


/// Permit fixing one typed error without making unrelated existing errors block progress.
/// New or changed typed values must be valid (or deliberately blank); Save draft remains stricter.
enum ReceiptFocusedCorrection {
    static func canApply(_ input: ReceiptReviewDraft, replacing baseline: ReceiptReviewDraft) -> Bool {
        if input.date != baseline.date && !input.date.isEmpty && ExactInput.date(input.date) == nil { return false }
        if input.currency != baseline.currency && !input.currency.isEmpty && ExactInput.currency(input.currency) == nil { return false }
        let scale = ExactInput.currency(input.currency)?.minorUnitScale ?? 2
        for (value, old) in [(input.subtotal, baseline.subtotal), (input.total, baseline.total)] {
            if value != old && !value.isEmpty && ExactInput.money(value, scale: scale) == nil { return false }
        }
        for line in input.lines {
            let old = baseline.lines.first { $0.id == line.id }
            if line.amount != old?.amount && !line.amount.isEmpty && ExactInput.money(line.amount, scale: scale) == nil { return false }
            if line.quantity != old?.quantity && !line.quantity.isEmpty && ExactInput.decimal(line.quantity) == nil { return false }
        }
        return true
    }
}
