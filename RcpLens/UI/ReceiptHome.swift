import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct ReceiptHome: View {
    @Bindable var workspace: ReceiptWorkspace
    @State private var importChoices = false
    @State private var photos = false
    @State private var files = false
    @State private var discard = false
    @State private var delete = false
    @State private var walletInformation = false
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
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if SyntheticNativePreview.enabled { Text("Synthetic preview").font(.system(size: 11)).foregroundStyle(.primary).padding(.horizontal, 16).padding(.vertical, 4).frame(maxWidth: .infinity, alignment: .trailing) }
            }
            #endif
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
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
                            Button { editing = nil; workspace.showSource() } label: { Text("Original") }
                                .accessibilityIdentifier("original").disabled(workspace.saving)
                        }
                    }
                    if workspace.flow == .wallet {
                        if workspace.library {
                            ToolbarItem(placement: .topBarLeading) {
                                Button("Wallet", systemImage: "chevron.left") { workspace.library = false }
                                    .accessibilityIdentifier("walletTab")
                            }
                        } else if !workspace.receipts.isEmpty {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("All receipts") { workspace.library = true }.accessibilityIdentifier("allReceipts")
                            }
                        }
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Wallet information", systemImage: "info.circle") { walletInformation = true }
                                .accessibilityIdentifier("walletInformation")
                        }
                        ToolbarItemGroup(placement: .bottomBar) {
                            Spacer()
                            Button { importChoices = true } label: {
                                HStack(spacing: 8) { Image(systemName: "plus"); Text("Import receipt") }
                                    .font(.body.weight(.semibold)).padding(.horizontal, 12).frame(minHeight: 34)
                            }
                            .buttonStyle(ReceiptProminentStyle()).controlSize(.large)
                            .accessibilityLabel("Import receipt").accessibilityIdentifier("import")
                            Spacer()
                        }
                    }
                    if workspace.flow == .detail {
                        ToolbarItemGroup(placement: .bottomBar) {
                            Spacer()
                            Button { workspace.edit() } label: {
                                HStack(spacing: 8) { Image(systemName: "pencil"); Text("Edit receipt") }
                                    .font(.body.weight(.semibold)).padding(.horizontal, 12).frame(minHeight: 34)
                            }.buttonStyle(ReceiptProminentStyle()).controlSize(.large)
                                .accessibilityIdentifier("edit").disabled(workspace.saving)
                            Spacer()
                        }
                        ToolbarItem(placement: .topBarTrailing) {
                            Menu {
                                Button("Storage details", systemImage: "info.circle") { walletInformation = true }
                                Button("Delete receipt", systemImage: "trash", role: .destructive) { delete = true }
                                    .accessibilityIdentifier("delete")
                            } label: { Image(systemName: "ellipsis") }
                            .accessibilityLabel("Receipt options").accessibilityIdentifier("receiptOptions")
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
            .alert("Delete this receipt?", isPresented: $delete) {
                Button("Delete receipt and original", role: .destructive) { workspace.deleteSelected() }
                Button("Cancel", role: .cancel) {}
            } message: { Text("This removes all revisions and the original from this app. Copies in Photos or Files remain there.") }
            .sheet(isPresented: $workspace.sourceVisible) { ReceiptSourceView(workspace: workspace) }
            .sheet(isPresented: $walletInformation) { WalletInformationView() }
            .disabled(workspace.saving)
        }
        .tint(.primary)
    }
    private var title: String {
        switch workspace.flow {
        case .wallet: ""
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
            else if workspace.receipts.isEmpty {
                GeometryReader { geometry in
                    ScrollView {
                        VStack(spacing: 24) {
                            if let notice = workspace.notice { Text(notice).font(.subheadline).accessibilityIdentifier("notice") }
                            EmptyWalletArtwork().frame(width: 240, height: 190)
                            VStack(spacing: 10) {
                                Text("A place for your receipts").font(.title2.weight(.semibold))
                                Text("Import a photo. Keep the details.")
                                    .font(.body).foregroundStyle(.primary)
                            }.multilineTextAlignment(.center)
                            Label("Private · on this device", systemImage: "lock")
                                .font(.footnote).foregroundStyle(.primary).padding(.top, 4)
                            debugControls
                        }
                        .padding(.horizontal, 28).padding(.vertical, 32)
                        .frame(maxWidth: .infinity, minHeight: max(0, geometry.size.height - 64))
                    }
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        if let notice = workspace.notice { Text(notice).font(.subheadline).accessibilityIdentifier("notice") }
                        HStack {
                            Text("Recent receipts").font(.headline)
                            Spacer()
                            Text("\(workspace.receipts.count) saved").font(.subheadline).foregroundStyle(.primary)
                        }
                        PaperPocket(workspace: workspace, records: Array(workspace.orderedReceipts.prefix(3)))
                        debugControls
                    }.padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 32)
                }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            Text(workspace.library ? "All receipts" : "Wallet").font(.largeTitle.weight(.bold))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20).padding(.top, 4).padding(.bottom, 16)
                .accessibilityAddTraits(.isHeader)
        }
        .accessibilityIdentifier("walletScreen")
    }
    @ViewBuilder private var debugControls: some View {
        #if DEBUG
        WorkflowTestControls(workspace: workspace)
        #endif
    }
}

/// Illustration only: no fake receipt data or competing action.
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

private struct PaperPocket: View {
    var workspace: ReceiptWorkspace
    let records: [ReceiptRecord]
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    private var reduceMotion: Bool { ReceiptAccessibility.reduceMotion(systemReduceMotion) }
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var systemContrast
    private var contrast: ColorSchemeContrast { ReceiptAccessibility.contrast(systemContrast) }
    @State private var pull: CGFloat = 0
    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: typeSize.isAccessibilitySize ? 14 : -8) {
                ForEach(Array(records.enumerated()), id: \.element.id) { index, record in
                    Button { workspace.open(record) } label: {
                        ReceiptSummary(record: record)
                            .padding(20).frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
                            .overlay { RoundedRectangle(cornerRadius: 18).stroke(.primary.opacity(contrast == .increased ? 0.6 : 0.1), lineWidth: 0.5) }
                            .shadow(color: .black.opacity(scheme == .dark ? 0.35 : 0.09), radius: 12, x: 0, y: 7)
                    }.buttonStyle(.plain)
                        .rotationEffect(.degrees(reduceMotion || typeSize.isAccessibilitySize ? 0 : (index % 2 == 0 ? -0.7 : 0.5)))
                        .offset(y: index == 0 ? pull : 0)
                        .zIndex(Double(records.count - index))
                        .accessibilityIdentifier("receipt-\(index)")
                        .accessibilityHint("Opens receipt and original")
                        .simultaneousGesture(DragGesture(minimumDistance: 24).onChanged { value in
                            guard index == 0, !reduceMotion, !typeSize.isAccessibilitySize, value.translation.height < -20 else { return }
                            pull = max(-60, value.translation.height / 2)
                        }.onEnded { value in
                            guard index == 0, !reduceMotion, !typeSize.isAccessibilitySize else { return }
                            withAnimation(.easeOut(duration: 0.22)) { pull = 0 }
                            if value.translation.height < -64 { workspace.open(record) }
                        })
                }
            }.padding(.horizontal, typeSize.isAccessibilitySize ? 0 : 12)
            if !typeSize.isAccessibilitySize {
                HStack(spacing: 8) {
                    Image(systemName: "wallet.bifold").font(.subheadline)
                    Text("RcpLens").font(.subheadline.weight(.medium))
                    Spacer()
                }.padding(.horizontal, 20).frame(height: 54)
                    .background(Color(uiColor: .tertiarySystemGroupedBackground), in: UnevenRoundedRectangle(topLeadingRadius: 8, bottomLeadingRadius: 22, bottomTrailingRadius: 22, topTrailingRadius: 8))
                    .overlay { UnevenRoundedRectangle(topLeadingRadius: 8, bottomLeadingRadius: 22, bottomTrailingRadius: 22, topTrailingRadius: 8).stroke(.primary.opacity(0.1), lineWidth: 0.5) }
                    .shadow(color: .black.opacity(0.1), radius: 14, y: 8)
                    .padding(.top, -2).accessibilityHidden(true)
            }
        }.padding(.top, 8)
    }
}

private struct WalletInformationView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label("Private by default", systemImage: "lock")
                    Text("Recognition and receipt storage stay on this device.")
                }
                Section("Storage") {
                    Text("Receipts are excluded from automatic backup. There is no export or restore yet. Uninstalling the app or losing this device can lose your receipts.")
                }
                Section("Before you leave") {
                    Text("Save your draft before leaving the app. Backgrounding clears unsaved work.")
                }
                #if DEBUG
                if !SyntheticNativePreview.enabled {
                    Section("Development") { NavigationLink("Synthetic diagnostics") { DiagnosticsView() } }
                }
                #endif
            }.navigationTitle("Your local wallet").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

struct ReceiptSummary: View {
    let record: ReceiptRecord
    @Environment(\.dynamicTypeSize) private var typeSize
    private var total: String {
        record.current.fields.total.map { "\($0.currency.code) \(ExactInput.format($0.minorUnits, scale: $0.currency.minorUnitScale))" } ?? "Total missing"
    }
    private var merchant: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(record.current.fields.merchant ?? "Merchant missing").font(.headline).fixedSize(horizontal: false, vertical: true)
            Text(ExactInput.dateText(record.current.fields.purchaseDate).nilIfEmpty ?? "Date missing").font(.footnote)
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if typeSize.isAccessibilitySize {
                merchant
                Text(total).font(.headline.monospacedDigit())
            } else {
                HStack(alignment: .top, spacing: 16) {
                    merchant
                    Spacer(minLength: 4)
                    Text(total).font(.headline.monospacedDigit()).fixedSize(horizontal: true, vertical: false)
                }
            }
            if !ReceiptCompletion.isComplete(record) {
                Label("Needs review", systemImage: "exclamationmark.circle").font(.caption.weight(.medium))
            }
        }.foregroundStyle(.primary).accessibilityElement(children: .combine)
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
        VStack(spacing: 0) {
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
        }.clipped()
        Color.clear.frame(height: 72).accessibilityHidden(true)
        }.accessibilityIdentifier("receiptLibrary")
    }
}
