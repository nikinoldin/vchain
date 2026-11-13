// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import Sparkle

/// App updates through Sparkle. The feed (SUFeedURL in Info.plist) is bitmapbabe.com/vchain/appcast.xml, which the
/// website redirects to the appcast attached to the latest GitHub release (scripts/release.sh writes it). Sparkle
/// checks once a day (SUScheduledCheckInterval) and only installs updates signed with the EdDSA key whose public
/// half is SUPublicEDKey. Off for developer copies (run-dev.sh, offscreen renders).
@MainActor
enum Updates {
    private static var controller: SPUStandardUpdaterController?

    static func start() {
        guard Bundle.main.bundleIdentifier == "com.bitmapbabe.vchain", DebugLaunch.testAudioFile == nil,
              Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil else { return }
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    }

    static var available: Bool { controller != nil }

    /// "Check for Updates…": activates the app first so Sparkle's window comes to the front (the keychain is a
    /// menu bar panel).
    static func check() {
        NSApp.activate()
        controller?.checkForUpdates(nil)
    }
}
