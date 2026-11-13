// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import VChainEngine

func runSpectrumChecks() {
    let numBins = 256
    let binHz: Float = 43.07
    let bands = Int(VC_NUM_SPECTRUM)

    func compute(_ mags: [Float]) -> [Float] {
        var out = [Float](repeating: -1, count: bands)
        mags.withUnsafeBufferPointer { m in
            vc_spectrum_bands(m.baseAddress, Int32(mags.count), binHz, &out, Int32(bands))
        }
        return out
    }

    Checks.run("spectrum: single bin at 100 Hz") {
        var mags = [Float](repeating: 0, count: numBins)
        mags[Int((100 / binHz).rounded())] = 1.0
        let out = compute(mags)
        // 100 Hz falls in band 3 (log-spaced 40 Hz...16 kHz, 24 bands).
        checkApprox(Double(out[3]), 1.0, tol: 0.02, "band holding 100 Hz is full scale")
        check(out[8...].allSatisfy { $0 < 0.05 }, "bands above 295 Hz (band 8 up) are quiet")
        check(out.allSatisfy { $0 >= 0 && $0 <= 1 }, "values within 0...1")
    }

    Checks.run("spectrum: silence") {
        let out = compute([Float](repeating: 0, count: numBins))
        check(out.allSatisfy { $0 == 0 }, "all bands 0")
    }

    Checks.run("spectrum: full-scale flat") {
        let out = compute([Float](repeating: 1, count: numBins))
        check(out.allSatisfy { $0 >= 0.95 }, "all bands >= 0.95")
    }

    // The display FFT is long enough that every band reads a bin of its own: a single full-scale bin
    // at a band's centre lights that band and neither neighbour.
    for rate: UInt32 in [44100, 48000, 96000] {
        Checks.run("spectrum: distinct bins per band at \(rate) Hz") {
            let size = Int(vc_spectrum_fft_size(rate))
            let rateHz = Float(rate), displayBinHz = rateHz / Float(size)
            check(size >= 4096 && size & (size - 1) == 0, "FFT size \(size) is a power of two >= 4096")
            check(displayBinHz <= 12, "bins of at most 12 Hz")
            var edges = [Float](repeating: 0, count: bands + 1)
            vc_spectrum_band_edges(&edges, Int32(bands + 1))
            var distinct = true
            for b in 0..<bands {
                var mags = [Float](repeating: 0, count: size / 2 + 1)
                mags[Int((sqrt(edges[b] * edges[b + 1]) / displayBinHz).rounded())] = 1
                var out = [Float](repeating: -1, count: bands)
                mags.withUnsafeBufferPointer { m in
                    vc_spectrum_bands(m.baseAddress, Int32(mags.count), displayBinHz, &out, Int32(bands))
                }
                let neighboursQuiet = (b == 0 || out[b - 1] == 0) && (b == bands - 1 || out[b + 1] == 0)
                if out[b] < 0.99 || !neighboursQuiet { distinct = false }
            }
            check(distinct, "each band's centre bin lights only that band")
        }
    }

    Checks.run("spectrum: band edges") {
        var edges = [Float](repeating: 0, count: bands + 1)
        vc_spectrum_band_edges(&edges, Int32(bands + 1))
        check(zip(edges, edges.dropFirst()).allSatisfy { $0 < $1 }, "strictly increasing")
        checkApprox(Double(edges[0]), 40, tol: 0.01, "starts at 40 Hz")
        checkApprox(Double(edges[bands]), 16000, tol: 1, "ends at 16 kHz")
    }
}
