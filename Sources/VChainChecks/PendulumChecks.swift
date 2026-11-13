// SPDX-License-Identifier: GPL-3.0-or-later
import VChainKit

func runPendulumChecks() {
    let dt = 1.0 / 120.0

    Checks.run("Pendulum: rest angles") {
        let r = Pendulum.restAngles()
        check(r.bpm == 2.0 && r.midi == -38.0 && r.energy == 45.0, "rest angles 2 / -38 / 45")
    }
    Checks.run("Pendulum: release") {
        for rest in [Pendulum.restAngles().bpm, Pendulum.restAngles().midi, Pendulum.restAngles().energy] {
            var p = Pendulum(rest: rest)
            p.release()
            check(p.angle - rest == Pendulum.releaseSwing && p.velocity == 0, "rest \(rest): starts 11° out to the right, still")
            check(p.drop == Pendulum.dropStart, "rest \(rest): drops in from dropStart")
            var crossings = 0
            var side = (p.angle - rest).sign
            for _ in 0..<240 {   // 2 s
                p.step(dt)
                if abs(p.angle - rest) > 0.5, (p.angle - rest).sign != side { crossings += 1; side = (p.angle - rest).sign }
            }
            check(crossings >= 2, "rest \(rest): swings side to side (≥2 visible reversals)")
            check(abs(p.angle - rest) < 0.1, "rest \(rest): settled within 0.1° after 2 s")
            check(abs(p.drop) < 0.05, "rest \(rest): drop settled after 2 s")
        }
        check(abs(Pendulum.releaseSwing) < 12, "release swing fits the panel's 12° margin")
    }
    Checks.run("Pendulum: push") {
        var p = Pendulum(rest: Pendulum.restAngles().midi)
        p.push(55)
        p.step(dt)
        check(abs(p.angle - p.rest) > 0.01, "push moves the pendulum")
        for _ in 0..<83 { p.step(dt) }   // 0.7 s total
        check(abs(p.angle - p.rest) < 1, "settles within 0.7 s after push")
    }
    Checks.run("Pendulum: MIDI strip damps harder") {
        // The strip's far end is ~365 pt from its hole: 0.08° there is half a point.
        var p = Pendulum(rest: Pendulum.restAngles().midi, damping: Pendulum.longDamping)
        p.push(-55)
        for _ in 0..<120 { p.step(dt) }   // 1 s
        check(abs(p.angle - p.rest) < 0.08, "MIDI strip within 0.08° 1 s after a push")
    }
    Checks.run("Pendulum: slow frames keep real time") {
        // 10 fps for 1 s settles like 120 fps for 1 s (no slow motion when frames are late).
        var slow = Pendulum(rest: -38), fast = Pendulum(rest: -38)
        slow.release(); fast.release()
        for _ in 0..<10 { slow.step(0.1) }
        for _ in 0..<120 { fast.step(dt) }
        check(abs(slow.angle - fast.angle) < 0.05 && abs(slow.drop - fast.drop) < 0.05, "same pose after 1 s at 10 fps and 120 fps")
        var big = Pendulum(rest: -38); big.release(); big.step(0.25)
        check(big.angle.isFinite && abs(big.angle - big.rest) <= abs(Pendulum.releaseSwing) && abs(big.drop) <= abs(Pendulum.dropStart), "a 0.25 s step stays bounded")
    }
    Checks.run("Pendulum: reduce motion") {
        var p = Pendulum(rest: 45)
        p.release(); p.push(30); p.step(dt)
        p.settleImmediately()
        check(p.angle == p.rest && p.velocity == 0, "settled immediately")
        check(p.drop == 0 && p.dropVelocity == 0, "no drop with Reduce Motion")
    }
}
