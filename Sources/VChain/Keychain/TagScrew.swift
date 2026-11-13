// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI

/// The BPM tag's corner screw: a Phillips head set countersunk flush into the case, 7 × 7 at 1×, with light from the
/// top left. `angle` turns the cross.
struct TagScrew: View {
    var angle: Angle
    var dark = false
    var scale: CGFloat = HardwareScale.app

    var body: some View {
        PartCanvas(size: CGSize(width: 7, height: 7), bleed: 1.5, scale: scale) { ctx in
            Self.draw(angle: angle, dark: dark, in: &ctx)
        }
        .accessibilityHidden(true)
    }

    // MARK: Drawing (1× units, the head's centre at (3.5, 3.5))

    private static let c = CGPoint(x: 3.5, y: 3.5)
    /// Unit vector toward the light (top left).
    private static let toLight = CGVector(dx: -0.6, dy: -0.8)

    private static func circle(_ r: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
    }
    /// From the lit side (top left) to the shaded side across a radius `r`.
    private static func lightToShade(_ r: CGFloat) -> (CGPoint, CGPoint) {
        (CGPoint(x: c.x + toLight.dx * r, y: c.y + toLight.dy * r), CGPoint(x: c.x - toLight.dx * r, y: c.y - toLight.dy * r))
    }

    private static func draw(angle: Angle, dark: Bool, in ctx: inout GraphicsContext) {
        // Countersunk flush: the cone in the case, a hairline gap, the flat head level with the plate.
        let sink: CGFloat = 3.5, head: CGFloat = 2.85
        let (l, s) = lightToShade(sink)
        ctx.fill(circle(sink), shaded: .linearGradient(
            Gradient(colors: [.black.opacity(dark ? 0.45 : 0.32), .black.opacity(0.08), .white.opacity(dark ? 0.25 : 0.65)]),
            startPoint: l, endPoint: s))
        ctx.stroke(circle(sink - 0.08), with: .color(.black.opacity(0.14)), lineWidth: 0.16)
        ctx.fill(circle(head + 0.14), with: .color(.black.opacity(0.55)))  // the gap where head meets case
        let (hl, hs) = lightToShade(head)
        ctx.fill(circle(head), shaded: .linearGradient(
            Gradient(colors: dark ? [hex(0xd2d5d9), hex(0x9a9ea4), hex(0x6f737a)] : [hex(0xf3f4f6), hex(0xbfc2c6), hex(0x8b8f95)]),
            startPoint: hl, endPoint: hs))
        anisotropic(&ctx, head: head)
        // Chamfered rim: bright on the lit edge.
        ctx.stroke(circle(head - 0.12), shaded: .linearGradient(
            Gradient(colors: [.white.opacity(0.8), .white.opacity(0), .black.opacity(0.25)]), startPoint: hl, endPoint: hs), lineWidth: 0.24)
        recess(&ctx, phillips(), angle: angle, dark: dark)
    }

    /// Turned-metal sheen: light and dark sectors swinging round the centre, clipped to the head.
    private static func anisotropic(_ ctx: inout GraphicsContext, head: CGFloat) {
        var g = ctx
        g.clip(to: circle(head))
        let w = Color.white.opacity(0.42), k = Color.black.opacity(0.13), o = Color.clear
        g.fill(circle(head), with: .conicGradient(Gradient(colors: [w, o, k, o, w, o, k, o, w]), center: c, angle: .degrees(-50)))
    }

    /// A socket cut into the head: dark floor, each wall lit or shaded by how it faces the light.
    private static func recess(_ ctx: inout GraphicsContext, _ outline: [CGPoint], angle: Angle, dark: Bool) {
        let rad = angle.radians
        let pts = outline.map { p in
            CGPoint(x: c.x + p.x * cos(rad) - p.y * sin(rad), y: c.y + p.x * sin(rad) + p.y * cos(rad))
        }
        let shape = Path { $0.addLines(pts); $0.closeSubpath() }
        // A thin bright lip on the far edge outside the cut, where the top face breaks into the wall.
        ctx.fill(shape.offsetBy(dx: 0.12, dy: 0.14), with: .color(.white.opacity(dark ? 0.25 : 0.5)))
        ctx.fill(shape, with: .color(hex(0x34373c)))
        let wall: CGFloat = 0.3
        var walls = ctx
        walls.clip(to: shape)
        for i in pts.indices {
            let p = pts[i], q = pts[(i + 1) % pts.count]
            let dx = q.x - p.x, dy = q.y - p.y, len = max(0.0001, hypot(dx, dy))
            var n = CGVector(dx: -dy / len, dy: dx / len)
            let mid = CGPoint(x: (p.x + q.x) / 2, y: (p.y + q.y) / 2)
            if !shape.contains(CGPoint(x: mid.x + n.dx * 0.05, y: mid.y + n.dy * 0.05)) { n = CGVector(dx: -n.dx, dy: -n.dy) }
            // A wall faces into the hole (along n) and up; it catches the light when n points toward it.
            let b = Double(n.dx * toLight.dx + n.dy * toLight.dy)
            let quad = Path { $0.addLines([p, q, CGPoint(x: q.x + n.dx * wall, y: q.y + n.dy * wall),
                                           CGPoint(x: p.x + n.dx * wall, y: p.y + n.dy * wall)]); $0.closeSubpath() }
            walls.fill(quad, with: .color(b > 0 ? hex(0xdfe2e5).opacity(0.85 * b) : .black.opacity(0.45 * -b)))
        }
    }

    /// Phillips cross: tapered arms, small diagonal wings at the centre.
    private static func phillips() -> [CGPoint] {
        let l: CGFloat = 1.8, a: CGFloat = 0.36, end: CGFloat = 0.28, wing: CGFloat = 0.22
        let quadrant = [CGPoint(x: l, y: -end), CGPoint(x: l, y: end), CGPoint(x: a + wing, y: a), CGPoint(x: a, y: a + wing)]
        return (0..<4).flatMap { k in
            quadrant.map { p in
                var p = p
                for _ in 0..<k { p = CGPoint(x: -p.y, y: p.x) }
                return p
            }
        }
    }
}
