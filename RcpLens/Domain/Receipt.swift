import Foundation

/// No binary floating-point financial values. A currency specifies its minor-unit scale.
struct ReceiptCurrency: Codable, Equatable, Sendable {
    let code: String
    let minorUnitScale: UInt8
    static let cad = try! ReceiptCurrency(code: "CAD", minorUnitScale: 2)

    init(code: String, minorUnitScale: UInt8) throws {
        guard code.utf8.count == 3, code.utf8.allSatisfy({ (65...90).contains($0) }), minorUnitScale <= 6 else {
            throw ReceiptValidationError.invalidCurrency
        }
        self.code = code
        self.minorUnitScale = minorUnitScale
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(code: c.decode(String.self, forKey: .code),
                      minorUnitScale: c.decode(UInt8.self, forKey: .minorUnitScale))
    }
}

struct ReceiptMoney: Codable, Equatable, Sendable {
    let minorUnits: Int64
    let currency: ReceiptCurrency

    func adding(_ other: ReceiptMoney) throws -> ReceiptMoney {
        guard currency == other.currency else { throw ReceiptValidationError.currencyMismatch }
        let (result, overflow) = minorUnits.addingReportingOverflow(other.minorUnits)
        guard !overflow else { throw ReceiptValidationError.arithmeticOverflow }
        return ReceiptMoney(minorUnits: result, currency: currency)
    }

    func subtracting(_ other: ReceiptMoney) throws -> ReceiptMoney {
        guard currency == other.currency else { throw ReceiptValidationError.currencyMismatch }
        let (result, overflow) = minorUnits.subtractingReportingOverflow(other.minorUnits)
        guard !overflow else { throw ReceiptValidationError.arithmeticOverflow }
        return ReceiptMoney(minorUnits: result, currency: currency)
    }
}

/// coefficient / 10^scale; retains printed precision for quantities and rates.
/// Arithmetic/rounding policy belongs to the split engine. Do not convert this to Double.
struct ReceiptDecimal: Codable, Equatable, Sendable {
    let coefficient: Int64
    let scale: UInt8

    init(coefficient: Int64, scale: UInt8) throws {
        guard scale <= 9 else { throw ReceiptValidationError.invalidDecimal }
        self.coefficient = coefficient
        self.scale = scale
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(coefficient: c.decode(Int64.self, forKey: .coefficient),
                      scale: c.decode(UInt8.self, forKey: .scale))
    }
}

enum ReceiptValidationError: Error, Equatable {
    case invalidCurrency, invalidDecimal, currencyMismatch, arithmeticOverflow
    case invalidDate, duplicateIdentifier, invalidQuantity, invalidTimestamp, invalidEvidence
}

/// A printed civil date, with no invented time zone or purchase time.
struct ReceiptDate: Codable, Equatable, Sendable {
    let year: Int
    let month: Int
    let day: Int

    init(year: Int, month: Int, day: Int) throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let components = DateComponents(year: year, month: month, day: day)
        guard (1...9999).contains(year), let date = calendar.date(from: components),
              calendar.dateComponents([.year, .month, .day], from: date) == components else {
            throw ReceiptValidationError.invalidDate
        }
        self.year = year; self.month = month; self.day = day
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(year: c.decode(Int.self, forKey: .year), month: c.decode(Int.self, forKey: .month),
                      day: c.decode(Int.self, forKey: .day))
    }
}

struct ReceiptLine: Codable, Equatable, Sendable, Identifiable {
    let id: UUID
    var description: String?
    var sku: String?
    var quantity: ReceiptDecimal?
    var unitPrice: ReceiptMoney?
    var amount: ReceiptMoney?
    var taxMarker: String?
    /// OCR line identities; optional because source linkage may be unavailable.
    var sourceLineIDs: [UUID]
}

struct ReceiptAdjustment: Codable, Equatable, Sendable, Identifiable {
    enum Kind: String, Codable, Sendable { case discount, tax, deposit, tip, other }
    let id: UUID
    var kind: Kind
    var label: String?
    var amount: ReceiptMoney?
    var rate: ReceiptDecimal?
    var sourceLineIDs: [UUID]
}

/// Optional values preserve unknowns. Even a matching total does not establish source verification.
struct ReceiptFields: Codable, Equatable, Sendable {
    var merchant: String?
    var purchaseDate: ReceiptDate?
    var currency: ReceiptCurrency?
    var items: [ReceiptLine]
    var adjustments: [ReceiptAdjustment]
    var subtotal: ReceiptMoney?
    var total: ReceiptMoney?

    func validate() throws {
        let ids = items.map(\.id) + adjustments.map(\.id)
        guard Set(ids).count == ids.count else { throw ReceiptValidationError.duplicateIdentifier }
        guard items.allSatisfy({ $0.quantity.map { $0.coefficient > 0 } ?? true }) else {
            throw ReceiptValidationError.invalidQuantity
        }
        let money = items.flatMap { [$0.unitPrice, $0.amount].compactMap { $0 } }
            + adjustments.compactMap(\.amount) + [subtotal, total].compactMap { $0 }
        guard money.allSatisfy({ $0.currency == currency }) else { throw ReceiptValidationError.currencyMismatch }
    }
}

/// Image-normalized Vision geometry; this is spatial data, never financial arithmetic.
struct ReceiptOCRBox: Codable, Equatable, Sendable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double

    init(x: Double, y: Double, width: Double, height: Double) throws {
        guard [x, y, width, height].allSatisfy(\.isFinite), x >= 0, y >= 0,
              width > 0, height > 0, x + width <= 1, y + height <= 1 else {
            throw ReceiptValidationError.invalidEvidence
        }
        self.x = x; self.y = y; self.width = width; self.height = height
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(x: c.decode(Double.self, forKey: .x), y: c.decode(Double.self, forKey: .y),
                      width: c.decode(Double.self, forKey: .width), height: c.decode(Double.self, forKey: .height))
    }
}

struct ReceiptOCRLine: Codable, Equatable, Sendable, Identifiable {
    let id: UUID
    let text: String
    /// Optional original engine confidence; never a calibrated receipt correctness score.
    let engineConfidence: Float?
    /// Vision's normalized lower-left origin; nil when the recognizer did not supply geometry.
    let boundingBox: ReceiptOCRBox?

    init(id: UUID, text: String, engineConfidence: Float?, boundingBox: ReceiptOCRBox? = nil) {
        self.id = id; self.text = text; self.engineConfidence = engineConfidence; self.boundingBox = boundingBox
    }
}

struct ReceiptExtractionIssue: Codable, Equatable, Sendable {
    let code: String
    let sourceLineIDs: [UUID]
    let detail: String?
}

struct ReceiptExtraction: Codable, Equatable, Sendable {
    let capturedAt: Date
    let recognizer: String
    let recognizerVersion: String
    let parser: String
    let parserVersion: String
    let rawOCR: [ReceiptOCRLine]
    /// Exact parser bytes including incomplete/uncertain fields; no lossy reserialization.
    let rawParserOutput: Data
    let fields: ReceiptFields
    let issues: [ReceiptExtractionIssue]

    func validate() throws {
        try fields.validate()
        guard capturedAt.timeIntervalSince1970.isFinite,
              Set(rawOCR.map(\.id)).count == rawOCR.count,
              rawOCR.allSatisfy({ $0.engineConfidence.map { $0.isFinite && (0...1).contains($0) } ?? true }) else {
            throw ReceiptValidationError.invalidEvidence
        }
        let sourceIDs = Set(rawOCR.map(\.id))
        let references = fields.items.flatMap(\.sourceLineIDs) + fields.adjustments.flatMap(\.sourceLineIDs)
            + issues.flatMap(\.sourceLineIDs)
        guard references.allSatisfy(sourceIDs.contains) else { throw ReceiptValidationError.invalidEvidence }
    }
}

struct ReceiptRevision: Codable, Equatable, Sendable, Identifiable {
    enum Review: String, Codable, Sendable { case draft, sourceReviewed }
    let id: UUID
    let createdAt: Date
    let fields: ReceiptFields
    /// This records a user's explicit source review; it is not arithmetic reconciliation.
    let review: Review
}

struct ReceiptAsset: Codable, Equatable, Sendable, Identifiable {
    let id: UUID
    let mediaType: String
    let byteCount: Int
    let sha256: Data
}

struct ReceiptRecord: Codable, Equatable, Sendable, Identifiable {
    let id: UUID
    let createdAt: Date
    let updatedAt: Date
    let original: ReceiptExtraction
    let asset: ReceiptAsset
    let revisions: [ReceiptRevision]
    var current: ReceiptRevision { revisions.last! }

    func validate() throws {
        try original.validate()
        guard !revisions.isEmpty, Set(revisions.map(\.id)).count == revisions.count else {
            throw ReceiptValidationError.duplicateIdentifier
        }
        guard createdAt.timeIntervalSince1970.isFinite, updatedAt.timeIntervalSince1970.isFinite,
              revisions.allSatisfy({ $0.createdAt.timeIntervalSince1970.isFinite }),
              revisions.first!.createdAt == createdAt, revisions.last!.createdAt == updatedAt,
              updatedAt >= createdAt else { throw ReceiptValidationError.invalidTimestamp }
        let sourceIDs = Set(original.rawOCR.map(\.id))
        var previous = createdAt
        for revision in revisions {
            try revision.fields.validate()
            let references = revision.fields.items.flatMap(\.sourceLineIDs) + revision.fields.adjustments.flatMap(\.sourceLineIDs)
            guard references.allSatisfy(sourceIDs.contains) else { throw ReceiptValidationError.invalidEvidence }
            guard revision.createdAt >= previous else { throw ReceiptValidationError.invalidTimestamp }
            previous = revision.createdAt
        }
        guard revisions.first!.fields == original.fields, revisions.first!.review == .draft,
              asset.byteCount > 0, asset.sha256.count == 32 else { throw ReceiptValidationError.invalidEvidence }
    }
}
