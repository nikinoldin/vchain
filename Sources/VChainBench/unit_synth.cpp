// SPDX-License-Identifier: GPL-3.0-or-later
#include "synth.h"
#include "unit.h"
#include <algorithm>

TEST(synthScenarios) {
    for (const auto& name : scenarioNames()) {
        Scenario sc = makeScenario(name);
        double len = sc.audio.size() / kSynthRate;
        float peak = 0;
        for (float v : sc.audio) peak = std::max(peak, std::fabs(v));
        bool increasing = true, cycles = true;
        for (size_t i = 1; i < sc.truth.beats.size(); i++) {
            increasing &= sc.truth.beats[i].t > sc.truth.beats[i - 1].t;
            const auto& p = sc.truth.beats[i - 1]; const auto& b = sc.truth.beats[i];
            bool sameGrid = b.t - p.t < 0.8;
            if (sameGrid) cycles &= b.beatInBar == p.beatInBar % 4 + 1;
        }
        CHECK(sc.name == name, name + ": renders");
        CHECK(len > 60, name + ": longer than 60 s");
        CHECK(peak > 0.1f && peak <= 1.0f, name + ": level");
        CHECK(increasing && cycles, name + ": truth beats increase and cycle 1-4");
        CHECK(!sc.truth.genre.empty(), name + ": genre set");
    }
}

TEST(synthTruthValues) {
    Scenario d = makeScenario("dnb-174");
    CHECK_NEAR(d.truth.bpmAt(60.0), 174.0, 0.01, "dnb-174 truth tempo");
    Scenario h = makeScenario("house-mix");
    for (const char* tag : {"breakdown", "ramp", "blend", "cut"}) {
        bool found = false;
        for (const auto& r : h.truth.regions) found |= r.tag == tag;
        CHECK(found, std::string("house-mix has region ") + tag);
    }
    Scenario l = makeScenario("loop-off-one");
    CHECK(l.truth.beats.front().beatInBar == 3, "loop-off-one starts on beat 3");
    Scenario a = makeScenario("techno-140", 1), b = makeScenario("techno-140", 1);
    CHECK(a.audio == b.audio, "same seed renders identical audio");
}
