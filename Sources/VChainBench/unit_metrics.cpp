// SPDX-License-Identifier: GPL-3.0-or-later
#include "metrics.h"
#include "synth.h"
#include "unit.h"
#include <cmath>

namespace {
// Sets Link straight from the truth, shifted by `shiftMs` and `shiftBeats`: what a perfect tracker would do.
class Oracle : public Pipeline {
public:
    Oracle(const Annotation& a, double shiftMs, int shiftBeats) : mA(a), mShiftMs(shiftMs), mShiftBeats(shiftBeats) {}
    const char* name() const override { return "oracle"; }
    void reset(uint32_t) override { mNext = 0; }
    void process(const float*, uint32_t n, int64_t capture, int64_t, LinkPort& link) override {
        double t0 = (capture - kBenchBaseUs) / 1e6, t1 = t0 + n / 48000.0;
        while (mNext < mA.beats.size() && mA.beats[mNext].t < t1) {
            const auto& b = mA.beats[mNext++];
            int64_t at = kBenchBaseUs + int64_t((b.t + mShiftMs / 1000) * 1e6);
            double cur = link.beatAtTime(at, 4);
            double want = std::floor(cur / 4) * 4 + ((b.beatInBar - 1 + mShiftBeats) % 4);
            if (want - cur > 2) want -= 4;
            if (cur - want > 2) want += 4;
            double bpm = mA.bpmAt(b.t);
            if (bpm > 0) link.setTempo(bpm, at);
            link.forceBeatAtTime(want, at, 4);
        }
        mView.state = 2;
        mView.displayBpm = mA.bpmAt(t0);
    }
    PipelineView view() const override { return mView; }
private:
    const Annotation& mA;
    double mShiftMs; int mShiftBeats; size_t mNext = 0;
    PipelineView mView;
};

Summary runOracle(const Scenario& sc, double ms, int beats) {
    Oracle o(sc.truth, ms, beats);
    RunOptions opt;
    RunTrace tr = runSection(o, sc.audio, sc.truth, opt);
    return summarize(sc.name, sc.truth.genre, measure(tr, sc.truth, 0));
}
} // namespace

TEST(metricsOracle) {
    Scenario sc = makeScenario("house-mix");
    Summary s = runOracle(sc, 0, 0);
    CHECK(s.phaseMedMs < 1, "perfect: phase median < 1 ms");
    CHECK_NEAR(s.barOkPct, 100, 0.01, "perfect: bar right 100 %");
    CHECK(s.beatF > 0.99, "perfect: beat F 1");
    Summary late = runOracle(sc, 30, 0);
    CHECK_NEAR(late.phaseMedMs, 30, 1.0, "30 ms early grid: phase median 30 ms");
    Summary bar = runOracle(sc, 0, 1);
    CHECK(bar.barOkPct < 1, "one beat off: bar right 0 %");
}
