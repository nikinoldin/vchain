// SPDX-License-Identifier: GPL-3.0-or-later
#include "trigger_bands.h"
#include <algorithm>
#include <cmath>

namespace {
// BandOnsets: DrumOnsets' constants, but decided 3 sub-hops (~8 ms) late instead of 24 ms: these drive visuals.
constexpr int kLook = 3;               // a peak is the max of ±3 sub-hops
constexpr int kLate = kLook;
constexpr int kMask = 2;               // bands within ±2 sub-hops (~5 ms) hit at the same moment
constexpr float kMaskShare = 0.15f;    // ...and a hit whose jump is under 15 % of the biggest one then is dropped,
constexpr float kMaskMaxStrength = 0.3f; // unless it's a real sound in its own band: ≥ 30 % of the band's recent strong
                                       // hits. Real music: a kick over a bassline jumps little against the low band's
                                       // busy 4 s mean while a mid band jumps a lot; masking it lost ~6 % of the beats
constexpr float kEnergyAlpha = 1.0f / 1500; // ~4 s mean energy (a band's usual level)
// A click (a kick's beater, a pop) is gone within a few ms; anything worth a visual still sounds ~8-16 ms later.
constexpr float kMinTail = 0.1f;       // BandOnsets: energy 3 sub-hops (~8 ms) after the hit, relative to its peak
constexpr float kSpill = 4.0f;         // a touching neighbour 6 dB louder at the same moment
constexpr float kMinHatTail = 0.05f;   // instruments: DrumOnsets' hat tail (~16 ms)
constexpr float kMinSnareTail = 0.04f; // instruments: DrumOnsets' snare/clap tail (16-21 ms): a kick's click is ≈ 0
constexpr float kMinRiseDb = 4.0f;
// Below 100 Hz a hit builds up over 20-30 ms (a few periods of the wave), so its rise is measured against the energy
// ~24 ms earlier: against the previous window only, a hit over a loud low hum (a techno rumble) rises just 2-3 dB.
constexpr int kSlowRiseLag = 9;
constexpr float kDevK = 2.0f;
constexpr float kAlpha = 1.0f / 375;   // ~1 s running statistics
constexpr float kRelStrength = 0.05f;  // instruments: a hat must reach 5 % of the recent strong hats (quiet hats under a snare)
constexpr float kBandRelStrength = 0.1f; // BandOnsets: a hit must reach 10 % of the band's recent strong hits. Real music:
                                       // 5 % let through ghost hits (≈ 13 % off the 16th grid vs 7 % for strong hits)
constexpr float kPeakDecay = 0.99967f; // ~8 s
// Confirmed small rises: under a continuous sound (a sub-bass, a rumble) a hit adds only 2-3 dB to its band, under the
// minimum above. Such a rise (still a local max, >= 2 dB over the band's mean rise) counts when another band has a clear
// hit (>= half its recent strong hits) at the same moment, and only within 1 s of other bands' hits (not a lone bass
// note in a drumless break). A higher band's hit may come up to ~40 ms earlier: an attack shows in the higher bands
// first, the low bands' longer energy windows peak later (a kick's 200-600 Hz punch ~35 ms before its 50-200 Hz rise).
constexpr float kSmallRiseDb = 2.0f;
constexpr float kConfirmStrength = 0.5f;
constexpr int kConfirmEarlier = 15;    // sub-hops (~40 ms) a higher band's confirming hit may lead
constexpr float kActivityMs = 1000;

// TriggerEnvelope
constexpr float kDefaultBpm = 120.0f;
constexpr float kHoldSeconds = 0.03f;  // follow mode: the hit's level is its peak over its first 30 ms
constexpr float kFollowRangeDb = 24.0f; // follow mode: 24 dB under the hit's peak = zero
} // namespace

// --- Band ranges ---

void triggerBandEdges(int count, float* lo, float* hi) {
    // Three frequency zones based on drum/instrument characteristics
    constexpr float kZoneFreqs[4] = {50.0f, 200.0f, 2000.0f, 16000.0f};

    // How many bands per zone for each total band count (2-8)
    static const int dist[7][3] = {
        {1, 0, 1}, // 2 bands: low + high
        {1, 1, 1}, // 3: low + mid + high
        {1, 2, 1}, // 4: low + 2×mid + high
        {1, 2, 2}, // 5: low + 2×mid + 2×high
        {2, 2, 2}, // 6: 2×low + 2×mid + 2×high
        {2, 3, 2}, // 7: 2×low + 3×mid + 2×high
        {2, 3, 3}, // 8: 2×low + 3×mid + 3×high
    };

    int idx = std::clamp(count, 2, 8) - 2;
    int ci = 0;
    for (int z = 0; z < 3; z++) {
        int n = dist[idx][z];
        float logLo = std::log2(kZoneFreqs[z]);
        float logHi = std::log2(kZoneFreqs[z + 1]);
        for (int i = 0; i < n && ci < count; i++) {
            float t0 = static_cast<float>(i) / static_cast<float>(n);
            float t1 = static_cast<float>(i + 1) / static_cast<float>(n);
            lo[ci] = std::exp2(logLo + t0 * (logHi - logLo));
            hi[ci] = std::exp2(logLo + t1 * (logHi - logLo));
            ci++;
        }
    }
}

// --- BandOnsets ---

void BandOnsets::reset(uint32_t sampleRate, int count, const float* lo, const float* hi) {
    mSr = sampleRate;
    mSubLen = std::max<uint32_t>(32, uint32_t(std::lround(sampleRate / 375.0)));
    mFill = 0;
    mSubIndex = 0;
    mCount = std::clamp(count, 0, kTriggerMaxBands);
    for (int i = 0; i < mCount; i++) {
        Band& b = mBand[i];
        b = Band{};
        // Two high-passes and two low-passes: 24 dB/octave skirts, so neighbouring bands leak less.
        b.f[b.filters++].set(BiquadType::HighPass, lo[i], 0.707, mSr);
        b.f[b.filters++].set(BiquadType::HighPass, lo[i], 0.707, mSr);
        if (hi[i] < 0.45 * mSr) {
            b.f[b.filters++].set(BiquadType::LowPass, hi[i], 0.707, mSr);
            b.f[b.filters++].set(BiquadType::LowPass, hi[i], 0.707, mSr);
        }
        b.touches = i > 0 && std::fabs(lo[i] - hi[i - 1]) < 1.0f; // shares its lower edge with the band below
        b.window = lo[i] < 100 ? 4 : lo[i] < 400 ? 2 : 1;
        b.riseLag = lo[i] < 100 ? kSlowRiseLag : std::max(2, b.window);
        b.refractoryMs = lo[i] < 150 ? 80 : lo[i] < 1000 ? 50 : 40;
    }
}

float BandOnsets::energy(int band) const {
    if (band < 0 || band >= mCount || mSubIndex == 0) return 0;
    return mBand[band].energy[(mSubIndex - 1) % kRing];
}

int BandOnsets::process(const float* x, uint32_t n, BandHit* out, int maxOut) {
    int count = 0;
    for (uint32_t i = 0; i < n; i++) {
        for (int bi = 0; bi < mCount; bi++) {
            Band& b = mBand[bi];
            float y = x[i];
            for (int f = 0; f < b.filters; f++) y = b.f[f].run(y);
            b.acc += double(y) * y;
        }
        if (++mFill == mSubLen) {
            endSubHop(out, maxOut, count);
            mFill = 0;
        }
    }
    return count;
}

void BandOnsets::endSubHop(BandHit* out, int maxOut, int& count) {
    const int64_t k = mSubIndex++;
    const int cur = int(k % kRing);
    const double subMs = mSubLen * 1000.0 / mSr;
    const int64_t c = k - kLate; // the sub-hop being decided
    for (int bi = 0; bi < mCount; bi++) {
        Band& b = mBand[bi];
        b.raw[cur] = float(b.acc / mSubLen);
        b.acc = 0;
        float e = 1e-12f;
        for (int d = 0; d < b.window; d++) e += b.raw[(k - d + 2 * kRing) % kRing] / b.window;
        float prev = b.energy[(k + kRing - b.riseLag) % kRing] + 1e-12f;
        b.energy[cur] = e;
        float rise = k >= b.riseLag ? std::max(0.0f, 10.0f * std::log10(e / prev)) : 0.0f;
        b.rise[cur] = rise;
        b.meanRise += kAlpha * (rise - b.meanRise);
        b.devRise += kAlpha * (std::fabs(rise - b.meanRise) - b.devRise);
        b.meanEnergy += kEnergyAlpha * (e - b.meanEnergy);
        b.peakStrength *= kPeakDecay;
        if (k < kLate + kLook + 2) continue;

        const int ci = int(c % kRing);
        float r = b.rise[ci];
        const bool small = r < b.meanRise + kDevK * b.devRise + kMinRiseDb; // only with confirmation, see below
        if (small && r < b.meanRise + kSmallRiseDb) continue;
        bool isMax = true;
        for (int d = -kLook; d <= kLook && isMax; d++)
            if (d != 0) {
                float o = b.rise[(c + d + kRing) % kRing];
                isMax = d < 0 ? r > o : r >= o;
            }
        if (!isMax) continue;
        if ((c - b.lastOnsetSub) * subMs < b.refractoryMs) continue;
        float level = 0;
        for (int d = 0; d <= kLate; d++) level = std::max(level, b.energy[(c + d) % kRing]);
        if (level < kBandRelStrength * b.peakStrength) continue;
        float before = b.energy[(c - b.riseLag + 2 * kRing) % kRing];
        if (b.energy[cur] - before < kMinTail * (level - before)) continue; // a click
        b.pending = true;
        b.small = small;
        b.candSub = c;
        b.candLevel = level;
        b.candJump = std::max(0.0f, level - before) / std::max(b.meanEnergy, 1e-9f);
        b.candStrength = level / std::max(b.peakStrength, level);
        if (small) continue; // takes its refractory gap and strength once confirmed
        b.peakStrength = std::max(b.peakStrength, level);
        b.lastOnsetSub = c;
    }
    // A candidate waits kMask sub-hops so a band hitting just after it is known too.
    for (int bi = 0; bi < mCount; bi++) {
        Band& b = mBand[bi];
        if (!b.pending || c - b.candSub < kMask) continue;
        b.pending = false;
        float biggest = 0;
        for (int j = 0; j < mCount; j++)
            if (!mBand[j].small && std::llabs(mBand[j].candSub - b.candSub) <= kMask) biggest = std::max(biggest, mBand[j].candJump);
        // A touching neighbour 6 dB+ louder at the same moment, or louder with a jump 4× bigger (each against its
        // band's usual level): the same sound spilling over (a kick's body over two low bands, a clap over two mid
        // bands).
        bool spill = false;
        for (int j : {bi - 1, bi + 1}) {
            if (j < 0 || j >= mCount || mBand[j].small || !(j < bi ? b.touches : mBand[j].touches)) continue;
            const Band& n = mBand[j];
            spill |= std::llabs(n.candSub - b.candSub) <= kMask
                  && (n.candLevel >= kSpill * b.candLevel || (n.candLevel >= b.candLevel && n.candJump >= kSpill * b.candJump));
        }
        // Masking drops only weak hits: a strong hit in its own band stays (a kick over a busy bassline).
        bool masked = b.candJump < kMaskShare * biggest && b.candStrength < kMaskMaxStrength;
        if (spill || masked) continue;
        if (b.small) {
            // Confirmed by another band's clear hit (not itself a small one) at the same moment, or a higher band's
            // up to kConfirmEarlier sooner; spill from a touching neighbour was already dropped above.
            bool confirmed = false, active = false;
            for (int j = 0; j < mCount; j++) {
                const Band& o = mBand[j];
                if (j == bi) continue;
                active |= o.lastHitSub < b.candSub - kMask && (b.candSub - o.lastHitSub) * subMs <= kActivityMs;
                const int64_t lead = b.candSub - o.candSub;
                confirmed |= !o.small && lead >= -kMask && lead <= (j > bi ? kConfirmEarlier : kMask)
                    && o.candStrength >= kConfirmStrength;
            }
            if (!confirmed || !active) continue;
            b.peakStrength = std::max(b.peakStrength, b.candLevel);
            b.lastOnsetSub = b.candSub;
        }
        b.lastHitSub = b.candSub;
        if (count < maxOut) out[count++] = BandHit{bi, b.candStrength};
    }
}

// --- TriggerEnvelope ---

void TriggerEnvelope::reset() {
    for (auto& b : mB) b = B{};
}

void TriggerEnvelope::hit(int band, float strength, float energy) {
    if (band < 0 || band >= kTriggerMaxBands) return;
    B& b = mB[band];
    b.s = b.v = std::clamp(strength, 0.0f, 1.0f);
    b.t = 0;
    b.level = energy;
}

void TriggerEnvelope::advance(float dt, float bpm, const float* energy, int count) {
    const float beat = 60.0f / (bpm > 20 ? bpm : kDefaultBpm);
    for (int i = 0; i < kTriggerMaxBands; i++) {
        B& b = mB[i];
        if (b.v <= 0) continue;
        b.t += dt;
        if (mBeats > 0) {
            float x = b.t / (mBeats * beat);
            b.v = x < 1 ? b.s * (1 - x) * (1 - x) : 0.0f;
            continue;
        }
        float e = i < count && energy ? energy[i] : 0.0f;
        if (b.t < kHoldSeconds) {
            b.level = std::max(b.level, e);
            continue;
        }
        float db = 10.0f * std::log10(std::max(e, 1e-12f) / std::max(b.level, 1e-12f));
        float target = b.s * std::clamp(1.0f + db / kFollowRangeDb, 0.0f, 1.0f);
        b.v = std::min(b.v, target);
        if (b.v < 0.01f) b.v = 0;
    }
}

// --- TriggerBands ---

void TriggerBands::reset(uint32_t sampleRate) {
    mSr = sampleRate;
    setBands(mCount, mLo, mHi);
}

void TriggerBands::setBands(int count, const float* lo, const float* hi) {
    mCount = std::clamp(count, 0, kTriggerMaxBands);
    for (int i = 0; i < mCount; i++) { mLo[i] = lo[i]; mHi[i] = hi[i]; }
    mT = 0;
    mDrums.reset(mSr);
    mDrums.setKeepLoudKicksUnderSnares(true);
    mDrums.setRumbleKicks(true);
    mDrums.setKicksNeedBody(true);
    mDrums.setSnareMinTail(kMinSnareTail);
    mDrums.setPitchSweep(true);
    mDrums.setHatMinStrength(kRelStrength);
    mBands.reset(mSr, instruments() ? 0 : mCount, mLo, mHi);
    mEnv.reset();
}

void TriggerBands::process(const float* x, uint32_t n, float bpm) {
    float energy[kTriggerMaxBands] = {};
    const float dt = float(n) / float(mSr);
    if (instruments()) {
        Onset hits[16];
        int nh = mDrums.process(x, n, mT, hits, 16);
        mT += int64_t(std::llround(n * 1e6 / mSr));
        // Kick follows the kick band, snare the noise band (claps have little body), hat the hat band.
        energy[0] = mDrums.energy(0);
        energy[1] = mDrums.energy(2);
        energy[2] = mDrums.energy(3);
        mEnv.advance(dt, bpm, energy, 3);
        for (int i = 0; i < nh; i++) {
            int band = hits[i].cls == OnsetClass::Kick ? 0 : hits[i].cls == OnsetClass::Snare ? 1
                     : hits[i].cls == OnsetClass::Hat && hits[i].tail >= kMinHatTail ? 2 : -1;
            if (band >= 0) mEnv.hit(band, hits[i].strength, energy[band]);
        }
        return;
    }
    BandHit hits[2 * kTriggerMaxBands];
    int nh = mBands.process(x, n, hits, 2 * kTriggerMaxBands);
    for (int i = 0; i < mCount; i++) energy[i] = mBands.energy(i);
    mEnv.advance(dt, bpm, energy, mCount);
    for (int i = 0; i < nh; i++) mEnv.hit(hits[i].band, hits[i].strength, energy[hits[i].band]);
}
