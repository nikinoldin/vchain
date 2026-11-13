// SPDX-License-Identifier: GPL-3.0-or-later
#include "grid_fit.h"
#include "unit.h"
#include <cmath>
#include <random>
#include <vector>

namespace {
// Kick+snare onsets on a half-beat grid at `bpm`, starting at t0 (µs); drop-outs, outliers, jitter.
std::vector<Onset> gridOnsets(double bpm, double seconds, double dropShare, double outlierShare, double jitterMs,
                              uint32_t seed, double bpmEnd = 0) {
    std::mt19937 rng(seed);
    std::uniform_real_distribution<double> u(0, 1);
    std::normal_distribution<double> j(0, jitterMs * 1000);
    std::vector<Onset> v;
    double t = 1e6;
    int k = 0;
    while (t < seconds * 1e6) {
        double b = bpmEnd > 0 ? bpm + (bpmEnd - bpm) * (t / (seconds * 1e6)) : bpm;
        double half = 30e6 / b;
        if (u(rng) > dropShare) v.push_back({int64_t(t + j(rng)), k % 2 ? OnsetClass::Snare : OnsetClass::Kick, 0.8f});
        if (u(rng) < outlierShare) v.push_back({int64_t(t + half * (0.2 + 0.6 * u(rng))), OnsetClass::Kick, 0.5f});
        t += half;
        k++;
    }
    return v;
}
} // namespace

TEST(gridFitHouse) {
    auto on = gridOnsets(126, 14, 0.2, 0.15, 3, 1);
    int64_t now = on.back().t + 1000;
    double approx = 30e6 / (126 * 1.014); // aubio's +1.4 % bias
    GridFit g = fitGrid(on.data(), int(on.size()), approx, now, 12e6);
    CHECK(g.ok, "fit ok");
    double bpm = 30e6 / g.step;
    CHECK_NEAR(bpm, 126.0, 126 * 0.0002, "tempo within 0.02 %");
    // Origin must sit on the true grid (1e6 + k·half).
    double half = 30e6 / 126, off = std::fmod(double(g.origin - 1000000), half);
    if (off > half / 2) off -= half;
    CHECK_NEAR(off / 1000, 0.0, 2.0, "origin on the grid (ms)");
    CHECK(g.inlierShare > 0.7f, "most onsets are inliers");
}

TEST(gridFitJungleGhosts) {
    // Ghost hits on 16ths (a quarter beat off the half grid) must be rejected, not fitted.
    auto on = gridOnsets(170, 14, 0.3, 0, 2, 2);
    double half = 30e6 / 170;
    size_t n = on.size();
    for (size_t i = 0; i < n; i += 3) on.push_back({on[i].t + int64_t(half / 2), OnsetClass::Snare, 0.2f});
    std::sort(on.begin(), on.end(), [](auto& a, auto& b) { return a.t < b.t; });
    GridFit g = fitGrid(on.data(), int(on.size()), half * 1.01, on.back().t + 1000, 12e6);
    CHECK(g.ok, "fit ok");
    CHECK_NEAR(30e6 / g.step, 170.0, 0.05, "170 BPM despite 16th ghosts");
    CHECK(g.residualRms < 4000, "ghosts don't inflate the residual");
}

TEST(gridFitRamp) {
    auto on = gridOnsets(126, 14, 0.1, 0, 1, 3, 128);
    GridFit g = fitGrid(on.data(), int(on.size()), 30e6 / 127, on.back().t + 1000, 12e6);
    CHECK(g.ok, "ramp fit ok");
    CHECK(g.residualRms < 8000, "ramp residual RMS < 8 ms (" + std::to_string(g.residualRms / 1000) + ")");
    CHECK_NEAR(30e6 / g.step, 127.8, 0.4, "ramp: tempo near the end of the window");
}

TEST(gridStepFromOnsets) {
    struct Case { double bpm; double expectS; const char* name; } cases[] = {
        {126, 126, "house 126"}, {174, 87, "DnB 174 -> 87 (half-beat grid)"}, {170, 85, "jungle 170"},
        {132, 132, "breaks 132"}, {140, 70 * 2, "techno 140"}};
    for (auto& c : cases) {
        auto on = gridOnsets(c.bpm, 10, 0.4, 0.1, 2, 9);
        double step = estimateGridStep(on.data(), int(on.size()), on.back().t + 1000, 8e6);
        double S = step > 0 ? 15e6 / step : 0;
        // A half-beat grid at bpm is a quarter-beat grid at bpm/2; either fold is the same grid.
        double want = c.expectS >= 150 ? c.expectS / 2 : c.expectS;
        CHECK(std::fabs(S / want - 1) < 0.004 || std::fabs(S / (want * 2) - 1) < 0.004, std::string(c.name) + " (S " + std::to_string(S) + ")");
    }
    // Hits only on the beats (house kicks + claps): not beat/3 (122 -> 91.5).
    std::vector<Onset> beatsOnly;
    for (int i = 0; i < 24; i++) beatsOnly.push_back({int64_t(1e6 + i * 60e6 / 122), i % 2 ? OnsetClass::Snare : OnsetClass::Kick, 0.9f});
    double S = 15e6 / estimateGridStep(beatsOnly.data(), 24, beatsOnly.back().t + 1000, 12e6);
    CHECK(std::fabs(S / 122 - 1) < 0.004 || std::fabs(S / 61 - 1) < 0.004, "beats only at 122: a dyadic grid (S " + std::to_string(S) + ")");
}
