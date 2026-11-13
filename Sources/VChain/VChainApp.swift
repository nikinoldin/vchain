// SPDX-License-Identifier: GPL-3.0-or-later
import VChainEngine
import SwiftUI

/// A menu bar app that keeps its Dock icon (so a pinned vChain shows it's running). The menu bar shows
/// the dancer and BPM; clicking it, or the Dock icon, opens the keychain (BPM tag, MIDI strip and
/// Energy module on a ring). Settings opens as a window.
@main
struct VChainApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate
    @ViewState private var model = EngineModel.shared

    var body: some Scene {
        MenuBarExtra {
            KeychainView()
                .environment(model)
        } label: {
            MenuBarLabel()
        }
        .menuBarExtraStyle(.window)
        .commands {
            CommandGroup(replacing: .help) {}  // no help book: no Help item that leads nowhere
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") { Updates.check() }.disabled(!Updates.available)
            }
        }

        // Developer gallery, only via `-debugOpen modules`: never at launch, not in the Window menu.
        Window("Modules", id: WindowID.modules) {
            ModuleGallery()
        }
        .defaultSize(width: 1400, height: 900)
        .defaultLaunchBehavior(.suppressed)
        .commandsRemoved()

        Settings {
            SettingsView()
                .environment(model)
        }
    }
}

enum WindowID {
    static let modules = "modules"
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if DebugLaunch.renderIfRequested() { return }
        DebugLaunch.applyAppearance()
        EngineModel.shared.start()
        MenuBarReadout.shared.start()
        KeychainDock.shared.start()
        Updates.start()
        DebugSnapshot.startIfRequested()
    }

    /// Clicking the Dock icon opens the keychain (unless a window is open: then macOS just
    /// brings it forward); a detached keychain is shown wherever it was left.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if KeychainDock.shared.isDetached { KeychainDock.shared.show() } else if !hasVisibleWindows { MenuBarReadout.openPanel() }
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Stops capture and removes the virtual MIDI port and Link session cleanly.
        EngineModel.shared.shutdown()
    }
}
