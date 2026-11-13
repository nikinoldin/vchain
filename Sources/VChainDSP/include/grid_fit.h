// SPDX-License-Identifier: GPL-3.0-or-later
// Robust fit of a constant grid t = origin + m·step to kick and snare onsets (hats ignored), docs/beat-tracking.md "GridFit".
// Step search: circular statistic over 121 candidates within ±3 % of approxStep; then iteratively reweighted least
// squares on the inliers (gate min(40 ms, step/4)). If the last 6 s fit clearly better (a DJ pitch ramp), that fit wins.
#pragma once
#include "drum_onsets.h"
#include <cstdint>

struct GridFit {
    bool ok = false;
    double step = 0;          // µs per grid step
    int64_t origin = 0;       // time of the grid index nearest to `now`
    double residualRms = 0;   // µs, inliers
    float inlierShare = 0;    // inliers / kick+snare onsets in the window, weighted by strength
    int inliers = 0, total = 0;
    double spanUs = 0;        // first to last inlier
};

GridFit fitGrid(const Onset* onsets, int n, double approxStep, int64_t now, double windowUs);

// Grid step from the onsets alone (no aubio): the S in [75,190] BPM whose quarter-beat grid the kick/snare onsets
// fit best (circular statistic, 0.1 BPM steps; ties between beat/3, beat/4 ... go to the plain 8th/16th grid). Returns µs per step, or 0 with fewer than 8 onsets. aubio's coarse
// tempo is unreliable in breakdowns and on breakbeats (jungle reads 114 instead of 170).
// hintS (aubio's tempo folded to [75,150), 0 = none) breaks ties between near-best plain steps: the one whose
// tempo agrees with it up to an octave wins.
double estimateGridStep(const Onset* onsets, int n, int64_t now, double windowUs, int64_t since = 0, double hintS = 0);
