import SwiftUI

struct ReceiptReviewView: View {
    @Bindable var workspace: ReceiptWorkspace
    var editing: FocusState<String?>.Binding
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var selectingDate = false
    @State private var pendingDate = Date()

    private func field(_ key: WritableKeyPath<ReceiptReviewDraft, String>) -> Binding<String> {
        Binding(get: { workspace.draft[keyPath: key] }, set: { value in workspace.updateDraft { $0[keyPath: key] = value } })
    }
    var body: some View {
        Form {
            Section {
                Label("Check details against the original.", systemImage: "doc.text.magnifyingglass")
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
                LabeledContent("Merchant") { TextField("Required", text: field(\.merchant), axis: typeSize > .large ? .vertical : .horizontal).multilineTextAlignment(.trailing).focused(editing, equals: "merchant").accessibilityIdentifier("merchantField") }
                Button {
                    editing.wrappedValue = nil
                    pendingDate = ReceiptDateSelection.date(workspace.draft.date) ?? Date()
                    selectingDate = true
                } label: {
                    LabeledContent("Date") {
                        if let date = ReceiptDateSelection.date(workspace.draft.date) {
                            Text(date.formatted(date: .abbreviated, time: .omitted))
                        } else { Label("Choose date", systemImage: "calendar") }
                    }
                }.foregroundStyle(.primary).accessibilityIdentifier("dateField")
                Picker("Currency", selection: field(\.currency)) {
                    Text("Choose currency").tag("")
                    ForEach(ExactInput.currencies.keys.sorted(), id: \.self) { Text($0).tag($0) }
                }.accessibilityIdentifier("currencyField")
            } header: { Text("Receipt").foregroundStyle(Color(uiColor: .label)) }
            footer: { Text("Use printed line amounts. Leave unknown quantities blank.").foregroundStyle(Color(uiColor: .label)) }
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
                        .tint(.green).accessibilityIdentifier("subtotalNotPrinted")
                }
            } header: { Text("Subtotal").foregroundStyle(Color(uiColor: .label)) }
            Section {
                ForEach(workspace.draft.lines.filter { $0.kind != "purchase" }) { line in
                    ReceiptLineEditor(workspace: workspace, id: line.id, editing: editing)
                }
                Menu {
                    ForEach(["discount", "tax", "deposit", "tip", "other"], id: \.self) { kind in
                        Button(kind.capitalized) { workspace.updateDraft { $0.lines.append(.blank(kind: kind)) } }
                    }
                } label: { Label("Add adjustment", systemImage: "plus").frame(minHeight: 44) }.accessibilityIdentifier("addAdjustment")
            } header: { Text("Adjustments").foregroundStyle(Color(uiColor: .label)) }
            footer: { Text("Discounts are negative. Enter printed taxes and fees only.").foregroundStyle(Color(uiColor: .label)) }
            Section {
                LabeledContent("Printed total") {
                    TextField("Required to finish", text: field(\.total)).keyboardType(.numbersAndPunctuation)
                        .multilineTextAlignment(.trailing).focused(editing, equals: "total").accessibilityIdentifier("totalField")
                }
                reconciliation
            } header: { Text("Total").foregroundStyle(Color(uiColor: .label)) }
            Section {
                Toggle("I checked the original", isOn: $workspace.draft.sourceChecked)
                    .tint(.green).disabled(!workspace.draft.sourceOpened).accessibilityIdentifier("sourceCheck")
                Text(workspace.draft.sourceOpened ? "Confirm every field and line. Editing clears this check; matching totals alone do not prove completeness." : "Open Original above and check every field and line, including anything recognition missed.")
                    .font(.footnote).foregroundStyle(.primary)
            } header: { Text("Source review").foregroundStyle(Color(uiColor: .label)) }
            Section {
                if let error = workspace.errorMessage { Label(error, systemImage: "exclamationmark.triangle").accessibilityIdentifier("saveError") }
                if workspace.saving { ProgressView("Saving locally") }
                if !workspace.draft.canSaveDraft {
                    Text("Choose a valid purchase date and check typed quantities or amounts before saving a draft. Missing fields can remain blank.").font(.footnote)
                }
                Text("Saved only on this device. The wallet is excluded from ordinary backup; no export or restore is available yet. Uninstalling or losing the device can lose your receipts.")
                    .font(.footnote).foregroundStyle(.primary).accessibilityIdentifier("reviewStorageFooter")
            }

        }.listSectionSpacing(20).scrollDismissesKeyboard(.interactively)
        .scrollClipDisabled().scrollEdgeEffectStyle(.soft, for: .vertical)
        .contentMargins(.bottom, 28, for: .scrollContent)
        .accessibilityIdentifier("reviewScreen")
        .sheet(isPresented: $selectingDate) {
            NavigationStack {
                ScrollView {
                    DatePicker("Purchase date", selection: $pendingDate, displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .environment(\.calendar, ReceiptDateSelection.calendar())
                        .accessibilityIdentifier("receiptDatePicker")
                    if !workspace.draft.date.isEmpty {
                        Button("Clear date", role: .destructive) {
                            workspace.updateDraft { $0.date = "" }; selectingDate = false
                        }.accessibilityIdentifier("clearReceiptDate")
                    }
                }.padding().navigationTitle("Purchase date").navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { selectingDate = false }.accessibilityIdentifier("cancelReceiptDate")
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") {
                                let date = ReceiptDateSelection.text(pendingDate)
                                workspace.updateDraft { $0.date = date }; selectingDate = false
                            }.accessibilityIdentifier("confirmReceiptDate")
                        }
                    }
            }.presentationDetents([.medium, .large])
        }
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

/// The picker handles local calendar days; persisted receipt dates remain civil Gregorian dates.
enum ReceiptDateSelection {
    static func calendar(timeZone: TimeZone = .current) -> Calendar {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = timeZone
        return calendar
    }
    static func date(_ text: String, timeZone: TimeZone = .current) -> Date? {
        guard let value = ExactInput.date(text) else { return nil }
        return calendar(timeZone: timeZone).date(from: DateComponents(year: value.year, month: value.month, day: value.day, hour: 12))
    }
    static func text(_ date: Date, timeZone: TimeZone = .current) -> String {
        let components = calendar(timeZone: timeZone).dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year!, components.month!, components.day!)
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

struct ReceiptPaper: View {
    let fields: ReceiptFields
    var input: ReceiptReviewDraft? = nil
    var showsSurface = true
    var reviewed = false
    @Environment(\.dynamicTypeSize) private var typeSize
    private func money(_ value: ReceiptMoney?, raw: String? = nil) -> String {
        value.map { ExactInput.format($0.minorUnits, scale: $0.currency.minorUnitScale) } ?? raw?.nilIfEmpty ?? "Missing"
    }
    var body: some View {
        content.background { if showsSurface { ReceiptPaperBackground() } }.receiptPaperStyle()
    }
    private var content: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 12) {
                Text(fields.merchant ?? "Merchant missing").font(.title2.weight(.semibold))
                Spacer(minLength: 0)
                if reviewed { ReceiptReviewedMark() }
            }
            Text("\(ExactInput.dateText(fields.purchaseDate).nilIfEmpty ?? "Date missing") · \(fields.currency?.code ?? "Currency missing")").font(.subheadline).foregroundStyle(.primary)
            Divider()
            Text("Items").font(.headline)
            ForEach(fields.items) { item in
                VStack(alignment: .leading, spacing: 5) {
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top) { Text(item.description ?? "Description missing"); Spacer(minLength: 20); Text(money(item.amount, raw: input?.lines.first { $0.id == item.id }?.amount)).monospacedDigit() }
                        VStack(alignment: .leading, spacing: 4) { Text(item.description ?? "Description missing"); Text(money(item.amount, raw: input?.lines.first { $0.id == item.id }?.amount)).monospacedDigit() }
                    }
                    Text(item.quantity.map { "Quantity \(ExactInput.quantity($0))" } ?? "Qty unknown").font(.caption).foregroundStyle(.primary)
                }.accessibilityElement(children: .combine)
            }
            if fields.items.isEmpty { Text("Purchases missing").foregroundStyle(.primary) }
            Divider()
            amountRow("Subtotal", fields.subtotal, raw: input?.subtotal)
            ForEach(fields.adjustments.filter { $0.kind == .discount }) { adjustment in amountRow(adjustment.label ?? "Discount", adjustment.amount, raw: input?.lines.first { $0.id == adjustment.id }?.amount) }
            ForEach(fields.adjustments.filter { $0.kind == .tax }) { adjustment in amountRow(adjustment.label ?? "Tax", adjustment.amount, raw: input?.lines.first { $0.id == adjustment.id }?.amount) }
            ForEach(fields.adjustments.filter { $0.kind != .discount && $0.kind != .tax }) { adjustment in amountRow(adjustment.label ?? adjustment.kind.rawValue.capitalized, adjustment.amount, raw: input?.lines.first { $0.id == adjustment.id }?.amount) }
            Divider()
            amountRow("Total", fields.total, raw: input?.total).font(.title3.weight(.semibold)).accessibilityIdentifier("receiptPaperTotal")
        }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
    }
    private func amountRow(_ name: String, _ value: ReceiptMoney?, raw: String? = nil) -> some View {
        LabeledContent(name) { Text(money(value, raw: raw)).monospacedDigit().foregroundStyle(.primary) }.foregroundStyle(.primary).accessibilityElement(children: .combine)
    }
}

struct ReceiptReviewedMark: View {
    var body: some View {
        Image(systemName: "checkmark.circle.fill").font(.system(size: 18, weight: .medium))
            .foregroundStyle(.primary.opacity(0.65))
            .accessibilityLabel("Reviewed and saved").accessibilityIdentifier("receiptReviewedMark")
    }
}
