// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import VChainEngine
import VChainKit
import Observation

/// The engine pointer, handed to background tasks for blocking calls (the C API is thread-safe).
struct EngineHandle: @unchecked Sendable {
    let pointer: OpaquePointer

    func snapshot() -> VCSnapshot {
        var s = VCSnapshot()
        vc_engine_get_snapshot(pointer, &s)
        return s
    }
}

/// The UserDefaults keys of the saved settings (the beat offset is saved per input under "beatOffset.<input>").
enum SettingsKey: String {
    case genre, bpmEnabled, stripEnabled, triggersSending, energyEnabled, energySending, triggerBands, triggerDecay,
         stripChannel, energyChannel, descriptorsEnabled, input
}

/// The app's single source of truth: owns the C++ engine, mirrors its settings (persisted in
/// UserDefaults) and hands live snapshots to the views. Live values are polled, never observed,
/// so the 60 Hz meters don't invalidate the rest of the UI.
@MainActor @Observable
final class EngineModel {
    static let shared = EngineModel()

    @ObservationIgnored let handle: EngineHandle
    /// The input: source, devices, permission and health (`InputController`).
    let input: InputController

    var genre: Int { didSet { vc_engine_set_genre(engine, Int32(genre)); save(genre, .genre) } }
    /// Settings › Beat-o-Matic › Beat offset (ms, −50…+150): positive puts Link's beats, and vChain's own beat display,
    /// earlier (Resolume/projector latency). Remembered per input.
    var beatOffsetMs: Int = 0 {
        didSet {
            vc_engine_set_beat_offset_ms(engine, Float(beatOffsetMs))
            defaults.set(beatOffsetMs, forKey: Self.beatOffsetKey(input.source))
        }
    }
    static let beatOffsetRange = -50...150
    private static func beatOffsetKey(_ source: InputSource) -> String { "beatOffset." + (source.storageValue ?? "file") }
    var bpmEnabled: Bool {
        didSet { vc_engine_set_module_enabled(engine, Int32(VC_MODULE_BPM.rawValue), bpmEnabled); save(bpmEnabled, .bpmEnabled) }
    }
    /// The MIDI strip's slide: the strip on or off (off = dark and its trigger CCs silent).
    var stripEnabled: Bool {
        didSet { pushTriggersSending(); save(stripEnabled, .stripEnabled) }
    }
    /// The MIDI strip's MIDI OUT plug (and Settings › BandsDance › MIDI out: Live): the trigger CCs 1–8 go out. Unplugged the
    /// strip keeps analysing and showing; the Energy CCs are not affected.
    var triggersSending: Bool {
        didSet { pushTriggersSending(); save(triggersSending, .triggersSending) }
    }
    /// The Energy module's MIDI OUT plug (and Settings › Annalisa › MIDI out: Live): the descriptor CCs 9–14 go out. Unplugged
    /// the module keeps analysing and showing.
    var energySending: Bool {
        didSet { vc_engine_set_midi_descriptors_sending(engine, energySending); save(energySending, .energySending) }
    }
    /// The strip's plug is in: strip on and its CCs not unplugged.
    var stripPlugged: Bool { stripEnabled && triggersSending }
    /// The Energy module's plug is in: module on and its CCs not unplugged.
    var energyPlugged: Bool { energyEnabled && energySending }

    /// Clicking a MIDI OUT plug. Plugging in also switches that module on; unplugging only stops its CCs.
    func setStripPlugged(_ plugged: Bool) {
        if plugged { stripEnabled = true }
        triggersSending = plugged
    }
    func setEnergyPlugged(_ plugged: Bool) {
        if plugged { energyEnabled = true }
        energySending = plugged
    }

    /// MIDI learn: one CC sent as a single 0 → 127 → 0 sweep, even while its module is unplugged (`vc_engine_send_learn_sweep`).
    @discardableResult func sendLearnSweep(cc: Int) -> Bool { vc_engine_send_learn_sweep(engine, Int32(cc)) }

    private func pushTriggersSending() { vc_engine_set_midi_triggers_sending(engine, stripEnabled && triggersSending) }
    /// Settings › BandsDance › MIDI channel: the trigger CCs 1–8 go out on it (1–16, default 16, `VC_MIDI_CHANNEL`).
    var stripChannel: Int {
        didSet { vc_engine_set_trigger_channel(engine, Int32(stripChannel)); save(stripChannel, .stripChannel) }
    }
    /// Settings › Annalisa › MIDI channel: the descriptor CCs 9–14 go out on it (1–16, default 16).
    var energyChannel: Int {
        didSet { vc_engine_set_descriptor_channel(engine, Int32(energyChannel)); save(energyChannel, .energyChannel) }
    }
    var triggerBands: Int {
        didSet { vc_engine_set_num_trigger_bands(engine, Int32(triggerBands)); save(triggerBands, .triggerBands) }
    }
    /// Settings › BandsDance › Trigger decay: beats from a hit back to zero at the current BPM, or 0 = follow the sound
    /// (`VC_TRIGGER_DECAY_FOLLOW`). Default half a beat (`VC_TRIGGER_DECAY_BEATS`).
    var triggerDecay: Double {
        didSet { vc_engine_set_trigger_decay(engine, Float(triggerDecay)); save(triggerDecay, .triggerDecay) }
    }
    /// The Energy module switch. Off sends every descriptor as disabled to the engine while
    /// `descriptorsEnabled` keeps the user's per-descriptor choices; on restores them.
    var energyEnabled: Bool {
        didSet { pushDescriptors(); save(energyEnabled, .energyEnabled) }
    }
    private(set) var descriptorsEnabled: [Bool]

    @ObservationIgnored private let defaults = UserDefaults.standard

    private var engine: OpaquePointer { handle.pointer }

    private func save(_ value: Any, _ key: SettingsKey) { defaults.set(value, forKey: key.rawValue) }

    /// A saved MIDI channel kept within 1–16.
    private static func clampChannel(_ channel: Int) -> Int { min(16, max(1, channel)) }

    private init() {
        let d = UserDefaults.standard
        let registered: [SettingsKey: Any] = [
            .genre: 0, .bpmEnabled: true, .triggersSending: true, .energyEnabled: true,
            .stripEnabled: true, .energySending: true, .triggerBands: 3, .triggerDecay: Double(VC_TRIGGER_DECAY_BEATS),
            .stripChannel: Int(VC_MIDI_CHANNEL), .energyChannel: Int(VC_MIDI_CHANNEL), .input: "system",
        ]
        d.register(defaults: Dictionary(uniqueKeysWithValues: registered.map { ($0.key.rawValue, $0.value) }))
        let portName = d.string(forKey: "midiPortName") ?? "vChain"
        handle = EngineHandle(pointer: vc_engine_create(portName))
        input = InputController(handle: handle)
        func int(_ key: SettingsKey) -> Int { d.integer(forKey: key.rawValue) }
        func bool(_ key: SettingsKey) -> Bool { d.bool(forKey: key.rawValue) }
        genre = int(.genre)
        bpmEnabled = bool(.bpmEnabled)
        stripEnabled = bool(.stripEnabled)
        triggersSending = bool(.triggersSending)
        energySending = bool(.energySending)
        triggerBands = int(.triggerBands)
        triggerDecay = max(0, d.double(forKey: SettingsKey.triggerDecay.rawValue))
        stripChannel = Self.clampChannel(int(.stripChannel))
        energyChannel = Self.clampChannel(int(.energyChannel))
        energyEnabled = bool(.energyEnabled)
        let storedDescriptors = d.array(forKey: SettingsKey.descriptorsEnabled.rawValue) as? [Bool]
        descriptorsEnabled = storedDescriptors?.count == Int(VC_NUM_DESCRIPTORS)
            ? storedDescriptors! : Array(repeating: true, count: Int(VC_NUM_DESCRIPTORS))

        pushAll()
        // Each input has its own beat offset: load it whenever the input changes.
        input.onSelect = { [unowned self] source in
            beatOffsetMs = min(Self.beatOffsetRange.upperBound, max(Self.beatOffsetRange.lowerBound,
                                                                    defaults.integer(forKey: Self.beatOffsetKey(source))))
        }
        input.watch()
    }

    /// Every setting to the engine (didSet doesn't run in init, so the restored settings go out here).
    private func pushAll() {
        vc_engine_set_genre(engine, Int32(genre))
        pushTriggersSending()
        vc_engine_set_midi_descriptors_sending(engine, energySending)
        vc_engine_set_num_trigger_bands(engine, Int32(triggerBands))
        vc_engine_set_trigger_decay(engine, Float(triggerDecay))
        vc_engine_set_trigger_channel(engine, Int32(stripChannel))
        vc_engine_set_descriptor_channel(engine, Int32(energyChannel))
        pushDescriptors()
        vc_engine_set_module_enabled(engine, Int32(VC_MODULE_BPM.rawValue), bpmEnabled)
        vc_engine_set_module_enabled(engine, Int32(VC_MODULE_MIDI.rawValue), true)
    }

    /// Starts the remembered input (or the developer test file).
    func start() {
        input.start()
    }

    func shutdown() {
        vc_engine_destroy(engine)
    }

    // MARK: Live values

    func live() -> LiveState {
        var s = handle.snapshot()
        DebugLaunch.applyFakeBeat(&s)
        return LiveState(s, now: vc_now_micros())
    }

    // MARK: Settings

    func setDescriptor(_ index: Int, enabled: Bool) {
        descriptorsEnabled[index] = enabled
        pushDescriptors()
        save(descriptorsEnabled, .descriptorsEnabled)
    }

    /// Sends the effective descriptor mask (Energy switch applied) to the engine.
    private func pushDescriptors() {
        let mask = DescriptorMask.engineMask(energyEnabled: energyEnabled, chosen: descriptorsEnabled)
        for (i, on) in mask.enumerated() { vc_engine_set_descriptor_enabled(engine, Int32(i), on) }
    }

    // MARK: Static info

    static let genres: [(name: String, center: Float)] = (0..<vc_genre_count()).map {
        (String(cString: vc_genre_name($0)), vc_genre_center_bpm($0))
    }

    static let descriptorNames: [String] = (0..<VC_NUM_DESCRIPTORS).map { String(cString: vc_descriptor_name(Int32($0))) }
}
