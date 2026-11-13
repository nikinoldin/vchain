// SPDX-License-Identifier: GPL-3.0-or-later
import VChainEngine

enum MIDIReference {
    /// A one-line summary per descriptor CC for Settings (index = descriptor, order as in AudioAnalyzer::Descriptor).
    static let descriptorSummaries = [
        "K-weighted loudness",
        "Drum density × noisiness",
        "Spectral rolloff",
        "Bass vs. treble",
        "Tonal change",
        "Spectral entropy",
    ]

    static func descriptorCC(_ d: Int) -> Int { d + Int(VC_CC_DESCRIPTOR_BASE) }
    static func triggerCC(_ i: Int) -> Int { i + Int(VC_CC_TRIGGER_BASE) }
}
