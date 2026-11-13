// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import VChainKit

/// Fixed sample values for module pictures that show no live audio: the module headers in Settings, the vector export
/// (`-debugRenderVector`), the app icon and the debug gallery's BPM tags.
enum SampleData {
    /// Trigger levels for up to eight bands.
    static let levels: [Float] = [0.9, 0.5, 0.75, 0.3, 0.6, 0.2, 0.8, 0.4]
    /// The six Energy descriptor values.
    static let values: [Float] = [0.62, 0.45, 0.5, 0.55, 0.3, 0.48]
    /// The 24 spectrum bands: falling gently towards the highs, with a wobble.
    static let spectrum: [Float] = (0..<24).map { i in Float(0.75 - 0.022 * Double(i) + 0.08 * sin(Double(i) * 1.7)) }

    /// A BPM tag's state: locked at 128 on beat 3 with one Link peer, unless told otherwise.
    static func tag(bpm: Double = 128, confidence: Double = 0.9, hasTempo: Bool = true, phase: Double = 2.4,
                    peers: Int = 1, enabled: Bool = true, problem: Bool = false, time: Double = 0.2) -> BPMTagState {
        BPMTagState.make(BPMInputs(enabled: enabled, bpm: bpm, confidence: confidence, hasTempo: hasTempo, beatPhase: phase,
                                   linkPeers: peers, inputProblem: problem, time: time))
    }
}
