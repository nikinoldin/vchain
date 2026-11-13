// SPDX-License-Identifier: GPL-3.0-or-later
#include "nn_beats.h"
#include "unit.h"
#include <cmath>
#include <random>
#include <vector>

// Windows of 12 s every 1 s report the same 126 BPM beats with 20 ms frame quantization and a little noise: each beat
// comes out once, averaged, after 3 windows.
TEST(nnBeatMerger) {
    NNBeatMerger m;
    m.reset();
    std::mt19937 rng(5);
    std::normal_distribution<double> noise(0, 6000);
    const double beat = 60e6 / 126;
    std::vector<Onset> got;
    for (int w = 3; w <= 40; w++) {
        int64_t tEnd = int64_t(w * 1e6);
        std::vector<int64_t> b;
        for (double t = std::ceil((tEnd - 12e6) / beat) * beat; t <= tEnd; t += beat)
            if (t >= 0) b.push_back(int64_t(std::round((t + noise(rng)) / 20000) * 20000));
        Onset out[64];
        int k = m.addWindow(tEnd, b.data(), int(b.size()), out, 64);
        got.insert(got.end(), out, out + k);
    }
    int dup = 0;
    double err = 0;
    for (size_t i = 0; i < got.size(); i++) {
        if (i && got[i].t - got[i - 1].t < 200000) dup++;
        double x = got[i].t / beat;
        err += std::fabs(x - std::round(x)) * beat;
    }
    CHECK(got.size() > 70, "beats delivered (" + std::to_string(got.size()) + ")");
    CHECK(dup == 0, "each beat once");
    CHECK(err / got.size() < 6000, "averaged position within 6 ms (" + std::to_string(err / got.size() / 1000) + " ms)");
}
