// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit

/// `-debugSnapshot <dir>`: every 2 s, draws each visible window offscreen into
/// `<dir>/<title>.png`. For UI checks while the screen is locked, when window-server captures
/// (scripts/screenshot.sh) fail. Debug only; never focuses anything.
enum DebugSnapshot {
    @MainActor static func startIfRequested() {
        guard let path = UserDefaults.standard.string(forKey: "debugSnapshot") else { return }
        let dir = URL(fileURLWithPath: path)
        Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
            MainActor.assumeIsolated { write(to: dir) }
        }
    }

    @MainActor static func write(to dir: URL) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for window in NSApp.windows where window.isVisible {
            // The frame view includes the title bar.
            guard let view = window.contentView?.superview ?? window.contentView,
                  view.bounds.width > 1, view.bounds.height > 1,
                  let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
            view.cacheDisplay(in: view.bounds, to: rep)
            let title = window.title.isEmpty ? String(describing: type(of: window)) : window.title
            let name = title.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: " ", with: "-") + ".png"
            try? rep.representation(using: .png, properties: [:])?.write(to: dir.appendingPathComponent(name))
        }
    }
}
