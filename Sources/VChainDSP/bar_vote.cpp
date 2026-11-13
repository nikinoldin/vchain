// SPDX-License-Identifier: GPL-3.0-or-later
#include "bar_vote.h"
#include <cmath>

void BarVote::addDownbeat(int64_t t) {
    mT[mHead] = t;
    mHead = (mHead + 1) % kMax;
    if (mCount < kMax) mCount++;
}

const BarState& BarVote::update(LinkPort& link, int64_t now, double beatUs) {
    if (beatUs <= 0) { mState = {}; return mState; }
    int votes[4] = {}, n = 0;
    for (int i = 0; i < mCount; i++) {
        int64_t t = mT[i];
        if (now - t > 16000000 || t > now) continue;
        double x = link.beatAtTime(t, kLinkQuantum);
        double k = std::round(x);
        if (std::fabs(x - k) * beatUs > 60000) continue; // not on one of Link's beats
        votes[(long long)k % 4 < 0 ? int((long long)k % 4 + 4) : int((long long)k % 4)]++;
        n++;
    }
    const float kShare = 0.85f; // swept 0.85-1.0 / 4-10 votes on synthetic + All-In-One: 0.85 / 4 is best
    const int kMin = 4;
    int best = 0;
    for (int r = 1; r < 4; r++) if (votes[r] > votes[best]) best = r;
    float share = n ? float(votes[best]) / n : 0;
    if (!mState.locked) {
        if (n >= kMin && share >= kShare) mState = {true, best, share};
        else mState = {false, n ? best : -1, share};
    } else {
        if (n < 2 || (best != mState.residue && share >= kShare && n >= kMin)) mState = {n >= kMin && share >= kShare, best, share};
        else if (share < 0.6f && best == mState.residue) mState.locked = false, mState.confidence = share;
        else if (best != mState.residue) { float own = n ? float(votes[mState.residue]) / n : 0; mState.confidence = own; if (own < 0.6f) mState.locked = false; }
        else mState.confidence = share;
    }
    return mState;
}
