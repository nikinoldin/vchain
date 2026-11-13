// SPDX-License-Identifier: GPL-3.0-or-later
// Everything vChain writes to Link (docs/beat-tracking.md, "LinkDriver"):
// - tempo: the locked grid's tempo smoothed over ~20 beats and rounded to 0.01 BPM, re-committed only when it moves by
//   >= 0.03 BPM; a small one-directional deviation (DJ ramp) is followed quickly, a jump only after 16 locked beats;
//   before the first lock aubio's coarse tempo; holding, settling and searching keep the last locked tempo;
// - phase: per locked, confident grid beat, a tempo nudge: T·(1 − clamp(0.5·e, ±3 %)) while pulling in after a lock,
//   then a 0.2 % nudge that starts when Link is > 8 ms off and runs until it is < 1 ms off;
// - at the first lock or a new tempo with Link more than 1/4 beat off: one forceBeatAtTime to the nearest beat;
// - the 1: once the bar vote has been locked on the same position for 8 beats, one whole-beat move of Link's bar;
// - a foreign tempo/phase edit (someone in Resolume) is reported (EvForeign), the expected timeline re-based, and no
//   force is made for 8 beats.
#pragma once
#include "bar_vote.h"
#include "beat_tracker.h"
#include "link_port.h"
#include <cstdint>

enum LinkEvent : uint8_t { EvNone = 0, EvCommit = 1, EvNudge = 2, EvForcePhase = 4, EvForceBar = 8, EvForeign = 16 };

class LinkDriver {
public:
    // aubio's coarse tempo and confidence (fallback before the first lock), set before each update.
    void setCoarse(double bpm, float conf) { mCoarseBpm = bpm; mCoarseConf = conf; }
    // Hybrid: the tempo to follow when it differs from the steering grid's (the drum tracker's, when it agrees with
    // the active grid within 1 %; steadier than the NN-fed fit). 0 = use the grid's own tempo.
    void setTempoSource(double bpm) { mTempoSource = bpm; }
    // Where the music's 1 is relative to Link's bar (BarVote); the driver moves Link's bar onto it (one whole-beat jump).
    void setBar(const BarState& b) { mBar = b; }
    const BarState& bar() const { return mBar; }
    // The tempo to show: the base tempo once locked, else aubio's (0 = none yet).
    double displayTempo() const;
    void reset();
    // Positive = Link's beats earlier than the audio (calibration for video latency).
    void setBeatOffsetUs(int64_t us) { mOffsetUs = us; }
    // Once per hop after the tracker. Returns LinkEvent bits for this hop.
    uint8_t update(int64_t now, BeatTracker& tracker, LinkPort& link);

private:
    uint8_t tempoStep(int64_t now, BeatTracker& tr, LinkPort& link);
    void barMoveStep(int64_t now, const BeatTracker& tr, LinkPort& link, uint8_t& ev);
    void phaseStep(int64_t now, int64_t latestBeat, const BeatTracker& tr, LinkPort& link, uint8_t& ev);
    void rebase(int64_t now, LinkPort& link);
    void commitTempo(double bpm, int64_t now, LinkPort& link);

    int64_t mOffsetUs = 0;
    bool mHaveBase = false;
    double mExpTempo = 0, mExpBeat = 0;  // the Link timeline vChain expects (from its own writes)
    int64_t mExpT = 0;
    size_t mPeers = 0;
    double mBase = 0;                    // tempo given to Link (smoothed locked tempo, rounded to 0.01)
    double mSmooth = 0;
    int mNudgeSign = 0;                  // running steady-state nudge: +1 slow down, -1 speed up, 0 none
    int64_t mLastJudged = 0;             // the last tracker beat Link's phase was judged at
    bool mPullIn = false, mForcePending = false;
    int mGoodBeats = 0;
    int64_t mNoForceUntil = 0;
    int64_t mLastSettlingCommit = -1;
    double mCoarseBpm = 0, mLastFallback = 0;
    float mCoarseConf = 0;
    int64_t mLastBaseCommit = 0;
    double mShown = 0;                   // shown tempo (0.1 BPM) with hysteresis
    double mTempoSource = 0;
    BarState mBar;
    int64_t mLastBarForce = -1;
    int mBarStableBeats = 0, mBarLastResidue = -1;
    int mBarShift = 0;                   // a scheduled bar move (beats), made on the beat that becomes the new 1
    int64_t mBarShiftUntil = 0, mPrevNow = 0;
    double mNudge = 1;                   // Link tempo = base x nudge while steering the phase
    int mPullSign = 0;                   // direction of the current pull
    double mPending = 0;                 // a different tempo waiting to be adopted
    int mPendingBeats = 0;               // locked beats it has held
    int mRampBeats = 0, mRampSign = 0;   // beats of a small one-directional deviation (a DJ ramp)
};
