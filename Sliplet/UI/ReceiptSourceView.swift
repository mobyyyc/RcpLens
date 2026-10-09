import SwiftUI
import UIKit

struct ReceiptSourceView: View {
    @Bindable var workspace: ReceiptWorkspace
    @State private var mode = 0
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    private var reduceMotion: Bool { ReceiptAccessibility.reduceMotion(systemReduceMotion) }
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Evidence", selection: $mode) {
                    Text("Original image").tag(0)
                    Text("Printed text").tag(1)
                }.pickerStyle(.segmented).padding().accessibilityIdentifier("sourceMode")
                if workspace.privacyCovered || !workspace.active {
                    ContentUnavailableView("Original locked", systemImage: "lock")
                } else if mode == 0, let image = workspace.image {
                    ZoomReceiptImage(bytes: image.bytes, boxes: (workspace.extraction?.rawOCR ?? []).filter { workspace.sourceLineIDs.contains($0.id) }.compactMap(\.boundingBox), reduceMotion: reduceMotion)
                        .accessibilityIdentifier("sourceImage")
                    Text("Pinch, double-tap or use the zoom buttons. Highlights show where a line was read.")
                        .font(.footnote).foregroundStyle(.primary).padding()
                    HStack {
                        Button("Zoom in", systemImage: "plus.magnifyingglass") { NotificationCenter.default.post(name: .receiptZoomIn, object: nil) }
                        Button("Zoom out", systemImage: "minus.magnifyingglass") { NotificationCenter.default.post(name: .receiptZoomOut, object: nil) }
                    }.buttonStyle(ReceiptSecondaryStyle()).padding(.bottom)
                } else {
                    List {
                        Section { Text("Text read from the original may contain errors or omissions. Check against the image.").font(.footnote) }
                        ForEach(workspace.extraction?.rawOCR ?? []) { line in
                            Text(line.text).textSelection(.enabled)
                                .listRowBackground(workspace.sourceLineIDs.contains(line.id) ? Color(uiColor: .tertiarySystemFill) : Color(uiColor: .secondarySystemGroupedBackground))
                        }
                        if workspace.extraction?.rawOCR.isEmpty ?? true { Text("No recognized text. Compare against the original image.") }
                    }
                }
            }.navigationTitle("Original evidence").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { workspace.sourceVisible = false; dismiss() }.accessibilityIdentifier("sourceDone") } }
        }.tint(.primary).accessibilityIdentifier("sourceScreen")
    }
}

extension Notification.Name {
    static let receiptZoomIn = Notification.Name("Sliplet.sourceZoomIn")
    static let receiptZoomOut = Notification.Name("Sliplet.sourceZoomOut")
}

/// In-memory UIKit image view; no file output, disk thumbnails or web cache.
struct ZoomReceiptImage: UIViewRepresentable {
    let bytes: Data
    let boxes: [ReceiptOCRBox]
    let reduceMotion: Bool
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> UIScrollView {
        let view = UIScrollView()
        view.backgroundColor = .systemBackground
        view.delegate = context.coordinator
        context.coordinator.reduceMotion = reduceMotion
        view.maximumZoomScale = 8
        view.minimumZoomScale = 0.01
        let imageView = context.coordinator.imageView
        imageView.image = ReceiptDisplayImage.make(bytes)
        imageView.contentMode = .scaleAspectFit
        let size = imageView.image?.size ?? CGSize(width: 1, height: 1)
        imageView.frame = CGRect(origin: .zero, size: size)
        imageView.isAccessibilityElement = true
        imageView.accessibilityLabel = "Original receipt image"
        imageView.accessibilityHint = "Pinch, double tap, or use the zoom buttons. Printed text provides an OCR alternative."
        view.addSubview(imageView); view.contentSize = size
        for box in boxes {
            let region = UIView(frame: CGRect(x: box.x * size.width, y: (1 - box.y - box.height) * size.height,
                                             width: box.width * size.width, height: box.height * size.height))
            region.layer.borderColor = UIColor.systemBlue.cgColor; region.layer.borderWidth = max(2, size.width / 250)
            region.isUserInteractionEnabled = false; region.isAccessibilityElement = false
            imageView.addSubview(region)
        }
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.doubleTap(_:)))
        tap.numberOfTapsRequired = 2; view.addGestureRecognizer(tap)
        context.coordinator.scrollView = view
        context.coordinator.observeZoom()
        return view
    }
    func updateUIView(_ view: UIScrollView, context: Context) {
        DispatchQueue.main.async {
            guard view.bounds.width > 0, !context.coordinator.fitted else { return }
            context.coordinator.fitted = true
            let fit = view.bounds.width / max(1, context.coordinator.imageView.bounds.width)
            view.minimumZoomScale = fit; view.maximumZoomScale = max(fit * 8, 2)
            view.setZoomScale(fit, animated: false)
        }
    }
    static func dismantleUIView(_ view: UIScrollView, coordinator: Coordinator) {
        coordinator.stopObserving(); view.delegate = nil
        coordinator.imageView.image = nil; coordinator.imageView.subviews.forEach { $0.removeFromSuperview() }
    }
    @MainActor final class Coordinator: NSObject, UIScrollViewDelegate {
        let imageView = UIImageView()
        weak var scrollView: UIScrollView?
        var fitted = false
        var reduceMotion = false
        private var tokens: [NSObjectProtocol] = []
        func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }
        @objc func doubleTap(_ gesture: UITapGestureRecognizer) {
            guard let view = scrollView else { return }
            view.setZoomScale(view.zoomScale > view.minimumZoomScale * 1.5 ? view.minimumZoomScale : min(view.maximumZoomScale, view.minimumZoomScale * 3), animated: !reduceMotion && !UIAccessibility.isReduceMotionEnabled)
        }
        func observeZoom() {
            tokens = [(.receiptZoomIn, 1.6), (.receiptZoomOut, 1 / 1.6)].map { name, factor in
                NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated {
                        guard let view = self?.scrollView else { return }
                        view.setZoomScale(min(view.maximumZoomScale, max(view.minimumZoomScale, view.zoomScale * factor)), animated: !(self?.reduceMotion ?? true) && !UIAccessibility.isReduceMotionEnabled)
                    }
                }
            }
        }
        func stopObserving() { tokens.forEach(NotificationCenter.default.removeObserver); tokens = [] }
    }
}


/// Normalize only the in-memory display image so its coordinate space matches Vision's oriented image.
/// Exact encoded bytes remain untouched in ReceiptImage and encrypted storage.
@MainActor enum ReceiptDisplayImage {
    static func make(_ bytes: Data) -> UIImage? {
        guard let original = UIImage(data: bytes), let cg = original.cgImage else { return nil }
        let swaps = [.left, .right, .leftMirrored, .rightMirrored].contains(original.imageOrientation)
        let width = swaps ? cg.height : cg.width, height = swaps ? cg.width : cg.height
        // The whole image is displayed. Downscale only the display raster, never OCR or original evidence.
        let factor = min(1, 2048 / CGFloat(width))
        let size = CGSize(width: CGFloat(width) * factor, height: CGFloat(height) * factor)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.systemBackground.setFill(); context.fill(CGRect(origin: .zero, size: size))
            original.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
