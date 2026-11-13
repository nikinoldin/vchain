// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import VChainEngine
import VChainKit
import Observation
import SwiftUI

/// The menu bar item: the LCD's mascot (the dancer) + BPM, drawn as a template image so the width is fixed (no
/// jumping as digits change) and it tints like any other menu bar item. The mascot moves with the one on the tag's
/// LCD (same `BPMTagState`): beat A / beat B alternate on every beat of the Link grid, the move on the 1 once the bar
/// is locked, still while the tempo settles (with a "?") and with Reduce Motion, dancing on through breakdowns (holding), meditating (seated) while
/// BPM detection is off. A warning triangle replaces it while the input needs attention. Each pose is the mascot's
/// own hand-drawn menu bar template (`Mascot.menuArt`), not the LCD segments scaled down. Polled at 10 Hz
/// (independent of any open window) for state and text, plus a one-shot update exactly on each beat change
/// (`BeatTicker`); the image is only redrawn when what it shows changes (about once per beat).
@MainActor @Observable
final class MenuBarReadout {
    static let shared = MenuBarReadout()

    private(set) var image = NSImage()
    private(set) var spoken = "vChain"

    @ObservationIgnored private var key = ""
    @ObservationIgnored private let beat = BeatTicker()

    func start() {
        beat.onFire = { MenuBarReadout.shared.update() }
        update()
        // State and text changes (tempo, settling, input) need no beat precision: 10 Hz. Beat changes get their
        // own one-shot redraw exactly on the beat (`beat`, re-armed in every update).
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            MainActor.assumeIsolated { MenuBarReadout.shared.update() }
        }
    }

    /// Opens the MenuBarExtra panel by clicking its status item (SwiftUI has no API for it).
    static func openPanel() {
        for window in NSApp.windows where String(describing: type(of: window)).contains("StatusBarWindow") {
            if let button = window.contentView?.firstSubview(of: NSStatusBarButton.self) {
                button.performClick(nil)
                return
            }
        }
    }

    enum Mark: Equatable { case mascot(MascotPose, settling: Bool), warning }

    private func update() {
        let model = EngineModel.shared
        let s = model.live()
        let problem = InputProblem.current(model)?.isWarning ?? false
        // The tag's own state, from the same inputs the keychain gives it, so the mascot moves with the tag's.
        let tag = BPMTagState.make(BPMInputs(
            enabled: s.bpmEnabled, bpm: Double(s.bpm), confidence: Double(s.confidence), hasTempo: s.hasTempo,
            beatPhase: s.beatPhase, linkPeers: s.linkPeers, inputProblem: problem, time: Double(s.now) / 1_000_000,
            barLocked: s.barLocked, beatState: BeatState(rawValue: Int(s.beatState))))
        let still = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let mark: Mark = problem ? .warning
            : tag.mascot == .hidden ? .mascot(.resting, settling: false)
            : .mascot(still && tag.mascot != .resting ? .still : tag.mascot, settling: tag.mode == .settling)
        let text = !s.bpmEnabled ? "Off" : (s.hasTempo ? String(format: "%.1f", s.bpm) : "–––")

        // Dancing: redraw exactly on the next beat change.
        if tag.mode == .locked && !problem && !still { beat.arm(s) } else { beat.cancel() }
        let newKey = "\(mark)" + text
        guard newKey != key else { return }
        key = newKey
        image = Self.draw(mark: mark, text: text)
        spoken = problem ? "vChain, input needs attention"
            : !s.bpmEnabled ? "vChain, BPM detection off"
            : s.hasTempo ? String(format: "vChain, %.1f BPM", s.bpm) : "vChain, listening"
    }

    private static let font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium)
    /// Wide enough for "188.8", so the item never changes width.
    private static let textWidth = ceil(("188.8" as NSString).size(withAttributes: [.font: font]).width)

    static func draw(mark: Mark, text: String) -> NSImage {
        let height: CGFloat = 18, gap: CGFloat = 4, markWidth = Mascot.current.menuWidth
        let size = NSSize(width: markWidth + gap + textWidth, height: height)
        // Flipped: the mascot's menu art is drawn y down, in points.
        let image = NSImage(size: size, flipped: true) { _ in
            NSColor.black.set()
            switch mark {
            case .warning:
                let markRect = NSRect(x: (markWidth - 14) / 2, y: (height - 14) / 2, width: 14, height: 14)
                let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
                NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: nil)?
                    .withSymbolConfiguration(config)?
                    .draw(in: markRect.insetBy(dx: 0, dy: 0.5), from: .zero, operation: .sourceOver, fraction: 1,
                          respectFlipped: true, hints: nil)
            case .mascot(let pose, let settling):
                if let cg = NSGraphicsContext.current?.cgContext {
                    cg.addPath(Mascot.current.menuArt(pose, settling: settling).cgPath)
                    cg.setFillColor(NSColor.black.cgColor)
                    cg.fillPath()
                }
            }
            let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]
            let textSize = (text as NSString).size(withAttributes: attributes)
            // Right-aligned so the decimal point stays put between 99.5 and 128.0.
            (text as NSString).draw(at: NSPoint(x: size.width - textSize.width,
                                                y: (height - textSize.height) / 2),
                                    withAttributes: attributes)
            return true
        }
        image.isTemplate = true
        return image
    }
}

struct MenuBarLabel: View {
    private let readout = MenuBarReadout.shared

    var body: some View {
        Image(nsImage: readout.image)
            .accessibilityLabel(Text(verbatim: readout.spoken))
            .withWindowOpener { DebugLaunch.openRequestedWindow($0) }
    }
}

private extension NSView {
    func firstSubview<T: NSView>(of type: T.Type) -> T? {
        if let match = self as? T { return match }
        for view in subviews { if let match = view.firstSubview(of: type) { return match } }
        return nil
    }
}

// MARK: - Offscreen preview

extension MenuBarReadout {
    /// `-debugRenderMenuBar <png>`: every readout state on a light and a dark menu bar, at real size (2× pixels)
    /// and zoomed 3×, written offscreen.
    static func renderPreview(to path: String) {
        let states: [(String, Mark, String)] = [
            ("still", .mascot(.still, settling: false), "128.0"), ("beat A", .mascot(.beatA, settling: false), "128.0"),
            ("beat B", .mascot(.beatB, settling: false), "128.0"), ("the 1", .mascot(.theOne, settling: false), "128.0"),
            ("settling", .mascot(.still, settling: true), "127.5"), ("no input", .warning, "128.0"),
            ("off (meditating)", .mascot(.resting, settling: false), "Off"),
        ]
        let bars: [(String, NSColor, NSColor)] = [
            ("LIGHT MENU BAR", NSColor(white: 0.96, alpha: 1), NSColor(white: 0, alpha: 0.85)),
            ("DARK MENU BAR", NSColor(white: 0.16, alpha: 1), NSColor(white: 1, alpha: 0.9)),
        ]
        let itemW = draw(mark: .warning, text: "Off").size.width
        let colW = max(140, itemW * 3 + 24), rowH: CGFloat = 26 + 24 + 18 * 3 + 30
        let size = NSSize(width: 20 + colW * CGFloat(states.count), height: rowH * CGFloat(bars.count) + 10)
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2),
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        func tinted(_ image: NSImage, _ color: NSColor) -> NSImage {
            NSImage(size: image.size, flipped: false) { r in
                image.draw(in: r); color.set(); r.fill(using: .sourceAtop); return true
            }
        }
        let small: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 10, weight: .semibold)]
        for (b, (title, bg, ink)) in bars.enumerated() {
            let top = size.height - CGFloat(b) * rowH - 5
            bg.setFill(); NSRect(x: 0, y: top - rowH, width: size.width, height: rowH).fill()
            var label = small; label[.foregroundColor] = ink
            (title as NSString).draw(at: NSPoint(x: 12, y: top - 16), withAttributes: label)
            for (i, (name, mark, text)) in states.enumerated() {
                let x = 12 + colW * CGFloat(i)
                let image = tinted(draw(mark: mark, text: text), ink)
                (name as NSString).draw(at: NSPoint(x: x, y: top - 32), withAttributes: label)
                image.draw(in: NSRect(x: x, y: top - 56, width: image.size.width, height: image.size.height))
                NSGraphicsContext.current?.imageInterpolation = .none
                image.draw(in: NSRect(x: x, y: top - 60 - 18 * 3, width: image.size.width * 3, height: image.size.height * 3))
            }
        }
        NSGraphicsContext.restoreGraphicsState()
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }
}
