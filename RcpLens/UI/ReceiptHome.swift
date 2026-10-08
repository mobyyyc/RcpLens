import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct ReceiptHome: View {
    @Bindable var workspace: ReceiptWorkspace
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    private var reduceMotion: Bool { ReceiptAccessibility.reduceMotion(systemReduceMotion) }
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var systemContrast
    private var contrast: ColorSchemeContrast { ReceiptAccessibility.contrast(systemContrast) }
    @State private var importChoices = false
    @State private var photos = false
    @State private var files = false
    @State private var discard = false
    @State private var delete = false
    @FocusState private var editing: String?

    var body: some View {
        let session = workspace.sessionID
        NavigationStack {
            Group {
                if workspace.privacyCovered { ContentUnavailableView("Receipts locked", systemImage: "lock", description: Text("Return to the app after unlocking.")) }
                else {
                    switch workspace.availability {
                    case .closed, .opening: ProgressView("Opening local wallet")
                    case .failed(let message):
                        ContentUnavailableView {
                            Label("Wallet unavailable", systemImage: "lock.trianglebadge.exclamationmark")
                        } description: { Text(message) } actions: { Button("Try again", action: workspace.retryOpen).buttonStyle(.bordered) }
                    case .ready: flow
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(uiColor: .systemGroupedBackground))
            #if DEBUG
            .safeAreaInset(edge: .top, spacing: 0) {
                if SyntheticNativePreview.enabled { Text("Synthetic preview").font(.caption2).foregroundStyle(.primary).padding(.horizontal, 16).padding(.vertical, 4).frame(maxWidth: .infinity, alignment: .trailing) }
            }
            #endif
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(workspace.flow == .wallet ? .large : .inline)
            .toolbar {
                if workspace.availability == .ready && !workspace.privacyCovered {
                    if workspace.flow != .wallet {
                        ToolbarItem(placement: .topBarLeading) {
                            Button(workspace.flow == .review ? "Cancel" : "Wallet", systemImage: "chevron.left") {
                                if workspace.flow == .review || workspace.flow == .reading || workspace.flow == .loading { discard = true }
                                else { workspace.backToWallet() }
                            }.disabled(workspace.saving).accessibilityIdentifier("back")
                        }
                    }
                    if workspace.image != nil {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Original", systemImage: "doc.viewfinder") { editing = nil; workspace.showSource() }
                                .accessibilityIdentifier("original").disabled(workspace.saving)
                        }
                    }
                    if workspace.flow == .wallet {
                        ToolbarItemGroup(placement: .bottomBar) {
                            Button("Wallet", systemImage: "wallet.bifold") { workspace.library = false }.accessibilityIdentifier("walletTab")
                            Button("All receipts", systemImage: "list.bullet.rectangle") { workspace.library = true }.accessibilityIdentifier("allReceipts")
                            Spacer()
                        }
                        ToolbarItem(placement: .bottomBar) {
                            Button("Import", systemImage: "plus") { importChoices = true }
                                .buttonStyle(ReceiptProminentStyle()).accessibilityIdentifier("import")
                        }
                    }
                    if workspace.flow == .detail {
                        ToolbarItemGroup(placement: .bottomBar) {
                            Button("Edit", systemImage: "pencil") { workspace.edit() }.buttonStyle(ReceiptProminentStyle())
                                .accessibilityIdentifier("edit").disabled(workspace.saving)
                            Spacer()
                        }
                        ToolbarItem(placement: .bottomBar) {
                            Button("Delete", systemImage: "trash", role: .destructive) { delete = true }
                                .accessibilityIdentifier("delete").disabled(workspace.saving)
                        }
                    }
                    if workspace.flow == .review {
                        ToolbarItem(placement: .bottomBar) {
                            Button("Save draft") { editing = nil; workspace.save(asDraft: true) }
                                .disabled(!workspace.draft.canSaveDraft || workspace.saving).accessibilityIdentifier("saveDraft")
                        }
                        ToolbarItem(placement: .bottomBar) {
                            Button("Finish") { editing = nil; workspace.save(asDraft: false) }
                                .buttonStyle(ReceiptProminentStyle()).disabled(!workspace.draft.canFinalize || workspace.saving).accessibilityIdentifier("finishSave")
                        }
                        ToolbarItemGroup(placement: .keyboard) {
                            Spacer(); Button("Done") { editing = nil }.accessibilityIdentifier("keyboardDone")
                        }
                    }
                    #if DEBUG
                    if WorkflowTestInput.enabled {
                        if workspace.flow == .wallet {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("Local test image") {
                                    if let url = try? WorkflowTestInput.imageURL() { workspace.importFile(url) }
                                }.accessibilityIdentifier("debugImport")
                            }
                        }
                        if workspace.flow == .review {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("Test reference") { WorkflowTestInput.applyReference(workspace) }.accessibilityIdentifier("debugReference")
                            }
                        }
                        if workspace.flow == .detail {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("Test verify") { WorkflowTestInput.verify(workspace) }.accessibilityIdentifier("debugVerify")
                            }
                        }
                    }
                    #endif
                }
            }
            .confirmationDialog("Import a receipt", isPresented: $importChoices, titleVisibility: .visible) {
                Button("Photo library") { photos = true }
                Button("Files") { files = true }
            } message: { Text("Choose a receipt image. Recognition stays on this device.") }
            .sheet(isPresented: $photos) {
                ReceiptPhotoPicker { loader in
                    photos = false
                    guard session == workspace.sessionID, let loader else { return }
                    workspace.startImport { try await loader.load() }
                }.ignoresSafeArea()
            }
            .fileImporter(isPresented: $files, allowedContentTypes: [.png, .jpeg, .heic, .heif], allowsMultipleSelection: false) { result in
                guard session == workspace.sessionID else { return }
                switch result {
                case .success(let urls): if let url = urls.first { workspace.importFile(url) }
                case .failure(let error):
                    if (error as NSError).code != CocoaError.userCancelled.rawValue { workspace.notice = ImportFailure.unavailableFile.message }
                }
            }
            .confirmationDialog("Discard unsaved changes?", isPresented: $discard, titleVisibility: .visible) {
                Button("Discard changes", role: .destructive) { workspace.finishEditing() }
            } message: { Text("Only receipts you explicitly saved are kept.") }
            .confirmationDialog("Delete this receipt?", isPresented: $delete, titleVisibility: .visible) {
                Button("Delete receipt and original", role: .destructive) { workspace.deleteSelected() }
            } message: { Text("This removes all revisions and the original from this app. Copies in Photos or Files remain there.") }
            .sheet(isPresented: $workspace.sourceVisible) { ReceiptSourceView(workspace: workspace) }
            .disabled(workspace.saving)
        }
        .tint(.primary)
    }
    private var title: String {
        switch workspace.flow {
        case .wallet: workspace.library ? "All receipts" : "Your wallet"
        case .review: "Review receipt"
        case .detail: "Receipt"
        case .failed: "Import needs attention"
        case .loading, .reading: "Import receipt"
        }
    }
    @ViewBuilder private var flow: some View {
        switch workspace.flow {
        case .wallet: wallet
        case .review: ReceiptReviewView(workspace: workspace, editing: $editing)
        case .detail:
            if let receipt = workspace.selected { ReceiptDetailView(workspace: workspace, record: receipt) }
        case .loading, .reading:
            VStack(spacing: 24) {
                ProgressView(workspace.flow == .loading ? "Loading image" : "Reading receipt")
                Text("Nothing is saved yet.")
                    .font(.subheadline).foregroundStyle(.primary).multilineTextAlignment(.center)
                Text("You can leave this screen or cancel. Returning from the background discards unsaved work.")
                    .font(.footnote).foregroundStyle(.primary).multilineTextAlignment(.center)
                Button("Cancel import", role: .cancel) { workspace.cancelImport() }
                    .buttonStyle(.bordered).frame(minHeight: 44).accessibilityIdentifier("cancelImport")
            }.padding(28).accessibilityElement(children: .contain).accessibilityIdentifier("processing")
        case .failed:
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Label("Reading needs attention", systemImage: "exclamationmark.triangle").font(.title2)
                    Text(workspace.errorMessage ?? "Choose another image or try again.")
                    if workspace.image != nil {
                        Button("View original", systemImage: "doc.viewfinder") { workspace.showSource() }.buttonStyle(.bordered)
                        Button("Retry reading", systemImage: "arrow.clockwise", action: workspace.readImage).buttonStyle(.bordered)
                        Button("Enter manually", systemImage: "pencil", action: workspace.manualReview).buttonStyle(ReceiptProminentStyle())
                            .accessibilityIdentifier("manual")
                    }
                    Button("Choose another image", systemImage: "photo") { workspace.cancelImport(showNotice: false); importChoices = true }.buttonStyle(.bordered)
                    Button("Return to wallet", action: workspace.backToWallet).buttonStyle(.bordered)
                }.padding(24)
            }
        }
    }
    private var wallet: some View {
        Group {
            if workspace.library { ReceiptLibraryView(workspace: workspace) }
            else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        if let notice = workspace.notice { Text(notice).font(.subheadline).accessibilityIdentifier("notice") }
                        Text("Keep the paper. Remember the purchase.").font(.title3).foregroundStyle(.primary)
                        if workspace.receipts.isEmpty {
                            PaperPocket(workspace: workspace, records: [])
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Your first receipt belongs here").font(.title2.weight(.semibold))
                                Text("Import a photo, check the printed details, then save it. Drafts can wait for later.").foregroundStyle(.primary)
                                Button("Import receipt", systemImage: "plus") { importChoices = true }.buttonStyle(ReceiptProminentStyle())
                                    .frame(minHeight: 44).accessibilityIdentifier("emptyImport")
                            }
                        } else {
                            PaperPocket(workspace: workspace, records: Array(workspace.orderedReceipts.prefix(3)))
                            Button("Browse all \(workspace.receipts.count) receipts", systemImage: "list.bullet") { workspace.library = true }
                                .buttonStyle(.bordered).frame(minHeight: 44).accessibilityIdentifier("browseAll")
                        }
                        Text("On this device only. No automatic backup. Uninstalling the app or losing the device can lose your receipts.")
                            .font(.footnote).foregroundStyle(.primary)
                        #if DEBUG
                        WorkflowTestControls(workspace: workspace)
                        if !SyntheticNativePreview.enabled { NavigationLink("Synthetic diagnostics") { DiagnosticsView() }.font(.footnote) }
                        #endif
                    }.padding(24)
                }
            }
        }.accessibilityIdentifier("walletScreen")
    }
}

private struct PaperPocket: View {
    var workspace: ReceiptWorkspace
    let records: [ReceiptRecord]
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    private var reduceMotion: Bool { ReceiptAccessibility.reduceMotion(systemReduceMotion) }
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.colorSchemeContrast) private var systemContrast
    private var contrast: ColorSchemeContrast { ReceiptAccessibility.contrast(systemContrast) }
    @State private var pull: CGFloat = 0
    var body: some View {
        VStack(spacing: 0) {
            if records.isEmpty {
                RoundedRectangle(cornerRadius: 12).fill(Color(uiColor: .secondarySystemGroupedBackground))
                    .frame(height: 100).overlay { Image(systemName: "doc.text").font(.largeTitle).foregroundStyle(.tertiary) }
                    .padding(.horizontal, 28).rotationEffect(.degrees(reduceMotion ? 0 : -2))
                    .accessibilityHidden(true)
            } else {
                VStack(spacing: typeSize.isAccessibilitySize ? 14 : -6) {
                    ForEach(Array(records.enumerated()), id: \.element.id) { index, record in
                        Button { workspace.open(record) } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                ReceiptSummary(record: record)
                                if index == records.count - 1 {
                                    Text("\(record.current.fields.items.count) items · Tap to open")
                                        .font(.caption).foregroundStyle(.primary)
                                }
                            }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                                .overlay(alignment: .topTrailing) {
                                    if !typeSize.isAccessibilitySize {
                                        Image(systemName: "triangle.fill").font(.caption).foregroundStyle(Color(uiColor: .systemGroupedBackground))
                                            .rotationEffect(.degrees(180)).padding(8).accessibilityHidden(true)
                                    }
                                }
                                .overlay { RoundedRectangle(cornerRadius: 12).stroke(.primary.opacity(contrast == .increased ? 0.7 : 0.09)) }
                                .shadow(color: .black.opacity(0.08), radius: 5, y: 3)
                        }.buttonStyle(.plain)
                            .rotationEffect(.degrees(reduceMotion || typeSize.isAccessibilitySize ? 0 : (index % 2 == 0 ? -1.2 : 1.1)))
                            .offset(y: index == 0 ? pull : 0)
                            .zIndex(Double(records.count - index))
                            .accessibilityIdentifier("receipt-\(index)")
                            .accessibilityHint("Opens receipt and original evidence")
                            .simultaneousGesture(DragGesture(minimumDistance: 24).onChanged { value in
                                guard index == 0, !reduceMotion, !typeSize.isAccessibilitySize, value.translation.height < -20 else { return }
                                pull = max(-60, value.translation.height / 2)
                            }.onEnded { value in
                                guard index == 0, !reduceMotion, !typeSize.isAccessibilitySize else { return }
                                withAnimation(.easeOut(duration: 0.22)) { pull = 0 }
                                if value.translation.height < -64 { workspace.open(record) }
                            })
                    }
                }.padding(.horizontal, typeSize.isAccessibilitySize ? 0 : 16)
            }
            HStack {
                Image(systemName: "wallet.bifold")
                Text("RcpLens").font(.headline)
                Spacer()
                Text(records.isEmpty ? "LOCAL WALLET" : "RECENT RECEIPTS").font(.caption2.weight(.medium))
            }.padding(24).frame(minHeight: 100)
                .background(Color(uiColor: .tertiarySystemFill), in: UnevenRoundedRectangle(topLeadingRadius: 12, bottomLeadingRadius: 24, bottomTrailingRadius: 24, topTrailingRadius: 12))
                .overlay { UnevenRoundedRectangle(topLeadingRadius: 12, bottomLeadingRadius: 24, bottomTrailingRadius: 24, topTrailingRadius: 12).stroke(.primary.opacity(0.1)) }
                .shadow(color: .black.opacity(0.06), radius: 9, y: 6)
                .padding(.top, -3).accessibilityHidden(true)
        }.padding(.top, 10)
    }
}

struct ReceiptSummary: View {
    let record: ReceiptRecord
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(record.current.fields.merchant ?? "Merchant missing").font(.headline).foregroundStyle(.primary)
            HStack(alignment: .top) {
                Text(ExactInput.dateText(record.current.fields.purchaseDate).nilIfEmpty ?? "Date missing").font(.subheadline)
                Spacer(minLength: 12)
                Text(record.current.fields.total.map { "\($0.currency.code) \(ExactInput.format($0.minorUnits, scale: $0.currency.minorUnitScale))" } ?? "Total missing")
                    .font(.subheadline.monospacedDigit())
            }.foregroundStyle(.primary)
            if !ReceiptCompletion.isComplete(record) { Label("Needs review", systemImage: "exclamationmark.circle").font(.caption).foregroundStyle(.primary) }
        }.accessibilityElement(children: .combine)
    }
}

struct ReceiptLibraryView: View {
    @Bindable var workspace: ReceiptWorkspace
    var filtered: [ReceiptRecord] {
        workspace.orderedReceipts.filter {
            (workspace.merchantFilter == "All stores" || ($0.current.fields.merchant ?? "Merchant missing") == workspace.merchantFilter)
            && (workspace.monthFilter == "All months" || month($0) == workspace.monthFilter)
        }
    }
    private func month(_ record: ReceiptRecord) -> String {
        guard let date = record.current.fields.purchaseDate else { return "Date missing" }
        return String(format: "%04d-%02d", date.year, date.month)
    }
    var body: some View {
        List {
            Section {
                Picker("Store", selection: $workspace.merchantFilter) {
                    Text("All stores").tag("All stores")
                    ForEach(Array(Set(workspace.receipts.map { $0.current.fields.merchant ?? "Merchant missing" })).sorted(), id: \.self) { Text($0).tag($0) }
                }
                Picker("Month", selection: $workspace.monthFilter) {
                    Text("All months").tag("All months")
                    ForEach(Array(Set(workspace.receipts.map(month))).sorted(by: >), id: \.self) { Text($0).tag($0) }
                }
            }
            if filtered.isEmpty { ContentUnavailableView("No receipts here", systemImage: "doc.text", description: Text("Import a receipt or choose different filters.")) }
            ForEach(Array(Set(filtered.map(month))).sorted(by: >), id: \.self) { group in
                Section {
                    ForEach(filtered.filter { month($0) == group }) { record in
                        Button { workspace.open(record) } label: { ReceiptSummary(record: record).padding(.vertical, 8) }
                            .buttonStyle(.plain).frame(minHeight: 44)
                    }
                } header: { Text(group).foregroundStyle(Color(uiColor: .label)) }
            }
        }.accessibilityIdentifier("receiptLibrary")
    }
}
