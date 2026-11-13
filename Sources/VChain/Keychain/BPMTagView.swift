// SPDX-License-Identifier: GPL-3.0-or-later
import VChainKit
import SwiftUI

/// The BPM tag (module "BPM + Link"): a 100 × 100 (1×) brushed-metal plate with a segment LCD,
/// the LCD's character is `Mascot.current`.
/// The LCD only switches fixed segments on and off; `state` (BPMTagState.make) says which.
/// Taps on the rocker and SET go to `onRocker` / `onSet`; while `isFront` is false the controls
/// don't hit-test, so a tap falls through to the caller's "bring to front" handling.
struct BPMTagView: View {
    var state: BPMTagState
    var isFront: Bool
    var onRocker: () -> Void
    var onSet: () -> Void
    /// Extra magnification on top of the app's 1.5× (the debug gallery, the vector export; below 1 for the Settings headers).
    var zoom: CGFloat = 1
    /// LCD elements left out entirely (not even a ghost): the app icon drops "NO INPUT", "?" and the meditating figure.
    var hiddenLCD: Set<String> = []
    /// While the rocker's power-on plays (`TagPowerOn`): what the LCD shows instead of `state`.
    var powerOn: TagPowerOn.Frame? = nil
    /// The input plug and its cable in the side jack; off for the small picture in Settings (the jack shows empty).
    var showsCable = true

    @Environment(\.colorScheme) private var scheme

    /// The plate, 1× units: side and corner radius.
    static let plate = KeyringGeometry.bpmTagSide, plateRadius = KeyringGeometry.bpmTagCornerRadius
    /// Plate size in points (100 at 1×).
    static let side: CGFloat = KeyringGeometry.bpmTagSide * HardwareScale.app
    /// Keyring hole centre from the plate's top-left corner, in points.
    static let holeCenter = CGPoint(x: KeyringGeometry.bpmTagHole.x * HardwareScale.app, y: KeyringGeometry.bpmTagHole.y * HardwareScale.app)

    var body: some View {
        let s = HardwareScale.app * zoom
        let dark = scheme == .dark
        let outline = Self.outline(plugged: showsCable && state.plugIn).scaled(s)
        ZStack(alignment: .topLeading) {
            ModuleOutline(path: outline, size: CGSize(width: Self.plate * s, height: Self.plate * s))
            // Behind the shell: rocker, jack (+ plug and cable).
            RockerSide(isOn: state.rockerOn, scale: s).offset(x: 96 * s, y: 16 * s)
            Jack(plugged: showsCable && state.plugIn, scale: s).offset(x: 98 * s, y: 42 * s)
            TagShell(dark: dark, scale: s)
            TagLCD(state: state, dark: dark, scale: s, hidden: hiddenLCD, powerOn: powerOn).offset(x: 11 * s, y: 17 * s)
            TagScrew(angle: .degrees(70), dark: dark, scale: s).offset(x: 88 * s, y: 5 * s)
            TagScrew(angle: .degrees(130), dark: dark, scale: s).offset(x: 5 * s, y: 88 * s)
            TagScrew(angle: .degrees(40), dark: dark, scale: s).offset(x: 88 * s, y: 88 * s)
            Grommet(opening: Grommet.opening * s, outer: Grommet.outer * s)
                .offset(x: (KeyringGeometry.bpmTagHole.x - Grommet.outer) * s, y: (KeyringGeometry.bpmTagHole.y - Grommet.outer) * s)
            SmileySticker(scale: s).offset(x: 38 * s, y: -10.5 * s)
            setButton(s)
            // The rocker sits behind the plate's edge: its hit area is the part that sticks out plus a margin.
            Color.clear
                .frame(width: 16 * s, height: 26 * s)
                // ≈ 20 × 28 units (30 × 42 pt): further out past the edge, up to just above the jack.
                .moduleControl(isFront: isFront, label: state.rockerOn ? "Turn Beat-o-Matic off" : "Turn Beat-o-Matic on",
                               grow: .units(top: 1, bottom: 1, trailing: 4, scale: s))
                .onTapGesture(perform: onRocker)
                .offset(x: 94 * s, y: 14 * s)
                .accessibilityAddTraits(.isButton)
            ModuleOutline.debug(outline, size: CGSize(width: Self.plate * s, height: Self.plate * s))
        }
        .frame(width: Self.plate * s, height: Self.plate * s, alignment: .topLeading)
    }

    /// Where the tag is drawn, in tag units (its hit area, `ModuleOutline`): the plate, the rocker's paddle, the jack (with
    /// plug and cable while `plugged`) and the SET key where they stick out of the plate's edge.
    static func outline(plugged: Bool) -> Path {
        var p = Path(roundedRect: CGRect(x: 0, y: 0, width: plate, height: plate), cornerRadius: plateRadius, style: .continuous)
        p = p.union(Path(CGRect(x: 96, y: 17, width: 11, height: 21))).union(Jack.outline(plugged: plugged))
        let span = TagSetButton.span
        return p.union(Path(CGRect(x: 99, y: span.lowerBound - 1, width: 5, height: span.upperBound - span.lowerBound + 2)))
    }

    /// SET (opens Settings › Beat-o-Matic): a push button on the right edge with a generous hit area.
    private func setButton(_ s: CGFloat) -> some View {
        let hit = TagSetButton.hitArea
        return Button(action: onSet) { EmptyView() }
            .buttonStyle(HardwareKeyStyle { pressed in TagSetButton(pressed: pressed, scale: s) })
            // 20 units wide (30 pt): further out past the edge.
            .moduleControl(isFront: isFront, label: "Beat-o-Matic settings", grow: .units(trailing: 4, scale: s))
            .offset(x: hit.minX * s, y: hit.minY * s)
    }
}

// MARK: - Shell

/// Plate, bezel, vent grille and the engraved I/O marks: everything static on the tag.
private struct TagShell: View {
    var dark: Bool
    var scale: CGFloat

    var body: some View {
        let side = BPMTagView.plate, radius = BPMTagView.plateRadius, hole = KeyringGeometry.bpmTagHole, o = Grommet.opening
        PartCanvas(size: CGSize(width: side, height: side), bleed: EdgeInsets(top: 4, leading: 10, bottom: 20, trailing: 10), scale: scale) { ctx in
            let rect = CGRect(x: 0, y: 0, width: side, height: side)
            let plate = Path(roundedRect: rect, cornerRadius: radius, style: .continuous)
            // The keyring hole is drilled through the plate (the grommet sits on top).
            ctx.clipOut(Path(ellipseIn: CGRect(x: hole.x - o, y: hole.y - o, width: 2 * o, height: 2 * o)))
            // 0 1px 1px rgba(0,0,0,.35), 0 8px 14px -4px rgba(0,0,0,.35)
            ctx.dropShadow(of: rect, radius: radius, dy: 8, blur: 14, spread: -4, color: .black.opacity(0.35))
            ctx.dropShadow(of: rect, radius: radius, dy: 1, blur: 1, color: .black.opacity(0.35))
            ctx.fill(plate, shaded: .linearGradient(Gradient(colors: dark ? [hex(0x4a4e55), hex(0x2b2e33)] : [hex(0xcfd2d6), hex(0xa9adb3)]),
                                                  startPoint: .zero, endPoint: CGPoint(x: 0, y: side)))
            // brushed: repeating-linear-gradient(90deg, …) = vertical hairlines
            var brushed = ctx
            brushed.clip(to: plate)
            let period: CGFloat = dark ? 2 : 3
            var x: CGFloat = 0
            while x < side {
                brushed.fill(Path(CGRect(x: x, y: 0, width: 1, height: side)), with: .color(.white.opacity(dark ? 0.06 : 0.12)))
                brushed.fill(Path(CGRect(x: x + 1, y: 0, width: 1, height: side)), with: .color(.black.opacity(dark ? 0.08 : 0.05)))
                if !dark { brushed.fill(Path(CGRect(x: x + 2, y: 0, width: 1, height: side)), with: .color(.white.opacity(0.04))) }
                x += period
            }
            // linear-gradient(160deg, white .55/.25, transparent 40%, black .12/.25)
            let sheen = cssGradientLine(160, in: rect)
            brushed.fill(plate, shaded: .linearGradient(
                Gradient(stops: [.init(color: .white.opacity(dark ? 0.25 : 0.55), location: 0), .init(color: .white.opacity(0), location: 0.4),
                                 .init(color: .black.opacity(dark ? 0.25 : 0.12), location: 1)]),
                startPoint: sheen.start, endPoint: sheen.end))
            // inset 0 1px 0 white .9, inset 0 -1px 0 black .25, inset 0 0 0 1px black .12
            ctx.insetShadow(in: plate, dy: 1, color: .white.opacity(0.9))
            ctx.insetShadow(in: plate, dy: -1, color: .black.opacity(0.25))
            ctx.stroke(Path(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), cornerRadius: 13.5, style: .continuous), with: .color(.black.opacity(0.12)), lineWidth: 1)

            // Bezel: 8 in from the sides, radius 14 − 8 = 6; lip 0 1px 0 white .75, inset 0 1px 2px black .8.
            let bezelRect = CGRect(x: 8, y: 14, width: 84, height: 66)
            let bezel = Path(roundedRect: bezelRect, cornerRadius: innerRadius(outer: 14, inset: 8), style: .continuous)
            ctx.fill(bezel.offsetBy(dx: 0, dy: 1), with: .color(.white.opacity(0.75)))
            ctx.fill(bezel, shaded: .linearGradient(Gradient(colors: [hex(0x1b1c1e), hex(0x3a3c40)]),
                                                  startPoint: CGPoint(x: 0, y: bezelRect.minY), endPoint: CGPoint(x: 0, y: bezelRect.maxY)))
            ctx.insetShadow(in: bezel, dy: 1, blur: 2, color: .black.opacity(0.8))

            TagGrille.draw(ctx: ctx, dark: dark)

            // "I" / "O" engraved next to the rocker (right: 3.2px; top 18.5 / 31).
            let ink: Color = dark ? .white.opacity(0.5) : .black.opacity(0.45)
            let shade: Color = dark ? .black.opacity(0.6) : .white.opacity(0.7)
            for (mark, top) in [("I", 18.5), ("O", 31.0)] {
                let t = { (c: Color) in Text(verbatim: mark).font(.system(size: 3.6, weight: .heavy)).foregroundStyle(c) }
                ctx.draw(t(shade), at: CGPoint(x: 96.8, y: top + (dark ? -0.4 : 0.4)), anchor: .topTrailing)
                ctx.draw(t(ink), at: CGPoint(x: 96.8, y: top), anchor: .topTrailing)
            }
            // The SET button gets its label ("SETTINGS") the same way, turned to run down the gutter.
            let span = TagSetButton.span
            var turned = ctx
            turned.translateBy(x: 95.0, y: (span.lowerBound + span.upperBound) / 2)
            turned.rotate(by: .degrees(90))
            let t = { (c: Color) in Text(verbatim: "SETTINGS").font(.system(size: 3.4, weight: .heavy)).tracking(0.15).foregroundStyle(c) }
            turned.draw(t(shade), at: CGPoint(x: dark ? -0.4 : 0.4, y: 0), anchor: .center)
            turned.draw(t(ink), at: .zero, anchor: .center)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - LCD

/// The segment LCD (78 × 60 at 1×). Drawn in a 140 × 96 design viewBox, stretched to fit
/// (not aspect-preserving); glass, ghosts, glow and glare come from SegmentLCD.
private struct TagLCD: View {
    var state: BPMTagState
    var dark: Bool
    var scale: CGFloat
    var hidden: Set<String> = []
    var powerOn: TagPowerOn.Frame? = nil

    private static let size = CGSize(width: 78, height: 60)

    var body: some View {
        let lit = litSegments()
        let pad = canvasEdgePad  // the glass fills the canvas: keep its edge off the layer's edge
        Canvas { ctx, _ in
            ctx.translateBy(x: pad, y: pad)
            ctx.scaleBy(x: scale * Self.size.width / 140, y: scale * Self.size.height / 96)
            SegmentLCD.draw(in: ctx, size: CGSize(width: 140, height: 96), corner: CGSize(width: 3 * 140 / 78, height: 3 * 96 / 60),
                            elements: hidden.isEmpty ? LCDElements.all : LCDElements.all.filter { !hidden.contains($0.name) }, isLit: { lit.contains($0.name) }, dark: dark, glow: 1.1,
                            litLevel: powerOn?.level ?? 1)
        }
        .frame(width: Self.size.width * scale + 2 * pad, height: Self.size.height * scale + 2 * pad)
        .padding(-pad)
        .accessibilityElement()
        .accessibilityLabel(Text(verbatim: accessibilityText))
    }

    /// Names of the lit segments.
    private func litSegments() -> Set<String> {
        if let powerOn {
            switch powerOn.show {
            case .all: return Set(LCDElements.all.filter { !$0.printed }.map(\.name))
            case .block(let i): return ["b\(i)"]
            case .mascot(let pose): return Mascot.current.lit(pose)
            }
        }
        var on = Set<String>()
        for (i, segs) in state.digits.enumerated() {
            for seg in segs { on.insert("d\(i)\(seg)") }
        }
        if state.decimalPoint { on.insert("dp") }
        if let beat = state.litBeat { on.insert("b\(beat)") }
        on.formUnion(Mascot.current.lit(state.mascot))
        if state.showQuestion { on.insert("q") }
        if state.mode == .noInput { on.insert("noin") }
        return on
    }

    private var accessibilityText: String {
        switch state.mode {
        case .off: return "Beat-o-Matic off"
        case .noInput: return "Beat-o-Matic, no input"
        case .settling: return "Beat-o-Matic, settling"
        case .locked: return "Beat-o-Matic, locked"
        }
    }
}

private enum LCDElements {
    static let all: [LCDElement] = build()

    static func build() -> [LCDElement] {
        var els: [LCDElement] = []
        func digit(_ i: Int, _ segs: [Segment: Path]) { els += SegmentLCD.digitElements("d\(i)", segs) }
        for (i, x) in [5, 33, 61].enumerated() { digit(i, SegmentLCD.sevenSeg(CGFloat(x), 5, 24, 44, 5, 0.08)) }
        els.append(LCDElement(name: "dp", kind: .fill(Path(CGRect(x: 90, y: 45, width: 5, height: 5)))))
        digit(3, SegmentLCD.sevenSeg(98, 23, 15, 26, 3.6, 0.08))
        els.append(LCDElement(name: "lblbpm", kind: .text("BPM", 8.5, .heavy, CGPoint(x: 136, y: 12), .end), printed: true))
        let divider = Path { p in p.move(to: CGPoint(x: 4, y: 56)); p.addLine(to: CGPoint(x: 62, y: 56)) }
        els.append(LCDElement(name: "div", kind: .stroke(divider, 0.8, dash: [1.5, 2], opacity: 0.35), printed: true))
        els.append(LCDElement(name: "noin", kind: .text("NO INPUT", 6.6, .black, CGPoint(x: 136, y: 59.5), .end)))

        els.append(LCDElement(name: "q", kind: .text("?", 11, .black, CGPoint(x: 38, y: 70), .start)))
        // The mascot (dancer) and what's printed with it (its stage line) fill the lower-left corner.
        els += Mascot.current.elements
        for (i, x) in [52, 73, 94, 115].enumerated() {
            let x = CGFloat(x)
            els.append(LCDElement(name: "b\(i)", kind: .fill(Path(CGRect(x: x, y: 64, width: 18, height: 22)))))
            els.append(LCDElement(name: "n\(i)", kind: .text("\(i + 1)", 6, .heavy, CGPoint(x: x + 9, y: 93.5), .middle), printed: true))
        }
        return els
    }
}
