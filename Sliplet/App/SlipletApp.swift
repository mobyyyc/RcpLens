import SwiftUI

@main
struct SlipletApp: App {
    @UIApplicationDelegateAdaptor(ReceiptPrivacyDelegate.self) private var privacyDelegate
    var body: some Scene {
        WindowGroup { ReceiptSessionView() }
    }
}

struct ReceiptSessionView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var systemTypeSize
    @State private var workspace: ReceiptWorkspace = {
        #if DEBUG
        if SyntheticNativePreview.enabled {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            return ReceiptWorkspace(directory: base.appendingPathComponent("T05SyntheticPreviewStore"),
                keyProvider: KeychainReceiptStoreKey(service: "com.mobyyyc.RcpLens.T05-synthetic-preview", account: "v1"))
        }
        if WorkflowTestInput.enabled {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            return ReceiptWorkspace(directory: base.appendingPathComponent("T05WorkflowTestStore"),
                keyProvider: KeychainReceiptStoreKey(service: "com.mobyyyc.RcpLens.T05-local-test", account: "v1"))
        }
        #endif
        return ReceiptWorkspace()
    }()
    @State private var appLock: ReceiptAppLock = {
        #if DEBUG
        if SyntheticNativePreview.enabled || WorkflowTestInput.enabled { return ReceiptAppLockFixture.make() }
        #endif
        return ReceiptAppLock()
    }()
    var body: some View {
        Group {
            if appLock.unlocked { ReceiptHome(workspace: workspace).id(workspace.sessionID) }
            else { ReceiptLockScreen(lock: appLock) }
        }.environment(appLock)
            #if DEBUG
            .dynamicTypeSize(SyntheticNativePreview.enabled && ProcessInfo.processInfo.arguments.contains("--t05-large-text") ? .accessibility5 : systemTypeSize)
            .preferredColorScheme(SyntheticNativePreview.enabled ? (ProcessInfo.processInfo.arguments.contains("--t05-light") ? .light : .dark) : nil)
            #endif
            .task {
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("--synthetic-diagnostics") || ProcessInfo.processInfo.arguments.contains(where: { $0.hasPrefix("--synthetic-storage-") }) {
                    return
                }
                #endif
                appLock.resume()
                if appLock.unlocked { activateWorkspace() }
                else { await appLock.unlock() }
                #if DEBUG
                await SyntheticNativePreview.run(workspace)
                await SyntheticNativePreview.addRequestedDemoReceipts(workspace)
                #endif
            }
            .onChange(of: scenePhase) { _, phase in
                switch phase {
                case .background: appLock.suspend(); workspace.suspend()
                case .active:
                    ReceiptPrivacyCover.hide()
                    let authenticateReturn = appLock.resume()
                    if appLock.unlocked { activateWorkspace() }
                    else if authenticateReturn { Task { await appLock.unlock() } }
                    // Transient Face ID inactivity never starts another prompt.
                case .inactive:
                    ReceiptPrivacyCover.show()
                    workspace.privacyCovered = true // Unsaved data is retained through transient picker inactivity.
                @unknown default: workspace.suspend()
                }
            }
            .onChange(of: appLock.unlocked) { _, unlocked in
                if unlocked && scenePhase == .active { activateWorkspace() }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.protectedDataWillBecomeUnavailableNotification)) { _ in appLock.revoke(); workspace.suspend() }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.protectedDataDidBecomeAvailableNotification)) { _ in
                if scenePhase == .active {
                    ReceiptPrivacyCover.hide()
                    let authenticateReturn = appLock.resume()
                    if appLock.unlocked { activateWorkspace() }
                    else if authenticateReturn { Task { await appLock.unlock() } }
                }
            }
            #if DEBUG
            .sheet(isPresented: .constant(ProcessInfo.processInfo.arguments.contains("--synthetic-diagnostics"))) {
                NavigationStack { DiagnosticsView(autoRun: true) }
            }
            .onChange(of: workspace.flow) { _, _ in WorkflowTestInput.recordState(workspace, event: "flow") }
            .onChange(of: workspace.availability) { _, _ in WorkflowTestInput.recordState(workspace, event: "availability") }
            .task { await SyntheticStorageDiagnostics.runIfRequested() }
            #endif
    }
    private func activateWorkspace() {
        guard appLock.unlocked else { return }
        workspace.activate(protectedDataAvailable: UIApplication.shared.isProtectedDataAvailable)
    }

}
