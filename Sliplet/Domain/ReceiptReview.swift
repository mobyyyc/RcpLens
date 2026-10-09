import Foundation

struct EditableReceiptLine: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var kind: String
    var name: String
    var quantity: String
    var amount: String
    var sourceLineIDs: [UUID]
    var sku: String? = nil
    var unitPrice: ReceiptMoney? = nil
    var taxMarker: String? = nil
    var rate: ReceiptDecimal? = nil
    static func blank(kind: String = "purchase") -> Self {
        .init(id: UUID(), kind: kind, name: "", quantity: "", amount: "", sourceLineIDs: [])
    }
}

struct ReceiptReviewDraft: Codable, Equatable, Sendable {
    var merchant = ""
    var date = ""
    var currency = ""
    var lines: [EditableReceiptLine] = []
    var subtotal = ""
    var total = ""
    var subtotalNotPrinted = false
    var sourceOpened = false
    var sourceChecked = false
    /// Optional for backward-compatible decoding of installed drafts. Checks are scoped to current values.
    var guidanceChecks: [String: String]? = nil

    init() {}
    init(parsed: ParsedReceipt) {
        merchant = parsed.merchant ?? ""; date = ExactInput.dateText(parsed.date)
        currency = parsed.currency?.code ?? ""
        subtotal = parsed.subtotal.map { ExactInput.format($0) } ?? ""
        total = parsed.total.map { ExactInput.format($0) } ?? ""
        lines = parsed.lines.map {
            EditableReceiptLine(id: $0.id, kind: $0.kind, name: $0.description,
                quantity: ExactInput.quantity($0.quantity), amount: ExactInput.format($0.amount), sourceLineIDs: $0.sourceLineIDs)
        }
    }
    init(fields: ReceiptFields) {
        merchant = fields.merchant ?? ""; date = ExactInput.dateText(fields.purchaseDate); currency = fields.currency?.code ?? ""
        func text(_ value: ReceiptMoney?) -> String { value.map { ExactInput.format($0.minorUnits, scale: $0.currency.minorUnitScale) } ?? "" }
        subtotal = text(fields.subtotal); total = text(fields.total)
        lines = fields.items.map {
            EditableReceiptLine(id: $0.id, kind: "purchase", name: $0.description ?? "", quantity: ExactInput.quantity($0.quantity),
                amount: text($0.amount), sourceLineIDs: $0.sourceLineIDs, sku: $0.sku, unitPrice: $0.unitPrice, taxMarker: $0.taxMarker)
        } + fields.adjustments.map {
            EditableReceiptLine(id: $0.id, kind: $0.kind.rawValue, name: $0.label ?? "", quantity: "", amount: text($0.amount),
                sourceLineIDs: $0.sourceLineIDs, rate: $0.rate)
        }
    }
    var fields: ReceiptFields {
        let c = ExactInput.currency(currency)
        func money(_ value: String) -> ReceiptMoney? {
            guard let c, let cents = ExactInput.money(value, scale: c.minorUnitScale) else { return nil }
            return ReceiptMoney(minorUnits: cents, currency: c)
        }
        return ReceiptFields(merchant: merchant.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            purchaseDate: ExactInput.date(date), currency: c,
            items: lines.filter { $0.kind == "purchase" }.map {
                ReceiptLine(id: $0.id, description: $0.name.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                    sku: $0.sku, quantity: ExactInput.decimal($0.quantity),
                    unitPrice: $0.unitPrice?.currency == c ? $0.unitPrice : nil, amount: money($0.amount),
                    taxMarker: $0.taxMarker, sourceLineIDs: $0.sourceLineIDs)
            }, adjustments: lines.filter { $0.kind != "purchase" }.map {
                ReceiptAdjustment(id: $0.id, kind: ReceiptAdjustment.Kind(rawValue: $0.kind) ?? .other,
                    label: $0.name.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty, amount: money($0.amount),
                    rate: $0.rate, sourceLineIDs: $0.sourceLineIDs)
            }, subtotal: money(subtotal), total: money(total))
    }
    var reconciliation: ReceiptReconciliation {
        var issues: [String] = []
        let f = fields
        if f.merchant == nil { issues.append("Merchant is missing.") }
        if f.purchaseDate == nil { issues.append("Choose the printed purchase date.") }
        if f.currency == nil { issues.append("Choose the currency printed on the receipt, or verify it with the store.") }
        if f.items.isEmpty { issues.append("Add the missing purchases.") }
        if lines.contains(where: { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) { issues.append("Each line needs a description.") }
        if lines.contains(where: { !$0.quantity.isEmpty && ExactInput.decimal($0.quantity) == nil }) { issues.append("Quantities must be positive decimals (for example 1 or 0.375).") }
        let scale = f.currency?.minorUnitScale ?? 2
        if lines.contains(where: { ExactInput.money($0.amount, scale: scale) == nil }) { issues.append("Every line needs a valid printed amount.") }
        if lines.contains(where: { $0.kind == "discount" && (ExactInput.money($0.amount, scale: scale) ?? 0) > 0 }) { issues.append("Enter discounts as negative amounts.") }
        if f.total == nil { issues.append("The printed total is missing or invalid.") }
        if !subtotal.isEmpty && f.subtotal == nil { issues.append("The subtotal is invalid.") }
        if subtotal.isEmpty && !subtotalNotPrinted { issues.append("Enter the printed subtotal or confirm that it is not printed.") }
        var difference: Int64?
        var subtotalNote: String?
        do {
            try f.validate()
            if let c = f.currency, f.items.allSatisfy({ $0.amount != nil }), f.adjustments.allSatisfy({ $0.amount != nil }), let total = f.total {
                let zero = ReceiptMoney(minorUnits: 0, currency: c)
                let purchaseSum = try f.items.reduce(zero) { try $0.adding($1.amount!) }
                let all = try f.adjustments.reduce(purchaseSum) { try $0.adding($1.amount!) }
                difference = try total.subtracting(all).minorUnits
                if difference != 0 { issues.append("Line amounts and adjustments do not match the printed total.") }
                if let subtotal = f.subtotal {
                    let discounted = try f.adjustments.filter { $0.kind == .discount }.reduce(purchaseSum) { try $0.adding($1.amount!) }
                    if subtotal == purchaseSum { subtotalNote = "Subtotal matches purchases before separate discounts." }
                    else if subtotal == discounted { subtotalNote = "Subtotal matches purchases after separate discounts." }
                    else {
                        let nonTax = try f.adjustments.filter { $0.kind != .tax && $0.kind != .tip }.reduce(purchaseSum) { try $0.adding($1.amount!) }
                        if subtotal == nonTax { subtotalNote = "Subtotal matches purchases and all separate non-tax adjustments (excluding tips)." }
                        else { issues.append("Subtotal does not match purchases before or after the printed non-tax adjustments. Check source lines and classifications.") }
                    }
                }
            }
        } catch { issues.append("These values exceed supported arithmetic bounds or use inconsistent currencies.") }
        return ReceiptReconciliation(issues: issues, difference: difference, subtotalNote: subtotalNote)
    }
    var canFinalize: Bool { reconciliation.issues.isEmpty && sourceOpened && sourceChecked }
    /// Drafts allow missing fields, never malformed typed values that would be silently discarded.
    var canSaveDraft: Bool {
        let scale = ExactInput.currency(currency)?.minorUnitScale ?? 2
        return (date.isEmpty || ExactInput.date(date) != nil)
            && (currency.isEmpty || ExactInput.currency(currency) != nil)
            && (subtotal.isEmpty || ExactInput.money(subtotal, scale: scale) != nil)
            && (total.isEmpty || ExactInput.money(total, scale: scale) != nil)
            && lines.allSatisfy { ($0.amount.isEmpty || ExactInput.money($0.amount, scale: scale) != nil)
                && ($0.quantity.isEmpty || ExactInput.decimal($0.quantity) != nil) }

    }
}

struct ReceiptReconciliation: Equatable, Sendable {
    let issues: [String]
    let difference: Int64?
    let subtotalNote: String?
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

/// This is the gate future splitting must use, in addition to complete participant assignment.
enum ReceiptCompletion {
    static func isComplete(_ record: ReceiptRecord) -> Bool {
        var draft = ReceiptReviewDraft(fields: record.current.fields)
        draft.subtotalNotPrinted = record.current.fields.subtotal == nil
        draft.sourceOpened = true; draft.sourceChecked = record.current.review == .sourceReviewed
        return draft.canFinalize
    }
}

/// Revocation can occur synchronously during a UI lifecycle callback while a store actor is busy.
final class ReceiptOperationPermit: @unchecked Sendable {
    private let lock = NSLock()
    private var valid = true
    func revoke() { lock.lock(); valid = false; lock.unlock() }
    /// Commit and lifecycle revocation are mutually exclusive. A commit already in progress
    /// completes before revocation returns; queued or revoked writes roll back.
    func committing<T>(_ body: () throws -> T) throws -> T {
        lock.lock(); defer { lock.unlock() }
        guard valid, !Task.isCancelled else { throw CancellationError() }
        return try body()
    }
    func check() throws {
        lock.lock(); let allowed = valid; lock.unlock()
        if !allowed || Task.isCancelled { throw CancellationError() }
    }
}
