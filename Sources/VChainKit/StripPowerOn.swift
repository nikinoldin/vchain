// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// The MIDI strip's power-on self-test, played when its slide switch is flipped on (≈1 s, like real
/// gear): everything lit, then a wave of ladders filling and emptying left to right, then each module's
/// LCDs come on and its ladder goes live, module after module. Purely visual: given the time since the
/// flip, what each channel module shows.
public enum StripPowerOn {
    /// What a module's two LCDs show.
    public enum LCDMode: Equatable, Sendable {
        /// Ghost segments only (as when off).
        case blank
        /// Every segment ("8.8.8 k", "8888").
        case all
        /// The band's range and CC number.
        case normal
    }

    public struct Module: Equatable, Sendable {
        /// Lit ladder steps, 0…10; nil = the live level.
        public var ladder: Int?
        public var lcd: LCDMode
        /// How far the LCD's lit segments have darkened in, 0…1 (LCD response, not a pop).
        public var lcdLevel: Double
        /// The CC LCD's level when it differs from the range LCD's (a retune that keeps the CC number); nil = `lcdLevel`.
        public var ccLevel: Double?

        public init(ladder: Int?, lcd: LCDMode, lcdLevel: Double, ccLevel: Double? = nil) {
            self.ladder = ladder; self.lcd = lcd; self.lcdLevel = lcdLevel; self.ccLevel = ccLevel
        }

        public static let live = Module(ladder: nil, lcd: .normal, lcdLevel: 1)
    }

    /// Everything on (LEDs at once, LCDs darkening in).
    public static let allOn = 0.2
    /// LCD segments darken in / fade out over this (liquid crystal response).
    public static let lcdResponse = 0.08
    /// The sweep starts once the "all on" LCDs have faded out.
    public static let sweepStart = allOn + lcdResponse
    /// One ladder's fill (bottom → top) plus empty (top → bottom).
    public static let ladderSweep = 0.3
    /// Per-module delays: a constant step for few bands, squeezed so 8 bands still end on time.
    static func sweepStagger(bands: Int) -> Double { bands > 1 ? min(0.12, 0.3 / Double(bands - 1)) : 0 }
    static func settleStagger(bands: Int) -> Double { bands > 1 ? min(0.08, 0.2 / Double(bands - 1)) : 0 }

    /// When the wave has left the last ladder.
    public static func sweepEnd(bands: Int) -> Double {
        sweepStart + ladderSweep + sweepStagger(bands: bands) * Double(max(bands, 1) - 1)
    }

    /// When module `i`'s LCDs start coming on and its ladder goes live.
    public static func settleStart(_ i: Int, bands: Int) -> Double {
        sweepEnd(bands: bands) + settleStagger(bands: bands) * Double(i)
    }

    /// Total length: the last module's LCDs fully on.
    public static func duration(bands: Int) -> Double {
        settleStart(max(bands, 1) - 1, bands: bands) + lcdResponse
    }

    /// Module `i` (0 = left) of `bands`, `elapsed` seconds after the flip.
    public static func module(_ i: Int, bands: Int, elapsed t: Double) -> Module {
        if t < 0 { return Module(ladder: 0, lcd: .blank, lcdLevel: 0) }
        if t < allOn { return Module(ladder: 10, lcd: .all, lcdLevel: ramp(t / lcdResponse)) }
        let settle = settleStart(i, bands: bands)
        if t >= settle { return Module(ladder: nil, lcd: .normal, lcdLevel: ramp((t - settle) / lcdResponse)) }
        // Dropped out: the LCD fades while the wave passes through the ladders.
        let lcd = t < sweepStart ? Module(ladder: 0, lcd: .all, lcdLevel: 1 - ramp((t - allOn) / lcdResponse))
                                 : Module(ladder: 0, lcd: .blank, lcdLevel: 0)
        var m = lcd
        m.ladder = sweepLadder((t - sweepStart - sweepStagger(bands: bands) * Double(i)) / ladderSweep)
        return m
    }

    /// Every module at `elapsed`, or nil once the test is over (show the live state).
    public static func modules(bands: Int, elapsed: Double) -> [Module]? {
        elapsed >= duration(bands: bands) ? nil : (0..<bands).map { module($0, bands: bands, elapsed: elapsed) }
    }

    /// A single module starting up after it has been added to the strip (≈0.6 s from the snap): everything on, the LCDs
    /// fade out while its ladder sweeps up and down once, then its range and CC values fade on. Nil once it's done.
    public static let bootAllOn = 0.15, bootSweepStart = 0.2
    public static var bootSettle: Double { bootSweepStart + ladderSweep }
    public static var bootDuration: Double { bootSettle + lcdResponse }

    public static func moduleBoot(elapsed t: Double) -> Module? {
        if t >= bootDuration { return nil }
        if t < 0 { return Module(ladder: 0, lcd: .blank, lcdLevel: 0) }
        if t < bootAllOn { return Module(ladder: 10, lcd: .all, lcdLevel: ramp(t / lcdResponse)) }
        if t >= bootSettle { return Module(ladder: nil, lcd: .normal, lcdLevel: ramp((t - bootSettle) / lcdResponse)) }
        let fading = t < bootAllOn + lcdResponse
        return Module(ladder: sweepLadder((t - bootSweepStart) / ladderSweep), lcd: fading ? .all : .blank,
                      lcdLevel: fading ? 1 - ramp((t - bootAllOn) / lcdResponse) : 0)
    }

    /// The strip's modules re-tuning after the band count changed (an eject or add has just snapped): at the snap every
    /// range LCD goes dark, then left to right each fades back on with its new range, its ladder blipping as it does;
    /// its CC LCD only goes dark and comes back if its number changed. Nil for a module once it's done.
    public static let retuneBlip = 0.07, retuneBlipSteps = 4
    static func retuneStagger(bands: Int) -> Double { bands > 1 ? min(0.06, 0.36 / Double(bands - 1)) : 0 }
    public static func retuneDuration(bands: Int) -> Double { retuneStagger(bands: bands) * Double(max(bands, 1) - 1) + lcdResponse }

    public static func retune(_ i: Int, bands: Int, elapsed t: Double, ccChanged: Bool) -> Module? {
        let local = t - retuneStagger(bands: bands) * Double(i)
        if t < 0 || local >= max(lcdResponse, retuneBlip) { return nil }
        let level = local < 0 ? 0 : ramp(local / lcdResponse)
        let blip = local >= 0 && local < retuneBlip
        return Module(ladder: blip ? retuneBlipSteps : nil, lcd: .normal, lcdLevel: level, ccLevel: ccChanged ? level : 1)
    }

    /// Lit steps at `p` through one ladder's sweep (0 → 10 → 0 over 0…1; dark outside).
    static func sweepLadder(_ p: Double) -> Int {
        guard p > 0, p < 1 else { return 0 }
        let up = p < 0.5 ? p * 2 : (1 - p) * 2
        return min(10, max(0, Int((up * 10).rounded())))
    }

    private static func ramp(_ x: Double) -> Double { min(1, max(0, x)) }
}

extension StripPowerOn {
    /// `frame` (one entry per module, nil = all live) with a band being learned laid over it: its ladder shows the
    /// MIDI learn sweep's value (0…1).
    public static func withLearn(_ frame: [Module]?, _ learning: (index: Int, value: Double)?, bands: Int) -> [Module]? {
        guard let learning, learning.index < bands else { return frame }
        var out = frame ?? Array(repeating: .live, count: bands)
        guard out.count == bands else { return frame }
        out[learning.index] = Module(ladder: Int((learning.value * 10).rounded()), lcd: .normal, lcdLevel: 1)
        return out
    }

    /// `frame` with the strip settling after an eject or add (`StripEdit.settle`: re-tuning ripple, an added module's
    /// start-up) laid over it, module by module.
    public static func withSettle(_ frame: [Module]?, _ settle: [Module]?, bands: Int) -> [Module]? {
        guard let settle, settle.count == bands else { return frame }
        return (0..<bands).map { i in settle[i] != .live ? settle[i] : (frame.flatMap { i < $0.count ? $0[i] : nil } ?? .live) }
    }
}
