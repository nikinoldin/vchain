// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import VChainEngine
import VChainKit
import SwiftUI

/// The menu bar drop-down: the BPM tag, the MIDI strip and the Energy module hanging from one split
/// ring under the status item. Opening drops them in from under the menu bar, swung 11° to the right;
/// each swings as a damped pendulum about the ring point and then stays still (nothing moves on the
/// beat). A tap on a module behind the others brings it to the front with a small push; only the
/// front module's switches and keys respond. Right-click any module for the app's commands. The
/// bead charms (BeadCharmsView) hang from the same ring point as decoration: they swing in, can be
/// brought to the front, and do nothing else.
///
/// One `TimelineView(.animation)` drives the motion and the live values. Each module and both ring
/// pieces sit in a `Frozen` wrapper keyed by what they show, so a frame where nothing visible changed
/// only moves layers instead of redrawing every Canvas.
struct KeychainView: View {
    @Environment(EngineModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    /// In the detached window (`KeychainDock`) rather than the menu bar drop-down.
    @Environment(\.keychainDetached) private var detached

    @ViewState private var keychain = KeychainView.storedState()
    @ViewState private var motion = KeychainMotion()
    /// The power-ons after a module's switch was flipped on (purely visual: the module works right away).
    @ViewState private var stripPowerOn = PowerOnPlayer<[StripPowerOn.Module]>()
    @ViewState private var energyPowerOn = PowerOnPlayer<EnergyPowerOn.Frame>()
    @ViewState private var tagPowerOn = PowerOnPlayer<TagPowerOn.Frame>()
    @ViewState private var stripEdit = StripEditor()
    @ViewState private var plugs = PlugHover()
    @ViewState private var learn = LearnPlayer()
    /// While a strip module is being ejected or added: the wider band count, so the panel keeps room for it.
    @ViewState private var editBands: Int?
    /// Open and on a lit display: only then does the timeline run.
    @ViewState private var isShowing = false
    /// Swinging, dropping, a module's power-on or a module coming or going: full display rate. At rest the LCD, ladders
    /// and spectrum only need 30 Hz, plus one redraw exactly on each beat change (`beat`), so the dancer and the beat
    /// blocks land on the beat rather than on the next 30 Hz tick.
    @ViewState private var isMoving = true
    @ViewState private var beat = BeatTicker()

    private var open: WindowOpener { WindowOpener(openWindow: openWindow, settingsAction: openSettings) }

    var body: some View {
        let layout = KeychainLayout(bands: editBands ?? model.triggerBands)
        let _ = beat.tick  // a beat change re-evaluates the body, so the timeline content redraws on it
        TimelineView(.animation(minimumInterval: isMoving ? nil : 1.0 / 30, paused: !isShowing)) { context in
            let pose = motion.advance(to: context.date)
            let bands = model.triggerBands
            let stripOn = stripPowerOn.frame(isOn: model.stripEnabled, at: context.date) { StripPowerOn.modules(bands: bands, elapsed: $0) }
            let energyOn = energyPowerOn.frame(isOn: model.energyEnabled, at: context.date, EnergyPowerOn.frame(elapsed:))
            let edit = stripEdit.frame(at: context.date)
            let settle = stripEdit.settleFrame(at: context.date)
            let peeks = (midi: plugs.peek(.midi, at: context.date), energy: plugs.peek(.energy, at: context.date))
            let learning = (midi: learn.frame(.midi, at: context.date), energy: learn.frame(.energy, at: context.date))
            let _ = noteEditEnded(edit == nil)
            let _ = noteRest(pose.atRest && stripOn == nil && edit == nil && settle == nil && energyOn == nil && !plugs.isEasing(at: context.date)
                             && learning.midi == nil && learning.energy == nil)
            let live = model.live()
            let _ = beat.arm(live)
            hanging(layout: layout, pose: pose, stripPowerOn: StripPowerOn.withLearn(StripPowerOn.withSettle(stripOn, settle, bands: bands),
                                                                                     learning.midi, bands: bands),
                    edit: edit, energyPowerOn: energyOn, peeks: peeks, learnLine: learning.energy, live: live)
        }
        .frame(width: layout.size.width, height: layout.size.height, alignment: .topLeading)
        // Detached: a fixed frame for the most bands with the ring point always in the same place, and room for the
        // ring's top (the menu bar hides it while attached).
        .padding(.leading, detached ? KeychainDock.detachedGeometry.ringPointX - layout.ringPoint.x : 0)
        .padding(.top, detached ? KeychainDock.detachedGeometry.topRoom : 0)
        .frame(width: detached ? KeychainDock.detachedGeometry.size.width : layout.size.width,
               height: detached ? KeychainDock.detachedGeometry.size.height : layout.size.height, alignment: .topLeading)
        .background(TransparentPanel(hookX: layout.hook.x, pinned: !detached,
                                     onOpen: { motion.release(settled: reduceMotion); isMoving = true },
                                     onShowing: { showing in
                                         // Closed: pose the modules at the drop-in start now, so the
                                         // first frame after the next open already shows it.
                                         if !showing {
                                             motion.release(settled: reduceMotion); stripPowerOn.cancel(); energyPowerOn.cancel(); tagPowerOn.cancel()
                                             stripEdit.cancel(); plugs.cancel(); learn.cancel(); beat.cancel()
                                         }
                                         isShowing = showing
                                     }))
        .contextMenu { KeychainMenu() }
        .onAppear {
            guard detached else { return }
            KeychainDock.shared.swing = { dv in
                guard !reduceMotion else { return }
                motion.carry(dv)
                isMoving = true
            }
        }
    }

    /// Gives the panel its normal size back once a module has finished coming or going (after this update).
    private func noteEditEnded(_ ended: Bool) {
        guard ended, editBands != nil else { return }
        DispatchQueue.main.async { editBands = nil }
    }

    /// Switches the timeline's rate when the keychain comes to rest (after this update, not during it).
    private func noteRest(_ atRest: Bool) {
        let atRest = atRest && !tagPowerOn.isPlaying
        guard atRest == isMoving else { return }
        DispatchQueue.main.async { isMoving = !atRest }
    }

    private func hanging(layout: KeychainLayout, pose: KeychainMotion.Pose, stripPowerOn: [StripPowerOn.Module]?,
                         edit: StripEditor.Frame?, energyPowerOn: EnergyPowerOn.Frame?, peeks: (midi: Double, energy: Double),
                         learnLine: (index: Int, value: Double)?, live s: LiveState) -> some View {
        let drop = pose.drop
        let front = keychain.front
        return ZStack(alignment: .topLeading) {
            ringPiece(.back, layout: layout, drop: drop).zIndex(0)
            hang(.bpm, size: CGSize(width: BPMTagView.side, height: BPMTagView.side), hole: BPMTagView.holeCenter,
                 angle: pose.bpm, drop: drop, layout: layout) { bpmTag(s, isFront: front == .bpm) }
            let stripBands = MIDIStripView.frameBands(bands: model.triggerBands, edit: edit?.edit)
            hang(.midi, size: CGSize(width: MIDIStripView.width(bands: stripBands), height: MIDIStripView.height),
                 hole: MIDIStripView.holeCenter(bands: stripBands), angle: pose.midi, drop: drop, layout: layout) {
                midiStrip(s, bands: model.triggerBands, powerOn: stripPowerOn, edit: edit, hangAngle: pose.midi,
                          fallRoom: Double(layout.size.height - layout.ringPoint.y - drop) / HardwareScale.app, plugPeek: peeks.midi,
                          isFront: front == .midi)
            }
            hang(.energy, size: EnergyModuleView.size, hole: EnergyModuleView.holeCenter,
                 angle: pose.energy, drop: drop, layout: layout) {
                energyModule(s, powerOn: energyPowerOn, plugPeek: peeks.energy,
                             learning: learnLine.map { EnergyModuleView.LearnLine(index: $0.index, value: $0.value) }, isFront: front == .energy)
            }
            BeadCharmsView(bunch: pose.bunch, angles: pose.charms, ringPoint: CGPoint(x: layout.ringPoint.x, y: layout.ringPoint.y + drop),
                           onTap: { tap(.charms) })
                .frame(width: layout.size.width, height: layout.size.height, alignment: .topLeading)
                .zIndex(z(.charms))
            ringPiece(.front, layout: layout, drop: drop).zIndex(10)
            // Detached: the keyring and the disc inside it move the window.
            let disc = layout.ringDisc
            RingGrip()
                .frame(width: disc.radius * 2, height: disc.radius * 2)
                .offset(x: disc.center.x - disc.radius, y: disc.center.y - disc.radius + drop)
                .allowsHitTesting(detached)
                .zIndex(11)
        }
        .frame(width: layout.size.width, height: layout.size.height, alignment: .topLeading)
    }

    // MARK: Modules

    private func bpmTag(_ s: LiveState, isFront: Bool) -> some View {
        let problem = InputProblem.current(model)?.isWarning ?? false
        let state = BPMTagState.make(BPMInputs(
            enabled: model.bpmEnabled || DebugLaunch.fakeBeat != nil, bpm: Double(s.bpm), confidence: Double(s.confidence), hasTempo: s.hasTempo,
            beatPhase: s.beatPhase, linkPeers: s.linkPeers, inputProblem: problem, time: Double(s.now) / 1_000_000,
            barLocked: s.barLocked, beatState: BeatState(rawValue: Int(s.beatState))))
        let model = model, open = open, tagPowerOn = tagPowerOn, isMoving = $isMoving, animate = !reduceMotion
        let powerOn = tagPowerOn.frame(isOn: model.bpmEnabled, at: Date(), TagPowerOn.frame(elapsed:))
        return Frozen(key: BPMKey(state: state, isFront: isFront, powerOn: powerOn)) {
            BPMTagView(state: state, isFront: isFront,
                       onRocker: {
                           // Off is instant; on plays the power-on (purely visual: detection starts right away).
                           if model.bpmEnabled { tagPowerOn.cancel() } else if animate { tagPowerOn.begin(); isMoving.wrappedValue = true }
                           model.bpmEnabled.toggle()
                       },
                       onSet: { open.settings(pane: "bpm") }, powerOn: powerOn)
        }
        .equatable()
    }

    private func midiStrip(_ s: LiveState, bands: Int, powerOn: [StripPowerOn.Module]?, edit: StripEditor.Frame?, hangAngle: Double,
                           fallRoom: Double, plugPeek: Double, isFront: Bool) -> some View {
        let isOn = model.stripEnabled, plugged = model.stripPlugged
        let channel = model.stripChannel
        // The ladders show tenths: quantize, so a frame only redraws when a segment changes.
        let lit = (0..<bands).map { i in i < s.triggers.count ? Int((min(max(s.triggers[i], 0), 1) * 10).rounded()) : 0 }
        let model = model, open = open, stripPowerOn = stripPowerOn, isMoving = $isMoving
        let stripEdit = stripEdit, editBands = $editBands, animate = !reduceMotion, plugs = plugs, learn = learn
        // MIDI learn while the strip shows but is unplugged: a band module click sends its CC once as a sweep.
        let learnable = isOn && !plugged
        /// Ejecting or adding changes the band count at once (the engine follows); the motion is only the picture.
        func change(_ kind: StripEdit.Kind) {
            guard !stripEdit.isPlaying else { return }
            let edit = StripEdit(from: model.triggerBands, kind: kind)
            guard edit.to >= Int(VC_MIN_TRIGGER_BANDS), edit.to <= Int(VC_MAX_TRIGGER_BANDS) else { return }
            if animate {
                stripEdit.begin(edit)
                editBands.wrappedValue = max(edit.from, edit.to)
                isMoving.wrappedValue = true
            }
            model.triggerBands = edit.to
        }
        // Only while a module comes or goes does the swing angle matter (the fall is straight down).
        let key = MIDIKey(bands: bands, lit: lit, isOn: isOn, plugged: plugged, plugPeek: plugPeek, channel: channel, powerOn: powerOn,
                          edit: edit?.edit, editTime: edit?.time,
                          hang: edit == nil ? 0 : hangAngle, fallRoom: edit == nil ? 0 : fallRoom, isFront: isFront)
        return Frozen(key: key) {
            MIDIStripView(bands: bands, levels: lit.map { Float($0) / 10 }, isOn: isOn, channel: channel, powerOn: powerOn,
                          edit: edit?.edit, editTime: edit?.time ?? 0, hangAngle: key.hang, fallRoom: key.fallRoom, isFront: isFront,
                          onSlide: {
                              // The strip on or off (off: dark and its CCs silent; the plug says whether they go out
                              // while it's on). The power-on is only the picture.
                              if isOn {
                                  model.stripEnabled = false
                                  stripPowerOn.cancel()
                              } else {
                                  model.stripEnabled = true
                                  stripPowerOn.begin()
                                  isMoving.wrappedValue = true
                              }
                          },
                          onSet: { open.settings(pane: "midi") },
                          onEject: { change(.remove($0)) },
                          onAdd: { change(.add) },
                          plugPeek: plugPeek,
                          onPlugHover: { plugs.hover(.midi, $0, animate: animate); isMoving.wrappedValue = true },
                          onLearn: learnable ? { k in
                              if model.sendLearnSweep(cc: MIDIReference.triggerCC(k)) {
                                  learn.begin(.midi, index: k)
                                  isMoving.wrappedValue = true
                              }
                          } : nil,
                          outPlugged: plugged,
                          onPlug: {
                              // Unplug: the strip keeps showing, its CCs stop. Plug in: they go out again. Instant.
                              model.setStripPlugged(!plugged)
                          })
        }
        .equatable()
    }

    private func energyModule(_ s: LiveState, powerOn: EnergyPowerOn.Frame?, plugPeek: Double, learning: EnergyModuleView.LearnLine?,
                              isFront: Bool) -> some View {
        let isOn = model.energyEnabled, plugged = model.energyPlugged
        let output = model.energyOutput
        let channel = model.energyChannel
        let enabled = model.descriptorsEnabled
        // Lines in 1/200 steps (finer than the screen's pixels); spectrum bars in 1/20 steps.
        let values = s.descriptorValues.map { Int((min(max($0, 0), 1) * 200).rounded()) }
        let dots = s.spectrum.map { min(20, max(0, Int(($0 * 20).rounded()))) }
        let model = model, open = open, energyPowerOn = energyPowerOn, isMoving = $isMoving, reduceMotion = reduceMotion, plugs = plugs, learn = learn
        // MIDI learn while the module shows but is unplugged: a row click sends its CC once as a sweep.
        let learnable = isOn && !plugged
        return Frozen(key: EnergyKey(values: values, enabled: enabled, isOn: isOn, output: output, channel: channel, dots: dots,
                                     powerOn: powerOn, plugged: plugged, plugPeek: plugPeek, learning: learning, isFront: isFront)) {
            EnergyModuleView(values: values.map { Float($0) / 200 }, enabled: enabled, isOn: isOn, output: output, channel: channel,
                             plugPeek: plugPeek,
                             onPlugHover: { plugs.hover(.energy, $0, animate: !reduceMotion); isMoving.wrappedValue = true },
                             onLearn: learnable ? { i in
                                 if model.sendLearnSweep(cc: MIDIReference.descriptorCC(i)) {
                                     learn.begin(.energy, index: i)
                                     isMoving.wrappedValue = true
                                 }
                             } : nil,
                             learning: learning,
                             outPlugged: plugged,
                             onPlug: {
                                 // Unplug: the module keeps showing, its CCs stop. Plug in: they go out again. Instant.
                                 model.setEnergyPlugged(!plugged)
                             },
                             spectrum: dots.map { Float($0) / 20 }, powerOn: powerOn, isFront: isFront,
                             onPower: {
                                 // Turned on by its key: the power-on plays (the CCs start right away). Off is instant.
                                 if model.energyEnabled { energyPowerOn.cancel() } else if !reduceMotion {
                                     energyPowerOn.begin()
                                     isMoving.wrappedValue = true
                                 }
                                 model.energyEnabled.toggle()
                             },
                             onSet: { open.settings(pane: "energy") },
                             onToggle: { i in model.setDescriptor(i, enabled: !model.descriptorsEnabled[i]) })
        }
        .equatable()
    }

    /// A module hung by its keyring hole from the ring point, swung `angle` degrees about it.
    private func hang<V: View>(_ module: Module, size: CGSize, hole: CGPoint, angle: Double, drop: CGFloat,
                               layout: KeychainLayout, @ViewBuilder _ content: () -> V) -> some View {
        content()
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            // A tap on the module itself brings it forward: its `ModuleOutline` (exactly where it's drawn) or a part
            // drawn on it, not a control (those hit-test only on the front module) and not its frame's empty corners,
            // shadows or bleed, which pass the click to the module behind.
            .onTapGesture { tap(module) }
            .hung(size: size, hole: hole, angle: angle, at: CGPoint(x: layout.ringPoint.x, y: layout.ringPoint.y + drop))
            .zIndex(z(module))
    }

    /// Between the back ring piece (0) and the front one (10), in the keychain's z-order.
    private func z(_ module: Module) -> Double {
        1 + Double(keychain.zOrder().firstIndex(of: module) ?? 0)
    }

    private func ringPiece(_ piece: RingPiece.Piece, layout: KeychainLayout, drop: CGFloat) -> some View {
        let origin = layout.point(hang: CGPoint(x: RingPiece.box.minX, y: RingPiece.box.minY))
        return Frozen(key: piece) { RingPiece(piece: piece) }
            .equatable()
            .offset(x: origin.x, y: origin.y + drop)
            .allowsHitTesting(false)
    }

    // MARK: Taps

    /// A tap that reaches the module itself (not one of its controls): bring it forward if it's behind.
    private func tap(_ module: Module) {
        guard keychain.tap(on: module) == .broughtToFront else { return }
        if !reduceMotion {
            motion.push(module)
            isMoving = true
        }
        UserDefaults.standard.set(module.name, forKey: "keychainFront")
    }

    /// The front module is remembered (`-keychainFront bpm|midi|energy|charms` sets it for screenshots).
    private static func storedState() -> KeychainState {
        var state = KeychainState()
        state.front = UserDefaults.standard.string(forKey: "keychainFront").flatMap(Module.init(name:)) ?? .bpm
        return state
    }
}

// MARK: - Motion

/// The three module pendulums (Pendulum, period 0.5 s, ζ 0.25; the long MIDI strip 0.4), the bead
/// charms (CharmsSwing: the bunch plus each strand's own wobble) and the shared drop. Plain class state, not
/// observed: the timeline reads it every frame, so changing it must not invalidate the view.
@MainActor
final class KeychainMotion {
    struct Pose {
        var bpm: Double, midi: Double, energy: Double
        /// The bead charms as a whole (their jump ring), and each strand (BeadCharms.Strand order).
        var bunch: Double
        var charms: [Double]
        /// Points; negative while the keychain is still falling in from under the menu bar.
        var drop: CGFloat
        /// Nothing visibly moving any more.
        var atRest: Bool
    }

    private let rest = Pendulum.restAngles()
    private lazy var bpm = Pendulum(rest: rest.bpm)
    private lazy var midi = Pendulum(rest: rest.midi, damping: Pendulum.longDamping)
    private lazy var energy = Pendulum(rest: rest.energy)
    private var charms = CharmsSwing()
    private var last: Date?

    /// The panel opened: drop in swung to the right and swing side to side, or (Reduce Motion) appear at rest.
    func release(settled: Bool) {
        for i in 0..<3 {
            update(i) { settled ? $0.settleImmediately() : $0.release() }
        }
        if settled { charms.settleImmediately() } else { charms.release() }
        last = nil
    }

    /// Carried (the detached keychain dragged by its ring): the window's horizontal velocity changed by `dv` points/s,
    /// so everything hanging from the ring swings the other way, like a real keychain.
    func carry(_ dv: Double) {
        let push = max(-160, min(160, dv * 0.07))
        bpm.push(push); midi.push(push); energy.push(push); charms.push(push * 0.8)
    }

    /// Brought to the front: a small push (the strip, fanned left, is pushed the other way).
    func push(_ module: Module) {
        switch module {
        case .bpm: bpm.push(55)
        case .midi: midi.push(-55)
        case .energy: energy.push(55)
        case .charms: charms.push(40)
        }
    }

    func advance(to date: Date) -> Pose {
        // Real elapsed time, so slow frames (a busy machine mid-set) don't stretch the swing out;
        // capped at 0.25 s so a long stall (sleep, a hidden panel) doesn't replay as a jump.
        let dt = last.map { min(0.25, max(0, date.timeIntervalSince($0))) } ?? 0
        last = date
        if dt > 0 {
            for i in 0..<3 { update(i) { $0.step(dt) } }
            charms.step(dt)
        }
        // Every module drops alike and hangs from the same ring point: the BPM tag's drop moves them all.
        let atRest = [bpm, midi, energy].allSatisfy {
            abs($0.angle - $0.rest) < 0.05 && abs($0.velocity) < 0.5 && abs($0.drop) < 0.05 && abs($0.dropVelocity) < 0.5
        } && charms.isSettled
        // Snap exactly to rest: otherwise the tail keeps changing the angle by thousandths of a degree
        // every frame, and the long rotated strip re-rasterizes with shimmering edges.
        if atRest {
            for i in 0..<3 { update(i) { $0.settleImmediately() } }
            charms.settleImmediately()
        }
        // The drop in whole half-points (a pixel on Retina): its tail flips sign by millionths of a point,
        // and a module sitting half a pixel off the grid then snaps to the pixel above, then below — a buzz.
        let drop = (CGFloat(bpm.drop) * HardwareScale.app * 2).rounded() / 2
        return Pose(bpm: bpm.angle, midi: midi.angle, energy: energy.angle, bunch: charms.bunchAngle,
                    charms: BeadCharms.Strand.allCases.map(charms.angle), drop: drop, atRest: atRest)
    }

    private func update(_ i: Int, _ change: (inout Pendulum) -> Void) {
        switch i {
        case 0: change(&bpm)
        case 1: change(&midi)
        default: change(&energy)
        }
    }
}

// MARK: - Redraw keys

/// Re-evaluates `content` only when `key` changes, so the per-frame timeline doesn't redraw a module
/// (or the ring) whose picture is the same. The content's action closures read the model when they run.
private struct Frozen<Key: Equatable, Content: View>: View, Equatable {
    let key: Key
    @ViewBuilder let content: () -> Content

    static func == (a: Self, b: Self) -> Bool { a.key == b.key }

    var body: some View { content() }
}

private struct BPMKey: Equatable {
    var state: BPMTagState
    var isFront: Bool
    var powerOn: TagPowerOn.Frame?
}

private struct MIDIKey: Equatable {
    var bands: Int
    var lit: [Int]
    var isOn: Bool
    var plugged: Bool
    var plugPeek: Double
    var channel: Int
    var powerOn: [StripPowerOn.Module]?
    var edit: StripEdit?
    var editTime: Double?
    var hang: Double
    var fallRoom: Double
    var isFront: Bool
}

private struct EnergyKey: Equatable {
    var values: [Int]
    var enabled: [Bool]
    var isOn: Bool
    var output: EnergyModuleView.Output
    var channel: Int
    var dots: [Int]
    var powerOn: EnergyPowerOn.Frame?
    var plugged: Bool
    var plugPeek: Double
    var learning: EnergyModuleView.LearnLine?
    var isFront: Bool
}
