// SPDX-License-Identifier: GPL-3.0-or-later
// The committed beat grid and its states (docs/beat-tracking.md, "BeatTracker"): searching / settling / locked / holding.
// Feeds on kick/snare onsets (DrumOnsets) and aubio's coarse tempo (BpmDetector); refits the half/16th grid
// (GridFit), decides octave and beat positions (BeatPhase), rejects short jumps (spinbacks, echo-outs) and
// accepts a new grid after a hard cut (4 consistent beats) or a different tempo (8 beats).
#pragma once
#include "beat_phase.h"
#include "drum_onsets.h"
#include "grid_fit.h"
#include <cstdint>

enum class BeatState : uint8_t { Searching = 0, Settling = 1, Locked = 2, Holding = 3 };

struct Grid {
    double beatUs = 0;       // µs per beat (0 = none)
    int64_t anchor = 0;      // the time of one beat
    // The last beat at or before t.
    int64_t beatAtOrBefore(int64_t t) const;
    double bpm() const { return beatUs > 0 ? 60e6 / beatUs : 0; }
};

class BeatTracker {
public:
    void reset();
    // New onsets (any class; hats are kept out of the grid).
    void addOnsets(const Onset* o, int n);
    // Once per hop. now = capture time of the hop's end.
    void tick(int64_t now, float coarseBpm, float priorCenter, float priorSigma);

    BeatState state() const { return mState; }
    const Grid& committed() const { return mCommitted; }
    // Settling before the very first lock: the best candidate grid so far (beatUs 0 if none).
    const Grid& candidate() const { return mCandidate; }
    // The candidate has been consistent for at least 4 beats (safe enough to give Link its tempo).
    bool candidateStable(int64_t now) const {
        return mCandidate.beatUs > 0 && mConsistentSince >= 0 && now - mConsistentSince >= int64_t(4 * mCandidate.beatUs);
    }
    bool everLocked() const { return mCommitted.beatUs > 0; }
    // True once after each new lock (track start, hard cut, re-lock after searching).
    bool takeLockEvent() { bool e = mLockEvent; mLockEvent = false; return e; }
    float stability() const { return mStability; }
    GrooveFamily family() const { return mPhase.choice().family; }

    static constexpr int kRing = 256;

private:
    struct Candidate { bool ok = false; Grid grid; GrooveFamily family = GrooveFamily::Unknown; bool decided = false; };
    Candidate evaluate(int64_t now, double approxStep, int64_t since, float priorCenter, float priorSigma, BeatPhase& phase);
    bool consistent(const Grid& a, const Grid& b, double phaseTolUs) const;
    void lockOn(const Grid& g, int64_t now);
    double gateUs() const;

    Onset mRing[kRing];
    int mCount = 0, mHead = 0;            // ring of kick/snare onsets, oldest at (mHead - mCount)
    int mNewSinceFit = 0;
    BeatState mState = BeatState::Searching;
    Grid mCommitted, mCandidate;
    BeatPhase mPhase, mChallengerPhase;
    bool mLockEvent = false;
    int64_t mConsistentSince = -1;        // candidate consistent since (before the first lock / after searching)
    int64_t mLastInlier = 0;              // last onset on the committed grid
    int64_t mHoldingSince = 0, mLastTick = 0;
    int64_t mChallengerStart = -1;        // first off-grid onset of a possible new grid
    int64_t mChallengerOkSince = -1;
    bool mChallengerHardCut = false;
    int mOffGrid = 0;                     // consecutive strong off-grid onsets
    double mOffGridOffsets[4] = {};
    float mShare = 1;                     // inlier share, moving average over ~10 onsets
    int mInlierRun = 0;                   // consecutive inliers
    int64_t mCoarseOffSince = -1;
    int64_t mGuardSince = -1;            // committed tempo disagrees with aubio (not by an octave) since
    float mStability = 0;
};
