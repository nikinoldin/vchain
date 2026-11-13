// SPDX-License-Identifier: GPL-3.0-or-later
// Ported from Beat This! (MIT), see THIRD_PARTY_NOTICES.md
#include "nn_peaks.h"
#include <algorithm>

int pickNNPeaks(const float* logits, int n, double* out, int maxOut) {
    int k = 0;
    int runStart = -1, runEnd = -1;
    auto flush = [&]() {
        if (runStart >= 0 && k < maxOut) out[k++] = 0.5 * (runStart + runEnd);
        runStart = runEnd = -1;
    };
    for (int i = 0; i < n; i++) {
        float m = logits[i];
        for (int d = -3; d <= 3; d++) {
            int j = i + d;
            if (j >= 0 && j < n) m = std::max(m, logits[j]);
        }
        bool peak = logits[i] == m && logits[i] > 0;
        if (peak) {
            if (runStart >= 0 && i == runEnd + 1) runEnd = i;
            else { flush(); runStart = runEnd = i; }
        }
    }
    flush();
    return k;
}
