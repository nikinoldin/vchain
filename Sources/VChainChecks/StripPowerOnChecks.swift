// SPDX-License-Identifier: GPL-3.0-or-later
import VChainKit

func runStripPowerOnChecks() {
    typealias P = StripPowerOn

    Checks.run("strip power-on: durations") {
        for n in 2...8 {
            let d = P.duration(bands: n)
            check(d >= 0.75 && d <= 1.2, "\(n) bands: total \(d) s within 0.75…1.2")
        }
        check(P.duration(bands: 8) > P.duration(bands: 2), "8 bands take longer than 2")
        checkApprox(P.duration(bands: 3), 1.06, tol: 0.001, "3 bands (default) ≈ 1.06 s")
    }

    Checks.run("strip power-on: phases") {
        for n in [2, 8] {
            let early = P.module(0, bands: n, elapsed: 0.02), lit = P.module(n - 1, bands: n, elapsed: 0.15)
            check(early.ladder == 10 && early.lcd == .all && early.lcdLevel < 0.5, "\(n): at 0.02 s ladders full, LCD all, still darkening")
            check(lit.ladder == 10 && lit.lcd == .all && lit.lcdLevel == 1, "\(n): at 0.15 s everything fully on")
            let drop = P.module(0, bands: n, elapsed: P.allOn + 0.01)
            check(drop.ladder == 0 && drop.lcd == .all && drop.lcdLevel > 0 && drop.lcdLevel < 1, "\(n): drop-out: LEDs off at once, LCD fading")
            let sweep = (0..<n).map { P.module($0, bands: n, elapsed: P.sweepStart + 0.05) }
            check(sweep.allSatisfy { $0.lcd == .blank }, "\(n): LCDs blank during the sweep")
            check(sweep[0].ladder! > 0 && sweep[n - 1].ladder! < sweep[0].ladder!, "\(n): wave starts at the left")
            let peak = P.module(0, bands: n, elapsed: P.sweepStart + P.ladderSweep / 2)
            check(peak.ladder == 10, "\(n): first ladder full at the top of its sweep")
            let settling = P.module(0, bands: n, elapsed: P.settleStart(0, bands: n) + 0.01)
            check(settling.ladder == nil && settling.lcd == .normal && settling.lcdLevel < 1, "\(n): first module goes live, LCD darkening in")
            check(P.module(n - 1, bands: n, elapsed: P.settleStart(0, bands: n) + 0.01).lcd == .blank || n == 1,
                  "\(n): last module still blank when the first settles")
        }
    }

    Checks.run("strip power-on: monotonic sweep order") {
        for n in [2, 3, 8] {
            // First time each ladder lights during the sweep, and when each module settles: left to right.
            var firstLit: [Double] = []
            for i in 0..<n {
                var t = P.sweepStart
                while (P.module(i, bands: n, elapsed: t).ladder ?? 0) == 0 && t < 2 { t += 0.001 }
                firstLit.append(t)
            }
            check(zip(firstLit, firstLit.dropFirst()).allSatisfy { $0 < $1 }, "\(n): ladders light left → right")
            let settles = (0..<n).map { P.settleStart($0, bands: n) }
            check(zip(settles, settles.dropFirst()).allSatisfy { $0 < $1 }, "\(n): modules settle left → right")
            check(settles[0] >= P.sweepEnd(bands: n), "\(n): settle after the wave")
            // Each ladder rises then falls (0 → 10 → 0), never jumps more than a few steps a frame.
            var counts: [Int] = []
            var t = P.sweepStart
            while t < P.sweepEnd(bands: n) { counts.append(P.module(n - 1, bands: n, elapsed: t).ladder ?? -1); t += 1.0 / 120 }
            let top = counts.firstIndex(of: 10) ?? -1
            check(top > 0 && zip(counts[..<top], counts[1...top]).allSatisfy { $0 <= $1 }
                  && zip(counts[top...], counts[(top + 1)...]).allSatisfy { $0 >= $1 }, "\(n): last ladder fills then empties")
        }
    }

    Checks.run("strip power-on: end state") {
        for n in [2, 8] {
            check(P.modules(bands: n, elapsed: P.duration(bands: n)) == nil, "\(n): over at its duration")
            check(P.modules(bands: n, elapsed: 5) == nil, "\(n): over long after")
            let last = P.module(n - 1, bands: n, elapsed: P.duration(bands: n))
            check(last.ladder == nil && last.lcd == .normal && last.lcdLevel > 0.999, "\(n): last module live, LCD fully on")
            check(P.modules(bands: n, elapsed: 0.5)?.count == n, "\(n): one state per module while playing")
        }
    }

    Checks.run("strip power-on: an added module's start-up") {
        check(P.bootDuration > 0.5 && P.bootDuration <= 0.65, "about 0.6 s (\(P.bootDuration))")
        let first = P.moduleBoot(elapsed: 0.05)
        check(first?.ladder == 10 && first?.lcd == .all, "starts all on")
        check(P.moduleBoot(elapsed: P.bootAllOn + 0.02)?.lcd == .all && P.moduleBoot(elapsed: P.bootAllOn + 0.02)!.lcdLevel < 1,
              "then the LCDs fade out")
        let peak = P.moduleBoot(elapsed: P.bootSweepStart + P.ladderSweep / 2)
        check(peak?.ladder == 10 && peak?.lcd == .blank, "its ladder sweeps up while the LCDs are blank")
        let settle = P.moduleBoot(elapsed: P.bootSettle + 0.02)
        check(settle?.ladder == nil && settle?.lcd == .normal && settle!.lcdLevel < 1, "then live, values fading on")
        check(P.moduleBoot(elapsed: P.bootDuration) == nil, "over after its duration")
    }

    Checks.run("strip power-on: learn and settle overlays") {
        let on = P.Module(ladder: 10, lcd: .all, lcdLevel: 1), blank = P.Module(ladder: 0, lcd: .blank, lcdLevel: 0)
        check(P.withLearn(nil, nil, bands: 3) == nil && P.withLearn([on, on, on], nil, bands: 3) == [on, on, on], "no learn: unchanged")
        let learnt = P.withLearn(nil, (index: 1, value: 0.46), bands: 3)
        check(learnt == [.live, P.Module(ladder: 5, lcd: .normal, lcdLevel: 1), .live], "learning band 2: its ladder shows the sweep")
        check(P.withLearn([on, on, on], (index: 0, value: 1), bands: 3)?[1] == on, "the other modules keep their frame")
        check(P.withLearn(nil, (index: 3, value: 1), bands: 3) == nil, "a band past the strip is ignored")
        check(P.withLearn([on, on], (index: 0, value: 1), bands: 3) == [on, on], "a frame of another band count is left alone")
        check(P.withSettle([on, on, on], nil, bands: 3) == [on, on, on], "no settle: unchanged")
        check(P.withSettle(nil, [blank, .live, .live], bands: 3) == [blank, .live, .live], "settle over live")
        check(P.withSettle([on, on, on], [blank, .live, .live], bands: 3) == [blank, on, on], "settling modules win, the rest keep the frame")
        check(P.withSettle([on, on, on], [blank, .live], bands: 3) == [on, on, on], "a settle of another band count is ignored")
    }
}
