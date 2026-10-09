# Receipt status and app lock

Completed receipts use an accessible checkmark in the paper’s upper-right corner, in previews and both detail entry paths. Routine Reviewed and Saved on this device labels are removed; drafts still say Needs review. Completion still requires the existing reviewed-fields and matching-total checks.

In Settings → Privacy, enable Require Face ID. The default return delay is After 5 minutes; Immediately, After 1 minute and After 15 minutes are also available. Every cold launch requires authentication. Background time uses system uptime; a return before the selected interval may reopen without prompting. Locking the phone revokes the grace period. Cancellation leaves the lock screen visible, with an explicit Unlock button to retry.

The app uses Apple’s `LocalAuthentication` device-owner policy, allowing Face ID or the iPhone passcode. Apple Intelligence is unnecessary. Enabling or disabling protection requires authentication; increasing the delay also requires authentication. The receipt database is opened only after the root gate allows access, and the existing encrypted storage and background privacy cover remain in place. This is an app access gate, not a change to the database’s Keychain encryption policy. Security preferences are stored separately so they can be read before opening the receipt store.

[Apple device-owner authentication](https://developer.apple.com/documentation/localauthentication/lapolicy/deviceownerauthentication)

## Test on iPhone

Build and Run the Sliplet scheme on your connected phone. Enable Require Face ID in the app’s Settings and approve the iOS Face ID permission. Check successful unlock and cancellation followed by Unlock. For a quick return test choose Immediately, leave the app, then reopen. Also test After 5 minutes before and after the interval, and the passcode fallback. Biometric behavior on the physical phone needs this check; automated tests use injected outcomes in a separate fictional store.

## Simulator test-runner crash

The reported process was `SlipletUITests-Runner`, not Sliplet. Local crash reports showed DYLD aborts because `@rpath/XCTest.framework/XCTest` was unavailable on a later launch outside Xcode’s test environment. The installed Apple test runner declared continuous background execution; reports recurred at five-minute intervals. Removing only `com.mobyyyc.RcpLensUITests.xctrunner` removes the disposable runner without removing Sliplet or its receipt store. Crash reporting remains enabled.

Use `scripts/test-ui.sh SIMULATOR-UUID` plus normal xcodebuild test options for command-line UI runs. Its exit trap removes this exact runner after success or failure. After tests directly through Xcode, the same cleanup can be performed with:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun simctl uninstall SIMULATOR-UUID com.mobyyyc.RcpLensUITests.xctrunner
```

This removes the temporary testing app; Xcode installs it again for the next UI test run. Normal Run (Command-R) launches Sliplet and does not need this runner.
