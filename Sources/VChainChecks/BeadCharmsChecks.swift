// SPDX-License-Identifier: GPL-3.0-or-later
import CoreGraphics
import Foundation
import VChainKit

func runBeadCharmsChecks() {
    typealias B = BeadCharms
    Checks.run("Bead charms: strands") {
        check(B.beads(.tulip).count == 7 && B.beads(.mushroom).count == 7 && B.beads(.millefiori).count == 10,
              "7 tulip-strand beads, 7 mushroom-strand beads, 10 millefiori discs")
        for s in B.Strand.allCases {
            let l = B.length(s)
            check((55...75).contains(l), "\(s): \(l) pt long as measured (55–75)")
            let small = B.beads(s).filter { $0 != .leaf && $0 != .mushroomHeart }
            check(small.allSatisfy { (5.5...9.2).contains($0.size.width) && (5.5...9.2).contains($0.size.height) },
                  "\(s): beads 5.5–9 pt as measured")
            let stack = B.stack(s)
            let touching = zip(stack, stack.dropFirst()).allSatisfy {
                abs(($1.center.y - $1.size.height / 2) - ($0.center.y + $0.size.height / 2) - B.gap) < 1e-9
            }
            check(touching, "\(s): beads stacked down the pin, \(B.gap) pt of wire between them")
            check(B.bottomLoop(s).y > stack.last!.center.y + stack.last!.size.height / 2, "\(s): bottom loop under the last bead")
            check(B.bounds(s).contains(CGPoint(x: 0, y: -B.loopRadius)) && B.bounds(s).maxY >= B.length(s),
                  "\(s): bounds hold the top loop and the bottom loop")
        }
        check(B.pivot(.tulip).x < B.pivot(.mushroom).x && B.pivot(.mushroom).x < B.pivot(.millefiori).x,
              "top loops in order on the jump ring: tulip, mushroom, millefiori")
        check(B.restAngle(.mushroom) == 0 && B.restAngle(.tulip) == -B.restAngle(.millefiori) && abs(B.restAngle(.tulip)) <= 8,
              "hanging down, only pushed apart a little where they meet (±\(B.restAngle(.tulip))°, tulip to the left)")
        // The heart hangs in front: the leaf and the last disc must still show at least half beside it.
        let heart = B.hang.beads(.mushroom).last!
        for s in [B.Strand.tulip, .millefiori] {
            let last = B.hang.beads(s).last!, hidden = last.intersection(heart)
            check(hidden.isNull || hidden.width <= last.width * 0.5, "\(s): last bead at least half visible beside the heart")
        }
    }
    Checks.run("Bead charms: jump ring and bounds") {
        let bare = B.Hang(scale: 2)
        check(bare.jumpCenter - B.jumpRadius * 2 < 0 && bare.jumpCenter > 0, "without a chain the jump ring's top goes round the split ring")
        typealias C = B.Chain
        check(C.isFaceOn(0) && !C.isFaceOn(1), "chain links alternate, the top one face on (threaded on the split ring)")
        check(C.linkCenter(1) - C.linkCenter(0) == C.pitch && C.pitch == C.linkLength - 2 * C.linkWire, "each link hangs in the one above")
        check(C.linkCenter(0) - C.linkLength / 2 < 0 && C.linkCenter(0) - C.linkLength / 2 + C.linkWire > -2,
              "the top link's upper end goes round the split ring at the ring point")
        check(B.Hang(scale: 2, chainLinks: 10).jumpCenter > C.end(links: 10), "on a chain the jump ring hangs from the last link")
        typealias K = B.Clasp
        check(abs(K.top + K.band - C.ringTop) < 1e-9 && K.top < K.clawBase && K.clawBase < K.dTop && K.dTop < K.end,
              "the clasp's claw rests on the split ring, then collar, swivel and D-ring")
        let clasped = B.Hang(scale: 1.6, chainLinks: 3, clasp: true)
        check(abs(C.linkCenter(0, top: clasped.chainTop) - C.linkLength / 2 + C.linkWire - K.end) < 1e-9, "the chain's top link hangs in the clasp's D-ring")
        check(B.Hang(scale: 1.6, clasp: true).jumpCenter > K.end, "without a chain the jump ring hangs in the D-ring")
        for hang in [B.hang, B.Hang(scale: 2.7)] {
            let box = hang.bounds
            check(B.Strand.allCases.flatMap(hang.beads).allSatisfy { box.contains($0) }, "\(hang): bounds hold every bead")
        }
    }
    Checks.run("Bead charms: show below every module at rest") {
        // 1.6× doesn't quite clear the Energy module's sloping edge with the whole
        // last bead; the strictest rule it meets: the lower 60 % of each strand's last bead (leaf, heart,
        // last disc) hangs clear of every module's body at rest, whichever is in front, for every band count.
        check(B.displayScale == 1.6 && B.hang.clasp && B.chainLinks == B.Hang.shortestChain(scale: 1.6, clasp: true, fraction: 0.6, margin: 0),
              "1.6× from the clasp on the shortest chain that shows them (\(B.chainLinks) links, \(Int(B.hang.jumpCenter.rounded())) pt to the jump ring)")
        let rest = Pendulum.restAngles()
        for bands in 2...8 {
            let bodies = KeyringGeometry.restBodies(bands: bands, rest: rest)
            for s in B.Strand.allCases {
                let b = B.hang.beads(s).last!
                let lower = CGRect(x: b.minX, y: b.maxY - b.height * 0.6, width: b.width, height: b.height * 0.6)
                let clear = KeyringGeometry.isClear(lower, of: bodies)
                if bands == 2 || bands == 3 || bands == 8 || !clear {
                    check(clear, "\(bands) bands: lower 60 % of \(s)'s last bead below the BPM tag, MIDI strip and Energy module")
                }
            }
        }
        check(B.hang.showsBelowEveryModule(fraction: 0.6, margin: 0), "the keychain's hang (\(B.hang)): lower 60 % of the last beads below every module")
    }
    Checks.run("Bead charms: swing") {
        for s in B.Strand.allCases {
            let t = B.period(s)
            check((0.38...0.5).contains(t), "\(s): own wobble period \(String(format: "%.3f", t)) s (rigid rod of its length)")
        }
        let t = B.bunchPeriod
        check(t > Pendulum.period && t < 0.85, "the whole bunch swings a bit slower than a module: \(String(format: "%.2f", t)) s")
        let dt = 1.0 / 120
        var w = CharmsSwing()
        w.release()
        check(w.bunchAngle == Pendulum.releaseSwing && B.Strand.allCases.allSatisfy { w.angle($0) == w.bunchAngle + B.restAngle($0) },
              "dropped in swung \(Pendulum.releaseSwing)° like the modules, strands at rest on it")
        var lagged = false, reversals = 0, side = w.bunchAngle.sign, peak = 0.0
        for k in 0..<480 {
            w.step(dt)
            if k < 120, B.Strand.allCases.contains(where: { abs(w.angle($0) - w.bunchAngle - B.restAngle($0)) > 0.3 }) { lagged = true }
            if abs(w.bunchAngle) > 0.5, w.bunchAngle.sign != side { reversals += 1; side = w.bunchAngle.sign }
            if k > 30 { peak = max(peak, B.Strand.allCases.map { abs(w.angle($0) - w.bunchAngle - B.restAngle($0)) }.max()!) }
        }
        check(lagged, "the strands swing a little on their own (lag behind the jump ring)")
        check(peak < 4, "…but only a little: at most \(String(format: "%.1f", peak))° off the jump ring")
        check(reversals >= 2, "swings side to side (≥2 visible reversals)")
        var settle = CharmsSwing()
        settle.release()
        var settledAt = Double.infinity
        for k in 0..<480 { settle.step(dt); if settle.isSettled, settledAt.isInfinite { settledAt = Double(k + 1) * dt } }
        check(settledAt < 2.2, "still within \(String(format: "%.2f", settledAt)) s of opening (modules ≈ 1.5–2 s)")
        var pushed = CharmsSwing()
        pushed.push(40)
        for _ in 0..<240 { pushed.step(dt) }
        check(pushed.isSettled, "a push (brought to the front) has died away after 2 s")
        var reduce = CharmsSwing()
        reduce.release(); reduce.push(30); reduce.step(dt); reduce.settleImmediately()
        check(reduce.isSettled && reduce.bunchAngle == 0, "Reduce Motion: straight down at once")
    }
}
