// SPDX-License-Identifier: GPL-3.0-or-later
import VChainKit

func runTagPowerOnChecks() {
    Checks.run("BPM tag power-on") {
        let f = { (t: Double) in TagPowerOn.frame(elapsed: t) }
        check(f(0.0) == .init(show: .all, level: 0), "flip: everything starts darkening in")
        check(f(0.1)?.show == .all && f(0.1)?.level == 1, "0.1 s: everything on")
        check(f(0.24)?.show == .all && (f(0.24)?.level ?? 1) < 1, "0.24 s: everything fading out")
        check((0..<4).map { f(TagPowerOn.sweepStart + Double($0) * TagPowerOn.blockStep + 0.05)?.show } == [.block(0), .block(1), .block(2), .block(3)],
              "beat blocks sweep 1 → 4")
        check(f(TagPowerOn.bootStart + 0.05)?.show == .mascot(.still), "the mascot comes on standing still")
        check(f(TagPowerOn.bootStart + 0.15)?.show == .mascot(.wave), "then waves")
        check(f(TagPowerOn.bootStart + 0.27)?.show == .mascot(.still), "arm down")
        check(f(TagPowerOn.bootStart + 0.36)?.show == .mascot(.wave), "waves again")
        check(TagPowerOn.duration > 1.0 && TagPowerOn.duration < 1.25, "about 1.1 s (\(TagPowerOn.duration))")
        check(f(TagPowerOn.duration) == nil, "then the live display")
        var t = 0.0, levels: [Double] = []
        while t < TagPowerOn.duration { levels.append(f(t)?.level ?? -1); t += 0.005 }
        check(levels.allSatisfy { $0 >= 0 && $0 <= 1 }, "levels stay within 0…1")
    }
}
