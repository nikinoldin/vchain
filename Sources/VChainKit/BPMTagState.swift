// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

public struct BPMInputs: Sendable {
    public var enabled: Bool
    public var bpm: Double
    public var confidence: Double
    public var hasTempo: Bool
    public var beatPhase: Double   // beats, Link grid; integer part counts beats
    public var linkPeers: Int
    public var inputProblem: Bool
    public var time: Double        // seconds, for blinking
    /// Link's beat 0 is the music's 1: only then may the mascot do its move on the 1 (the beat blocks always follow Link's bar).
    public var barLocked: Bool
    /// The beat tracker's state (VCBeatState). It decides settling vs. dancing; nil (no tracker, e.g. the galleries)
    /// falls back to `confidence`.
    public var beatState: BeatState?

    public init(enabled: Bool, bpm: Double, confidence: Double, hasTempo: Bool, beatPhase: Double,
                linkPeers: Int, inputProblem: Bool, time: Double, barLocked: Bool = true, beatState: BeatState? = nil) {
        self.enabled = enabled; self.bpm = bpm; self.confidence = confidence; self.hasTempo = hasTempo
        self.beatPhase = beatPhase; self.linkPeers = linkPeers; self.inputProblem = inputProblem
        self.time = time; self.barLocked = barLocked; self.beatState = beatState
    }
}

/// The beat tracker's state, VCBeatState's values: searching and settling show the tag settling ("?"); locked and
/// holding (a breakdown: the tempo is held and Link keeps the beat) show it locked, the mascot dancing.
public enum BeatState: Int, Sendable {
    case searching = 0, settling = 1, locked = 2, holding = 3
}

public enum BPMMode: Sendable { case locked, settling, off, noInput }
/// What the LCD's mascot (the dancer; more characters may follow) shows. Neutral names, so each character draws
/// its own take: `beatA`/`beatB` alternate on every beat (each beat a clearly visible change), `theOne` is the
/// move on the 1 (only once the bar is locked), `still` while settling, `resting` (the dancer meditates) while the input is
/// missing, `hidden` while BPM detection is off. `wave` (hello) is only for the tag's power-on (`TagPowerOn`).
public enum MascotPose: Sendable { case still, beatA, beatB, theOne, resting, hidden, wave }

public struct BPMTagState: Sendable, Equatable {
    /// Without a beat state: confidence below this counts as still settling.
    public static let lockConfidence = 0.15
    static let blinkHz = 2.0
    static let questionHz = 1.6

    public var mode: BPMMode
    /// Hundreds, tens, ones, tenths.
    public var digits: [Set<Segment>]
    public var decimalPoint: Bool
    public var litBeat: Int?
    public var mascot: MascotPose
    public var showQuestion: Bool
    public var plugIn: Bool
    public var rockerOn: Bool

    static let blank = [Set<Segment>](repeating: [], count: 4)

    public static func make(_ i: BPMInputs) -> BPMTagState {
        guard i.enabled else {
            return BPMTagState(mode: .off, digits: blank, decimalPoint: false, litBeat: nil,
                               mascot: .hidden, showQuestion: false, plugIn: false, rockerOn: false)
        }
        if i.inputProblem {
            return BPMTagState(mode: .noInput, digits: [Set<Segment>](repeating: SevenSegment.dash, count: 4),
                               decimalPoint: false, litBeat: nil, mascot: .resting, showQuestion: false,
                               plugIn: false, rockerOn: true)
        }
        let plug = i.linkPeers > 0
        // The tracker's state decides (aubio's confidence dips while the grid stays locked); confidence only without it.
        let unsettled = i.beatState.map { $0 == .searching || $0 == .settling } ?? (i.confidence < lockConfidence)
        if !i.hasTempo || unsettled {
            let blinkOff = Int(floor(i.time * blinkHz)) % 2 != 0
            let question = Int(floor(i.time * questionHz)) % 2 == 0
            // No tempo yet: blinking dashes, not the digits of bpm 0.
            let shown = i.hasTempo ? digits(for: i.bpm) : [Set<Segment>](repeating: SevenSegment.dash, count: 4)
            return BPMTagState(mode: .settling, digits: blinkOff ? blank : shown,
                               decimalPoint: !blinkOff && i.hasTempo, litBeat: nil, mascot: .still,
                               showQuestion: question, plugIn: plug, rockerOn: true)
        }
        let beat = Int(floor(i.beatPhase))
        let index = ((beat % 4) + 4) % 4
        let mascot: MascotPose
        // Holding (breakdown) keeps dancing on Link's beat; the move on the 1 needs a locked bar either way and lasts
        // the whole beat (then A, B, A: every beat still a visible change).
        if index == 0 && i.barLocked { mascot = .theOne }
        else { mascot = index % 2 == 1 ? .beatA : .beatB }
        return BPMTagState(mode: .locked, digits: digits(for: i.bpm), decimalPoint: true,
                           litBeat: index, mascot: mascot, showQuestion: false, plugIn: plug, rockerOn: true)
    }

    /// Seconds from `beatPhase` (Link beats into the bar, 0..<4) at `tempo` BPM until the beat display next changes:
    /// the next beat. The keychain and the menu bar schedule a redraw for then, so the mascot and the beat blocks
    /// change on the beat instead of on their next timer tick. Nil without a tempo.
    public static func secondsToNextChange(beatPhase: Double, tempo: Double) -> Double? {
        guard tempo > 0, beatPhase.isFinite else { return nil }
        return (1 - (beatPhase - floor(beatPhase))) * 60 / tempo
    }

    /// Four digits for a BPM rounded to tenths; leading zero suppressed (e.g. 99.5 -> _995).
    static func digits(for bpm: Double) -> [Set<Segment>] {
        guard bpm.isFinite else { return blank }
        let tenths = min(9999, max(0, Int((bpm * 10).rounded())))
        let parts = [tenths / 1000, tenths / 100 % 10, tenths / 10 % 10, tenths % 10]
        return parts.enumerated().map { idx, d in
            idx == 0 && d == 0 ? [] : SevenSegment.segments(for: d)
        }
    }
}
