// SPDX-License-Identifier: GPL-3.0-or-later
#include "nn_beats.h"
#include <cmath>

int NNBeatMerger::addWindow(int64_t tEndUs, const int64_t* beats, int n, Onset* out, int maxOut) {
    int k = 0;
    for (int b = 0; b < n; b++) {
        double t = double(beats[b]);
        if (t > double(tEndUs) - 250000) continue;
        int hit = -1;
        for (int i = mCount - 1; i >= 0; i--) {
            if (mT[i].time < t - 1e6) break;
            if (std::fabs(mT[i].time - t) < 60000) { hit = i; break; }
        }
        if (hit < 0) {
            if (mCount > 0 && t < mT[mCount - 1].time - 1e6) continue; // far behind the newest: already settled
            if (mCount == kMax) { for (int i = 1; i < kMax; i++) mT[i - 1] = mT[i]; mCount--; }
            int pos = mCount;
            while (pos > 0 && mT[pos - 1].time > t) { mT[pos] = mT[pos - 1]; pos--; }
            mT[pos] = Tracked{t, t, 1, false};
            mCount++;
            continue;
        }
        Tracked& x = mT[hit];
        x.sum += t;
        x.n++;
        x.time = x.sum / x.n;
        if (!x.sent && x.n >= 3 && k < maxOut) {
            x.sent = true;
            out[k++] = Onset{int64_t(std::llround(x.time)), OnsetClass::Beat, 1.0f};
        }
    }
    return k;
}
