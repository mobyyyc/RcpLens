import XCTest
import LocalAuthentication
@testable import Sliplet

@MainActor final class ReceiptAppLockTests: XCTestCase {
    private var suite = ""
    private var defaults: UserDefaults!
    override func setUp() {
        super.setUp(); suite = "Sliplet.lock.tests." + UUID().uuidString
        defaults = UserDefaults(suiteName: suite)!
    }
    override func tearDown() {
        defaults.removePersistentDomain(forName: suite); defaults = nil; super.tearDown()
    }
    func testDisabledByDefaultAndFiveMinutePreference() {
        let lock = ReceiptAppLock(defaults: defaults)
        XCTAssertFalse(lock.enabled); XCTAssertTrue(lock.unlocked); XCTAssertEqual(lock.delay, .fiveMinutes)
    }
    func testColdStartRequiresAuthenticationEvenAfterPriorUnlock() async {
        defaults.set(true, forKey: "appLock.enabled")
        let lock = ReceiptAppLock(defaults: defaults, authenticate: { _ in true })
        lock.resume(); XCTAssertFalse(lock.unlocked)
        await lock.unlock(); XCTAssertTrue(lock.unlocked)
        XCTAssertFalse(ReceiptAppLock(defaults: defaults).unlocked)
    }
    func testGracePeriodEndsExactlyAtFiveMinutes() async {
        defaults.set(true, forKey: "appLock.enabled")
        var now = 100.0
        let lock = ReceiptAppLock(defaults: defaults, uptime: { now }, authenticate: { _ in true })
        await lock.unlock(); lock.suspend(); XCTAssertFalse(lock.unlocked)
        now = 399; lock.resume(); XCTAssertTrue(lock.unlocked)
        lock.suspend(); now = 699; lock.resume(); XCTAssertFalse(lock.unlocked)
    }
    func testImmediateAndDeviceProtectionRevokeGrace() async {
        defaults.set(true, forKey: "appLock.enabled")
        defaults.set(0, forKey: "appLock.delay")
        let lock = ReceiptAppLock(defaults: defaults, authenticate: { _ in true })
        await lock.unlock(); lock.suspend(); lock.resume(); XCTAssertFalse(lock.unlocked)
        await lock.unlock(); await lock.setDelay(.fiveMinutes)
        lock.revoke(); lock.resume(); XCTAssertFalse(lock.unlocked)
    }
    func testFailureAndCancellationNeverUnlockOrEnable() async {
        let cancelled = ReceiptAppLock(defaults: defaults, authenticate: { _ in
            throw NSError(domain: LAError.errorDomain, code: LAError.userCancel.rawValue)
        })
        await cancelled.setEnabled(true); XCTAssertFalse(cancelled.enabled); XCTAssertNil(cancelled.message)
        defaults.set(true, forKey: "appLock.enabled")
        let failed = ReceiptAppLock(defaults: defaults, authenticate: { _ in false })
        await failed.unlock(); XCTAssertFalse(failed.unlocked); XCTAssertNotNil(failed.message)
        failed.suspend(); failed.resume(); XCTAssertFalse(failed.unlocked)
        await failed.setEnabled(false); XCTAssertTrue(failed.enabled)
    }
    func testEnabledAndDelayPersistOnlyAfterAuthentication() async {
        var permitted = true
        let lock = ReceiptAppLock(defaults: defaults, authenticate: { _ in permitted })
        await lock.setEnabled(true); XCTAssertTrue(defaults.bool(forKey: "appLock.enabled"))
        await lock.setDelay(.oneMinute); XCTAssertEqual(lock.delay, .oneMinute)
        permitted = false
        await lock.setDelay(.fifteenMinutes); XCTAssertEqual(lock.delay, .oneMinute)
        await lock.setEnabled(false); XCTAssertTrue(lock.enabled)
        permitted = true
        await lock.setEnabled(false); XCTAssertFalse(defaults.bool(forKey: "appLock.enabled"))
    }
    func testBackgroundInvalidatesOutstandingSuccess() async {
        defaults.set(true, forKey: "appLock.enabled")
        var completion: CheckedContinuation<Bool, Never>?
        let lock = ReceiptAppLock(defaults: defaults, authenticate: { _ in
            await withCheckedContinuation { completion = $0 }
        })
        let task = Task { await lock.unlock() }
        while completion == nil { await Task.yield() }
        lock.suspend(); completion?.resume(returning: true); await task.value
        lock.resume(); XCTAssertFalse(lock.unlocked); XCTAssertFalse(lock.busy)
    }
    func testRepeatedBackgroundCannotExtendGrace() async {
        defaults.set(true, forKey: "appLock.enabled")
        var now = 100.0
        let lock = ReceiptAppLock(defaults: defaults, uptime: { now }, authenticate: { _ in true })
        await lock.unlock(); lock.suspend(); now = 390; lock.suspend()
        now = 400; lock.resume(); XCTAssertFalse(lock.unlocked)
    }
    func testTransientForegroundDoesNotRequestAgain() async {
        defaults.set(true, forKey: "appLock.enabled")
        let lock = ReceiptAppLock(defaults: defaults, authenticate: { _ in true })
        XCTAssertFalse(lock.resume())
        await lock.unlock()
        XCTAssertFalse(lock.resume()); XCTAssertTrue(lock.unlocked)
        lock.revoke(); XCTAssertTrue(lock.resume())
    }
    func testUnavailablePasscodeCannotEnableLock() async {
        let lock = ReceiptAppLock(defaults: defaults, authenticate: { _ in
            throw NSError(domain: LAError.errorDomain, code: LAError.passcodeNotSet.rawValue)
        })
        await lock.setEnabled(true)
        XCTAssertFalse(lock.enabled); XCTAssertTrue(lock.message?.contains("passcode") == true)
    }
}
