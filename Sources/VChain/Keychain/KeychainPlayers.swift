// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import VChainEngine
import VChainKit

// The keychain's short-lived motions besides the pendulums (KeychainMotion): plain class state the timeline reads every
// frame, so changing it doesn't invalidate the view. Each is started by a click and over by itself.

/// When a module was switched on, for its power-on (`StripPowerOn`, `TagPowerOn`, `EnergyPowerOn`; `Frame` is that
/// timeline's frame). Plain class state like `KeychainMotion`: started only by the module's own switch (not at launch
/// or when the panel opens, not with Reduce Motion), cancelled when the module goes off or the panel closes, and over
/// by itself when its timeline ends (≈1 s).
@MainActor
final class PowerOnPlayer<Frame> {
    private var start: Date?

    var isPlaying: Bool { start != nil }
    func begin() { start = Date() }
    func cancel() { start = nil }

    /// This frame of the power-on (`timeline` at the seconds since it began), or nil when none is playing.
    func frame(isOn: Bool, at date: Date, _ timeline: (_ elapsed: Double) -> Frame?) -> Frame? {
        guard isOn, let start else { self.start = nil; return nil }
        let frame = timeline(max(0, date.timeIntervalSince(start)))
        if frame == nil { self.start = nil }
        return frame
    }
}

// MARK: - Strip module eject / add

/// A strip module being ejected or added (`StripEdit`) and when it started. Plain class state like
/// `KeychainMotion`; over by itself after ≈0.6 s, cancelled when the panel closes.
@MainActor
final class StripEditor {
    struct Frame { var edit: StripEdit; var time: Double }
    private var edit: StripEdit?
    private var start: Date?
    /// The strip settling once the modules have snapped (`StripEdit.settle`): which edit and when it snapped.
    private var settling: (edit: StripEdit, start: Date)?

    var isPlaying: Bool { edit != nil }
    func begin(_ edit: StripEdit) { self.edit = edit; start = Date(); settling = nil }
    func cancel() { edit = nil; start = nil; settling = nil }

    /// This frame of the motion, or nil when none is playing. It hands over to the settling (re-tune, start-up).
    func frame(at date: Date) -> Frame? {
        guard let edit, let start else { return nil }
        let t = max(0, date.timeIntervalSince(start))
        if t >= edit.duration {
            self.edit = nil; self.start = nil
            settling = (edit, start.addingTimeInterval(edit.duration))
            return nil
        }
        return Frame(edit: edit, time: t)
    }

    /// The settling frame, one entry per module of the new count, or nil when none is playing.
    func settleFrame(at date: Date) -> [StripPowerOn.Module]? {
        guard let settling else { return nil }
        guard let frame = settling.edit.settle(at: date.timeIntervalSince(settling.start)) else { self.settling = nil; return nil }
        return frame
    }
}

// MARK: - MIDI OUT plugs and MIDI learn

/// The MIDI OUT plugs under the pointer (`PlugMotion.peek`): each eases a little out of its socket while hovered and
/// back when the pointer leaves. Plain class state like `KeychainMotion`.
@MainActor
final class PlugHover {
    /// By module: `.midi` (the strip's plug) and `.energy`.
    private var state: [Module: (hovered: Bool, from: Double, start: Date)] = [:]

    func hover(_ which: Module, _ hovered: Bool, animate: Bool) {
        let now = Date()
        let current = peek(which, at: now)
        state[which] = (hovered, animate ? current : (hovered ? 1 : 0), animate ? now : .distantPast)
    }
    func cancel() { state = [:] }

    func peek(_ which: Module, at date: Date) -> Double {
        guard let s = state[which] else { return 0 }
        return PlugMotion.peek(from: s.from, hovered: s.hovered, elapsed: date.timeIntervalSince(s.start))
    }
    /// Still easing somewhere (the timeline then runs at full rate).
    func isEasing(at date: Date) -> Bool {
        state.values.contains { date.timeIntervalSince($0.start) < PlugMotion.hoverTime }
    }
}

/// A MIDI learn sweep being shown (the engine sends it, `vc_engine_send_learn_sweep`): which module, which element, when.
@MainActor
final class LearnPlayer {
    private var sweeps: [Module: (index: Int, start: Date)] = [:]

    func begin(_ which: Module, index: Int) { sweeps[which] = (index, Date()) }
    func cancel() { sweeps = [:] }

    /// The element and the sweep's value (0…1, the same curve the engine sends), or nil when none is running.
    func frame(_ which: Module, at date: Date) -> (index: Int, value: Double)? {
        guard let s = sweeps[which] else { return nil }
        let t = date.timeIntervalSince(s.start)
        if t >= Double(VC_LEARN_SWEEP_SECONDS) { sweeps[which] = nil; return nil }
        return (s.index, Double(vc_learn_sweep_value(Float(max(0, t)))))
    }
}
