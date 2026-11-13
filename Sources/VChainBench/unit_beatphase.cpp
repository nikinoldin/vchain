// SPDX-License-Identifier: GPL-3.0-or-later
#include "beat_phase.h"
#include "unit.h"
#include <cmath>
#include <vector>

namespace {
struct Pattern { std::vector<int> kick, snare; };

// Onsets for `bars` bars of a 16-step pattern at `bpm` starting at t0 (µs); returns the downbeat times too.
void addBars(std::vector<Onset>& v, double& t, double bpm, int bars, const Pattern& p) {
    double step = 15e6 / bpm;
    for (int b = 0; b < bars; b++) {
        for (int s : p.kick) v.push_back({int64_t(t + s * step), OnsetClass::Kick, 0.9f});
        for (int s : p.snare) v.push_back({int64_t(t + s * step), OnsetClass::Snare, 0.8f});
        t += 16 * step;
    }
}

double fold(double bpm) { while (bpm >= 150) bpm /= 2; while (bpm < 75) bpm *= 2; return bpm; }

// Runs BeatPhase every half second over the onsets; returns the final choice and the fit.
BeatChoice run(std::vector<Onset> v, double coarseBpm, double endUs, GridFit& fitOut, double fromUs = 2e6) {
    std::sort(v.begin(), v.end(), [](auto& a, auto& b) { return a.t < b.t; });
    BeatPhase bp;
    bp.reset();
    BeatChoice c;
    for (double now = fromUs; now <= endUs; now += 5e5) {
        std::vector<Onset> w;
        for (auto& o : v) if (o.t <= now && o.t > now - 12e6) w.push_back(o);
        GridFit f = fitGrid(w.data(), int(w.size()), 15e6 / fold(coarseBpm), int64_t(now), 12e6);
        if (!f.ok) continue;
        c = bp.update(f, w.data(), int(w.size()), int64_t(now), 120, 50);
        fitOut = f;
    }
    return c;
}

double bpmOf(const BeatChoice& c, const GridFit& f) { return c.k ? 60e6 / (c.k * f.step) : 0; }
bool onBeat(const BeatChoice& c, const GridFit& f, double t0, double bpm) {
    double beat = 60e6 / bpm, d = std::fmod(std::fabs(double(c.beatAnchor) - t0), beat);
    return std::min(d, beat - d) < 0.25 * f.step;
}

const Pattern kHouse{{0, 4, 8, 12}, {4, 12}}, kDnb{{0, 10}, {4, 12}}, kBreaks{{0, 6, 10}, {4, 12}},
    kHalfTime{{0}, {8}}, kFour{{0, 4, 8, 12}, {}};
} // namespace

TEST(beatPhaseHouse) {
    std::vector<Onset> v; double t = 1e6, t0 = t;
    addBars(v, t, 126, 12, kHouse);
    GridFit f; BeatChoice c = run(v, 127.8, t, f);
    CHECK_NEAR(bpmOf(c, f), 126, 0.1, "house 126");
    CHECK(c.family == GrooveFamily::FourFour && c.decided, "four on the floor, decided");
    CHECK(onBeat(c, f, t0, 126), "beats on the kicks");
}

TEST(beatPhaseDnb) {
    std::vector<Onset> v; double t = 1e6, t0 = t;
    addBars(v, t, 174, 16, kDnb);
    GridFit f; BeatChoice c = run(v, 87.6, t, f); // aubio reads 87
    CHECK_NEAR(bpmOf(c, f), 174, 0.1, "DnB reads 174 with genre Auto");
    CHECK(c.family == GrooveFamily::Backbeat, "backbeat");
    CHECK(onBeat(c, f, t0, 174), "beats on kick 1 and the snares, not the 'and'");
}

TEST(beatPhaseBreaks) {
    std::vector<Onset> v; double t = 1e6, t0 = t;
    addBars(v, t, 132, 12, kBreaks);
    GridFit f; BeatChoice c = run(v, 133.6, t, f);
    CHECK_NEAR(bpmOf(c, f), 132, 0.1, "breaks 132");
    CHECK(c.family == GrooveFamily::Backbeat, "backbeat");
    CHECK(onBeat(c, f, t0, 132), "beats on the snares, not the syncopated kicks");
}

TEST(beatPhaseSlowFour) {
    std::vector<Onset> v; double t = 1e6;
    addBars(v, t, 87, 8, kFour);
    GridFit f; BeatChoice c = run(v, 87, t, f);
    CHECK_NEAR(bpmOf(c, f), 87, 0.1, "kick on every beat at 87 stays 87");
    std::vector<Onset> w; double t2 = 1e6;
    addBars(w, t2, 120, 10, kHouse);
    BeatChoice c2 = run(w, 121.5, t2, f);
    CHECK_NEAR(bpmOf(c2, f), 120, 0.1, "house 120 stays 120, not 60");
}

TEST(beatPhaseDnbHalfTimeKeepsOctave) {
    std::vector<Onset> v; double t = 1e6;
    addBars(v, t, 174, 24, kDnb);
    addBars(v, t, 174, 8, kHalfTime);   // 32 beats of half-time feel
    GridFit f; BeatChoice c = run(v, 87, t, f);
    CHECK_NEAR(bpmOf(c, f), 174, 0.1, "half-time section keeps 174");
}
