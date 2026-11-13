// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import SwiftUI

/// Opens the app's windows from the menu bar keychain. The keychain doesn't activate the app, so it
/// activates itself first, otherwise the window would open behind Resolume.
@MainActor
struct WindowOpener {
    let openWindow: OpenWindowAction
    let settingsAction: OpenSettingsAction

    func openSettings() {
        NSApp.activate()
        settingsAction()
    }

    /// Settings on one tab ("general", "bpm", "midi", "energy"): SettingsView keeps the tab in this default.
    func settings(pane: String) {
        UserDefaults.standard.set(pane, forKey: "settingsPane")
        openSettings()
    }
}

extension View {
    /// The window opener from this view's environment.
    func withWindowOpener(_ body: @escaping (WindowOpener) -> Void) -> some View {
        modifier(WindowOpenerReader(body: body))
    }
}

private struct WindowOpenerReader: ViewModifier {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    var body: (WindowOpener) -> Void

    func body(content: Content) -> some View {
        content.onAppear { body(WindowOpener(openWindow: openWindow, settingsAction: openSettings)) }
    }
}
