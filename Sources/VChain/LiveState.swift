// SPDX-License-Identifier: GPL-3.0-or-later
import VChainEngine

/// The input's state as the engine reports it (`VCInputState`).
enum InputHealth {
    case idle, starting, running, noPermission, failed

    init(_ state: Int32) {
        switch VCInputState(rawValue: UInt32(state)) {
        case VC_INPUT_STATE_STARTING: self = .starting
        case VC_INPUT_STATE_RUNNING: self = .running
        case VC_INPUT_STATE_NO_PERMISSION: self = .noPermission
        case VC_INPUT_STATE_FAILED: self = .failed
        default: self = .idle
        }
    }
}

/// A Swift copy of the engine's VCSnapshot for the views. SwiftUI crashed (AttributeGraph, in body
/// diffing) when the imported C struct itself was passed through the live view closures, so views
/// only ever see this type.
struct LiveState {
    var now: UInt64
    var input: InputHealth

    var bpmEnabled: Bool
    var bpm: Float
    var confidence: Float
    var linkPeers: Int
    var linkTempo: Double
    var linkPhase: Double
    /// VCBeatState (searching / settling / locked / holding) and whether Link's beat 0 is the music's 1.
    var beatState: Int32
    var barLocked: Bool
    var phaseMicros: UInt64

    var triggers: [Float]
    var descriptorValues: [Float]
    /// 24 log-spaced bands (0...1); zeros while MIDI analysis is off.
    var spectrum: [Float]

    init(_ s: VCSnapshot, now: UInt64) {
        func array<T>(_ tuple: T, count: Int) -> [Float] {
            withUnsafeBytes(of: tuple) { Array($0.bindMemory(to: Float.self).prefix(count)) }
        }
        let bandCount = Int(min(max(s.numTriggerBands, 0), VC_MAX_TRIGGER_BANDS))
        self.now = now
        input = InputHealth(s.inputState)
        bpmEnabled = s.bpmEnabled
        bpm = s.bpm
        confidence = s.confidence
        linkPeers = Int(s.linkPeers)
        linkTempo = s.linkTempo
        linkPhase = s.linkPhase
        beatState = s.beatState
        barLocked = s.barLocked
        phaseMicros = s.phaseMicros
        triggers = array(s.triggers, count: bandCount)
        descriptorValues = array(s.descriptors, count: Int(VC_NUM_DESCRIPTORS))
        spectrum = array(s.spectrum, count: Int(VC_NUM_SPECTRUM))
    }

    var hasTempo: Bool { bpm > 1 }

    /// Link beat phase (0..<4) now, extrapolated from when the engine sampled it.
    var beatPhase: Double {
        guard bpmEnabled, linkTempo > 0 else { return 0 }
        let elapsed = Double(Int64(bitPattern: now &- phaseMicros)) / 1_000_000
        let beats = Double(VC_BEATS_PER_BAR)
        let phase = (linkPhase + elapsed * linkTempo / 60).truncatingRemainder(dividingBy: beats)
        return phase < 0 ? phase + beats : phase
    }
}
