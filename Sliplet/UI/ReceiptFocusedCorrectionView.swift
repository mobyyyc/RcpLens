import SwiftUI

/// A transactional correction. The working copy never reaches the receipt until Apply is tapped.
struct ReceiptFocusedCorrectionView: View {
    @Bindable var workspace: ReceiptWorkspace
    let check: ReceiptReviewGuidance
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.dynamicTypeSize) private var systemTypeSize
    private var reduceMotion: Bool { ReceiptAccessibility.reduceMotion(systemReduceMotion) }
    @State private var input: ReceiptReviewDraft
    @State private var lineID: UUID?
    @State private var sourceIndex = 0
    @State private var showReadText = false
    @State private var expanded = false
    @State private var zoomTarget = UUID()
    @State private var expandedZoomTarget = UUID()
    @State private var groupChecked = false
    @State private var purchaseDate: Date
    @State private var error: String?
    @FocusState private var editing: String?
    private let baseline: ReceiptReviewDraft
    init(workspace: ReceiptWorkspace, check: ReceiptReviewGuidance) {
        self.workspace = workspace; self.check = check; baseline = workspace.draft
        _input = State(initialValue: workspace.draft)
        if case .line(let id) = check.target { _lineID = State(initialValue: id) }
        _purchaseDate = State(initialValue: ReceiptDateSelection.date(workspace.draft.date) ?? Date())
    }
    private var sources: [ReceiptOCRLine] {
        (workspace.extraction?.rawOCR ?? []).filter { check.sourceLineIDs.contains($0.id) }
    }
    private var currentSource: ReceiptOCRLine? { sources.indices.contains(sourceIndex) ? sources[sourceIndex] : nil }
    private var isSourceGroup: Bool { if case .source = check.target { return sources.count > 1 }; return false }
    private var boxes: [ReceiptOCRBox] {
        if case .source = check.target { return currentSource?.boundingBox.map { [$0] } ?? [] }
        return sources.compactMap(\.boundingBox)
    }
    private func field(_ key: WritableKeyPath<ReceiptReviewDraft, String>) -> Binding<String> {
        Binding(get: { input[keyPath: key] }, set: { input[keyPath: key] = $0 })
    }
    private func lineField(_ key: WritableKeyPath<EditableReceiptLine, String>) -> Binding<String> {
        Binding(get: { input.lines.first { $0.id == lineID }?[keyPath: key] ?? "" }, set: { value in
            if let i = input.lines.firstIndex(where: { $0.id == lineID }) { input.lines[i][keyPath: key] = value }
        })
    }
    var body: some View {
        NavigationStack {
            Form {
                Section { Text(check.message).font(.footnote) }
                Section {
                    if workspace.active && !workspace.privacyCovered, let image = workspace.image {
                        ZoomReceiptImage(bytes: image.bytes, boxes: boxes, reduceMotion: reduceMotion, zoomTarget: zoomTarget, rasterID: "focusedSourceRaster")
                            .id(sourceIndex).frame(height: systemTypeSize.isAccessibilitySize ? 180 : 150).accessibilityIdentifier("focusedSourceImage")
                        HStack {
                            ReceiptSourceZoomControls(target: zoomTarget, prefix: "focused")
                            Spacer()
                            Button("Expand original", systemImage: "arrow.up.left.and.arrow.down.right") { editing = nil; expanded = true }
                                .labelStyle(.iconOnly).buttonStyle(ReceiptSecondaryStyle())
                                .accessibilityIdentifier("expandFocusedOriginal")
                        }
                        if sources.count > 1, case .source = check.target {
                            HStack {
                                Button("Previous row") { sourceIndex -= 1 }.disabled(sourceIndex == 0)
                                Spacer()
                                Text("\(sourceIndex + 1) of \(sources.count)").monospacedDigit()
                                Spacer()
                                Button("Next row") { sourceIndex += 1 }.disabled(sourceIndex == sources.count - 1)
                            }.frame(minHeight: 44).buttonStyle(.borderless)
                        }
                    } else { Text("Original unavailable. Close this check and reopen the receipt.") }
                } header: { Text("Original comparison") }
                footer: {
                    Text(boxes.isEmpty ? "No position is available for this check. Compare the full original." : "Compare the photo; read text may contain errors.").font(.footnote)
                }
                switch check.target {
                case .receipt:
                    Section {
                        TextField("Merchant", text: field(\.merchant)).focused($editing, equals: "merchant").accessibilityIdentifier("focusedMerchant")
                        Picker("Currency", selection: field(\.currency)) {
                            Text("Choose currency").tag("")
                            ForEach(ExactInput.currencies.keys.sorted(), id: \.self) { Text($0).tag($0) }
                        }
                    } header: { Text("Receipt details") }
                case .date:
                    Section {
                        Text(input.date.isEmpty ? "Date not confirmed" : "Current: " + input.date)
                        DatePicker("Printed purchase date", selection: $purchaseDate, displayedComponents: .date)
                            .environment(\.calendar, ReceiptDateSelection.calendar())
                        Button("Use selected date") { input.date = ReceiptDateSelection.text(purchaseDate) }.accessibilityIdentifier("focusedUseDate")
                        Button("Leave date unknown") { input.date = "" }
                    }
                case .subtotal, .total:
                    Section {
                        LabeledContent("Printed subtotal") { TextField("Missing", text: field(\.subtotal)).keyboardType(.numbersAndPunctuation).focused($editing, equals: "subtotal").accessibilityIdentifier("focusedSubtotal") }
                        if input.subtotal.isEmpty { Toggle("Subtotal is not printed", isOn: $input.subtotalNotPrinted).tint(.green) }
                        LabeledContent("Printed total") { TextField("Missing", text: field(\.total)).keyboardType(.numbersAndPunctuation).focused($editing, equals: "total").accessibilityIdentifier("focusedTotal") }
                        if let difference = input.reconciliation.difference {
                            Text("Difference: " + ExactInput.format(difference, scale: ExactInput.currency(input.currency)?.minorUnitScale ?? 2))
                        }
                        Text("For a difference, check purchases and adjustments in the full review. Do not change a correct total just to make it match.").font(.footnote)
                    } header: { Text("Printed totals") }
                case .line, .source:
                    if case .source = check.target {
                        Section {
                            Picker("Existing line", selection: $lineID) {
                                Text("Choose a line").tag(UUID?.none)
                                ForEach(input.lines) { line in Text(line.name.nilIfEmpty ?? "Unnamed line").tag(Optional(line.id)) }
                            }.accessibilityIdentifier("focusedExistingLine")
                            Button("Add purchase from this row", systemImage: "plus") {
                                var line = EditableReceiptLine.blank()
                                line.sourceLineIDs = currentSource.map { [$0.id] } ?? []
                                input.lines.append(line); lineID = line.id
                            }.accessibilityIdentifier("focusedAddPurchase")
                            if lineID != nil, let source = currentSource {
                                Button("Link this row to selected line") {
                                    if let i = input.lines.firstIndex(where: { $0.id == lineID }), !input.lines[i].sourceLineIDs.contains(source.id) {
                                        input.lines[i].sourceLineIDs.append(source.id)
                                    }
                                }.accessibilityIdentifier("focusedLinkRow")
                            }
                        } header: { Text("Missing or wrapped line") }
                    }
                    if lineID != nil {
                        Section {
                            LabeledContent("Line amount") { TextField("Missing", text: lineField(\.amount)).keyboardType(.numbersAndPunctuation).focused($editing, equals: "lineAmount").accessibilityIdentifier("focusedLineAmount") }
                            TextField("Printed description", text: lineField(\.name), axis: .vertical).focused($editing, equals: "lineName").accessibilityIdentifier("focusedLineName")
                            Picker("Type", selection: lineField(\.kind)) {
                                ForEach(["purchase", "discount", "tax", "deposit", "tip", "other"], id: \.self) { Text($0.capitalized).tag($0) }
                            }
                            LabeledContent("Quantity") { TextField("Unknown", text: lineField(\.quantity)).keyboardType(.decimalPad).focused($editing, equals: "quantity").accessibilityIdentifier("focusedQuantity") }
                            Text("Use the printed full line amount. Unknown quantities stay blank.").font(.footnote)
                        } header: { Text("Focused line") }
                    }
                }
                if let currentSource {
                    Section {
                        DisclosureGroup("Read text", isExpanded: $showReadText) {
                            Text(currentSource.text).font(.callout).textSelection(.enabled)
                        }.accessibilityIdentifier("focusedReadText")
                    }
                }
                Section {
                    if isSourceGroup {
                        Toggle("I checked all \(sources.count) source rows", isOn: $groupChecked).tint(.green).accessibilityIdentifier("focusedGroupChecked")
                    }
                    if let error { Label(error, systemImage: "exclamationmark.circle").accessibilityIdentifier("focusedError") }
                    Text("Applying keeps only your explicit edits. This check does not confirm the entire receipt; Finish still requires full original review and matching totals.").font(.footnote)
                }
            }.scrollDismissesKeyboard(.interactively).scrollEdgeEffectStyle(.soft, for: .vertical)
                .contentMargins(.bottom, 28, for: .scrollContent)
                .accessibilityIdentifier("focusedCorrectionForm")
                .navigationTitle(check.title).navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { editing = nil; dismiss() }.accessibilityIdentifier("cancelFocusedCorrection") }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(check.requiresCorrection || input != baseline ? "Apply" : "Checked") { apply() }
                            .disabled(workspace.saving || !workspace.active || workspace.privacyCovered || workspace.image == nil || (isSourceGroup && !groupChecked && input == baseline))
                            .accessibilityIdentifier("applyFocusedCorrection")
                    }
                    ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { editing = nil } }
                }
                .sheet(isPresented: $expanded) {
                    NavigationStack {
                        if workspace.active && !workspace.privacyCovered, let image = workspace.image {
                            VStack {
                                ZoomReceiptImage(bytes: image.bytes, boxes: boxes, reduceMotion: reduceMotion, zoomTarget: expandedZoomTarget, rasterID: "expandedSourceRaster")
                                ReceiptSourceZoomControls(target: expandedZoomTarget, prefix: "expanded").padding()
                            }.navigationTitle("Original image").navigationBarTitleDisplayMode(.inline)
                                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { expanded = false }.accessibilityIdentifier("closeExpandedOriginal") } }
                        }
                    }
                }
        }.tint(.primary).accessibilityIdentifier("focusedCorrectionScreen")
            #if DEBUG
            .dynamicTypeSize(SyntheticNativePreview.enabled && ProcessInfo.processInfo.arguments.contains("--t05-large-text") ? .accessibility5 : systemTypeSize)
            #endif
    }
    private func apply() {
        editing = nil
        guard workspace.draft == baseline else { error = "The receipt changed. Cancel and reopen this check."; return }
        guard ReceiptFocusedCorrection.canApply(input, replacing: baseline) else { error = "Check typed dates, amounts and quantities. Missing values may stay blank."; return }
        workspace.applyFocusedCorrection(input, check: check, markChecked: !isSourceGroup || groupChecked)
        dismiss()
    }
}
