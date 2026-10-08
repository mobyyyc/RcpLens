import SwiftUI

/// History opens a reading surface directly; only the home wallet lifts a paper from its stack.
struct ReceiptSearchDetailView: View {
    @Bindable var workspace: ReceiptWorkspace
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @State private var revealed = false
    private var reduceMotion: Bool { ReceiptAccessibility.reduceMotion(systemReduceMotion) }

    var body: some View {
        ScrollView {
            if let record = workspace.selected {
                VStack(alignment: .leading, spacing: 20) {
                    if let match = workspace.searchMatch {
                        ReceiptSearchContext(workspace: workspace, match: match)
                    }
                    VStack(alignment: .leading, spacing: 20) {
                        HStack(alignment: .top) {
                            Label(ReceiptCompletion.isComplete(record) ? "Reviewed" : "Needs review",
                                  systemImage: ReceiptCompletion.isComplete(record) ? "checkmark.circle" : "exclamationmark.circle")
                            Spacer()
                            if record.isStarred { Image(systemName: "star.fill").accessibilityLabel("Starred") }
                        }.font(.footnote.weight(.medium)).fixedSize(horizontal: false, vertical: true)
                        ReceiptPaper(fields: record.current.fields,
                                     input: record.current.reviewInput.flatMap { try? JSONDecoder().decode(ReceiptReviewDraft.self, from: $0) })
                        VStack(alignment: .leading, spacing: 18) {
                            if workspace.image == nil && workspace.errorMessage == nil { ProgressView("Loading original").font(.footnote) }
                            if let error = workspace.errorMessage { Text(error).font(.subheadline) }
                            if record.current.fields.currency == nil { Text("Currency needs confirmation. Edit to check the saved amounts.").font(.footnote) }
                            Label("Saved on this device", systemImage: "lock").font(.footnote)
                                .accessibilityIdentifier("searchReceiptFooter")
                        }
                    }
                    .padding(.horizontal, 30)
                    .opacity(revealed ? 1 : 0)
                    .offset(y: reduceMotion || revealed ? 0 : 12)
                }.padding(.top, 12).padding(.bottom, 24)
            }
        }
        // Context and paper share normal scroll layout; there is no fixed search-header occlusion.
        .scrollClipDisabled().scrollEdgeEffectStyle(.soft, for: .vertical)
        .accessibilityIdentifier("detailScreen")
        .onAppear {
            withAnimation(.easeOut(duration: reduceMotion ? 0.12 : 0.22)) { revealed = true }
        }
    }
}

struct ReceiptPurchaseHistoryView: View {
    @Bindable var workspace: ReceiptWorkspace
    private var results: [ReceiptSearchIndex.Result] {
        workspace.searchIndex.results(query: workspace.searchQuery, collection: workspace.collection,
            includeArchived: workspace.includeArchived, merchant: workspace.merchantFilter, month: workspace.monthFilter)
    }
    private var merchants: [String] { Array(Set(workspace.receipts.compactMap { $0.current.fields.merchant })).sorted() }
    private var months: [String] { Array(Set(workspace.receipts.compactMap(ReceiptHistory.monthKey))).sorted(by: >) }
    var body: some View {
        let found = results
        let groups = Dictionary(grouping: found) { ReceiptHistory.monthKey($0.record) ?? "" }
        List {
            Section {
                Picker("Collection", selection: $workspace.collection) {
                    Text("All receipts").tag("All receipts"); Text("Starred").tag("Starred"); Text("Archive").tag("Archive")
                }.accessibilityIdentifier("collectionPicker")
                Picker("Store", selection: $workspace.merchantFilter) {
                    Text("All stores").tag(ReceiptHistoryChoice.all)
                    ForEach(merchants, id: \.self) { Text($0).tag(ReceiptHistoryChoice.value($0)) }
                    if workspace.receipts.contains(where: { $0.current.fields.merchant == nil }) { Text("Merchant missing").tag(ReceiptHistoryChoice.missing) }
                }.accessibilityIdentifier("searchMerchantFilter")
                Picker("Month", selection: $workspace.monthFilter) {
                    Text("All months").tag(ReceiptHistoryChoice.all)
                    ForEach(months, id: \.self) { Text(ReceiptHistory.monthTitle($0)).tag(ReceiptHistoryChoice.value($0)) }
                    if workspace.receipts.contains(where: { $0.current.fields.purchaseDate == nil }) { Text("Date missing").tag(ReceiptHistoryChoice.missing) }
                }.accessibilityIdentifier("searchMonthFilter")
                if workspace.collection != "Archive" {
                    Toggle("Include archived", isOn: $workspace.includeArchived).tint(.green).accessibilityIdentifier("searchIncludeArchived")
                }
                if workspace.merchantFilter != .all || workspace.monthFilter != .all {
                    Button("Clear filters") { workspace.merchantFilter = .all; workspace.monthFilter = .all }
                        .accessibilityIdentifier("searchClearFilters")
                }
            }
            Section {
                Text("\(found.count) \(found.count == 1 ? "receipt" : "receipts")")
                    .font(.subheadline).accessibilityIdentifier("searchResultCount")
                if found.isEmpty {
                    ContentUnavailableView(workspace.searchQuery.isEmpty ? "No receipts here" : "No matching purchases",
                        systemImage: workspace.searchQuery.isEmpty ? "doc.text" : "magnifyingglass",
                        description: Text(workspace.searchQuery.count > 512 ? "Use a shorter search." : "Try another word, SKU or filter. Archive is searchable separately."))
                }
            }
            ForEach(groups.keys.sorted(by: >), id: \.self) { key in
                Section {
                    ForEach(groups[key] ?? []) { result in
                        Button { workspace.open(result.record) } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                ReceiptSummary(record: result.record)
                                if result.record.isArchived { Label("Archived", systemImage: "archivebox").font(.caption) }
                            }.padding(.vertical, 8).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                        }.buttonStyle(.plain).frame(minHeight: 44).accessibilityIdentifier("searchReceipt-" + result.id.uuidString)
                        ForEach(result.matches) { match in
                            Button { workspace.open(result.record, match: match) } label: {
                                ReceiptSearchMatchLabel(match: match, record: result.record, compact: true)
                                    .padding(.vertical, 6).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                            }.buttonStyle(.plain).frame(minHeight: 44).accessibilityIdentifier("searchMatch-" + match.id)
                        }
                    }
                } header: { Text(ReceiptHistory.monthTitle(key.isEmpty ? nil : key)).foregroundStyle(Color(uiColor: .label)) }
            }
        }
        .searchable(text: $workspace.searchQuery, placement: .navigationBarDrawer(displayMode: .always), prompt: "Merchant, item or SKU")
        .autocorrectionDisabled()
        .scrollDismissesKeyboard(.interactively)
        .scrollClipDisabled().scrollEdgeEffectStyle(.soft, for: .vertical)
        .accessibilityIdentifier("receiptLibrary")
        // Reset only stale filters after a committed edit/deletion. Never replace a missing civil date.
        .onChange(of: merchants) { _, values in
            if case .value(let selected) = workspace.merchantFilter, !values.contains(selected) { workspace.merchantFilter = .all }
            if workspace.merchantFilter == .missing && !workspace.receipts.contains(where: { $0.current.fields.merchant == nil }) { workspace.merchantFilter = .all }
        }
        .onChange(of: months) { _, values in
            if case .value(let selected) = workspace.monthFilter, !values.contains(selected) { workspace.monthFilter = .all }
            if workspace.monthFilter == .missing && !workspace.receipts.contains(where: { $0.current.fields.purchaseDate == nil }) { workspace.monthFilter = .all }
        }
    }
}

struct ReceiptSearchMatchLabel: View {
    let match: ReceiptSearchIndex.Match
    let record: ReceiptRecord
    var compact = false
    private var item: ReceiptLine? { record.current.fields.items.first { $0.id == match.itemID } }
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(match.title).font(.body.weight(.medium)).lineLimit(compact ? 2 : nil).fixedSize(horizontal: false, vertical: true)
            if match.originalOnly {
                Text(match.unparsed ? "Original text · not linked to a current purchase" : "Original extraction · removed from current receipt").font(.caption)
            } else if let item {
                Text(item.amount.map { "\($0.currency.code) \(ExactInput.format($0.minorUnits, scale: $0.currency.minorUnitScale))" }
                     ?? "Amount missing").font(.subheadline.monospacedDigit())
                if let sku = item.sku { Text("SKU \(sku)").font(.caption) }
            }
            switch match.basis {
            case .original: Text("Original description: \(match.matchedText)").font(.caption)
            case .rawText: Text("Original text: \(match.matchedText)").font(.caption)
            case .originalSKU: Text("Original SKU: \(match.matchedText)").font(.caption)
            case .sku: Text("Matched SKU: \(match.matchedText)").font(.caption)
            case .merchant:
                if match.matchedText != record.current.fields.merchant { Text("Original merchant: \(match.matchedText)").font(.caption) }
            case .corrected: Text("Current purchase description").font(.caption)
            }
        }.lineLimit(compact ? 2 : nil).foregroundStyle(.primary).accessibilityElement(children: .combine)
    }
}

struct ReceiptSearchContext: View {
    @Bindable var workspace: ReceiptWorkspace
    let match: ReceiptSearchIndex.Match
    @State private var details = false
    @Environment(\.dynamicTypeSize) private var typeSize
    private var dismissButton: some View {
        Button { workspace.searchMatch = nil } label: { Image(systemName: "xmark").frame(minWidth: 44, minHeight: 44).contentShape(Rectangle()) }
            .buttonStyle(.plain).accessibilityLabel("Dismiss match")
    }
    private func originalButton(iconOnly: Bool) -> some View {
        Button { workspace.showSource(ids: match.sourceLineIDs) } label: {
            Group {
                if iconOnly { Image(systemName: "doc.viewfinder").frame(minWidth: 44, minHeight: 44) }
                else { Label("View matched original", systemImage: "doc.viewfinder").frame(minHeight: 44) }
            }.contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel("View matched original").disabled(workspace.image == nil).accessibilityIdentifier("searchOriginal")
    }

    var body: some View {
        if let record = workspace.selected {
            Group {
                if typeSize.isAccessibilitySize {
                    HStack(spacing: 12) {
                        Button { details = true } label: { Text("Match").font(.headline).frame(minHeight: 44).contentShape(Rectangle()) }
                            .buttonStyle(.plain).accessibilityLabel("View search match details").accessibilityValue(match.title).accessibilityIdentifier("searchMatchDetails")
                        Spacer(minLength: 0)
                        originalButton(iconOnly: true)
                        dismissButton
                    }
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack { Text(match.originalOnly ? "Matched original evidence" : "Search match").font(.caption.weight(.semibold)); Spacer(); dismissButton }
                        Text(match.title).font(.headline).lineLimit(2)
                        Text(match.originalOnly ? "Original evidence only" : "Current receipt match").font(.caption)
                        Button { details = true } label: { Text("Match details").frame(minHeight: 44).contentShape(Rectangle()) }
                            .buttonStyle(.plain).accessibilityIdentifier("searchMatchDetails")
                        originalButton(iconOnly: false)
                    }
                }
            }.padding(.horizontal, 20).padding(.bottom, 10).background(Color(uiColor: .systemGroupedBackground))
                .accessibilityElement(children: .contain)
                .sheet(isPresented: $details) {
                    NavigationStack {
                        ScrollView { ReceiptSearchMatchLabel(match: match, record: record).padding(24).frame(maxWidth: .infinity, alignment: .leading) }
                            .navigationTitle("Match details").navigationBarTitleDisplayMode(.inline)
                            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { details = false } } }
                    }
                }
        }
    }
}
