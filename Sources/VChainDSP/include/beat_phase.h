// SPDX-License-Identifier: GPL-3.0-or-later
// Decides what the fitted grid leaves open (docs/beat-tracking.md, "BeatPhase"):
// - the octave: beat = k grid steps, k = 2, 4 or 8 within 60-180 BPM (the grid step is a quarter beat of the coarse
//   tempo folded into [75,150): a half beat for DnB, a 16th for house/techno/breaks),
// - which grid positions are the beats (not the off-beats),
// - the groove family: FourFour (kick on >= 80 % of beats) or Backbeat (snare on >= 70 % of every second beat, < 30 %
//   of the others: DnB, breaks). The backbeat rule picks the octave that puts the snare on every second beat, so DnB
//   reads 174, not 87. The genre prior only breaks ties.
// Within a lock the octave changes only after 64 beats of contrary evidence (a DnB half-time section keeps 174),
// the beat/off-beat choice after 16.
#pragma once
#include "grid_fit.h"
#include <cstdint>

enum class GrooveFamily : uint8_t { Unknown = 0, FourFour = 1, Backbeat = 2 };

struct BeatChoice {
    int k = 0;                   // beat = k grid steps (0 = no choice yet)
    int64_t beatAnchor = 0;      // the time of one beat (any beat; with the grid this places every beat)
    GrooveFamily family = GrooveFamily::Unknown;
    bool decided = false;        // the same choice for >= 6 beats
};

class BeatPhase {
public:
    void reset();
    // Re-evaluates on a new fit. onsets: recent kick/snare/hat onsets (hats ignored).
    BeatChoice update(const GridFit& fit, const Onset* onsets, int n, int64_t now, float priorCenterBpm, float priorSigma);
    // A new lock (track start, hard cut): the next choice is free again.
    void newLock();
    const BeatChoice& choice() const { return mChoice; }

private:
    struct Eval { int k; int64_t anchor; GrooveFamily family; bool kickOk, backbeatOk; double nnShare = 0; };
    Eval evaluate(const GridFit& fit, const Onset* onsets, int n, int k, int64_t now) const;

    BeatChoice mChoice;
    int64_t mStableSince = 0;     // when the current choice was first seen
    int64_t mContraSince = -1;    // when contrary evidence started (-1 = none)
    bool mLockedOnce = false;     // after `decided`, hysteresis applies until newLock()
};
