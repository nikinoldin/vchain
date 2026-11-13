// SPDX-License-Identifier: GPL-3.0-or-later
import CoreGraphics
import SwiftUI

// MARK: - Smiley sticker

/// The acid-house smiley sticker on the BPM tag: a matte, slightly worn paper label (fine grain, scuffed rim, one faint
/// crease), tilted 15°, stuck over the top edge so only the grin and the bottoms of the eyes show, catching the edge's
/// bevel highlight where it bends over. Its lower right edge
/// has curled up a little, showing a sliver of the paper backing. Face after the classic acid smiley: thin ring, tall
/// oval eyes, a near half-circle grin with short ticks across its ends. 24 × 24 at 1×; in the design at tag
/// (38, −10.5), above the plate. Everything above the plate's top edge (y < 10.5) is not drawn.
/// A physical sticker, so it looks the same in light and dark mode.
struct SmileySticker: View {
    var scale: CGFloat = HardwareScale.app

    var body: some View {
        PartCanvas(size: CGSize(width: 24, height: 24), bleed: 0, scale: scale) { ctx in
            Self.draw(&ctx)
        }
        .accessibilityHidden(true)
    }

    // The sticker's own frame: origin at its centre, y down, before the 15° tilt. Proportions measured off the
    // reference smiley (diameter D = 18): eyes ±0.127 D across, 0.136 D up, 0.10 × 0.20 D; the grin a circular arc
    // (centre 0.036 D down, radius 0.29 D) from 8° to 172°; ring ≈ 0.035 D, grin ≈ 0.04 D.
    private static let radius: CGFloat = 9
    private static let tilt = Angle.degrees(15)
    private static let yellow = hex(0xf7d944)
    private static let ink = hex(0x161412)
    /// The curled edge: which way it faces (in the sticker's frame), how deep into the disc the curl starts, and how
    /// far back over the face the rolled-up edge reaches (as a share of that depth).
    private static let peelAngle = Angle.degrees(36)
    private static let peelDepth: CGFloat = 0.65
    private static let curl: CGFloat = 0.6

    private static func draw(_ ctx: inout GraphicsContext) {
        let r = radius
        let u = CGPoint(x: cos(peelAngle.radians), y: sin(peelAngle.radians))
        let d = r - peelDepth          // the curl line: points with p·u > d have lifted off
        let c = sqrt(r * r - d * d)    // half the curl line's length
        // peel frame (x along u) → sticker frame
        let toPeel = CGAffineTransform(rotationAngle: peelAngle.radians)

        var base = ctx
        base.clip(to: Path(CGRect(x: -10, y: 10.5, width: 44, height: 30)))
        base.translateBy(x: 12, y: 12)
        base.rotate(by: tilt)

        let disc = Path(ellipseIn: CGRect(x: -r, y: -r, width: 2 * r, height: 2 * r))
        let lifted = Path(CGRect(x: d, y: -r - 1, width: 2, height: 2 * r + 2)).applying(toPeel)

        // Under the lift: bare plate, darkest right under the curl line.
        var under = base
        under.clip(to: disc)
        under.fill(lifted, shaded: .linearGradient(
            Gradient(stops: [.init(color: .black.opacity(0.26), location: 0), .init(color: .black.opacity(0), location: 1)]),
            startPoint: CGPoint(x: d * u.x, y: d * u.y), endPoint: CGPoint(x: r * u.x, y: r * u.y)))

        // The face, minus the lifted part.
        var face = base
        face.clip(to: Path(CGRect(x: -r - 1, y: -r - 1, width: d + r + 1, height: 2 * r + 2)).applying(toPeel))
        face.clip(to: disc)
        face.fill(disc, with: .color(yellow))
        // matte paper: a faint darkening towards the rim
        face.fill(disc, shaded: .radialGradient(
            Gradient(stops: [.init(color: .black.opacity(0), location: 0.62), .init(color: .black.opacity(0.07), location: 1)]),
            center: .zero, startRadius: 0, endRadius: r))
        face.stroke(Path(ellipseIn: CGRect(x: -r, y: -r, width: 2 * r, height: 2 * r).insetBy(dx: 0.36, dy: 0.36)),
                    with: .color(ink), lineWidth: 0.72)
        for x in [-2.3, 2.3] as [CGFloat] {
            face.fill(Path(ellipseIn: CGRect(x: x - 0.93, y: -2.45 - 1.83, width: 1.86, height: 3.66)), with: .color(ink))
        }
        let grin = Path { p in
            let centre = CGPoint(x: 0, y: 0.65), rr: CGFloat = 5.25
            for i in 0...32 {
                let a = (8 + 164 * Double(i) / 32) * .pi / 180
                let q = CGPoint(x: centre.x + rr * cos(a), y: centre.y + rr * sin(a))
                if i == 0 { p.move(to: q) } else { p.addLine(to: q) }
            }
            // ticks across the ends, outer end lower
            p.move(to: CGPoint(x: -6.1, y: 1.62)); p.addLine(to: CGPoint(x: -4.95, y: 1.02))
            p.move(to: CGPoint(x: 6.1, y: 1.62)); p.addLine(to: CGPoint(x: 4.95, y: 1.02))
        }
        face.stroke(grin, with: .color(ink), style: StrokeStyle(lineWidth: 0.8, lineCap: .round, lineJoin: .round))
        paperWear(&face, radius: r)

        // The rolled-up edge: the lifted cap seen from below, foreshortened, lying back over the face.
        let flap = Path { p in
            let steps = 24
            for i in 0...steps {
                let y = -c + 2 * c * CGFloat(i) / CGFloat(steps)
                let x = d - curl * (sqrt(max(r * r - y * y, 0)) - d)
                if i == 0 { p.move(to: CGPoint(x: x, y: y)) } else { p.addLine(to: CGPoint(x: x, y: y)) }
            }
            p.addQuadCurve(to: CGPoint(x: d, y: -c), control: CGPoint(x: d + 0.12, y: 0))  // the roll bulges out a touch
            p.closeSubpath()
        }.applying(toPeel)
        var rolled = base
        rolled.addFilter(.shadow(color: .black.opacity(0.25), radius: 0.3, x: 0.1, y: 0.25))
        let tip = CGPoint(x: (d - curl * peelDepth) * u.x, y: (d - curl * peelDepth) * u.y)
        rolled.fill(flap, shaded: .linearGradient(
            Gradient(stops: [.init(color: hex(0xf3efe4), location: 0), .init(color: hex(0xe6e0d2), location: 0.5),
                             .init(color: hex(0xcdc5b4), location: 1)]),
            startPoint: CGPoint(x: d * u.x, y: d * u.y), endPoint: tip))
        base.stroke(flap, with: .color(.black.opacity(0.12)), lineWidth: 0.14)

        // Where it wraps over the plate's top edge (the tag's lit 1-unit lip, y 10.5…11.5 here): the paper bends round
        // the bevel, catching the same highlight, a touch darker right at the edge where it turns away.
        var bend = ctx
        bend.clip(to: disc.applying(CGAffineTransform(translationX: 12, y: 12).rotated(by: tilt.radians)))
        let top: CGFloat = 10.5
        bend.fill(Path(CGRect(x: 0, y: top, width: 24, height: 1.6)), shaded: .linearGradient(
            Gradient(stops: [.init(color: .white.opacity(0.18), location: 0), .init(color: .white.opacity(0.55), location: 0.2),
                             .init(color: .white.opacity(0.42), location: 0.55), .init(color: .white.opacity(0), location: 1)]),
            startPoint: CGPoint(x: 0, y: top), endPoint: CGPoint(x: 0, y: top + 1.6)))
        bend.fill(Path(CGRect(x: 0, y: top, width: 24, height: 0.3)), with: .color(.black.opacity(0.14)))
    }

    /// Fine paper grain, ink rubbed off the rim in a few places and one faint crease: worn price-label paper. Fixed
    /// pseudo-random positions, so it looks the same every launch.
    private static func paperWear(_ ctx: inout GraphicsContext, radius r: CGFloat) {
        var seed: UInt32 = 0x5eed_c0de
        func rnd() -> CGFloat {
            seed = seed &* 1_664_525 &+ 1_013_904_223
            return CGFloat(seed >> 8) / CGFloat(1 << 24)
        }
        var dark = Path(), light = Path()
        for i in 0..<170 {
            let a = rnd() * 2 * .pi, rr = r * sqrt(rnd()), s = 0.1 + rnd() * 0.14
            let dot = Path(ellipseIn: CGRect(x: rr * cos(a) - s / 2, y: rr * sin(a) - s / 2, width: s, height: s))
            if i % 3 == 0 { light.addPath(dot) } else { dark.addPath(dot) }
        }
        ctx.fill(dark, with: .color(.black.opacity(0.09)))
        ctx.fill(light, with: .color(.white.opacity(0.32)))
        // scuffs on the rim: the paper showing through the ink ring
        var scuffs = Path()
        for start in [0.35, 1.25, 2.6, 3.95, 5.3] as [CGFloat] {
            let len = 0.05 + rnd() * 0.1
            let rr = r - 0.32 + (rnd() - 0.5) * 0.25
            scuffs.move(to: CGPoint(x: rr * cos(start), y: rr * sin(start)))
            for k in 1...4 {
                let a = start + len * CGFloat(k) / 4
                scuffs.addLine(to: CGPoint(x: rr * cos(a), y: rr * sin(a)))
            }
        }
        ctx.stroke(scuffs, with: .color(.white.opacity(0.3)), style: StrokeStyle(lineWidth: 0.16, lineCap: .round))
        // a crease across the lower half: a lit side and a shaded side
        let crease = Path { p in
            p.move(to: CGPoint(x: -8.6, y: 2.4))
            p.addQuadCurve(to: CGPoint(x: 7.4, y: 5.6), control: CGPoint(x: -0.5, y: 3.0))
        }
        ctx.stroke(crease, with: .color(.white.opacity(0.2)), lineWidth: 0.2)
        ctx.stroke(crease.offsetBy(dx: 0.05, dy: 0.2), with: .color(.black.opacity(0.08)), lineWidth: 0.22)
    }
}

// MARK: - BitmapBabe sticker

/// The BitmapBabe logo, white on a black vinyl strip, stuck on the MIDI strip's right end cap: high up,
/// just below the keyring hole (the pride flag sticker covers its bottom end), fully on the cap (all four edges visible), running bottom to
/// top like a box's spine label, tilted 2°; the top end has a small lifted corner showing the paper backing.
/// Drawn in the right cap's coordinates (17 × 100 at 1×): place it at the cap's top-left corner.
/// A physical sticker, so it looks the same in light and dark mode.
struct BitmapBabeSticker: View {
    var scale: CGFloat = HardwareScale.app

    static let cap = CGSize(width: StripGeometry.rightCap, height: StripGeometry.height)

    // Sticker in its own frame: x along the reading direction, y across (0 = centre line).
    private static let letterHeight: CGFloat = 6.5
    private static let margin: CGFloat = 1.2
    private static let lead: CGFloat = 2  // blank vinyl before "BITMAP"
    private static let tail: CGFloat = 2  // blank vinyl after "BABE", room for the lifted corner
    private static let radius: CGFloat = 1.1
    /// Where "BITMAP" starts on the cap (the vinyl runs ≈ 14…77, its top end just under the grommet's bottom at 13) and
    /// the tilt.
    private static let textStart = CGPoint(x: 8.5, y: 75.25)
    private static let angle = Angle.degrees(-90 + 2)

    var body: some View {
        PartCanvas(size: Self.cap, bleed: EdgeInsets(), scale: scale) { ctx in
            Self.draw(&ctx)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private static func draw(_ ctx: inout GraphicsContext) {
        let logo = BitmapBabeLogo.glyphs
        let k = letterHeight / logo.boundingRect.height
        let textLength = logo.boundingRect.width * k
        let h = letterHeight + 2 * margin
        let length = lead + textLength + tail
        // sticker frame → cap: origin at the start of the vinyl, rotated to read bottom to top
        let toCap = CGAffineTransform(translationX: textStart.x, y: textStart.y)
            .rotated(by: angle.radians)
            .translatedBy(x: -lead, y: 0)
        func onCap(_ p: CGPoint) -> CGPoint { p.applying(toCap) }

        // The lifted corner (top end, right side on the cap): the vinyl folds back along a slightly
        // curved crease, showing the paper backing.
        let corner = CGPoint(x: length, y: h / 2)
        let a: CGFloat = 2.6, b: CGFloat = 2.0  // crease ends: back along the long edge, in along the short edge
        let c1 = CGPoint(x: length - a, y: h / 2), c2 = CGPoint(x: length, y: h / 2 - b)
        let mid = CGPoint(x: (c1.x + c2.x) / 2 - 0.12, y: (c1.y + c2.y) / 2 - 0.12)  // crease bows inward a touch
        let folded = reflect(corner, c1, c2)
        let flapTip = CGPoint(x: folded.x + 0.15, y: folded.y - 0.05)

        let bodyShape = Path(roundedRect: CGRect(x: 0, y: -h / 2, width: length, height: h), cornerRadius: radius)
        let lifted = Path { p in  // the area the folded corner no longer covers
            p.move(to: c1)
            p.addQuadCurve(to: c2, control: mid)
            p.addLine(to: CGPoint(x: length + 1, y: h / 2 - b))
            p.addLine(to: CGPoint(x: length + 1, y: h / 2 + 1))
            p.addLine(to: CGPoint(x: length - a, y: h / 2 + 1))
            p.closeSubpath()
        }
        let flap = Path { p in
            p.move(to: c1)
            p.addQuadCurve(to: c2, control: mid)
            p.addQuadCurve(to: c1, control: flapTip)
            p.closeSubpath()
        }
        let vinyl = bodyShape.subtracting(lifted).applying(toCap)
        let text = logo.applying(CGAffineTransform(translationX: lead, y: 0)
            .scaledBy(x: k, y: k)
            .translatedBy(x: -logo.boundingRect.minX, y: -logo.boundingRect.midY))
            .applying(toCap)

        let capOutline = cornerPath(CGRect(origin: .zero, size: cap), 3, 13, 13, 3)
        ctx.clip(to: capOutline)
        paint(&ctx, vinyl: vinyl, text: text)

        // flap: paper backing catching the light, a soft shadow under it
        let flapOnCap = flap.applying(toCap)
        var paper = ctx
        paper.addFilter(.shadow(color: .black.opacity(0.35), radius: 0.35, x: 0.25, y: 0.4))
        paper.fill(flapOnCap, shaded: .linearGradient(
            Gradient(stops: [.init(color: hex(0xd9d4c6), location: 0), .init(color: hex(0xfbf9f3), location: 0.4),
                             .init(color: hex(0xece7da), location: 1)]),
            startPoint: onCap(mid), endPoint: onCap(folded)))
        ctx.stroke(flapOnCap, with: .color(.black.opacity(0.18)), lineWidth: 0.2)
        var crease = Path()
        crease.move(to: c1)
        crease.addQuadCurve(to: c2, control: mid)
        ctx.stroke(crease.applying(toCap), with: .color(.white.opacity(0.55)), lineWidth: 0.22)
    }

    /// The vinyl (thin, so only a tight contact shadow), a faint sheen, a hairline edge, then the ink.
    private static func paint(_ ctx: inout GraphicsContext, vinyl: Path, text: Path) {
        var under = ctx
        under.addFilter(.shadow(color: .black.opacity(0.3), radius: 0.3, x: 0.1, y: 0.25))
        under.fill(vinyl, with: .color(hex(0x121212)))
        let box = vinyl.boundingRect
        ctx.fill(vinyl, shaded: .linearGradient(
            Gradient(stops: [.init(color: hex(0x2a2a2a), location: 0), .init(color: hex(0x141414), location: 0.45),
                             .init(color: hex(0x0c0c0c), location: 1)]),
            startPoint: CGPoint(x: box.minX, y: box.minY), endPoint: CGPoint(x: box.maxX, y: box.maxY)))
        ctx.stroke(vinyl, with: .color(.white.opacity(0.10)), lineWidth: 0.18)
        ctx.fill(text, with: .color(hex(0xf4f2ec)))
    }

    /// `p` mirrored across the line through `a` and `b`.
    private static func reflect(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGPoint {
        let d = CGPoint(x: b.x - a.x, y: b.y - a.y)
        let t = ((p.x - a.x) * d.x + (p.y - a.y) * d.y) / (d.x * d.x + d.y * d.y)
        let foot = CGPoint(x: a.x + t * d.x, y: a.y + t * d.y)
        return CGPoint(x: 2 * foot.x - p.x, y: 2 * foot.y - p.y)
    }
}

// MARK: - Progress pride flag sticker

/// A Progress Pride flag sticker on the MIDI strip's right end cap: matte paper with a thin white die-cut border,
/// stood upright and stuck on casually low on the cap, over the BitmapBabe sticker's bottom end ("BIT" of "BITMAP"), wrapped over the cap's
/// right edge (the purple stripe's side goes round the edge, out of sight; the paper takes the edge's shaded bevel where it bends).
/// Drawn in the right cap's coordinates (17 × 100 at 1×), like `BitmapBabeSticker`: place it at the cap's top-left corner.
/// A physical sticker, so it looks the same in light and dark mode.
struct PrideFlagSticker: View {
    var scale: CGFloat = HardwareScale.app

    /// The printed flag (5 : 3) and the white border round it.
    private static let flag = CGSize(width: 18.85, height: 11.3)
    private static let border: CGFloat = 0.6
    /// Low on the cap, its bottom (≈ 85) just above the add button (top at 86.5).
    private static let center = CGPoint(x: 12.4, y: 74.5)
    /// Upright: the chevron at the bottom pointing up, the purple stripe's edge going round the cap's right edge.
    private static let angle = Angle.degrees(-79)

    private static let stripes: [UInt32] = [0xe40303, 0xff8c00, 0xffed00, 0x008026, 0x24408e, 0x732982]
    /// The chevron at the hoist, outermost first: black, brown, light blue, pink, then the white triangle.
    private static let chevrons: [UInt32] = [0x000000, 0x784f17, 0x5bcefa, 0xf5a9b8, 0xffffff]

    var body: some View {
        PartCanvas(size: BitmapBabeSticker.cap, bleed: 0, scale: scale) { ctx in
            Self.draw(&ctx)
        }
        .accessibilityHidden(true)
    }

    private static func draw(_ ctx: inout GraphicsContext) {
        let w = flag.width, h = flag.height, b = border
        let cap = BitmapBabeSticker.cap
        let capOutline = UnevenRoundedRectangle(topLeadingRadius: 3, bottomLeadingRadius: 3, bottomTrailingRadius: 13,
                                                topTrailingRadius: 13).path(in: CGRect(origin: .zero, size: cap))
        ctx.clip(to: capOutline)
        var bend = ctx  // unrotated: the edge's bevel, at the end
        ctx.translateBy(x: center.x, y: center.y)
        ctx.rotate(by: angle)
        ctx.translateBy(x: -w / 2, y: -h / 2)  // flag's top-left at the origin
        let paper = Path(roundedRect: CGRect(x: -b, y: -b, width: w + 2 * b, height: h + 2 * b), cornerRadius: 0.55)

        // paper, with a tight contact shadow
        var under = ctx
        under.addFilter(.shadow(color: .black.opacity(0.35), radius: 0.3, x: 0.1, y: 0.25))
        under.fill(paper, with: .color(hex(0xf4f1e8)))

        var print = ctx
        print.clip(to: Path(CGRect(x: 0, y: 0, width: w, height: h)))
        let sh = h / CGFloat(stripes.count)
        for (i, c) in stripes.enumerated() {
            print.fill(Path(CGRect(x: 0, y: CGFloat(i) * sh - 0.02, width: w, height: sh + 0.04)), with: .color(hex(c)))
        }
        // Chevrons: nested arrows pointing right, each band `step` wide, the white triangle's tip at `tip0`.
        let tip0 = 0.24 * w, step = 0.065 * w
        for (i, c) in chevrons.enumerated() {
            let tip = tip0 + CGFloat(chevrons.count - 1 - i) * step
            let arrow = Path { p in
                p.move(to: CGPoint(x: -1, y: -h / 2 * 0))
                p.addLine(to: CGPoint(x: tip - tip0, y: 0))
                p.addLine(to: CGPoint(x: tip, y: h / 2))
                p.addLine(to: CGPoint(x: tip - tip0, y: h))
                p.addLine(to: CGPoint(x: -1, y: h))
                p.closeSubpath()
            }
            print.fill(arrow, with: .color(hex(c)))
        }
        // matte, a little worn: the print slightly faded, fine grain over paper and print
        print.fill(Path(CGRect(x: 0, y: 0, width: w, height: h)), with: .color(.white.opacity(0.08)))
        var seed: UInt32 = 0x0f1a_9b0e
        func rnd() -> CGFloat {
            seed = seed &* 1_664_525 &+ 1_013_904_223
            return CGFloat(seed >> 8) / CGFloat(1 << 24)
        }
        var dark = Path(), light = Path()
        for i in 0..<70 {
            let s = 0.08 + rnd() * 0.1
            let dot = Path(ellipseIn: CGRect(x: -b + rnd() * (w + 2 * b), y: -b + rnd() * (h + 2 * b), width: s, height: s))
            if i % 3 == 0 { light.addPath(dot) } else { dark.addPath(dot) }
        }
        var grain = ctx
        grain.clip(to: paper)
        grain.fill(dark, with: .color(.black.opacity(0.1)))
        grain.fill(light, with: .color(.white.opacity(0.3)))
        // the paper's edge
        ctx.stroke(paper, with: .color(.black.opacity(0.14)), lineWidth: 0.14)

        // Bending round the cap's right edge: the paper takes the edge's bevel, a faint catch-light then the cap's
        // 1-unit dark inset.
        let toCap = CGAffineTransform(translationX: center.x, y: center.y).rotated(by: angle.radians)
            .translatedBy(x: -w / 2, y: -h / 2)
        bend.clip(to: paper.applying(toCap))
        let x0 = cap.width - 1.8
        bend.fill(Path(CGRect(x: x0, y: 0, width: 1.8, height: cap.height)), shaded: .linearGradient(
            Gradient(stops: [.init(color: .white.opacity(0), location: 0), .init(color: .white.opacity(0.12), location: 0.28),
                             .init(color: .black.opacity(0.1), location: 0.42), .init(color: .black.opacity(0.34), location: 0.46),
                             .init(color: .black.opacity(0.42), location: 1)]),
            startPoint: CGPoint(x: x0, y: 0), endPoint: CGPoint(x: cap.width, y: 0)))
    }
}

// MARK: - Logo artwork

/// The BitmapBabe logo glyphs ("BITMAP" in pixel letters, "BABE" in a serif), path data copied from
/// bitmapbabe.com/components/logo.vue (viewBox 0 0 595.3 99.2; same as BB Design Assets/main.svg).
enum BitmapBabeLogo {
    static let glyphs: Path = {
        var p = Path()
        for d in pathData { p.addPath(SVGPathData.parse(d)) }
        return p
    }()

    private static let pathData = [
        "M18.7 80.7V18.4h31.2v3.1H53v3.1h3.1v3.1h3.1v15.6h-3.1v6.2h3.1v3.1h3.1v18.7h-3.1v3.1h-3.1v3.1H53v3.1l-34.3.1zm28-37.4v-3.1h3.1v-9.4h-3.1v-3.1H28v15.6h18.7zm3.1 28.1v-3.1H53V55.8h-3.1v-3.1H28v18.7h21.8zM72.4 80.7V18.4h9.4v62.4h-9.4v-.1zM109.4 80.7v-53H87.6v-9.4h53v9.4h-21.8v53h-9.4zM146.7 80.7V18.4h15.6v9.4h3.1V34h3.1v9.4h3.1v9.4h3.1v12.5h3.1V52.7h3.1v-9.4h3.1v-9.4h3.1v-6.2h3.1v-9.4H206v62.4h-9.4V33.9h-3.1v6.2h-3.1v12.5h-3.1v12.5h-3.1v9.4H181v6.2h-9.4v-6.2h-3.1v-9.4h-3.1V52.7h-3.1V40.2h-3.1V34h-3.1v46.8h-9.4v-.1z",
        "M213.5 80.7v-9.4h3.1v-6.2h3.1v-9.4h3.1v-6.2h3.1v-6.2h3.1v-6.2h3.1v-6.2h3.1v-6.2h3.1v-6.2h9.4v6.2h3.1v6.2h3.1v6.2h3.1v6.2h3.1v6.2h3.1v6.2h3.1v9.4h3.1v6.2h3.1v9.4h-9.4v-6.2H260v-6.2h-3.1V62h-28.1v6.2h-3.1v6.2h-3.1v6.2h-9.1v.1zm40.5-28v-3.1h-3.1v-6.2h-3.1v-6.2h-3.1V31h-3.1v6.2h-3.1v6.2h-3.1v6.2h-3.1v3.1H254zM280.3 80.7V18.4h34.3v3.1h3.1v3.1h3.1v3.1h3.1v15.6h-3.1v3.1h-3.1v3.1h-3.1v3.1h-24.9v28.1h-9.4zm31.2-37.4v-3.1h3.1v-9.4h-3.1v-3.1h-21.8v15.6h21.8z",
        "m339.2 65.7.4-32.1c0-11.7-2.3-15.1-2.3-15.1h19c19.3 0 28.4 6.2 28.4 14.4 0 9.3-7.5 13.3-14.7 14.9 16.1 1.6 21.4 7.9 21.3 15 0 10.6-10.6 18-31.3 18-2.1.1-6.3.1-13.4 0H337c-.2-.1 2.2-3.5 2.2-15.1zm8.4-21.4c4.1 2 9.1 2.7 12.8 2.8 8.7 0 15.7-5 15.7-12 0-10.1-11.2-13.4-18.3-13.4-3 0-6.5.4-9.3 1.1-.4 2.3-.9 5.8-.9 10.9v10.6zm.1 21.4c0 3.5.3 6.2.5 8.4 3.2 2 9.3 2.8 12 2.8 12.1 0 20.9-2.8 20.9-11.7 0-13.8-19.1-16.2-33.5-15.7l.1 16.2zM400 69.3l21.5-43.2c-1.6-2.8-4.1-5.2-7.8-7.5v-.2l14.1.1c.7 2 1.7 4.3 3.1 7.4l19.7 41.9c1.9 3.7 5.1 9.6 8.4 12.9h-15.7c1-2.4-.9-8.4-2.1-11.6l-3.3-7.5h-28.4l-3.4 7.7c-.5 1.5-2.5 6.9-1.8 11.4h-10.9c2.3-3.7 4.9-8.3 6.6-11.4zm36.1-11.4L426 35.7l-2.7-6L411 57.9h25.1zM467.1 65.7l.4-32.1c0-11.7-2.3-15.1-2.3-15.1h19c19.3 0 28.4 6.2 28.4 14.4 0 9.3-7.5 13.3-14.7 14.9 16.1 1.6 21.4 7.9 21.3 15 0 10.6-10.6 18-31.3 18-2.1.1-6.3.1-13.4 0h-9.6c-.1-.1 2.2-3.5 2.2-15.1zm8.5-21.4c4.1 2 9.1 2.7 12.8 2.8 8.7 0 15.7-5 15.7-12 0-10.1-11.2-13.4-18.3-13.4-3 0-6.5.4-9.3 1.1-.4 2.3-.9 5.8-.9 10.9v10.6zm0 21.4c0 3.5.3 6.2.5 8.4 3.2 2 9.3 2.8 12 2.8 12.1 0 20.9-2.8 20.9-11.7 0-13.8-19.1-16.2-33.5-15.7l.1 16.2zM529.9 65.7l.4-32.1c0-11.7-2.2-15.1-2.3-15.1l47.8-.4 2.1 12.2-.6.4c-5.5-8.9-26.2-8.6-38.1-8.5-.5 2.4-1 6-1 11.4l.1 14.1h35.2v3.7h-35.2l.1 14.2c0 5.2.4 8.8 1 11.2 14 .2 34.9.7 40.6-8.5l.6.4-2.1 12.3-50.9-.3s2.3-3.4 2.3-15z",
    ]
}
