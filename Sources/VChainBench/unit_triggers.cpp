// SPDX-License-Identifier: GPL-3.0-or-later
// The MIDI strip's trigger CCs (TriggerBands): which band fires for which sound, and the two decay shapes.
#include "trigger_bands.h"
#include "synth.h"
#include "unit.h"
#include <cstdlib>
#include <cmath>
#include <string>
#include <vector>

namespace {
constexpr uint32_t kHop = 512;

// Hit times (s) per band: hops where the CC jumps up.
std::vector<std::vector<double>> hitTimes(const std::vector<float>& a, int bands) {
    float lo[kTriggerMaxBands], hi[kTriggerMaxBands];
    triggerBandEdges(bands, lo, hi);
    TriggerBands tb;
    tb.reset(uint32_t(kSynthRate));
    tb.setBands(bands, lo, hi);
    tb.setDecayBeats(0.25f);
    std::vector<std::vector<double>> hits(bands);
    std::vector<float> prev(bands, 0);
    for (size_t pos = 0; pos + kHop <= a.size(); pos += kHop) {
        tb.process(&a[pos], kHop, 126);
        for (int i = 0; i < bands; i++) {
            if (tb.value(i) > prev[i] + 0.05f) hits[i].push_back((pos + kHop) / kSynthRate);
            prev[i] = tb.value(i);
        }
    }
    return hits;
}

// house-mix bars 1-15 (126 BPM, before the breakdown): kick on every beat, clap on steps 4 and 12, hats on the
// offbeats (2, 6, 10, 14) and quietly on odd 16ths, a bassline, a crash on bar 8's one (left out).
struct House {
    std::vector<float> audio;
    std::vector<double> steps[16]; // step time per 16th position
};
House scenarioSteps(const char* name, int barFrom, int barTo) {
    Scenario sc = makeScenario(name);
    House h;
    h.audio = sc.audio;
    const auto& b = sc.truth.beats;
    for (int bar = barFrom; bar < barTo; bar++)
        for (int k = 0; k < 4; k++) {
            double t0 = b[bar * 4 + k].t, ibi = b[bar * 4 + k + 1].t - t0;
            for (int s = 0; s < 4; s++)
                if (!(std::string(name) == "house-mix" && bar == 8 && k == 0 && s == 0)) h.steps[k * 4 + s].push_back(t0 + ibi * s / 4);
        }
    return h;
}
House house() { return scenarioSteps("house-mix", 1, 16); }

// Share of the given steps with a hit from ~5 ms before to 50 ms after (detection lags by up to ~40 ms).
double share(const std::vector<double>& hits, const House& h, std::initializer_list<int> steps) {
    int n = 0, found = 0;
    for (int s : steps)
        for (double t : h.steps[s]) {
            n++;
            for (double x : hits) if (x > t - 0.005 && x < t + 0.05) { found++; break; }
        }
    return n ? double(found) / n : 0;
}
std::string pct(double x) { return std::to_string(int(std::lround(x * 100))) + " %"; }
} // namespace

TEST(triggersBands) {
    House h = house();
    for (int bands : {2, 4, 5, 8}) {
        std::string tag = std::to_string(bands) + " bands";
        auto hits = hitTimes(h.audio, bands);
        // From 6 bands the lowest is sub/bassline (50-100 Hz): the kick may land in either of the two lowest, not both.
        double kick = share(hits[0], h, {0, 4, 8, 12});
        if (bands >= 6) {
            double k1 = share(hits[1], h, {0, 4, 8, 12});
            CHECK(std::min(kick, k1) <= 0.1, tag + ": the kick fires one low band, not two (" + pct(kick) + ", " + pct(k1) + ")");
            kick = std::max(kick, k1);
        }
        double hat = share(hits[bands - 1], h, {2, 6, 10, 14});
        double spill = share(hits[bands - 1], h, {0, 8});
        CHECK(kick >= 0.9, tag + ": a low band on the kicks (" + pct(kick) + ")");
        CHECK(hat >= 0.8, tag + ": highest band on the offbeat hats (" + pct(hat) + ")");
        CHECK(spill <= 0.1, tag + ": highest band quiet on kick-only steps (" + pct(spill) + ")");
        if (getenv("TRIGGER_DEBUG"))
            for (int i = 0; i < bands; i++)
                printf("    band %d: %zu hits; steps 0/8 %s, 4/12 %s, offbeats %s\n", i, hits[i].size(),
                       pct(share(hits[i], h, {0, 8})).c_str(), pct(share(hits[i], h, {4, 12})).c_str(),
                       pct(share(hits[i], h, {2, 6, 10, 14})).c_str());
    }
}

TEST(triggersInstruments) {
    // 3 bands = kick / snare / hat.
    House h = house();
    auto hits = hitTimes(h.audio, 3);
    double kick = share(hits[0], h, {0, 4, 8, 12}), kickOff = share(hits[0], h, {2, 6, 10, 14});
    double clap = share(hits[1], h, {4, 12}), clapOff = share(hits[1], h, {0, 8});
    double hat = share(hits[2], h, {2, 6, 10, 14}), hatOnKick = share(hits[2], h, {0, 8});
    CHECK(kick >= 0.9, "CC1 on the kicks (" + pct(kick) + ")");
    CHECK(kickOff <= 0.15, "CC1 quiet on the offbeats (" + pct(kickOff) + ")");
    CHECK(clap >= 0.8, "CC2 on the claps (" + pct(clap) + ")");
    CHECK(clapOff <= 0.1, "CC2 quiet on kick-only steps (" + pct(clapOff) + ")");
    CHECK(hat >= 0.8, "CC3 on the offbeat hats (" + pct(hat) + ")");
    CHECK(hatOnKick <= 0.1, "CC3 quiet on kick-only steps (" + pct(hatOnKick) + ")");
    if (getenv("TRIGGER_DEBUG"))
        printf("    CC1 steps 0/8 %s, 4/12 %s\n", pct(share(hits[0], h, {0, 8})).c_str(), pct(share(hits[0], h, {4, 12})).c_str());
}

TEST(triggersDnb) {
    // dnb-174 bars 8-40: kick on steps 0 and 10, snare on 4 and 12, a quiet hat on every 16th. The synth snare's noise
    // rings ~90 ms into the hat band and hides the hats after it, and its kick click is ~10 dB louder than a hat, so a
    // hat under a kick reads as the click (printed, not checked).
    House h = scenarioSteps("dnb-174", 8, 40);
    for (int bands : {3, 5}) {
        auto hits = hitTimes(h.audio, bands);
        std::string tag = std::to_string(bands) + " bands";
        double kick = share(hits[0], h, {0, 10}), hat = share(hits[bands - 1], h, {2, 6, 8, 14});
        CHECK(kick >= 0.9, tag + ": kicks (" + pct(kick) + ")");
        CHECK(hat >= 0.4, tag + ": hats away from kick and snare (" + pct(hat) + ")");
        if (getenv("TRIGGER_DEBUG"))
            printf("    hats landing with a kick: %s\n", pct(share(hits[bands - 1], h, {0, 10})).c_str());
    }
}

TEST(triggersClickNotSnare) {
    // Rumble techno (fourfour-altechmist): a kick on every beat whose beater click is a ~2 ms burst at +20 dB in
    // 1-5 kHz, a clap (three bursts, ~90 ms noise tail) on beats 2 and 4 for 8 bars, then 8 bars without claps.
    // The click passes the snare rule's big rise; only the clap's tail tells them apart.
    const double ibi = 60.0 / 126;
    std::vector<float> a(size_t((16 * 4 + 1) * ibi * kSynthRate), 0.0f);
    uint32_t seed = 7;
    auto noise = [&] { seed = seed * 1664525u + 1013904223u; return float(seed >> 8) / float(1 << 23) - 1.0f; };
    Biquad<float> hp, lp, clickHp, clickLp; // 1.5-5 kHz noise for the claps and the clicks
    for (auto* f : {&hp, &clickHp}) f->set(BiquadType::HighPass, 1500, 0.707, kSynthRate);
    for (auto* f : {&lp, &clickLp}) f->set(BiquadType::LowPass, 5000, 0.707, kSynthRate);
    std::vector<double> clapBeats, quietBeats;
    for (int beat = 0; beat < 16 * 4; beat++) {
        double t0 = beat * ibi;
        size_t s0 = size_t(t0 * kSynthRate);
        double ph = 0;
        for (size_t i = 0; i < size_t(0.3 * kSynthRate) && s0 + i < a.size(); i++) {
            double t = i / kSynthRate;
            ph += 2 * M_PI * (48 + 110 * std::exp(-t / 0.03)) / kSynthRate;
            a[s0 + i] += float(0.8 * std::sin(ph) * std::exp(-t / 0.2));
            if (t < 0.002) a[s0 + i] += 1.5f * clickLp.run(clickHp.run(noise()));
        }
        bool clap = beat % 2 == 1 && beat < 8 * 4;
        (clap ? clapBeats : quietBeats).push_back(t0);
        if (!clap) continue;
        for (size_t i = 0; i < size_t(0.25 * kSynthRate) && s0 + i < a.size(); i++) {
            double t = i / kSynthRate, env = 0;
            for (int k = 0; k < 3; k++) {
                double tk = t - k * 0.011;
                if (tk >= 0) env = std::max(env, std::exp(-tk / (k == 2 ? 0.09 : 0.006)));
            }
            a[s0 + i] += float(0.6 * env) * lp.run(hp.run(noise()));
        }
    }
    auto hits = hitTimes(a, 3);
    auto shareAt = [](const std::vector<double>& hit, const std::vector<double>& at) {
        int found = 0;
        for (double t : at)
            for (double x : hit) if (x > t - 0.005 && x < t + 0.05) { found++; break; }
        return at.empty() ? 0.0 : double(found) / at.size();
    };
    double clap = shareAt(hits[1], clapBeats), click = shareAt(hits[1], quietBeats), kick = shareAt(hits[0], quietBeats);
    CHECK(clap >= 0.8, "CC2 on the claps (" + pct(clap) + ")");
    CHECK(click <= 0.1, "CC2 quiet on the kick clicks (" + pct(click) + ")");
    CHECK(kick >= 0.9, "CC1 on the kicks (" + pct(kick) + ")");
}

TEST(triggersEnvelope) {
    // Tempo-locked: half a beat at 120 BPM = 250 ms, falling all the way.
    TriggerEnvelope env;
    env.setDecayBeats(0.5f);
    env.hit(0, 0.8f, 1);
    CHECK_NEAR(env.value(0), 0.8, 1e-6, "hit sets the strength");
    float prev = env.value(0);
    bool falling = true;
    float at200 = 0;
    for (int i = 1; i <= 30; i++) {
        env.advance(0.01f, 120, nullptr, 0);
        falling &= env.value(0) <= prev;
        prev = env.value(0);
        if (i == 20) at200 = prev;
    }
    CHECK(falling, "tempo decay never rises");
    CHECK(at200 > 0, "still above zero at 200 ms");
    CHECK(env.value(0) == 0, "zero after half a beat");
    env.hit(0, 1, 1);
    env.advance(0.125f, 240, nullptr, 0);
    CHECK(env.value(0) == 0, "half a beat at 240 BPM is 125 ms");

    // Follow: the energy falls 60 dB/s; 24 dB under the peak is zero (~0.4 s), and it never rises without a hit.
    TriggerEnvelope f;
    f.setDecayBeats(0);
    f.hit(0, 1, 1);
    float t = 0, zeroAt = -1;
    prev = 1;
    falling = true;
    for (int i = 0; i < 100; i++) {
        t += 0.01f;
        float e = std::pow(10.0f, -6.0f * std::max(0.0f, t - 0.03f));
        if (i == 50) e = 1; // a burst without a hit
        f.advance(0.01f, 120, &e, 1);
        falling &= f.value(0) <= prev;
        prev = f.value(0);
        if (zeroAt < 0 && prev == 0) zeroAt = t;
    }
    CHECK(falling, "follow never rises without a hit");
    CHECK(zeroAt > 0.3f && zeroAt < 0.5f, "follow reaches zero ~24 dB down (" + std::to_string(zeroAt) + " s)");
}
