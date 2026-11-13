// SPDX-License-Identifier: GPL-3.0-or-later
// "The 1" from the NN's downbeats (docs/beat-tracking.md, "BarVote"). Merged NN downbeats vote for Link's beat they land on
// (Link's beat count mod 4 at that time; votes are re-read against Link's current mapping, so a bar jump re-reads
// them correctly); over the last 16 s, the bar locks when one position has >= 85 % of at
// least 4 votes, and unlocks below 60 % (hysteresis). A wrong 1 shown confidently is worse than none (anti-goal), so
// nothing locks without that agreement.
#pragma once
#include "link_port.h"
#include <cstdint>

struct BarState {
    bool locked = false;
    int residue = -1;        // Link's beat (count mod 4) the music's 1 falls on; 0 = Link's bar is right
    float confidence = 0;    // share of the votes for that position
};

class BarVote {
public:
    void reset() { mCount = 0; mState = {}; }
    void addDownbeat(int64_t t);
    // Re-evaluate against Link (beatUs: the current beat length). Call once per hop while the beat is locked.
    const BarState& update(LinkPort& link, int64_t now, double beatUs);
    const BarState& state() const { return mState; }

private:
    static constexpr int kMax = 64;
    int64_t mT[kMax] = {};
    int mCount = 0, mHead = 0;
    BarState mState;
};
