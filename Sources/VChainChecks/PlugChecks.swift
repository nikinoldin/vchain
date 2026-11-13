// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import VChainEngine
import VChainKit

func runPlugChecks() {
    Checks.run("MIDI OUT plug hover") {
        let T = PlugMotion.hoverTime
        check(T > 0.08 && T < 0.2, "a quick ease (\(T) s)")
        check(PlugMotion.peek(from: 0, hovered: true, elapsed: 0) == 0 && PlugMotion.peek(from: 0, hovered: true, elapsed: T) == 1,
              "hovered: eases from in to out")
        check(PlugMotion.peek(from: 1, hovered: false, elapsed: T) == 0, "left: eases back in")
        checkApprox(PlugMotion.peek(from: 0.4, hovered: false, elapsed: 0), 0.4, tol: 1e-12, "leaving mid-ease starts where it was")
        let v = stride(from: 0.0, through: T, by: T / 20).map { PlugMotion.peek(from: 0, hovered: true, elapsed: $0) }
        check(zip(v, v.dropFirst()).allSatisfy { $0 <= $1 } && v.allSatisfy { $0 >= 0 && $0 <= 1 }, "steady, no overshoot")
        check(PlugMotion.peekUnits > 1.5 && PlugMotion.peekUnits < 3.5, "comes out a little (\(PlugMotion.peekUnits) units)")
        check(BandLCD.learn() == [[.d, .e, .f], [.e, .g], [.c, .e, .g], []], "the strip's channel LCD reads LRn while unplugged")
    }

    Checks.run("MIDI learn sweep") {
        let T = Double(VC_LEARN_SWEEP_SECONDS)
        check(T >= 0.3 && T <= 0.5, "a short sweep (\(T) s)")
        check(vc_learn_sweep_value(0) == 0 && vc_learn_sweep_value(Float(T)) == 0, "starts and ends at 0")
        checkApprox(Double(vc_learn_sweep_value(Float(T / 2))), 1, tol: 1e-6, "reaches 127 half way")
        let v = stride(from: 0.0, to: T, by: T / 60).map { Double(vc_learn_sweep_value(Float($0))) }
        let peak = v.firstIndex(of: v.max()!)!
        check(zip(v[..<peak], v[1...peak]).allSatisfy { $0 <= $1 } && zip(v[peak...], v[(peak + 1)...]).allSatisfy { $0 >= $1 },
              "up, then down, once")
        check(vc_learn_sweep_value(-0.1) == 0 && vc_learn_sweep_value(Float(T) + 1) == 0, "0 outside the sweep")
    }

    Checks.run("engine: descriptor pause and learn sweep") {
        // A fresh engine starts with its modules off, so no MIDI port is created here.
        guard let e = vc_engine_create("vChain Checks") else { check(false, "engine created"); return }
        defer { vc_engine_destroy(e) }
        var s = VCSnapshot()
        vc_engine_set_midi_descriptors_sending(e, false)
        Thread.sleep(forTimeInterval: 0.05)
        vc_engine_get_snapshot(e, &s)
        check(!s.midiDescriptorsSending, "the descriptor pause shows in the snapshot")
        vc_engine_set_midi_descriptors_sending(e, true)
        check(!vc_engine_send_learn_sweep(e, 9), "learn sweep refused while the MIDI module is off (no port)")
        check(!vc_engine_send_learn_sweep(e, 0) && !vc_engine_send_learn_sweep(e, 32), "learn sweep refuses CCs outside 1–31")
    }
}
