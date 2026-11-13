// SPDX-License-Identifier: GPL-3.0-or-later
// Merges what successive rolling NN windows report into one stream of beats for the tracker (hybrid front end).
// Each beat is seen by up to ~12 windows (12 s window, one per second): its position is averaged over the windows that
// report it (matched within 60 ms), the window's last 0.25 s is skipped (the edge is unreliable), and a beat is handed
// on once, after 3 windows have seen it. Without this the NN's 20 ms frames and window-to-window changes jitter the
// grid (2-3x the tempo commits). Allocation-free; used on the engine thread (NNFrontEnd::popBeats) and by the bench.
#pragma once
#include "drum_onsets.h"
#include <cstdint>

class NNBeatMerger {
public:
    void reset() { mCount = 0; }
    // One window ending at tEndUs with its beat times (µs, capture clock). Writes beats that became ready to `out`
    // (at most maxOut, as OnsetClass::Beat onsets) and returns how many.
    int addWindow(int64_t tEndUs, const int64_t* beats, int n, Onset* out, int maxOut);

    static constexpr int kMax = 64;

private:
    struct Tracked { double time, sum; int n; bool sent; };
    Tracked mT[kMax];
    int mCount = 0; // sorted by time, oldest first
};
