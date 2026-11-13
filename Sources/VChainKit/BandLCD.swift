// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// What the MIDI strip's two small segment LCDs show per channel module: the band's frequency range
/// (start on the upper row, end on the lower) and its CC number.
public enum BandLCD {
    /// One frequency row: three digit cells, right-aligned (nil = blank), a decimal point after the
    /// second cell, and the "k" annunciator for kHz.
    public struct Frequency: Equatable, Sendable {
        public var digits: [Int?]
        public var decimalPoint: Bool
        public var kilo: Bool

        public var cells: [Set<Segment>] { digits.map { $0.map(SevenSegment.segments(for:)) ?? [] } }

        /// As the display reads, e.g. "50", "5.7k", "16k".
        public var text: String {
            var s = ""
            for (i, d) in digits.enumerated() {
                if let d { s += String(d) }
                if i == 1 && decimalPoint { s += "." }
            }
            return kilo ? s + "k" : s
        }
    }

    /// Hz below 1000 as a plain integer (431); from 1 kHz on as kHz with the "k" lit: one decimal below
    /// 10 kHz (5.7), an integer from 10 kHz (16). Rounded to nearest; clamped to 0…999 k.
    public static func frequency(_ hz: Double) -> Frequency {
        let hz = max(0, hz)
        if hz.rounded() < 1000 {
            return Frequency(digits: rightAligned(Int(hz.rounded())), decimalPoint: false, kilo: false)
        }
        let tenths = Int((hz / 100).rounded())
        if tenths < 100 {
            return Frequency(digits: [nil, tenths / 10, tenths % 10], decimalPoint: true, kilo: true)
        }
        return Frequency(digits: rightAligned(min(Int((hz / 1000).rounded()), 999)), decimalPoint: false, kilo: true)
    }

    /// "CC n" over four cells: C, C, then the number right-aligned in the last two (blank tens below 10).
    public static func cc(_ number: Int) -> [Set<Segment>] {
        let n = min(max(number, 0), 99)
        let tens: Set<Segment> = n >= 10 ? SevenSegment.segments(for: n / 10) : []
        return [SevenSegment.letterC, SevenSegment.letterC, tens, SevenSegment.segments(for: n % 10)]
    }

    /// The MIDI channel over four cells: "CH", then 1–16 right-aligned (blank tens below 10).
    public static func channel(_ number: Int) -> [Set<Segment>] {
        let n = min(max(number, 1), 16)
        let tens: Set<Segment> = n >= 10 ? SevenSegment.segments(for: n / 10) : []
        return [SevenSegment.letterC, SevenSegment.letterH, tens, SevenSegment.segments(for: n % 10)]
    }

    /// With 3 trigger bands the strip's modules are instruments, not frequency ranges: the range LCD's upper row reads
    /// the drum-machine name instead, right-aligned like the frequencies: "bd" (kick), "Sd" (snare/clap), "HH" (hats).
    /// Seven segments can't draw a K, hence bd. Lower row blank. Index outside 0…2: blank.
    public static func instrument(_ index: Int) -> [Set<Segment>] {
        let b: Set<Segment> = [.c, .d, .e, .f, .g], d: Set<Segment> = [.b, .c, .d, .e, .g]
        let s: Set<Segment> = [.a, .c, .d, .f, .g], h = SevenSegment.letterH
        switch index {
        case 0: return [[], b, d]
        case 1: return [[], s, d]
        case 2: return [[], h, h]
        default: return [[], [], []]
        }
    }

    /// "LRn" over four cells (L, r, n, blank): the MIDI strip's channel LCD while it's unplugged (MIDI learn).
    public static func learn() -> [Set<Segment>] { [[.d, .e, .f], [.e, .g], [.c, .e, .g], []] }

    private static func rightAligned(_ n: Int) -> [Int?] {
        [n >= 100 ? n / 100 : nil, n >= 10 ? n / 10 % 10 : nil, n % 10]
    }
}
