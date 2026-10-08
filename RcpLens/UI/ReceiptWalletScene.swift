import SwiftUI
import UIKit

/// One retained scene: papers leave in their screen order while the selected paper lifts in place.
struct ReceiptWalletScene: View {
    @Bindable var workspace: ReceiptWorkspace
    var requestDelete: (ReceiptRecord) -> Void
    @Namespace private var paperSpace
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var systemMotion
    @State private var revealedID: UUID?
    private var reduceMotion: Bool { ReceiptAccessibility.reduceMotion(systemMotion) }
    private var selectedID: UUID? { workspace.flow == .detail ? workspace.selected?.id : nil }
    private var records: [ReceiptRecord] { Array(workspace.orderedReceipts.filter { !$0.isArchived }.reversed()) }
    private var motion: Animation { reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.56, dampingFraction: 0.86) }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {
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
                            } else {
                                WalletCrown(count: records.count) {
                                    if let last = records.last { withAnimation(motion) { proxy.scrollTo(last.id, anchor: .bottom) } }
                                }
                                .padding(.bottom, -20)
                                .offset(y: selectedID == nil || reduceMotion ? 0 : -geometry.size.height)
                                .opacity(selectedID != nil && reduceMotion ? 0 : 1)
                                .zIndex(Double(records.count + 2))
                                LazyVStack(spacing: typeSize.isAccessibilitySize ? 14 : -108) {
                                    ForEach(Array(records.enumerated()), id: \.element.id) { index, record in
                                        card(record, index: index, height: geometry.size.height)
                                            .id(record.id).zIndex(Double(index + 1))
                                    }
                                }.padding(.horizontal, 10)
                            }
                            if let notice = workspace.notice {
                                Text(notice).font(.footnote).padding(.top, 24).opacity(selectedID == nil ? 1 : 0)
                            }
                            #if DEBUG
                            WorkflowTestControls(workspace: workspace)
                            #endif
                        }.padding(.horizontal, 20).padding(.top, 10).padding(.bottom, 90)
                    }
                    .scrollDisabled(selectedID != nil)
                    .accessibilityHidden(selectedID != nil)
                }
                if let record = workspace.selected, selectedID != nil {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            HStack {
                                Label(ReceiptCompletion.isComplete(record) ? "Reviewed" : "Needs review", systemImage: ReceiptCompletion.isComplete(record) ? "checkmark.circle" : "exclamationmark.circle")
                                Spacer()
                                if record.isStarred { Image(systemName: "star.fill").accessibilityLabel("Starred") }
                            }.font(.footnote.weight(.medium)).padding(.horizontal, 4)
                            ReceiptPaper(fields: record.current.fields, input: record.current.reviewInput.flatMap { try? JSONDecoder().decode(ReceiptReviewDraft.self, from: $0) }, paperSpace: reduceMotion ? nil : paperSpace, paperID: record.id)
                            if workspace.image == nil && workspace.errorMessage == nil { ProgressView("Loading original").font(.footnote) }
                            if let error = workspace.errorMessage { Text(error).font(.subheadline) }
                            if record.current.fields.currency == nil { Text("Currency needs confirmation. Edit to check the saved amounts.").font(.footnote) }
                            Label("Saved on this device", systemImage: "lock").font(.footnote)
                            #if DEBUG
                            WorkflowDetailTestControls(workspace: workspace)
                            #endif
                        }.padding(.horizontal, 30).padding(.top, 10).padding(.bottom, 90)
                    }
                    .accessibilityIdentifier("detailScreen")
                    .transition(.opacity.animation(.easeOut(duration: 0.12)))
                    .zIndex(Double(records.count + 3))
                }
            }
            .clipped()
            .animation(motion, value: selectedID)
            .animation(motion, value: records.map(\.id))
            .onChange(of: selectedID) { _, _ in revealedID = nil }
        }
    }
    private func card(_ record: ReceiptRecord, index: Int, height: CGFloat) -> some View {
        let focus = selectedID == record.id
        let selectedIndex = records.firstIndex { $0.id == selectedID }
        let departure: CGFloat = selectedIndex.map { index < $0 ? -height - 350 : height + 350 } ?? (selectedID == nil ? 0 : height + 350)
        return ReceiptSwipePaper(record: record, settings: workspace.walletSettings, revealedID: $revealedID, hidden: focus,
                                 paperSpace: reduceMotion ? nil : paperSpace, identifier: "receipt-\(index)") {
            if revealedID != nil { withAnimation(motion) { revealedID = nil } }
            else { workspace.open(record) }
        } perform: { action in
            withAnimation(motion) { revealedID = nil }
            if action == .delete { requestDelete(record) } else { workspace.organize(record, action: action) }
        }
        .offset(y: selectedID == nil || focus || reduceMotion ? 0 : departure)
        .opacity(focus || (selectedID != nil && reduceMotion) ? 0 : 1)
        .animation(.easeOut(duration: 0.1), value: focus)
        .allowsHitTesting(selectedID == nil)
    }
}

private struct WalletCrown: View {
    let count: Int
    var jumpToLatest: () -> Void
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: "wallet.bifold").font(.title2.weight(.light))
            VStack(alignment: .leading, spacing: 5) {
                Text("Wallet").font(.title2.weight(.semibold)).accessibilityIdentifier("walletHeading")
                Text("\(count) saved").font(.subheadline)
            }
            Spacer(minLength: 6)
            if count > 3 {
                Button(action: jumpToLatest) { Image(systemName: "arrow.down").frame(width: 44, height: 44) }
                    .buttonStyle(.glass).accessibilityLabel("Jump to newest receipt").accessibilityIdentifier("latestReceipt")
            }
        }
        .foregroundStyle(.white).padding(22).frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 25).fill(LinearGradient(colors: [Color(white: scheme == .dark ? 0.24 : 0.27), Color(white: 0.12)], startPoint: .topLeading, endPoint: .bottomTrailing))
        }
        .overlay { RoundedRectangle(cornerRadius: 25).stroke(.white.opacity(0.16), lineWidth: 0.5) }
        .overlay(alignment: .bottom) { Capsule().fill(.white.opacity(0.16)).frame(height: 1).padding(.horizontal, 22).padding(.bottom, 13) }
        .shadow(color: .black.opacity(0.22), radius: 14, y: 8)
    }
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
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var systemContrast
    private var contrast: ColorSchemeContrast { ReceiptAccessibility.contrast(systemContrast) }
    var body: some View {
        ReceiptPaperEdge().fill(Color(uiColor: .secondarySystemGroupedBackground))
            .overlay { ReceiptPaperEdge().stroke(.primary.opacity(contrast == .increased ? 0.6 : 0.12), lineWidth: 0.5) }
            .shadow(color: .black.opacity(scheme == .dark ? 0.42 : 0.15), radius: 12, y: 7)
            .shadow(color: .black.opacity(0.09), radius: 2, y: 1)
    }
}

private struct ReceiptSwipePaper: View {
    let record: ReceiptRecord
    let settings: ReceiptWalletSettings
    @Binding var revealedID: UUID?
    let hidden: Bool
    var paperSpace: Namespace.ID?
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
                Button { perform(action) } label: {
                    VStack(spacing: 8) { Image(systemName: action.symbol).font(.title3); Text(action.title(for: record)).font(.caption.weight(.semibold)) }
                        .frame(width: 88).frame(minHeight: typeSize.isAccessibilitySize ? 100 : 80)
                }.buttonStyle(.glass).tint(action == .delete ? .red : .primary)
                    .accessibilityIdentifier("swipeAction-\(identifier)")
                    .padding(.top, 24)
            }
            ReceiptPreviewPaper(record: record)
                .contentShape(ReceiptPaperEdge())
                .onTapGesture(perform: open)
                .accessibilityElement(children: .ignore)
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { open() }
                .background { ReceiptPaperBackground() }
                .mask {
                    if record.current.fields.items.count > 3 && !typeSize.isAccessibilitySize {
                        LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.78), .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom)
                    } else { Color.black }
                }
                .receiptPaperGeometry(id: record.id, space: hidden ? nil : paperSpace)
                .offset(x: revealedID == record.id || horizontal ? offset : 0)
                .accessibilityLabel(summary)
                .accessibilityHint(revealedID == record.id ? "Closes the swipe action" : "Expands receipt. Swipe left or right for actions.")
                .accessibilityIdentifier(identifier)
                .gesture(ReceiptHorizontalPan { translation, ended in
                    let configured = translation < 0 ? settings.leftSwipe : settings.rightSwipe
                    if !ended {
                        guard configured != .none else { return }
                        horizontal = true; revealedID = record.id
                        offset = max(-100, min(100, translation))
                    } else {
                        withAnimation(animation) {
                            if abs(translation) > 42 && configured != .none { offset = offset < 0 ? -100 : 100; revealedID = record.id }
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
        }
        .onChange(of: revealedID) { _, next in if next != record.id { withAnimation(animation) { offset = 0 } } }
    }
    private var summary: String {
        [record.current.fields.merchant ?? "Merchant missing", ExactInput.dateText(record.current.fields.purchaseDate),
         record.current.fields.total.map { "\($0.currency.code) \(ExactInput.format($0.minorUnits, scale: $0.currency.minorUnitScale))" } ?? "Total missing",
         record.isStarred ? "Starred" : "", ReceiptCompletion.isComplete(record) ? "Reviewed" : "Needs review"].filter { !$0.isEmpty }.joined(separator: ", ")
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


extension View {
    @ViewBuilder func receiptPaperGeometry(id: UUID?, space: Namespace.ID?) -> some View {
        if let id, let space { matchedGeometryEffect(id: id, in: space, anchor: .top) }
        else { self }
    }
}
