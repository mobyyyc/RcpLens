#if DEBUG
import Foundation
import LocalAuthentication

/// Only explicit fictional-store launches can inject authentication outcomes.
@MainActor enum ReceiptAppLockFixture {
    static func make() -> ReceiptAppLock {
        let suite = "com.mobyyyc.RcpLens.synthetic-app-lock"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        guard let mode = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--app-lock-fixture=") })?.split(separator: "=").last else {
            return ReceiptAppLock(defaults: defaults)
        }
        defaults.set(mode != "settings", forKey: "appLock.enabled")
        var calls = 0
        return ReceiptAppLock(defaults: defaults, authenticate: { _ in
            calls += 1
            if mode == "cancel" { throw NSError(domain: LAError.errorDomain, code: LAError.userCancel.rawValue) }
            return (mode == "settings" && calls == 1) || (mode == "retry" && calls > 1)
        })
    }
}
#endif
