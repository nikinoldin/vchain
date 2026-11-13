// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// The BPM tag's power-on, played when its rocker is flipped on (≈1.1 s, like the MIDI strip's self-test and real
/// segment-LCD gear): every segment lit, dropping out, the beat blocks sweeping 1 → 4, then the mascot boots (comes on
/// standing still and waves hello twice) and the live display takes over (settling "- - -" until a tempo is found).
/// Purely visual: given the time since the flip, what the LCD shows. Never at launch, none with Reduce Motion, and
/// switching off stays instant (the caller's job).
public enum TagPowerOn {
    public enum Show: Equatable, Sendable {
        /// Every segment of the LCD.
        case all
        /// One beat block (0 = "1").
        case block(Int)
        /// The mascot in a pose (digits and blocks dark).
        case mascot(MascotPose)
    }

    public struct Frame: Equatable, Sendable {
        public var show: Show
        /// How far the lit segments have darkened in, 0…1 (LCD response, not a pop).
        public var level: Double
        public init(show: Show, level: Double) { self.show = show; self.level = level }
    }

    /// LCD segments darken in / fade out over this (liquid crystal response), as on the strip.
    public static let lcdResponse = StripPowerOn.lcdResponse
    /// Everything on.
    public static let allOn = 0.2
    /// The block sweep starts once "all" has faded out.
    public static let sweepStart = allOn + lcdResponse + 0.02
    /// Each beat block's turn.
    public static let blockStep = 0.09
    /// The mascot comes on.
    public static let bootStart = sweepStart + 4 * blockStep + 0.02
    /// The mascot's hello, after it came on still: (start, pose).
    public static let hello: [(Double, MascotPose)] = [
        (bootStart, .still), (bootStart + 0.12, .wave), (bootStart + 0.24, .still), (bootStart + 0.32, .wave),
    ]
    /// Total length; then the live display.
    public static let duration = bootStart + 0.44

    /// The LCD `elapsed` seconds after the flip, or nil once the power-on is over (show the live state).
    public static func frame(elapsed t: Double) -> Frame? {
        if t >= duration { return nil }
        if t < 0 { return Frame(show: .all, level: 0) }
        if t < allOn { return Frame(show: .all, level: ramp(t / lcdResponse)) }
        if t < sweepStart { return Frame(show: .all, level: 1 - ramp((t - allOn) / lcdResponse)) }
        if t < bootStart {
            let i = min(3, Int((t - sweepStart) / blockStep))
            let into = t - sweepStart - Double(i) * blockStep
            return Frame(show: .block(i), level: ramp(into / lcdResponse))
        }
        let step = hello.last { $0.0 <= t } ?? hello[0]
        // Only coming on darkens in; the hello's limbs switch like a real LCD's segments within one frame or two.
        return Frame(show: .mascot(step.1), level: ramp((t - bootStart) / lcdResponse))
    }

    private static func ramp(_ x: Double) -> Double { min(1, max(0, x)) }
}
