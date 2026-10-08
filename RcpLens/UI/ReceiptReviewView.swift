import SwiftUI

struct ReceiptReviewView: View {
    @Bindable var workspace: ReceiptWorkspace
    var editing: FocusState<String?>.Binding
    @Environment(\.dynamicTypeSize) private var typeSize

    private func field(_ key: WritableKeyPath<ReceiptReviewDraft, String>) -> Binding<String> {
        Binding(get: { workspace.draft[keyPath: key] }, set: { value in workspace.updateDraft { $0[keyPath: key] = value } })
    }
    var body: some View {
        Form {
            Section {
                Label("Check the paper before finishing", systemImage: "doc.text.magnifyingglass").font(.headline)
                Text("Check every purchase, quantity, discount and tax against the original. Reading can miss or misread details.")
                    .font(.subheadline).foregroundStyle(.primary)
                if let extraction = workspace.extraction {
                    if extraction.issues.contains(where: { $0.code == "date_order_check" }) {
                        Label("The printed date order is ambiguous. Verify month and day.", systemImage: "calendar.badge.exclamationmark").font(.subheadline)
                    }
                    if extraction.issues.contains(where: { $0.code == "amount_unparsed_check_source" }) {
                        Label("Some numeric source rows were not parsed. Check for omitted lines or totals.", systemImage: "exclamationmark.triangle").font(.subheadline)
                    }
                }
            }
            Section {
                LabeledContent("Merchant") { TextField("Required", text: field(\.merchant)).multilineTextAlignment(.trailing).focused(editing, equals: "merchant").accessibilityIdentifier("merchantField") }
                LabeledContent("Date") { TextField("YYYY-MM-DD", text: field(\.date)).multilineTextAlignment(.trailing).focused(editing, equals: "date").keyboardType(.numbersAndPunctuation).accessibilityIdentifier("dateField") }
                Picker("Currency", selection: field(\.currency)) {
                    Text("Choose currency").tag("")
                    ForEach(ExactInput.currencies.keys.sorted(), id: \.self) { Text($0).tag($0) }
                }.accessibilityIdentifier("currencyField")
                Text("Amounts are printed line extensions, not unit prices. Quantity is optional; blank stays unknown.").font(.footnote).foregroundStyle(.primary)
            } header: { Text("Receipt").foregroundStyle(Color(uiColor: .label)) }
            Section {
                ForEach(workspace.draft.lines.filter { $0.kind == "purchase" }) { line in
                    ReceiptLineEditor(workspace: workspace, id: line.id, editing: editing)
                }
                Button("Add purchase", systemImage: "plus") { workspace.updateDraft { $0.lines.append(.blank()) } }
                    .frame(minHeight: 44).accessibilityIdentifier("addPurchase")
            } header: { Text("Items").foregroundStyle(Color(uiColor: .label)) }
            Section {
                LabeledContent("Printed subtotal") {
                    TextField("Missing", text: field(\.subtotal)).keyboardType(.numbersAndPunctuation)
                        .multilineTextAlignment(.trailing).focused(editing, equals: "subtotal").accessibilityIdentifier("subtotalField")
                }
                if workspace.draft.subtotal.isEmpty {
                    Toggle("Subtotal is not printed", isOn: Binding(get: { workspace.draft.subtotalNotPrinted }, set: { value in workspace.updateDraft { $0.subtotalNotPrinted = value } }))
                        .accessibilityIdentifier("subtotalNotPrinted")
                }
            } header: { Text("Subtotal").foregroundStyle(Color(uiColor: .label)) }
            Section {
                Text("Enter discounts as negative amounts. Add only printed tax, deposit or adjustment amounts; the app does not infer missing tax.")
                    .font(.footnote).foregroundStyle(.primary)
                ForEach(workspace.draft.lines.filter { $0.kind != "purchase" }) { line in
                    ReceiptLineEditor(workspace: workspace, id: line.id, editing: editing)
                }
                Menu {
                    ForEach(["discount", "tax", "deposit", "tip", "other"], id: \.self) { kind in
                        Button(kind.capitalized) { workspace.updateDraft { $0.lines.append(.blank(kind: kind)) } }
                    }
                } label: { Label("Add adjustment", systemImage: "plus").frame(minHeight: 44) }.accessibilityIdentifier("addAdjustment")
            } header: { Text("Discounts, tax and other adjustments").foregroundStyle(Color(uiColor: .label)) }
            Section {
                LabeledContent("Printed total") {
                    TextField("Required to finish", text: field(\.total)).keyboardType(.numbersAndPunctuation)
                        .multilineTextAlignment(.trailing).focused(editing, equals: "total").accessibilityIdentifier("totalField")
                }
                reconciliation
            } header: { Text("Total").foregroundStyle(Color(uiColor: .label)) }
            Section {
                Button("Compare with original", systemImage: "doc.viewfinder") { editing.wrappedValue = nil; workspace.showSource() }
                    .frame(minHeight: 44).accessibilityIdentifier("compareOriginal")
                Toggle("I checked every field and line against the original", isOn: $workspace.draft.sourceChecked)
                    .disabled(!workspace.draft.sourceOpened).accessibilityIdentifier("sourceCheck")
                Text(workspace.draft.sourceOpened ? "Changing a field clears this confirmation. Matching totals alone do not prove completeness." : "Open the original first. Review all lines, including ones recognition missed.")
                    .font(.footnote).foregroundStyle(.primary)
            } header: { Text("Source review").foregroundStyle(Color(uiColor: .label)) }
            Section {
                if let error = workspace.errorMessage { Label(error, systemImage: "exclamationmark.triangle").accessibilityIdentifier("saveError") }
                if workspace.saving { ProgressView("Saving locally") }
                if !workspace.draft.canSaveDraft {
                    Text("Fix malformed date, quantity or amount entries before saving a draft. Missing fields can remain blank.").font(.footnote)
                }
                Text("Saved only on this device. The wallet is excluded from ordinary backup; no export or restore is available yet. Uninstalling or losing the device can lose your receipts.")
                    .font(.footnote).foregroundStyle(.primary)
            }

        }.scrollDismissesKeyboard(.interactively).accessibilityIdentifier("reviewScreen")
    }
    private var reconciliation: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let difference = workspace.draft.reconciliation.difference {
                Label(difference == 0 ? "Line amounts match the total" : "Difference: \(ExactInput.format(difference, scale: ExactInput.currency(workspace.draft.currency)?.minorUnitScale ?? 2)) \(workspace.draft.currency)", systemImage: difference == 0 ? "equal.circle" : "exclamationmark.circle")
                    .font(.headline).accessibilityIdentifier("reconciliation")
            } else { Label("Cannot reconcile yet", systemImage: "questionmark.circle").font(.headline).accessibilityIdentifier("reconciliation") }
            if let note = workspace.draft.reconciliation.subtotalNote { Text(note).font(.footnote).foregroundStyle(.primary) }
            ForEach(workspace.draft.reconciliation.issues, id: \.self) { Text($0).font(.subheadline) }
        }.padding(.vertical, 8).accessibilityElement(children: .combine)
    }
}

private struct ReceiptLineEditor: View {
    var workspace: ReceiptWorkspace
    let id: UUID
    var editing: FocusState<String?>.Binding
    @Environment(\.dynamicTypeSize) private var typeSize
    private var line: EditableReceiptLine? { workspace.draft.lines.first { $0.id == id } }
    private func field(_ key: WritableKeyPath<EditableReceiptLine, String>) -> Binding<String> {
        Binding(get: { line?[keyPath: key] ?? "" }, set: { value in
            workspace.updateDraft { draft in
                if let i = draft.lines.firstIndex(where: { $0.id == id }) { draft.lines[i][keyPath: key] = value }
            }
        })
    }
    var body: some View {
        if let line {
            VStack(alignment: .leading, spacing: 12) {
                TextField(line.kind == "purchase" ? "Printed item description" : "Printed adjustment label", text: field(\.name), axis: .vertical)
                    .font(.body.weight(.medium)).focused(editing, equals: "name-\(id)").accessibilityLabel("Line description")
                    .accessibilityIdentifier("lineName-\(id)")
                Picker("Type", selection: field(\.kind)) {
                    ForEach(["purchase", "discount", "tax", "deposit", "tip", "other"], id: \.self) { Text($0.capitalized).tag($0) }
                }
                if line.kind == "purchase" {
                    LabeledContent("Quantity") {
                        TextField("Unknown", text: field(\.quantity)).keyboardType(.decimalPad).multilineTextAlignment(.trailing).focused(editing, equals: "quantity-\(id)")
                            .accessibilityLabel("Printed quantity").accessibilityIdentifier("lineQuantity-\(id)")
                    }
                }
                LabeledContent("Line amount") {
                    TextField("Missing", text: field(\.amount)).keyboardType(.numbersAndPunctuation).multilineTextAlignment(.trailing).focused(editing, equals: "amount-\(id)")
                        .accessibilityLabel("Printed line amount").accessibilityIdentifier("lineAmount-\(id)")
                }
                HStack {
                    Button("Source", systemImage: "doc.viewfinder") { editing.wrappedValue = nil; workspace.showSource(ids: line.sourceLineIDs) }
                        .frame(minHeight: 44).disabled(line.sourceLineIDs.isEmpty).accessibilityHint("Highlights the OCR observations linked to this line")
                    Spacer()
                    Button("Remove", systemImage: "minus.circle", role: .destructive) { workspace.updateDraft { $0.lines.removeAll { $0.id == id } } }
                        .frame(minHeight: 44).foregroundStyle(.primary).accessibilityLabel("Remove this line")
                }.buttonStyle(.borderless)
                if line.sourceLineIDs.isEmpty { Text("Manually entered · compare with original").font(.caption).foregroundStyle(.primary) }
            }.padding(.vertical, 10).accessibilityElement(children: .contain)
        }
    }
}

struct ReceiptDetailView: View {
    var workspace: ReceiptWorkspace
    let record: ReceiptRecord
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if !ReceiptCompletion.isComplete(record) {
                    Label("Needs review", systemImage: "exclamationmark.circle").font(.headline)
                    Text("Open Edit to fill missing details and check the total against the original.").font(.subheadline)
                } else { Label("Source reviewed", systemImage: "checkmark.circle").font(.subheadline) }
                if let error = workspace.errorMessage { Text(error).font(.subheadline) }
                if record.current.fields.currency == nil {
                    Text("Currency still needs confirmation. Amounts below are the saved editable text; they cannot be reconciled yet.").font(.subheadline)
                }
                ReceiptPaper(fields: record.current.fields, input: record.current.reviewInput.flatMap { try? JSONDecoder().decode(ReceiptReviewDraft.self, from: $0) })
                Text("Original kept unchanged.").font(.footnote).foregroundStyle(.primary)
                Button("View original", systemImage: "doc.viewfinder") { workspace.showSource() }.buttonStyle(.bordered).frame(minHeight: 44)
                Text("On this device only · no automatic backup").font(.footnote).foregroundStyle(.primary)
                #if DEBUG
                WorkflowDetailTestControls(workspace: workspace)
                #endif
            }.padding(24)
        }.accessibilityIdentifier("detailScreen")
    }
}

struct ReceiptPaper: View {
    let fields: ReceiptFields
    var input: ReceiptReviewDraft? = nil
    @Environment(\.dynamicTypeSize) private var typeSize
    private func money(_ value: ReceiptMoney?, raw: String? = nil) -> String {
        value.map { ExactInput.format($0.minorUnits, scale: $0.currency.minorUnitScale) } ?? raw?.nilIfEmpty ?? "Missing"
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(fields.merchant ?? "Merchant missing").font(.title2.weight(.semibold))
            Text("\(ExactInput.dateText(fields.purchaseDate).nilIfEmpty ?? "Date missing") · \(fields.currency?.code ?? "Currency missing")").font(.subheadline).foregroundStyle(.primary)
            Divider()
            Text("Items").font(.headline)
            ForEach(fields.items) { item in
                VStack(alignment: .leading, spacing: 5) {
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top) { Text(item.description ?? "Description missing"); Spacer(minLength: 20); Text(money(item.amount, raw: input?.lines.first { $0.id == item.id }?.amount)).monospacedDigit() }
                        VStack(alignment: .leading, spacing: 4) { Text(item.description ?? "Description missing"); Text(money(item.amount, raw: input?.lines.first { $0.id == item.id }?.amount)).monospacedDigit() }
                    }
                    Text(item.quantity.map { "Quantity \(ExactInput.quantity($0))" } ?? "Quantity not recorded").font(.caption).foregroundStyle(.primary)
                }.accessibilityElement(children: .combine)
            }
            if fields.items.isEmpty { Text("Purchases missing").foregroundStyle(.primary) }
            Divider()
            amountRow("Subtotal", fields.subtotal, raw: input?.subtotal)
            ForEach(fields.adjustments.filter { $0.kind == .discount }) { adjustment in amountRow(adjustment.label ?? "Discount", adjustment.amount, raw: input?.lines.first { $0.id == adjustment.id }?.amount) }
            ForEach(fields.adjustments.filter { $0.kind == .tax }) { adjustment in amountRow(adjustment.label ?? "Tax", adjustment.amount, raw: input?.lines.first { $0.id == adjustment.id }?.amount) }
            ForEach(fields.adjustments.filter { $0.kind != .discount && $0.kind != .tax }) { adjustment in amountRow(adjustment.label ?? adjustment.kind.rawValue.capitalized, adjustment.amount, raw: input?.lines.first { $0.id == adjustment.id }?.amount) }
            Divider()
            amountRow("Total", fields.total, raw: input?.total).font(.title3.weight(.semibold))
        }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
            .overlay { RoundedRectangle(cornerRadius: 16).stroke(.primary.opacity(0.12)) }
            .shadow(color: .black.opacity(0.07), radius: 10, y: 5)
    }
    private func amountRow(_ name: String, _ value: ReceiptMoney?, raw: String? = nil) -> some View {
        LabeledContent(name) { Text(money(value, raw: raw)).monospacedDigit().foregroundStyle(.primary) }.foregroundStyle(.primary).accessibilityElement(children: .combine)
    }
}
