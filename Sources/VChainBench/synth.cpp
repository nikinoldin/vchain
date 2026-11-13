// SPDX-License-Identifier: GPL-3.0-or-later
#include "synth.h"
#include "biquad.h"
#include <algorithm>
#include <cmath>
#include <functional>

namespace {

constexpr double SR = kSynthRate;

struct Rng {
    uint64_t s;
    explicit Rng(uint64_t seed) : s(seed * 0x9E3779B97F4A7C15ull + 1) {}
    uint32_t next() { s ^= s << 13; s ^= s >> 7; s ^= s << 17; return uint32_t(s >> 11); }
    float uni() { return (next() & 0xFFFFFF) / float(0x1000000); }
    float noise() { return uni() * 2.0f - 1.0f; }
};

using Filter = Biquad<double>;
Filter filter(BiquadType type, double f, double q) {
    Filter b;
    b.set(type, f, q, SR);
    return b;
}
constexpr BiquadType LP = BiquadType::LowPass, HP = BiquadType::HighPass, BP = BiquadType::BandPass;

using Sound = std::vector<float>;

Sound kickSound(double endHz, double decay, float click, Rng& r) {
    Sound s(size_t(0.4 * SR));
    double ph = 0;
    Filter hp = filter(HP, 3000, 0.7);
    for (size_t i = 0; i < s.size(); i++) {
        double t = i / SR;
        double f = endHz + 110 * std::exp(-t / 0.03);
        ph += 2 * M_PI * f / SR;
        double v = std::sin(ph) * std::exp(-t / decay) * std::min(1.0, t / 0.001);
        if (t < 0.003) v += click * hp.run(r.noise()) * (1 - t / 0.003);
        s[i] = float(v);
    }
    return s;
}

Sound noiseSound(double dur, double decay, Filter a, Filter b, Rng& r, int bursts = 1, double gap = 0) {
    Sound s(size_t(dur * SR));
    for (size_t i = 0; i < s.size(); i++) {
        double t = i / SR, env = 0;
        for (int k = 0; k < bursts; k++) {
            double tk = t - k * gap;
            if (tk >= 0) env = std::max(env, std::exp(-tk / (k == bursts - 1 ? decay : 0.006)) * std::min(1.0, tk / 0.0005));
        }
        s[i] = float(b.run(a.run(r.noise())) * env);
    }
    return s;
}

Sound snareSound(double bodyHz, Rng& r) {
    Sound s = noiseSound(0.25, 0.09, filter(HP, 1000, 0.7), filter(LP, 6000, 0.7), r);
    for (size_t i = 0; i < s.size(); i++) {
        double t = i / SR;
        s[i] = 0.8f * s[i] + float(0.7 * std::sin(2 * M_PI * bodyHz * t) * std::exp(-t / 0.06) * std::min(1.0, t / 0.0008));
    }
    return s;
}

void normalize(Sound& s) {
    float p = 0;
    for (float v : s) p = std::max(p, std::fabs(v));
    if (p > 0) for (float& v : s) v /= p;
}

struct Kit {
    Sound kick, clap, snare, hat, ohat, crash, ride;
    static Kit make(int variant, Rng& r) {
        Kit k;
        k.kick = kickSound(variant == 1 ? 50 : variant == 2 ? 42 : 46, variant == 2 ? 0.3 : 0.22, variant == 1 ? 0.6f : 0.35f, r);
        k.clap = noiseSound(0.3, 0.09, filter(BP, 1400 + 200 * variant, 1.2), filter(HP, 700, 0.7), r, 3, 0.011);
        k.snare = snareSound(185 + 15 * variant, r);
        k.hat = noiseSound(0.06, 0.018, filter(HP, 7500, 0.7), filter(HP, 7000, 0.7), r);
        k.ohat = noiseSound(0.35, 0.16, filter(HP, 7000, 0.7), filter(HP, 6500, 0.7), r);
        k.crash = noiseSound(2.0, 0.9, filter(HP, 4000, 0.7), filter(HP, 3500, 0.7), r);
        k.ride = noiseSound(0.5, 0.25, filter(BP, 5500, 2.0), filter(HP, 4000, 0.7), r);
        for (Sound* s : {&k.kick, &k.clap, &k.snare, &k.hat, &k.ohat, &k.crash, &k.ride}) normalize(*s);
        return k;
    }
};

void add(std::vector<float>& out, const Sound& s, double t, float g) {
    long start = lround(t * SR);
    for (size_t i = 0; i < s.size(); i++) {
        long j = start + long(i);
        if (j >= 0 && j < long(out.size())) out[j] += g * s[i];
    }
}

void tone(std::vector<float>& out, double t, double dur, double f, float g, bool saw) {
    long start = lround(t * SR), n = lround(dur * SR);
    double ph = 0;
    for (long i = 0; i < n && start + i < long(out.size()); i++) {
        if (start + i < 0) continue;
        double x = i / SR;
        double env = std::min(1.0, x / 0.004) * std::min(1.0, (dur - x) / 0.01);
        ph += f / SR;
        double frac = ph - std::floor(ph);
        double v = saw ? 0.7 * std::sin(2 * M_PI * ph) + 0.3 * (2 * frac - 1) : std::sin(2 * M_PI * ph);
        out[start + i] += g * float(env * v);
    }
}

enum class Style { House, Minimal, Techno, DnB, Jungle, Breaks };

struct BarSpec {
    bool kick = true, clap = true, hats = true, ohat = true, bass = true, pad = false, crash = false;
    bool halftime = false, kickOnlyOne = false, kickOneThree = false;
    float gain = 1;
};

// A beat grid: beats[i] is the time of beat i; beat i sits at position (i + first) % 4 in its bar (0 = the 1).
struct Grid {
    std::vector<double> beats;
    int first = 0;
    double barTime(int bar) const { int i = bar * 4 - first; return i >= 0 && i < int(beats.size()) ? beats[i] : end(); }
    double end() const { return beats.empty() ? 0 : beats.back() + 60.0 / lastBpm; }
    double lastBpm = 120;
    void appendFrom(double t0, int n, double bpmA, double bpmB) {
        double t = t0;
        for (int k = 0; k < n; k++) {
            double bpm = bpmA + (bpmB - bpmA) * (n > 1 ? double(k) / (n - 1) : 0.0);
            beats.push_back(t);
            t += 60.0 / bpm;
            lastBpm = bpm;
        }
    }
};

struct Deck {
    Style style;
    Kit kit;
    double roots[4];
};

// Renders bars [barFrom, barTo) of a deck over a grid.
void renderDeck(std::vector<float>& out, const Deck& d, const Grid& g, int barFrom, int barTo,
                const std::function<BarSpec(int)>& spec, Rng& rng) {
    for (int bar = barFrom; bar < barTo; bar++) {
        BarSpec b = spec(bar);
        if (b.gain <= 0) continue;
        double root = d.roots[((bar % 4) + 4) % 4];
        for (int k = 0; k < 4; k++) {
            int i = bar * 4 + k - g.first;
            if (i < 0 || i >= int(g.beats.size())) continue;
            double t0 = g.beats[i];
            double ibi = i + 1 < int(g.beats.size()) ? g.beats[i + 1] - t0 : 60.0 / g.lastBpm;
            for (int s = 0; s < 4; s++) {
                int step = k * 4 + s;
                double t = t0 + ibi * s / 4.0;
                float G = b.gain;
                auto hit = [&](const Sound& snd, float gain) { add(out, snd, t, gain * G); };
                switch (d.style) {
                    case Style::House:
                    case Style::Techno: {
                        bool kickHere = step % 4 == 0;
                        if (b.kickOneThree) kickHere = step == 0 || step == 8;
                        if (b.kickOnlyOne) kickHere = step == 0;
                        if (b.kick && kickHere) hit(d.kit.kick, 0.9f);
                        if (b.clap && (step == 4 || step == 12)) hit(d.kit.clap, 0.45f);
                        if (b.hats && step % 4 == 2) hit(d.kit.hat, 0.16f);
                        if (b.hats && step % 2 == 1) hit(d.kit.hat, 0.06f);
                        if (b.ohat && step % 4 == 2) hit(d.kit.ohat, 0.28f);
                        if (b.bass && step % 4 == 2)
                            tone(out, t, ibi * (d.style == Style::Techno ? 0.2 : 0.4), root, 0.32f * G, d.style == Style::House);
                        if (b.bass && d.style == Style::Techno && step % 4 == 3) tone(out, t, ibi * 0.2, root, 0.22f * G, false);
                        break;
                    }
                    case Style::Minimal:
                        if (b.kick && step % 4 == 0) hit(d.kit.kick, 0.9f);
                        if (b.hats) hit(d.kit.hat, step % 2 == 0 ? 0.08f : 0.04f);
                        break;
                    case Style::DnB: {
                        bool kickHere = b.halftime ? step == 0 : (step == 0 || step == 10);
                        bool snareHere = b.halftime ? step == 8 : (step == 4 || step == 12);
                        if (b.kick && kickHere) hit(d.kit.kick, 0.9f);
                        if (b.clap && snareHere) hit(d.kit.snare, 0.6f);
                        if (b.hats) hit(d.kit.hat, step % 2 == 0 ? 0.1f : 0.05f);
                        if (b.bass && (step == 0 || step == 10)) tone(out, t, ibi * (step == 0 ? 1.8 : 1.4), root, 0.35f * G, false);
                        break;
                    }
                    case Style::Jungle: {
                        bool odd = bar % 2 == 1;
                        bool kickHere = odd ? (step == 2 || step == 10 || step == 11) : (step == 0 || step == 10);
                        if (b.kick && kickHere) hit(d.kit.kick, 0.85f);
                        if (b.clap && (step == 4 || step == 12)) hit(d.kit.snare, 0.6f);
                        bool ghost = odd ? (step == 6 || step == 14) : (step == 7 || step == 9 || step == 15);
                        if (b.clap && ghost) hit(d.kit.snare, 0.12f + 0.06f * rng.uni());
                        if (b.hats && step % 2 == 0) hit(d.kit.ride, 0.1f);
                        if (b.bass && step == 0) tone(out, t, ibi * 3.5, root, 0.35f * G, false);
                        break;
                    }
                    case Style::Breaks: {
                        bool kickHere = b.kickOnlyOne ? step == 0 : (step == 0 || step == 6 || step == 10);
                        if (b.kick && kickHere) hit(d.kit.kick, 0.9f);
                        if (b.clap && (step == 4 || step == 12)) hit(d.kit.snare, 0.6f);
                        if (b.hats && step % 2 == 0) hit(d.kit.hat, step % 4 == 2 ? 0.14f : 0.09f);
                        if (b.ohat && step == 14) hit(d.kit.ohat, 0.2f);
                        if (b.bass && (step == 0 || step == 6)) tone(out, t, ibi * 1.2, root, 0.32f * G, true);
                        break;
                    }
                }
                if (step == 0 && b.crash) hit(d.kit.crash, 0.28f);
                if (step == 0 && b.pad && bar % 2 == 0)
                    for (double m : {1.0, 1.26, 1.5}) tone(out, t, ibi * 8, root * 4 * m, 0.07f * G, false);
            }
        }
    }
}

void truthFromGrid(const Grid& g, int barFrom, int barTo, Annotation& a) {
    for (int bar = barFrom; bar < barTo; bar++)
        for (int k = 0; k < 4; k++) {
            int i = bar * 4 + k - g.first;
            if (i >= 0 && i < int(g.beats.size())) a.beats.push_back({g.beats[i], k + 1});
        }
}

void finish(Scenario& sc) {
    float p = 0;
    for (float v : sc.audio) p = std::max(p, std::fabs(v));
    if (p > 0) for (float& v : sc.audio) v *= 0.8f / p;
    std::sort(sc.truth.beats.begin(), sc.truth.beats.end(), [](auto& a, auto& b) { return a.t < b.t; });
}

const double kRootsA[4] = {55.0, 55.0, 43.65, 49.0}, kRootsB[4] = {73.42, 65.41, 58.27, 65.41},
             kRootsC[4] = {61.74, 61.74, 46.25, 55.0}, kRootsD[4] = {41.2, 49.0, 36.71, 43.65};

Deck deck(Style s, int variant, const double* roots, Rng& r) {
    Deck d{s, Kit::make(variant, r), {}};
    std::copy(roots, roots + 4, d.roots);
    return d;
}

std::vector<float> buffer(double seconds) { return std::vector<float>(size_t(seconds * SR), 0.0f); }

// ---- scenarios ----

Scenario houseMix(Rng& r) {
    Scenario sc{"house-mix", {}, {}, {}, {"trackstart", "breakdown", "ramp", "blend", "cut"}};
    sc.truth.genre = "fourfour";
    Grid g;
    g.appendFrom(0.5, 48 * 4, 126, 126);
    double t = g.beats.back() + 60.0 / 126;
    g.appendFrom(t, 8 * 4, 126, 128);
    t = g.beats.back() + 60.0 / 128;
    g.appendFrom(t, 40 * 4, 128, 128);
    double cut = g.end() + 0.3 * 60.0 / 128;
    Grid c;
    c.appendFrom(cut, 32 * 4, 122, 122);
    sc.audio = buffer(c.end() + 2);
    Deck A = deck(Style::House, 0, kRootsA, r), B = deck(Style::House, 1, kRootsB, r), C = deck(Style::House, 2, kRootsC, r);
    renderDeck(sc.audio, A, g, 0, 72, [&](int bar) {
        BarSpec b;
        bool bd = bar >= 16 && bar < 32, build = bar >= 24 && bar < 32;
        b.kick = !bd; b.clap = !bd || build; b.ohat = !bd || build; b.bass = !bd && bar < 64; b.pad = bd;
        b.crash = !bd && bar % 8 == 0;
        b.gain = bar < 56 ? 1.0f : float(1.0 - (bar - 56) / 16.0);
        return b;
    }, r);
    renderDeck(sc.audio, B, g, 56, 96, [&](int bar) {
        BarSpec b;
        b.bass = bar >= 64; b.crash = bar % 8 == 0;
        b.gain = bar >= 64 ? 1.0f : float((bar - 56 + 1) / 8.0);
        return b;
    }, r);
    renderDeck(sc.audio, C, c, 0, 32, [&](int bar) { BarSpec b; b.crash = bar % 8 == 0; return b; }, r);
    truthFromGrid(g, 0, 96, sc.truth);
    truthFromGrid(c, 0, 32, sc.truth);
    sc.truth.regions = {{0.5, 30.5, "trackstart"}, {g.barTime(16), g.barTime(32), "breakdown"},
                        {g.barTime(48), g.barTime(56), "ramp"}, {g.barTime(56), g.barTime(72), "blend"},
                        {g.barTime(63), g.barTime(65), "swap"}, {cut, cut + 10, "cut"}};
    finish(sc);
    return sc;
}

Scenario loopOffOne(Rng& r) {
    Scenario sc{"loop-off-one", {}, {}, {}, {"trackstart", "loop-off-one"}};
    sc.truth.genre = "fourfour";
    Grid g;
    g.first = 2; // the audio starts on beat 3
    g.appendFrom(0.5, 48 * 4 - 2, 128, 128);
    sc.audio = buffer(g.end() + 1);
    Deck A = deck(Style::House, 1, kRootsC, r);
    renderDeck(sc.audio, A, g, 0, 48, [&](int bar) {
        BarSpec b;
        b.clap = bar >= 16; b.ohat = bar >= 16; b.crash = bar >= 16 && bar % 8 == 0;
        return b;
    }, r);
    truthFromGrid(g, 0, 48, sc.truth);
    sc.truth.regions = {{0.5, 30.5, "trackstart"}};
    finish(sc);
    return sc;
}

Scenario minimal(Rng& r) {
    Scenario sc{"minimal", {}, {}, {}, {"minimal", "trackstart"}};
    sc.truth.genre = "fourfour";
    Grid g;
    g.appendFrom(0.5, 48 * 4, 126, 126);
    sc.audio = buffer(g.end() + 1);
    Deck A = deck(Style::Minimal, 0, kRootsA, r);
    renderDeck(sc.audio, A, g, 0, 48, [](int) { return BarSpec{}; }, r);
    truthFromGrid(g, 0, 48, sc.truth);
    sc.truth.regions = {{0.5, 30.5, "trackstart"}};
    finish(sc);
    return sc;
}

Scenario halfTimeBreak(Rng& r) {
    Scenario sc{"half-time-break", {}, {}, {}, {"halftime"}};
    sc.truth.genre = "fourfour";
    Grid g;
    g.appendFrom(0.5, 40 * 4, 124, 124);
    sc.audio = buffer(g.end() + 1);
    Deck A = deck(Style::House, 2, kRootsB, r);
    renderDeck(sc.audio, A, g, 0, 40, [](int bar) {
        BarSpec b; b.kickOneThree = bar >= 16 && bar < 24; b.crash = bar % 8 == 0; return b;
    }, r);
    truthFromGrid(g, 0, 40, sc.truth);
    sc.truth.regions = {{g.barTime(16), g.barTime(24), "halftime"}};
    finish(sc);
    return sc;
}

Scenario spinback(Rng& r) {
    Scenario sc{"spinback", {}, {}, {}, {"cut"}};
    sc.truth.genre = "fourfour";
    Grid a;
    a.appendFrom(0.5, 24 * 4, 125, 125);
    double spin = a.end(), beat = 60.0 / 125;
    double bStart = spin + 2 * beat + 1.5;
    Grid b;
    b.appendFrom(bStart, 24 * 4, 124, 124);
    sc.audio = buffer(b.end() + 1);
    Deck A = deck(Style::House, 0, kRootsA, r), B = deck(Style::House, 1, kRootsD, r);
    renderDeck(sc.audio, A, a, 0, 24, [](int bar) { BarSpec s; s.crash = bar % 8 == 0; return s; }, r);
    // Spinback: the last beat played backwards, speeding up, fading out over 2 beats.
    long s0 = lround((spin - beat) * SR), s1 = lround(spin * SR), n = lround(2 * beat * SR);
    double pos = double(s1 - 1);
    for (long i = 0; i < n; i++) {
        double speed = 1.0 + 2.0 * i / n;
        pos -= speed;
        if (pos < s0) pos += double(s1 - s0);
        long j = s1 + i;
        if (j < long(sc.audio.size())) sc.audio[j] += sc.audio[long(pos)] * float(1.0 - double(i) / n);
    }
    renderDeck(sc.audio, B, b, 0, 24, [](int bar) { BarSpec s; s.crash = bar % 8 == 0; return s; }, r);
    truthFromGrid(a, 0, 24, sc.truth);
    truthFromGrid(b, 0, 24, sc.truth);
    sc.truth.regions = {{spin, bStart, "nobeat"}, {bStart, bStart + 10, "cut"}};
    finish(sc);
    return sc;
}

Scenario silenceGap(Rng& r) {
    Scenario sc{"silence-gap", {}, {}, {}, {"cut"}};
    sc.truth.genre = "fourfour";
    Grid a;
    a.appendFrom(0.5, 20 * 4, 126, 126);
    double stop = a.end(), resume = stop + 5.0;
    Grid b;
    b.appendFrom(resume, 20 * 4, 126, 126);
    sc.audio = buffer(b.end() + 1);
    Deck A = deck(Style::House, 0, kRootsA, r);
    renderDeck(sc.audio, A, a, 0, 20, [](int bar) { BarSpec s; s.crash = bar % 8 == 0; return s; }, r);
    renderDeck(sc.audio, A, b, 0, 20, [](int bar) { BarSpec s; s.crash = bar % 8 == 0; return s; }, r);
    truthFromGrid(a, 0, 20, sc.truth);
    truthFromGrid(b, 0, 20, sc.truth);
    sc.truth.regions = {{stop, resume, "nobeat"}, {resume, resume + 10, "cut"}};
    finish(sc);
    return sc;
}

Scenario techno140(Rng& r) {
    Scenario sc{"techno-140", {}, {}, {}, {"trackstart", "breakdown"}};
    sc.truth.genre = "fourfour";
    Grid g;
    g.appendFrom(0.5, 48 * 4, 140, 140);
    sc.audio = buffer(g.end() + 1);
    Deck A = deck(Style::Techno, 2, kRootsD, r);
    renderDeck(sc.audio, A, g, 0, 48, [](int bar) {
        BarSpec b; bool bd = bar >= 24 && bar < 32;
        b.kick = !bd; b.bass = !bd; b.pad = bd; b.clap = !bd; b.crash = !bd && bar % 8 == 0; return b;
    }, r);
    truthFromGrid(g, 0, 48, sc.truth);
    sc.truth.regions = {{0.5, 30.5, "trackstart"}, {g.barTime(24), g.barTime(32), "breakdown"}};
    finish(sc);
    return sc;
}

Scenario dnb174(Rng& r) {
    Scenario sc{"dnb-174", {}, {}, {}, {"trackstart", "breakdown", "intro"}};
    sc.truth.genre = "dnb";
    Grid g;
    g.appendFrom(0.5, 72 * 4, 174, 174);
    sc.audio = buffer(g.end() + 1);
    Deck A = deck(Style::DnB, 1, kRootsD, r);
    renderDeck(sc.audio, A, g, 0, 72, [](int bar) {
        BarSpec b;
        bool intro = bar < 8, bd = bar >= 40 && bar < 56;
        b.kick = !intro && !bd; b.clap = !intro && !bd; b.bass = !intro && !bd; b.pad = bd;
        b.crash = (bar == 8 || bar == 56) || (!intro && !bd && bar % 8 == 0);
        return b;
    }, r);
    truthFromGrid(g, 0, 72, sc.truth);
    sc.truth.regions = {{0.5, g.barTime(8), "intro"}, {g.barTime(8), g.barTime(8) + 30, "trackstart"},
                        {g.barTime(40), g.barTime(56), "breakdown"}};
    finish(sc);
    return sc;
}

Scenario dnbBlend(Rng& r) {
    Scenario sc{"dnb-blend", {}, {}, {}, {"blend", "ramp", "halftime"}};
    sc.truth.genre = "dnb";
    Grid g;
    g.appendFrom(0.5, 64 * 4, 172, 172);
    double t = g.beats.back() + 60.0 / 172;
    g.appendFrom(t, 8 * 4, 172, 174);
    t = g.beats.back() + 60.0 / 174;
    g.appendFrom(t, 24 * 4, 174, 174);
    sc.audio = buffer(g.end() + 1);
    Deck A = deck(Style::DnB, 0, kRootsA, r), B = deck(Style::DnB, 2, kRootsC, r);
    renderDeck(sc.audio, A, g, 0, 64, [](int bar) {
        BarSpec b; b.bass = bar < 48; b.crash = bar % 8 == 0;
        b.gain = bar < 32 ? 1.0f : float(1.0 - (bar - 32) / 32.0); return b;
    }, r);
    renderDeck(sc.audio, B, g, 32, 96, [](int bar) {
        BarSpec b; b.bass = bar >= 48; b.halftime = bar >= 72 && bar < 80; b.crash = bar % 8 == 0;
        b.gain = bar >= 40 ? 1.0f : float((bar - 32 + 1) / 8.0); return b;
    }, r);
    truthFromGrid(g, 0, 96, sc.truth);
    sc.truth.regions = {{g.barTime(32), g.barTime(64), "blend"}, {g.barTime(47), g.barTime(49), "swap"},
                        {g.barTime(64), g.barTime(72), "ramp"}, {g.barTime(72), g.barTime(80), "halftime"}};
    finish(sc);
    return sc;
}

Scenario jungle170(Rng& r) {
    Scenario sc{"jungle-170", {}, {}, {}, {"trackstart"}};
    sc.truth.genre = "dnb";
    Grid g;
    g.appendFrom(0.5, 48 * 4, 170, 170);
    sc.audio = buffer(g.end() + 1);
    Deck A = deck(Style::Jungle, 0, kRootsB, r);
    renderDeck(sc.audio, A, g, 0, 48, [](int bar) { BarSpec b; b.crash = bar % 8 == 0; return b; }, r);
    truthFromGrid(g, 0, 48, sc.truth);
    sc.truth.regions = {{0.5, 30.5, "trackstart"}};
    finish(sc);
    return sc;
}

Scenario breaks132(Rng& r) {
    Scenario sc{"breaks-132", {}, {}, {}, {"trackstart", "cut"}};
    sc.truth.genre = "breaks";
    Grid g;
    g.appendFrom(0.5, 56 * 4, 132, 132);
    double cut = g.end() + 0.4 * 60.0 / 132;
    Grid c;
    c.appendFrom(cut, 24 * 4, 128, 128);
    sc.audio = buffer(c.end() + 1);
    Deck A = deck(Style::Breaks, 1, kRootsC, r), C = deck(Style::House, 0, kRootsA, r);
    renderDeck(sc.audio, A, g, 0, 56, [](int bar) {
        BarSpec b; b.kickOnlyOne = bar >= 32 && bar < 48; b.crash = bar % 8 == 0; return b;
    }, r);
    renderDeck(sc.audio, C, c, 0, 24, [](int bar) { BarSpec b; b.crash = bar % 8 == 0; return b; }, r);
    truthFromGrid(g, 0, 56, sc.truth);
    truthFromGrid(c, 0, 24, sc.truth);
    sc.truth.regions = {{0.5, 30.5, "trackstart"}, {cut, cut + 10, "cut"}};
    finish(sc);
    return sc;
}

} // namespace

std::vector<std::string> scenarioNames() {
    return {"house-mix", "loop-off-one", "minimal", "half-time-break", "spinback", "silence-gap", "techno-140",
            "dnb-174", "dnb-blend", "jungle-170", "breaks-132", "peer-edit"};
}

Scenario makeScenario(const std::string& name, uint32_t seed) {
    Rng r(seed);
    if (name == "house-mix") return houseMix(r);
    if (name == "loop-off-one") return loopOffOne(r);
    if (name == "minimal") return minimal(r);
    if (name == "half-time-break") return halfTimeBreak(r);
    if (name == "spinback") return spinback(r);
    if (name == "silence-gap") return silenceGap(r);
    if (name == "techno-140") return techno140(r);
    if (name == "dnb-174") return dnb174(r);
    if (name == "dnb-blend") return dnbBlend(r);
    if (name == "jungle-170") return jungle170(r);
    if (name == "breaks-132") return breaks132(r);
    if (name == "peer-edit") {
        Scenario sc = houseMix(r);
        sc.name = "peer-edit";
        sc.tags = {"peer-edit"};
        // Someone types 120 BPM in Resolume at 60 s, and shifts its phase by 0.4 beat at 120 s.
        sc.linkEdits = {{LinkSimEdit::Tempo, 60'000'000, 120.0}, {LinkSimEdit::Phase, 120'000'000, 0.4}};
        return sc;
    }
    return Scenario{};
}

std::vector<float> resampleLinear(const std::vector<float>& in, double ratio) {
    std::vector<float> out(size_t(in.size() * ratio));
    for (size_t i = 0; i < out.size(); i++) {
        double x = i / ratio;
        size_t k = size_t(x);
        double f = x - k;
        float a = in[std::min(k, in.size() - 1)], b = in[std::min(k + 1, in.size() - 1)];
        out[i] = float(a + (b - a) * f);
    }
    return out;
}
