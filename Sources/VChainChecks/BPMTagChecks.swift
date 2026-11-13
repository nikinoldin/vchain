// SPDX-License-Identifier: GPL-3.0-or-later
import VChainEngine
import VChainKit

func runBPMTagChecks() {
    func inputs(bpm: Double = 128.0, confidence: Double = 0.9, hasTempo: Bool = true,
                phase: Double = 1.3, peers: Int = 1, enabled: Bool = true,
                problem: Bool = false, time: Double = 0) -> BPMInputs {
        BPMInputs(enabled: enabled, bpm: bpm, confidence: confidence, hasTempo: hasTempo,
                  beatPhase: phase, linkPeers: peers, inputProblem: problem, time: time)
    }
    let S = SevenSegment.segments(for:)

    Checks.run("BPM tag: locked") {
        let s = BPMTagState.make(inputs())
        check(s.mode == .locked, "locked mode")
        check(s.digits == [S(1), S(2), S(8), S(0)], "digits 1,2,8,0")
        check(s.decimalPoint, "decimal point lit")
        check(s.litBeat == 1, "lit beat 1 at phase 1.3")
        check(s.mascot == .beatA, "odd beat: beat A")
        check(s.plugIn, "plug in with link peers")
        check(s.rockerOn, "rocker on")
        check(!s.showQuestion, "no question mark")
        check(!BPMTagState.make(inputs(peers: 0)).plugIn, "no plug without peers")
    }
    Checks.run("BPM tag: the 1 only on a found bar, dancing while holding") {
        var i = inputs(phase: 0.2); i.barLocked = false
        check(BPMTagState.make(i).mascot == .beatB, "bar not found: beat 0 is beat B, no move on the 1")
        check(BPMTagState.make(i).litBeat == BPMTagState.make(inputs(phase: 0.2)).litBeat, "blocks march either way")
        i = inputs(phase: 2.4); i.beatState = .holding
        check(BPMTagState.make(i).mode == .locked, "holding: locked")
        check(BPMTagState.make(i).mascot == .beatB, "holding: keeps dancing")
        i = inputs(phase: 0.2); i.beatState = .holding; i.barLocked = false
        check(BPMTagState.make(i).mascot == .beatB, "holding, bar not found: no move on the 1")
    }
    Checks.run("BPM tag: next change on the beat") {
        func near(_ a: Double?, _ b: Double) -> Bool { a.map { abs($0 - b) < 1e-9 } ?? false }
        check(near(BPMTagState.secondsToNextChange(beatPhase: 1.25, tempo: 120), 0.375), "beat 2, a quarter in: 0.375 s to the next beat")
        check(near(BPMTagState.secondsToNextChange(beatPhase: 0.1, tempo: 120), 0.45), "on the 1: the move lasts until beat 2")
        check(near(BPMTagState.secondsToNextChange(beatPhase: 3.9, tempo: 60), 0.1), "beat 4: to the next bar")
        check(BPMTagState.secondsToNextChange(beatPhase: 1, tempo: 0) == nil, "no tempo: nothing to schedule")
    }
    Checks.run("BPM tag: the beat state decides settling") {
        var i = inputs(confidence: 0.05); i.beatState = .locked
        check(BPMTagState.make(i).mode == .locked, "locked tracker, low confidence: locked, dancing")
        i = inputs(confidence: 0.9); i.beatState = .settling
        check(BPMTagState.make(i).mode == .settling, "settling tracker, high confidence: settling")
        i.beatState = .searching
        check(BPMTagState.make(i).mode == .settling, "searching: settling")
        i = inputs(hasTempo: false); i.beatState = .locked
        check(BPMTagState.make(i).mode == .settling, "no tempo: settling whatever the tracker says")
        for (c, swift) in [(VC_BEAT_SEARCHING, BeatState.searching), (VC_BEAT_SETTLING, .settling), (VC_BEAT_LOCKED, .locked), (VC_BEAT_HOLDING, .holding)] {
            check(BeatState(rawValue: Int(c.rawValue)) == swift, "VCBeatState \(c.rawValue) = \(swift)")
        }
    }
    Checks.run("BPM tag: mascot poses") {
        check(BPMTagState.make(inputs(phase: 0.2)).mascot == .theOne, "phase 0.2: the move on the 1")
        check(BPMTagState.make(inputs(phase: 0.95)).mascot == .theOne, "phase 0.95: the move lasts the whole 1")
        check(BPMTagState.make(inputs(phase: 1.05)).mascot == .beatA, "beat 2: beat A")
        check(BPMTagState.make(inputs(phase: 4.2)).mascot == .theOne, "the 1 on every bar start")
        check(BPMTagState.make(inputs(phase: 2.3)).mascot == .beatB, "even beat 2: beat B")
        check(BPMTagState.make(inputs(phase: 3.5)).litBeat == 3, "lit beat 3 at phase 3.5")
    }
    Checks.run("BPM tag: every beat a visible change") {
        // Early in each beat of two bars, with and without a found bar: the pose differs from the previous beat's.
        for barLocked in [true, false] {
            var last: MascotPose?
            for beat in 0..<8 {
                var i = inputs(phase: Double(beat) + 0.1); i.barLocked = barLocked
                let pose = BPMTagState.make(i).mascot
                if let last { check(pose != last, "beat \(beat) changes (bar \(barLocked ? "locked" : "not found"))") }
                last = pose
            }
        }
    }
    Checks.run("BPM tag: settling") {
        let s = BPMTagState.make(inputs(hasTempo: false, time: 0.0))
        check(s.mode == .settling, "no tempo: settling")
        check(s.litBeat == nil, "no lit beat")
        check(s.mascot == .still, "mascot still")
        check(s.showQuestion, "question shown at t=0")
        check(!BPMTagState.make(inputs(hasTempo: false, time: 0.7)).showQuestion, "question hidden at t=0.7")
        let on = BPMTagState.make(inputs(hasTempo: false, time: 0.2))
        let off = BPMTagState.make(inputs(hasTempo: false, time: 0.7))
        check(on.digits != Array(repeating: Set<Segment>(), count: 4), "digits visible on even half-second")
        check(off.digits == Array(repeating: Set<Segment>(), count: 4), "digits blank on odd half-second")
        check(on.digits == Array(repeating: SevenSegment.dash, count: 4), "no tempo: dashes, not bpm 0")
        check(!on.decimalPoint, "no tempo: no decimal point between the dashes")
        check(BPMTagState.make(inputs(confidence: 0.10, time: 0.2)).digits == [S(1), S(2), S(8), S(0)],
              "low confidence with tempo: digits of the bpm")
        check(BPMTagState.make(inputs(confidence: 0.10)).mode == .settling, "confidence 0.10 settling")
        check(BPMTagState.make(inputs(confidence: 0.20)).mode == .locked, "confidence 0.20 locked")
    }
    Checks.run("BPM tag: no input") {
        let s = BPMTagState.make(inputs(problem: true))
        check(s.mode == .noInput, "no input mode")
        check(s.digits == Array(repeating: SevenSegment.dash, count: 4), "all dashes")
        check(s.litBeat == nil, "no lit beat")
        check(s.mascot == .resting, "mascot resting")
        check(!BPMTagState.make(inputs(problem: true, time: 0.0)).showQuestion, "no input: no \"?\" (it would sit over the meditating figure)")
        check(!s.plugIn, "no plug")
    }
    Checks.run("BPM tag: off") {
        let s = BPMTagState.make(inputs(enabled: false))
        check(s.mode == .off, "off mode")
        check(s.digits == Array(repeating: Set<Segment>(), count: 4), "digits empty")
        check(s.mascot == .hidden, "mascot hidden")
        check(!s.plugIn, "no plug")
        check(!s.rockerOn, "rocker off")
    }
    Checks.run("BPM tag: leading zero") {
        let s = BPMTagState.make(inputs(bpm: 99.5))
        check(s.digits == [[], S(9), S(9), S(5)], "99.5 -> _ 9 9 5")
    }
}
