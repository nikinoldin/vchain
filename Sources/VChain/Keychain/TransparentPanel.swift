// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import SwiftUI

/// Turns the `MenuBarExtra(.window)` panel hosting the keychain into a bare, transparent window: no
/// background, no material, no shadow, so only the ring and the modules hang below the menu bar. It
/// also pins the window's top edge to the menu bar's bottom edge, with the ring's hook right under the
/// status item (the ring's top is cut off by the window's top edge, as if it went behind the menu
/// bar). It reports each time the panel opens (so the keychain can swing in) and whether it can be
/// seen at all (closed, or the display asleep: the keychain stops animating; SwiftUI keeps a closed
/// MenuBarExtra's timeline running otherwise).
struct TransparentPanel: NSViewRepresentable {
    /// The ring's hook, in the keychain view's coordinates (x is what lines up with the status item).
    var hookX: CGFloat
    /// The menu bar drop-down (pinned under the status item); false in the detached keychain's own window.
    var pinned = true
    var onOpen: () -> Void
    var onShowing: (Bool) -> Void

    func makeNSView(context: Context) -> PanelAttachment {
        let view = PanelAttachment()
        view.pinned = pinned
        return view
    }

    func updateNSView(_ view: PanelAttachment, context: Context) {
        view.onOpen = onOpen
        view.onShowing = onShowing
        view.pinned = pinned
        if view.hookX != hookX {
            view.hookX = hookX
            view.anchor()
        }
    }
}

final class PanelAttachment: NSView {
    var hookX: CGFloat = 0
    var pinned = true
    var onOpen: (() -> Void)?
    var onShowing: ((Bool) -> Void)?

    private var observers: [NSObjectProtocol] = []
    private var isOpen = false
    private var isShowing = false
    private var isAnchoring = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        guard let window else { return }
        if pinned { KeychainDock.shared.panelWindow = window }
        clear(window)
        let center = NotificationCenter.default
        // An outside click fades the panel out: the occlusion change can arrive while it's still
        // visible, with nothing after the fade, so look again a moment later too.
        for name in [NSWindow.didChangeOcclusionStateNotification, NSWindow.didResignKeyNotification] {
            observers.append(center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.visibilityChanged()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { self?.visibilityChanged() }
                }
            })
        }
        for name in [NSWindow.didResizeNotification, NSWindow.didMoveNotification] {
            observers.append(center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.windowChangedFrame() }
            })
        }
        visibilityChanged()
    }

    private func visibilityChanged() {
        guard let window else { return }
        if window.isVisible != isOpen {
            isOpen = window.isVisible
            if isOpen, pinned, KeychainDock.shared.isDetached {
                // Detached: the menu bar item shows/hides the floating keychain instead. Shut the drop-down at once
                // (still invisible, see below; the status item's click toggles it) and hand over.
                window.alphaValue = 0
                DispatchQueue.main.async {
                    MenuBarReadout.openPanel()
                    KeychainDock.shared.toggle()
                }
                return
            }
            if isOpen {
                // The window is already on screen when this runs: keep it invisible until the glass is
                // hidden, it sits under the status item and the keychain has drawn its swing start,
                // or the first frames flash the glass, the old pose and the unpinned position.
                window.alphaValue = 0
                clear(window)
                anchor()
                onOpen?()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self, weak window] in
                    guard let self, let window else { return }
                    self.clear(window, last: true)
                    window.alphaValue = 1
                }
            } else {
                // Closed: stay invisible so the next open starts hidden too (see above).
                window.alphaValue = 0
            }
        }
        let showing = isOpen && window.occlusionState.contains(.visible)
        if showing != isShowing {
            isShowing = showing
            // Not inside a SwiftUI update (this can run while the view moves to its window).
            DispatchQueue.main.async { [weak self] in self?.onShowing?(showing) }
        }
    }

    /// Clear background, no shadow, and the panel's material made invisible. Up to macOS 15 that is an
    /// NSVisualEffectView (a background sibling, or a container of the hosting view: hiding a container
    /// would hide the keychain too, so its own drawing is switched off instead). On macOS 26 the panel
    /// is Liquid Glass, drawn by SwiftUI as layers inside the hosting view's SDFLayer: a CABackdropLayer
    /// (the glass itself) next to SDF portal layers that show the content. Only the backdrop is hidden
    /// (hiding the portals hides the keychain too). SwiftUI builds them lazily, so this runs again just
    /// after the panel shows (`last`: the pass after which neither turning up is worth a debug log).
    private func clear(_ window: NSWindow, last: Bool = false) {
        guard pinned else { return }  // the detached keychain's window is made transparent by KeychainDock
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        guard let root = window.contentView?.superview ?? window.contentView else { return }
        let backdrops = root.layer.map(Self.hideGlass(in:)) ?? 0
        let effects = root.descendants(of: NSVisualEffectView.self)
        #if DEBUG
        if last, backdrops == 0, effects.isEmpty {
            Self.logOnce("TransparentPanel: no CABackdropLayer or NSVisualEffectView found; the panel's material may show")
        }
        #endif
        for effect in effects {
            if isDescendant(of: effect) {
                effect.state = .inactive
                effect.material = .fullScreenUI
                effect.blendingMode = .withinWindow
                effect.wantsLayer = true
                effect.layer?.backgroundColor = .clear
                effect.layer?.contents = nil
                effect.maskImage = nil
                for sub in effect.subviews where !isDescendant(of: sub) { sub.isHidden = true }
                effect.layer?.sublayers?.forEach { layer in
                    if !(effect.subviews.contains { $0.layer === layer }) { layer.isHidden = true }
                }
            } else {
                effect.isHidden = true
            }
        }
        // The panel rounds its corners with a layer mask; nothing should clip the keychain but the window.
        var view: NSView? = superview
        while let v = view {
            v.layer?.cornerRadius = 0
            v.layer?.backgroundColor = .clear
            view = v.superview
        }
    }

    /// Hides every CABackdropLayer (macOS 26's glass) in the panel. A private class, so matched by name.
    /// Returns how many it found.
    @discardableResult
    private static func hideGlass(in layer: CALayer) -> Int {
        var found = 0
        for sub in layer.sublayers ?? [] {
            if String(describing: type(of: sub)) == "CABackdropLayer" {
                sub.isHidden = true
                found += 1
            } else {
                found += hideGlass(in: sub)
            }
        }
        return found
    }

    #if DEBUG
    private static var logged: Set<String> = []

    /// Developer builds only: a private-API match (class names) stopped working. Each message once.
    private static func logOnce(_ message: String) {
        guard logged.insert(message).inserted else { return }
        NSLog("%@", message)
    }
    #endif

    /// SwiftUI resizes the panel when the content's size changes (trigger bands) and may move it: put it back.
    private func windowChangedFrame() {
        guard let window else { return }
        anchor()
        clear(window)
    }

    /// Top edge on the menu bar's bottom edge; the hook under the middle of the status item.
    func anchor() {
        guard pinned, !isAnchoring, let window else { return }
        guard let item = statusItemFrame(near: window) else {
            #if DEBUG
            Self.logOnce("TransparentPanel: no StatusBarWindow found; the keychain isn't pinned under the status item")
            #endif
            return
        }
        let frame = window.frame
        let origin = CGPoint(x: (item.midX - hookX).rounded(), y: item.minY - frame.height)
        guard abs(frame.origin.x - origin.x) > 0.5 || abs(frame.origin.y - origin.y) > 0.5 else { return }
        isAnchoring = true
        window.setFrameOrigin(origin)
        isAnchoring = false
    }

    /// The status item's frame on screen: the status bar window closest to where the panel opened
    /// (one per display when each display has its own menu bar).
    private func statusItemFrame(near window: NSWindow) -> CGRect? {
        let items = NSApp.windows
            .filter { String(describing: type(of: $0)).contains("StatusBarWindow") }
            .map(\.frame)
        let x = window.frame.midX, y = window.frame.maxY
        return items.min { hypot($0.midX - x, $0.minY - y) < hypot($1.midX - x, $1.minY - y) }
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

private extension NSView {
    func descendants<T: NSView>(of type: T.Type) -> [T] {
        subviews.flatMap { sub in ((sub as? T).map { [$0] } ?? []) + sub.descendants(of: type) }
    }
}
