// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// The Energy module's power-on self-test, played when its power key turns it on (≈1 s, like the MIDI strip's
/// and the BPM tag's). The screen is treated as fixed graphics that light up over the faint ghosts it shows
/// when off: everything lit at full (labels, CCs, header, all six lines and every spectrum bar full), drop
/// out to the ghosts, then the six descriptor rows light one after another (label, CC and the line sweeping
/// to full and back, then live), then the spectrum bars sweep left to right and go live. Each element fades
/// on and off over `fade` (like the LCDs' segments). Purely visual: given the time since the key press,
/// what the screen shows.
public enum EnergyPowerOn {
    public struct Frame: Equatable, Sendable {
        /// The header (MIDI icon, "CH n") and the divider: 0 = ghost, 1 = lit.
        public var header: Double
        /// Each descriptor row's label, CC and track (6): 0 = ghost, 1 = lit.
        public var rows: [Double]
        /// Each row's value line (6), 0…1; nil = the live value.
        public var lines: [Double?]
        /// The spectrum's bars and baselines: 0 = ghost, 1 = lit.
        public var spectrumLit: Double
        /// Each spectrum bar (24), 0…1; nil = the live level.
        public var spectrum: [Double?]
    }

    public static let rowCount = 6
    public static let barCount = 24

    /// Elements fade on and off over this (liquid-crystal-like response, crisp).
    public static let fade = 0.08
    /// Everything lit at full.
    public static let allOn = 0.2
    /// The rows start once everything has dropped out to the ghosts.
    public static let rowsStart = allOn + fade
    /// Each row: lit, its line sweeping to full and back over `lineSweep`, then live; the next `rowStagger` later.
    public static let rowStagger = 0.07, lineSweep = 0.22
    /// The spectrum bars sweep left to right: each rises and falls over `barSweep`, the next `barStagger` later.
    public static let spectrumStart = 0.62, barSweep = 0.14, barStagger = 0.01

    /// When row `i` lights.
    public static func rowStart(_ i: Int) -> Double { rowsStart + Double(i) * rowStagger }
    /// When spectrum bar `c` goes live.
    public static func barLive(_ c: Int) -> Double { spectrumStart + Double(c) * barStagger + barSweep }

    /// The whole test: the last spectrum bar live (the last row is live before that).
    public static var duration: Double { max(barLive(barCount - 1), rowStart(rowCount - 1) + lineSweep) }

    /// The screen `elapsed` seconds after the key press, or nil once the test is over (show the live state).
    public static func frame(elapsed t: Double) -> Frame? {
        guard t >= 0, t < duration else { return nil }
        if t < rowsStart {
            // Everything on at full, then dropping out to the ghosts.
            let level = t < allOn ? ramp(t / fade) : 1 - ramp((t - allOn) / fade)
            return Frame(header: level, rows: Array(repeating: level, count: rowCount),
                         lines: Array(repeating: 1, count: rowCount),
                         spectrumLit: level, spectrum: Array(repeating: 1, count: barCount))
        }
        let rows = (0..<rowCount).map { ramp((t - rowStart($0)) / fade) }
        let lines: [Double?] = (0..<rowCount).map { i in
            let p = (t - rowStart(i)) / lineSweep
            return p >= 1 ? nil : sweep(p)
        }
        let spectrum: [Double?] = (0..<barCount).map { c in
            let start = spectrumStart + Double(c) * barStagger
            return t >= start + barSweep ? nil : sweep((t - start) / barSweep)
        }
        return Frame(header: rows[0], rows: rows, lines: lines,
                     spectrumLit: ramp((t - spectrumStart) / fade), spectrum: spectrum)
    }

    /// Up to full and back down over 0…1 (eased); 0 outside.
    static func sweep(_ p: Double) -> Double {
        guard p > 0, p < 1 else { return 0 }
        let up = p < 0.5 ? p * 2 : (1 - p) * 2
        return up * up * (3 - 2 * up)
    }

    private static func ramp(_ x: Double) -> Double { min(1, max(0, x)) }
}
