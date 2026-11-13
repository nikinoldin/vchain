// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import VChainKit

func runStripEditChecks() {
    typealias E = StripEdit

    Checks.run("strip edit: rest and end poses") {
        let r = E.rest(bands: 3)
        check(r.slots.map(\.x) == [-3, -2, -1] && r.leftEdge == -3 && r.snapped, "3 bands at rest: modules at −3, −2, −1, left edge −3")
        for edit in [E(from: 4, kind: .remove(1)), E(from: 2, kind: .add), E(from: 8, kind: .remove(7)), E(from: 7, kind: .add)] {
            check(edit.pose(at: 0).slots.filter { $0.old != nil }.map(\.x) == E.rest(bands: edit.from).slots.map(\.x),
                  "\(edit.from) \(edit.kind): starts where \(edit.from) bands rest")
            check(edit.pose(at: edit.duration) == E.rest(bands: edit.to), "\(edit.from) \(edit.kind): ends exactly at rest with \(edit.to)")
            check(edit.duration > 0.4 && edit.duration <= 0.65, "\(edit.from) \(edit.kind): \(edit.duration) s")
        }
    }

    Checks.run("strip edit: eject falls out") {
        let e = E(from: 4, kind: .remove(1))
        let falls = stride(from: 0.0, to: e.duration, by: 0.05).map { e.pose(at: $0).slots[1] }
        check(falls.allSatisfy { $0.new == nil && $0.lift == 0 && $0.opacity == 1 }, "the ejected module stays opaque (no fade, it falls out of the panel)")
        let d = falls.map(\.fall), steps = zip(d, d.dropFirst()).map { $1 - $0 }
        check(zip(steps, steps.dropFirst()).allSatisfy { $1 > $0 }, "falls faster and faster (gravity)")
        check(falls.last!.fall > 250, "falls well out of the panel (\(Int(falls.last!.fall)) units)")
        check(zip(falls, falls.dropFirst()).allSatisfy { $1.spin >= $0.spin } && falls.last!.spin < 30, "tumbles a little, one way")
        let mid = e.pose(at: E.closeStart + E.closeTime * 0.6)
        check(mid.slots[0].x > -4 && mid.slots[2].x == -2 && mid.slots[3].x == -1, "left part closes the gap, right of it stays put")
        check(e.pose(at: E.closeStart - 0.01).slots[0].x == -4, "the gap waits until the module has mostly fallen clear")
        check(e.pose(at: E.closeStart - 0.01).slots[1].fall > 40, "…by then it has dropped \(Int(e.pose(at: E.closeStart - 0.01).slots[1].fall)) units")
        let xs = stride(from: E.closeStart, to: e.duration, by: 0.01).map { e.pose(at: $0).slots[0].x }
        check(xs.max()! <= -3 + 0.03, "the snap overshoots by under 3 % of a module")
        check(e.pose(at: 0.3).slots.map(\.new) == [0, nil, 1, 2], "new indices skip the ejected one")
    }

    Checks.run("strip edit: add") {
        let a = E(from: 3, kind: .add)
        let p = a.pose(at: E.openTime)
        check(p.slots.prefix(3).map(\.x) == [-4, -3, -2] && p.leftEdge == -4, "the end opens: left part one module further left")
        check(p.slots[3].old == nil && p.slots[3].new == 3 && p.slots[3].x == -1, "the new module comes in at the right end")
        check(a.pose(at: E.dropStart).slots[3].lift == -E.lift && a.pose(at: E.dropStart).slots[3].opacity == 0, "drops in from above")
        check(!a.pose(at: a.duration - 0.01).snapped && a.pose(at: a.duration).snapped, "ranges switch when it snaps in")
    }

    Checks.run("strip edit: fall is straight down in the world") {
        let flat = E.fallOffset(100, hangDegrees: 0)
        checkApprox(flat.x, 0, tol: 1e-9, "unturned: no sideways")
        checkApprox(flat.y, 100, tol: 1e-9, "unturned: down")
        let hung = E.fallOffset(100, hangDegrees: -38)
        checkApprox(hung.x, -61.57, tol: 0.01, "strip at −38°: towards its free (left) end")
        checkApprox(hung.y, 78.80, tol: 0.01, "strip at −38°: and down its face")
    }

    Checks.run("strip edit: the fall fades out before the panel edge") {
        let r = CGRect(x: -40, y: -10, width: 27, height: 100)
        checkApprox(E.lowestBelowHole(r, hangDegrees: 0), 90, tol: 1e-9, "unturned: the bottom edge")
        let turned = E.lowestBelowHole(r, hangDegrees: -38)
        checkApprox(turned, -40 * sin(-38 * .pi / 180) + 90 * cos(-38 * .pi / 180), tol: 1e-9, "turned −38°: the lower left corner")
        check(E.fallOpacity(fall: 0, clearance: 120, fadeOver: 27) == 1, "opaque at the start")
        check(E.fallOpacity(fall: 92, clearance: 120, fadeOver: 27) == 1, "opaque until the last 27 units")
        checkApprox(E.fallOpacity(fall: 106.5, clearance: 120, fadeOver: 27), 0.5, tol: 1e-9, "half way through the fade")
        check(E.fallOpacity(fall: 120, clearance: 120, fadeOver: 27) == 0, "gone when it would reach the edge")
        check(E.fallOpacity(fall: 300, clearance: 120, fadeOver: 27) == 0, "stays gone")
        let e = E(from: 4, kind: .remove(1))
        check(e.pose(at: e.duration - 0.01).slots[1].fall > 120, "the fall goes past any panel's room (so the fade always completes)")
    }

    Checks.run("strip edit: the others re-tune after the snap") {
        let e = E(from: 4, kind: .remove(1))
        let start = e.settle(at: 0)!
        check(start.count == 3 && start.allSatisfy { $0.lcd == .normal && $0.lcdLevel < 0.01 }, "at the snap every range LCD goes dark")
        check(start[0].ccLevel == 1 && start[1].ccLevel! < 0.01 && start[2].ccLevel! < 0.01,
              "CC LCDs: kept left of the gap, re-lit right of it (numbers changed)")
        check(start[0].ladder == StripPowerOn.retuneBlipSteps, "the first module's ladder blips as it re-lights")
        let mid = e.settle(at: 0.08)!
        check(mid[0].lcdLevel > mid[2].lcdLevel, "a ripple: left re-lights before right")
        check(e.settle(at: StripPowerOn.retuneDuration(bands: 3)) == nil, "done after \(StripPowerOn.retuneDuration(bands: 3)) s")
        for n in 2...8 { check(StripPowerOn.retuneDuration(bands: n) <= 0.45, "\(n) bands: ripple ≤ 0.45 s") }
        let a = E(from: 3, kind: .add)
        let af = a.settle(at: 0.05)!
        check(af.count == 4 && af[3].lcd == .all && af[0...2].allSatisfy { $0.lcd == .normal && $0.ccLevel == 1 },
              "add: the new module boots, the others re-tune keeping their CC")
        check(a.settle(at: StripPowerOn.bootDuration) == nil, "add: done with the start-up")
    }

    Checks.run("band LCD: MIDI channel") {
        let S = SevenSegment.segments(for:), C = SevenSegment.letterC, H = SevenSegment.letterH
        check(BandLCD.channel(16) == [C, H, S(1), S(6)], "16 → C H 1 6")
        check(BandLCD.channel(3) == [C, H, [], S(3)], "3 → C H _ 3")
        check(BandLCD.channel(0) == BandLCD.channel(1) && BandLCD.channel(20) == BandLCD.channel(16), "clamped to 1…16")
        check(H == [.b, .c, .e, .f, .g], "H is segments b, c, e, f, g")
    }
}
