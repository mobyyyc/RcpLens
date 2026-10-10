import SwiftUI
import UniformTypeIdentifiers
import UIKit

enum ReceiptBackupMode: String, Identifiable { case export, restore; var id: String { rawValue } }
struct ReceiptBackupSettingsSection: View {
    @Bindable var workspace: ReceiptWorkspace
    @Binding var mode: ReceiptBackupMode?
    var body: some View {
        Section {
            Button("Export encrypted backup", systemImage: "square.and.arrow.up") { mode = .export }
                .accessibilityIdentifier("exportBackup")
            Button("Restore from backup", systemImage: "square.and.arrow.down") { mode = .restore }
                .accessibilityIdentifier("restoreBackup")
        } header: { Text("Backup") } footer: {
            Text("Receipts stay on this device until you choose to export. Deleting Sliplet or losing this device can lose your receipts without a backup.")
        }
    }
}
struct ReceiptBackupView: View {
    @Bindable var workspace: ReceiptWorkspace
    let mode: ReceiptBackupMode
    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var confirmation = ""
    @State private var selectingFile = false
    @State private var exportingFile = false
    @State private var selectionPassword = ""
    @State private var localMessage: String?
    private var passwordValid: Bool { password.count >= 12 && password.utf8.count <= 1_024 }
    var body: some View {
        let exportSession = workspace.sessionID
        let exportedURL = workspace.backupExportURL
        NavigationStack {
            Form {
                if workspace.privacyCovered {
                    Section { Label("Return after unlocking to continue.", systemImage: "lock") }
                } else {
                    if let preview = workspace.backupPreview {
                        Section("Restore preview") {
                            LabeledContent("Receipts in backup", value: "\(preview.total)")
                            LabeledContent("New receipts", value: "\(preview.added)")
                            LabeledContent("Existing receipts skipped", value: "\(preview.skipped)")
                            LabeledContent("Differing versions skipped", value: "\(preview.conflicts)")
                            Text("Existing receipts, edits and wallet settings will stay unchanged. Only missing receipts will be added with their originals, history and split choices. Differing versions are included in the skipped count.")
                                .font(.footnote).foregroundStyle(.secondary)
                            Button("Add \(preview.added) \(preview.added == 1 ? "receipt" : "receipts")") { workspace.confirmBackupRestore() }
                                .buttonStyle(ReceiptProminentStyle())
                                .disabled(preview.added == 0 || workspace.backupBusy).accessibilityIdentifier("confirmBackupRestore")
                        }
                    } else {
                        Section {
                            SecureField("Backup password", text: $password).textContentType(mode == .export ? .newPassword : .password)
                                .accessibilityIdentifier("backupPassword")
                            if mode == .export {
                                SecureField("Confirm password", text: $confirmation).textContentType(.newPassword)
                                    .accessibilityIdentifier("backupPasswordConfirmation")
                            }
                        } header: { Text(mode == .export ? "Choose a backup password" : "Enter the backup password") } footer: {
                            Text("Use at least 12 characters. Keep the password separately: a forgotten backup password cannot be recovered. Sliplet does not save it.")
                        }
                        Section {
                            #if DEBUG
                            if mode == .restore && SyntheticNativePreview.enabled && ProcessInfo.processInfo.arguments.contains("--p205-backup-fixture") {
                                Button("Use fictional test file") { workspace.prepareFictionalBackupForNativeCheck() }
                                    .accessibilityIdentifier("useFictionalBackup")
                            }
                            #endif
                            if mode == .export {
                                Button("Choose where to save") {
                                    workspace.beginBackupExport(password: password); clearPasswords()
                                }.buttonStyle(ReceiptProminentStyle())
                                    .disabled(!passwordValid || password != confirmation || workspace.backupBusy)
                                    .accessibilityIdentifier("chooseBackupDestination")
                            } else {
                                Button("Choose backup file") {
                                    selectionPassword = password; password = ""; selectingFile = true
                                }.buttonStyle(ReceiptSecondaryStyle())
                                    .disabled(!passwordValid || workspace.backupBusy).accessibilityIdentifier("chooseBackupFile")
                            }
                        } footer: {
                            Text(mode == .export ? "Includes every saved receipt and original image, revisions, review notes, archive/star choices, split choices and wallet preferences. You choose the destination in Files; the file is encrypted before it leaves Sliplet." : "Choose one .slipletbackup file in Files. Sliplet validates it before showing a preview. Restore adds missing receipts and keeps existing versions and wallet preferences.")
                        }
                    }
                    if workspace.backupBusy { Section { ProgressView(mode == .export ? "Encrypting backup…" : "Checking or restoring backup…") } }
                    if let message = localMessage ?? workspace.backupMessage {
                        Section { Text(message).accessibilityIdentifier("backupMessage") }
                    }
                }
            }
            .navigationTitle(mode == .export ? "Export backup" : "Restore backup").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) {
                Button("Close") { clearPasswords(); workspace.cancelBackup(); dismiss() }.accessibilityIdentifier("closeBackup")
            } }
            .sheet(isPresented: $selectingFile, onDismiss: { selectionPassword = "" }) {
                ReceiptBackupFileImporter(password: selectionPassword, sessionID: workspace.sessionID) { result, selectedPassword, pickerSession in
                    guard workspace.active, workspace.sessionID == pickerSession else { return }
                    // The picker coordinator captured this secret at presentation. Parent dismissal
                    // may clear State before the delegate callback, without breaking file selection.
                    selectionPassword = ""; selectingFile = false
                    switch result {
                    case .success(let files):
                        guard files.count == 1, let file = files.first else { localMessage = "Choose one backup file."; return }
                        localMessage = nil; workspace.prepareBackupRestore(url: file, password: selectedPassword)
                    case .failure:
                        localMessage = "File selection cancelled or unavailable. Your wallet has not changed."
                    }
                }
            }
            .sheet(isPresented: Binding(get: { exportingFile && workspace.sessionID == exportSession }, set: { presented in
                guard !presented, workspace.active, workspace.sessionID == exportSession,
                      let exportedURL, workspace.backupExportURL == exportedURL else { return }
                // Native save dismisses before its delegate result. Stop presentation now;
                // the guarded delegate (or coordinator release after a swipe) owns cleanup.
                exportingFile = false
            })) {
                if let url = exportedURL {
                    ReceiptBackupFileExporter(url: url) { saved in
                        guard workspace.active, workspace.sessionID == exportSession, workspace.backupExportURL == url else { return }
                        workspace.finishBackupExport(saved: saved)
                    }
                }
            }
            .onChange(of: workspace.backupExportURL) { _, url in exportingFile = url != nil }
            .onChange(of: workspace.active) { _, active in
                if !active { selectingFile = false; exportingFile = false; clearPasswords(); dismiss() }
            }
            .onDisappear { if !selectingFile && workspace.backupExportURL == nil { clearPasswords() } }
        }.tint(.primary)
    }
    private func clearPasswords() { password = ""; confirmation = ""; selectionPassword = "" }
}
/// Export an already encrypted file; avoid FileDocument's whole-archive Data copy on the UI thread.
struct ReceiptBackupFileExporter: UIViewControllerRepresentable {
    let url: URL
    let completion: @MainActor (Bool) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(completion: completion) }
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forExporting: [url], asCopy: true)
        picker.delegate = context.coordinator; return picker
    }
    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}
    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let completion: @MainActor (Bool) -> Void
        init(completion: @escaping @MainActor (Bool) -> Void) { self.completion = completion }
        deinit {
            // A native swipe can dismiss without invoking the document delegate. After native
            // references release, cancel only if the captured session/file is still pending.
            // A preceding successful result already cleared that identity and ignores this.
            let callback = completion
            Task { @MainActor in callback(false) }
        }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { completion(false) }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) { completion(!urls.isEmpty) }
    }
}

/// An explicit selection/cancel callback owns password disposal, independently of presentation bindings.
struct ReceiptBackupFileImporter: UIViewControllerRepresentable {
    let password: String
    let sessionID: UUID
    let completion: (Result<[URL], Error>, String, UUID) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(password: password, sessionID: sessionID, completion: completion) }
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.data], asCopy: false)
        picker.allowsMultipleSelection = false; picker.delegate = context.coordinator; return picker
    }
    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}
    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        private var password: String
        private let sessionID: UUID
        let completion: (Result<[URL], Error>, String, UUID) -> Void
        init(password: String, sessionID: UUID, completion: @escaping (Result<[URL], Error>, String, UUID) -> Void) {
            self.password = password; self.sessionID = sessionID; self.completion = completion
        }
        // An unselected secret is released with this coordinator after native swipe dismissal.
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            password = ""; completion(.failure(CancellationError()), "", sessionID)
        }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            let selectedPassword = password; password = ""
            completion(.success(urls), selectedPassword, sessionID)
        }
    }
}
