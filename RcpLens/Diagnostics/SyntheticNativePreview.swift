#if DEBUG
import SwiftUI
import UIKit

/// Fictional native visual-review scenarios, isolated from both production and private-test stores.
@MainActor enum SyntheticNativePreview {
    static var enabled: Bool { ProcessInfo.processInfo.arguments.contains("--t05-synthetic-preview") }
    static var mode: String {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "--t05-synthetic-preview"), i + 1 < args.count else { return "wallet" }
        return args[i + 1]
    }
    static var readyURL: URL { FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("t05-synthetic-preview.json") }
    static func fixture(index: Int) -> (Data, ReceiptReviewDraft) {
        let merchant = ["SYNTHETIC CORNER", "SYNTHETIC MARKET", "SYNTHETIC STORE"][index % 3]
        let date = String(format: "2026-10-%02d", 7 - index % 3)
        let content = [merchant, date + " CAD", "TEST ITEM 12.34", "SUBTOTAL 12.34", "TOTAL 12.34"]
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        let image = UIGraphicsImageRenderer(size: CGSize(width: 720, height: 480), format: format).pngData { _ in
            UIColor.white.setFill(); UIRectFill(CGRect(x: 0, y: 0, width: 720, height: 480))
            for (i, line) in content.enumerated() {
                (line as NSString).draw(at: CGPoint(x: 40, y: 50 + i * 76), withAttributes: [.font: UIFont.monospacedSystemFont(ofSize: 32, weight: .regular), .foregroundColor: UIColor.black])
            }
        }
        var d = ReceiptReviewDraft(); d.merchant = merchant; d.date = date; d.currency = "CAD"
        d.lines = [.init(id: UUID(), kind: "purchase", name: "TEST ITEM", quantity: "", amount: "12.34", sourceLineIDs: [])]
        d.subtotal = "12.34"; d.total = "12.34"; d.sourceOpened = true; d.sourceChecked = true
        return (image, d)
    }
    static func run(_ workspace: ReceiptWorkspace) async {
        guard enabled else { return }
        try? FileManager.default.removeItem(at: readyURL)
        for _ in 0..<100 {
            if workspace.availability == .ready { break }
            try? await Task.sleep(for: .milliseconds(25))
        }
        await workspace.seedSyntheticPreview(count: mode == "library" ? 500 : (mode == "empty" ? 0 : 3))
        if let receipt = workspace.orderedReceipts.first, ["detail", "review", "source"].contains(mode) {
            workspace.open(receipt)
            for _ in 0..<100 {
                if workspace.flow == .detail { break }
                try? await Task.sleep(for: .milliseconds(25))
            }
            if mode == "review" { workspace.edit() }
            if mode == "source" { workspace.showSource(ids: receipt.original.fields.items.first?.sourceLineIDs ?? []) }
        }
        if mode == "library" { workspace.library = true }
        try? JSONSerialization.data(withJSONObject: ["mode":mode,"count":workspace.receipts.count,"ready":true], options: [.sortedKeys]).write(to: readyURL, options: .atomic)
    }
}

extension ReceiptWorkspace {
    func seedSyntheticPreview(count: Int) async {
        guard SyntheticNativePreview.enabled else { return }
        await seedFictionalRecordsForPreview(count: count)
    }
}
#endif
