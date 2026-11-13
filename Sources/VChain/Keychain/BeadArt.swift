// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import VChainKit
import SwiftUI

/// The bead recipes, in 1× points around each bead's centre.
enum BeadArt {
    static func strand(_ s: BeadCharms.Strand, _ ctx: inout GraphicsContext) {
        let stack = BeadCharms.stack(s)
        let bottom = BeadCharms.bottomLoop(s)
        let r = BeadCharms.loopRadius, w = BeadCharms.wire
        shadowed(&ctx) { l in
            // The pin, behind the beads: it shows between them and through the glass ones.
            var pin = Path()
            pin.move(to: CGPoint(x: 0, y: r - w / 2))
            pin.addLine(to: CGPoint(x: 0, y: bottom.y - r + w / 2))
            gold(&l, pin, width: w, across: true)
            loop(&l, at: .zero)
            loop(&l, at: bottom)
            for (i, p) in stack.enumerated() { bead(p, index: i, &l) }
        }
    }

    /// Soft drop shadow down-right (like the ring's and the modules'): glass casts a lighter one.
    static func shadowed(_ ctx: inout GraphicsContext, _ draw: @escaping (inout GraphicsContext) -> Void) {
        var c = ctx
        c.addFilter(.shadow(color: .black.opacity(0.32), radius: 0.6, x: 0.55, y: 1.05))
        c.drawLayer { l in draw(&l) }
    }

    private static let goldStops = Gradient(stops: [
        .init(color: hex(0xfff2c2), location: 0), .init(color: hex(0xe2b955), location: 0.35),
        .init(color: hex(0xa97a24), location: 0.7), .init(color: hex(0xd9ae4c), location: 1),
    ])

    /// Solid gold (a stamped or cast piece): the gold gradient across it (left to right with `across`, else
    /// diagonally), a dark edge and a catch-light along its upper-left edge.
    static func goldSolid(_ ctx: inout GraphicsContext, _ path: Path, across: Bool = false, eoFill: Bool = false) {
        let b = path.boundingRect
        let style = FillStyle(eoFill: eoFill)
        ctx.fill(path, shaded: across
            ? .linearGradient(goldStops, startPoint: CGPoint(x: b.minX, y: b.midY), endPoint: CGPoint(x: b.maxX, y: b.midY))
            : .linearGradient(goldStops, startPoint: b.origin, endPoint: CGPoint(x: b.maxX, y: b.maxY)), style: style)
        var light = ctx
        light.clip(to: path, style: style)
        light.stroke(path.offsetBy(dx: 0.35, dy: 0.35), with: .color(.white.opacity(0.55)), lineWidth: 0.45)
        ctx.stroke(path, with: .color(hex(0x6e4a12)), lineWidth: 0.3)
    }

    /// Gold wire: a dark edge, the gold gradient, a fine highlight on its upper-left side.
    static func gold(_ ctx: inout GraphicsContext, _ path: Path, width: CGFloat, across: Bool = false) {
        let b = path.boundingRect.insetBy(dx: -width, dy: -width)
        let shade: GraphicsContext.Shading = across
            ? .linearGradient(goldStops, startPoint: CGPoint(x: b.midX - width / 2, y: b.midY), endPoint: CGPoint(x: b.midX + width / 2, y: b.midY))
            : .linearGradient(goldStops, startPoint: b.origin, endPoint: CGPoint(x: b.maxX, y: b.maxY))
        ctx.stroke(path, with: .color(hex(0x6e4a12)), lineWidth: width + 0.2)
        ctx.stroke(path, with: shade, lineWidth: width)
        ctx.stroke(path.offsetBy(dx: -width * 0.2, dy: -width * 0.15), with: .color(.white.opacity(0.5)), lineWidth: width * 0.25)
    }

    private static func loop(_ ctx: inout GraphicsContext, at c: CGPoint) {
        let r = BeadCharms.loopRadius - BeadCharms.wire / 2
        gold(&ctx, Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)), width: BeadCharms.wire)
    }

    // MARK: Beads

    private static func bead(_ p: BeadCharms.Placed, index: Int, _ ctx: inout GraphicsContext) {
        let c = p.center, sz = p.size
        switch p.bead {
        case .redRound:
            sphere(&ctx, c, sz.width / 2, hi: 0xff7466, mid: 0xd8141e, lo: 0x6a0610, gloss: 0.95)
            glow(&ctx, c, sz.width / 2, color: 0xff3b2e, opacity: 0.45)
        case .daisy: daisy(&ctx, c, sz)
        case .heartDisc: heartDisc(&ctx, c, sz)
        case .pearl: pearl(&ctx, c, sz.width / 2)
        case .ribbedCube: ribbedCube(&ctx, c, sz)
        case .tulip: tulip(&ctx, c, sz)
        case .leaf: leaf(&ctx, c, sz)
        case .roseQuartz:
            stone(&ctx, c, sz.width / 2, hi: 0xfff6f6, mid: 0xefd5d9, lo: 0xbf9ea4, gloss: 0.85, blobs: [
                Blob(-0.3, 0.25, 0.45, 0.3, 30, 0xffffff, 0.45), Blob(0.35, -0.1, 0.35, 0.22, -20, 0xe2b3bb, 0.5),
                Blob(0.1, 0.5, 0.3, 0.2, 10, 0xf7e6e8, 0.5),
            ])
        case .carnelian:
            stone(&ctx, c, sz.width / 2, hi: 0xffbb84, mid: 0xec7539, lo: 0x983812, gloss: 0.9, blobs: [
                Blob(-0.25, 0.1, 0.5, 0.18, 35, 0xfab07a, 0.7), Blob(0.3, 0.35, 0.4, 0.22, -15, 0xd2501b, 0.55),
                Blob(0.15, -0.35, 0.32, 0.14, 60, 0xfdd3ad, 0.5), Blob(-0.4, 0.5, 0.25, 0.2, 0, 0xe0612a, 0.5),
            ])
        case .aqua:
            stone(&ctx, c, sz.width / 2, hi: 0xeef7f5, mid: 0xb3cdca, lo: 0x76918d, gloss: 0.95, blobs: [])
        case .lilacBarrel: barrel(&ctx, c, sz)
        case .jade:
            stone(&ctx, c, sz.width / 2, hi: 0xf2faec, mid: 0xbedab3, lo: 0x80a378, gloss: 0.9, blobs: [
                Blob(-0.2, 0.3, 0.45, 0.3, 20, 0xe2f2d9, 0.55), Blob(0.35, -0.2, 0.3, 0.2, -30, 0xa3c697, 0.45),
            ])
            glow(&ctx, c, sz.width / 2, color: 0xe6f5dc, opacity: 0.4)
        case .kyanite:
            stone(&ctx, c, sz.width / 2, hi: 0x86a2e2, mid: 0x2e4a9c, lo: 0x141f52, gloss: 0.95, blobs: [
                Blob(-0.15, 0.15, 0.6, 0.12, 70, 0x7491d8, 0.65), Blob(0.3, 0.3, 0.5, 0.1, 60, 0xa9bbe8, 0.45),
                Blob(0.2, -0.3, 0.4, 0.16, 75, 0x172664, 0.6), Blob(-0.45, -0.1, 0.3, 0.1, 80, 0x5a78c6, 0.5),
            ])
        case .mushroomHeart: mushroomHeart(&ctx, c, sz)
        case .millefiori(let i): millefiori(&ctx, c, sz, pattern: i)
        }
    }

    /// A glossy ball: lit from the top left, a reflected rim at the bottom right, a window highlight.
    private static func sphere(_ ctx: inout GraphicsContext, _ c: CGPoint, _ r: CGFloat, hi: UInt32, mid: UInt32, lo: UInt32,
                               gloss: Double, blobs: [Blob] = []) {
        let ball = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
        ctx.fill(ball, shaded: .radialGradient(
            Gradient(stops: [.init(color: hex(hi), location: 0), .init(color: hex(mid), location: 0.42), .init(color: hex(lo), location: 1)]),
            center: CGPoint(x: c.x - r * 0.35, y: c.y - r * 0.4), startRadius: 0, endRadius: r * 1.55))
        var inside = ctx
        inside.clip(to: ball)
        if !blobs.isEmpty {
            var m = inside
            m.addFilter(.blur(radius: r * 0.12))
            for b in blobs { b.draw(&m, c, r) }
            // Keep the shading on top of the mottling.
            inside.fill(ball, shaded: .radialGradient(
                Gradient(stops: [.init(color: .white.opacity(0.25), location: 0), .init(color: .clear, location: 0.4),
                                 .init(color: .black.opacity(0.35), location: 1)]),
                center: CGPoint(x: c.x - r * 0.35, y: c.y - r * 0.4), startRadius: 0, endRadius: r * 1.55))
        }
        // Light bounced back up into the lower right.
        inside.fill(ball, shaded: .radialGradient(
            Gradient(stops: [.init(color: .white.opacity(0.22), location: 0), .init(color: .clear, location: 1)]),
            center: CGPoint(x: c.x + r * 0.55, y: c.y + r * 0.62), startRadius: 0, endRadius: r * 0.6))
        highlight(&inside, c, r, gloss: gloss)
    }

    private static func stone(_ ctx: inout GraphicsContext, _ c: CGPoint, _ r: CGFloat, hi: UInt32, mid: UInt32, lo: UInt32,
                              gloss: Double, blobs: [Blob]) {
        sphere(&ctx, c, r, hi: hi, mid: mid, lo: lo, gloss: gloss, blobs: blobs)
    }

    /// A window reflection (soft oval) and a sharp sparkle in the upper left.
    private static func highlight(_ ctx: inout GraphicsContext, _ c: CGPoint, _ r: CGFloat, gloss: Double, soft: Bool = false) {
        var h = ctx
        h.addFilter(.blur(radius: r * (soft ? 0.14 : 0.06)))
        h.translateBy(x: c.x - r * 0.4, y: c.y - r * 0.45)
        h.rotate(by: .degrees(-35))
        h.fill(Path(ellipseIn: CGRect(x: -r * 0.32, y: -r * 0.18, width: r * 0.64, height: r * 0.36)), with: .color(.white.opacity(gloss * 0.85)))
        if !soft {
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - r * 0.52, y: c.y - r * 0.56, width: r * 0.2, height: r * 0.2)),
                     with: .color(.white.opacity(gloss)))
        }
    }

    /// Translucent material lit from inside: light gathered on the side away from the light.
    private static func glow(_ ctx: inout GraphicsContext, _ c: CGPoint, _ r: CGFloat, color: UInt32, opacity: Double) {
        let ball = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
        var g = ctx
        g.clip(to: ball)
        g.fill(ball, shaded: .radialGradient(
            Gradient(stops: [.init(color: hex(color, opacity: opacity), location: 0), .init(color: .clear, location: 1)]),
            center: CGPoint(x: c.x + r * 0.3, y: c.y + r * 0.42), startRadius: 0, endRadius: r * 0.7))
    }

    /// The pin seen through glass, bent a little by it (refraction), and a caustic opposite the light.
    private static func throughGlass(_ ctx: inout GraphicsContext, _ shape: Path, _ c: CGPoint, _ sz: CGSize, bend: CGFloat, caustic: UInt32) {
        var g = ctx
        g.clip(to: shape)
        var pin = Path()
        pin.move(to: CGPoint(x: 0, y: c.y - sz.height / 2))
        pin.addQuadCurve(to: CGPoint(x: 0, y: c.y + sz.height / 2), control: CGPoint(x: bend, y: c.y))
        g.stroke(pin, with: .color(hex(0xd9ae4c, opacity: 0.75)), lineWidth: BeadCharms.wire * 0.8)
        g.stroke(pin.offsetBy(dx: -0.12, dy: 0), with: .color(.white.opacity(0.35)), lineWidth: 0.12)
        var k = g
        k.addFilter(.blur(radius: 0.6))
        k.fill(Path(ellipseIn: CGRect(x: c.x + sz.width * 0.05, y: c.y + sz.height * 0.12, width: sz.width * 0.32, height: sz.height * 0.26)),
               with: .color(hex(caustic, opacity: 0.55)))
    }

    private static func pearl(_ ctx: inout GraphicsContext, _ c: CGPoint, _ r: CGFloat) {
        let ball = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
        ctx.fill(ball, shaded: .radialGradient(
            Gradient(stops: [.init(color: hex(0xffffff), location: 0), .init(color: hex(0xf2ede7), location: 0.4),
                             .init(color: hex(0xd8d0c8), location: 0.75), .init(color: hex(0xa69d95), location: 1)]),
            center: CGPoint(x: c.x - r * 0.3, y: c.y - r * 0.35), startRadius: 0, endRadius: r * 1.5))
        // Nacre: a rosy sheen one side, a cool green-blue the other.
        var sheen = ctx
        sheen.clip(to: ball)
        sheen.addFilter(.blur(radius: r * 0.25))
        sheen.fill(Path(ellipseIn: CGRect(x: c.x + r * 0.05, y: c.y - r * 0.85, width: r * 0.9, height: r * 0.9)), with: .color(hex(0xf5c9d6, opacity: 0.45)))
        sheen.fill(Path(ellipseIn: CGRect(x: c.x - r * 0.95, y: c.y + r * 0.1, width: r * 0.9, height: r * 0.8)), with: .color(hex(0xc7e3e0, opacity: 0.45)))
        sheen.stroke(Path(ellipseIn: CGRect(x: c.x - r * 0.75, y: c.y - r * 0.75, width: r * 1.5, height: r * 1.5)),
                     with: .color(.white.opacity(0.35)), lineWidth: r * 0.12)
        var inside = ctx
        inside.clip(to: ball)
        highlight(&inside, c, r, gloss: 0.8, soft: true)
    }

    private static func daisy(_ ctx: inout GraphicsContext, _ c: CGPoint, _ sz: CGSize) {
        var g = ctx
        g.translateBy(x: c.x, y: c.y)
        g.rotate(by: .degrees(12))
        let rx = sz.width / 2
        var petals: [Path] = []
        for k in 0..<6 {
            let a = Double(k) * Double.pi / 3
            let d = rx * 0.55
            let petal = Path(ellipseIn: CGRect(x: -rx * 0.44, y: -rx * 0.38, width: rx * 0.88, height: rx * 0.76))
                .applying(CGAffineTransform(translationX: d, y: 0).concatenating(CGAffineTransform(rotationAngle: a)))
            petals.append(petal)
        }
        var flower = Path(ellipseIn: CGRect(x: -rx * 0.6, y: -rx * 0.6, width: rx * 1.2, height: rx * 1.2))
        for p in petals { flower = flower.union(p) }
        // Matte polymer clay: soft shading, no sparkle.
        g.fill(flower, shaded: .radialGradient(
            Gradient(stops: [.init(color: hex(0xffffff), location: 0), .init(color: hex(0xf4f2ee), location: 0.5),
                             .init(color: hex(0xcfcbc2), location: 1)]),
            center: CGPoint(x: -rx * 0.35, y: -rx * 0.4), startRadius: 0, endRadius: rx * 1.5))
        var inside = g
        inside.clip(to: flower)
        for p in petals { inside.stroke(p, with: .color(hex(0xc9c4ba, opacity: 0.55)), lineWidth: 0.22) }
        // A few grey veins in the clay.
        var vein = Path()
        vein.move(to: CGPoint(x: rx * 0.3, y: rx * 0.15)); vein.addQuadCurve(to: CGPoint(x: rx * 0.9, y: rx * 0.45), control: CGPoint(x: rx * 0.65, y: rx * 0.05))
        vein.move(to: CGPoint(x: rx * 0.2, y: rx * 0.6)); vein.addLine(to: CGPoint(x: rx * 0.55, y: rx * 0.75))
        inside.stroke(vein, with: .color(hex(0x8d8a84, opacity: 0.45)), lineWidth: 0.15)
        let eye = CGRect(x: -rx * 0.42, y: -rx * 0.2, width: rx * 0.48, height: rx * 0.44)
        g.fill(Path(ellipseIn: eye), shaded: .radialGradient(
            Gradient(colors: [hex(0xffd84a), hex(0xf2b51d), hex(0xd4921a)]),
            center: CGPoint(x: eye.midX - 0.25, y: eye.midY - 0.25), startRadius: 0, endRadius: rx * 0.3))
    }

    private static func heartDisc(_ ctx: inout GraphicsContext, _ c: CGPoint, _ sz: CGSize) {
        let r = sz.width / 2
        let face = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
        // The disc's edge, seen a little from above-left.
        ctx.fill(face.offsetBy(dx: 0.35, dy: 0.55), with: .color(hex(0xd47892)))
        ctx.fill(face, shaded: .radialGradient(
            Gradient(colors: [hex(0xfbbfcd), hex(0xf5a0b5), hex(0xe5839c)]),
            center: CGPoint(x: c.x - r * 0.3, y: c.y - r * 0.35), startRadius: 0, endRadius: r * 1.4))
        ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r * 0.88, y: c.y - r * 0.88, width: r * 1.76, height: r * 1.76)),
                   with: .color(.white.opacity(0.18)), lineWidth: 0.3)
        let h = heart(CGRect(x: c.x - r * 0.42, y: c.y - r * 0.36, width: r * 0.84, height: r * 0.78))
        ctx.fill(h.offsetBy(dx: 0.12, dy: 0.18), with: .color(hex(0x8a0c1f, opacity: 0.5)))
        ctx.fill(h, shaded: .linearGradient(Gradient(colors: [hex(0xe0263f), hex(0xb80f27)]),
                                          startPoint: CGPoint(x: c.x, y: c.y - r * 0.36), endPoint: CGPoint(x: c.x, y: c.y + r * 0.42)))
        var inside = ctx
        inside.clip(to: face)
        highlight(&inside, c, r, gloss: 0.45, soft: true)
    }

    private static func ribbedCube(_ ctx: inout GraphicsContext, _ c: CGPoint, _ sz: CGSize) {
        var g = ctx
        g.translateBy(x: c.x, y: c.y)
        g.rotate(by: .degrees(-9))
        let w = sz.width, h = sz.height
        let body = Path(roundedRect: CGRect(x: -w / 2, y: -h / 2, width: w, height: h), cornerRadius: 1.7, style: .continuous)
        g.fill(body, shaded: .linearGradient(
            Gradient(stops: [.init(color: hex(0xc9dbf6, opacity: 0.62), location: 0), .init(color: hex(0x9fbbe8, opacity: 0.5), location: 0.5),
                             .init(color: hex(0x7f9fd6, opacity: 0.7), location: 1)]),
            startPoint: CGPoint(x: -w / 2, y: -h / 2), endPoint: CGPoint(x: w / 2, y: h / 2)))
        throughGlass(&g, body, .zero, sz, bend: 0.7, caustic: 0xeef5ff)
        var inside = g
        inside.clip(to: body)
        // Twisted ribs: S-curved, a light and a dark line each.
        for k in 0..<5 {
            let x = -w / 2 + w * (CGFloat(k) + 0.5) / 5
            var rib = Path()
            rib.move(to: CGPoint(x: x - 0.7, y: -h / 2))
            rib.addCurve(to: CGPoint(x: x + 0.7, y: h / 2), control1: CGPoint(x: x + 1.1, y: -h / 6), control2: CGPoint(x: x - 1.0, y: h / 6))
            inside.stroke(rib, with: .color(.white.opacity(0.5)), lineWidth: 0.4)
            inside.stroke(rib.offsetBy(dx: 0.45, dy: 0), with: .color(hex(0x6f8fc8, opacity: 0.45)), lineWidth: 0.3)
        }
        // The top face catching the light.
        inside.fill(Path(CGRect(x: -w / 2, y: -h / 2, width: w, height: 1.1)), with: .color(hex(0xeaf2ff, opacity: 0.55)))
        g.stroke(body, with: .color(hex(0x6d8fca, opacity: 0.75)), lineWidth: 0.35)
        var streak = inside
        streak.addFilter(.blur(radius: 0.25))
        streak.fill(Path(roundedRect: CGRect(x: -w / 2 + 0.7, y: -h / 2 + 1.3, width: 0.9, height: h - 2.6), cornerRadius: 0.45),
                    with: .color(.white.opacity(0.7)))
    }

    private static func tulip(_ ctx: inout GraphicsContext, _ c: CGPoint, _ sz: CGSize) {
        var g = ctx
        g.translateBy(x: c.x, y: c.y)
        g.rotate(by: .degrees(4))
        let w = sz.width / 2, h = sz.height / 2
        let cup = Path { p in
            p.move(to: CGPoint(x: 0, y: h))
            p.addCurve(to: CGPoint(x: -w * 0.92, y: -h * 0.85), control1: CGPoint(x: -w * 1.2, y: h * 0.75), control2: CGPoint(x: -w * 1.05, y: -h * 0.2))
            p.addQuadCurve(to: CGPoint(x: -w * 0.35, y: -h * 0.5), control: CGPoint(x: -w * 0.55, y: -h * 0.82))
            p.addQuadCurve(to: CGPoint(x: 0, y: -h), control: CGPoint(x: -w * 0.2, y: -h * 0.95))
            p.addQuadCurve(to: CGPoint(x: w * 0.35, y: -h * 0.5), control: CGPoint(x: w * 0.2, y: -h * 0.95))
            p.addQuadCurve(to: CGPoint(x: w * 0.92, y: -h * 0.85), control: CGPoint(x: w * 0.55, y: -h * 0.82))
            p.addCurve(to: CGPoint(x: 0, y: h), control1: CGPoint(x: w * 1.05, y: -h * 0.2), control2: CGPoint(x: w * 1.2, y: h * 0.75))
            p.closeSubpath()
        }
        g.fill(cup, shaded: .radialGradient(
            Gradient(stops: [.init(color: hex(0xfbc1d2, opacity: 0.8), location: 0), .init(color: hex(0xef86a6, opacity: 0.72), location: 0.55),
                             .init(color: hex(0xc9557b, opacity: 0.85), location: 1)]),
            center: CGPoint(x: -w * 0.3, y: -h * 0.2), startRadius: 0, endRadius: w * 1.5))
        throughGlass(&g, cup, .zero, sz, bend: -0.6, caustic: 0xffd9e6)
        var inside = g
        inside.clip(to: cup)
        // The front petal's edge and the one behind it.
        var petal = Path()
        petal.move(to: CGPoint(x: -w * 0.35, y: -h * 0.5))
        petal.addQuadCurve(to: CGPoint(x: w * 0.25, y: h * 0.9), control: CGPoint(x: -w * 0.35, y: h * 0.45))
        inside.stroke(petal, with: .color(hex(0xb8456b, opacity: 0.55)), lineWidth: 0.35)
        inside.stroke(petal.offsetBy(dx: -0.35, dy: 0), with: .color(.white.opacity(0.3)), lineWidth: 0.25)
        g.stroke(cup, with: .color(hex(0xb54a70, opacity: 0.6)), lineWidth: 0.3)
        var streak = inside
        streak.addFilter(.blur(radius: 0.3))
        streak.fill(Path(ellipseIn: CGRect(x: -w * 0.8, y: -h * 0.55, width: w * 0.42, height: h * 0.9)), with: .color(.white.opacity(0.55)))
    }

    private static func leaf(_ ctx: inout GraphicsContext, _ c: CGPoint, _ sz: CGSize) {
        var g = ctx
        g.translateBy(x: c.x, y: c.y)
        g.rotate(by: .degrees(-3))
        let w = sz.width / 2, h = sz.height / 2
        let shape = Path { p in
            p.move(to: CGPoint(x: -w, y: -h * 0.75))
            p.addQuadCurve(to: CGPoint(x: w, y: -h * 0.75), control: CGPoint(x: 0, y: h * 2.7))
            p.addQuadCurve(to: CGPoint(x: -w, y: -h * 0.75), control: CGPoint(x: 0, y: h * 0.45))
            p.closeSubpath()
        }
        g.fill(shape, shaded: .linearGradient(
            Gradient(stops: [.init(color: hex(0xa6e889, opacity: 0.8), location: 0), .init(color: hex(0x55c43e, opacity: 0.78), location: 0.45),
                             .init(color: hex(0x23861c, opacity: 0.92), location: 1)]),
            startPoint: CGPoint(x: 0, y: -h), endPoint: CGPoint(x: 0, y: h)))
        throughGlass(&g, shape, .zero, sz, bend: 0.5, caustic: 0xdfffc8)
        var inside = g
        inside.clip(to: shape)
        var rim = Path()
        rim.move(to: CGPoint(x: -w * 0.8, y: -h * 0.35))
        rim.addQuadCurve(to: CGPoint(x: w * 0.8, y: -h * 0.35), control: CGPoint(x: 0, y: h * 1.1))
        var streak = inside
        streak.addFilter(.blur(radius: 0.2))
        streak.stroke(rim, with: .color(.white.opacity(0.65)), lineWidth: 0.55)
        g.stroke(shape, with: .color(hex(0x1f7a18, opacity: 0.8)), lineWidth: 0.32)
    }

    private static func barrel(_ ctx: inout GraphicsContext, _ c: CGPoint, _ sz: CGSize) {
        let rect = CGRect(x: c.x - sz.width / 2, y: c.y - sz.height / 2, width: sz.width, height: sz.height)
        let body = Path(roundedRect: rect, cornerRadius: 1.7, style: .continuous)
        // A short cylinder on its axis (the pin): shaded side to side.
        ctx.fill(body, shaded: .linearGradient(
            Gradient(stops: [.init(color: hex(0x8e7b97), location: 0), .init(color: hex(0xc1b0c6), location: 0.28),
                             .init(color: hex(0xa794ad), location: 0.6), .init(color: hex(0x6a5974), location: 1)]),
            startPoint: CGPoint(x: rect.minX, y: c.y), endPoint: CGPoint(x: rect.maxX, y: c.y)))
        var inside = ctx
        inside.clip(to: body)
        inside.fill(body, shaded: .linearGradient(
            Gradient(stops: [.init(color: .white.opacity(0.28), location: 0), .init(color: .clear, location: 0.25),
                             .init(color: .clear, location: 0.8), .init(color: .black.opacity(0.18), location: 1)]),
            startPoint: CGPoint(x: c.x, y: rect.minY), endPoint: CGPoint(x: c.x, y: rect.maxY)))
        var streak = inside
        streak.addFilter(.blur(radius: 0.18))
        streak.fill(Path(roundedRect: CGRect(x: rect.minX + sz.width * 0.2, y: rect.minY + 0.8, width: 0.75, height: sz.height - 1.6), cornerRadius: 0.35),
                    with: .color(.white.opacity(0.75)))
        streak.fill(Path(roundedRect: CGRect(x: rect.maxX - sz.width * 0.2, y: rect.minY + 1.2, width: 0.4, height: sz.height - 2.4), cornerRadius: 0.2),
                    with: .color(.white.opacity(0.35)))
    }

    private static func mushroomHeart(_ ctx: inout GraphicsContext, _ c: CGPoint, _ sz: CGSize) {
        let rect = CGRect(x: c.x - sz.width / 2, y: c.y - sz.height / 2, width: sz.width, height: sz.height)
        let shape = heart(rect)
        // Frosted glass: milky, a little see-through at the edge.
        ctx.fill(shape, shaded: .radialGradient(
            Gradient(stops: [.init(color: hex(0xffffff, opacity: 0.95), location: 0), .init(color: hex(0xeceef2, opacity: 0.9), location: 0.55),
                             .init(color: hex(0xbfc5cf, opacity: 0.85), location: 1)]),
            center: CGPoint(x: rect.midX - sz.width * 0.15, y: rect.midY - sz.height * 0.2), startRadius: 0, endRadius: sz.width * 0.75))
        var inside = ctx
        inside.clip(to: shape)
        // Raised texture: little hearts and white dots.
        let hearts: [(CGFloat, CGFloat, Double)] = [(0.2, 0.28, -15), (0.78, 0.3, 20), (0.86, 0.55, 10), (0.25, 0.62, -25), (0.55, 0.82, 5), (0.68, 0.14, -10)]
        for (x, y, a) in hearts {
            var t = inside
            t.translateBy(x: rect.minX + sz.width * x, y: rect.minY + sz.height * y)
            t.rotate(by: .degrees(a))
            let small = heart(CGRect(x: -1.3, y: -1.2, width: 2.6, height: 2.4))
            t.stroke(small.offsetBy(dx: 0.15, dy: 0.2), with: .color(hex(0x9aa3b0, opacity: 0.35)), lineWidth: 0.3)
            t.stroke(small, with: .color(.white.opacity(0.9)), lineWidth: 0.3)
        }
        let dots: [(CGFloat, CGFloat)] = [(0.13, 0.42), (0.44, 0.24), (0.82, 0.44), (0.3, 0.75), (0.62, 0.66), (0.4, 0.5)]
        for (x, y) in dots {
            let d = Path(ellipseIn: CGRect(x: rect.minX + sz.width * x - 0.55, y: rect.minY + sz.height * y - 0.55, width: 1.1, height: 1.1))
            inside.fill(d.offsetBy(dx: 0.15, dy: 0.22), with: .color(hex(0x8f97a3, opacity: 0.35)))
            inside.fill(d, with: .color(hex(0xfdfdf8)))
        }
        // The painted mushroom, raised: a white stem under a red cap with white spots.
        var m = inside
        m.translateBy(x: rect.midX - 0.2, y: rect.midY + 0.2)
        m.rotate(by: .degrees(-14))
        let stem = Path { p in
            p.move(to: CGPoint(x: -0.85, y: -0.6))
            p.addQuadCurve(to: CGPoint(x: -1.25, y: 3.6), control: CGPoint(x: -0.7, y: 2.2))
            p.addQuadCurve(to: CGPoint(x: 1.0, y: 3.6), control: CGPoint(x: -0.1, y: 4.3))
            p.addQuadCurve(to: CGPoint(x: 0.85, y: -0.6), control: CGPoint(x: 0.6, y: 2.0))
            p.closeSubpath()
        }
        let cap = Path { p in
            p.move(to: CGPoint(x: -3.3, y: 0))
            p.addCurve(to: CGPoint(x: 3.3, y: 0), control1: CGPoint(x: -3.0, y: -4.4), control2: CGPoint(x: 3.0, y: -4.4))
            p.addQuadCurve(to: CGPoint(x: -3.3, y: 0), control: CGPoint(x: 0, y: 0.9))
            p.closeSubpath()
        }
        var raised = m
        raised.addFilter(.shadow(color: hex(0x5d6570, opacity: 0.45), radius: 0.25, x: 0.2, y: 0.3))
        raised.drawLayer { l in
            l.fill(stem, shaded: .linearGradient(Gradient(colors: [hex(0xffffff), hex(0xf1ece2), hex(0xd8d1c4)]),
                                               startPoint: CGPoint(x: -1.2, y: 0), endPoint: CGPoint(x: 1.1, y: 0)))
            l.fill(cap, shaded: .linearGradient(Gradient(colors: [hex(0xe8323a), hex(0xcc141e), hex(0x9c0c15)]),
                                              startPoint: CGPoint(x: -1, y: -3.2), endPoint: CGPoint(x: 1, y: 0.6)))
        }
        for (x, y) in [(-1.6, -1.1), (-0.3, -1.6), (1.1, -1.2), (0.4, -0.4), (2.2, -0.5)] as [(CGFloat, CGFloat)] {
            m.fill(Path(ellipseIn: CGRect(x: x - 0.38, y: y - 0.38, width: 0.76, height: 0.76)), with: .color(hex(0xfffdf6)))
        }
        var gloss = m
        gloss.addFilter(.blur(radius: 0.15))
        gloss.stroke(Path { p in p.move(to: CGPoint(x: -2.3, y: -1.4)); p.addQuadCurve(to: CGPoint(x: -0.6, y: -2.9), control: CGPoint(x: -1.9, y: -2.7)) },
                     with: .color(.white.opacity(0.7)), lineWidth: 0.35)
        // Glass rim: lit at the upper left, darker round the lower right.
        inside.stroke(shape.offsetBy(dx: 0.35, dy: 0.4), with: .color(.white.opacity(0.7)), lineWidth: 0.6)
        inside.stroke(shape.offsetBy(dx: -0.3, dy: -0.35), with: .color(hex(0x8e96a3, opacity: 0.4)), lineWidth: 0.6)
        ctx.stroke(shape, with: .color(hex(0x9aa1ad, opacity: 0.65)), lineWidth: 0.3)
    }

    // MARK: Millefiori

    private struct Cane {
        var base: UInt32, baseAlpha: Double = 1, petal: UInt32, outline: UInt32?, center: UInt32, petals: Int = 6, star = false
    }

    /// Top to bottom, as on the real strand.
    private static let canes: [Cane] = [
        Cane(base: 0xc8161f, petal: 0xfbf6ee, outline: 0xe4c9c0, center: 0xf3c21b),
        Cane(base: 0xe9eeee, baseAlpha: 0.55, petal: 0xd5212b, outline: 0xffffff, center: 0xd5212b),
        Cane(base: 0x7a0c18, petal: 0x111111, outline: 0xf3f0ea, center: 0xc8161f, petals: 8, star: true),
        Cane(base: 0xf0be1c, petal: 0xfdf1c4, outline: nil, center: 0xd8202a, petals: 5),
        Cane(base: 0x1a1515, petal: 0xf4f0e6, outline: nil, center: 0xf0c020, petals: 6),
        Cane(base: 0xf2f2ee, baseAlpha: 0.9, petal: 0xffffff, outline: 0xbcbcb6, center: 0xf0c020, petals: 5),
        Cane(base: 0x58b7e2, petal: 0xfbfbf6, outline: nil, center: 0xf0681e),
        Cane(base: 0x1b3ca8, petal: 0xf7f7f2, outline: 0x9fb2e8, center: 0xd51f26),
        Cane(base: 0xeef0ee, baseAlpha: 0.5, petal: 0xffffff, outline: 0xcfcfc8, center: 0xf0c020),
        Cane(base: 0x47213f, petal: 0xf3eef0, outline: 0xb79ab0, center: 0xd51f26),
    ]

    /// A flat glass disc, face on but turned a little on the pin, with its flower cane.
    private static func millefiori(_ ctx: inout GraphicsContext, _ c: CGPoint, _ sz: CGSize, pattern i: Int) {
        let cane = canes[i % canes.count]
        let tilts: [Double] = [-8, 6, -4, 10, -12, 4, -6, 8, -3, 7]
        var g = ctx
        g.translateBy(x: c.x, y: c.y)
        g.rotate(by: .degrees(tilts[i % tilts.count]))
        let rx = sz.width / 2, ry = sz.height / 2
        let face = Path(ellipseIn: CGRect(x: -rx, y: -ry, width: rx * 2, height: ry * 2))
        // The disc's side.
        g.fill(face.offsetBy(dx: 0.3, dy: 0.45), with: .color(hex(cane.base, opacity: min(1, cane.baseAlpha + 0.25)).mix(.black, 0.35)))
        g.fill(face, shaded: .radialGradient(
            Gradient(colors: [hex(cane.base, opacity: cane.baseAlpha).mix(.white, 0.25), hex(cane.base, opacity: cane.baseAlpha),
                              hex(cane.base, opacity: cane.baseAlpha).mix(.black, 0.2)]),
            center: CGPoint(x: -rx * 0.3, y: -ry * 0.35), startRadius: 0, endRadius: rx * 1.4))
        if cane.baseAlpha < 1 { throughGlass(&g, face, .zero, sz, bend: 0.3, caustic: 0xffffff) }
        var inside = g
        inside.clip(to: face)
        let n = cane.petals
        if cane.star {
            let star = Path { p in
                for k in 0..<(n * 2) {
                    let a = Double(k) * Double.pi / Double(n) - Double.pi / 2
                    let r = k.isMultiple(of: 2) ? rx * 0.78 : rx * 0.42
                    let pt = CGPoint(x: r * CGFloat(cos(a)), y: r * CGFloat(sin(a)))
                    if k == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
                }
                p.closeSubpath()
            }
            inside.fill(star, with: .color(hex(cane.petal)))
            inside.stroke(star, with: .color(hex(cane.outline ?? 0xffffff)), lineWidth: 0.3)
            inside.fill(Path(ellipseIn: CGRect(x: -rx * 0.36, y: -rx * 0.36, width: rx * 0.72, height: rx * 0.72)), with: .color(hex(0xf6f2ea)))
        } else {
            for k in 0..<n {
                let a = Double(k) * 2 * Double.pi / Double(n) - Double.pi / 2
                var p = inside
                p.rotate(by: .radians(a))
                let petal = Path(ellipseIn: CGRect(x: rx * 0.2, y: -rx * 0.21, width: rx * 0.58, height: rx * 0.42))
                p.fill(petal, with: .color(hex(cane.petal)))
                if let o = cane.outline { p.stroke(petal, with: .color(hex(o)), lineWidth: 0.2) }
            }
        }
        let cr = rx * 0.28
        inside.fill(Path(ellipseIn: CGRect(x: -cr, y: -cr, width: cr * 2, height: cr * 2)), with: .color(hex(cane.center)))
        // Polished glass: a crescent of window light and a sparkle.
        var gl = inside
        gl.addFilter(.blur(radius: 0.2))
        gl.stroke(Path(ellipseIn: CGRect(x: -rx * 0.82, y: -ry * 0.82, width: rx * 1.64, height: ry * 1.64))
                    .trimmedPath(from: 0.55, to: 0.78), with: .color(.white.opacity(0.75)), lineWidth: 0.55)
        inside.fill(Path(ellipseIn: CGRect(x: -rx * 0.5, y: -ry * 0.62, width: 0.7, height: 0.6)), with: .color(.white.opacity(0.9)))
        g.stroke(face, with: .color(hex(cane.base).mix(.black, 0.45).opacity(0.5)), lineWidth: 0.22)
    }

    // MARK: Shapes

    static func heart(_ r: CGRect) -> Path {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: r.minX + r.width * x, y: r.minY + r.height * y) }
        return Path { path in
            path.move(to: p(0.5, 1))
            path.addCurve(to: p(0, 0.3), control1: p(0.2, 0.8), control2: p(0, 0.58))
            path.addCurve(to: p(0.5, 0.17), control1: p(0, 0.02), control2: p(0.4, -0.04))
            path.addCurve(to: p(1, 0.3), control1: p(0.6, -0.04), control2: p(1, 0.02))
            path.addCurve(to: p(0.5, 1), control1: p(1, 0.58), control2: p(0.8, 0.8))
            path.closeSubpath()
        }
    }

    /// A soft streak of colour inside a stone (mottling), in units of the bead's radius.
    struct Blob {
        var x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat, angle: Double, color: UInt32, opacity: Double
        init(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ angle: Double, _ color: UInt32, _ opacity: Double) {
            self.x = x; self.y = y; self.w = w; self.h = h; self.angle = angle; self.color = color; self.opacity = opacity
        }

        func draw(_ ctx: inout GraphicsContext, _ c: CGPoint, _ r: CGFloat) {
            var b = ctx
            b.translateBy(x: c.x + x * r, y: c.y + y * r)
            b.rotate(by: .degrees(angle))
            b.fill(Path(ellipseIn: CGRect(x: -w * r, y: -h * r, width: w * r * 2, height: h * r * 2)), with: .color(hex(color, opacity: opacity)))
        }
    }
}

private extension Color {
    /// This colour's RGB blended `amount` of the way towards `other`'s (sRGB), keeping this colour's opacity: tinting a
    /// translucent glass bead towards black or white must not make it opaque.
    func mix(_ other: Color, _ amount: Double) -> Color {
        let a = NSColor(self).usingColorSpace(.sRGB) ?? .black, b = NSColor(other).usingColorSpace(.sRGB) ?? .black
        func m(_ x: CGFloat, _ y: CGFloat) -> Double { Double(x + (y - x) * amount) }
        return Color(.sRGB, red: m(a.redComponent, b.redComponent), green: m(a.greenComponent, b.greenComponent),
                     blue: m(a.blueComponent, b.blueComponent), opacity: Double(a.alphaComponent))
    }
}
