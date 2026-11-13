// SPDX-License-Identifier: GPL-3.0-or-later
import VChainEngine
import VChainKit
import SwiftUI

/// The Energy module (the six descriptors, CC 9–14):
/// a yellow anodized body with a wide left bezel (keyring washer at the top; SET above power at the
/// bottom, a green status LED between; a right-angle MIDI OUT plug in the left edge next to power, `MIDIOutJack`, unplugged
/// while the CCs don't go out) and a black OLED touchscreen: header with a DIN icon + "CH 16" (the MIDI channel, `channel`)
/// and a 24-bar spectrum over the right column, then a 2 × 3 grid of labels with their CC
/// in grey and a slim white line per value. No value numbers; a descriptor that is off shows "OFF"
/// instead of its CC and an empty line. While its plug is pulled (`output` .unplugged), the header reads
/// "UNPLUGGED · LEARN" instead of "CH 16", the CCs turn dark grey and the status LED goes out. Drawn in its design's SVG units (300 × 212) × `HardwareScale.energy`.
/// Taps go to `onPower` / `onSet` / `onToggle(i)`; while `isFront` is false nothing hit-tests. Turned on by its
/// power key it runs a ≈1 s self-test first (`powerOn`, EnergyPowerOn): the screen's fixed graphics light up over
/// the ghosts it shows when off (everything at full, the ghosts, row after row, the spectrum), then go live.
struct EnergyModuleView: View {
    /// The six descriptor values, 0…1 (`LiveState.descriptorValues`).
    var values: [Float]
    /// Which descriptors are switched on (`EngineModel.descriptorsEnabled`).
    var enabled: [Bool]
    var isOn: Bool
    /// Whether the CCs actually go out (`EngineModel.energyOutput`).
    var output: Output = .sending
    /// The MIDI channel the CCs go out on (Settings › Annalisa › MIDI channel), for the header.
    var channel = Int(VC_MIDI_CHANNEL)
    /// Hovering the MIDI OUT plug (`PlugMotion.peek`, 0…1).
    var plugPeek: Double = 0
    /// The pointer entering or leaving the plug.
    var onPlugHover: (Bool) -> Void = { _ in }
    /// MIDI learn (while unplugged): clicking a row sends its CC as a sweep instead of switching it. Nil: off.
    var onLearn: ((Int) -> Void)? = nil
    /// The row being learned and its sweep value (0…1), shown on its line.
    var learning: LearnLine? = nil

    struct LearnLine: Equatable { var index: Int; var value: Double }
    /// Whether the MIDI OUT plug is in (`EngineModel.energyPlugged`); nil = in while the CCs go out.
    var outPlugged: Bool? = nil
    /// Clicking the MIDI OUT plug (nil: not clickable).
    var onPlug: (() -> Void)? = nil
    /// The MIDI OUT plug and its cable; off for the small pictures in Settings, where the cables only get in the way.
    var showsMIDIOut = true
    /// 24 bands, 0…1 (`LiveState.spectrum`).
    var spectrum: [Float]
    /// The power-on self-test's current frame, nil when not running.
    var powerOn: EnergyPowerOn.Frame? = nil
    var isFront: Bool
    var onPower: () -> Void
    var onSet: () -> Void
    var onToggle: (Int) -> Void
    /// Extra magnification on top of the app's scale (the debug gallery, the vector export; below 1 for the Settings headers).
    var zoom: CGFloat = 1

    @Environment(\.colorScheme) private var scheme

    /// The descriptor CCs: going out, or this module's plug pulled.
    enum Output: Equatable { case sending, unplugged }

    static let names = ["LOUDNESS", "INTENSITY", "BRIGHTNESS", "TONE", "CHANGE", "TEXTURE"]
    /// The body in its design's SVG units (× `HardwareScale.energy` = points) and its corner radius.
    static let design = KeyringGeometry.energyDesignSize, cornerRadius: CGFloat = 32
    static let size = CGSize(width: KeyringGeometry.energySize.width * HardwareScale.app, height: KeyringGeometry.energySize.height * HardwareScale.app)
    /// Keyring hole centre from the body's top-left corner, in points.
    static let holeCenter = CGPoint(x: KeyringGeometry.energyHole.x * HardwareScale.app, y: KeyringGeometry.energyHole.y * HardwareScale.app)

    var body: some View {
        let e = HardwareScale.energy * zoom
        let frame = CGSize(width: Self.design.width * e, height: Self.design.height * e)
        // MIDI OUT on the left edge, its axis level with the power key's centre (y 176): plugged while the CCs go
        // out. Its cable's shape for the 45° hang (in the part's mirrored coordinates): it drops,
        // swings out to the left sagging well below the module's left corner, sweeps back right under the module
        // and goes in behind its bottom edge about a third of the way along (level with the CHANGE row on
        // screen): one cubic, so one smooth hanging arc. A black/yellow braid.
        let jack = MIDIOutJack(plugged: outPlugged ?? (isOn && output == .sending), peek: plugPeek, tuck: CGPoint(x: -64, y: 17.5),
                               arrive: CGVector(dx: -0.86, dy: -0.5), startHandle: 44, endHandle: 16, braid: .blackYellow, scale: HardwareScale.app * zoom)
        ZStack(alignment: .topLeading) {
            ModuleOutline(path: outline(jack, e: e), size: frame)
            jack
                .opacity(showsMIDIOut ? 1 : 0)
                .scaleEffect(x: -1, y: 1, anchor: .topLeading)
                .offset(x: 0, y: 176 * e)
            EnergyBody(dark: scheme == .dark, scale: e)
            EnergyScreen(values: values, enabled: enabled, isOn: isOn, output: output, channel: channel, spectrum: spectrum, powerOn: powerOn,
                         learning: learning, scale: e)
            Washer(outer: 17.2 * e, opening: 6 * e).position(x: 26 * e, y: 26 * e)
            StatusLED(isOn: isOn && output == .sending, radius: 2.2 * e).position(x: 26 * e, y: 155 * e)
            MIDIOutHit(plugged: outPlugged ?? (isOn && output == .sending), isFront: isFront && onPlug != nil,
                       origin: CGPoint(x: 0, y: 176 * e), unit: HardwareScale.app * zoom, onPlug: { onPlug?() },
                       onHover: onPlugHover)
            Button(action: onSet) { EmptyView() }
                .buttonStyle(HardwareKeyStyle { pressed in
                    TEKey(cap: TEKey.setCap, edge: TEKey.setEdge, glyph: .sliders, pressed: pressed, radius: 15 * e)
                })
                // Keys are 30 SVG units across; the hit areas 38 (30 pt), still apart (centres 44 apart).
                .moduleControl(isFront: isFront, label: "Annalisa settings", grow: .all(4 * e), centered: true)
                .position(x: 26 * e, y: 132 * e)
            Button(action: onPower) { EmptyView() }
                .buttonStyle(HardwareKeyStyle { pressed in
                    TEKey(cap: TEKey.powerCap, edge: TEKey.powerEdge, glyph: .power, pressed: pressed || !isOn, radius: 15 * e)
                })
                .moduleControl(isFront: isFront, label: isOn ? "Turn Annalisa off" : "Turn Annalisa on", grow: .all(4 * e), centered: true)
                .position(x: 26 * e, y: 176 * e)
            // Touch cells: one per descriptor (dead while the screen is off).
            ForEach(0..<6, id: \.self) { i in
                Color.clear
                    .frame(width: 106 * e, height: 46 * e)
                    .moduleControl(isFront: isFront && isOn, label: onLearn != nil ? "Learn CC \(MIDIReference.descriptorCC(i))" : Self.names[i])
                    .accessibilityValue(Text(verbatim: !isEnabled(i) ? "off" : (output == .sending ? "on" : "on, unplugged")))
                    .accessibilityAddTraits(.isButton)
                    .onTapGesture { if let onLearn { onLearn(i) } else { onToggle(i) } }
                    .position(x: (56 + EnergyScreen.cellX(i) + 48) * e, y: (16 + EnergyScreen.cellY(i) + 19) * e)
            }
            ModuleOutline.debug(outline(jack, e: e), size: frame)
        }
        .frame(width: Self.design.width * e, height: Self.design.height * e, alignment: .topLeading)
    }

    /// Where the module is drawn (its hit area, `ModuleOutline`), in points: the body and the MIDI OUT socket, plug and cable.
    private func outline(_ jack: MIDIOutJack, e: CGFloat) -> Path {
        let body = Path(roundedRect: CGRect(origin: .zero, size: Self.design), cornerRadius: Self.cornerRadius, style: .continuous).scaled(e)
        guard showsMIDIOut else { return body }
        return body.union(jack.outline(mirroredAt: CGPoint(x: 0, y: 176 * e), unit: HardwareScale.app * zoom))
    }

    private func isEnabled(_ i: Int) -> Bool { i < enabled.count ? enabled[i] : true }
}

/// Yellow anodized body, chamfer highlight, glass; the keyring hole drilled through.
private struct EnergyBody: View {
    var dark: Bool
    var scale: CGFloat

    var body: some View {
        PartCanvas(size: EnergyModuleView.design, bleed: EdgeInsets(top: 12, leading: 20, bottom: 34, trailing: 20), scale: scale) { ctx in
            let rect = CGRect(origin: .zero, size: EnergyModuleView.design)
            let shape = Path(roundedRect: rect, cornerRadius: EnergyModuleView.cornerRadius, style: .continuous)
            // The keyring hole (the washer sits on top).
            ctx.clipOut(Path(ellipseIn: CGRect(x: 20, y: 20, width: 12, height: 12)))
            // feDropShadow dy 6, stdDeviation 7, .45
            ctx.dropShadow(of: rect, radius: 32, dy: 6, blur: 14, color: .black.opacity(0.45))
            let metal: [Color] = dark ? [hex(0xffd437), hex(0xf1bd14), hex(0xd9a209)] : [hex(0xffe066), hex(0xffcf26), hex(0xf0b90d)]
            ctx.fill(shape, shaded: .linearGradient(
                Gradient(stops: [.init(color: metal[0], location: 0), .init(color: metal[1], location: 0.6), .init(color: metal[2], location: 1)]),
                startPoint: .zero, endPoint: CGPoint(x: 75, y: EnergyModuleView.design.height)))
            // chamfer: a light edge shifted .8 down, a dark hairline on the edge
            ctx.stroke(shape.offsetBy(dx: 0, dy: 0.8), with: .color(.white.opacity(dark ? 0.22 : 0.75)), lineWidth: 1.2)
            ctx.stroke(shape, with: .color(.black.opacity(0.35)), lineWidth: 0.8)
            // Glass: inset 12 from the top/right/bottom edges → radius 32 − 12 = 20 on all four corners.
            let glass = Path(roundedRect: CGRect(x: 52, y: 12, width: 236, height: 188), cornerRadius: innerRadius(outer: 32, inset: 12), style: .continuous)
            ctx.fill(glass, with: .color(hex(0x0b0b0b)))
            ctx.stroke(glass, with: .color(.black.opacity(0.55)), lineWidth: 1.2)
        }
        .accessibilityHidden(true)
    }
}

/// The OLED: black active area inset 4 inside the glass (radius 20 − 4 = 16), white and grey only.
private struct EnergyScreen: View {
    var values: [Float]
    var enabled: [Bool]
    var isOn: Bool
    var output: EnergyModuleView.Output
    var channel: Int
    var spectrum: [Float]
    var powerOn: EnergyPowerOn.Frame?
    var learning: EnergyModuleView.LearnLine?
    var scale: CGFloat

    static func cellX(_ i: Int) -> CGFloat { 12 + CGFloat(i % 2) * 110 }
    static func cellY(_ i: Int) -> CGFloat { 38 + CGFloat(i / 2) * 48 }
    private static let white = hex(0xf2f2f2), grey = hex(0x8a8a8a), dim = hex(0x262626)
    /// The right column of the grid: x 122…218 (cell width 96).
    private static let column: ClosedRange<CGFloat> = 122...218
    /// The value line's height: 3 pt at app scale, in SVG units.
    private static let lineHeight: CGFloat = 3 / HardwareScale.energy

    var body: some View {
        Canvas { ctx, _ in
            ctx.scaleBy(x: scale, y: scale)
            ctx.clip(to: Path(roundedRect: CGRect(x: 53, y: 13, width: 234, height: 186), cornerRadius: innerRadius(outer: 20, inset: 1), style: .continuous))
            var screen = ctx
            screen.translateBy(x: 56, y: 16)
            screen.opacity = isOn ? 1 : Self.ghost
            screen.drawLayer { layer in draw(&layer) }
            // glass glare
            ctx.fill(Path { p in
                p.move(to: CGPoint(x: 52, y: 12)); p.addLine(to: CGPoint(x: 288, y: 12)); p.addLine(to: CGPoint(x: 288, y: 40))
                p.addQuadCurve(to: CGPoint(x: 52, y: 140), control: CGPoint(x: 202, y: 70)); p.closeSubpath()
            }, with: .color(.white.opacity(0.045)))
        }
        .frame(width: EnergyModuleView.design.width * scale, height: EnergyModuleView.design.height * scale)
        .accessibilityHidden(true)
    }

    /// How faintly the graphics show when off (the screen's ghosts).
    static let ghost = 0.08

    private func draw(_ g: inout GraphicsContext) {
        g.fill(Path(roundedRect: CGRect(x: 0, y: 0, width: 228, height: 180), cornerRadius: innerRadius(outer: 20, inset: 4), style: .continuous),
               with: .color(.black))
        func type(_ s: String, _ size: CGFloat, _ color: Color) -> Text {
            Text(verbatim: s).font(Brand.monoline(size, weight: .regular)).tracking(0.5).foregroundStyle(color)
        }
        // During the self-test each element shows between its ghost (0) and lit (1); otherwise everything is lit.
        func lit(_ level: Double) -> GraphicsContext {
            var c = g
            c.opacity = powerOn == nil ? 1 : Self.ghost + (1 - Self.ghost) * level
            return c
        }
        // Header: 5-pin DIN icon + "CH 16", spectrum bars over the right column, divider.
        let head = lit(powerOn?.header ?? 1)
        let din = CGPoint(x: 17, y: 14)
        head.stroke(Path(ellipseIn: CGRect(x: din.x - 5, y: din.y - 5, width: 10, height: 10)), with: .color(Self.grey), lineWidth: 1.2)
        for (dx, dy) in [(-2.6, 0.6), (-1.8, -1.9), (0, -2.8), (1.8, -1.9), (2.6, 0.6)] {
            head.fill(Path(ellipseIn: CGRect(x: din.x + dx - 0.65, y: din.y + dy - 0.65, width: 1.3, height: 1.3)), with: .color(Self.grey))
        }
        head.fill(Path(CGRect(x: din.x - 1, y: din.y + 3.6, width: 2, height: 1.6)), with: .color(Self.grey))
        let header = switch output { case .sending: "CH \(channel)"; case .unplugged: "UNPLUGGED · LEARN" }
        head.draw(type(header, 14, output == .sending ? Self.white : Self.grey), x: 27, baseline: 18.5)
        let ccInk = output == .sending ? Self.grey : Self.grey.opacity(0.4)

        // Spectrum: 24 slim vertical bars over the right column, growing up from the divider.
        let bars = lit(powerOn?.spectrumLit ?? 1)
        let pitch = (Self.column.upperBound - Self.column.lowerBound) / 24, barWidth = pitch * 0.6
        let bottom: CGFloat = 24, top: CGFloat = 5
        for c in 0..<24 {
            let level = CGFloat(powerOn.flatMap { $0.spectrum[c] } ?? Double(c < spectrum.count ? min(max(spectrum[c], 0), 1) : 0))
            let x = Self.column.lowerBound + CGFloat(c) * pitch + (pitch - barWidth) / 2
            bars.fill(Path(CGRect(x: x, y: bottom - 1, width: barWidth, height: 1)), with: .color(Self.dim))
            if level > 0 {
                let h = (bottom - top) * level
                bars.fill(Path(CGRect(x: x, y: bottom - h, width: barWidth, height: h)), with: .color(Self.white))
            }
        }
        head.fill(Path(CGRect(x: 12, y: 27.5, width: Self.column.upperBound - 12, height: 1)), with: .color(Self.dim))

        // Grid: label left, CC (or OFF) right, a slim line under it that grows with the value.
        for i in 0..<6 {
            let row = lit(powerOn?.rows[i] ?? 1)
            let x = Self.cellX(i), y = Self.cellY(i), width: CGFloat = 96
            let on = i < enabled.count ? enabled[i] : true
            let live = Double(on && i < values.count ? min(max(values[i], 0), 1) : 0)
            let value = CGFloat(powerOn.flatMap { $0.lines[i] } ?? (learning?.index == i ? learning!.value : live))
            row.draw(type(EnergyModuleView.names[i], 19, on ? Self.white : Self.white.opacity(0.28)), x: x, baseline: y + 18)
            row.draw(type(on ? "CC \(9 + i)" : "OFF", 15, ccInk), x: x + width, baseline: y + 18, anchor: .end)
            let h = Self.lineHeight
            row.fill(Path(roundedRect: CGRect(x: x, y: y + 31, width: width, height: h), cornerRadius: h / 2), with: .color(Self.dim))
            if value > 0 {
                row.fill(Path(roundedRect: CGRect(x: x, y: y + 31, width: max(h, width * value), height: h), cornerRadius: h / 2), with: .color(Self.white))
            }
        }
    }
}

extension EngineModel {
    /// What the Energy module's CCs do: going out, or its plug pulled.
    var energyOutput: EnergyModuleView.Output { energySending ? .sending : .unplugged }
}
