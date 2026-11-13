// SPDX-License-Identifier: GPL-3.0-or-later
import VChainKit

func runEnergyPowerOnChecks() {
    typealias E = EnergyPowerOn
    let dt = 1.0 / 240
    let times = stride(from: 0.0, to: E.duration, by: dt).map { $0 }
    let frames = times.map { E.frame(elapsed: $0)! }
    func at(_ t: Double) -> E.Frame { E.frame(elapsed: t)! }

    Checks.run("Energy power-on: timeline") {
        check((0.9...1.1).contains(E.duration), "about a second (\(E.duration) s)")
        check(E.frame(elapsed: -0.01) == nil && E.frame(elapsed: E.duration) == nil, "nothing before the press or after the end")
        let full = at(E.allOn - 0.01)
        check(full.header == 1 && full.rows.allSatisfy { $0 == 1 } && full.spectrumLit == 1
              && full.lines.allSatisfy { $0 == 1 } && full.spectrum.allSatisfy { $0 == 1 },
              "first everything lit at full: header, labels, CCs, all six lines and every spectrum bar")
        check(at(E.fade / 2).header > 0 && at(E.fade / 2).header < 1 && at(E.fade).header == 1, "lighting up takes \(E.fade) s (crisp, not a pop)")
        let ghosts = at(E.rowsStart + 0.001)
        check(ghosts.header < 0.05 && ghosts.rows.allSatisfy { $0 < 0.05 } && ghosts.spectrumLit == 0, "then everything drops out to the ghosts")
    }
    Checks.run("Energy power-on: rows, then spectrum") {
        let lit = (0..<E.rowCount).map { i in times[frames.firstIndex { $0.rows[i] >= 1 && $0.lines[i] != 1 }!] }
        check(zip(lit, lit.dropFirst()).allSatisfy { $0 < $1 }, "the six rows light one after another")
        for i in 0..<E.rowCount {
            let after = zip(times, frames).filter { $0.0 > E.rowsStart }.map { $0.1.lines[i] }
            check(after.contains { ($0 ?? 0) > 0.99 }, "row \(i): its line sweeps to full")
            let live = frames.firstIndex { $0.lines[i] == nil } ?? frames.count
            check(frames[live...].allSatisfy { $0.lines[i] == nil && $0.rows[i] == 1 }, "row \(i): lit and live once its sweep is over")
        }
        let spectrumOn = zip(times, frames).first { $0.0 > E.rowsStart && $0.1.spectrumLit > 0 }!.0
        check(spectrumOn > lit.first! && spectrumOn < E.duration, "the spectrum comes after the rows have started")
        let peaks = (0..<E.barCount).map { c in zip(times, frames).filter { $0.0 > E.rowsStart }.max { ($0.1.spectrum[c] ?? 0) < ($1.1.spectrum[c] ?? 0) }!.0 }
        check(zip(peaks, peaks.dropFirst()).allSatisfy { $0 < $1 }, "the spectrum bars sweep left to right")
        let last = frames.last!
        check(last.header == 1 && last.rows.allSatisfy { $0 == 1 } && last.lines.allSatisfy { $0 == nil }, "everything lit and live by the end")
    }
}
