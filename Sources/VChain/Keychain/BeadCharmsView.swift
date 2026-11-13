// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import VChainKit
import SwiftUI

/// The bead charms (decoration, no controls): a gold jump ring threaded on the split ring
/// at the ring point (or hanging from a short chain on it, `BeadCharms.Hang`) with three strands of beads on gold eye pins (BeadCharms in VChainKit has the
/// geometry, CharmsSwing the motion). The jump ring swings with the bunch; each strand hangs from it at
/// its own angle. The artwork never changes, so jump ring and strands are frozen Canvases that only get
/// moved and rotated. Light from the top left like the modules; the same in light and dark mode.
struct BeadCharmsView: View {
    /// The bunch's (jump ring's) angle, degrees (0 = straight down).
    var bunch: Double
    /// Each strand's angle (BeadCharms.Strand order), degrees.
    var angles: [Double]
    /// The ring point in the parent, points.
    var ringPoint: CGPoint
    var onTap: () -> Void
    /// Size and chain (`BeadCharms.hang` unless told otherwise).
    var hang = BeadCharms.hang
    @Environment(\.keychainDetached) private var detached

    var body: some View {
        let k = HardwareScale.app * hang.scale
        ZStack(alignment: .topLeading) {
            if hang.clasp {
                ClaspView(scale: HardwareScale.app).equatable()
                    .background(Rectangle().fill(Color.clickCatcher(detached)))
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onTap)
                    .hung(size: ClaspView.size(HardwareScale.app), hole: ClaspView.hole(HardwareScale.app), angle: bunch, at: ringPoint)
            }
            ChainView(links: hang.chainLinks, top: hang.chainTop, scale: HardwareScale.app).equatable()
                .background(Rectangle().fill(Color.clickCatcher(detached)))
                .contentShape(Rectangle())
                .onTapGesture(perform: onTap)
                .hung(size: ChainView.size(hang.chainLinks, top: hang.chainTop, HardwareScale.app),
                      hole: ChainView.hole(top: hang.chainTop, HardwareScale.app), angle: bunch, at: ringPoint)
            JumpRingView(scale: k).equatable()
                .background(Ellipse().fill(Color.clickCatcher(detached)))
                .contentShape(Ellipse())
                .onTapGesture(perform: onTap)
                .hung(size: JumpRingView.size(k), hole: JumpRingView.center(k), angle: bunch,
                      at: onBunch(CGPoint(x: 0, y: hang.jumpCenter)))
            // Back to front: the millefiori strand behind, the mushroom heart in front.
            ForEach([BeadCharms.Strand.millefiori, .tulip, .mushroom], id: \.self) { s in
                BeadStrandView(strand: s, scale: k).equatable()
                    .background(StrandOutline(strand: s, scale: k).fill(Color.clickCatcher(detached)))
                    .contentShape(StrandOutline(strand: s, scale: k))
                    .onTapGesture(perform: onTap)
                    .hung(size: BeadStrandView.size(s, k), hole: BeadStrandView.hole(s, k),
                          angle: angles[s.rawValue], at: onBunch(hang.pivot(s)))
            }
        }
    }

    /// A point of the bunch (keychain 1×, relative to the ring point at rest), swung with the jump ring.
    private func onBunch(_ p: CGPoint) -> CGPoint {
        let a = bunch * Double.pi / 180
        let c = CGFloat(cos(a)), sn = CGFloat(sin(a)), s = HardwareScale.app
        return CGPoint(x: ringPoint.x + (p.x * c - p.y * sn) * s, y: ringPoint.y + (p.x * sn + p.y * c) * s)
    }
}

// MARK: - Chain

/// The gold cable chain, hanging straight down from the ring point: oval links alternating face on
/// (the hole shows) and edge on (a slim bar), the edge-on ones passing through the face-on ones. The top
/// link hangs in the clasp's D-ring, or on the split ring like a module's hole (the ring's front piece covers its
/// upper crossing, the back piece runs under the lower one); its inside rests at `top`. Keychain 1× points ×
/// `scale`; nothing at all with 0 links.
struct ChainView: View, Equatable {
    var links: Int
    var top: CGFloat = BeadCharms.Chain.ringTop
    var scale: CGFloat

    private typealias C = BeadCharms.Chain
    /// The Canvas's top-left corner, relative to the ring point.
    private static func origin(_ top: CGFloat) -> CGPoint {
        CGPoint(x: -C.linkWidth / 2 - 1, y: C.linkCenter(0, top: top) - C.linkLength / 2 - 1)
    }
    static func size(_ links: Int, top: CGFloat = C.ringTop, _ s: CGFloat) -> CGSize {
        let h = links == 0 ? 1 : C.linkCenter(links - 1) - C.linkCenter(0) + C.linkLength + 3
        return CGSize(width: (C.linkWidth + 3) * s, height: h * s)
    }
    static func hole(top: CGFloat = C.ringTop, _ s: CGFloat) -> CGPoint {
        let o = origin(top)
        return CGPoint(x: -o.x * s, y: -o.y * s)
    }

    var body: some View {
        Canvas { ctx, _ in
            let o = Self.origin(top)
            ctx.scaleBy(x: scale, y: scale)
            ctx.translateBy(x: -o.x, y: -o.y)
            BeadArt.shadowed(&ctx) { l in
                // Face-on links first: each edge-on link passes through the ends of its neighbours.
                for i in 0..<links where C.isFaceOn(i) { Self.faceOn(&l, center: C.linkCenter(i, top: top)) }
                for i in 0..<links where !C.isFaceOn(i) { Self.edgeOn(&l, center: C.linkCenter(i, top: top)) }
            }
        }
        .frame(width: Self.size(links, top: top, scale).width, height: Self.size(links, top: top, scale).height)
        .allowsHitTesting(links > 0)
        .accessibilityHidden(true)
    }

    private static func faceOn(_ ctx: inout GraphicsContext, center y: CGFloat) {
        let w = C.linkWire
        let rect = CGRect(x: -C.linkWidth / 2 + w / 2, y: y - C.linkLength / 2 + w / 2, width: C.linkWidth - w, height: C.linkLength - w)
        BeadArt.gold(&ctx, Path(roundedRect: rect, cornerRadius: rect.width / 2, style: .continuous), width: w * 0.9)
    }

    private static func edgeOn(_ ctx: inout GraphicsContext, center y: CGFloat) {
        let w = C.linkWire * 1.3
        let bar = Path(roundedRect: CGRect(x: -w / 2, y: y - C.linkLength / 2, width: w, height: C.linkLength), cornerRadius: w / 2, style: .continuous)
        ctx.fill(bar, with: .color(hex(0x6e4a12)))
        ctx.fill(bar, shaded: .linearGradient(
            Gradient(stops: [.init(color: hex(0xfff2c2), location: 0), .init(color: hex(0xe2b955), location: 0.35),
                             .init(color: hex(0xa97a24), location: 0.8), .init(color: hex(0x8a6420), location: 1)]),
            startPoint: CGPoint(x: -w / 2, y: y), endPoint: CGPoint(x: w / 2, y: y)))
        // The slit between the link's two wires, seen edge on, and a catch-light down its left side.
        var slit = Path()
        slit.move(to: CGPoint(x: 0.05, y: y - C.linkLength / 2 + C.linkWire))
        slit.addLine(to: CGPoint(x: 0.05, y: y + C.linkLength / 2 - C.linkWire))
        ctx.stroke(slit, with: .color(hex(0x5a3c0e, opacity: 0.7)), lineWidth: 0.16)
        var shine = Path()
        shine.move(to: CGPoint(x: -w * 0.22, y: y - C.linkLength / 2 + 0.6))
        shine.addLine(to: CGPoint(x: -w * 0.22, y: y + C.linkLength / 2 - 0.6))
        ctx.stroke(shine, with: .color(.white.opacity(0.55)), lineWidth: 0.2)
        ctx.stroke(bar, with: .color(hex(0x6e4a12)), lineWidth: 0.15)
    }
}

// MARK: - Clasp

/// The gold lobster clasp hooked on the split ring (BeadCharms.Clasp has its measures): a stamped teardrop claw
/// with the spring gate down its right side and the gate's ribbed lever sticking out, a rivet below the opening,
/// a collar, the swivel barrel and a D-ring. The split ring runs through the claw's top (its front piece covers
/// the upper crossing like a module's hole). Keychain 1× points × `scale`.
struct ClaspView: View, Equatable {
    var scale: CGFloat

    private typealias K = BeadCharms.Clasp
    /// The Canvas's top-left corner, relative to the ring point (room for the lever and the shadow).
    private static let origin = CGPoint(x: -K.width / 2 - 1.5, y: K.top - 1.5)
    static func size(_ s: CGFloat) -> CGSize {
        // Left: the claw's half and a margin; right: room for the lever (its tip reaches about 10 × size from the centre).
        CGSize(width: (K.width / 2 + 1.5 + 11.5 * K.size) * s, height: (K.end + K.dWire - K.top + 4) * s)
    }
    static func hole(_ s: CGFloat) -> CGPoint { CGPoint(x: -origin.x * s, y: -origin.y * s) }

    var body: some View {
        Canvas { ctx, _ in
            ctx.scaleBy(x: scale, y: scale)
            ctx.translateBy(x: -Self.origin.x, y: -Self.origin.y)
            BeadArt.shadowed(&ctx) { l in Self.draw(&l) }
        }
        .frame(width: Self.size(scale).width, height: Self.size(scale).height)
        .accessibilityHidden(true)
    }

    private static func draw(_ ctx: inout GraphicsContext) {
        let u = K.size, t = K.top, half = K.width / 2, base = K.clawBase
        // The claw: a round head as wide as the claw, sides running down almost straight to a solid body, which
        // narrows in a concave sweep to the neck.
        let L = K.clawLength, head = CGPoint(x: 0, y: t + half), neck = K.collar.width / 2 + 0.2 * u
        let shoulder = t + 0.66 * L
        var outer = Path()
        outer.addArc(center: head, radius: half, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
        outer.addCurve(to: CGPoint(x: half * 0.86, y: shoulder), control1: CGPoint(x: half, y: head.y + 2.4 * u),
                       control2: CGPoint(x: half * 0.88, y: shoulder - 2.4 * u))
        outer.addCurve(to: CGPoint(x: neck, y: base), control1: CGPoint(x: half * 0.84, y: shoulder + 2.6 * u),
                       control2: CGPoint(x: neck + 0.4 * u, y: base - 1.6 * u))
        outer.addLine(to: CGPoint(x: -neck, y: base))
        outer.addCurve(to: CGPoint(x: -half * 0.86, y: shoulder), control1: CGPoint(x: -neck - 0.4 * u, y: base - 1.6 * u),
                       control2: CGPoint(x: -half * 0.84, y: shoulder + 2.6 * u))
        outer.addCurve(to: CGPoint(x: -half, y: head.y), control1: CGPoint(x: -half * 0.88, y: shoulder - 2.4 * u),
                       control2: CGPoint(x: -half, y: head.y + 2.4 * u))
        outer.closeSubpath()
        // The opening: a teardrop, round under the head and pointing down into the body, in its upper half.
        let b = K.band, ih = half - b, tip = t + 0.6 * L
        var inner = Path()
        inner.addArc(center: head, radius: ih, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
        inner.addCurve(to: CGPoint(x: 0, y: tip), control1: CGPoint(x: ih, y: head.y + 3.6 * u), control2: CGPoint(x: ih * 0.55, y: tip - 1.4 * u))
        inner.addCurve(to: CGPoint(x: -ih, y: head.y), control1: CGPoint(x: -ih * 0.55, y: tip - 1.4 * u), control2: CGPoint(x: -ih, y: head.y + 3.6 * u))
        inner.closeSubpath()
        var claw = outer
        claw.addPath(inner)

        // The gate's lever, behind the body's right side at the rivet: a tab sticking out to the right, angled a
        // little up and widening towards its end.
        let pivot = CGPoint(x: half * 0.7, y: t + 0.69 * L)
        let turn = CGAffineTransform(translationX: pivot.x, y: pivot.y).rotated(by: -0.28).translatedBy(x: -pivot.x, y: -pivot.y)
        var lever = Path()
        lever.move(to: CGPoint(x: pivot.x, y: pivot.y - 1.1 * u))
        lever.addLine(to: CGPoint(x: pivot.x + 5.2 * u, y: pivot.y - 1.5 * u))
        lever.addQuadCurve(to: CGPoint(x: pivot.x + 5.2 * u, y: pivot.y + 1.3 * u), control: CGPoint(x: pivot.x + 6.4 * u, y: pivot.y - 0.1 * u))
        lever.addLine(to: CGPoint(x: pivot.x, y: pivot.y + 1.1 * u))
        lever.closeSubpath()
        BeadArt.goldSolid(&ctx, lever.applying(turn))

        // Collar, swivel barrel (with its groove) and the D-ring under it.
        let collar = CGRect(x: -K.collar.width / 2, y: base - 0.4 * u, width: K.collar.width, height: K.collar.height + 0.6 * u)
        BeadArt.goldSolid(&ctx, Path(roundedRect: collar, cornerRadius: 0.4 * u), across: true)
        var d = Path()
        let dy = K.dTop + K.dWire / 2, r = K.dHalf
        d.move(to: CGPoint(x: -r, y: dy))
        d.addLine(to: CGPoint(x: r, y: dy))
        d.addLine(to: CGPoint(x: r, y: K.dRound))
        d.addArc(center: CGPoint(x: 0, y: K.dRound), radius: r, startAngle: .degrees(0), endAngle: .degrees(180), clockwise: false)
        d.closeSubpath()
        BeadArt.gold(&ctx, d, width: K.dWire)
        let barrel = CGRect(x: -K.barrel.width / 2, y: K.barrelTop, width: K.barrel.width, height: K.barrel.height)
        BeadArt.goldSolid(&ctx, Path(roundedRect: barrel, cornerRadius: 0.9 * u), across: true)
        var groove = Path()
        groove.move(to: CGPoint(x: barrel.minX + 0.3 * u, y: barrel.midY)); groove.addLine(to: CGPoint(x: barrel.maxX - 0.3 * u, y: barrel.midY))
        ctx.stroke(groove, with: .color(hex(0x6e4a12, opacity: 0.7)), lineWidth: 0.25 * u)

        // The claw on top, its gate split off down the right side, and the rivet.
        BeadArt.goldSolid(&ctx, claw, eoFill: true)
        // The spring gate: a cut down the band's left side, from high on the head to the opening's point.
        let mid = (half + ih) / 2
        var gate = Path()
        gate.move(to: CGPoint(x: head.x + mid * CGFloat(cos(-2.45)), y: head.y + mid * CGFloat(sin(-2.45))))
        gate.addArc(center: head, radius: mid, startAngle: .radians(-2.45), endAngle: .degrees(180), clockwise: true)
        gate.addCurve(to: CGPoint(x: -0.5 * u, y: tip + 0.9 * u), control1: CGPoint(x: -mid, y: head.y + 2.6 * u),
                      control2: CGPoint(x: -mid * 0.5, y: tip - 0.4 * u))
        ctx.stroke(gate, with: .color(hex(0x5a3c0e, opacity: 0.75)), lineWidth: 0.22 * u)
        let rivet = CGRect(x: -0.9 * u, y: t + 0.72 * L - 0.9 * u, width: 1.8 * u, height: 1.8 * u)
        ctx.fill(Path(ellipseIn: rivet), with: .color(hex(0x6e4a12)))
        ctx.fill(Path(ellipseIn: rivet.insetBy(dx: 0.25 * u, dy: 0.25 * u).offsetBy(dx: -0.1 * u, dy: -0.1 * u)),
                 shaded: .radialGradient(Gradient(colors: [hex(0xfff2c2), hex(0xb88a2e)]),
                                         center: CGPoint(x: rivet.midX - 0.25 * u, y: rivet.midY - 0.25 * u), startRadius: 0, endRadius: 0.7 * u))
    }
}

// MARK: - Jump ring

/// The gold jump ring, seen a little from the side; the split ring runs through its top (the ring's front
/// piece covers the upper crossing, its back piece passes under the lower one).
struct JumpRingView: View, Equatable {
    var scale: CGFloat

    private static let half: CGFloat = BeadCharms.jumpRadius + 1.5
    static func size(_ s: CGFloat) -> CGSize { CGSize(width: half * 2 * s, height: half * 2 * s) }
    static func center(_ s: CGFloat) -> CGPoint { CGPoint(x: half * s, y: half * s) }

    var body: some View {
        Canvas { ctx, _ in
            ctx.scaleBy(x: scale, y: scale)
            ctx.translateBy(x: Self.half, y: Self.half)
            let r = BeadCharms.jumpRadius
            let ring = Path(ellipseIn: CGRect(x: -r * 0.82, y: -r, width: r * 1.64, height: r * 2))
            BeadArt.shadowed(&ctx) { l in
                BeadArt.gold(&l, ring, width: 0.62)
                // The cut where the ring was opened and closed again.
                var cut = Path()
                cut.move(to: CGPoint(x: r * 0.66, y: -r * 0.52)); cut.addLine(to: CGPoint(x: r * 0.9, y: -r * 0.42))
                l.stroke(cut, with: .color(hex(0x5a3c0e)), lineWidth: 0.18)
            }
        }
        .frame(width: Self.size(scale).width, height: Self.size(scale).height)
        .accessibilityHidden(true)
    }
}

// MARK: - Strand

/// One strand: top loop, the beads on the gold pin, bottom loop. Its pivot (the top loop's centre) is `hole`.
struct BeadStrandView: View, Equatable {
    var strand: BeadCharms.Strand
    var scale: CGFloat = HardwareScale.app

    static func size(_ s: BeadCharms.Strand, _ scale: CGFloat) -> CGSize {
        let b = BeadCharms.bounds(s)
        return CGSize(width: b.width * scale, height: b.height * scale)
    }

    static func hole(_ s: BeadCharms.Strand, _ scale: CGFloat) -> CGPoint {
        let b = BeadCharms.bounds(s)
        return CGPoint(x: -b.minX * scale, y: -b.minY * scale)
    }

    var body: some View {
        let b = BeadCharms.bounds(strand)
        Canvas { ctx, _ in
            ctx.scaleBy(x: scale, y: scale)
            ctx.translateBy(x: -b.minX, y: -b.minY)
            BeadArt.strand(strand, &ctx)
        }
        .frame(width: b.width * scale, height: b.height * scale)
        .accessibilityHidden(true)
    }
}

/// The beads and loops only (not the strand's bounding box), so clicks next to a strand reach the
/// module under it.
private struct StrandOutline: Shape {
    var strand: BeadCharms.Strand
    var scale: CGFloat

    func path(in _: CGRect) -> Path {
        let b = BeadCharms.bounds(strand)
        var p = Path()
        let r = BeadCharms.loopRadius
        p.addRect(CGRect(x: -r, y: -r, width: r * 2, height: BeadCharms.length(strand) + r))
        for bead in BeadCharms.stack(strand) {
            p.addRect(CGRect(x: -bead.size.width / 2, y: bead.center.y - bead.size.height / 2, width: bead.size.width, height: bead.size.height))
        }
        return p.applying(CGAffineTransform(translationX: -b.minX, y: -b.minY).concatenating(CGAffineTransform(scaleX: scale, y: scale)))
    }
}
