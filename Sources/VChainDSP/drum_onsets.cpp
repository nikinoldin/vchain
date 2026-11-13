// SPDX-License-Identifier: GPL-3.0-or-later
#include "drum_onsets.h"
#include <algorithm>
#include <cmath>

namespace {
constexpr int kRing = 32;
constexpr int kBack = 6;          // walk back up to 6 sub-hops (16 ms) to the start of the attack
constexpr float kRelStrength = 0.4f;  // a hit must reach 40 % of the band's recent strong hits (bass notes, ghosts out)
constexpr float kPeakDecay = 0.99967f; // ~8 s at 2.7 ms per sub-hop (a breakdown must not lower the bar)
constexpr float kEnergyAlpha = 1.0f / 1500; // ~4 s mean energy
constexpr int kLook = 3;          // peak must be the max of ±3 sub-hops
constexpr int kLate = 9;          // decide 9 sub-hops (~24 ms) late: a clap's later, louder bursts count for its level
constexpr int kTailSubs = 6;      // Onset::tail is measured 6 sub-hops (~16 ms) after the onset
constexpr int kSnareTailEnd = 8;  // setSnareMinTail: the best of sub-hops 6-8 (16-21 ms; a clap's bursts leave gaps)
constexpr float kMinRiseDb = 4.0f;
constexpr float kDevK = 2.0f;
// Trigger-only kick rules (setRumbleKicks / setKicksNeedBody): a rumble kick's minimum rise over the band's mean rise,
// and the body band's (150-400 Hz) minimum peak relative to its recent strong hits for a rumble kick / for any kick.
constexpr float kRumbleRiseDb = 2.0f;
constexpr float kRumbleBody = 0.75f;
constexpr float kKickBody = 0.45f;
// setKicksNeedBody: a kick with less body still passes when its pitch sweeps down. The beater's attack passes through
// 150-400 Hz first: the body band peaks >= 4 sub-hops (~11 ms) before the kick band, at >= 20 % of its recent strong
// hits, and is back under 20 % of that peak ~24 ms after the onset. An offbeat bass note holds its pitch: both bands
// rise together and the body rings on. The kick itself must be a real one: >= 60 % of the kick band's recent strong
// hits and >= 1.8 × (2.5 dB over) its ~4 s mean energy (a repeated offbeat tom-like bass note with a small drop
// passes the sweep test at ~1.3 dB over the mean; kicks are typically 6 dB over).
constexpr int kSweepBefore = 3; // the body band's peak is searched from 3 sub-hops before the kick onset
constexpr int kSweepLead = 4;
constexpr float kSweepBody = 0.2f;
constexpr float kSweepTail = 0.2f;
constexpr float kSweepLevel = 0.6f;
constexpr float kSweepOverMean = 1.8f;
// A rumble kick also needs a snare or hat onset within the last second: a sub-bass or reese in a breakdown or intro
// (no drums) otherwise reads as kicks.
constexpr float kRumbleDrumsMs = 1000;
// Pitch-swept kicks (setPitchSweep): the zero-crossing rate's minimum fall from the attack (sub-hops -3..0) to its
// tail (4..kLate), in octaves, and the weaker body and minimum level such a kick needs.
constexpr float kZcSweepOct = 0.5f;
constexpr float kZcSweepBody = 0.3f;
constexpr float kZcSweepLevel = 0.7f;
constexpr float kAlpha = 1.0f / 375; // ~1 s running statistics at ~2.7 ms per sub-hop
// Refractory gaps per band (ms): kick 80 (16th-note kicks up to ~185 BPM still pass), body, snare 50, hat 40.
constexpr float kRefractoryMs[DrumOnsets::kBands] = {80, 50, 50, 40};
// Energy window per band, in sub-hops: kick 4 (~11 ms), body 2, noise and hat 1.
constexpr int kWindow[DrumOnsets::kBands] = {4, 2, 1, 1};
} // namespace

void DrumOnsets::reset(uint32_t sampleRate) {
    mSr = sampleRate;
    mSubLen = std::max<uint32_t>(32, uint32_t(std::lround(sampleRate / 375.0)));
    mSubUs = mSubLen * 1e6 / mSr;
    mFill = 0;
    mSubIndex = 0;
    mLastSnareSub = -1;
    mLastDrumSub = -1;
    for (auto& b : mBand) b = Band{};
    for (int i = 0; i < kRing; i++) mZcCount[i] = mZcHalf[i] = 0;
    mZcN = mZcSum = 0; mPrevKickY = 0; mSample = 0; mLastZc = -1;
    constexpr BiquadType HP = BiquadType::HighPass, LP = BiquadType::LowPass;
    mBand[0].f[0].set(HP, 40, 0.707, mSr);   mBand[0].f[1].set(LP, 150, 0.707, mSr);
    mBand[1].f[0].set(HP, 150, 0.707, mSr);  mBand[1].f[1].set(LP, 400, 0.707, mSr);
    mBand[2].f[0].set(HP, 1000, 0.707, mSr); mBand[2].f[1].set(LP, 5000, 0.707, mSr);
    mBand[3].f[0].set(HP, 6000, 0.707, mSr); mBand[3].f[1].set(HP, 6000, 0.707, mSr);
}

float DrumOnsets::energy(int band) const {
    if (band < 0 || band >= kBands || mSubIndex == 0) return 0;
    return mBand[band].energy[(mSubIndex - 1) % kRing];
}

int DrumOnsets::process(const float* x, uint32_t n, int64_t t0, Onset* out, int maxOut) {
    int count = 0;
    for (uint32_t i = 0; i < n; i++) {
        if (mFill == 0) mSubStartT = t0 + int64_t(std::llround(i * 1e6 / mSr));
        for (int bi = 0; bi < kBands; bi++) {
            Band& b = mBand[bi];
            float y = b.f[1].run(b.f[0].run(x[i]));
            b.acc += double(y) * y;
            if (bi == 0 && mPitchSweep) {
                // Zero crossings of the kick band: their spacing is its dominant period (the kick's pitch).
                if ((y >= 0) != (mPrevKickY >= 0)) {
                    if (mLastZc >= 0) { mZcN += 1; mZcSum += float(mSample - mLastZc); }
                    mLastZc = mSample;
                }
                mPrevKickY = y;
                mSample++;
            }
        }
        if (++mFill == mSubLen) {
            endSubHop(mSubStartT, out, maxOut, count);
            mFill = 0;
        }
    }
    return count;
}

bool DrumOnsets::sweptKick(int64_t c, float level) const {
    auto E = [](const Band& b, int64_t s) { return b.energy[(s + 2 * kRing) % kRing]; };
    const Band& kick = mBand[0];
    const Band& body = mBand[1];
    if (level < kSweepLevel * kick.peakStrength || level < kSweepOverMean * kick.meanEnergy) return false;
    // The kick band is current up to c + kLate, the body band (updated after it) up to c + kLate - 1.
    int kickAt = 0, bodyAt = -kSweepBefore;
    float kickPeak = 0, bodyPeak = 0;
    for (int d = 0; d <= kLate; d++)
        if (E(kick, c + d) > kickPeak) { kickPeak = E(kick, c + d); kickAt = d; }
    for (int d = -kSweepBefore; d < kLate; d++)
        if (E(body, c + d) > bodyPeak) { bodyPeak = E(body, c + d); bodyAt = d; }
    return kickAt - bodyAt >= kSweepLead && bodyPeak >= kSweepBody * body.peakStrength &&
           E(body, c + kLate - 1) <= kSweepTail * bodyPeak;
}

void DrumOnsets::endSubHop(int64_t tSub, Onset* out, int maxOut, int& count) {
    const int64_t k = mSubIndex++;
    const int cur = int(k % kRing);
    mZcCount[cur] = mZcN; mZcHalf[cur] = mZcSum; mZcN = mZcSum = 0;
    float peakRise[kBands] = {}, peakEnergy[kBands] = {}, peakJump[kBands] = {};
    bool peak[kBands] = {};
    for (int bi = 0; bi < kBands; bi++) {
        Band& b = mBand[bi];
        // Energy over the band's window (low bands need ~11 ms: a 50 Hz kick ripples by several dB within 2.7 ms),
        // compared with the window before it.
        b.raw[cur] = float(b.acc / mSubLen);
        b.acc = 0;
        const int W = kWindow[bi];
        float e = 1e-12f;
        for (int d = 0; d < W; d++) e += b.raw[(k - d + 2 * kRing) % kRing] / W;
        float prev = b.energy[(k + kRing - std::max(2, W)) % kRing] + 1e-12f;
        b.energy[cur] = e;
        float rise = k >= 2 ? std::max(0.0f, 10.0f * std::log10(e / prev)) : 0.0f;
        b.rise[cur] = rise;
        b.jump[cur] = std::max(0.0f, e - prev) / std::max(b.meanEnergy, 1e-9f);
        // Running statistics of the rise and the energy.
        b.meanRise += kAlpha * (rise - b.meanRise);
        b.devRise += kAlpha * (std::fabs(rise - b.meanRise) - b.devRise);
        b.meanEnergy += kEnergyAlpha * (e - b.meanEnergy);
        // Candidate = the sub-hop kLate back, if it is the max of ±kLook and above threshold.
        b.peakStrength *= kPeakDecay;
        if (k < kLate + kLook + kBack + 2) continue;
        int c = int((k - kLate) % kRing);
        float r = b.rise[c];
        float thr = b.meanRise + kDevK * b.devRise + kMinRiseDb;
        // Rumble kick: a small kick-band rise that only counts with the body band's punch (checked below) and among drums.
        const bool rumble = r < thr && bi == 0 && mRumbleKicks && r >= b.meanRise + kRumbleRiseDb
            && mLastDrumSub >= 0 && (k - kLate - mLastDrumSub) * mSubUs <= kRumbleDrumsMs * 1000;
        if (r < thr && !rumble) continue;
        bool isMax = true;
        for (int d = -kLook; d <= kLook && isMax; d++)
            if (d != 0) {
                float o = b.rise[(k - kLate + d + kRing) % kRing];
                isMax = d < 0 ? r > o : r >= o;
            }
        if (!isMax) continue;
        if ((k - kLate - b.lastOnsetSub) * mSubUs < kRefractoryMs[bi] * 1000) continue;
        // Level = the hit's peak energy over the kLate sub-hops from the candidate on (a clap's later bursts count). A
        // hit must reach kRelStrength (hats: mHatMinStrength) of the band's recent strong hits: rejects bass notes under
        // a kick, hat leakage, pads in a breakdown.
        float level = 0;
        for (int d = 0; d <= kLate; d++) level = std::max(level, b.energy[(c + d) % kRing]);
        if (level < (bi == 3 ? mHatMinStrength : kRelStrength) * b.peakStrength) continue;
        if (bi == 0 && (rumble || mKicksNeedBody)) {
            // The body band's peak over the same span (its ring is updated after this band: current up to k - 1).
            const Band& body = mBand[1];
            float punch = 0;
            for (int d = 0; d < kLate; d++) punch = std::max(punch, body.energy[(c + d) % kRing]);
            bool ok = punch >= (rumble ? kRumbleBody : kKickBody) * body.peakStrength;
            // A kick whose attack passes through 150-400 Hz first (sweptKick), or a loud hit whose zero-crossing pitch
            // falls (sweepOctaves), is a kick even with little punch (clean, sub-heavy kicks).
            if (!ok && !rumble) ok = sweptKick(k - kLate, level);
            if (!ok && mPitchSweep && punch >= kZcSweepBody * body.peakStrength && level >= kZcSweepLevel * b.peakStrength)
                ok = sweepOctaves(c) >= kZcSweepOct;
            if (!ok) continue;
        }
        b.peakStrength = std::max(b.peakStrength, level);
        float jumpSum = level / b.peakStrength;
        peak[bi] = true;
        peakRise[bi] = r;
        peakEnergy[bi] = level;
        peakJump[bi] = jumpSum;
    }
    // Onset time: where the band's energy has risen 10 % of the way from the floor before the attack to the hit's
    // peak (walking back from the candidate). A pitch-swept kick enters 40-150 Hz gradually and a kick on the tail
    // of the previous one rises late, so the steepest rise is too late; multi-burst claps peak on a later burst.
    auto timeOf = [&](int bi) {
        const Band& b = mBand[bi];
        int c = int((k - kLate) % kRing);
        float floorE = b.energy[(c - kBack - 1 + 2 * kRing) % kRing];
        for (int d = 1; d <= kBack + 1; d++) floorE = std::min(floorE, b.energy[(c - d + 2 * kRing) % kRing]);
        float level = 0;
        for (int d = 0; d <= kLate; d++) level = std::max(level, b.energy[(c + d) % kRing]);
        float thr = floorE + 0.1f * (level - floorE);
        int back = 0;
        while (back < kBack && b.energy[(c - back - 1 + 2 * kRing) % kRing] > thr) back++;
        // Within the first sub-hop above the threshold: interpolate where the energy crossed it.
        float e1 = b.energy[(c - back + 2 * kRing) % kRing], e0 = b.energy[(c - back - 1 + 2 * kRing) % kRing];
        float frac = e1 > e0 ? std::clamp((e1 - thr) / (e1 - e0), 0.0f, 1.0f) : 0.0f;
        // Energy of a sub-hop belongs to its centre; the crossing is `frac` of a sub-hop before that centre.
        // A W-sub-hop window centres (W - 1) / 2 sub-hops before its last sub-hop.
        return tSub - int64_t(std::llround((kLate + back + frac - 0.5 + (kWindow[bi] - 1) * 0.5) * mSubUs));
    };
    auto tailOf = [&](int bi, int last = kTailSubs) {
        const Band& b = mBand[bi];
        int c = int((k - kLate) % kRing);
        float level = 0;
        for (int d = 0; d <= kLate; d++) level = std::max(level, b.energy[(c + d) % kRing]);
        // Above the energy already there (a ringing open hat must not make a click look sustained).
        float before = b.energy[(c - 2 + kRing) % kRing];
        float after = 0;
        for (int d = kTailSubs; d <= last; d++) after = std::max(after, b.energy[(c + d) % kRing]);
        return std::max(0.0f, after - before) / std::max(level - before, 1e-12f);
    };
    auto emit = [&](int bi, OnsetClass cls, float strength) {
        mBand[bi].lastOnsetSub = k - kLate;
        if (count < maxOut) out[count++] = Onset{timeOf(bi), cls, strength, tailOf(bi)};
    };
    // A kick-band onset shortly after a snare is the snare's body, not a kick.
    bool afterSnare = mLastSnareSub >= 0 && (k - kLate - mLastSnareSub) * mSubUs >= 8000 && (k - kLate - mLastSnareSub) * mSubUs <= 60000;
    if (peak[0] && (!afterSnare || (mKeepLoudKicks && peakJump[0] >= 0.7f)))
        emit(0, OnsetClass::Kick, peakJump[0]);
    // Snare/clap: a noise-band onset louder than the hat band, with a body onset or a big rise.
    bool body = peak[1] || mBand[1].rise[(k - kLate) % kRing] > 6.0f || mBand[1].rise[(k - kLate - 1 + kRing) % kRing] > 6.0f;
    const Band& hat = mBand[3];
    int c0 = int((k - kLate) % kRing);
    float hatLevel = 0;
    for (int d = 0; d <= 2; d++) hatLevel = std::max(hatLevel, hat.energy[(c0 + d) % kRing]);
    if (peak[2] && peakEnergy[2] >= 0.7f * hatLevel && (body || peakRise[2] >= 9.0f) &&
        (mSnareMinTail <= 0 || tailOf(2, kSnareTailEnd) >= mSnareMinTail)) {
        emit(2, OnsetClass::Snare, peakJump[2]);
        mLastSnareSub = k - kLate;
        mLastDrumSub = k - kLate;
        if (peak[3]) mBand[3].lastOnsetSub = k - kLate; // the same hit, not a hat
    } else if (peak[3]) {
        emit(3, OnsetClass::Hat, peakJump[3]);
        mLastDrumSub = k - kLate;
    }
    if (peak[1]) mBand[1].lastOnsetSub = k - kLate;
}

// How far the kick band's zero-crossing rate falls from the attack (sub-hops c-3..c) to its tail (c+4..c+kLate), in
// octaves; 0 if either span has no crossing. A kick sweeps down by about an octave, a bass note stays near 0.
float DrumOnsets::sweepOctaves(int c) const {
    float ne = 0, se = 0, nl = 0, sl = 0;
    for (int d = -3; d <= 0; d++) { int j = (c + d + kRing) % kRing; ne += mZcCount[j]; se += mZcHalf[j]; }
    for (int d = 4; d <= kLate; d++) { int j = (c + d) % kRing; nl += mZcCount[j]; sl += mZcHalf[j]; }
    if (ne <= 0 || nl <= 0) return 0;
    return std::log2((ne / se) / (nl / sl));
}
