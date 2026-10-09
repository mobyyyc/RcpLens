import SwiftUI
import LocalAuthentication

/// Security preferences are available before the encrypted receipt store is opened.
enum ReceiptLockDelay: Int, CaseIterable, Identifiable {
    case immediately = 0, oneMinute = 60, fiveMinutes = 300, fifteenMinutes = 900
    var id: Int { rawValue }
    var title: String {
        switch self {
        case .immediately: "Immediately"
        case .oneMinute: "After 1 minute"
        case .fiveMinutes: "After 5 minutes"
        case .fifteenMinutes: "After 15 minutes"
        }
    }
}

@MainActor @Observable final class ReceiptAppLock {
    private let defaults: UserDefaults
    private let uptime: () -> TimeInterval
    private let authenticate: ((String) async throws -> Bool)?
    private var context: LAContext?
    private var attempt = UUID()
    private var backgroundTime: TimeInterval?
    private var suspended = false
    private(set) var enabled: Bool
    private(set) var delay: ReceiptLockDelay
    private(set) var unlocked: Bool
    private(set) var busy = false
    private(set) var message: String?

    init(defaults: UserDefaults = .standard,
         uptime: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         authenticate: ((String) async throws -> Bool)? = nil) {
        self.defaults = defaults; self.uptime = uptime; self.authenticate = authenticate
        let storedEnabled = defaults.bool(forKey: "appLock.enabled")
        enabled = storedEnabled
        delay = ReceiptLockDelay(rawValue: defaults.object(forKey: "appLock.delay") as? Int ?? 300) ?? .fiveMinutes
        unlocked = !storedEnabled
    }
    /// No authentication reuse across a process restart. Grace uses a monotonic clock.
    @discardableResult func resume() -> Bool {
        let returning = suspended
        suspended = false
        if !enabled { unlocked = true }
        else if let backgroundTime, delay != .immediately,
                uptime() >= backgroundTime, uptime() - backgroundTime < Double(delay.rawValue) {
            unlocked = true
        }
        backgroundTime = nil
        return returning && enabled && !unlocked
    }
    func suspend() {
        // A cancelled or failed authentication must never start a grace period.
        if backgroundTime == nil && enabled && unlocked { backgroundTime = uptime() }
        suspended = true; unlocked = !enabled
        cancelAttempt()
    }
    func revoke() {
        backgroundTime = nil; suspended = true; unlocked = !enabled
        cancelAttempt()
    }
    private func cancelAttempt() {
        attempt = UUID(); context?.invalidate(); context = nil; busy = false
    }
    func unlock() async {
        guard enabled, !unlocked else { return }
        if await verify(reason: "Unlock your receipts in Sliplet.") { unlocked = true }
    }
    func setEnabled(_ value: Bool) async {
        guard enabled != value else { return }
        // Both enabling and removing the lock require device-owner authentication.
        guard await verify(reason: value ? "Enable Face ID protection for Sliplet." : "Turn off Sliplet’s app lock.") else { return }
        enabled = value; unlocked = true; backgroundTime = nil
        defaults.set(value, forKey: "appLock.enabled")
    }
    func setDelay(_ value: ReceiptLockDelay) async {
        guard delay != value else { return }
        // Lengthening the grace period weakens protection; verify that change.
        if enabled && value.rawValue > delay.rawValue {
            guard await verify(reason: "Change when Sliplet requires authentication.") else { return }
        }
        guard !suspended else { return }
        delay = value; defaults.set(value.rawValue, forKey: "appLock.delay")
    }
    private func verify(reason: String) async -> Bool {
        guard !busy, !suspended else { return false }
        busy = true; message = nil
        let token = UUID(); attempt = token
        defer { if attempt == token { busy = false; context = nil } }
        do {
            let success: Bool
            if let authenticate { success = try await authenticate(reason) }
            else {
                let request = LAContext(); context = request
                var error: NSError?
                guard request.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
                    throw error ?? NSError(domain: LAError.errorDomain, code: LAError.passcodeNotSet.rawValue)
                }
                success = try await request.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
            }
            guard attempt == token, !suspended else { return false }
            if !success { message = "Authentication wasn’t completed. Try again." }
            return success
        } catch {
            guard attempt == token, !suspended else { return false }
            let code = (error as NSError).code
            if [LAError.userCancel.rawValue, LAError.systemCancel.rawValue, LAError.appCancel.rawValue].contains(code) {
                message = nil
            } else if code == LAError.passcodeNotSet.rawValue {
                message = "Set an iPhone passcode in Settings to use app lock."
            } else { message = "Unable to authenticate. Try again using Face ID or your iPhone passcode." }
            return false
        }
    }
}

struct ReceiptLockScreen: View {
    @Bindable var lock: ReceiptAppLock
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.shield").font(.system(size: 48, weight: .light)).foregroundStyle(.secondary)
            Text("Sliplet is locked").font(.title2.weight(.semibold))
            Text("Unlock to view your receipts.").font(.subheadline).foregroundStyle(.secondary)
            if let message = lock.message { Text(message).font(.footnote).multilineTextAlignment(.center) }
            Button { Task { await lock.unlock() } } label: {
                Label(lock.busy ? "Unlocking…" : "Unlock", systemImage: "faceid")
            }.buttonStyle(ReceiptProminentStyle()).disabled(lock.busy).accessibilityIdentifier("unlockApp")
        }.padding(30).frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(uiColor: .systemGroupedBackground)).tint(.primary)
    }
}

struct ReceiptAppLockSettings: View {
    @Environment(ReceiptAppLock.self) private var lock
    var body: some View {
        Section {
            Toggle("Require Face ID", isOn: Binding(get: { lock.enabled }, set: { value in
                Task { await lock.setEnabled(value) }
            })).tint(.green).accessibilityIdentifier("appLockSetting")
            if lock.enabled {
                Picker("Lock on return", selection: Binding(get: { lock.delay }, set: { value in
                    Task { await lock.setDelay(value) }
                })) { ForEach(ReceiptLockDelay.allCases) { Text($0.title).tag($0) } }
                    .accessibilityIdentifier("appLockDelay")
            }
            if let message = lock.message { Text(message).font(.footnote) }
        } header: { Text("Privacy") } footer: {
            Text("Authenticate when opening Sliplet. On return, use the delay you choose. Your iPhone passcode is available as a fallback.")
        }.disabled(lock.busy)
    }
}
