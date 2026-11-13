// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import SwiftUI
import VChainEngine
import VChainKit

/// The keychain detached from the menu bar (right-click › Detach from Menu Bar): the same `KeychainView` in an
/// ordinary transparent window (normal level, not floating) that the user moves by dragging the keyring or the
/// area inside it; the modules swing as it's moved. While detached, clicking vChain's menu bar item shows or hides
/// it (bringing it forward when another app's window covers it) instead of opening the drop-down, and right-click ›
/// Attach to Menu Bar puts it back under the item.
/// Detached or not, and where, survives a relaunch (`keychainDetached`, `keychainDetachedTopLeft`).
@MainActor
final class KeychainDock {
    static let shared = KeychainDock()

    private(set) var isDetached = UserDefaults.standard.bool(forKey: "keychainDetached")
    /// The menu bar drop-down's window (registered by `TransparentPanel`), where a detach starts from.
    weak var panelWindow: NSWindow?
    /// The detached keychain's swing: a change of the window's horizontal velocity (points/s).
    var swing: ((Double) -> Void)?

    private var window: NSWindow?
    var detachedWindow: NSWindow? { window }
    private var moveObserver: NSObjectProtocol?

    /// At launch: show the keychain where it was left. (While detached, `TransparentPanel` shuts the drop-down as it
    /// opens and calls `toggle()`: on macOS 26 a status item's clicks don't pass through the app's event monitors.)
    func start() {
        if isDetached { show() }
    }

    func detach() {
        guard !isDetached else { return }
        // Where the keychain hangs now: the detached one starts with its ring point there, a little lower so the
        // whole ring clears the menu bar.
        let layout = KeychainLayout(bands: EngineModel.shared.triggerBands)
        let geometry = Self.detachedGeometry
        var topLeft: CGPoint?
        if let panel = panelWindow, panel.isVisible {
            topLeft = CGPoint(x: panel.frame.minX + layout.ringPoint.x - geometry.ringPointX,
                              y: panel.frame.maxY - 12)
            MenuBarReadout.openPanel()  // the status item click toggles: this closes the drop-down
        }
        isDetached = true
        UserDefaults.standard.set(true, forKey: "keychainDetached")
        if let topLeft { UserDefaults.standard.set(NSStringFromPoint(topLeft), forKey: "keychainDetachedTopLeft") }
        show()
    }

    func attach() {
        guard isDetached else { return }
        window?.orderOut(nil)
        isDetached = false
        UserDefaults.standard.set(false, forKey: "keychainDetached")
        MenuBarReadout.openPanel()  // drops in under the menu bar item
    }

    /// The menu bar item while detached: hides the keychain when it's in front (vChain active, the keychain its key
    /// window), otherwise brings it forward. It's an ordinary window, so another app's windows often cover it
    /// (clicks on its transparent parts reach the app below): `isVisible` alone would hide a buried keychain.
    func toggle() {
        if let window, window.isVisible, Self.isFrontmost(window) { window.orderOut(nil) } else { show() }
    }

    func show() {
        let window = self.window ?? makeWindow()
        self.window = window
        window.setFrameTopLeftPoint(Self.onScreen(Self.storedTopLeft, size: window.frame.size))
        // A status item click doesn't let the app activate itself (macOS 14+), so order it in front regardless.
        NSApp.activate()
        window.orderFrontRegardless()
        window.makeKey()
    }

    /// No other app's ordinary window above it (on-screen order, front to back), whether or not vChain is active.
    private static func isFrontmost(_ window: NSWindow) -> Bool {
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        for info in list where info[kCGWindowLayer as String] as? Int == 0 {
            if info[kCGWindowNumber as String] as? Int == window.windowNumber { return true }
            let alpha = info[kCGWindowAlpha as String] as? Double ?? 1
            if alpha > 0, info[kCGWindowOwnerPID as String] as? pid_t != getpid() { return false }
        }
        return false
    }

    // MARK: Window

    /// The detached window's content: room for the most bands (so it never resizes; the ring point stays put when
    /// bands are added or ejected) plus the ring's top, which the menu bar hides while attached.
    static var detachedGeometry: (size: CGSize, ringPointX: CGFloat, topRoom: CGFloat) {
        let widest = KeychainLayout(bands: Int(VC_MAX_TRIGGER_BANDS))
        return (CGSize(width: widest.size.width, height: widest.size.height + widest.ringTopRoom), widest.ringPoint.x, widest.ringTopRoom)
    }

    private func makeWindow() -> NSWindow {
        let size = Self.detachedGeometry.size
        let window = DetachedKeychainWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless],
                                            backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .normal
        window.isReleasedWhenClosed = false
        window.isExcludedFromWindowsMenu = true
        window.title = "vChain"
        window.contentView = FirstMouseHostingView(rootView: KeychainView()
            .environment(EngineModel.shared)
            .environment(\.keychainDetached, true))
        moveObserver = NotificationCenter.default.addObserver(forName: NSWindow.didMoveNotification, object: window,
                                                              queue: .main) { note in
            guard let window = note.object as? NSWindow else { return }
            let topLeft = CGPoint(x: window.frame.minX, y: window.frame.maxY)
            UserDefaults.standard.set(NSStringFromPoint(topLeft), forKey: "keychainDetachedTopLeft")
        }
        return window
    }

    private static var storedTopLeft: CGPoint? {
        UserDefaults.standard.string(forKey: "keychainDetachedTopLeft").map(NSPointFromString)
    }

    /// `topLeft` if the ring would be on a screen there, else the top middle of the main screen.
    private static func onScreen(_ topLeft: CGPoint?, size: CGSize) -> CGPoint {
        let ring = detachedGeometry
        if let topLeft {
            let ringPoint = CGPoint(x: topLeft.x + ring.ringPointX, y: topLeft.y - ring.topRoom - 40)
            if NSScreen.screens.contains(where: { $0.visibleFrame.contains(ringPoint) }) { return topLeft }
        }
        let visible = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        return CGPoint(x: visible.midX - ring.ringPointX, y: visible.maxY - 20)
    }
}

/// Borderless, but able to become key and main like an ordinary window (clicking it brings it forward).
private final class DetachedKeychainWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

private struct KeychainDetachedKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// The `KeychainView` in the detached window (not the menu bar drop-down). Written out: no `@Entry` macro with
    /// the Command Line Tools.
    var keychainDetached: Bool {
        get { self[KeychainDetachedKey.self] }
        set { self[KeychainDetachedKey.self] = newValue }
    }
}

// MARK: - Ring grip

/// The detached keychain's drag area: the keyring and the disc inside it. Dragging moves the window (by the mouse's
/// screen position: the view moves with the window) and reports the window's horizontal velocity changes to
/// `KeychainDock.swing`, so the modules swing as they're carried. Right-clicks reach the keychain's menu.
struct RingGrip: View {
    var body: some View {
        Circle()
            .fill(Color.clickCatcher(true))
            .contentShape(Circle())
            .pointerStyle(.grabIdle)
            .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .global)
                .onChanged { _ in KeychainDock.shared.drag(ended: false) }
                .onEnded { _ in KeychainDock.shared.drag(ended: true) })
    }
}

extension KeychainDock {
    private struct Drag {
        var startMouse: CGPoint
        var startOrigin: CGPoint
        var lastMouse: CGPoint
        var lastTime: TimeInterval
        var velocity: Double = 0
    }
    private static var current: Drag?

    /// A step of a ring drag (`ended`: let go).
    func drag(ended: Bool) {
        guard let window = detachedWindow else { return }
        let mouse = NSEvent.mouseLocation
        let now = ProcessInfo.processInfo.systemUptime
        guard var d = Self.current else {
            Self.current = Drag(startMouse: mouse, startOrigin: window.frame.origin, lastMouse: mouse, lastTime: now)
            return
        }
        if ended {
            swing?(-d.velocity)  // put down: it stops, the modules swing on
            Self.current = nil
            return
        }
        window.setFrameOrigin(CGPoint(x: d.startOrigin.x + mouse.x - d.startMouse.x, y: d.startOrigin.y + mouse.y - d.startMouse.y))
        let dt = now - d.lastTime
        if dt > 0.001 {
            // Smoothed a little: single mouse events are jittery.
            let v = 0.5 * d.velocity + 0.5 * Double(mouse.x - d.lastMouse.x) / dt
            swing?(v - d.velocity)
            d.velocity = v
            d.lastMouse = mouse
            d.lastTime = now
        }
        Self.current = d
    }
}

/// Takes the first click even while vChain isn't active, so the ring can be dragged straight away.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
