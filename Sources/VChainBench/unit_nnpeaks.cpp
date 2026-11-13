// SPDX-License-Identifier: GPL-3.0-or-later
#include "nn_peaks.h"
#include "unit.h"

// Beat This!'s minimal postprocessing: max within +/- 3 frames and > 0; adjacent peak frames merge.
TEST(nnPeaks) {
    float l[40];
    for (float& v : l) v = -5;
    l[5] = 2; l[6] = 1;            // one peak at 5
    l[15] = 3; l[16] = 3;          // a plateau: one peak at 15.5
    l[20] = 0.5f; l[22] = 4;       // 20 is within 3 frames of a bigger one: only 22
    l[30] = -0.5f;                 // below 0: none
    double p[10];
    int n = pickNNPeaks(l, 40, p, 10);
    CHECK(n == 3, "three peaks (" + std::to_string(n) + ")");
    CHECK(n == 3 && p[0] == 5 && p[1] == 15.5 && p[2] == 22, "at 5, 15.5, 22");
}
