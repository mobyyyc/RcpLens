import SwiftUI
import UIKit

/// Monotone screen-space projection: widest spacing in the reading zone, tight spacing at the pocket.
struct ReceiptStackProjection {
    static let pitch: CGFloat = 136
    static let paperHeight: CGFloat = 244
    let anchor: CGFloat
    let readingY: CGFloat
    let viewportHeight: CGFloat
    private let minimum: CGFloat = 36 / 136
    private let amplitude: CGFloat = (224 - 36) / 136
    private let width: CGFloat
    private let focus: CGFloat

    init(viewportHeight: CGFloat, readingY: CGFloat, anchor: CGFloat) {
        self.viewportHeight = viewportHeight; self.readingY = readingY; self.anchor = anchor
        width = max(60, min(130, viewportHeight * 0.15))
        var low: CGFloat = -4000, high: CGFloat = 4000
        for _ in 0..<40 {
            let distance = (low + high) / 2
            let span = minimum * distance + amplitude * width * tanh(distance / width)
            if span < anchor - readingY { low = distance } else { high = distance }
        }
        focus = anchor - (low + high) / 2
    }
    func position(_ logicalY: CGFloat) -> CGFloat {
        anchor + minimum * (logicalY - anchor)
        + amplitude * width * (tanh((logicalY - focus) / width) - tanh((anchor - focus) / width))
    }
    func logicalPosition(_ displayedY: CGFloat) -> CGFloat {
        var low = anchor - 20_000, high = anchor + 20_000
        for _ in 0..<44 {
            let middle = (low + high) / 2
            if position(middle) < displayedY { low = middle } else { high = middle }
        }
        return (low + high) / 2
    }
    func displayedPosition(_ logicalY: CGFloat, endPull: CGFloat) -> CGFloat {
        // Beyond the last receipt, preserve the shared paper-and-wallet rubber band.
        position(logicalY + endPull) - endPull
    }
    func visibleIndices(baseY: CGFloat, count: Int, endPull: CGFloat) -> Range<Int> {
        guard count > 0 else { return 0..<0 }
        let start = Int(floor((logicalPosition(-300 + endPull) - endPull - baseY) / Self.pitch))
        let end = Int(ceil((logicalPosition(viewportHeight + 60 + endPull) - endPull - baseY) / Self.pitch)) + 1
        let first = max(0, min(count, start)), last = max(first, min(count, end))
        return first..<last
    }
}

/// One retained scene: papers leave in their screen order while the selected paper lifts in place.
struct ReceiptWalletScene: View {
    @Bindable var workspace: ReceiptWorkspace
    var requestDelete: (ReceiptRecord) -> Void
    @State private var presented: ReceiptRecord?
    @State private var expanded = false
    @State private var paperFrames: [UUID: CGRect] = [:]
    @State private var origin = CGRect.zero
    @State private var readingOffset: CGFloat = 0
    @State private var walletFrame = CGRect.zero
    @State private var walletHeight: CGFloat = 110
    @State private var endBounce: CGFloat = 0
    @State private var jumpToNewest = 0
    @State private var stackHeight: CGFloat = 0
    @State private var measuredCount = 0
    @State private var stackSceneY: CGFloat?
    private let tuckedDepth: CGFloat = 32
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var systemMotion
    @State private var revealedID: UUID?
    private var reduceMotion: Bool { ReceiptAccessibility.reduceMotion(systemMotion) }
    private var selectedID: UUID? { workspace.flow == .detail ? workspace.selected?.id : nil }
    private var records: [ReceiptRecord] { Array(workspace.orderedReceipts.filter { !$0.isArchived }.reversed()) }
    private var motion: Animation { reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.56, dampingFraction: 0.86) }
    private var elastic: Bool { !reduceMotion && !typeSize.isAccessibilitySize }

    var body: some View {
        GeometryReader { geometry in
            let viewportHeight = geometry.size.height
            ZStack(alignment: .topLeading) {
                if !records.isEmpty {
                    walletBack(in: geometry)
                        .offset(x: 20, y: geometry.size.height - walletHeight - 32 - endBounce)
                        .opacity(presented == nil ? 1 : 0)
                        .zIndex(-1)
                        .allowsHitTesting(false).accessibilityHidden(true)
                }
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 0) {
                            if records.isEmpty {
                                VStack(spacing: 24) {
                                    EmptyWalletArtwork().frame(width: 240, height: 190)
                                    VStack(spacing: 10) {
                                        Text(workspace.receipts.isEmpty ? "A place for your receipts" : "Your wallet is clear").font(.title2.weight(.semibold))
                                        Text(workspace.receipts.isEmpty ? "Import a photo. Keep the details." : "Find archived receipts in Settings.").font(.body)
                                    }.multilineTextAlignment(.center)
                                    Label("Private · on this device", systemImage: "lock").font(.footnote).padding(.top, 4)
                                }
                                .padding(.horizontal, 8).padding(.vertical, 32)
                                .frame(maxWidth: .infinity, minHeight: max(0, geometry.size.height - 140))
                                .opacity(selectedID == nil ? 1 : 0)
                                if let notice = workspace.notice {
                                    Text(notice).font(.footnote).padding(.top, 24).opacity(selectedID == nil ? 1 : 0)
                                }
                            } else {
                                VStack(spacing: 0) {
                                    if let notice = workspace.notice {
                                        Text(notice).font(.footnote).padding(.bottom, 16).opacity(selectedID == nil ? 1 : 0)
                                    }
                                    if elastic {
                                        elasticStack(in: geometry)
                                    } else { LazyVStack(spacing: typeSize.isAccessibilitySize ? 14 : -108) {
                                        ForEach(Array(records.enumerated()), id: \.element.id) { index, record in
                                            card(record, index: index, height: geometry.size.height)
                                                .id(record.id).zIndex(revealedID == record.id ? Double(records.count + 1) : Double(index + 1))
                                                .onGeometryChange(for: CGRect.self) { proxy in
                                                    let bounds = proxy.frame(in: .named("walletScene"))
                                                    return CGRect(x: bounds.midX - proxy.size.width / 2, y: bounds.midY - proxy.size.height / 2,
                                                                  width: proxy.size.width, height: proxy.size.height)
                                                } action: { if presented == nil { paperFrames[record.id] = $0 } }
                                                .rotationEffect(.degrees(tilt(index)))
                                        }
                                    }.padding(.horizontal, 10) }
                                }
                                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                                    if presented == nil { stackHeight = $0; measuredCount = records.count }
                                }
                                .padding(.top, stackTop(in: geometry))
                                // Even at the last scroll position, the paper stays inside the pocket.
                                Color.clear.frame(height: max(0, walletHeight + 20 - tuckedDepth)).id("walletEnd")
                            }
                            #if DEBUG
                            if records.isEmpty { WorkflowTestControls(workspace: workspace) }
                            #endif
                        }.padding(.horizontal, 20).padding(.top, records.isEmpty ? 14 : 0).padding(.bottom, records.isEmpty ? 24 : 0)
                            .onGeometryChange(for: CGFloat.self) { content in
                                // Measure the actual stack end, including native rubber-banding.
                                // For a short stack, its resting end is above the viewport bottom.
                                let restingEnd = min(viewportHeight, content.size.height)
                                return max(0, restingEnd - content.frame(in: .named("walletScene")).maxY)
                            } action: { pull in
                                if presented == nil { endBounce = reduceMotion ? 0 : pull }
                            }
                    }
                    .onChange(of: jumpToNewest) { _, _ in
                        withAnimation(motion) { proxy.scrollTo("walletEnd", anchor: .bottom) }
                    }
                    .scrollDisabled(presented != nil)
                    .accessibilityHidden(presented != nil)
                    .scrollBounceBehavior(.always)
                    .walletScreenEdges(in: geometry)
                }
                if !records.isEmpty {
                    pocketBacking(in: geometry)
                        .offset(y: geometry.size.height - 32 - endBounce)
                        .opacity(presented == nil ? 1 : 0)
                        .zIndex(Double(records.count) + 1.9)
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        walletPocket { jumpToNewest += 1 }
                            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("walletScene")) } action: {
                                walletHeight = $0.height
                                if presented == nil { walletFrame = $0 }
                            }
                            .padding(.horizontal, 20).padding(.bottom, 20)
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .offset(y: -endBounce)
                    .opacity(presented == nil ? 1 : 0)
                    .accessibilityHidden(presented != nil)
                    .zIndex(Double(records.count + 2))
                }
                if let presented {
                    let selectedIndex = records.firstIndex { $0.id == presented.id } ?? records.count
                    liftedPaper(workspace.selected ?? presented, geometry: geometry)
                        .zIndex(Double(selectedIndex + 1))
                    // Foreground papers live beside the lifted paper, rather than behind its overlay.
                    // Their z-order never changes when the selected paper returns.
                    ForEach(Array(records.enumerated()).filter { $0.offset > selectedIndex }, id: \.element.id) { index, record in
                        if let frame = paperFrames[record.id] {
                            ReceiptPreviewSurface(record: record)
                                .frame(width: frame.width, height: frame.height)
                                .rotationEffect(.degrees(tilt(index)))
                                .offset(x: frame.minX, y: frame.minY + (expanded && !reduceMotion ? geometry.size.height + 350 : 0))
                                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
                                .opacity(expanded && reduceMotion ? 0 : 1)
                                .zIndex(Double(index + 1))
                                .allowsHitTesting(false).accessibilityHidden(true)
                        }
                    }
                    if walletFrame != .zero {
                        walletBack(in: geometry)
                            .offset(x: walletFrame.minX, y: walletFrame.minY - 12 + (expanded && !reduceMotion ? geometry.size.height + 350 : 0))
                            .opacity(expanded && reduceMotion ? 0 : 1)
                            .zIndex(-1)
                            .allowsHitTesting(false).accessibilityHidden(true)
                        pocketBacking(in: geometry)
                            .offset(y: walletFrame.maxY - 12 + (expanded && !reduceMotion ? geometry.size.height + 350 : 0))
                            .opacity(expanded && reduceMotion ? 0 : 1)
                            .zIndex(Double(records.count) + 1.9)
                        walletPocket {}
                            .frame(width: walletFrame.width, height: walletFrame.height)
                            .offset(x: walletFrame.minX, y: walletFrame.minY + (expanded && !reduceMotion ? geometry.size.height + 350 : 0))
                            .opacity(expanded && reduceMotion ? 0 : 1)
                            .zIndex(Double(records.count + 2))
                            .allowsHitTesting(false).accessibilityHidden(true)
                    }
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
            .coordinateSpace(name: "walletScene")
            .animation(motion, value: records.map(\.id))
            .onChange(of: selectedID, initial: true) { _, next in
                revealedID = nil
                if next != nil, let record = workspace.selected {
                    presented = record
                    readingOffset = 0
                    origin = paperFrames[record.id] ?? CGRect(x: 30, y: 52, width: geometry.size.width - 60, height: 244)
                    // Mount the same opaque paper at its original rectangle before moving it.
                    expanded = false
                } else if presented != nil {
                    withAnimation(motion, completionCriteria: .removed) { expanded = false } completion: {
                        if selectedID == nil { presented = nil }
                    }
                }
            }
            .task(id: presented?.id) {
                guard presented != nil, selectedID != nil else { return }
                try? await Task.sleep(for: .milliseconds(24))
                guard !Task.isCancelled, selectedID != nil else { return }
                withAnimation(motion) { expanded = true }
            }
        }
    }
    private func projection(in geometry: GeometryProxy) -> ReceiptStackProjection {
        let fullHeight = geometry.size.height + geometry.safeAreaInsets.top + geometry.safeAreaInsets.bottom
        return ReceiptStackProjection(viewportHeight: geometry.size.height,
            readingY: fullHeight / 3 - geometry.safeAreaInsets.top,
            anchor: geometry.size.height - walletHeight - 20 + tuckedDepth - ReceiptStackProjection.paperHeight)
    }
    private func elasticStack(in geometry: GeometryProxy) -> some View {
        let snapshot = records
        let curve = projection(in: geometry)
        let baseY = stackSceneY ?? stackTop(in: geometry)
        let visible = curve.visibleIndices(baseY: baseY, count: snapshot.count, endPull: endBounce)
        let ids = visible.map { snapshot[$0].id }
        return ZStack(alignment: .topLeading) {
            ForEach(visible, id: \.self) { index in
                let record = snapshot[index]
                let y = curve.displayedPosition(baseY + CGFloat(index) * ReceiptStackProjection.pitch, endPull: endBounce)
                card(record, index: index, height: geometry.size.height)
                    .frame(height: ReceiptStackProjection.paperHeight)
                    .id(record.id).zIndex(revealedID == record.id ? Double(records.count + 1) : Double(index + 1))
                    .rotationEffect(.degrees(tilt(index)))
                    .offset(y: y - baseY)
                    .onGeometryChange(for: CGRect.self) { proxy in
                        let bounds = proxy.frame(in: .named("walletScene"))
                        return CGRect(x: bounds.midX - proxy.size.width / 2, y: bounds.midY - proxy.size.height / 2,
                                      width: proxy.size.width, height: proxy.size.height)
                    } action: { if presented == nil { paperFrames[record.id] = $0 } }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: CGFloat(max(0, snapshot.count - 1)) * ReceiptStackProjection.pitch + ReceiptStackProjection.paperHeight, alignment: .topLeading)
        .onGeometryChange(for: CGFloat.self) { $0.frame(in: .named("walletScene")).minY } action: {
            if presented == nil { stackSceneY = $0 }
        }
        .onChange(of: ids, initial: true) { _, visibleIDs in
            if presented == nil { paperFrames = paperFrames.filter { visibleIDs.contains($0.key) } }
        }
        .padding(.horizontal, 10)
    }
    private func card(_ record: ReceiptRecord, index: Int, height: CGFloat) -> some View {
        let focus = presented?.id == record.id
        let selectedIndex = records.firstIndex { $0.id == presented?.id }
        let departure: CGFloat = selectedIndex.map { index < $0 ? -height - 350 : height + 350 } ?? (presented == nil ? 0 : height + 350)
        return ReceiptSwipePaper(record: record, settings: workspace.walletSettings, revealedID: $revealedID, identifier: "receipt-\(index)") {
            if revealedID != nil { withAnimation(motion) { revealedID = nil } }
            else { workspace.open(record) }
        } perform: { action in
            withAnimation(motion) { revealedID = nil }
            if action == .delete { requestDelete(record) } else { workspace.organize(record, action: action) }
        }
        .offset(y: !expanded || focus || reduceMotion ? 0 : departure)
        .opacity(focus || (presented != nil && index > (selectedIndex ?? records.count)) || (expanded && reduceMotion) ? 0 : 1)
        .allowsHitTesting(presented == nil)
    }
    private func stackTop(in geometry: GeometryProxy) -> CGFloat {
        if elastic {
            let curve = projection(in: geometry)
            return max(curve.logicalPosition(14), curve.anchor - CGFloat(max(0, records.count - 1)) * ReceiptStackProjection.pitch)
        }
        let estimate = CGFloat(max(0, records.count - 1)) * (typeSize.isAccessibilitySize ? 258 : 136) + 244
        let height = measuredCount == records.count && stackHeight > 0 ? stackHeight : estimate
        let pocketTop = geometry.size.height - walletHeight - 20
        return max(14, pocketTop + tuckedDepth - height)
    }
    private func tilt(_ index: Int) -> Double {
        typeSize.isAccessibilitySize ? 0 : [-1.0, 0.7, -0.5, 1.1][index % 4]
    }
    private func walletPocket(_ jump: @escaping () -> Void) -> some View {
        WalletCrown(count: records.count, jumpToLatest: jump).fixedSize(horizontal: false, vertical: true)
            .allowsHitTesting(presented == nil)
    }
    private func pocketBacking(in geometry: GeometryProxy) -> some View {
        // A separate, non-interactive layer conceals paper below the pocket without covering controls.
        Color(uiColor: .systemGroupedBackground)
            .frame(width: geometry.size.width, height: 32 + geometry.safeAreaInsets.bottom)
            .allowsHitTesting(false).accessibilityHidden(true)
    }
    private func walletBack(in geometry: GeometryProxy) -> some View {
        WalletBackPanel().frame(width: geometry.size.width - 40, height: walletHeight + 12)
    }
    private func liftedPaper(_ record: ReceiptRecord, geometry: GeometryProxy) -> some View {
        ScrollView {
            WalletLiftedPaper(record: record, expanded: expanded, origin: origin,
                              width: geometry.size.width - 60, viewportHeight: geometry.size.height,
                              returnOffset: readingOffset, tilt: tilt(records.firstIndex { $0.id == record.id } ?? 0),
                              reduceMotion: reduceMotion, error: workspace.errorMessage,
                              loading: workspace.image == nil && workspace.errorMessage == nil)
        }
        .walletScreenEdges(in: geometry)
        .scrollDisabled(!expanded)
        .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y + $0.contentInsets.top } action: { _, offset in
            if expanded { readingOffset = offset }
        }
        .accessibilityIdentifier("detailScreen")
        .accessibilityHidden(selectedID == nil)
    }

}

/// A single paper silhouette changes its rectangle; its torn bottom travels with that rectangle.
private struct WalletLiftedPaper: View {
    let record: ReceiptRecord
    let expanded: Bool
    let origin: CGRect
    let width: CGFloat
    let viewportHeight: CGFloat
    let returnOffset: CGFloat
    let tilt: Double
    let reduceMotion: Bool
    let error: String?
    let loading: Bool
    @State private var fullHeight: CGFloat = 244
    @Environment(\.dynamicTypeSize) private var typeSize
    private var reading: Bool { expanded || reduceMotion }
    private var paperWidth: CGFloat { reading ? width : origin.width }
    private var paperHeight: CGFloat { reading ? fullHeight : origin.height }
    var body: some View {
        ZStack(alignment: .topLeading) {
            HStack {
                Label(ReceiptCompletion.isComplete(record) ? "Reviewed" : "Needs review", systemImage: ReceiptCompletion.isComplete(record) ? "checkmark.circle" : "exclamationmark.circle")
                Spacer()
                if record.isStarred { Image(systemName: "star.fill").accessibilityLabel("Starred") }
            }.font(.footnote.weight(.medium)).padding(.horizontal, 34).padding(.top, 10)
                .opacity(expanded ? 1 : 0)
            ZStack(alignment: .topLeading) {
                ReceiptPaper(fields: record.current.fields, input: record.current.reviewInput.flatMap { try? JSONDecoder().decode(ReceiptReviewDraft.self, from: $0) }, showsSurface: false)
                    .frame(width: paperWidth).fixedSize(horizontal: false, vertical: true)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { fullHeight = $0 }
                    .opacity(expanded ? 1 : 0).accessibilityHidden(!expanded)
                ReceiptPreviewPaper(record: record)
                    .frame(width: paperWidth).opacity(expanded ? 0 : 1).accessibilityHidden(true)
            }
            .frame(width: paperWidth, height: paperHeight, alignment: .topLeading)
            .clipShape(ReceiptPaperEdge())
            .background { ReceiptPaperBackground(fade: !expanded && record.current.fields.items.count > 3 && !typeSize.isAccessibilitySize ? 1 : 0) }
            .receiptPaperStyle()
            .rotationEffect(.degrees(reading ? 0 : tilt))
            .offset(x: reading ? 30 : origin.minX, y: reading ? 52 : origin.minY + returnOffset)
            VStack(alignment: .leading, spacing: 18) {
                if loading { ProgressView("Loading original").font(.footnote) }
                if let error { Text(error).font(.subheadline) }
                if record.current.fields.currency == nil { Text("Currency needs confirmation. Edit to check the saved amounts.").font(.footnote) }
                Label("Saved on this device", systemImage: "lock").font(.footnote)
            }.padding(.horizontal, 30).offset(y: fullHeight + 74).opacity(expanded ? 1 : 0)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: max(viewportHeight, fullHeight + 180), alignment: .topLeading)
    }
}

private struct WalletCrown: View {
    let count: Int
    var jumpToLatest: () -> Void
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Wallet").font(.system(.title2, design: .serif, weight: .semibold))
                    .shadow(color: .white.opacity(scheme == .dark ? 0.08 : 0.25), radius: 0, y: 1)
                    .accessibilityIdentifier("walletHeading")
                Text("\(count) saved").font(.subheadline)
            }
            Spacer(minLength: 6)
            if count > 3 {
                Button(action: jumpToLatest) { Image(systemName: "arrow.down").frame(width: 44, height: 44) }
                    .buttonStyle(.glass).accessibilityLabel("Jump to newest receipt").accessibilityIdentifier("latestReceipt")
            } else {
                Image(systemName: "wallet.bifold").font(.title2.weight(.light)).opacity(0.75).accessibilityHidden(true)
            }
        }
        .foregroundStyle(scheme == .dark ? Color(red: 0.99, green: 0.92, blue: 0.83) : Color(red: 0.12, green: 0.06, blue: 0.03))
        .padding(.horizontal, 28).padding(.top, 26).padding(.bottom, 26)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { LeatherWalletSurface() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("walletPocket")
    }
}

/// A shallow scooped mouth sits in front of the inserted papers, with a separate leather welt.
private struct WalletPocketFace: Shape {
    func path(in r: CGRect) -> Path {
        let w = r.width, h = r.height, corner: CGFloat = min(28, h / 3)
        var p = Path()
        p.move(to: CGPoint(x: 0, y: corner))
        p.addQuadCurve(to: CGPoint(x: corner, y: 8), control: CGPoint(x: 0, y: 8))
        p.addCurve(to: CGPoint(x: w - corner, y: 8), control1: CGPoint(x: w * 0.3, y: 18), control2: CGPoint(x: w * 0.7, y: 18))
        p.addQuadCurve(to: CGPoint(x: w, y: corner), control: CGPoint(x: w, y: 8))
        p.addLine(to: CGPoint(x: w, y: h - corner))
        p.addQuadCurve(to: CGPoint(x: w - corner, y: h), control: CGPoint(x: w, y: h))
        p.addLine(to: CGPoint(x: corner, y: h))
        p.addQuadCurve(to: CGPoint(x: 0, y: h - corner), control: CGPoint(x: 0, y: h))
        p.closeSubpath(); return p
    }
}

private struct WalletStitch: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 9, y: 32)); p.addLine(to: CGPoint(x: 9, y: r.height - 28))
        p.addQuadCurve(to: CGPoint(x: 28, y: r.height - 9), control: CGPoint(x: 9, y: r.height - 9))
        p.addLine(to: CGPoint(x: r.width - 28, y: r.height - 9))
        p.addQuadCurve(to: CGPoint(x: r.width - 9, y: r.height - 28), control: CGPoint(x: r.width - 9, y: r.height - 9))
        p.addLine(to: CGPoint(x: r.width - 9, y: 32)); return p
    }
}

private struct LeatherWalletSurface: View {
    @Environment(\.colorScheme) private var scheme
    private var dark: Bool { scheme == .dark }
    var body: some View {
        ZStack {
            // Only the front welt and face belong here. The back is a scene sibling below all papers.
            WalletPocketFace().fill(LinearGradient(colors: dark ? [Color(red: 0.49, green: 0.32, blue: 0.21), Color(red: 0.25, green: 0.14, blue: 0.08)] : [Color(red: 0.81, green: 0.62, blue: 0.43), Color(red: 0.49, green: 0.28, blue: 0.16)], startPoint: .top, endPoint: .bottom))
                .overlay { WalletPocketFace().stroke(.white.opacity(0.16), lineWidth: 1) }
            WalletPocketFace().fill(Color(red: 0.18, green: 0.09, blue: 0.05)).padding(.horizontal, 6).padding(.top, 1).padding(.bottom, 6)
            WalletPocketFace()
                .fill(LinearGradient(colors: dark ? [Color(red: 0.48, green: 0.31, blue: 0.20), Color(red: 0.34, green: 0.19, blue: 0.11)] : [Color(red: 0.78, green: 0.57, blue: 0.39), Color(red: 0.67, green: 0.43, blue: 0.27)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay {
                    Canvas { context, size in
                        // Fixed, sparse grain: no image assets, randomness or moving texture.
                        for row in 0..<Int(size.height / 3) {
                            for column in 0..<Int(size.width / 3) {
                                let seed = (row * 37 + column * 17) % 19
                                let rect = CGRect(x: CGFloat(column * 3) + CGFloat(seed % 3) * 0.3,
                                                  y: CGFloat(row * 3), width: 0.7, height: 0.9)
                                context.fill(Path(ellipseIn: rect), with: .color(seed % 2 == 0 ? .white.opacity(0.08) : .black.opacity(0.07)))
                            }
                        }
                    }.clipShape(WalletPocketFace())
                }
                .overlay { WalletPocketFace().stroke(.black.opacity(0.22), lineWidth: 1) }
                .overlay { WalletPocketFace().stroke(.white.opacity(0.14), lineWidth: 0.7).padding(1) }
                .overlay {
                    WalletStitch().stroke(.black.opacity(0.22), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: [2, 5]))
                    WalletStitch().stroke(Color(red: 0.94, green: 0.76, blue: 0.55).opacity(dark ? 0.38 : 0.65), style: StrokeStyle(lineWidth: 1, lineCap: .round, dash: [2, 5]))
                        .offset(y: -0.5)
                }
                .padding(.horizontal, 4).padding(.bottom, 4)
        }
        .compositingGroup()
        .shadow(color: .black.opacity(dark ? 0.4 : 0.2), radius: 14, y: 8)
        .shadow(color: .black.opacity(0.18), radius: 2, y: 2)
        .allowsHitTesting(false).accessibilityHidden(true)
    }
}

private struct WalletBackPanel: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        RoundedRectangle(cornerRadius: 28)
            .fill(LinearGradient(colors: scheme == .dark ? [Color(red: 0.35, green: 0.21, blue: 0.13), Color(red: 0.25, green: 0.14, blue: 0.08)] : [Color(red: 0.62, green: 0.40, blue: 0.25), Color(red: 0.49, green: 0.28, blue: 0.16)], startPoint: .top, endPoint: .bottom))
            .overlay { RoundedRectangle(cornerRadius: 28).stroke(.white.opacity(0.2), lineWidth: 0.8) }
            .overlay { RoundedRectangle(cornerRadius: 24).stroke(.black.opacity(0.22), lineWidth: 1).padding(4) }
    }
}

private struct ReceiptPaperAppearanceKey: EnvironmentKey {
    static let defaultValue: ReceiptPaperAppearance = .matchAppearance
}
extension EnvironmentValues {
    var receiptPaperAppearance: ReceiptPaperAppearance {
        get { self[ReceiptPaperAppearanceKey.self] }
        set { self[ReceiptPaperAppearanceKey.self] = newValue }
    }
}
private struct ReceiptPaperStyle: ViewModifier {
    @Environment(\.receiptPaperAppearance) private var appearance
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View {
        content.environment(\.colorScheme, appearance == .alwaysWhite ? .light : scheme)
    }
}
extension View {
    func receiptPaperStyle() -> some View { modifier(ReceiptPaperStyle()) }
}

/// A modest torn edge and opaque reading surface; long previews fade toward their bottom.
struct ReceiptPaperEdge: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let radius: CGFloat = 12
        p.move(to: CGPoint(x: 0, y: radius))
        p.addQuadCurve(to: CGPoint(x: radius, y: 0), control: .zero)
        p.addLine(to: CGPoint(x: rect.maxX - radius, y: 0))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: radius), control: CGPoint(x: rect.maxX, y: 0))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - 4))
        let steps = max(1, Int(rect.width / 12))
        for step in stride(from: steps, through: 0, by: -1) {
            p.addLine(to: CGPoint(x: rect.width * CGFloat(step) / CGFloat(steps), y: rect.maxY - (step % 2 == 0 ? 4 : 0)))
        }
        p.closeSubpath(); return p
    }
}

struct ReceiptPaperBackground: View {
    var fade: CGFloat = 0
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var systemContrast
    private var contrast: ColorSchemeContrast { ReceiptAccessibility.contrast(systemContrast) }
    var body: some View {
        ReceiptPaperEdge().fill(Color(uiColor: .secondarySystemGroupedBackground))
            .overlay { ReceiptPaperEdge().stroke(.primary.opacity(contrast == .increased ? 0.6 : 0.12), lineWidth: 0.5) }
            .mask {
                LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.78),
                                       .init(color: .black.opacity(1 - fade), location: 1)], startPoint: .top, endPoint: .bottom)
            }
            .compositingGroup()
            .shadow(color: .black.opacity(scheme == .dark ? 0.45 : 0.16), radius: 12, y: 6)
            .shadow(color: .black.opacity(scheme == .dark ? 0.3 : 0.12), radius: 2, y: 2)
    }
}

private struct ReceiptSwipePaper: View {
    let record: ReceiptRecord
    let settings: ReceiptWalletSettings
    @Binding var revealedID: UUID?
    let identifier: String
    var open: () -> Void
    var perform: (ReceiptWalletAction) -> Void
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var systemMotion
    @State private var offset: CGFloat = 0
    @State private var horizontal = false
    private var action: ReceiptWalletAction { offset < 0 ? settings.leftSwipe : settings.rightSwipe }
    private var animation: Animation { ReceiptAccessibility.reduceMotion(systemMotion) ? .easeOut(duration: 0.1) : .spring(response: 0.32, dampingFraction: 0.88) }
    var body: some View {
        ZStack(alignment: offset < 0 ? .topTrailing : .topLeading) {
            if revealedID == record.id, action != .none {
                let distance = abs(offset)
                let progress = min(1, distance / 108)
                Button { perform(action) } label: {
                    VStack(spacing: 7) { Image(systemName: action.symbol).font(.title3); Text(action.title(for: record)).font(.caption.weight(.semibold)) }
                        .frame(width: 84, height: typeSize.isAccessibilitySize ? 100 : 78)
                        .scaleEffect(0.65 + 0.35 * progress)
                        .opacity(progress)
                        .frame(width: max(0, distance - 12), height: 44 + 38 * progress)
                        .clipped()
                        .glassEffect(action == .delete ? .regular.tint(.red).interactive() : .regular.interactive(), in: .rect(cornerRadius: 18))
                }.buttonStyle(.plain)
                    .accessibilityLabel(action.title(for: record))
                    .accessibilityIdentifier("swipeAction-\(identifier)")
                    .allowsHitTesting(!horizontal && distance >= 56)
                    .padding(.top, 24)
            }
            ReceiptPreviewSurface(record: record)
                .contentShape(ReceiptPaperEdge())
                .onTapGesture(perform: open)
                .accessibilityElement(children: .ignore)
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { open() }
                .accessibilityLabel(summary)
                .accessibilityHint(revealedID == record.id ? "Closes the swipe action" : "Expands receipt. Swipe left or right for actions.")
                .accessibilityIdentifier(identifier)
                .gesture(ReceiptHorizontalPan { translation, ended in
                    let configured = translation < 0 ? settings.leftSwipe : settings.rightSwipe
                    if !ended {
                        guard configured != .none else { return }
                        horizontal = true; revealedID = record.id
                        offset = max(-180, min(180, translation))
                    } else {
                        withAnimation(animation) {
                            if abs(translation) > 42 && configured != .none { offset = translation < 0 ? -108 : 108; revealedID = record.id }
                            else { offset = 0; revealedID = nil }
                        }
                        horizontal = false
                    }
                })
                .accessibilityRepresentation {
                    Button(action: open) { Text(summary) }
                        .accessibilityIdentifier(identifier)
                        .accessibilityHint(revealedID == record.id ? "Closes the swipe action" : "Expands receipt. Swipe left or right for actions.")
                        .accessibilityAction(named: Text(record.isStarred ? "Unstar" : "Star")) { perform(.star) }
                        .accessibilityAction(named: Text(record.isArchived ? "Unarchive" : "Archive")) { perform(.archive) }
                        .accessibilityAction(named: Text("Delete")) { perform(.delete) }
                }
                .offset(x: revealedID == record.id || horizontal ? offset : 0)
        }
        .onChange(of: revealedID) { _, next in if next != record.id { withAnimation(animation) { offset = 0 } } }
    }
    private var summary: String {
        [record.current.fields.merchant ?? "Merchant missing", ExactInput.dateText(record.current.fields.purchaseDate),
         record.current.fields.total.map { "\($0.currency.code) \(ExactInput.format($0.minorUnits, scale: $0.currency.minorUnitScale))" } ?? "Total missing",
         record.isStarred ? "Starred" : "", ReceiptCompletion.isComplete(record) ? "Reviewed" : "Needs review"].filter { !$0.isEmpty }.joined(separator: ", ")
    }
}

private struct ReceiptPreviewSurface: View {
    let record: ReceiptRecord
    @Environment(\.dynamicTypeSize) private var typeSize
    private var fades: Bool { record.current.fields.items.count > 3 && !typeSize.isAccessibilitySize }
    var body: some View {
        ReceiptPreviewPaper(record: record)
            .mask {
                if fades {
                    LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.78), .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom)
                } else { Color.black }
            }
            .background { ReceiptPaperBackground(fade: fades ? 1 : 0) }
            .receiptPaperStyle()
    }
}

struct ReceiptPreviewPaper: View {
    let record: ReceiptRecord
    @Environment(\.dynamicTypeSize) private var typeSize
    private var fields: ReceiptFields { record.current.fields }
    private var long: Bool { fields.items.count > 2 || fields.items.contains { ($0.description?.count ?? 0) > 40 } }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                Text(fields.merchant ?? "Merchant missing").font(.headline).lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                Spacer(minLength: 8)
                if record.isStarred { Image(systemName: "star.fill").font(.caption) }
            }
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) { Text(ExactInput.dateText(fields.purchaseDate).nilIfEmpty ?? "Date missing").font(.footnote); Spacer(); total }
                VStack(alignment: .leading, spacing: 6) { Text(ExactInput.dateText(fields.purchaseDate).nilIfEmpty ?? "Date missing").font(.footnote); total }
            }
            if !ReceiptCompletion.isComplete(record) { Label("Needs review", systemImage: "exclamationmark.circle").font(.caption) }
            PaperRule().stroke(.primary.opacity(0.18), style: StrokeStyle(lineWidth: 1, dash: [3, 3])).frame(height: 1)
            VStack(alignment: .leading, spacing: 9) {
                ForEach(fields.items.prefix(long ? 6 : 3)) { item in
                    HStack(alignment: .firstTextBaseline) {
                        Text(item.description ?? "Description missing").lineLimit(1)
                        Spacer(minLength: 10)
                        Text(item.amount.map { ExactInput.format($0.minorUnits, scale: $0.currency.minorUnitScale) } ?? "—").monospacedDigit()
                    }.font(.system(.footnote, design: .monospaced))
                }
                if fields.items.isEmpty { Text("Purchases need review").font(.footnote) }
            }
            .frame(maxHeight: typeSize.isAccessibilitySize ? nil : (long ? 126 : 68), alignment: .top)
            .clipped()
            .mask {
                if long && !typeSize.isAccessibilitySize {
                    LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.45), .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom)
                } else { Color.black }
            }
            if !typeSize.isAccessibilitySize { Spacer(minLength: 0) }
            if !long || typeSize.isAccessibilitySize { HStack {
                Text("\(fields.items.count) \(fields.items.count == 1 ? "item" : "items")")
                Spacer()
                Image(systemName: "arrow.up.left.and.arrow.down.right")
            }.font(.caption).padding(.bottom, 4) }
        }
        .foregroundStyle(.primary).padding(.horizontal, 22).padding(.top, 30).padding(.bottom, 14)
        .frame(height: typeSize.isAccessibilitySize ? nil : 244, alignment: .top)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    private var total: some View {
        Text(fields.total.map { "\($0.currency.code) \(ExactInput.format($0.minorUnits, scale: $0.currency.minorUnitScale))" } ?? "Total missing")
            .font(.subheadline.weight(.semibold)).monospacedDigit()
    }
}

struct PaperRule: Shape {
    func path(in rect: CGRect) -> Path { var p = Path(); p.move(to: .zero); p.addLine(to: CGPoint(x: rect.width, y: 0)); return p }
}

struct ReceiptWalletSettingsView: View {
    @Bindable var workspace: ReceiptWorkspace
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Receipt paper", selection: Binding(get: { workspace.walletSettings.paperAppearance }, set: { appearance in
                        var settings = workspace.walletSettings
                        settings.paperAppearance = appearance
                        workspace.setWalletSettings(settings)
                    })) {
                        ForEach(ReceiptPaperAppearance.allCases) { Text($0.title).tag($0) }
                    }.accessibilityIdentifier("paperAppearanceSetting")
                } header: { Text("Appearance") } footer: { Text("Keep receipts white, or let the paper follow Light and Dark Mode.") }
                Section {
                    actionPicker("Swipe left", left: true).accessibilityIdentifier("leftSwipeSetting")
                    actionPicker("Swipe right", left: false).accessibilityIdentifier("rightSwipeSetting")
                } header: { Text("Receipt actions") } footer: { Text("Swipe to reveal an action, then tap it. Delete always asks for confirmation.") }
                Section {
                    Button("Archive", systemImage: "archivebox") {
                        workspace.collection = "Archive"; workspace.library = true; dismiss()
                    }.accessibilityIdentifier("openArchive")
                    Button("Starred", systemImage: "star") {
                        workspace.collection = "Starred"; workspace.library = true; dismiss()
                    }.accessibilityIdentifier("openStarred")
                }
                if let notice = workspace.notice { Section { Text(notice) } }
            }
            .navigationTitle("Settings").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .disabled(workspace.saving)
        }.tint(.primary)
    }
    private func actionPicker(_ label: String, left: Bool) -> some View {
        Picker(label, selection: Binding(get: { left ? workspace.walletSettings.leftSwipe : workspace.walletSettings.rightSwipe }, set: { action in
            var settings = workspace.walletSettings
            if left { settings.leftSwipe = action } else { settings.rightSwipe = action }
            workspace.setWalletSettings(settings)
        })) { ForEach(ReceiptWalletAction.allCases) { Text($0.title).tag($0) } }
    }
}

/// Reject vertical pans before recognition so the surrounding ScrollView keeps its native gesture.
private struct ReceiptHorizontalPan: UIGestureRecognizerRepresentable {
    var change: (CGFloat, Bool) -> Void
    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }
    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let gesture = UIPanGestureRecognizer()
        gesture.maximumNumberOfTouches = 1
        gesture.delegate = context.coordinator
        return gesture
    }
    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
        switch recognizer.state {
        case .began, .changed: change(recognizer.translation(in: recognizer.view).x, false)
        case .ended: change(recognizer.translation(in: recognizer.view).x, true)
        case .cancelled, .failed: change(0, true)
        default: break
        }
    }
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return false }
            let velocity = pan.velocity(in: pan.view)
            return abs(velocity.x) > abs(velocity.y) * 1.35
        }
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool { true }
    }
}

private struct EmptyWalletArtwork: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
                .overlay(alignment: .top) {
                    VStack(alignment: .leading, spacing: 10) {
                        RoundedRectangle(cornerRadius: 2).fill(.primary.opacity(0.23)).frame(width: 52, height: 5)
                        ForEach(0..<4) { index in
                            HStack {
                                RoundedRectangle(cornerRadius: 2).fill(.primary.opacity(0.12)).frame(width: index == 2 ? 52 : 72, height: 3)
                                Spacer()
                                RoundedRectangle(cornerRadius: 2).fill(.primary.opacity(0.12)).frame(width: 24, height: 3)
                            }
                        }
                    }.padding(20)
                }
                .overlay { RoundedRectangle(cornerRadius: 16).stroke(.primary.opacity(0.08), lineWidth: 0.5) }
                .frame(width: 164, height: 166).rotationEffect(.degrees(-6)).offset(x: -4, y: -18)
                .shadow(color: .black.opacity(scheme == .dark ? 0.4 : 0.1), radius: 16, x: 0, y: 9)
            RoundedRectangle(cornerRadius: 23)
                .fill(LinearGradient(colors: [Color(uiColor: .tertiarySystemGroupedBackground), Color(uiColor: .secondarySystemGroupedBackground)], startPoint: .top, endPoint: .bottom))
                .overlay { RoundedRectangle(cornerRadius: 23).stroke(.primary.opacity(0.12), lineWidth: 0.5) }
                .overlay(alignment: .top) { Capsule().fill(.primary.opacity(0.1)).frame(height: 1).padding(.horizontal, 18).padding(.top, 12) }
                .overlay { Image(systemName: "wallet.bifold").font(.system(size: 23, weight: .light)).foregroundStyle(.primary.opacity(0.55)) }
                .frame(width: 218, height: 87)
                .shadow(color: .black.opacity(scheme == .dark ? 0.35 : 0.1), radius: 18, x: 0, y: 10)
        }.accessibilityHidden(true)
    }
}

private extension View {
    func walletScreenEdges(in geometry: GeometryProxy) -> some View {
        let top = geometry.safeAreaInsets.top
        let bottom = geometry.safeAreaInsets.bottom
        // Scroll beneath the system bars; preserve safe resting positions with content margins.
        // The native effect belongs at the screen edges, not around a central paper rectangle.
        return self
            .scrollClipDisabled()
            .scrollEdgeEffectStyle(.soft, for: .vertical)
            .contentMargins(.top, top, for: .scrollContent)
            .contentMargins(.bottom, bottom, for: .scrollContent)
            .frame(width: geometry.size.width, height: geometry.size.height + top + bottom)
            .offset(y: -top)
    }
}
