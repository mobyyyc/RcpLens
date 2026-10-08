import XCTest
import Foundation
@testable import RcpLens

enum SplitFixture {
    static let a = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    static let b = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    static let c = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
    static func record(amounts: [Int64], adjustments: [(ReceiptAdjustment.Kind, Int64)] = [], review: ReceiptRevision.Review = .sourceReviewed) -> ReceiptRecord {
        let now = Date(timeIntervalSince1970: 1700000000)
        let items = amounts.enumerated().map { index, amount in
            ReceiptLine(id: UUID(), description: "FICTIONAL ITEM \(index)", sku: nil, quantity: nil, unitPrice: nil,
                amount: .init(minorUnits: amount, currency: .cad), taxMarker: index == 0 ? "AMBIGUOUS H" : nil, sourceLineIDs: [])
        }
        let changes = adjustments.map { kind, amount in ReceiptAdjustment(id: UUID(), kind: kind, label: "FICTIONAL \(kind.rawValue)", amount: .init(minorUnits: amount, currency: .cad), rate: nil, sourceLineIDs: []) }
        let total = amounts.reduce(0, +) + adjustments.map(\.1).reduce(0, +)
        let fields = ReceiptFields(merchant: "FICTIONAL STORE", purchaseDate: try! .init(year: 2026, month: 10, day: 8), currency: .cad,
            items: items, adjustments: changes, subtotal: nil, total: .init(minorUnits: total, currency: .cad))
        let extraction = ReceiptExtraction(capturedAt: now, recognizer: "Fictional", recognizerVersion: "1", parser: "Fictional", parserVersion: "1", rawOCR: [], rawParserOutput: Data("{}".utf8), fields: fields, issues: [])
        return ReceiptRecord(id: UUID(), createdAt: now, updatedAt: now, original: extraction,
            asset: .init(id: UUID(), mediaType: "image/png", byteCount: 1, sha256: Data(repeating: 0, count: 32)),
            revisions: [.init(id: UUID(), createdAt: now, fields: fields, review: .draft), .init(id: UUID(), createdAt: now, fields: fields, review: review)])
    }
    static func plan(_ record: ReceiptRecord, owners: [[UUID]]? = nil) -> ReceiptSplitPlan {
        var plan = ReceiptSplitPlan()
        plan.participants = [.init(id: a, name: "Fictional Alex"), .init(id: b, name: "Fictional Blair"), .init(id: c, name: "Fictional Casey")]
        for (index, item) in record.current.fields.items.enumerated() { plan.assignments[item.id] = owners?[index] ?? [a, b, c] }
        plan.policies = record.current.fields.adjustments.map { .init(id: $0.id, accepted: true) }
        return plan
    }
}

final class ReceiptSplitTests: XCTestCase {
    func testOddCentsThreePeopleAndStableUUIDTies() throws {
        let shares = try ReceiptSplitEngine.allocate(100, weights: [SplitFixture.c: 1, SplitFixture.b: 1, SplitFixture.a: 1])
        XCTAssertEqual(shares, [SplitFixture.a: 34, SplitFixture.b: 33, SplitFixture.c: 33])
        XCTAssertEqual(try ReceiptSplitEngine.allocate(-100, weights: [SplitFixture.a: 1, SplitFixture.c: 1, SplitFixture.b: 1]), shares.mapValues { -$0 })
    }
    func testFullWidthAndMinimumInteger() throws {
        let a = SplitFixture.a, b = SplitFixture.b
        XCTAssertEqual(try ReceiptSplitEngine.allocate(Int64.max, weights: [a: UInt64(Int64.max), b: UInt64(Int64.max)])[a], 4611686018427387904)
        XCTAssertEqual(try ReceiptSplitEngine.allocate(Int64.min, weights: [a: 1]), [a: Int64.min])
        XCTAssertEqual(try ReceiptSplitEngine.allocate(Int64.min, weights: [a: 1, b: 1]), [a: -4611686018427387904, b: -4611686018427387904])
        XCTAssertThrowsError(try ReceiptSplitEngine.allocate(1, weights: [a: UInt64.max, b: 1])) { XCTAssertEqual($0 as? SplitError, .overflow) }
        XCTAssertThrowsError(try ReceiptSplitEngine.add(Int64.max, 1))
        XCTAssertThrowsError(try ReceiptSplitEngine.add(Int64.min, -1))
    }
    func testZeroValueBaseNeverSilentlyFallsBack() throws {
        let record = SplitFixture.record(amounts: [0], adjustments: [(.tip, 5)])
        var plan = SplitFixture.plan(record)
        XCTAssertThrowsError(try ReceiptSplitEngine.compute(record, plan: plan)) { XCTAssertEqual($0 as? SplitError, .zeroBase) }
        plan.policies[0].method = .equal
        let result = try ReceiptSplitEngine.compute(record, plan: plan)
        XCTAssertEqual(result.totals, [SplitFixture.a: 2, SplitFixture.b: 2, SplitFixture.c: 1])
        XCTAssertEqual(try ReceiptSplitEngine.allocate(0, weights: [SplitFixture.a: 0]), [SplitFixture.a: 0])
        XCTAssertThrowsError(try ReceiptSplitEngine.allocate(0, weights: [:]))
    }
    func testIndividualSharedDiscountDepositTipAndNegativeAdjustment() throws {
        let record = SplitFixture.record(amounts: [1001, 499, 250], adjustments: [(.discount, -101), (.tax, 63), (.deposit, 20), (.tip, 100), (.other, -2)])
        var plan = SplitFixture.plan(record, owners: [[SplitFixture.a], [SplitFixture.b, SplitFixture.c], [SplitFixture.c]])
        plan.policies[2].target = .selectedPeople; plan.policies[2].selectedIDs = [SplitFixture.c]
        plan.policies[3].method = .equal
        let result = try ReceiptSplitEngine.compute(record, plan: plan)
        XCTAssertEqual(result.total, 1830)
        XCTAssertEqual(result.totals.values.reduce(0, +), 1830)
        XCTAssertEqual(result.components[1].shares, [SplitFixture.b: 250, SplitFixture.c: 249])
        XCTAssertEqual(result.components.first { $0.id == record.current.fields.adjustments[2].id }!.shares[SplitFixture.c], 20)
        for (component, amount) in zip(result.components, [1001, 499, 250, -101, 63, 20, 100, -2]) { XCTAssertEqual(component.shares.values.reduce(0, +), Int64(amount)) }
    }
    func testSourceConfirmedTaxAndUnknownMarkerFallback() throws {
        let record = SplitFixture.record(amounts: [1000, 2000], adjustments: [(.tax, 130)])
        var plan = SplitFixture.plan(record, owners: [[SplitFixture.a], [SplitFixture.b]])
        let fallback = try ReceiptSplitEngine.compute(record, plan: plan)
        XCTAssertTrue(fallback.components.last!.detail.contains("Unknown tax"))
        XCTAssertEqual(fallback.components.last!.shares, [SplitFixture.a: 43, SplitFixture.b: 87])
        plan.policies[0].target = .selectedPurchases; plan.policies[0].selectedIDs = [record.current.fields.items[0].id]
        XCTAssertThrowsError(try ReceiptSplitEngine.compute(record, plan: plan)) { XCTAssertEqual($0 as? SplitError, .unknownTaxScope) }
        plan.policies[0].sourceConfirmed = true
        let result = try ReceiptSplitEngine.compute(record, plan: plan)
        XCTAssertEqual(result.totals[SplitFixture.a], 1130); XCTAssertEqual(result.totals[SplitFixture.b], 2000)
    }
    func testCouponLimitedToItemOwnersAndEqualPolicy() throws {
        let record = SplitFixture.record(amounts: [900, 100], adjustments: [(.discount, -99)])
        var plan = SplitFixture.plan(record, owners: [[SplitFixture.a], [SplitFixture.b, SplitFixture.c]])
        plan.policies[0].target = .selectedPurchases; plan.policies[0].selectedIDs = [record.current.fields.items[1].id]
        XCTAssertEqual(try ReceiptSplitEngine.compute(record, plan: plan).components.last!.shares, [SplitFixture.b: -50, SplitFixture.c: -49])
        plan.policies[0].target = .allPurchases; plan.policies[0].selectedIDs = []; plan.policies[0].method = .equal
        XCTAssertEqual(try ReceiptSplitEngine.compute(record, plan: plan).components.last!.shares, [SplitFixture.a: -33, SplitFixture.b: -33, SplitFixture.c: -33])
    }
    func testEqualAllPurchasesIncludesPeopleWithoutAssignedItems() throws {
        let record = SplitFixture.record(amounts: [300], adjustments: [(.tip, 5)])
        var plan = SplitFixture.plan(record, owners: [[SplitFixture.a]])
        plan.policies[0].method = .equal
        let result = try ReceiptSplitEngine.compute(record, plan: plan)
        XCTAssertEqual(result.components.last!.shares, [SplitFixture.a: 2, SplitFixture.b: 2, SplitFixture.c: 1])
        XCTAssertTrue(result.components.last!.detail.contains("All people"))
        plan.policies[0].target = .selectedPurchases; plan.policies[0].selectedIDs = [record.current.fields.items[0].id]
        XCTAssertEqual(try ReceiptSplitEngine.compute(record, plan: plan).components.last!.shares, [SplitFixture.a: 5])
    }
    func testReturnLinesUseAbsoluteGrossValue() throws {
        let record = SplitFixture.record(amounts: [-300, 100], adjustments: [(.other, -20)])
        let plan = SplitFixture.plan(record, owners: [[SplitFixture.a], [SplitFixture.b]])
        let result = try ReceiptSplitEngine.compute(record, plan: plan)
        XCTAssertEqual(result.totals[SplitFixture.a], -315); XCTAssertEqual(result.totals[SplitFixture.b], 95)
    }
    func testDraftDiscrepancyAssignmentsAndUnconfirmedPoliciesReject() throws {
        let draft = SplitFixture.record(amounts: [100], review: .draft)
        XCTAssertThrowsError(try ReceiptSplitEngine.compute(draft, plan: SplitFixture.plan(draft)))
        let record = SplitFixture.record(amounts: [100], adjustments: [(.tax, 1)])
        var plan = SplitFixture.plan(record)
        plan.assignments = [:]; XCTAssertThrowsError(try ReceiptSplitEngine.compute(record, plan: plan))
        plan = SplitFixture.plan(record); plan.assignments[UUID()] = [SplitFixture.a]; XCTAssertThrowsError(try ReceiptSplitEngine.compute(record, plan: plan))
        plan = SplitFixture.plan(record); plan.assignments[record.current.fields.items[0].id] = [UUID()]; XCTAssertThrowsError(try ReceiptSplitEngine.compute(record, plan: plan))
        plan = SplitFixture.plan(record); plan.policies[0].accepted = false; XCTAssertThrowsError(try ReceiptSplitEngine.compute(record, plan: plan))
        var changed = record
        let old = record.current
        var fields = old.fields; fields.total = .init(minorUnits: 999, currency: .cad)
        changed = ReceiptRecord(id: record.id, createdAt: record.createdAt, updatedAt: record.updatedAt, original: record.original, asset: record.asset,
            revisions: [record.revisions[0], .init(id: old.id, createdAt: old.createdAt, fields: fields, review: .sourceReviewed)])
        XCTAssertThrowsError(try ReceiptSplitEngine.compute(changed, plan: SplitFixture.plan(record)))
    }
    func testInvalidPlanBoundsDuplicatesAndTargets() throws {
        let record = SplitFixture.record(amounts: [100], adjustments: [(.deposit, 10)])
        var plan = SplitFixture.plan(record)
        plan.participants.append(plan.participants[0]); XCTAssertThrowsError(try plan.validateStructure())
        plan = SplitFixture.plan(record); plan.participants[0].name = String(repeating: "x", count: 81); XCTAssertThrowsError(try plan.validateStructure())
        plan = SplitFixture.plan(record); plan.version = 2; XCTAssertThrowsError(try plan.validateStructure())
        plan = SplitFixture.plan(record); plan.policies[0].target = .selectedPeople; XCTAssertThrowsError(try ReceiptSplitEngine.compute(record, plan: plan))
        plan.policies[0].selectedIDs = [UUID()]; XCTAssertThrowsError(try ReceiptSplitEngine.compute(record, plan: plan))
        plan = SplitFixture.plan(record); plan.assignments[record.current.fields.items[0].id] = [SplitFixture.a, SplitFixture.a]; XCTAssertThrowsError(try plan.validateStructure())
    }
    func testDeterminismAndSumInvariantsAcrossManySignedAmounts() throws {
        for amount in stride(from: -1003, through: 1003, by: 7) {
            let record = SplitFixture.record(amounts: [Int64(amount), 101, 0], adjustments: [(.discount, -17), (.tip, 9)])
            var plan = SplitFixture.plan(record, owners: [[SplitFixture.a, SplitFixture.b, SplitFixture.c], [SplitFixture.b], [SplitFixture.c]])
            let expected = try ReceiptSplitEngine.compute(record, plan: plan)
            plan.participants.reverse(); plan.policies.reverse()
            // Component ordering follows receipt order, not dictionary/participant/policy iteration.
            XCTAssertEqual(try ReceiptSplitEngine.compute(record, plan: plan), expected)
            XCTAssertEqual(expected.totals.values.reduce(0, +), record.current.fields.total!.minorUnits)
            for component in expected.components { XCTAssertEqual(component.shares.values.reduce(0, +), (record.current.fields.items.first { $0.id == component.id }?.amount ?? record.current.fields.adjustments.first { $0.id == component.id }!.amount)!.minorUnits) }
        }
    }
    func testRepeatedSharedOddCentsStayBalancedWithinEachOwnerSet() throws {
        for amounts: [Int64] in [[101, 101, 101], [-101, -101, -101], [-1, 2], [1, -2, 0, 1, -3, 5], [-1, 2, -3, 0, 5]] {
            for owners in [[SplitFixture.a, SplitFixture.b], [SplitFixture.a, SplitFixture.b, SplitFixture.c]] {
                let record = SplitFixture.record(amounts: amounts)
                var plan = SplitFixture.plan(record, owners: amounts.map { _ in owners })
                let result = try ReceiptSplitEngine.compute(record, plan: plan)
                let totals = owners.map { result.totals[$0]! }
                XCTAssertLessThanOrEqual(totals.max()! - totals.min()!, 1)
                for (component, amount) in zip(result.components, amounts) {
                    XCTAssertEqual(component.shares.values.reduce(0, +), amount)
                    for value in component.shares.values {
                        XCTAssertLessThan(abs(value * Int64(owners.count) - amount), Int64(owners.count), "Every line stays within one minor unit of its equal share, even crossing zero")
                    }
                }
                plan.assignments = plan.assignments.mapValues { $0.reversed() }
                XCTAssertEqual(try ReceiptSplitEngine.compute(record, plan: plan), result)
            }
        }
    }
    func testMixedOwnerSetsMaintainIndependentCumulativeRounding() throws {
        let record = SplitFixture.record(amounts: [101, 101, 101, 101, 101, 101, 0])
        let plan = SplitFixture.plan(record, owners: [[SplitFixture.a, SplitFixture.b], [SplitFixture.b, SplitFixture.c], [SplitFixture.b, SplitFixture.a], [SplitFixture.c, SplitFixture.b], [SplitFixture.a, SplitFixture.b], [SplitFixture.b, SplitFixture.c], [SplitFixture.a, SplitFixture.b]])
        let result = try ReceiptSplitEngine.compute(record, plan: plan)
        let ab = [result.components[0], result.components[2], result.components[4], result.components[6]]
        let bc = [result.components[1], result.components[3], result.components[5]]
        for (components, owners) in [(ab, [SplitFixture.a, SplitFixture.b]), (bc, [SplitFixture.b, SplitFixture.c])] {
            let sums = owners.map { id in components.reduce(Int64(0)) { $0 + $1.shares[id]! } }
            XCTAssertEqual(abs(sums[0] - sums[1]), 1)
        }
        XCTAssertEqual(result.total, 606)
    }
    func testMalformedReceiptAndReviewAmountBoundsFailWithoutTrapping() throws {
        let record = SplitFixture.record(amounts: [100])
        let invalid = ReceiptRecord(id: record.id, createdAt: record.createdAt, updatedAt: record.updatedAt, original: record.original, asset: record.asset, revisions: [])
        XCTAssertThrowsError(try ReceiptSplitEngine.compute(invalid, plan: SplitFixture.plan(record))) { XCTAssertEqual($0 as? SplitError, .invalidPlan) }
        XCTAssertThrowsError(try ReceiptSplitEngine.summary(invalid, plan: ReceiptSplitPlan()))
        let beyondReviewBounds = SplitFixture.record(amounts: [Int64.max])
        XCTAssertThrowsError(try ReceiptSplitEngine.compute(beyondReviewBounds, plan: SplitFixture.plan(beyondReviewBounds))) { XCTAssertEqual($0 as? SplitError, .receiptNeedsReview) }
    }
    func testFinalSummaryRequiresCurrentRevisionAndContainsItemsPolicies() throws {
        let record = SplitFixture.record(amounts: [101], adjustments: [(.tax, 1)])
        var plan = SplitFixture.plan(record)
        XCTAssertThrowsError(try ReceiptSplitEngine.summary(record, plan: plan))
        plan.finalizedRevision = UUID(); XCTAssertThrowsError(try ReceiptSplitEngine.summary(record, plan: plan))
        plan.finalizedRevision = record.current.id
        let summary = try ReceiptSplitEngine.summary(record, plan: plan)
        XCTAssertTrue(summary.contains("Receipt total: CAD 1.02")); XCTAssertTrue(summary.contains("Fictional Alex"))
        XCTAssertTrue(summary.contains("FICTIONAL ITEM 0")); XCTAssertTrue(summary.contains("Unknown tax applicability fallback"))
        XCTAssertEqual(summary, try ReceiptSplitEngine.summary(record, plan: plan))
    }
}
