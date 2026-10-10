import Foundation
import Observation
import UIKit
#if DEBUG
import CryptoKit
#endif

/// Main-actor presentation state. Only explicit user actions persist receipts or wallet preferences.
@MainActor @Observable
final class ReceiptWorkspace {
    enum Availability: Equatable { case closed, opening, ready, failed(String) }
    enum Flow: Equatable { case wallet, loading, reading, review, detail, failed }
    var availability: Availability = .closed
    var flow: Flow = .wallet
    var receipts: [ReceiptRecord] = [] { didSet { searchIndex = ReceiptSearchIndex(receipts) } }
    private(set) var searchIndex = ReceiptSearchIndex()
    var searchQuery = ""
    var includeArchived = false
    var searchMatch: ReceiptSearchIndex.Match?
    var selected: ReceiptRecord?
    var draft = ReceiptReviewDraft()
    var image: ReceiptImage?
    var extraction: ReceiptExtraction?
    var splitVisible = false
    var sourceVisible = false
    var sourceLineIDs: [UUID] = []
    var errorMessage: String?
    var notice: String?
    var saving = false
    var backupBusy = false
    var backupPreview: ReceiptBackupPreview?
    var backupExportURL: URL?
    var backupMessage: String?
    @ObservationIgnored private var preparedBackup: ReceiptPreparedBackup?
    @ObservationIgnored private var backupTask: Task<Void, Never>?
    @ObservationIgnored private var backupPermit: ReceiptOperationPermit?
    @ObservationIgnored private var backupExportDirectory: URL?
    var sessionID = UUID()
    var privacyCovered = false
    var library = false
    var collection = "All receipts"
    var walletSettings = ReceiptWalletSettings()
    var merchantFilter: ReceiptHistoryChoice = .all
    var monthFilter: ReceiptHistoryChoice = .all
    var active = false
    @ObservationIgnored private var store: ReceiptStore?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var worker: Task<ReceiptExtraction, Error>?
    @ObservationIgnored private var recognition: ReceiptRecognitionJob?
    @ObservationIgnored private var permit = ReceiptOperationPermit()
    @ObservationIgnored private var shutdown: Task<Void, Never>?
    #if DEBUG
    @ObservationIgnored var failNextListRefresh = false // XCTest-only failure boundary; no UI or launch switch.
    #endif
    @ObservationIgnored private let directory: URL?
    @ObservationIgnored private let keyProvider: (any ReceiptStoreKeyProvider)?

    init(directory: URL? = nil, keyProvider: (any ReceiptStoreKeyProvider)? = nil) {
        self.directory = directory; self.keyProvider = keyProvider
    }
    func activate(protectedDataAvailable: Bool) {
        guard protectedDataAvailable else { suspend(); return }
        privacyCovered = false
        guard !active else { return }
        active = true; availability = .opening
        sessionID = UUID(); let session = sessionID
        permit = ReceiptOperationPermit(); let lease = permit
        let previousClose = shutdown
        task = Task { [weak self] in
            await previousClose?.value
            guard let self, self.isCurrent(session) else { return }
            do {
                try lease.check()
                let directory = try self.directory ?? ReceiptStore.applicationDirectory()
                let opened = try ReceiptStore(directory: directory, keyProvider: self.keyProvider ?? KeychainReceiptStoreKey())
                guard self.isCurrent(session) else { try? await opened.close(); return }
                self.store = opened
                let records = try await opened.receipts()
                let settings = try await opened.walletSettings()
                try lease.check()
                guard self.isCurrent(session) else { return }
                self.receipts = records; self.walletSettings = settings; self.availability = .ready
            } catch is CancellationError { }
            catch { if self.isCurrent(session) { self.availability = .failed(Self.storageMessage(error)) } }
        }
    }
    /// Synchronous revocation precedes any actor hop. Queued writes fail or roll back before commit.
    func suspend() {
        active = false; privacyCovered = true; sessionID = UUID()
        permit.revoke(); cancelBackup(); task?.cancel(); worker?.cancel(); recognition?.cancel()
        task = nil; worker = nil; recognition = nil
        let closing = store; store = nil
        let previous = shutdown
        shutdown = Task { await previous?.value; try? await closing?.close() }
        receipts = []; selected = nil; image = nil; extraction = nil
        draft = ReceiptReviewDraft(); sourceVisible = false; splitVisible = false; sourceLineIDs = []
        errorMessage = nil; notice = nil; saving = false; flow = .wallet; availability = .closed
        merchantFilter = .all; monthFilter = .all; library = false
        searchQuery = ""; searchMatch = nil; includeArchived = false
        collection = "All receipts"; walletSettings = ReceiptWalletSettings()
    }
    func retryOpen() { suspend(); activate(protectedDataAvailable: UIApplication.shared.isProtectedDataAvailable) }
    private func isCurrent(_ session: UUID) -> Bool { active && sessionID == session && !Task.isCancelled }
    func startImport(_ load: @escaping @Sendable () async throws -> Data) {
        guard active, availability == .ready, !saving else { return }
        cancelImport(showNotice: false)
        flow = .loading; errorMessage = nil; notice = nil
        let session = sessionID
        task = Task { [weak self] in
            do {
                let data = try await load()
                try Task.checkCancellation()
                guard let self, self.isCurrent(session), self.flow == .loading else { return }
                // Image validation is performed off the UI thread, preserving encoded bytes.
                let decode = Task.detached(priority: .userInitiated) { try ReceiptImage.decode(data) }
                let image = try await withTaskCancellationHandler { try await decode.value } onCancel: { decode.cancel() }
                guard self.isCurrent(session), self.flow == .loading else { return }
                self.image = image; self.readImage()
            } catch is CancellationError { }
            catch {
                guard let self, self.isCurrent(session), self.flow == .loading else { return }
                self.errorMessage = (error as? ImportFailure ?? .unavailableFile).message; self.flow = .failed
            }
        }
    }
    func importFile(_ url: URL) {
        startImport {
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else { throw ImportFailure.unavailableFile }
            guard size > 0, size <= ReceiptStore.maximumAssetBytes else { throw ImportFailure.tooLarge }
            return try Data(contentsOf: url, options: [])
        }
    }
    func readImage() {
        guard let image, active, !saving else { return }
        task?.cancel(); worker?.cancel(); recognition?.cancel()
        draft = ReceiptReviewDraft(); extraction = nil; selected = nil; sourceVisible = false
        flow = .reading; errorMessage = nil
        let job = ReceiptRecognitionJob(); recognition = job
        let session = sessionID
        let work = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            let result = try job.run(image)
            try Task.checkCancellation()
            return try ReceiptParser.extraction(result)
        }
        worker = work
        task = Task { [weak self] in
            do {
                let extraction = try await withTaskCancellationHandler { try await work.value } onCancel: { job.cancel(); work.cancel() }
                guard let self, self.isCurrent(session), self.recognition === job else { return }
                self.extraction = extraction
                self.draft = ReceiptReviewDraft(parsed: try JSONDecoder().decode(ParsedReceipt.self, from: extraction.rawParserOutput))
                self.worker = nil; self.recognition = nil
                if extraction.rawOCR.isEmpty { self.flow = .failed; self.errorMessage = ImportFailure.noText.message }
                else { self.flow = .review }
            } catch is CancellationError { }
            catch {
                guard let self, self.isCurrent(session), self.recognition === job else { return }
                self.worker = nil; self.recognition = nil
                #if DEBUG
                if WorkflowTestInput.enabled {
                    let e = error as NSError
                    if let bytes = try? JSONSerialization.data(withJSONObject: ["domain":e.domain,"code":e.code]) {
                        try? bytes.write(to: WorkflowTestInput.directory.appendingPathComponent("recognition-error.json"), options: .atomic)
                    }
                }
                #endif
                self.errorMessage = ImportFailure.recognitionFailed.message; self.flow = .failed
            }
        }
    }
    func manualReview() {
        guard image != nil, active, !saving else { return }
        task?.cancel(); worker?.cancel(); recognition?.cancel(); worker = nil; recognition = nil
        if extraction == nil {
            let result = OCRResult(lines: [], revision: 0)
            extraction = try? ReceiptParser.extraction(result)
        }
        draft = ReceiptReviewDraft(); flow = .review; sourceVisible = false
    }
    func cancelImport(showNotice: Bool = true) {
        guard !saving else { return }
        task?.cancel(); worker?.cancel(); recognition?.cancel(); worker = nil; recognition = nil
        image = nil; extraction = nil; selected = nil; draft = ReceiptReviewDraft()
        sourceVisible = false; sourceLineIDs = []; searchMatch = nil; errorMessage = nil; flow = .wallet
        if showNotice { notice = "Unsaved receipt discarded." }
    }
    func showSource(ids: [UUID] = []) {
        guard image != nil else { return }
        sourceLineIDs = ids; sourceVisible = true
        if flow == .review { draft.sourceOpened = true }
    }
    func open(_ record: ReceiptRecord, match: ReceiptSearchIndex.Match? = nil) {
        guard let store, active, !saving else { return }
        task?.cancel(); let session = sessionID
        selected = record; image = nil; extraction = record.original; searchMatch = match
        flow = .detail; errorMessage = nil
        task = Task { [weak self] in
            do {
                guard let current = try await store.receipt(id: record.id) else { throw ReceiptStoreError.notFound }
                let bytes = try await store.originalImage(receiptID: record.id)
                let decoded = try await Task.detached(priority: .userInitiated) { try ReceiptImage.decode(bytes) }.value
                guard let self, self.isCurrent(session), self.flow == .detail, self.selected?.id == record.id else { return }
                self.selected = current; self.image = decoded; self.extraction = current.original; self.flow = .detail
                if let index = self.receipts.firstIndex(where: { $0.id == current.id }) { self.receipts[index] = current }
            } catch {
                guard let self, self.isCurrent(session) else { return }
                guard self.selected?.id == record.id, self.flow == .detail else { return }
                self.errorMessage = Self.storageMessage(error)
            }
        }
    }
    func edit() {
        guard let selected, image != nil, !saving else { return }
        searchMatch = nil
        if let bytes = selected.current.reviewInput, let input = try? JSONDecoder().decode(ReceiptReviewDraft.self, from: bytes) { draft = input }
        else { draft = ReceiptReviewDraft(fields: selected.current.fields) }
        draft.sourceChecked = false; draft.sourceOpened = false
        flow = .review; errorMessage = nil
    }
    func finishEditing() {
        guard !saving else { return }
        draft = ReceiptReviewDraft(); errorMessage = nil
        if selected != nil { flow = .detail } else { cancelImport() }
    }
    func updateDraft(_ change: (inout ReceiptReviewDraft) -> Void) {
        guard !saving else { return }
        let previous = draft
        change(&draft)
        if draft != previous { draft.sourceChecked = false; draft.sourceOpened = false }
    }
    /// Focused sheets edit a local copy; cancel never touches the receipt or its review confirmation.
    func applyFocusedCorrection(_ input: ReceiptReviewDraft, check: ReceiptReviewGuidance, markChecked: Bool = true) {
        guard active, flow == .review, !saving, image != nil, !privacyCovered, ReceiptFocusedCorrection.canApply(input, replacing: draft) else { return }
        updateDraft { $0 = input }
        draft.sourceOpened = true // The original was displayed in the focused comparison.
        draft.sourceChecked = false // One check never confirms every field/purchase.
        if !check.requiresCorrection && markChecked {
            if draft.guidanceChecks == nil { draft.guidanceChecks = [:] }
            let signature = check.signature(in: draft)
            draft.guidanceChecks?[check.id] = signature
        } else if !markChecked {
            draft.guidanceChecks?[check.id] = nil
        }
    }
    func save(asDraft: Bool) {
        guard active, !saving, let store, let image, let extraction,
              asDraft ? draft.canSaveDraft : draft.canFinalize else { return }
        let fields = draft.fields
        let review: ReceiptRevision.Review = asDraft ? .draft : .sourceReviewed
        let session = sessionID, lease = permit, old = selected
        let input: Data
        do { input = try JSONEncoder().encode(draft); try fields.validate() }
        catch { errorMessage = "Check the entered values before saving."; return }
        saving = true; errorMessage = nil
        task = Task { [weak self] in
            do {
                try lease.check()
                let saved: ReceiptRecord
                if let old {
                    saved = try await store.revise(id: old.id, expectedRevision: old.current.id, fields: fields, review: review, reviewInput: input, permit: lease)
                } else {
                    saved = try await store.create(extraction: extraction, originalImage: image.bytes, mediaType: image.mediaType,
                        correction: fields, review: review, reviewInput: input, permit: lease)
                }
                try lease.check()
                guard let self, self.isCurrent(session) else { return }
                // Reflect the committed identity before refreshing. A failed list must not allow duplicate creation on retry.
                self.selected = saved; self.draft = ReceiptReviewDraft(); self.flow = .detail
                if let index = self.receipts.firstIndex(where: { $0.id == saved.id }) { self.receipts[index] = saved }
                else { self.receipts.append(saved) }
                let records = try await self.refreshedList(store)
                guard self.isCurrent(session) else { return }
                self.receipts = records
                self.saving = false; self.flow = .detail
                self.notice = asDraft ? "Draft saved. It still needs review." : "Receipt reviewed and saved."
            } catch is CancellationError { }
            catch {
                guard let self, self.isCurrent(session) else { return }
                self.saving = false; self.errorMessage = self.flow == .detail ? "Receipt saved, but the wallet could not refresh. Return to the wallet and reopen it." : Self.storageMessage(error)
                if error as? ReceiptStoreError == .editConflict { self.errorMessage = "This receipt changed elsewhere. Return to the wallet and reopen it before editing again." }
            }
        }
    }
    func deleteSelected() { if let selected { deleteReceipt(selected) } }
    func deleteReceipt(_ record: ReceiptRecord) {
        guard active, !saving, let store else { return }
        let selected = record
        let session = sessionID, lease = permit
        saving = true
        task = Task { [weak self] in
            var committed = false
            do {
                try await store.delete(id: selected.id, permit: lease)
                committed = true
                try lease.check()
                guard let self, self.isCurrent(session) else { return }
                // Forget deleted evidence as soon as DELETE commits, independently of list refresh.
                self.selected = nil; self.image = nil; self.extraction = nil; self.draft = ReceiptReviewDraft()
                self.sourceVisible = false; self.sourceLineIDs = []; self.searchMatch = nil; self.flow = .wallet
                self.receipts.removeAll { $0.id == selected.id }
                self.notice = "Receipt and original deleted from this app."
                let records = try await self.refreshedList(store)
                guard self.isCurrent(session) else { return }
                self.saving = false; self.receipts = records
            } catch is CancellationError { }
            catch {
                guard let self, self.isCurrent(session) else { return }
                self.saving = false
                if committed { self.notice = "Receipt deleted, but the wallet could not refresh. Reopen the wallet to try again." }
                else { self.errorMessage = Self.storageMessage(error); if self.flow == .wallet { self.notice = self.errorMessage } }
            }
        }
    }
    func organize(_ record: ReceiptRecord, action: ReceiptWalletAction) {
        guard active, !saving, let store, action == .archive || action == .star else { return }
        let session = sessionID, lease = permit
        saving = true
        task = Task { [weak self] in
            do {
                let updated = try await store.organize(id: record.id, expectedRevision: record.current.id, action: action, permit: lease)
                try lease.check()
                guard let self, self.isCurrent(session) else { return }
                if let index = self.receipts.firstIndex(where: { $0.id == record.id }) { self.receipts[index] = updated }
                if self.selected?.id == record.id { self.selected = updated }
                self.saving = false
                if action == .archive && self.flow == .detail { self.backToWallet() }
            } catch {
                guard let self, self.isCurrent(session) else { return }
                self.saving = false; self.notice = Self.storageMessage(error)
                if self.flow == .detail { self.errorMessage = self.notice }
            }
        }
    }
    func setWalletSettings(_ settings: ReceiptWalletSettings) {
        guard active, !saving, let store else { return }
        let session = sessionID, lease = permit
        saving = true
        task = Task { [weak self] in
            do {
                try await store.saveWalletSettings(settings, permit: lease)
                try lease.check()
                guard let self, self.isCurrent(session) else { return }
                self.walletSettings = settings; self.saving = false
            } catch {
                guard let self, self.isCurrent(session) else { return }
                self.saving = false; self.notice = Self.storageMessage(error)
            }
        }
    }
    private func refreshedList(_ store: ReceiptStore) async throws -> [ReceiptRecord] {
        #if DEBUG
        if failNextListRefresh { failNextListRefresh = false; throw ReceiptStoreError.injectedFailure }
        #endif
        return try await store.receipts()
    }

    func saveSplit(_ plan: ReceiptSplitPlan, finalize: Bool) {
        guard let store, let selected, active, !saving else { return }
        let session = sessionID, lease = permit
        saving = true; errorMessage = nil
        task = Task { [weak self] in
            do {
                let saved = try await store.saveSplit(id: selected.id, expectedRevision: selected.current.id,
                    expectedPlan: selected.splitPlan?.id, plan: plan, finalize: finalize, permit: lease)
                try lease.check()
                guard let self, self.isCurrent(session), self.selected?.id == selected.id else { return }
                self.selected = saved
                if let index = self.receipts.firstIndex(where: { $0.id == saved.id }) { self.receipts[index] = saved }
                self.saving = false; self.notice = finalize ? "Split finalized." : "Split choices saved."
            } catch is CancellationError { }
            catch {
                guard let self, self.isCurrent(session) else { return }
                self.saving = false
                self.errorMessage = (error as? SplitError)?.errorDescription ?? Self.storageMessage(error)
            }
        }
    }


    /// Backup cancellation has its own lease so cancelling a file chooser never locks the wallet.
    func cancelBackup() {
        let restoring = preparedBackup != nil && backupBusy
        if restoring { saving = false }
        backupPermit?.revoke(); backupTask?.cancel(); backupTask = nil; backupPermit = nil
        preparedBackup = nil; backupPreview = nil; backupExportURL = nil
        if let directory = backupExportDirectory { try? FileManager.default.removeItem(at: directory) }
        backupExportDirectory = nil; backupBusy = false; backupMessage = nil
        // A revoke may follow an already completed commit. Refresh after the actor finishes rather
        // than leaving a stale wallet or claiming that cancellation undid committed receipts.
        if restoring, active, let store {
            let session = sessionID
            Task { [weak self] in
                if let records = try? await store.receipts(), let self, self.isCurrent(session) { self.receipts = records }
            }
        }
    }
    func beginBackupExport(password: String) {
        guard active, availability == .ready, !privacyCovered, !saving, !backupBusy, let store else { return }
        cancelBackup()
        let lease = ReceiptOperationPermit(), session = sessionID
        backupPermit = lease; backupBusy = true
        backupTask = Task { [weak self] in
            var outputDirectory: URL?
            do {
                let directory = try ReceiptBackupArchive.temporaryDirectory(); outputDirectory = directory
                let url = directory.appendingPathComponent("Sliplet-backup.slipletbackup")
                try await store.exportBackup(to: url, password: password, permit: lease)
                try lease.check()
                guard let self, self.isCurrent(session) else { try? FileManager.default.removeItem(at: directory); return }
                self.backupExportDirectory = directory; self.backupExportURL = url; self.backupBusy = false
            } catch {
                if let outputDirectory { try? FileManager.default.removeItem(at: outputDirectory) }
                guard let self, self.isCurrent(session), self.backupPermit === lease else { return }
                self.backupBusy = false
                if !(error is CancellationError) { self.backupMessage = Self.backupErrorMessage(error) }
            }
        }
    }
    func finishBackupExport(saved: Bool) {
        cancelBackup(); backupMessage = saved ? "Encrypted backup saved. Keep its password separately." : "Export cancelled. No backup was saved by Sliplet."
    }
    func prepareBackupRestore(url: URL, password: String) {
        guard active, availability == .ready, !privacyCovered, !saving, !backupBusy, let store else { return }
        cancelBackup()
        let lease = ReceiptOperationPermit(), session = sessionID
        backupPermit = lease; backupBusy = true
        let work = Task.detached(priority: .userInitiated) {
            try await ReceiptBackupPreparation.prepare(url: url, password: password, permit: lease)
        }
        backupTask = Task { [weak self] in
            do {
                let prepared = try await withTaskCancellationHandler { try await work.value } onCancel: { lease.revoke(); work.cancel() }
                let preview = try await store.previewBackup(prepared, permit: lease)
                try lease.check()
                guard let self, self.isCurrent(session), self.backupPermit === lease else { return }
                self.preparedBackup = prepared; self.backupPreview = preview; self.backupBusy = false
            } catch {
                guard let self, self.isCurrent(session), self.backupPermit === lease else { return }
                self.backupBusy = false
                if !(error is CancellationError) { self.backupMessage = Self.backupErrorMessage(error) }
            }
        }
    }
    func confirmBackupRestore() {
        guard active, !privacyCovered, !saving, !backupBusy, let store, let preparedBackup,
              let expected = backupPreview, let lease = backupPermit else { return }
        let session = sessionID
        backupBusy = true; saving = true; backupMessage = nil
        backupTask = Task { [weak self] in
            var result: ReceiptBackupPreview?
            do {
                result = try await store.mergeBackup(preparedBackup, expected: expected, permit: lease)
                let records = try await store.receipts(); try lease.check()
                guard let self, self.isCurrent(session), self.backupPermit === lease, let result else { return }
                self.receipts = records; self.preparedBackup = nil; self.backupPreview = nil
                self.saving = false; self.backupBusy = false
                self.backupMessage = "Restored \(result.added) \(result.added == 1 ? "receipt" : "receipts"). Kept \(result.skipped) existing \(result.skipped == 1 ? "receipt" : "receipts") unchanged."
            } catch {
                guard let self, self.isCurrent(session), self.backupPermit === lease else { return }
                self.saving = false; self.backupBusy = false
                self.preparedBackup = nil; self.backupPreview = nil
                self.backupMessage = result == nil ? Self.backupErrorMessage(error) : "Receipts restored, but the wallet could not refresh. Close Settings and reopen Sliplet."
            }
        }
    }
    static func backupErrorMessage(_ error: Error) -> String {
        (error as? ReceiptBackupError)?.errorDescription ?? "The backup action could not finish safely. Existing receipts have not been replaced. Try again with an available file after unlocking."
    }

    func backToWallet() { cancelImport(showNotice: false) }
    var orderedReceipts: [ReceiptRecord] {
        receipts.sorted {
            let a = ExactInput.dateText($0.current.fields.purchaseDate), b = ExactInput.dateText($1.current.fields.purchaseDate)
            return a == b ? $0.createdAt > $1.createdAt : a > b
        }
    }
    static func storageMessage(_ error: Error) -> String {
        guard let error = error as? ReceiptStoreError else { return "Local storage could not complete this action. Your stored data has not been reset. Try again after unlocking." }
        switch error {
        case .missingKey, .invalidKey, .authenticationFailed:
            return "The local encryption key is missing or does not match. Existing receipts have not been reset. Keep the app and its data intact."
        case .corruptStore, .unsupportedSchema:
            return "This local store cannot be read safely. Existing data has not been reset. Keep the app and its data intact."
        case .keychain, .protectionUnavailable, .closed:
            return "Local storage is unavailable. Unlock the device and try again. Existing data has not been reset."
        case .sizeLimit: return "This receipt exceeds a local storage limit. Return to the wallet and try a new import. The existing receipt is unchanged."
        case .editConflict: return "This receipt changed elsewhere. Reopen it before editing again."
        case .notFound: return "This receipt is no longer available. Return to the wallet."
        default: return "The local save did not complete. Check your receipt and try again."
        }
    }
    #if DEBUG
    /// DEBUG-only selected-file fixture, available solely after a synthetic-preview launch.
    /// Creates a conflicting fictional version and one new finalized fictional receipt in a temporary store.
    func prepareFictionalBackupForNativeCheck() {
        guard SyntheticNativePreview.enabled, ProcessInfo.processInfo.arguments.contains("--p205-backup-fixture"),
              active, !saving, !backupBusy, let store, let existing = receipts.first else { return }
        cancelBackup()
        let session = sessionID, lease = ReceiptOperationPermit()
        backupPermit = lease; backupBusy = true
        let (image, draft) = SyntheticNativePreview.fixture(index: 2)
        backupTask = Task { [weak self] in
            var directory: URL?
            do {
                let root = try ReceiptBackupArchive.temporaryDirectory(); directory = root
                let key = try ReceiptBackupArchive.randomKey()
                let source = try ReceiptStore(directory: root, keyProvider: ReceiptBackupTemporaryKey(bytes: key))
                let now = Date()
                let extraction = ReceiptExtraction(capturedAt: now, recognizer: "FICTIONAL", recognizerVersion: "1",
                    parser: "FICTIONAL", parserVersion: "1", rawOCR: [], rawParserOutput: Data("{}".utf8), fields: draft.fields, issues: [])
                let created = try await source.create(extraction: extraction, originalImage: image, mediaType: "image/png",
                    correction: draft.fields, review: .sourceReviewed, reviewInput: JSONEncoder().encode(draft), permit: lease)
                let person = SplitParticipant(id: UUID(), name: "FICTIONAL PERSON")
                let plan = ReceiptSplitPlan(participants: [person], assignments: Dictionary(uniqueKeysWithValues: created.current.fields.items.map { ($0.id, [person.id]) }))
                let added = try await source.saveSplit(id: created.id, expectedRevision: created.current.id, expectedPlan: nil, plan: plan, finalize: true, permit: lease)
                try await source.close()
                let oldImage = try await store.originalImage(receiptID: existing.id)
                var fields = existing.current.fields; fields.merchant = "FICTIONAL DIFFERING BACKUP VERSION"
                let revision = ReceiptRevision(id: UUID(), createdAt: now, fields: fields, review: .draft)
                let conflict = ReceiptRecord(id: existing.id, createdAt: existing.createdAt, updatedAt: now, original: existing.original,
                    asset: existing.asset, revisions: existing.revisions + [revision], organization: existing.organization)
                let url = root.appendingPathComponent("native-fixture.slipletbackup")
                let writer = try ReceiptBackupArchive.Writer(url: url, password: "fictional-backup-password")
                try writer.write(JSONEncoder().encode(ReceiptBackupManifest(version: 1, storeSchema: ReceiptStore.schemaVersion,
                    createdAt: now, receiptCount: 2, walletSettings: ReceiptWalletSettings())), maximum: 16_384, permit: lease)
                for (record, bytes) in [(conflict, oldImage), (added, image)] {
                    try writer.write(JSONEncoder().encode(record), maximum: ReceiptStore.maximumRecordBytes, permit: lease)
                    try writer.write(bytes, maximum: ReceiptStore.maximumAssetBytes, permit: lease)
                }
                try writer.finish(); try lease.check()
                guard let self, self.isCurrent(session), self.backupPermit === lease else { try? FileManager.default.removeItem(at: root); return }
                self.backupBusy = false
                self.prepareBackupRestore(url: url, password: "fictional-backup-password")
                self.backupExportDirectory = root // Keep the encrypted fixture until this backup session closes.
            } catch {
                if let directory { try? FileManager.default.removeItem(at: directory) }
                guard let self, self.isCurrent(session), self.backupPermit === lease else { return }
                self.backupBusy = false; self.backupMessage = "Fictional backup setup failed."
            }
        }
    }
    /// Explicit simulator action only; append ten marked samples without resetting records or settings.
    func addFictionalDemoReceipts() async -> Int {
        guard let store, active, !saving else { return 0 }
        var added = 0
        let session = sessionID, lease = permit
        saving = true
        defer { if isCurrent(session) { saving = false } }
        do {
            var existing = Set(receipts.map { $0.asset.sha256 })
            for index in 0..<10 {
                try Task.checkCancellation(); try lease.check()
                let (bytes, draft) = SyntheticNativePreview.demoFixture(index: index)
                let digest = Data(SHA256.hash(data: bytes))
                if existing.contains(digest) { continue }
                let result = try await Task.detached { try ReceiptRecognitionJob().run(ReceiptImage.decode(bytes)) }.value
                _ = try await store.create(extraction: ReceiptParser.extraction(result), originalImage: bytes, mediaType: "image/png",
                    correction: draft.fields, review: .sourceReviewed, reviewInput: JSONEncoder().encode(draft), permit: lease)
                existing.insert(digest); added += 1
            }
            let records = try await store.receipts(); try lease.check()
            if isCurrent(session) { receipts = records }
        } catch {
            if isCurrent(session) { notice = "Demo receipt setup did not finish. Existing receipts are preserved." }
        }
        return added
    }
    /// Called only for the separate fictional-preview store configured at launch.
    func seedFictionalRecordsForPreview(count: Int) async {
        guard SyntheticNativePreview.enabled, let store, active else { return }
        do {
            try Task.checkCancellation()
            try await store.purgeAllReceipts()
            let settings = ReceiptWalletSettings(paperAppearance: ProcessInfo.processInfo.arguments.contains("--t05-white-paper") ? .alwaysWhite : .matchAppearance)
            try await store.saveWalletSettings(settings)
            walletSettings = settings
            if SyntheticNativePreview.mode.hasPrefix("correction-") {
                let (bytes, extraction, draft) = try SyntheticCorrectionPreview.fixture(SyntheticNativePreview.mode)
                _ = try await store.create(extraction: extraction, originalImage: bytes, mediaType: "image/png", correction: draft.fields,
                    review: .draft, reviewInput: JSONEncoder().encode(draft), permit: permit)
                receipts = try await store.receipts()
                return
            }
            if ["search", "search-large"].contains(SyntheticNativePreview.mode) {
                for index in 0..<count {
                    try Task.checkCancellation()
                    let (bytes, extraction, draft) = SyntheticSearchPreview.fixture(index)
                    _ = try await store.create(extraction: extraction, originalImage: bytes, mediaType: "image/png", correction: draft.fields,
                        review: draft.date.isEmpty ? .draft : .sourceReviewed, reviewInput: JSONEncoder().encode(draft), permit: permit)
                }
                receipts = try await store.receipts()
                return
            }
            var fixtures: [(Data, ReceiptReviewDraft, ReceiptExtraction)] = []
            for index in 0..<3 {
                try Task.checkCancellation()
                let (bytes, draft) = SyntheticNativePreview.fixture(index: index)
                let result = try await Task.detached { try ReceiptRecognitionJob().run(ReceiptImage.decode(bytes)) }.value
                fixtures.append((bytes, draft, try ReceiptParser.extraction(result)))
            }
            for index in 0..<count {
                try Task.checkCancellation()
                let (bytes, draft, extraction) = fixtures[index % 3]
                _ = try await store.create(extraction: extraction, originalImage: bytes, mediaType: "image/png", correction: draft.fields,
                    review: .sourceReviewed, reviewInput: JSONEncoder().encode(draft), permit: permit)
            }
            receipts = try await store.receipts()
        } catch is CancellationError { }
        catch { notice = "Synthetic preview setup failed." }
    }
    #endif

}
