// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI
import VChainKit

/// One of the split ring's two static pieces: the front
/// piece runs from the top down into the holes, above every module, and ends at the hole's far edge,
/// cut along the hole's round edge and darkening into it; the back piece continues from there round
/// to the top, below every module. Two windings (radius 18.4 and 16.9, 1×), each a dark edge under a
/// steel gradient, with a soft drop shadow. Drawn in hang units ×1.5.
struct RingPiece: View {
    enum Piece { case front, back }
    var piece: Piece

    /// The Canvas, in hang units: the ring's centre is at about (0, 26), radius 18.4.
    static let box = CGRect(x: -24, y: 2, width: 48, height: 48)

    private static let steel = Gradient(stops: [
        .init(color: hex(0xfdfdfd), location: 0), .init(color: hex(0x8b9095), location: 0.22),
        .init(color: hex(0xeef0f2), location: 0.42), .init(color: hex(0x5e6368), location: 0.6),
        .init(color: hex(0xd6d9dc), location: 0.8), .init(color: hex(0x7b8085), location: 1),
    ])

    var body: some View {
        let s = HardwareScale.app
        Canvas { ctx, _ in
            ctx.scaleBy(x: s, y: s)
            ctx.translateBy(x: -Self.box.minX, y: -Self.box.minY)
            draw(&ctx)
        }
        .frame(width: Self.box.width * s, height: Self.box.height * s)
        .accessibilityHidden(true)
    }

    private func draw(_ ctx: inout GraphicsContext) {
        let g = KeyringGeometry.self
        let ring = g.ring(hook: g.hook, hole: g.ringPoint, radius: g.ringRadius)
        let c = ring.center, h = g.ringPoint, opening = g.holeOpening
        let outer = g.ringRadius, inner = g.ringRadius - 1.5
        let aH = Double(atan2(h.y - c.y, h.x - c.x)), top = -Double.pi / 2
        func cut(_ r: CGFloat) -> Double { 2 * asin(Double(opening / (2 * r))) }
        func arc(_ a0: Double, _ a1: Double, _ r: CGFloat) -> Path {
            var p = Path()
            let n = max(8, Int(abs(a1 - a0) / 0.03))
            for k in 0...n {
                let a = a0 + (a1 - a0) * Double(k) / Double(n)
                let pt = CGPoint(x: c.x + r * CGFloat(cos(a)), y: c.y + r * CGFloat(sin(a)))
                if k == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
            }
            return p
        }

        switch piece {
        case .back:
            let arcs = ring.arcs(holeOpening: opening)
            steel(&ctx, [arc(arcs.back.lowerBound, arcs.back.upperBound, outer),
                         arc(aH + cut(inner), top + 2 * Double.pi - 0.4, inner)])
        case .front:
            // Drawn a little past the hole, then cut along its round far edge: keep everything on the
            // near side of the hole's centre, plus the opening itself.
            let o = arc(top, aH + 2 * cut(outer), outer), i = arc(top + 0.15, aH + 2 * cut(inner), inner)
            let t = CGPoint(x: -sin(aH), y: cos(aH))   // the way the ring runs through the hole
            let m = CGPoint(x: cos(aH), y: sin(aH))
            let big: CGFloat = 80
            var near = Path()
            near.move(to: CGPoint(x: h.x + m.x * big, y: h.y + m.y * big))
            near.addLine(to: CGPoint(x: h.x - m.x * big, y: h.y - m.y * big))
            near.addLine(to: CGPoint(x: h.x - m.x * big - t.x * big, y: h.y - m.y * big - t.y * big))
            near.addLine(to: CGPoint(x: h.x + m.x * big - t.x * big, y: h.y + m.y * big - t.y * big))
            near.closeSubpath()
            let hole = Path(ellipseIn: CGRect(x: h.x - opening, y: h.y - opening, width: opening * 2, height: opening * 2))
            var clipped = ctx
            clipped.clip(to: near.union(hole))
            steel(&clipped, [o, i])
            // Darkening into the hole.
            var shade = clipped
            shade.clip(to: hole)
            let into = Shade.linearGradient(
                Gradient(stops: [.init(color: .black.opacity(0), location: 0), .init(color: .black.opacity(0.15), location: 0.45),
                                 .init(color: .black.opacity(0.75), location: 1)]),
                startPoint: CGPoint(x: h.x - t.x * opening, y: h.y - t.y * opening),
                endPoint: CGPoint(x: h.x + t.x * opening, y: h.y + t.y * opening))
            shade.stroke(o, shaded: into, lineWidth: 2.2)
            shade.stroke(i, shaded: into, lineWidth: 2.2)
        }
    }

    /// Dark edge under a steel gradient (diagonal across each winding), one shadow under both.
    private func steel(_ ctx: inout GraphicsContext, _ windings: [Path]) {
        var shadowed = ctx
        shadowed.addFilter(.shadow(color: .black.opacity(0.35), radius: 0.7, x: 0.6, y: 1.2))
        shadowed.drawLayer { layer in
            for w in windings {
                let b = w.boundingRect
                layer.stroke(w, with: .color(hex(0x4d5156)), lineWidth: 2)
                layer.stroke(w, shaded: .linearGradient(Self.steel, startPoint: b.origin, endPoint: CGPoint(x: b.maxX, y: b.maxY)),
                             lineWidth: 1.45)
            }
        }
    }
}
