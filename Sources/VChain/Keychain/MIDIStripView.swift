// SPDX-License-Identifier: GPL-3.0-or-later
import VChainEngine
import VChainKit
import SwiftUI

/// The MIDI strip (module "MIDI analysis", trigger bands): a left end cap (slide switch, SET key under it, the MIDI channel
/// LCD "CH16" running along the cap at the bottom), one channel module per trigger band, and a right end cap
/// with the keyring hole. Each channel module has a small segment LCD on top with the band's range (start over
/// end, from `vc_trigger_band_edges`, formatted by `BandLCD`; with 3 bands the instrument instead, "bd" / "Sd" / "HH",
/// `BandLCD.instrument`), a 10-step LED ladder with the top two yellow, an
/// LCD reading "CC n" at the bottom, and a plain black key on its top edge that ejects it (one band fewer). A
/// round chrome push button at the bottom of the right cap's face, under the sticker, adds a module. A right-angle
/// MIDI OUT plug sits in the left cap's free edge (`MIDIOutJack`; unplugged while off). No printed labels. Off: ladders dark, LCDs show only ghost segments. Flipped on, it plays a ≈1 s self-test
/// (`StripPowerOn`, passed in as `powerOn`). Modules butt together; each keeps its ≈3 pt corners and light/dark
/// edges, so the seams read as grooves with small notches (magnetic, no connectors).
/// Widths follow `KeyringGeometry.stripWidth` (19 + 27 per band + 17 at 1×), so the hole lands where the ring
/// expects it. While a module is being removed or added (`edit`, `StripEdit`) the strip is drawn at the wider of
/// the two widths, right-aligned: it hangs by the right cap, which stays put. An ejected module falls out as its
/// own layer, straight down in the world (`hangAngle` is the strip's current swing), past the strip's frame.
struct MIDIStripView: View {
    var bands: Int
    /// Trigger level per band, 0…1 (`LiveState.triggers`); missing entries count as 0.
    var levels: [Float]
    var isOn: Bool
    /// The MIDI channel the trigger CCs go out on (Settings › BandsDance › MIDI channel), for the left cap's LCD.
    var channel = Int(VC_MIDI_CHANNEL)
    /// The power-on self-test frame, one entry per module (`StripPowerOn.modules`); nil = normal.
    var powerOn: [StripPowerOn.Module]? = nil
    /// A module being removed or added and how far along it is; `bands` is then the new count.
    var edit: StripEdit? = nil
    var editTime: Double = 0
    /// The strip's rotation on the keychain (degrees), so an ejected module falls straight down.
    var hangAngle: Double = 0
    /// Room below the keyring hole, straight down to the panel's bottom edge (1× units): an ejected module fades out
    /// before it gets there instead of being cut off. Nil: no fade.
    var fallRoom: Double? = nil
    var isFront: Bool
    var onSlide: () -> Void
    var onSet: () -> Void
    var onEject: (Int) -> Void = { _ in }
    var onAdd: () -> Void = {}
    /// Hovering the MIDI OUT plug (`PlugMotion.peek`, 0…1).
    var plugPeek: Double = 0
    /// The pointer entering or leaving the plug.
    var onPlugHover: (Bool) -> Void = { _ in }
    /// MIDI learn (while unplugged): clicking band module k sends its CC as a sweep. Nil: off (and no LRN hint).
    var onLearn: ((Int) -> Void)? = nil
    /// Whether the MIDI OUT plug is in (`EngineModel.stripPlugged`); nil = in while the strip is on.
    var outPlugged: Bool? = nil
    /// Clicking the MIDI OUT plug (nil: not clickable).
    var onPlug: (() -> Void)? = nil
    /// The MIDI OUT plug and its cable; off for the small pictures in Settings, where the cables only get in the way.
    var showsMIDIOut = true
    /// Extra magnification on top of the app's 1.5× (the debug gallery, the vector export; below 1 for the Settings headers).
    var zoom: CGFloat = 1

    @Environment(\.colorScheme) private var scheme

    static let height: CGFloat = StripGeometry.height * HardwareScale.app
    static func width(bands: Int) -> CGFloat { KeyringGeometry.stripWidth(bands: bands, scale: HardwareScale.app) }
    /// Keyring hole centre from the strip's top-left corner, in points.
    static func holeCenter(bands: Int) -> CGPoint { KeyringGeometry.stripHoleOffset(bands: bands, scale: HardwareScale.app) }
    /// The band count the frame is sized for: the wider one while a module comes or goes.
    static func frameBands(bands: Int, edit: StripEdit?) -> Int { edit.map { max($0.from, $0.to) } ?? bands }

    var body: some View {
        let s = HardwareScale.app * zoom
        let frame = Self.frameBands(bands: bands, edit: edit)
        let w = KeyringGeometry.stripWidth(bands: frame, scale: 1)
        let hole = KeyringGeometry.stripHoleOffset(bands: frame, scale: 1)
        let pose = edit?.pose(at: editTime) ?? StripEdit.rest(bands: bands)
        let geo = StripGeometry(width: w, pose: pose)
        let falling = pose.slots.first { $0.fall > 0 }
        let fallBy = StripEdit.fallOffset(falling?.fall ?? 0, hangDegrees: hangAngle)
        let fallX = falling.map { geo.moduleX($0.x) + StripGeometry.channel / 2 } ?? 0
        // Fade (and shrink a touch, as if dropping away) over its last 40 pt before its lowest corner, with a margin for
        // the tumble, would reach the panel's edge.
        let fallOpacity: Double = {
            guard let falling, let fallRoom else { return 1 }
            let x0 = geo.moduleX(falling.x) - hole.x
            let rect = CGRect(x: x0, y: -hole.y - EjectKey.out, width: StripGeometry.channel, height: StripGeometry.height + EjectKey.out)
            let clearance = fallRoom - StripEdit.lowestBelowHole(rect, hangDegrees: hangAngle) - 8
            return StripEdit.fallOpacity(fall: falling.fall, clearance: clearance, fadeOver: 40 / HardwareScale.app)
        }()
        let removable = bands > Int(VC_MIN_TRIGGER_BANDS), full = bands >= Int(VC_MAX_TRIGGER_BANDS)
        // MIDI OUT low on the left cap's free edge, beside the channel LCD; unplugged while the strip is off. Its cable
        // swoops down in one arc, sagging with world-down at the strip's rest angle (part coordinates: down and away
        // from the strip), and goes in behind the strip under its bottom-left corner.
        let jack = MIDIOutJack(plugged: outPlugged ?? isOn, peek: plugPeek, tuck: CGPoint(x: -10, y: 21), arrive: CGVector(dx: -0.85, dy: -0.53),
                               braid: .black, scale: s)
        let outline = Self.outline(geo: geo, jack: showsMIDIOut ? jack : nil, scale: s)
        ZStack(alignment: .topLeading) {
            ModuleOutline(path: outline, size: CGSize(width: w * s, height: StripGeometry.height * s))
            jack
                .opacity(showsMIDIOut ? 1 : 0)
                .scaleEffect(x: -1, y: 1, anchor: .topLeading)
                .offset(x: geo.leftX * s, y: StripGeometry.midiOutY * s)
            StripBody(bands: bands, edit: edit, pose: pose, levels: levels, isOn: isOn, channel: channel, powerOn: powerOn,
                      falling: nil, learnHint: onLearn != nil, dark: scheme == .dark, scale: s)
            Grommet(opening: Grommet.opening * s, outer: Grommet.outer * s)
                .offset(x: (hole.x - Grommet.outer) * s, y: (hole.y - Grommet.outer) * s)
            MIDIOutHit(plugged: outPlugged ?? isOn, isFront: isFront && edit == nil && onPlug != nil,
                       origin: CGPoint(x: geo.leftX * s, y: StripGeometry.midiOutY * s), unit: s, onPlug: { onPlug?() },
                       onHover: onPlugHover)
            // MIDI learn: each band module's body (under the eject keys, which stay on top) while unplugged.
            ForEach(0..<Int(VC_MAX_TRIGGER_BANDS), id: \.self) { k in
                let slot = k < pose.slots.count ? pose.slots[k] : nil
                Color.clear
                    .frame(width: StripGeometry.channel * s, height: StripGeometry.height * s)
                    .moduleControl(isFront: isFront && edit == nil && onLearn != nil && slot != nil, label: "Learn CC \(MIDIReference.triggerCC(k))")
                    .accessibilityHidden(onLearn == nil || slot == nil)
                    .accessibilityAddTraits(.isButton)
                    .onTapGesture { onLearn?(k) }
                    .offset(x: geo.moduleX(slot?.x ?? 0) * s)
            }
            BitmapBabeSticker(scale: s).offset(x: (w - BitmapBabeSticker.cap.width) * s)  // on the right end cap, just below the hole
            PrideFlagSticker(scale: s).offset(x: (w - BitmapBabeSticker.cap.width) * s)  // low on the cap, over the BitmapBabe sticker's bottom end
            SlideSwitch(isOn: isOn, scale: s)
                // Hit area ≈ 21 × 29.5 units: past the cap's left edge and top, up to halfway to SET.
                .moduleControl(isFront: isFront, label: isOn ? "Turn BandsDance off" : "Turn BandsDance on",
                               grow: .units(top: 11, leading: 9, bottom: 1.5, trailing: 6, scale: s))
                .onTapGesture(perform: onSlide)
                .accessibilityAddTraits(.isButton)
                .offset(x: (geo.leftX + 6.5) * s, y: 9 * s)
            Button(action: onSet) { EmptyView() }
                .buttonStyle(HardwareKeyStyle { pressed in PillKey(label: "SET", pressed: pressed, scale: s) })
                // Hit area ≈ 21 × 30.5 units: from halfway to the slide down to the MIDI OUT plug's area.
                .moduleControl(isFront: isFront, label: "BandsDance settings",
                               grow: .units(top: 1.5, leading: 9, bottom: 12, trailing: 6, scale: s))
                .offset(x: (geo.leftX + 6.5) * s, y: StripGeometry.setTop * s)
            // One eject key per possible module (constant structure); unused ones and a falling one's are hidden
            // (the falling module draws its own).
            ForEach(0..<Int(VC_MAX_TRIGGER_BANDS), id: \.self) { k in
                let slot = k < pose.slots.count ? pose.slots[k] : nil
                let shown = slot != nil && slot!.fall == 0
                Button { onEject(k) } label: { EmptyView() }
                    .buttonStyle(HardwareKeyStyle { pressed in
                        EjectKey(pressed: pressed, locked: !removable, scale: s).padding(EjectKey.hitPadding * s)
                            .contentShape(Rectangle())  // the padding counts too (inside the style, or it's see-through)
                    })
                    .moduleControl(isFront: isFront && edit == nil && removable && shown, label: "Remove band \(k + 1)")
                    .opacity(shown ? slot!.opacity : 0)
                    .accessibilityHidden(!shown || edit != nil)
                    .offset(x: (geo.moduleX(slot?.x ?? 0) + (StripGeometry.channel - EjectKey.width) / 2 - EjectKey.hitPadding.leading) * s,
                            y: (-EjectKey.out + (slot?.lift ?? 0) - EjectKey.hitPadding.top) * s)
            }
            // The right cap's add button, below the sticker.
            let pad = AddButton.hitRadius - AddButton.radius
            Button(action: onAdd) { EmptyView() }
                .buttonStyle(HardwareKeyStyle { pressed in AddButton(pressed: pressed, locked: full, scale: s).padding(pad * s).contentShape(Circle()) })
                .contentShape(Circle())
                .overlay { Circle().fill(DebugHitAreas.on && isFront && edit == nil && !full ? DebugHitAreas.fill : .clear).allowsHitTesting(false) }
                .allowsHitTesting(isFront && edit == nil && !full)
                .pointerStyle(isFront && edit == nil && !full ? .link : nil)
                .accessibilityLabel(Text(verbatim: "Add band"))
                .offset(x: (geo.rightX + AddButton.center.x - AddButton.hitRadius) * s, y: (AddButton.center.y - AddButton.hitRadius) * s)
            // An ejected module falling out, in front of the strip, straight down in the world.
            StripBody(bands: bands, edit: edit, pose: pose, levels: levels, isOn: isOn, channel: channel, powerOn: powerOn,
                      falling: falling, fallLayer: true, dark: scheme == .dark, scale: s)
                .rotationEffect(.degrees(falling?.spin ?? 0), anchor: UnitPoint(x: fallX / w, y: 0.5))
                .scaleEffect(1 - 0.08 * (1 - fallOpacity), anchor: UnitPoint(x: fallX / w, y: 0.5))
                .opacity(fallOpacity)
                .offset(x: fallBy.x * s, y: fallBy.y * s)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            ModuleOutline.debug(outline, size: CGSize(width: w * s, height: StripGeometry.height * s))
        }
        .frame(width: w * s, height: StripGeometry.height * s, alignment: .topLeading)
    }

    /// Where the strip is drawn for a pose (its hit area, `ModuleOutline`), in points: the end caps, each module that is in
    /// (lifted ones where they are now, not a falling one) with its eject key, and the MIDI OUT socket, plug and cable.
    static func outline(geo: StripGeometry, jack: MIDIOutJack?, scale s: CGFloat) -> Path {
        let left = CGRect(x: geo.leftX, y: 0, width: StripGeometry.leftCap, height: StripGeometry.height)
        let right = CGRect(x: geo.rightX, y: 0, width: StripGeometry.rightCap, height: StripGeometry.height)
        var p = cornerPath(left, 13, 3, 3, 13).union(cornerPath(right, 3, 13, 13, 3))
        for slot in geo.pose.slots where slot.fall == 0 && slot.opacity > 0 {
            let x = geo.moduleX(slot.x)
            p = p.union(cornerPath(CGRect(x: x, y: slot.lift, width: StripGeometry.channel, height: StripGeometry.height), 3, 3, 3, 3))
                .union(Path(CGRect(x: x + (StripGeometry.channel - EjectKey.width) / 2, y: slot.lift - EjectKey.out,
                                   width: EjectKey.width, height: EjectKey.out)))
        }
        p = p.scaled(s)
        guard let jack else { return p }
        return p.union(jack.outline(mirroredAt: CGPoint(x: geo.leftX * s, y: StripGeometry.midiOutY * s), unit: s))
    }
}

private extension EdgeInsets {
    static func * (e: EdgeInsets, s: CGFloat) -> EdgeInsets {
        EdgeInsets(top: e.top * s, leading: e.leading * s, bottom: e.bottom * s, trailing: e.trailing * s)
    }
}

/// Caps, channel modules, LCDs and ladders in one Canvas (the levels redraw it), without any falling module.
/// As the `fallLayer` it draws only the `falling` module (dark, with its key), or nothing.
private struct StripBody: View {
    var bands: Int
    var edit: StripEdit?
    var pose: StripEdit.Pose
    var levels: [Float]
    var isOn: Bool
    var channel: Int
    var powerOn: [StripPowerOn.Module]?
    var falling: StripEdit.Slot?
    /// Unplugged, MIDI learn on: the channel LCD reads "LRn".
    var learnHint = false
    var fallLayer = false
    var dark: Bool
    var scale: CGFloat

    private static let leftCap = StripGeometry.leftCap, channel = StripGeometry.channel, rightCap = StripGeometry.rightCap
    /// Vertical layout of a channel module (1×): range LCD, ladder well, CC LCD.
    private static let rangeTop: CGFloat = 5, wellTop: CGFloat = 23, wellBottom: CGFloat = 81, ccTop: CGFloat = 85

    var body: some View {
        let frame = MIDIStripView.frameBands(bands: bands, edit: edit)
        let w = KeyringGeometry.stripWidth(bands: frame, scale: 1)
        let geo = StripGeometry(width: w, pose: pose)
        // Ranges and CC numbers: the old count until the modules snap together, then the new one.
        let rangeBands = pose.snapped ? bands : (edit?.from ?? bands)
        var lo = [Float](repeating: 0, count: rangeBands), hi = [Float](repeating: 0, count: rangeBands)
        vc_trigger_band_edges(Int32(rangeBands), &lo, &hi)
        let test = (0..<bands).map { i in isOn ? (powerOn.flatMap { i < $0.count ? $0[i] : nil } ?? .live) : nil }
        // Ejected modules and ones not yet snapped in have no power.
        func powered(_ slot: StripEdit.Slot) -> Int? {
            guard isOn, let new = slot.new, pose.snapped || slot.old != nil else { return nil }
            return new
        }
        let onlyFalling = fallLayer
        return PartCanvas(size: CGSize(width: w, height: StripGeometry.height),
                   bleed: EdgeInsets(top: edit == nil ? 4 : StripEdit.lift + 10, leading: 10, bottom: 18, trailing: 10), scale: scale) { ctx in
            // The keyring hole is drilled through the right cap (the grommet sits on top).
            let hole = KeyringGeometry.stripHoleOffset(bands: frame, scale: 1)
            let o = Grommet.opening
            ctx.clipOut(Path(ellipseIn: CGRect(x: hole.x - o, y: hole.y - o, width: 2 * o, height: 2 * o)))
            func rect(_ slot: StripEdit.Slot) -> CGRect { CGRect(x: geo.moduleX(slot.x), y: 0, width: Self.channel, height: StripGeometry.height) }
            func module(_ ctx: GraphicsContext, _ slot: StripEdit.Slot) {
                let x0 = geo.moduleX(slot.x)
                let i = powered(slot)
                let t = i.flatMap { test[$0] }
                let r = pose.snapped ? slot.new : slot.old
                let mode = i == nil ? .blank : (t?.lcd ?? .blank), level = t?.lcdLevel ?? 0
                let range: Set<String>, cc: Set<String>
                switch (mode, r) {
                case (.all, _): (range, cc) = (BandLCDs.rangeAll, BandLCDs.ccAll)
                case (.normal, let r?) where r < rangeBands:
                    let label = rangeBands == Int(VC_INSTRUMENT_BANDS)
                        ? BandLCDs.cells("r0d", BandLCD.instrument(r)) : BandLCDs.rangeLit(lo: Double(lo[r]), hi: Double(hi[r]))
                    (range, cc) = (label, BandLCDs.ccLit(MIDIReference.triggerCC(r)))
                default: (range, cc) = ([], [])
                }
                lcd(ctx, at: CGPoint(x: x0 + (Self.channel - BandLCDs.width) / 2, y: Self.rangeTop), size: BandLCDs.rangeSize,
                    elements: BandLCDs.range, lit: range, level: level)
                lcd(ctx, at: CGPoint(x: x0 + (Self.channel - BandLCDs.width) / 2, y: Self.ccTop), size: BandLCDs.ccSize,
                    elements: BandLCDs.cc, lit: cc, level: t?.ccLevel ?? level)
                let lit = i.map { i in t?.ladder ?? (i < levels.count ? Int((min(max(levels[i], 0), 1) * 10).rounded()) : 0) } ?? 0
                ladder(ctx, x0: x0, lit: lit)
            }
            /// A module out of line (dropping in or falling out): its own shadow and plastic, then its face.
            func loose(_ l: GraphicsContext, _ slot: StripEdit.Slot) {
                let r = rect(slot), p = cornerPath(r, 3, 3, 3, 3)
                var sh = l
                sh.addFilter(.blur(radius: 5))
                sh.fill(p.offsetBy(dx: 0, dy: 6 + max(0, -slot.lift) * 0.15), with: .color(.black.opacity(0.28)))
                plastic(l, r, p)
                module(l, slot)
            }

            if onlyFalling {
                guard let slot = falling else { return }
                var key = ctx
                key.translateBy(x: rect(slot).minX + (Self.channel - EjectKey.width) / 2, y: -EjectKey.out)
                EjectKey.draw(key)
                loose(ctx, slot)
                return
            }

            // Caps (CSS corner order tl, tr, br, bl), then the modules sitting in the strip.
            let left = CGRect(x: geo.leftX, y: 0, width: Self.leftCap, height: StripGeometry.height)
            let right = CGRect(x: geo.rightX, y: 0, width: Self.rightCap, height: StripGeometry.height)
            let caps = [(left, cornerPath(left, 13, 3, 3, 13)), (right, cornerPath(right, 3, 13, 13, 3))]
            let seated = pose.slots.filter { $0.lift == 0 && $0.opacity == 1 && $0.fall == 0 }
            let moving = pose.slots.filter { ($0.lift != 0 || $0.opacity != 1) && $0.fall == 0 }
            let shapes = caps + seated.map { (rect($0), cornerPath(rect($0), 3, 3, 3, 3)) }

            // 0 6px 10px -2px rgba(0,0,0,.28) under the whole strip (the −2 spread is left out)
            var shadow = ctx
            shadow.addFilter(.blur(radius: 5))
            for (_, p) in shapes { shadow.fill(p.offsetBy(dx: 0, dy: 6), with: .color(.black.opacity(0.28))) }
            for (r, p) in shapes { plastic(ctx, r, p) }
            channelLCD(ctx, x0: geo.leftX, test: test.first ?? nil)

            for slot in seated { module(ctx, slot) }
            // A module dropping in: lifted and faded as one layer.
            for slot in moving {
                var layer = ctx
                layer.opacity = slot.opacity
                layer.drawLayer { l in
                    l.translateBy(x: 0, y: slot.lift)
                    loose(l, slot)
                }
            }

        }
        .accessibilityElement()
        .accessibilityLabel(Text(verbatim: isOn ? "BandsDance, \(bands) bands, MIDI channel \(channel)" : "BandsDance off"))
    }

    /// The left cap's MIDI channel LCD ("CH16" on a CC-sized glass running along the cap, reading top to bottom
    /// like the SET label); follows the first module through the self-test.
    private func channelLCD(_ ctx: GraphicsContext, x0: CGFloat, test: StripPowerOn.Module?) {
        let mode = test?.lcd ?? .blank, level = test?.lcdLevel ?? 0
        let lit: Set<String>
        switch mode {
        case .blank: lit = []
        case .all: lit = BandLCDs.ccAll
        case .normal: lit = BandLCDs.cells("c", learnHint ? BandLCD.learn() : BandLCD.channel(channel))
        }
        let size = BandLCDs.ccSize
        let upright = CGSize(width: size.height / BandLCDs.unit, height: size.width / BandLCDs.unit)
        lcd(ctx, at: CGPoint(x: x0 + (Self.leftCap - upright.width) / 2, y: StripGeometry.channelLCDCenterY - upright.height / 2), size: size,
            elements: BandLCDs.cc, lit: lit, level: level, turned: true)
    }

    /// Warm grey / dark grey moulded plastic with its own edges: light left + top, dark right = a groove where two meet.
    private func plastic(_ ctx: GraphicsContext, _ rect: CGRect, _ shape: Path) {
        let line = cssGradientLine(170, in: rect)
        let stops: [Color] = dark ? [hex(0x45464a), hex(0x36373b), hex(0x2c2d30)] : [hex(0xdedad2), hex(0xcfcac0), hex(0xc3bdb2)]
        ctx.fill(shape, shaded: .linearGradient(
            Gradient(stops: [.init(color: stops[0], location: 0), .init(color: stops[1], location: 0.6), .init(color: stops[2], location: 1)]),
            startPoint: line.start, endPoint: line.end))
        // radial-gradient(120% 90% at 30% 0%, white .45/.10, transparent 55%): an ellipse, so squash a circle
        var hi = ctx
        hi.clip(to: shape)
        hi.translateBy(x: rect.minX + rect.width * 0.3, y: rect.minY)
        let rx = rect.width * 1.2, ry = rect.height * 0.9
        hi.scaleBy(x: rx / ry, y: 1)
        hi.fill(Path(ellipseIn: CGRect(x: -ry, y: -ry, width: ry * 2, height: ry * 2)), shaded: .radialGradient(
            Gradient(stops: [.init(color: .white.opacity(dark ? 0.10 : 0.45), location: 0), .init(color: .white.opacity(0), location: 0.55)]),
            center: .zero, startRadius: 0, endRadius: ry))
        // inset 1px 0 0 white .18, inset -1px 0 0 black .35, inset 0 1px 0 white .25
        ctx.insetShadow(in: shape, dx: 1, dy: 0, color: .white.opacity(0.18))
        ctx.insetShadow(in: shape, dx: -1, dy: 0, color: .black.opacity(0.35))
        ctx.insetShadow(in: shape, dy: 1, color: .white.opacity(0.25))
    }

    /// A small segment LCD set into the plastic: a window like the ladder's well (light edge under,
    /// inset shadow) with the glass 0.75 in from its edge. `size` is in LCD units (BandLCDs.unit per point).
    /// `turned`: mounted a quarter turn clockwise (the channel LCD along the cap); `origin` is then the upright
    /// glass's top-left and only the segments turn, the window and the glass's light stay as on every other LCD.
    private func lcd(_ ctx: GraphicsContext, at origin: CGPoint, size: CGSize, elements: [LCDElement], lit: Set<String>, level: Double,
                     turned: Bool = false) {
        let w = size.width / BandLCDs.unit, h = size.height / BandLCDs.unit
        let glassRect = CGRect(origin: origin, size: turned ? CGSize(width: h, height: w) : CGSize(width: w, height: h))
        let window = Path(roundedRect: glassRect.insetBy(dx: -0.75, dy: -0.75), cornerRadius: 1.8)
        ctx.fill(window.offsetBy(dx: 0, dy: 1), with: .color(.white.opacity(dark ? 0.12 : 0.7)))
        ctx.fill(window, with: .color(dark ? hex(0x121212) : hex(0x2b2a27)))
        var glass = ctx
        if turned {
            glass.translateBy(x: glassRect.maxX, y: glassRect.minY)
            glass.rotate(by: .degrees(90))
        } else {
            glass.translateBy(x: glassRect.minX, y: glassRect.minY)
        }
        glass.scaleBy(x: 1 / BandLCDs.unit, y: 1 / BandLCDs.unit)
        SegmentLCD.draw(in: glass, size: size, corner: CGSize(width: 2, height: 2), elements: elements,
                        isLit: { lit.contains($0.name) }, dark: dark, glow: BandLCDs.glow, litLevel: level, turned: turned)
        ctx.insetShadow(in: window, dy: 1, blur: 2, color: .black.opacity(dark ? 0.8 : 0.7))
    }

    /// The 10-step ladder (sides 7; padding 2, gap 2), filled from the bottom.
    private func ladder(_ ctx: GraphicsContext, x0: CGFloat, lit: Int) {
        let well = CGRect(x: x0 + 7, y: Self.wellTop, width: Self.channel - 14, height: Self.wellBottom - Self.wellTop)
        let wellPath = Path(roundedRect: well, cornerRadius: 2)
        ctx.fill(wellPath.offsetBy(dx: 0, dy: 1), with: .color(.white.opacity(dark ? 0.12 : 0.7)))
        ctx.fill(wellPath, with: .color(dark ? hex(0x121212) : hex(0x2b2a27)))
        ctx.insetShadow(in: wellPath, dy: 1, blur: 2, color: .black.opacity(dark ? 0.8 : 0.7))
        let inner = well.insetBy(dx: 2, dy: 2)
        let segH = (inner.height - 2 * 9) / 10
        for k in 0..<10 {
            let r = CGRect(x: inner.minX, y: inner.maxY - CGFloat(k + 1) * segH - CGFloat(k) * 2, width: inner.width, height: segH)
            let seg = Path(roundedRect: r, cornerRadius: 1)
            if k < lit {
                let color = k >= 8 ? hex(0xffd23a) : hex(0xff5a1f)
                var glow = ctx
                glow.addFilter(.shadow(color: color.opacity(0.9), radius: 2))
                glow.fill(seg, with: .color(color))
            } else {
                ctx.fill(seg, with: .color(hex(0x4a2a1d)))
            }
        }
    }
}

/// The strip's two LCD layouts, in LCD units (`unit` per point): the range display (two rows of three
/// digits, a decimal point after the second, a "k" annunciator per row) and the CC display (four cells).
private enum BandLCDs {
    static let unit: CGFloat = 2
    /// Width of both glasses in points.
    static let width: CGFloat = 18
    static let rangeSize = CGSize(width: 36, height: 28)
    static let ccSize = CGSize(width: 36, height: 16)
    /// Dark-mode backlight blur, in units.
    static let glow: CGFloat = 0.8

    static let cellW: CGFloat = 6.4, cellH: CGFloat = 10, cellGap: CGFloat = 2.3, stroke: CGFloat = 1.8, skew: CGFloat = 0.08
    static func cell(_ x: CGFloat, _ y: CGFloat) -> [Segment: Path] {
        SegmentLCD.sevenSeg(x, y, cellW, cellH, stroke, skew, gap: 0.45)
    }

    static let range: [LCDElement] = {
        var els: [LCDElement] = []
        let x0: CGFloat = 3
        for row in 0..<2 {
            let y = 3 + CGFloat(row) * 12
            for c in 0..<3 { els += SegmentLCD.digitElements("r\(row)d\(c)", cell(x0 + CGFloat(c) * (cellW + cellGap), y)) }
            let dpX = x0 + 2 * cellW + cellGap + (cellGap - 1.5) / 2
            els.append(LCDElement(name: "r\(row)dp", kind: .fill(Path(CGRect(x: dpX, y: y + cellH - 1.5, width: 1.5, height: 1.5)))))
            // lower-case k after the digits, slanted like them
            let kx = x0 + 3 * cellW + 2 * cellGap + 1.8
            func P(_ dx: CGFloat, _ dy: CGFloat) -> CGPoint { CGPoint(x: kx + dx + skew * (cellH - dy), y: y + dy) }
            let k = Path { p in
                p.move(to: P(0.6, 0.7)); p.addLine(to: P(0.6, cellH - 0.7))
                p.move(to: P(3.6, 4.2)); p.addLine(to: P(0.9, 6.9)); p.addLine(to: P(3.8, cellH - 0.7))
            }
            els.append(LCDElement(name: "r\(row)k", kind: .stroke(k, 1.2)))
        }
        return els
    }()

    static let cc: [LCDElement] = {
        let x0 = (ccSize.width - 4 * cellW - 3 * cellGap) / 2
        return (0..<4).flatMap { c in SegmentLCD.digitElements("c\(c)", cell(x0 + CGFloat(c) * (cellW + cellGap), 3)) }
    }()

    /// Every element: the self-test's "all segments" frame.
    static let rangeAll = Set(range.map(\.name))
    static let ccAll = Set(cc.map(\.name))

    static func rangeLit(lo: Double, hi: Double) -> Set<String> {
        var on = Set<String>()
        for (row, hz) in [lo, hi].enumerated() {
            let f = BandLCD.frequency(hz)
            for (c, segs) in f.cells.enumerated() { for seg in segs { on.insert("r\(row)d\(c)\(seg)") } }
            if f.decimalPoint { on.insert("r\(row)dp") }
            if f.kilo { on.insert("r\(row)k") }
        }
        return on
    }

    static func ccLit(_ number: Int) -> Set<String> { cells("c", BandLCD.cc(number)) }

    /// Element names of lit segments, cell by cell ("<prefix><cell><segment>").
    static func cells(_ prefix: String, _ cells: [Set<Segment>]) -> Set<String> {
        var on = Set<String>()
        for (c, segs) in cells.enumerated() { for seg in segs { on.insert("\(prefix)\(c)\(seg)") } }
        return on
    }
}

