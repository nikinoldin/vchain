// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import VChainEngine
import VChainKit
import Observation

/// A one-shot timer for the next moment the beat display changes (`BPMTagState.secondsToNextChange`: the next beat),
/// so the mascot and the beat blocks change on the beat instead of on the next timer tick (the keychain redraws at
/// 30 Hz at rest, the menu bar polls at 10 Hz: up to 33 or 100 ms late, visibly off the beat). The keychain reads `tick` in its body (a change
/// re-evaluates it); the menu bar passes `onFire`. Re-armed after every update, so tempo changes are followed.
@MainActor @Observable
final class BeatTicker {
    /// Bumped when the timer fires.
    private(set) var tick = 0
    @ObservationIgnored var onFire: (() -> Void)?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var due: Date?

    /// Arms the timer for the next change after `s` (just past it, so the phase reads the new beat); keeps one
    /// already armed for (nearly) the same moment. No tempo: cancels.
    func arm(_ s: LiveState) {
        guard let secs = BPMTagState.secondsToNextChange(beatPhase: s.beatPhase, tempo: s.linkTempo) else { cancel(); return }
        // `s` was sampled at `s.now`; take off the time since.
        let since = Double(vc_now_micros() &- s.now) / 1_000_000
        let date = Date().addingTimeInterval(max(0, secs - since) + 0.002)
        if let due, abs(due.timeIntervalSince(date)) < 0.003 { return }
        timer?.invalidate()
        due = date
        let t = Timer(fire: date, interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.timer = nil; self.due = nil
                self.tick &+= 1
                self.onFire?()
            }
        }
        t.tolerance = 0
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func cancel() {
        timer?.invalidate(); timer = nil; due = nil
    }
}
