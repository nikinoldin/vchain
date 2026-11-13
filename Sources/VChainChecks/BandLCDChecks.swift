// SPDX-License-Identifier: GPL-3.0-or-later
import VChainEngine
import VChainKit

func runBandLCDChecks() {
    let S = SevenSegment.segments(for:)
    let C = SevenSegment.letterC

    Checks.run("band LCD: Hz") {
        check(BandLCD.frequency(50).text == "50", "50 → 50")
        check(BandLCD.frequency(50).digits == [nil, 5, 0], "50 right-aligned, first cell blank")
        check(BandLCD.frequency(430.9).text == "431", "430.9 → 431")
        check(BandLCD.frequency(200).cells == [S(2), S(0), S(0)], "200 cells 2, 0, 0")
        check(BandLCD.frequency(50).cells == [[], S(5), S(0)], "50 cells blank, 5, 0")
        check(BandLCD.frequency(999.4).text == "999", "999.4 → 999")
        check(!BandLCD.frequency(928).kilo && !BandLCD.frequency(928).decimalPoint, "Hz: no k, no point")
    }
    Checks.run("band LCD: kHz") {
        let two = BandLCD.frequency(2000)
        check(two.text == "2.0k", "2000 → 2.0 k")
        check(two.digits == [nil, 2, 0] && two.decimalPoint && two.kilo, "2.0: point after cell 2, k lit")
        check(BandLCD.frequency(5656.9).text == "5.7k", "5656.9 → 5.7 k")
        check(BandLCD.frequency(999.6).text == "1.0k", "999.6 rounds up to 1.0 k")
        check(BandLCD.frequency(9960).text == "10k", "9960 → 10 k (not 10.0)")
        let sixteen = BandLCD.frequency(16000)
        check(sixteen.text == "16k" && !sixteen.decimalPoint, "16000 → 16 k, no point")
    }
    Checks.run("band LCD: instruments (3 bands)") {
        let b: Set<Segment> = [.c, .d, .e, .f, .g], d: Set<Segment> = [.b, .c, .d, .e, .g]
        check(BandLCD.instrument(0) == [[], b, d], "kick → _ b d")
        check(BandLCD.instrument(1) == [[], S(5), d], "snare → _ S d (S is a 5)")
        check(BandLCD.instrument(2) == [[], SevenSegment.letterH, SevenSegment.letterH], "hats → _ H H")
        check(BandLCD.instrument(3) == [[], [], []], "out of range → blank")
        check(Int(VC_INSTRUMENT_BANDS) == 3, "3 bands are the instruments")
    }
    Checks.run("band LCD: CC") {
        check(BandLCD.cc(1) == [C, C, [], S(1)], "CC 1 → C C _ 1")
        check(BandLCD.cc(8) == [C, C, [], S(8)], "CC 8 → C C _ 8")
        check(BandLCD.cc(14) == [C, C, S(1), S(4)], "CC 14 → C C 1 4")
        check(C == [.a, .d, .e, .f], "C is segments a, d, e, f")
    }

    func edges(_ count: Int) -> ([Float], [Float]) {
        var lo = [Float](repeating: 0, count: count), hi = [Float](repeating: 0, count: count)
        vc_trigger_band_edges(Int32(count), &lo, &hi)
        return (lo, hi)
    }
    Checks.run("trigger band edges") {
        let (lo3, hi3) = edges(3)
        check(lo3.map { Int($0.rounded()) } == [50, 200, 2000], "3 bands start at 50, 200, 2000")
        check(hi3.map { Int($0.rounded()) } == [200, 2000, 16000], "3 bands end at 200, 2000, 16000")
        let (lo8, hi8) = edges(8)
        let all8 = (lo8 + [hi8.last!]).map { Int($0.rounded()) }
        check(all8 == [50, 100, 200, 431, 928, 2000, 4000, 8000, 16000], "8 bands: 9 edges incl 431, 928 (\(all8))")
        var ok = true
        for n in Int(VC_MIN_TRIGGER_BANDS)...Int(VC_MAX_TRIGGER_BANDS) {
            let (lo, hi) = edges(n)
            if abs(lo[0] - 50) > 0.01 || abs(hi[n - 1] - 16000) > 1 { ok = false }
            for i in 0..<n where lo[i] >= hi[i] { ok = false }
            // 2 bands leave the mid zone out (low + high); from 3 on each band starts where the last ends.
            if n > 2 { for i in 1..<n where abs(lo[i] - hi[i - 1]) > 0.01 { ok = false } }
        }
        check(ok, "2…8 bands: 50 Hz to 16 kHz, lo < hi, contiguous from 3")
        let (lo2, hi2) = edges(2)
        check(lo2.map { Int($0.rounded()) } == [50, 2000] && Int(hi2[0].rounded()) == 200, "2 bands: low + high, gap 200–2000")
    }
}
