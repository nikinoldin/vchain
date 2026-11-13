// SPDX-License-Identifier: GPL-3.0-or-later
import VChainKit
import SwiftUI

/// MIDI OUT on the side of the MIDI strip and the Energy module: a 3.5 mm socket in the edge with a right-angle plug in it whose short braided cable runs down along
/// the edge and tucks behind the module. No LED, no label: the cable is the indicator, and while that module's
/// output is off the socket is empty. Clicking the plug unplugs it or plugs it back in (`MIDIOutHit`).
///
/// Drawn pointing right out of an edge: the local origin is on the edge at the socket's axis (1× units × `scale`),
/// +y runs along the edge. The plug's head is centred on the axis; the cable leaves it along the edge through a
/// ribbed strain relief and swoops in one smooth arc to `tuck`, a point under the module body near its bottom, where
/// it arrives travelling along `arrive` (both in the part's own coordinates; the caller derives them from the world's
/// down at the module's rest angle, `gravity(hangDegrees:mirrored:)`). Place the part *behind* the module body, which
/// hides the cable's end; mirror it with `scaleEffect(x: -1, anchor: .topLeading)` for a left edge (and give `tuck`
/// and `arrive` in the mirrored coordinates). Its frame is a zero-size point at the origin.
struct MIDIOutJack: View {
    var plugged: Bool
    /// Hovering (`PlugMotion.peek`, 0…1): a plugged plug eases a little out of the socket, showing a sliver of its pin; an
    /// empty socket gets a soft highlight.
    var peek: Double = 0
    /// Where the cable ends, under the module body (hidden).
    var tuck: CGPoint
    /// The cable's direction of travel as it disappears (unit length).
    var arrive: CGVector
    /// Lengths of the arc's two handles (out of the strain relief, into `tuck`): longer = a looser, deeper swoop.
    var startHandle: CGFloat = 7
    var endHandle: CGFloat = 7
    var braid: Braid
    var scale: CGFloat = HardwareScale.app

    @Environment(\.colorScheme) private var scheme

    /// The cable's woven fabric jacket.
    enum Braid {
        /// Black and yellow strands woven alternately (the Energy module).
        case blackYellow
        /// All-black braid: black and dark-grey strands (the MIDI strip).
        case black
    }

    /// World down for a module drawn turned `hangDegrees` (SwiftUI rotation), in a part `mirrored` for a left edge.
    static func gravity(hangDegrees: Double, mirrored: Bool) -> CGVector {
        let a = hangDegrees * .pi / 180
        return CGVector(dx: (mirrored ? -1 : 1) * sin(a), dy: cos(a))
    }

    var body: some View {
        let bounds = cablePath.boundingRect.union(CGRect(x: -2, y: -7, width: 15, height: 20)).insetBy(dx: -3, dy: -3)
        PartCanvas(size: .zero, bleed: EdgeInsets(top: -bounds.minY, leading: -bounds.minX, bottom: bounds.maxY, trailing: bounds.maxX),
                   scale: scale) { ctx in
            let out = CGFloat(PlugMotion.peekUnits * peek)
            if plugged {
                // The cable is fixed to the plug, so it comes along (its far end is hidden behind the module anyway).
                var c = ctx
                c.translateBy(x: out, y: 0)
                drawCable(&c)
            }
            if !plugged && peek > 0 {
                // An empty socket under the pointer: a soft halo round the nut (light on dark plastic, a shade on light).
                var glow = ctx
                glow.addFilter(.blur(radius: 1.1))
                let halo = Path(roundedRect: CGRect(x: -0.3, y: -5.3, width: 4.4, height: 10.6), cornerRadius: 1.6)
                glow.stroke(halo, with: .color(scheme == .dark ? .white.opacity(0.55 * peek) : hex(0x2a2620).opacity(0.45 * peek)),
                            lineWidth: 1.2)
            }
            socket(&ctx)
            if plugged {
                if out > 0.05 { pin(&ctx, exposed: out) }
                var p = ctx
                p.translateBy(x: out, y: 0)
                plug(&p)
            }
        }
        .frame(width: 0, height: 0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private static let chrome = Gradient(stops: [.init(color: hex(0xf6f7f8), location: 0), .init(color: hex(0xb4b8bd), location: 0.35),
                                                 .init(color: hex(0x7d8287), location: 0.62), .init(color: hex(0xd9dcdf), location: 1)])
    private static let outline = Color.black.opacity(0.55)

    /// Small, sharp contact shadow (no soft blob).
    private func shadow(_ ctx: GraphicsContext, _ path: Path) {
        var s = ctx
        s.addFilter(.blur(radius: 0.35))
        s.fill(path.offsetBy(dx: 0.25, dy: 0.6), with: .color(.black.opacity(0.35)))
    }

    /// The socket's knurled chrome nut on a thin black washer.
    private func socket(_ ctx: inout GraphicsContext) {
        ctx.fill(Path(roundedRect: CGRect(x: -0.4, y: -4.8, width: 1.1, height: 9.6), cornerRadius: 0.35), with: .color(hex(0x161617)))
        let rect = CGRect(x: 0.7, y: -4, width: 2, height: 8)
        let nut = UnevenRoundedRectangle(topLeadingRadius: 0.3, bottomLeadingRadius: 0.3, bottomTrailingRadius: 0.7, topTrailingRadius: 0.7)
            .path(in: rect)
        shadow(ctx, nut)
        ctx.fill(nut, shaded: .linearGradient(Self.chrome, startPoint: CGPoint(x: 0, y: rect.minY), endPoint: CGPoint(x: 0, y: rect.maxY)))
        var knurl = ctx
        knurl.clip(to: nut)
        var y = rect.minY + 0.6
        while y < rect.maxY - 0.3 {
            knurl.fill(Path(CGRect(x: rect.minX, y: y, width: rect.width, height: 0.4)), with: .color(.black.opacity(0.28)))
            y += 1.1
        }
        ctx.stroke(nut, with: .color(Self.outline), lineWidth: 0.25)
    }

    /// The plug's 3.5 mm pin where it shows between the socket nut and the pulled-out plug: a chrome barrel (as thick
    /// as a real 3.5 mm pin) with the black insulator rings between sleeve, ring and tip.
    private func pin(_ ctx: inout GraphicsContext, exposed: CGFloat) {
        let rect = CGRect(x: 2.4, y: -1.75, width: 0.9 + exposed, height: 3.5)
        ctx.fill(Path(rect), shaded: .linearGradient(Self.chrome, startPoint: CGPoint(x: 0, y: rect.minY), endPoint: CGPoint(x: 0, y: rect.maxY)))
        var rings = ctx
        rings.clip(to: Path(rect))
        // Sleeve nearest the plug, then a ring and the tip going into the socket: insulators 1.2 and 2.4 units from the plug.
        for d in [1.2, 2.4] as [CGFloat] {
            let x = rect.maxX - d
            rings.fill(Path(CGRect(x: x, y: rect.minY, width: 0.35, height: rect.height)), with: .color(hex(0x141415)))
        }
        ctx.stroke(Path(rect), with: .color(Self.outline), lineWidth: 0.2)
    }

    /// Right-angle plug: a moulded black head centred on the axis, almost flush against the socket nut (only a
    /// hairline of the full-thickness barrel shows, no thin neck), with a lit top edge and a parting line, and the
    /// ribbed strain relief tapering down out of its lower side.
    private func plug(_ ctx: inout GraphicsContext) {
        // The plug's barrel: as thick as a real 3.5 mm barrel against the nut, and barely showing.
        let sleeve = CGRect(x: 2.7, y: -3, width: 0.45, height: 6)
        ctx.fill(Path(sleeve), shaded: .linearGradient(Self.chrome, startPoint: CGPoint(x: 0, y: sleeve.minY), endPoint: CGPoint(x: 0, y: sleeve.maxY)))
        ctx.stroke(Path(sleeve), with: .color(Self.outline), lineWidth: 0.25)

        // Strain relief: four ribs stepping in as it goes down, under the head.
        let ribs: [(CGFloat, CGFloat, CGFloat)] = [(4.9, 2.1, 1.6), (6.5, 1.85, 1.5), (8, 1.6, 1.45), (9.45, 1.35, 1.4)]
        let cx: CGFloat = 6.9
        for (y, half, h) in ribs.reversed() {
            let rib = Path(roundedRect: CGRect(x: cx - half, y: y, width: half * 2, height: h), cornerRadius: 0.45)
            ctx.fill(rib, shaded: .linearGradient(Gradient(colors: [hex(0x3c3c3e), hex(0x18181a), hex(0x0e0e0f)]),
                                                startPoint: CGPoint(x: cx - half, y: 0), endPoint: CGPoint(x: cx + half, y: 0)))
            ctx.stroke(rib, with: .color(Self.outline), lineWidth: 0.2)
            ctx.fill(Path(CGRect(x: cx - half + 0.35, y: y + 0.2, width: 0.35, height: h - 0.4)), with: .color(.white.opacity(0.2)))
        }

        // Head.
        let head = CGRect(x: 3.05, y: -5, width: 7.8, height: 10.2)
        let body = Path(roundedRect: head, cornerRadius: 1.7, style: .continuous)
        shadow(ctx, body)
        ctx.fill(body, shaded: .linearGradient(
            Gradient(stops: [.init(color: hex(0x55555a), location: 0), .init(color: hex(0x2a2a2d), location: 0.3),
                             .init(color: hex(0x161618), location: 0.75), .init(color: hex(0x0c0c0d), location: 1)]),
            startPoint: CGPoint(x: head.minX, y: head.minY), endPoint: CGPoint(x: head.maxX, y: head.maxY)))
        var face = ctx
        face.clip(to: body)
        // Lit top and left edges, a darker bottom edge, and the mould's parting line along the axis.
        face.fill(Path(CGRect(x: head.minX, y: head.minY, width: head.width, height: 0.5)), with: .color(.white.opacity(0.32)))
        face.fill(Path(CGRect(x: head.minX, y: head.minY, width: 0.45, height: head.height)), with: .color(.white.opacity(0.18)))
        face.fill(Path(CGRect(x: head.minX, y: head.maxY - 0.6, width: head.width, height: 0.6)), with: .color(.black.opacity(0.45)))
        face.fill(Path(CGRect(x: head.minX + 1.2, y: -0.15, width: head.width - 2.4, height: 0.3)), with: .color(.black.opacity(0.35)))
        face.fill(Path(CGRect(x: head.minX + 1.2, y: 0.15, width: head.width - 2.4, height: 0.2)), with: .color(.white.opacity(0.08)))
        ctx.stroke(body, with: .color(Self.outline), lineWidth: 0.3)
    }

    /// Where the part is drawn, for its module's hit area (`ModuleOutline`), in its own units: the socket's nut and, while
    /// plugged, the plug's head and strain relief (pulled out by `peek`) and the cable a little wider than drawn.
    var outline: Path {
        let socket = Path(CGRect(x: -0.5, y: -5, width: 3.5, height: 10))
        guard plugged else { return socket }
        let out = CGFloat(PlugMotion.peekUnits * peek)
        return socket.union(Path(CGRect(x: 2.5, y: -5, width: 8.5 + out, height: 17)))
            .union(cablePath.strokedPath(StrokeStyle(lineWidth: 4.5, lineCap: .round)).offsetBy(dx: out, dy: 0))
    }

    /// The cable's centre line: one cubic Bézier out of the strain relief (tangent along the edge) into `tuck`
    /// (tangent `arrive`). A single cubic has continuous curvature, so the cable hangs as one smooth arc with no bumps.
    private var segments: [(CGPoint, CGPoint, CGPoint, CGPoint)] {
        let s = CGPoint(x: 6.9, y: 10.6)
        return [(s, CGPoint(x: s.x, y: s.y + startHandle),
                 CGPoint(x: tuck.x - arrive.dx * endHandle, y: tuck.y - arrive.dy * endHandle), tuck)]
    }

    private var cablePath: Path {
        Path { p in
            for (i, (a, c1, c2, b)) in segments.enumerated() {
                if i == 0 { p.move(to: a) }
                p.addCurve(to: b, control1: c1, control2: c2)
            }
        }
    }

    /// Points along the centre line every `step` units (by arc length), each with its unit tangent.
    private func samples(every step: CGFloat) -> [(CGPoint, CGVector)] {
        var dense: [CGPoint] = []
        for (a, c1, c2, b) in segments {
            for k in 0...40 where !(k == 0 && !dense.isEmpty) {
                let t = CGFloat(k) / 40, u = 1 - t
                let x = u * u * u * a.x + 3 * u * u * t * c1.x + 3 * u * t * t * c2.x + t * t * t * b.x
                let y = u * u * u * a.y + 3 * u * u * t * c1.y + 3 * u * t * t * c2.y + t * t * t * b.y
                dense.append(CGPoint(x: x, y: y))
            }
        }
        var out: [(CGPoint, CGVector)] = []
        var carry: CGFloat = 0
        for i in 1..<dense.count {
            let a = dense[i - 1], b = dense[i]
            let len = hypot(b.x - a.x, b.y - a.y)
            guard len > 0 else { continue }
            let t = CGVector(dx: (b.x - a.x) / len, dy: (b.y - a.y) / len)
            var d = step - carry
            while d <= len {
                out.append((CGPoint(x: a.x + t.dx * d, y: a.y + t.dy * d), t))
                d += step
            }
            carry = len - (d - step)
        }
        return out
    }

    /// The cable: a woven braid (a herringbone of strands across the tube, clipped to it, with a soft fabric sheen).
    /// Same thickness all along.
    private func drawCable(_ ctx: inout GraphicsContext) {
        let path = cablePath
        let width: CGFloat = 3.0
        let round = StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round)
        ctx.stroke(path, with: .color(Self.outline), style: StrokeStyle(lineWidth: width + 0.5, lineCap: .round, lineJoin: .round))
        ctx.stroke(path, with: .color(hex(0x0f0f10)), style: round)
        var weave = ctx
        weave.clip(to: path.strokedPath(round))
        let half = width / 2 + 0.2, step: CGFloat = 0.85
        for (i, (p, t)) in samples(every: step).enumerated() {
            let n = CGVector(dx: -t.dy, dy: t.dx)
            // A chevron: both edges sweep forward to the centre line half a step on (the herringbone).
            let tip = CGPoint(x: p.x + t.dx * step * 0.9, y: p.y + t.dy * step * 0.9)
            let colour: Color
            switch braid {
            case .blackYellow: colour = i % 2 == 0 ? hex(0x2b2b2d) : hex(0xd9a812)
            case .black: colour = i % 2 == 0 ? hex(0x38383b) : hex(0x1a1a1c)
            }
            for side in [-1.0, 1.0] as [CGFloat] {
                let edge = CGPoint(x: p.x + n.dx * half * side, y: p.y + n.dy * half * side)
                weave.stroke(Path { q in q.move(to: edge); q.addLine(to: tip) }, with: .color(colour),
                             style: StrokeStyle(lineWidth: 0.42, lineCap: .round))
            }
        }
        // Fabric sheen: a soft light band on the lit side, a little shade on the other.
        var sheen = weave
        sheen.translateBy(x: -0.5, y: -0.45)
        sheen.stroke(path, with: .color(.white.opacity(0.22)), style: StrokeStyle(lineWidth: 0.9, lineCap: .round))
        var shade = weave
        shade.translateBy(x: 0.7, y: 0.65)
        shade.stroke(path, with: .color(.black.opacity(0.35)), style: StrokeStyle(lineWidth: 1, lineCap: .round))
    }
}

/// The click target over a MIDI OUT plug and the top of its cable (both modules): clicking unplugs or plugs back in.
/// `origin` is the socket's axis on a LEFT edge (the part mirrored), in points; only live while the module is in front.
struct MIDIOutHit: View {
    var plugged: Bool
    var isFront: Bool
    var origin: CGPoint
    var unit: CGFloat
    var onPlug: () -> Void
    /// The pointer entering or leaving (the plug eases out a little, an empty socket lights).
    var onHover: (Bool) -> Void = { _ in }

    var body: some View {
        // In the part's coordinates: the plug's head and nut with room outward (x -1…17, 19 units = 28 pt) and the
        // cable's first stretch below it (y -7…19).
        Color.clear
            .frame(width: 19 * unit, height: 26 * unit)
            .moduleControl(isFront: isFront, label: plugged ? "Unplug MIDI out" : "Plug in MIDI out")
            .accessibilityAddTraits(.isButton)
            .onTapGesture(perform: onPlug)
            .onHover { onHover(isFront && $0) }
            .offset(x: origin.x - 18 * unit, y: origin.y - 7 * unit)
    }
}

extension MIDIOutJack {
    /// `outline` where the module puts the part: mirrored for a left edge (`scaleEffect(x: -1)`) at `origin` (points).
    func outline(mirroredAt origin: CGPoint, unit: CGFloat) -> Path {
        outline.applying(CGAffineTransform(a: -unit, b: 0, c: 0, d: unit, tx: origin.x, ty: origin.y))
    }
}
