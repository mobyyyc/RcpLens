import Foundation
import Observation
import UIKit

/// Main-actor presentation state. Nothing here is persisted until an explicit Save action.
@MainActor @Observable
final class ReceiptWorkspace {
    enum Availability: Equatable { case closed, opening, ready, failed(String) }
    enum Flow: Equatable { case wallet, loading, reading, review, detail, failed }
    var availability: Availability = .closed
    var flow: Flow = .wallet
    var receipts: [ReceiptRecord] = []
    var selected: ReceiptRecord?
    var draft = ReceiptReviewDraft()
    var image: ReceiptImage?
    var extraction: ReceiptExtraction?
    var sourceVisible = false
    var sourceLineIDs: [UUID] = []
    var errorMessage: String?
    var notice: String?
    var saving = false
    var sessionID = UUID()
    var privacyCovered = false
    var library = false
    var merchantFilter = "All stores"
    var monthFilter = "All months"
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
                try lease.check()
                guard self.isCurrent(session) else { return }
                self.receipts = records; self.availability = .ready
            } catch is CancellationError { }
            catch { if self.isCurrent(session) { self.availability = .failed(Self.storageMessage(error)) } }
        }
    }
    /// Synchronous revocation precedes any actor hop. Queued writes fail or roll back before commit.
    func suspend() {
        active = false; privacyCovered = true; sessionID = UUID()
        permit.revoke(); task?.cancel(); worker?.cancel(); recognition?.cancel()
        task = nil; worker = nil; recognition = nil
        let closing = store; store = nil
        let previous = shutdown
        shutdown = Task { await previous?.value; try? await closing?.close() }
        receipts = []; selected = nil; image = nil; extraction = nil
        draft = ReceiptReviewDraft(); sourceVisible = false; sourceLineIDs = []
        errorMessage = nil; notice = nil; saving = false; flow = .wallet; availability = .closed
        merchantFilter = "All stores"; monthFilter = "All months"; library = false
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
        sourceVisible = false; sourceLineIDs = []; errorMessage = nil; flow = .wallet
        if showNotice { notice = "Unsaved receipt discarded." }
    }
    func showSource(ids: [UUID] = []) {
        guard image != nil else { return }
        sourceLineIDs = ids; sourceVisible = true
        if flow == .review { draft.sourceOpened = true }
    }
    func open(_ record: ReceiptRecord) {
        guard let store, active, !saving else { return }
        task?.cancel(); let session = sessionID
        selected = nil; image = nil; extraction = nil
        flow = .loading; errorMessage = nil
        task = Task { [weak self] in
            do {
                guard let current = try await store.receipt(id: record.id) else { throw ReceiptStoreError.notFound }
                let bytes = try await store.originalImage(receiptID: record.id)
                let decoded = try ReceiptImage.decode(bytes)
                guard let self, self.isCurrent(session), self.flow == .loading else { return }
                self.selected = current; self.image = decoded; self.extraction = current.original; self.flow = .detail
            } catch {
                guard let self, self.isCurrent(session) else { return }
                self.flow = .failed; self.errorMessage = Self.storageMessage(error)
            }
        }
    }
    func edit() {
        guard let selected, !saving else { return }
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
    func deleteSelected() {
        guard active, !saving, let selected, let store else { return }
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
                self.sourceVisible = false; self.sourceLineIDs = []; self.flow = .wallet
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
                else { self.errorMessage = Self.storageMessage(error) }
            }
        }
    }
    private func refreshedList(_ store: ReceiptStore) async throws -> [ReceiptRecord] {
        #if DEBUG
        if failNextListRefresh { failNextListRefresh = false; throw ReceiptStoreError.injectedFailure }
        #endif
        return try await store.receipts()
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
    /// Called only for the separate fictional-preview store configured at launch.
    func seedFictionalRecordsForPreview(count: Int) async {
        guard SyntheticNativePreview.enabled, let store, active else { return }
        do {
            try await store.purgeAllReceipts()
            var fixtures: [(Data, ReceiptReviewDraft, ReceiptExtraction)] = []
            for index in 0..<3 {
                let (bytes, draft) = SyntheticNativePreview.fixture(index: index)
                let result = try await Task.detached { try ReceiptRecognitionJob().run(ReceiptImage.decode(bytes)) }.value
                fixtures.append((bytes, draft, try ReceiptParser.extraction(result)))
            }
            for index in 0..<count {
                let (bytes, draft, extraction) = fixtures[index % 3]
                _ = try await store.create(extraction: extraction, originalImage: bytes, mediaType: "image/png", correction: draft.fields,
                    review: .sourceReviewed, reviewInput: JSONEncoder().encode(draft), permit: permit)
            }
            receipts = try await store.receipts()
        } catch { notice = "Synthetic preview setup failed." }
    }
    #endif

}
