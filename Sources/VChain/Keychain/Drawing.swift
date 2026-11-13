// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI

// Canvas drawing helpers for the keychain's parts and modules: the part canvas, colours, CSS-style shadow and gradient
// recipes, baseline-placed text and hole cutting.

/// A Canvas drawing in design units: `size` is the part's body (its layout frame), `bleed` extra room
/// around it for shadows and overhanging bits, which spill outside the frame without taking layout space.
struct PartCanvas: View {
    var size: CGSize
    var bleed: EdgeInsets
    var scale: CGFloat
    var draw: (inout GraphicsContext) -> Void

    init(size: CGSize, bleed: CGFloat, scale: CGFloat, draw: @escaping (inout GraphicsContext) -> Void) {
        self.init(size: size, bleed: EdgeInsets(top: bleed, leading: bleed, bottom: bleed, trailing: bleed), scale: scale, draw: draw)
    }

    init(size: CGSize, bleed: EdgeInsets, scale: CGFloat, draw: @escaping (inout GraphicsContext) -> Void) {
        self.size = size
        self.bleed = bleed
        self.scale = scale
        self.draw = draw
    }

    var body: some View {
        let width = (size.width + bleed.leading + bleed.trailing) * scale
        let height = (size.height + bleed.top + bleed.bottom) * scale
        let pad = canvasEdgePad
        Canvas { ctx, _ in
            // Drawn edge-padded: a fill that reached the canvas's own edge would step when the module swings.
            ctx.translateBy(x: pad, y: pad)
            ctx.clip(to: Path(CGRect(x: 0, y: 0, width: width, height: height)))
            ctx.scaleBy(x: scale, y: scale)
            ctx.translateBy(x: bleed.leading, y: bleed.top)
            draw(&ctx)
        }
        .frame(width: width + 2 * pad, height: height + 2 * pad)
        .padding(EdgeInsets(top: -bleed.top * scale - pad, leading: -bleed.leading * scale - pad,
                            bottom: -bleed.bottom * scale - pad, trailing: -bleed.trailing * scale - pad))
        // A drawing never catches clicks: its frame (with the bleed: shadows, transparent margins) is far larger than
        // what it draws. Modules get theirs from `ModuleOutline`, controls from `moduleControl`'s content shape.
        .allowsHitTesting(false)
    }
}

/// Transparent margin (points) round every keychain canvas. A swinging module turns each of its canvases as one flat
/// layer, and Core Animation doesn't antialias a layer's own edge: a fill reaching the canvas's edge (the LCD glass,
/// a sticker wrapped over a cap's edge) came out stepped. With the margin, those edges are clip edges inside the
/// drawing, which Core Graphics smooths.
let canvasEdgePad: CGFloat = 2

/// `#rrggbb` as a Color.
func hex(_ rgb: UInt32, opacity: Double = 1) -> Color {
    Color(.sRGB, red: Double((rgb >> 16) & 0xff) / 255, green: Double((rgb >> 8) & 0xff) / 255,
          blue: Double(rgb & 0xff) / 255, opacity: opacity)
}

extension GraphicsContext {
    /// CSS `inset <dx> <dy> <blur> <color>` inside `shape` (blur 0 = a hard edge line).
    func insetShadow(in shape: Path, dx: CGFloat = 0, dy: CGFloat, blur: CGFloat = 0, color: Color) {
        var inner = self
        inner.clip(to: shape)
        if blur > 0 { inner.addFilter(.blur(radius: blur / 2)) }
        var ring = Path(shape.boundingRect.insetBy(dx: -abs(dx) - abs(dy) - blur * 4 - 2, dy: -abs(dx) - abs(dy) - blur * 4 - 2))
        ring.addPath(shape.offsetBy(dx: dx, dy: dy))
        inner.fill(ring, with: .color(color), style: FillStyle(eoFill: true))
    }

    /// CSS outer `box-shadow: <dx> <dy> <blur> <spread> <color>` of a rounded rect.
    func dropShadow(of rect: CGRect, radius: CGFloat, dx: CGFloat = 0, dy: CGFloat, blur: CGFloat, spread: CGFloat = 0, color: Color) {
        var shadow = self
        if blur > 0 { shadow.addFilter(.blur(radius: blur / 2)) }
        let r = rect.insetBy(dx: -spread, dy: -spread).offsetBy(dx: dx, dy: dy)
        shadow.fill(Path(roundedRect: r, cornerRadius: max(0, radius + spread), style: .continuous), with: .color(color))
    }

    /// Keeps everything drawn after this out of `hole` (a see-through keyring hole). Used instead of filling the hole
    /// with `.destinationOut` at the end, which PDF can't express, so a vector export would turn the whole canvas
    /// into one bitmap.
    mutating func clipOut(_ hole: Path) {
        var outside = Path(CGRect(x: -1e5, y: -1e5, width: 2e5, height: 2e5))
        outside.addPath(hole)
        clip(to: outside, style: FillStyle(eoFill: true))
    }

    enum TextAnchor { case start, middle, end }

    /// Draws `text` with its first baseline at `baseline`, like SVG `<text x y text-anchor>`.
    func draw(_ text: Text, x: CGFloat, baseline: CGFloat, anchor: TextAnchor = .start) {
        let resolved = resolve(text)
        let size = resolved.measure(in: CGSize(width: 10_000, height: 10_000))
        let base = resolved.firstBaseline(in: size)
        let left: CGFloat
        switch anchor {
        case .start: left = x
        case .middle: left = x - size.width / 2
        case .end: left = x - size.width
        }
        draw(resolved, at: CGPoint(x: left, y: baseline - base), anchor: .topLeading)
    }
}

/// A rounded rect with the CSS corner order (top-left, top-right, bottom-right, bottom-left).
func cornerPath(_ rect: CGRect, _ tl: CGFloat, _ tr: CGFloat, _ br: CGFloat, _ bl: CGFloat) -> Path {
    UnevenRoundedRectangle(topLeadingRadius: tl, bottomLeadingRadius: bl, bottomTrailingRadius: br, topTrailingRadius: tr)
        .path(in: rect)
}

/// End points of a CSS `linear-gradient(<deg>)` across `rect` (0° = towards the top, clockwise).
func cssGradientLine(_ degrees: Double, in rect: CGRect) -> (start: CGPoint, end: CGPoint) {
    let a = degrees * .pi / 180
    let dir = CGPoint(x: sin(a), y: -cos(a))
    let half = (abs(rect.width * dir.x) + abs(rect.height * dir.y)) / 2
    let c = CGPoint(x: rect.midX, y: rect.midY)
    return (CGPoint(x: c.x - dir.x * half, y: c.y - dir.y * half), CGPoint(x: c.x + dir.x * half, y: c.y + dir.y * half))
}

extension Color {
    /// The detached keychain's window passes clicks on its fully transparent pixels to the window behind, and the
    /// modules' Canvas drawings don't count: a module's outline (and the ring's disc) is filled with this faintest
    /// tint (≈ 1/255, invisible) there so the window catches the mouse. Fully clear in the menu bar drop-down.
    static func clickCatcher(_ detached: Bool) -> Color { .black.opacity(detached ? 0.006 : 0) }
}
