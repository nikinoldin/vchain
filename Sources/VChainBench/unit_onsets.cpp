// SPDX-License-Identifier: GPL-3.0-or-later
#include "drum_onsets.h"
#include "synth.h"
#include "unit.h"
#include <algorithm>
#include <cstdlib>
#include <cmath>
#include <vector>

namespace {
std::vector<Onset> detect(const std::vector<float>& audio, double sr) {
    DrumOnsets d;
    d.reset(uint32_t(sr));
    std::vector<Onset> all;
    Onset buf[16];
    for (size_t pos = 0; pos + 512 <= audio.size(); pos += 512) {
        int n = d.process(&audio[pos], 512, int64_t(std::llround(pos * 1e6 / sr)), buf, 16);
        all.insert(all.end(), buf, buf + n);
    }
    return all;
}

struct Hit { double t; OnsetClass cls; };

// Found share, median offset (ms) and share within ±3 ms of the median.
void score(const std::vector<Hit>& want, const std::vector<Onset>& got, double& found, double& med, double& tight) {
    std::vector<double> off;
    for (const auto& w : want) {
        double best = 1e9;
        for (const auto& g : got)
            if (g.cls == w.cls && std::fabs(g.t / 1e6 - w.t) < std::fabs(best)) best = g.t / 1e6 - w.t;
        if (std::fabs(best) < 0.015) off.push_back(best * 1000);
    }
    found = want.empty() ? 0 : double(off.size()) / want.size();
    if (getenv("ONSET_DEBUG")) {
        int miss[3] = {}, tot[3] = {};
        for (const auto& w : want) {
            tot[int(w.cls)]++;
            bool hit = false;
            for (const auto& g : got) hit |= g.cls == w.cls && std::fabs(g.t / 1e6 - w.t) < 0.015;
            if (!hit) { miss[int(w.cls)]++; if (miss[int(w.cls)] < 4) {
                printf("    miss cls %d at %.3f; nearby:", int(w.cls), w.t);
                for (const auto& g : got) if (std::fabs(g.t / 1e6 - w.t) < 0.05) printf(" [%d %.1fms %.2f]", int(g.cls), (g.t / 1e6 - w.t) * 1000, g.strength);
                printf("\n"); } }
        }
        printf("    missed kicks %d/%d snares %d/%d\n", miss[0], tot[0], miss[1], tot[1]);
    }
    std::vector<double> s = off;
    std::sort(s.begin(), s.end());
    med = s.empty() ? 0 : s[s.size() / 2];
    int ok = 0;
    for (double o : off) ok += std::fabs(o - med) <= 3.0;
    tight = off.empty() ? 0 : double(ok) / off.size();
}

std::vector<Hit> dnbHits(const Scenario& sc, int barFrom, int barTo) {
    std::vector<Hit> h;
    const auto& b = sc.truth.beats;
    for (int bar = barFrom; bar < barTo; bar++) {
        size_t i = size_t(bar) * 4;
        if (i + 3 >= b.size()) break;
        double ibi = b[i + 3].t - b[i + 2].t;
        h.push_back({b[i].t, OnsetClass::Kick});
        h.push_back({b[i + 2].t + ibi * 0.5, OnsetClass::Kick});
        h.push_back({b[i + 1].t, OnsetClass::Snare});
        h.push_back({b[i + 3].t, OnsetClass::Snare});
    }
    return h;
}
} // namespace

TEST(onsetsDnb) {
    for (double sr : {48000.0, 44100.0}) {
        Scenario sc = makeScenario("dnb-174");
        if (sr != kSynthRate) sc.audio = resampleLinear(sc.audio, sr / kSynthRate);
        auto got = detect(sc.audio, sr);
        double found, med, tight;
        score(dnbHits(sc, 8, 40), got, found, med, tight);
        std::string tag = sr == 48000 ? "48 kHz" : "44.1 kHz";
        CHECK(found >= 0.95, "dnb-174 " + tag + ": kicks and snares found (" + std::to_string(found) + ")");
        CHECK(std::fabs(med) <= 4.0, "dnb-174 " + tag + ": median offset small (" + std::to_string(med) + " ms)");
        CHECK(tight >= 0.9, "dnb-174 " + tag + ": timing within ±3 ms of the median (" + std::to_string(tight) + ")");
    }
}

TEST(onsetsHouseNoOffbeatKicks) {
    Scenario sc = makeScenario("house-mix");
    auto got = detect(sc.audio, kSynthRate);
    const auto& b = sc.truth.beats;
    double grooveEnd = b[16 * 4].t, bdA = b[16 * 4].t, bdB = b[24 * 4].t;
    int onBeat = 0, offBeat = 0, inBreakdown = 0, claps = 0, clapsWanted = 0;
    for (const auto& o : got) {
        double t = o.t / 1e6;
        if (o.cls == OnsetClass::Hat || t < 3.0) continue; // the running statistics warm up for ~2 s
        if (t > bdA + 0.05 && t < bdB) { inBreakdown++; continue; }
        if (t > grooveEnd) continue;
        double best = 1e9;
        for (size_t i = 0; i < 16 * 4; i++) best = std::min(best, std::fabs(b[i].t - t));
        (best < 0.02 ? onBeat : offBeat)++;
    }
    for (size_t i = 4; i < 16 * 4; i++) {
        if (i % 4 != 1 && i % 4 != 3) continue;
        clapsWanted++;
        for (const auto& o : got)
            if (o.cls == OnsetClass::Snare && std::fabs(o.t / 1e6 - b[i].t) < 0.015) { claps++; break; }
    }
    CHECK(onBeat >= 60, "house groove: kicks/claps on the beats (" + std::to_string(onBeat) + ")");
    CHECK(offBeat <= 3, "house groove: no kick/snare onsets on the off-beat hats (" + std::to_string(offBeat) + ")");
    CHECK(claps >= clapsWanted * 0.95, "house groove: claps on 2 and 4 classed as snare (" + std::to_string(claps) + "/" + std::to_string(clapsWanted) + ")");
    CHECK(inBreakdown == 0, "pad breakdown: no kick/snare onsets (" + std::to_string(inBreakdown) + ")");
}
