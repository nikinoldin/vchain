// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import SwiftUI

/// The app's commands (About, Check for Updates, Settings, Restart Input, Detach from / Attach to Menu Bar, Quit) plus
/// the input problem and its fixes when there is one.
struct KeychainMenu: View {
    @Environment(EngineModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @Environment(\.keychainDetached) private var detached

    var body: some View {
        let open = WindowOpener(openWindow: openWindow, settingsAction: openSettings)
        if let problem = InputProblem.current(model), problem.isWarning {
            Text(problem.message)
            if let url = problem.settingsURL {
                Button("Open Privacy Settings…") { NSWorkspace.shared.open(url) }
            }
            if problem.settingsURL != nil || problem.canRetry {
                Button("Try Again") { model.input.retry() }
            }
            Divider()
        }
        Button("About vChain") {
            // The standard About panel: version and copyright from Info.plist, credits from Resources/Credits.html.
            NSApp.activate()
            NSApp.orderFrontStandardAboutPanel(nil)
        }
        if Updates.available {
            Button("Check for Updates…") { Updates.check() }
        }
        Button("Settings…") { open.openSettings() }
        Button("Restart Input") { model.input.retry() }
        Divider()
        if detached {
            Button("Attach to Menu Bar") { KeychainDock.shared.attach() }
        } else {
            Button("Detach from Menu Bar") { KeychainDock.shared.detach() }
        }
        Divider()
        Button("Quit vChain") { NSApp.terminate(nil) }
    }
}
