// SPDX-License-Identifier: GPL-3.0-or-later
import VChainKit
import SwiftUI

/// Debug window (`-debugOpen modules`, page via `-modulesPage bpm|midi|power|energy|keychain`): each keychain module
/// at real size (1×) in its states and at 2×, to check them via `-debugSnapshot`; `keychain` hangs
/// the whole keychain at rest (ring, modules, bead charms) with 3 and 8 bands and each item in front.
/// The window title names the page, so each page snapshots to its own file.
struct ModuleGallery: View {
    enum Page: String, CaseIterable { case bpm, midi, power, energy, keychain }

    @ViewState private var page: Page = Page(rawValue: UserDefaults.standard.string(forKey: "modulesPage") ?? "") ?? .bpm
    @Environment(\.colorScheme) private var scheme
    private var dark: Bool { scheme == .dark }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Picker(selection: $page) {
                ForEach(Page.allCases, id: \.self) { Text(verbatim: $0.rawValue.uppercased()).tag($0) }
            } label: { EmptyView() }
                .pickerStyle(.segmented)
                .fixedSize()
            switch page {
            case .bpm: bpmPage
            case .midi: midiPage
            case .power: powerPage
            case .energy: energyPage
            case .keychain: keychainPage
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .galleryBackdrop(dark: dark)
        .navigationTitle(Text(verbatim: "Modules \(page.rawValue.uppercased())"))
    }

    private func section<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(verbatim: title.uppercased()).font(.system(size: 11, weight: .semibold)).tracking(0.9)
                .foregroundStyle(dark ? hex(0xc9c6bf) : hex(0x5a564e))
            content()
        }
    }

    private func caption(_ t: String) -> some View {
        Text(verbatim: t).font(.system(size: 11)).foregroundStyle(dark ? hex(0xa7a59f) : hex(0x5a564e))
    }

    // MARK: BPM

    static let bpmStates: [(String, BPMTagState)] = [
        ("locked, beat 3, linked", SampleData.tag()),
        ("locked, the 1, alone", SampleData.tag(bpm: 99.5, phase: 0.2, peers: 0)),
        ("settling (low confidence)", SampleData.tag(bpm: 127.5, confidence: 0.05)),
        ("settling, no tempo yet", SampleData.tag(bpm: 0, hasTempo: false)),
        ("no input", SampleData.tag(problem: true)),
        ("off", SampleData.tag(enabled: false)),
    ]

    private var bpmPage: some View {
        VStack(alignment: .leading, spacing: 28) {
            section("BPM tag, real size") {
                HStack(alignment: .top, spacing: 64) {
                    ForEach(Self.bpmStates.indices, id: \.self) { i in
                        VStack(alignment: .leading, spacing: 22) {
                            BPMTagView(state: Self.bpmStates[i].1, isFront: true, onRocker: {}, onSet: {})
                            caption(Self.bpmStates[i].0)
                        }
                        .padding(.top, 10)
                    }
                }
            }
            section("BPM tag, 2×") {
                HStack(alignment: .top, spacing: 70) {
                    BPMTagView(state: Self.bpmStates[0].1, isFront: true, onRocker: {}, onSet: {}, zoom: 2)
                    BPMTagView(state: Self.bpmStates[4].1, isFront: true, onRocker: {}, onSet: {}, zoom: 2)
                }
                .padding(.top, 20)
            }
        }
    }

    // MARK: MIDI

    private static let levels: [Float] = [1, 0.55, 0.3, 0.85, 0.12, 0.7, 0, 0.45]

    private func strip(_ bands: Int, on: Bool, zoom: CGFloat = 1) -> some View {
        MIDIStripView(bands: bands, levels: Self.levels, isOn: on, isFront: true, onSlide: {}, onSet: {}, zoom: zoom)
    }

    private var midiPage: some View {
        VStack(alignment: .leading, spacing: 28) {
            section("MIDI strip, real size") {
                HStack(alignment: .top, spacing: 40) {
                    VStack(alignment: .leading, spacing: 16) { strip(3, on: true); caption("3 bands, on") }
                    VStack(alignment: .leading, spacing: 16) { strip(3, on: false); caption("3 bands, off") }
                    VStack(alignment: .leading, spacing: 16) { strip(2, on: true); caption("2 bands") }
                    VStack(alignment: .leading, spacing: 16) { strip(8, on: true); caption("8 bands") }
                }
            }
            section("MIDI strip, 2×") {
                HStack(alignment: .top, spacing: 40) {
                    strip(3, on: true, zoom: 2)
                    strip(3, on: false, zoom: 2)
                }
            }
        }
    }

    // MARK: MIDI power-on

    /// When the replay button was pressed (the live strip plays the self-test from then).
    @ViewState private var replayStart = Date.distantPast

    private func frame(_ bands: Int, at t: Double) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            MIDIStripView(bands: bands, levels: Self.levels, isOn: true, powerOn: StripPowerOn.modules(bands: bands, elapsed: t),
                          isFront: true, onSlide: {}, onSet: {})
            caption(String(format: "%.2f s", t))
        }
    }

    private var powerPage: some View {
        VStack(alignment: .leading, spacing: 28) {
            section("Power-on self-test, 3 bands (\(String(format: "%.2f", StripPowerOn.duration(bands: 3))) s)") {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(alignment: .top, spacing: 24) { ForEach([0.03, 0.12, 0.23, 0.33, 0.43], id: \.self) { frame(3, at: $0) } }
                    HStack(alignment: .top, spacing: 24) { ForEach([0.53, 0.63, 0.75, 0.86, 0.95, 1.1], id: \.self) { frame(3, at: $0) } }
                }
            }
            section("8 bands (\(String(format: "%.2f", StripPowerOn.duration(bands: 8))) s)") {
                HStack(alignment: .top, spacing: 24) { ForEach([0.4, 0.6, 0.95], id: \.self) { frame(8, at: $0) } }
            }
            section("Replay") {
                HStack(alignment: .top, spacing: 24) {
                    Button("Flip on") { replayStart = Date() }
                    TimelineView(.animation) { context in
                        MIDIStripView(bands: 3, levels: Self.levels, isOn: true,
                                      powerOn: StripPowerOn.modules(bands: 3, elapsed: context.date.timeIntervalSince(replayStart)),
                                      isFront: true, onSlide: { replayStart = Date() }, onSet: {}, zoom: 2)
                    }
                }
            }
        }
    }

    // MARK: Energy

    private static let values: [Float] = [0.53, 0.43, 0.5, 0.55, 0.55, 0.5]
    private static let spectrum: [Float] = (0..<24).map { (c: Int) -> Float in
        let x = Double(c)
        let tilt: Double = 1.15 - x / 36
        let wobble: Double = 0.35 + 0.65 * abs(sin(2.2 + x * 1.37))
        return Float(max(0, min(1, 0.936 * tilt * wobble)))
    }

    private static func energy(on: Bool, enabled: [Bool] = Array(repeating: true, count: 6), output: EnergyModuleView.Output = .sending,
                        zoom: CGFloat = 1) -> some View {
        EnergyModuleView(values: Self.values, enabled: enabled, isOn: on, output: output, spectrum: on ? Self.spectrum : Array(repeating: 0, count: 24),
                         isFront: true, onPower: {}, onSet: {}, onToggle: { _ in }, zoom: zoom)
    }

    private var energyPage: some View {
        VStack(alignment: .leading, spacing: 28) {
            section("Energy module, real size") {
                HStack(alignment: .top, spacing: 48) {
                    VStack(alignment: .leading, spacing: 30) { Self.energy(on: true); caption("on") }
                    VStack(alignment: .leading, spacing: 30) { Self.energy(on: false); caption("off") }
                    VStack(alignment: .leading, spacing: 30) {
                        Self.energy(on: true, enabled: [true, true, false, true, true, true]); caption("BRIGHTNESS off")
                    }
                    VStack(alignment: .leading, spacing: 30) { Self.energy(on: true, output: .unplugged); caption("unplugged") }
                }
            }
            section("Energy module, 2×") {
                HStack(alignment: .top, spacing: 48) {
                    Self.energy(on: true, zoom: 2)
                    Self.energy(on: true, enabled: [true, true, false, true, true, true], zoom: 2)
                }
            }
        }
    }

    // MARK: Whole keychain

    private var keychainPage: some View { Self.keychainOverview(dark: dark) }

    /// The whole keychain at rest, 3 and 8 bands, each item in front (also rendered offscreen by
    /// `-debugRenderKeychain`).
    static func keychainOverview(dark: Bool) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach([3, 8], id: \.self) { bands in
                VStack(alignment: .leading, spacing: 14) {
                    Text(verbatim: "KEYCHAIN AT REST, \(bands) BANDS: BPM TAG, MIDI STRIP, ENERGY MODULE, CHARMS IN FRONT")
                        .font(.system(size: 11, weight: .semibold)).tracking(0.9)
                        .foregroundStyle(dark ? hex(0xc9c6bf) : hex(0x5a564e))
                    HStack(alignment: .top, spacing: 18) {
                        ForEach([Module.bpm, .midi, .energy, .charms], id: \.self) { front in
                            let layout = KeychainLayout(bands: bands)
                            Self.restingKeychain(front: front, bands: bands, ringPoint: layout.ringPoint, size: layout.size)
                        }
                    }
                }
            }
        }
    }

    /// The keychain as it hangs once settled, put together like KeychainView (no motion, no live values):
    /// the ring point at `ringPoint` in a `size` frame.
    static func restingKeychain(front: Module, bands: Int, ringPoint: CGPoint, size: CGSize) -> some View {
        let rest = Pendulum.restAngles()
        var state = KeychainState()
        state.front = front
        let order = state.zOrder()
        func z(_ m: Module) -> Double { 1 + Double(order.firstIndex(of: m) ?? 0) }
        let s = HardwareScale.app, g = KeyringGeometry.ringPoint
        let ringOrigin = CGPoint(x: ringPoint.x + (RingPiece.box.minX - g.x) * s, y: ringPoint.y + (RingPiece.box.minY - g.y) * s)
        return ZStack(alignment: .topLeading) {
            RingPiece(piece: .back).offset(x: ringOrigin.x, y: ringOrigin.y).zIndex(0)
            BPMTagView(state: Self.bpmStates[0].1, isFront: front == .bpm, onRocker: {}, onSet: {})
                .hung(size: CGSize(width: BPMTagView.side, height: BPMTagView.side), hole: BPMTagView.holeCenter,
                      angle: rest.bpm, at: ringPoint)
                .zIndex(z(.bpm))
            MIDIStripView(bands: bands, levels: Self.levels, isOn: true, isFront: front == .midi, onSlide: {}, onSet: {})
                .hung(size: CGSize(width: MIDIStripView.width(bands: bands), height: MIDIStripView.height),
                      hole: MIDIStripView.holeCenter(bands: bands), angle: rest.midi, at: ringPoint)
                .zIndex(z(.midi))
            Self.energy(on: true)
                .hung(size: EnergyModuleView.size, hole: EnergyModuleView.holeCenter, angle: rest.energy, at: ringPoint)
                .zIndex(z(.energy))
            BeadCharmsView(bunch: 0, angles: BeadCharms.Strand.allCases.map(BeadCharms.restAngle), ringPoint: ringPoint, onTap: {})
                .frame(width: size.width, height: size.height, alignment: .topLeading)
                .zIndex(z(.charms))
            RingPiece(piece: .front).offset(x: ringOrigin.x, y: ringOrigin.y).zIndex(10)
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .background(alignment: .top) { Rectangle().fill(.black.opacity(0.08)).frame(height: 1) }  // the menu bar's bottom edge
    }

    /// `-debugRenderHitAreas <png>` (with `-debugHitAreas YES`): every module's controls with their hit areas drawn, at 2×,
    /// light: the BPM tag, the MIDI strip plugged and unplugged (MIDI learn targets), the Energy module.
    static func hitAreasRender() -> some View {
        let z: CGFloat = 2
        func label(_ t: String) -> some View {
            Text(verbatim: t).font(.system(size: 12, weight: .semibold)).tracking(0.8).foregroundStyle(hex(0x3a362f))
        }
        return VStack(alignment: .leading, spacing: 40) {
            label("HIT AREAS (RED), 2×: ACTIVE ONLY WHILE THE MODULE IS IN FRONT · MODULE OUTLINE (BLUE): BRINGS IT FORWARD")
            HStack(alignment: .top, spacing: 120) {
                VStack(alignment: .leading, spacing: 30) {
                    label("BPM TAG: ROCKER, SETTINGS KEY")
                    BPMTagView(state: bpmStates[0].1, isFront: true, onRocker: {}, onSet: {}, zoom: z).padding(30)
                }
                VStack(alignment: .leading, spacing: 30) {
                    label("ENERGY: SET, POWER, ROWS, MIDI OUT PLUG")
                    EnergyModuleView(values: [0.53, 0.43, 0.5, 0.55, 0.55, 0.5], enabled: Array(repeating: true, count: 6), isOn: true,
                                     onPlug: {}, spectrum: Array(repeating: 0.4, count: 24), isFront: true,
                                     onPower: {}, onSet: {}, onToggle: { _ in }, zoom: z).padding(40)
                }
            }
            HStack(alignment: .top, spacing: 120) {
                VStack(alignment: .leading, spacing: 30) {
                    label("MIDI STRIP: SLIDE, SET, EJECT KEYS, ADD BUTTON, MIDI OUT PLUG")
                    MIDIStripView(bands: 3, levels: [0.9, 0.5, 0.3], isOn: true, isFront: true, onSlide: {}, onSet: {},
                                  outPlugged: true, onPlug: {}, zoom: z).padding(50)
                }
                VStack(alignment: .leading, spacing: 30) {
                    label("MIDI STRIP UNPLUGGED: + MIDI LEARN (EACH BAND MODULE)")
                    MIDIStripView(bands: 3, levels: [0.9, 0.5, 0.3], isOn: true, isFront: true, onSlide: {}, onSet: {},
                                  onLearn: { _ in }, outPlugged: false, onPlug: {}, zoom: z).padding(50)
                }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .galleryBackdrop(dark: false)
        .environment(\.colorScheme, .light)
        .fixedSize()
    }
}

extension View {
    /// The debug renders' background: warm grey, or near-black in dark mode.
    func galleryBackdrop(dark: Bool) -> some View {
        background(dark ? hex(0x1d1e22) : hex(0xcfcbc2))
    }
}
