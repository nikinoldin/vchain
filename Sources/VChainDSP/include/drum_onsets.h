// SPDX-License-Identifier: GPL-3.0-or-later
// Kick / snare / hat onsets with capture timestamps, for the beat grid (docs/beat-tracking.md, "DrumOnsets").
// Four band-passes (kick 40-150 Hz, snare body 150-400 Hz, snare/clap noise 1-5 kHz, hat > 6 kHz), energy per
// sub-hop (~2.7 ms), a log-energy rise per band, an adaptive threshold, local-max peak picking. Allocation-free.
#pragma once
#include "biquad.h"
#include <cstdint>

// Beat = a beat reported by the neural network front end (Beat This!), not a drum hit.
enum class OnsetClass : uint8_t { Kick = 0, Snare = 1, Hat = 2, Beat = 3 };

struct Onset {
    int64_t t;        // capture time of the onset, µs
    OnsetClass cls;
    float strength;   // peak energy relative to the band's recent strongest hits (0..1)
    float tail = 1;   // the band's energy ~16 ms after the onset over the hit's peak, both above the energy before: a click ≈ 0
};

class DrumOnsets {
public:
    void reset(uint32_t sampleRate);
    // A kick-band onset just after a snare counts as the snare's body and is dropped. With this on, a loud one
    // (>= 70 % of recent kicks) is kept: a kick landing with a clap (the MIDI strip's triggers; the beat grid keeps
    // the default).
    void setKeepLoudKicksUnderSnares(bool keep) { mKeepLoudKicks = keep; }
    // The hat band's minimum level relative to its recent strong hits (default 0.4, like the other bands). The
    // triggers lower it so quiet hats under a loud snare still count.
    void setHatMinStrength(float s) { mHatMinStrength = s; }
    // Rumble kicks: under a continuous sub-bass a kick adds only 2-3 dB to 40-150 Hz, under the 4 dB minimum rise.
    // With this on, a smaller kick-band rise (a local max >= 2 dB over the band's mean rise) still counts when the
    // body band (150-400 Hz) peaks at the same moment at >= 75 % of its recent strong hits (the kick's punch) and a
    // snare or hat onset came within the last second (no rumble kicks from a bassline in a drumless breakdown/intro).
    // Triggers only; the beat grid keeps the default.
    void setRumbleKicks(bool on) { mRumbleKicks = on; }
    // With this on, every kick needs the body band at >= 45 % of its recent strong hits within its ~24 ms: an offbeat
    // bass note rising out of a gap has no punch in 150-400 Hz. A strong kick with less body still passes when its pitch
    // sweeps down (150-400 Hz peaks >= ~11 ms before 40-150 Hz and is gone ~24 ms later; a bass note holds its pitch).
    // Triggers only.
    void setKicksNeedBody(bool on) { mKicksNeedBody = on; }
    // Snares/claps need a noise-band (1-5 kHz) tail of at least this (like Onset::tail, but the best of 16-21 ms
    // after the onset, as a clap's bursts leave gaps; 0 = off, the default). A kick's beater click is +20 dB in
    // 1-5 kHz for about one sub-hop and gone by then (tail ≈ 0), a snare or clap still rings. On the bench's 4/4
    // tracks it cut CC2 on beats 1/3 from 47 % to 19 %. Triggers only.
    void setSnareMinTail(float t) { mSnareMinTail = t; }
    // Pitch sweep: a kick sweeps down (~150 -> 50 Hz within ~30 ms), an offbeat bass note holds its pitch. With this
    // on, a kick-band hit whose zero-crossing rate falls by >= 0.5 octave from its attack to ~11-24 ms later counts
    // with a weaker body (>= 30 % instead of 45 %, or 75 % for a rumble kick) if it is loud (>= 70 % of recent kicks).
    // Triggers only.
    void setPitchSweep(bool on) { mPitchSweep = on; }
    // Processes n samples whose first sample was captured at t0 (µs). Writes at most maxOut onsets found in this
    // call (they lag the audio by a few sub-hops) and returns how many.
    int process(const float* x, uint32_t n, int64_t t0, Onset* out, int maxOut);

    static constexpr int kBands = 4; // kick, body, noise, hat
    // Latest windowed energy of a band (kick 0, body 1, noise 2, hat 3); the trigger envelope follows it.
    float energy(int band) const;

private:
    struct Band {
        Biquad<float> f[2];
        double acc = 0;                 // energy accumulator of the current sub-hop
        float raw[32] = {};             // ring of per-sub-hop energies (kRing)
        float energy[32] = {};          // ring of windowed energies
        float rise[32] = {};            // ring of log-energy rises (dB)
        float jump[32] = {};            // ring of energy jumps relative to the mean
        float meanRise = 0, devRise = 1, meanEnergy = 1e-6f;
        float peakStrength = 0;         // decaying max of recent hits' peak energy (~8 s)
        int64_t lastOnsetSub = -1000;
    };
    void endSubHop(int64_t tSub, Onset* out, int maxOut, int& count);
    // A strong kick (peak energy `level`) at sub-hop c whose pitch sweeps down through 150-400 Hz (setKicksNeedBody)
    bool sweptKick(int64_t c, float level) const;
    float sweepOctaves(int c) const;

    // Zero crossings of the kick band per sub-hop (rings of kRing): count and summed half-periods (samples).
    float mZcCount[32] = {}, mZcHalf[32] = {};
    float mZcN = 0, mZcSum = 0;  // current sub-hop
    float mPrevKickY = 0;
    int64_t mSample = 0, mLastZc = -1;

    double mSr = 48000;
    uint32_t mSubLen = 128;      // samples per sub-hop
    double mSubUs = 2666.7;      // µs per sub-hop
    uint32_t mFill = 0;          // samples in the current sub-hop
    int64_t mSubIndex = 0;       // sub-hops since reset
    int64_t mSubStartT = 0;      // capture time of the current sub-hop's first sample
    int64_t mLastSnareSub = -1;  // sub-hop of the last snare onset
    int64_t mLastDrumSub = -1;   // sub-hop of the last snare or hat onset
    bool mKeepLoudKicks = false;
    bool mRumbleKicks = false;
    bool mKicksNeedBody = false;
    bool mPitchSweep = false;
    float mHatMinStrength = 0.4f;
    float mSnareMinTail = 0;
    Band mBand[kBands];
};
