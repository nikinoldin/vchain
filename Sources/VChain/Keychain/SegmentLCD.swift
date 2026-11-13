// SPDX-License-Identifier: GPL-3.0-or-later
import VChainKit
import SwiftUI

/// Segment-LCD glass shared by the BPM tag and the MIDI strip: greenish glass (dark: black with
/// green backlight), fixed elements that are only switched on and off, unlit ones as 7.5 % "ghosts",
/// a glow under the lit ones in dark mode, and a glare across the top. Drawn in each display's own
/// unit space (the caller scales the context).
enum SegmentLCD {
    static func ink(dark: Bool) -> Color { dark ? hex(0x46ff63) : hex(0x1b2215) }
    /// Printed graphics (labels, divider, waves, beat numbers) are screen-printed on the glass, not liquid
    /// crystal: a flat grey, lighter than the lit segments, with no backlight glow, so off never looks lit.
    static func printInk(dark: Bool) -> Color { dark ? hex(0x7f857c) : hex(0x575d4e) }

    /// Draws glass, elements and glare into `size` (unit space). `glow` is the dark-mode backlight
    /// blur radius in units; printed elements always show, in `printInk`. `litLevel` < 1 draws the lit segments
    /// part-way between ghost and full ink (an LCD darkening in or fading out).
    /// `turned`: the display is mounted a quarter turn clockwise (its rows run down, like the MIDI strip's channel
    /// LCD): the segments turn with it but the glass shading and glare stay lit from the top left like every other.
    static func draw(in ctx: GraphicsContext, size: CGSize, corner: CGSize, elements: [LCDElement],
                     isLit: (LCDElement) -> Bool, dark: Bool, glow: CGFloat, litLevel: Double = 1, turned: Bool = false) {
        let ink = ink(dark: dark)
        var ctx = ctx
        let glass = Path(roundedRect: CGRect(origin: .zero, size: size), cornerSize: corner)
        ctx.clip(to: glass)
        // The upright frame the light comes from: undo the quarter turn (upright (x, y) = glass (y, h − x)).
        var upright = ctx
        if turned {
            upright.translateBy(x: 0, y: size.height)
            upright.rotate(by: .degrees(-90))
        }
        let w = turned ? size.height : size.width, h = turned ? size.width : size.height
        upright.fill(Path(CGRect(x: 0, y: 0, width: w, height: h)), shaded: .linearGradient(
            Gradient(colors: dark ? [hex(0x0b120b), hex(0x050905)] : [hex(0xaeb79b), hex(0x97a183)]),
            startPoint: .zero, endPoint: CGPoint(x: w, y: h)))
        let lit = elements.filter { !$0.printed && isLit($0) }
        // Ghosts first, then the printed graphics, then the lit segments (with the dark theme's backlight glow under them).
        for el in elements where !el.printed && !isLit(el) {
            el.draw(in: ctx, color: ink.opacity(0.075))
        }
        for el in elements where el.printed { el.draw(in: ctx, color: printInk(dark: dark)) }
        let level = min(1, max(0, litLevel))
        let litInk = level >= 1 ? ink : ink.opacity(0.075 + 0.925 * level)
        if dark && !lit.isEmpty && level > 0 {
            var g = ctx
            g.addFilter(.blur(radius: glow))
            for el in lit { el.draw(in: g, color: ink.opacity(level)) }
        }
        for el in lit { el.draw(in: ctx, color: litInk) }
        // Glass glare: the BPM tag's shape (140 × 96), scaled to the display, in the upright frame.
        upright.fill(Path { p in
            p.move(to: .zero); p.addLine(to: CGPoint(x: w, y: 0)); p.addLine(to: CGPoint(x: w, y: h * 8 / 96))
            p.addQuadCurve(to: CGPoint(x: 0, y: h * 42 / 96), control: CGPoint(x: w / 2, y: h * 26 / 96)); p.closeSubpath()
        }, with: .color(.white.opacity(0.10)))
    }

    /// A seven-segment digit at (x, y, w, h) with bar thickness t: hexagonal bars with `gap` between them, slanted by `skew`.
    static func sevenSeg(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ t: CGFloat, _ skew: CGFloat,
                         gap g: CGFloat = 0.8) -> [Segment: Path] {
        let r = t / 2
        func P(_ xx: CGFloat, _ yy: CGFloat) -> CGPoint { CGPoint(x: xx + skew * (y + h - yy), y: yy) }
        func poly(_ pts: [CGPoint]) -> Path { Path { p in p.addLines(pts); p.closeSubpath() } }
        func H(_ x1: CGFloat, _ x2: CGFloat, _ yc: CGFloat) -> Path {
            poly([P(x1, yc), P(x1 + r, yc - r), P(x2 - r, yc - r), P(x2, yc), P(x2 - r, yc + r), P(x1 + r, yc + r)])
        }
        func V(_ xc: CGFloat, _ y1: CGFloat, _ y2: CGFloat) -> Path {
            poly([P(xc, y1), P(xc + r, y1 + r), P(xc + r, y2 - r), P(xc, y2), P(xc - r, y2 - r), P(xc - r, y1 + r)])
        }
        let xl = x + r, xr = x + w - r, yt = y + r, ym = y + h / 2, yb = y + h - r
        return [.a: H(xl + g, xr - g, yt), .g: H(xl + g, xr - g, ym), .d: H(xl + g, xr - g, yb),
                .f: V(xl, yt + g, ym - g), .e: V(xl, ym + g, yb - g), .b: V(xr, yt + g, ym - g), .c: V(xr, ym + g, yb - g)]
    }

    /// The seven elements of one digit cell, named "<prefix><segment>" (e.g. "d0a").
    static func digitElements(_ prefix: String, _ segs: [Segment: Path]) -> [LCDElement] {
        Segment.allCases.map { LCDElement(name: "\(prefix)\($0)", kind: .fill(segs[$0]!)) }
    }
}

/// One fixed LCD shape: a filled polygon/path, a stroked path, or a printed text.
struct LCDElement {
    enum Kind { case fill(Path), stroke(Path, CGFloat, dash: [CGFloat] = [], opacity: Double = 1), text(String, CGFloat, Font.Weight, CGPoint, GraphicsContext.TextAnchor) }
    var name: String
    var kind: Kind
    /// Printed graphics always show, in the flat print ink (BPM, divider, waves, beat numbers).
    var printed = false

    func draw(in ctx: GraphicsContext, color: Color) {
        switch kind {
        case .fill(let p):
            ctx.fill(p, with: .color(color))
        case .stroke(let p, let w, let dash, let opacity):
            ctx.stroke(p, with: .color(color.opacity(opacity)), style: StrokeStyle(lineWidth: w, lineCap: dash.isEmpty ? .round : .butt, lineJoin: .round, dash: dash))
        case .text(let s, let size, let weight, let at, let anchor):
            ctx.draw(Text(verbatim: s).font(.system(size: size, weight: weight)).tracking(0.6).foregroundStyle(color),
                     x: at.x, baseline: at.y, anchor: anchor)
        }
    }
}
