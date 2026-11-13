// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI
import VChainKit

// Reusable hardware parts for the keychain modules. Every part draws in its design units, multiplied by a scale:
// `HardwareScale.app` (1.5) for the BPM tag / MIDI strip parts, designed at 1×, and
// `HardwareScale.energy` (1.5 / 1.9) for the Energy parts, designed in SVG units at 1.9 units per 1× point.
// A part's frame is its body (the screw head, the switch slot, the barrel…); shadows, printed
// labels, the plug and cable spill outside it, so modules can place parts by their design
// left/top numbers × scale.

enum HardwareScale {
    /// The app draws everything at 1.5× of the 1× design sizes, times `zoom`.
    static let app: CGFloat = 1.5 * zoom
    /// `-keychainZoom <n>` (1…4, launch argument only, never saved): the whole keychain drawn n× as large, still sharp
    /// (it's all vector drawing), for close-up screen recordings. `open build/vChain.app --args -keychainZoom 2.5`;
    /// the menu bar item stays its normal size.
    static let zoom: CGFloat = {
        let z = UserDefaults.standard.double(forKey: "keychainZoom")
        return z > 0 ? CGFloat(min(max(z, 1), 4)) : 1
    }()
    /// Energy design SVG units → points: 1.9 SVG units per 1× point, then 1.5×.
    static let energy: CGFloat = app / KeyringGeometry.energyUnitsPerPoint
}

/// Concentric corner radius for a layer inset inside another (inner = outer − inset), never below 2 pt.
func innerRadius(outer: CGFloat, inset: CGFloat) -> CGFloat {
    max(2, outer - inset)
}

// MARK: - Keyring holes

/// Chrome eyelet around a keyring hole (BPM tag, MIDI end cap). The frame is the eyelet
/// (`outer` radius, 4.5 at 1×); the centre is cut out, so whatever is behind the module shows through.
struct Grommet: View {
    /// The tag's and the strip's keyring hole (1× units): the opening drilled through the plate and the grommet's rim.
    static let opening: CGFloat = 2.3, outer: CGFloat = 4.5

    /// Radius of the see-through opening, in points (2.3 at 1×).
    var opening: CGFloat
    /// Outer radius of the eyelet, in points.
    var outer: CGFloat = 4.5 * HardwareScale.app

    var body: some View {
        // Drawn in points; the design's sub-point details scale with the eyelet.
        let u = outer / 4.5
        PartCanvas(size: CGSize(width: outer * 2, height: outer * 2), bleed: 1.5 * u, scale: 1) { ctx in
            let c = CGPoint(x: outer, y: outer)
            func disc(_ r: CGFloat, dy: CGFloat = 0) -> Path {
                Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r + dy, width: r * 2, height: r * 2))
            }
            // The open centre lets the backdrop show through (the bore's shadow keeps only a soft rim).
            ctx.clipOut(disc(opening - 0.6 * u))
            // 0 .6px .6px rgba(255,255,255,.7): catch-light where the eyelet meets the plate below
            var light = ctx
            light.addFilter(.blur(radius: 0.3 * u))
            light.fill(disc(outer, dy: 0.6 * u), with: .color(.white.opacity(0.7)))
            // 0 0 0 .5px rgba(0,0,0,.4)
            ctx.fill(disc(outer + 0.5 * u), with: .color(.black.opacity(0.4)))
            var ring = Path()
            ring.addPath(disc(outer))
            ring.addPath(disc(opening))
            // conic-gradient(from 200deg, …): CSS starts at 12 o'clock, SwiftUI at 3 o'clock
            ctx.fill(ring, with: .conicGradient(
                Gradient(colors: [0xf7f8f9, 0x8d9196, 0xe9ebed, 0x6c7075, 0xf2f3f4, 0x9a9ea3, 0xf7f8f9].map { hex($0) }),
                center: c, angle: .degrees(110)), style: FillStyle(eoFill: true))
            // inset 0 0 .8px rgba(0,0,0,.5) on the outer edge
            ctx.stroke(disc(outer - 0.2 * u), with: .color(.black.opacity(0.35)), lineWidth: 0.4 * u)
            // the dark lip of the hole: #2a2c2f from opening + .1 to + .4
            ctx.stroke(disc(opening + 0.25 * u), with: .color(hex(0x2a2c2f)), lineWidth: 0.4 * u)
            // ::after inset .4px .9px 1.2px rgba(0,0,0,.65): shadow inside the bore, heavier at the top
            var bore = ctx
            bore.clip(to: disc(opening + 0.4 * u))
            bore.addFilter(.blur(radius: 0.6 * u))
            var shadow = Path(CGRect(x: c.x - outer * 2, y: c.y - outer * 2, width: outer * 4, height: outer * 4))
            shadow.addPath(Path(ellipseIn: CGRect(x: c.x - opening + 0.4 * u, y: c.y - opening + 0.9 * u, width: opening * 2, height: opening * 2)))
            bore.fill(shadow, with: .color(.black.opacity(0.65)), style: FillStyle(eoFill: true))
        }
        .accessibilityHidden(true)
    }
}

/// Energy keyring hole: a chrome washer in the same dark cutout ring as the TE keys, with a
/// see-through opening. `outer` is the cutout's radius (= TE key radius + cutout gap, 17.2 SVG units).
struct Washer: View {
    var outer: CGFloat = 17.2 * HardwareScale.energy
    /// Radius of the see-through opening, in points (6.0 SVG units).
    var opening: CGFloat = 6.0 * HardwareScale.energy

    var body: some View {
        let u = outer / 17.2
        PartCanvas(size: CGSize(width: outer * 2, height: outer * 2), bleed: 0, scale: 1) { ctx in
            let c = CGPoint(x: outer, y: outer)
            func disc(_ r: CGFloat) -> Path { Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)) }
            ctx.clipOut(disc(opening))
            ctx.fill(disc(17.2 * u), with: .color(.black.opacity(0.55)))
            let chrome = disc(15.0 * u)
            ctx.fill(chrome, shaded: .linearGradient(
                Gradient(stops: [.init(color: hex(0xffffff), location: 0), .init(color: hex(0xa3a8ae), location: 0.3),
                                 .init(color: hex(0xf1f2f4), location: 0.55), .init(color: hex(0x767b81), location: 0.8),
                                 .init(color: hex(0xd6d9dc), location: 1)]),
                startPoint: CGPoint(x: c.x - 15 * u, y: c.y - 15 * u), endPoint: CGPoint(x: c.x + 15 * u, y: c.y + 15 * u)))
            for r in [11.5, 8.6] {
                ctx.stroke(disc(r * u), with: .color(.black.opacity(0.18)), lineWidth: 0.5 * u)
            }
            ctx.stroke(disc(7.3 * u), with: .color(.white.opacity(0.6)), lineWidth: 0.7 * u)
            ctx.stroke(disc(6.4 * u), with: .color(.black.opacity(0.6)), lineWidth: 1 * u)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Switches and keys

/// The BPM tag's rocker switch seen from the side (14 × 22 at 1×): a curved paddle in a flange.
/// On: the lower end proud with the orange mark; off: flipped, white mark. The "I"/"O" marks are
/// engraved on the faceplate, so the module draws them.
struct RockerSide: View {
    var isOn: Bool
    var scale: CGFloat = HardwareScale.app

    var body: some View {
        PartCanvas(size: CGSize(width: 14, height: 22), bleed: 0, scale: scale) { ctx in
            ctx.fill(Path(roundedRect: CGRect(x: 3.6, y: 1, width: 1.8, height: 20), cornerRadius: 0.5), with: .color(hex(0x1a1a1b)))
            var pad = ctx
            if !isOn {  // scale(1,-1) about (7, 11)
                pad.translateBy(x: 0, y: 22)
                pad.scaleBy(x: 1, y: -1)
            }
            let paddle = Path { p in
                p.move(to: CGPoint(x: 5.2, y: 2.2))
                p.addLine(to: CGPoint(x: 6.6, y: 2.2))
                p.addQuadCurve(to: CGPoint(x: 7.4, y: 11), control: CGPoint(x: 8.2, y: 7))
                p.addQuadCurve(to: CGPoint(x: 10.6, y: 19.6), control: CGPoint(x: 7.6, y: 15))
                p.addLine(to: CGPoint(x: 5.2, y: 19.6))
                p.closeSubpath()
            }
            pad.fill(paddle, shaded: .linearGradient(
                Gradient(stops: [.init(color: hex(0x0d0d0e), location: 0), .init(color: hex(0x3b3b3e), location: 0.55),
                                 .init(color: hex(0x1b1b1c), location: 1)]),
                startPoint: CGPoint(x: 5.2, y: 0), endPoint: CGPoint(x: 10.6, y: 0)))
            let edge = Path { p in
                p.move(to: CGPoint(x: 6.6, y: 2.4))
                p.addQuadCurve(to: CGPoint(x: 7.3, y: 11), control: CGPoint(x: 8.1, y: 7))
                p.addQuadCurve(to: CGPoint(x: 10.4, y: 19.3), control: CGPoint(x: 7.5, y: 15))
            }
            pad.stroke(edge, with: .color(.white.opacity(0.35)), lineWidth: 0.45)
            var mark = pad
            mark.translateBy(x: 8.8, y: 16.7)
            mark.rotate(by: .degrees(-30))
            mark.fill(Path(roundedRect: CGRect(x: -0.4, y: -1.1, width: 0.9, height: 2.2), cornerRadius: 0.3),
                      with: .color(isOn ? hex(0xff5a1f) : hex(0xe9e9e9)))
        }
        .accessibilityHidden(true)
    }
}

/// MIDI strip slide switch: an orange ridged knob in a dark 6 × 17 slot (1×), "I" and "O" printed to
/// its right. On: knob up, orange; off: knob down, grey.
struct SlideSwitch: View {
    var isOn: Bool
    var scale: CGFloat = HardwareScale.app
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let print = scheme == .dark ? hex(0xa7a59f) : hex(0x6e695f)
        PartCanvas(size: CGSize(width: 6, height: 17), bleed: EdgeInsets(top: 1, leading: 1, bottom: 2, trailing: 6), scale: scale) { ctx in
            let slot = Path(roundedRect: CGRect(x: 0, y: 0, width: 6, height: 17), cornerRadius: 3)
            // 0 .6px 0 rgba(255,255,255,.5): moulded lip under the slot
            ctx.fill(slot.offsetBy(dx: 0, dy: 0.6), with: .color(.white.opacity(0.5)))
            ctx.fill(slot, with: .color(hex(0x1d1d1f)))
            ctx.insetShadow(in: slot, dy: 1, blur: 2, color: .black.opacity(0.8))
            let knob = CGRect(x: 0.6, y: isOn ? 0.8 : 8.2, width: 4.8, height: 8)
            let knobPath = Path(roundedRect: knob, cornerRadius: 2)
            var shadowed = ctx
            shadowed.addFilter(.shadow(color: .black.opacity(0.6), radius: 0.5, x: 0, y: 0.6))
            shadowed.fill(knobPath, shaded: .linearGradient(
                isOn ? Gradient(stops: [.init(color: hex(0xff8a4c), location: 0), .init(color: hex(0xff5a1f), location: 0.55),
                                        .init(color: hex(0xd0400e), location: 1)])
                     : Gradient(colors: [hex(0xbdbdbd), hex(0x8d8d8d)]),
                startPoint: CGPoint(x: 0, y: knob.minY), endPoint: CGPoint(x: 0, y: knob.maxY)))
            ridges(&ctx, in: knob, clip: knobPath)
            let font = Font.custom("Avenir Next Condensed", size: 4).weight(.bold)
            ctx.draw(Text(verbatim: "I").font(font).foregroundStyle(print), at: CGPoint(x: 7.6, y: 0.8), anchor: .topLeading)
            ctx.draw(Text(verbatim: "O").font(font).foregroundStyle(print), at: CGPoint(x: 7.6, y: 16.2), anchor: .bottomLeading)
        }
        .accessibilityHidden(true)
    }

    /// repeating-linear-gradient(0deg, rgba(0,0,0,.25) 0 .6px, transparent .6px 1.6px), from the bottom up
    private func ridges(_ ctx: inout GraphicsContext, in rect: CGRect, clip: Path) {
        var lines = ctx
        lines.clip(to: clip)
        var y = rect.maxY - 0.6
        while y > rect.minY - 0.6 {
            lines.fill(Path(CGRect(x: rect.minX, y: y, width: rect.width, height: 0.6)), with: .color(.black.opacity(0.25)))
            y -= 1.6
        }
    }
}

/// The MIDI strip's orange rubber SET key: the slide switch's 6 × 17 pill (1×), the label running
/// along it, top to bottom: the strip rests tilted -38 deg, so this reads right way up (bottom to top
/// would end up upside down).
struct PillKey: View {
    var label: String
    var pressed = false
    var scale: CGFloat = HardwareScale.app

    var body: some View {
        PartCanvas(size: CGSize(width: 6, height: 17), bleed: 2.5, scale: scale) { ctx in
            let pill = Path(roundedRect: CGRect(x: 0, y: 0, width: 6, height: 17), cornerRadius: 3)
            var body = ctx
            if pressed {
                body.translateBy(x: 0, y: 0.4)
            } else {
                // 0 1.4px 1.6px rgba(0,0,0,.35), then 0 .8px 0 #a8380c (the key's own lower edge)
                var drop = ctx
                drop.addFilter(.blur(radius: 0.8))
                drop.fill(pill.offsetBy(dx: 0, dy: 1.4), with: .color(.black.opacity(0.35)))
                ctx.fill(pill.offsetBy(dx: 0, dy: 0.8), with: .color(hex(0xa8380c)))
            }
            body.fill(pill, shaded: .linearGradient(
                Gradient(stops: [.init(color: hex(0xff8a4c), location: 0), .init(color: hex(0xf05a1c), location: 0.6),
                                 .init(color: hex(0xd84a12), location: 1)]),
                startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: 6, y: 0)))
            if pressed {
                body.insetShadow(in: pill, dy: 0.6, blur: 1, color: .black.opacity(0.3))
            } else {
                // inset .6px 0 0 rgba(255,255,255,.45): highlight down the left side
                var hi = body
                hi.clip(to: pill)
                hi.fill(pill.offsetBy(dx: -6 + 0.6, dy: 0), with: .color(.white.opacity(0.45)))
            }
            var text = body
            text.translateBy(x: 3, y: 8.5)
            text.rotate(by: .degrees(90))
            text.draw(Text(verbatim: label).font(.custom("Avenir Next Condensed", size: 3.4).weight(.heavy))
                        .tracking(3.4 * 0.08).foregroundStyle(hex(0x5a1a02)), at: .zero, anchor: .center)
        }
        .accessibilityHidden(true)
    }
}

/// The symbol printed on a TE key's cap.
enum TEKeyGlyph {
    case power, sliders
}

/// Teenage Engineering-style key: a big round flat matte cap in a dark cutout, symbol printed on
/// the cap. The frame is the cutout (radius + 2.2 SVG units), the same size as `Washer`.
struct TEKey: View {
    var cap: Color
    var edge: Color
    var glyph: TEKeyGlyph
    var pressed: Bool
    /// Cap radius in points (15 SVG units).
    var radius: CGFloat = 15 * HardwareScale.energy

    /// The power key's colours (orange cap, darker side).
    static let powerCap = hex(0xff6a1f), powerEdge = hex(0xb8430e)
    /// The SET key's colours (light grey cap, darker side).
    static let setCap = hex(0xd9d8d4), setEdge = hex(0x9e9c97)

    var body: some View {
        let u = radius / 15, outer = 17.2 * u
        PartCanvas(size: CGSize(width: outer * 2, height: outer * 2), bleed: 0, scale: 1) { ctx in
            let c = CGPoint(x: outer, y: outer)
            func disc(_ r: CGFloat, dy: CGFloat = 0) -> Path {
                Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r + dy, width: r * 2, height: r * 2))
            }
            ctx.fill(disc(outer), with: .color(.black.opacity(0.55)))  // cutout gap
            ctx.fill(disc(radius, dy: (pressed ? 0.4 : 1.4) * u), with: .color(edge))  // cap side
            let top = (pressed ? 0.2 : 0) * u
            ctx.fill(disc(radius, dy: top), with: .color(cap))  // flat top
            ctx.stroke(disc(radius - 0.6 * u, dy: top), with: .color(.white.opacity(0.35)), lineWidth: 0.8 * u)
            // The symbol is printed on the cap, so it moves with it.
            var g = ctx
            g.translateBy(x: c.x, y: c.y + top)
            g.scaleBy(x: u, y: u)
            switch glyph {
            case .power:
                var p = Path()
                p.move(to: CGPoint(x: 0, y: -6))
                p.addLine(to: CGPoint(x: 0, y: -1))
                // SVG: M-4.6 -3.4 a6.2 6.2 0 1 0 9.2 0 (the large arc round the bottom)
                let r: CGFloat = 6.2, cy = -3.4 + sqrt(r * r - 4.6 * 4.6)
                let a = atan2(-3.4 - cy, -4.6)
                p.move(to: CGPoint(x: -4.6, y: -3.4))
                p.addArc(center: CGPoint(x: 0, y: cy), radius: r, startAngle: .radians(a), endAngle: .radians(.pi - a), clockwise: true)
                g.stroke(p, with: .color(hex(0x3a1606)), style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
            case .sliders:
                for (k, dy) in [-4.0, 0, 4].enumerated() {
                    var line = Path()
                    line.move(to: CGPoint(x: -6, y: dy))
                    line.addLine(to: CGPoint(x: 6, y: dy))
                    g.stroke(line, with: .color(hex(0x2b2b2b)), style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
                    let x = [-2.5, 3, -0.5][k]
                    let knob = Path(ellipseIn: CGRect(x: x - 1.9, y: dy - 1.9, width: 3.8, height: 3.8))
                    g.fill(knob, with: .color(cap))
                    g.stroke(knob, with: .color(hex(0x2b2b2b)), lineWidth: 1.3)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// The Energy module's tiny status LED (radius 2.2 SVG units): green and glowing while on, dark when off.
struct StatusLED: View {
    var isOn: Bool
    var radius: CGFloat = 2.2 * HardwareScale.energy

    var body: some View {
        Circle()
            .fill(isOn ? hex(0x58ff7a) : hex(0x1f2a20))
            .frame(width: radius * 2, height: radius * 2)
            .shadow(color: isOn ? hex(0x58ff7a) : .clear, radius: 3 * HardwareScale.energy / 2)
            .accessibilityHidden(true)
    }
}

// MARK: - Jack

/// The BPM tag's 3.5 mm jack on its right edge. The frame is the knurled barrel (6 × 11 at 1×; in the
/// design at tag (98, 42), sticking out 4 past the edge). While `plugged`, a plug sits in it (chrome
/// tip, ridged black housing, tapered strain relief, small teal LED) and its cable curves back behind
/// the tag. Place the whole part *behind* the tag body, which hides the barrel's inner end and the cable.
struct Jack: View {
    var plugged: Bool
    var scale: CGFloat = HardwareScale.app

    var body: some View {
        // Local origin = barrel top-left = tag (98, 42); the cable reaches tag x 78…137, y 46…98.
        PartCanvas(size: CGSize(width: 6, height: 11), bleed: EdgeInsets(top: 2, leading: 21, bottom: 58, trailing: 34), scale: scale) { ctx in
            if plugged {
                var cable = ctx
                cable.translateBy(x: -98, y: -42)  // the design's cable path is in tag coordinates
                cable.stroke(Self.cablePath, with: .color(hex(0x141414)), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                let shine = Path { p in
                    p.move(to: CGPoint(x: 126, y: 46.5))
                    p.addCurve(to: CGPoint(x: 119.5, y: 85), control1: CGPoint(x: 139, y: 46.5), control2: CGPoint(x: 140.5, y: 69))
                }
                cable.stroke(shine, with: .color(.white.opacity(0.18)), lineWidth: 1)
            }
            // Barrel: border-radius 1px 2px 2px 1px, knurled, box-shadow 0 1px 1px rgba(0,0,0,.45)
            let barrelRect = CGRect(x: 0, y: 0, width: 6, height: 11)
            let barrel = UnevenRoundedRectangle(topLeadingRadius: 1, bottomLeadingRadius: 1, bottomTrailingRadius: 2, topTrailingRadius: 2)
                .path(in: barrelRect)
            var drop = ctx
            drop.addFilter(.blur(radius: 0.5))
            drop.fill(barrel.offsetBy(dx: 0, dy: 1), with: .color(.black.opacity(0.45)))
            ctx.fill(barrel, shaded: .linearGradient(
                Gradient(stops: [.init(color: hex(0xf1f2f4), location: 0), .init(color: hex(0x9da1a6), location: 0.55),
                                 .init(color: hex(0xcfd2d6), location: 1)]),
                startPoint: .zero, endPoint: CGPoint(x: 0, y: 11)))
            var knurl = ctx
            knurl.clip(to: barrel)
            var y: CGFloat = 11 - 0.6
            while y > -0.6 {
                knurl.fill(Path(CGRect(x: 0, y: y, width: 6, height: 0.6)), with: .color(.black.opacity(0.25)))
                y -= 1.6
            }
            if plugged { drawPlug(&ctx) }
        }
        .accessibilityHidden(true)
    }

    /// The cable's centre line, in tag units (4 wide, round caps).
    static let cablePath = Path { p in
        p.move(to: CGPoint(x: 126, y: 47.5))
        p.addCurve(to: CGPoint(x: 120, y: 86), control1: CGPoint(x: 140, y: 47.5), control2: CGPoint(x: 142, y: 70))
        p.addCurve(to: CGPoint(x: 80, y: 96), control1: CGPoint(x: 108, y: 95), control2: CGPoint(x: 96, y: 97))
    }

    /// Where the jack is drawn, in tag units: the barrel and, while plugged, the plug (housing and strain relief) and
    /// the cable a little wider than drawn.
    static func outline(plugged: Bool) -> Path {
        let barrel = Path(CGRect(x: 98, y: 42, width: 6, height: 11))
        guard plugged else { return barrel }
        return barrel.union(Path(CGRect(x: 102, y: 41, width: 25, height: 13)))
            .union(cablePath.strokedPath(StrokeStyle(lineWidth: 6, lineCap: .round)))
    }

    /// The plug at tag (102, 41) = local (4, −1).
    private func drawPlug(_ ctx: inout GraphicsContext) {
        var p = ctx
        p.translateBy(x: 4, y: -1)
        // tip: 4 × 5.4 chrome with a dark insulator ring
        let tip = CGRect(x: 0, y: 3.8, width: 4, height: 5.4)
        p.fill(Path(tip), shaded: .linearGradient(
            Gradient(stops: [.init(color: .white, location: 0), .init(color: hex(0xa8a8a8), location: 0.6), .init(color: hex(0xd8d8d8), location: 1)]),
            startPoint: CGPoint(x: 0, y: tip.minY), endPoint: CGPoint(x: 0, y: tip.maxY)))
        p.fill(Path(CGRect(x: 1.4, y: tip.minY, width: 0.7, height: tip.height)), with: .color(.black.opacity(0.45)))
        // strain relief: 7 × 8, tapering (clip-path polygon), drawn first so the housing overlaps it
        let relief = Path { r in
            r.addLines([CGPoint(x: 18, y: 2.5), CGPoint(x: 25 - 1, y: 2.5 + 8 * 0.22), CGPoint(x: 25, y: 2.5 + 8 * 0.22 + 1),
                        CGPoint(x: 25, y: 2.5 + 8 * 0.78 - 1), CGPoint(x: 25 - 1, y: 2.5 + 8 * 0.78), CGPoint(x: 18, y: 10.5)])
            r.closeSubpath()
        }
        p.fill(relief, shaded: .linearGradient(Gradient(colors: [hex(0x3a3a3b), hex(0x121213)]),
                                             startPoint: CGPoint(x: 0, y: 2.5), endPoint: CGPoint(x: 0, y: 10.5)))
        // housing: 15 × 13, ridged black
        let housingRect = CGRect(x: 4, y: 0, width: 15, height: 13)
        let housing = UnevenRoundedRectangle(topLeadingRadius: 2, bottomLeadingRadius: 2, bottomTrailingRadius: 3, topTrailingRadius: 3)
            .path(in: housingRect)
        var drop = p
        drop.addFilter(.blur(radius: 0.5))
        drop.fill(housing.offsetBy(dx: 0, dy: 1), with: .color(.black.opacity(0.4)))
        p.fill(housing, shaded: .linearGradient(
            Gradient(stops: [.init(color: hex(0x4a4a4c), location: 0), .init(color: hex(0x151516), location: 0.6),
                             .init(color: hex(0x2a2a2b), location: 1)]),
            startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: 0, y: 13)))
        var ridges = p
        ridges.clip(to: housing)
        var x = housingRect.minX
        while x < housingRect.maxX {
            ridges.fill(Path(CGRect(x: x, y: 0, width: 1, height: 13)), with: .color(.white.opacity(0.08)))
            x += 2.5
        }
        // inset 0 1px 0 rgba(255,255,255,.25)
        ridges.fill(Path(CGRect(x: housingRect.minX, y: 0, width: 15, height: 1)), with: .color(.white.opacity(0.25)))
        // small teal LED
        var led = p
        led.addFilter(.shadow(color: hex(0x3ff0e0).opacity(0.9), radius: 0.8))
        led.fill(Path(ellipseIn: CGRect(x: 14.6, y: 5.7, width: 1.6, height: 1.6)), with: .color(hex(0x6ff6ff)))
    }
}
