// SPDX-License-Identifier: GPL-3.0-or-later
// The MIDI strip's trigger CCs (1-8): which sound hit, how hard, and how the CC falls back to zero.
// 3 bands = instruments: kick, snare/clap, hat from DrumOnsets (the beat grid's detector).
// Any other count = frequency bands (vc_trigger_band_edges), each with its own detector (BandOnsets).
// Allocation-free; runs on the engine thread, one call per hop.
#pragma once
#include "drum_onsets.h"
#include <cstdint>

constexpr int kTriggerMaxBands = 8;
constexpr int kTriggerInstrumentBands = 3; // this count means kick / snare / hat, not frequency ranges

// Band ranges in Hz for count bands (2-8): zones 50-200-2000-16000 Hz split log-spaced per a fixed table (2 bands
// skip the mid zone). The engine's vc_trigger_band_edges and the UI's range LCDs use this.
void triggerBandEdges(int count, float* lo, float* hi);

struct BandHit {
    int band;
    float strength; // the hit's level relative to the band's recent strongest hits (0..1)
};

// One onset detector per frequency band, DrumOnsets' method: band-pass, energy per sub-hop (~2.7 ms), log-energy
// rise over an adaptive threshold, local-max peak picking, a refractory gap, a floor relative to the band's recent strong
// hits. The rise is measured over ~5 ms, but over ~24 ms in bands starting below 100 Hz, where a hit builds up over a
// few periods of the wave (a kick over a loud rumble rises only 2-3 dB per 5-10 ms). Bands fire independently, but a
// weak hit is dropped when another band jumped far more at the same moment, each jump measured against that band's own
// usual level: one kick's click must not also fire the hat band, while a kick and a hat together fire both (a hit
// that's strong for its own band is never masked). A hit is also dropped when a touching neighbour band hit 6 dB
// louder, or louder with a 4× bigger jump, at the same moment (one sound spilling over two bands), or when it's a click
// (its energy gone within ~8 ms). A small rise (2 dB+ over the band's usual rise, under the normal threshold) counts
// only when another band hit clearly at the same moment (a higher band up to ~40 ms earlier) and other bands hit within
// the last second.
class BandOnsets {
public:
    void reset(uint32_t sampleRate, int count, const float* lo, const float* hi);
    int process(const float* x, uint32_t n, BandHit* out, int maxOut);
    float energy(int band) const; // latest windowed energy
    int count() const { return mCount; }

private:
    static constexpr int kRing = 32;
    struct Band {
        Biquad<float> f[4];
        int filters = 0;
        bool touches = false;    // its range starts where the band below ends
        int window = 1;          // energy window in sub-hops (low bands need longer: a 50 Hz wave ripples)
        int riseLag = 2;         // the rise compares the energy with this many sub-hops earlier
        float refractoryMs = 50;
        double acc = 0;
        float raw[kRing] = {}, energy[kRing] = {}, rise[kRing] = {};
        float meanRise = 0, devRise = 1, peakStrength = 0, meanEnergy = 1e-9f;
        int64_t lastOnsetSub = -1000;
        // The latest candidate (fired or still waiting for its neighbours).
        bool pending = false, small = false; // small: a below-threshold rise that needs another band's confirmation
        int64_t lastHitSub = -100000; // the latest hit sent
        int64_t candSub = -1000;
        float candJump = 0, candStrength = 0, candLevel = 0;
    };
    void endSubHop(BandHit* out, int maxOut, int& count);

    double mSr = 48000;
    uint32_t mSubLen = 128;
    uint32_t mFill = 0;
    int64_t mSubIndex = 0;
    int mCount = 0;
    Band mBand[kTriggerMaxBands];
};

// The CC value after a hit: jumps to the hit's strength, then either falls to zero in a fixed number of beats
// (tempo-locked) or follows the band's energy down (decayBeats 0, "follow the sound"; it never rises without a hit).
class TriggerEnvelope {
public:
    void reset();
    void setDecayBeats(float beats) { mBeats = beats; } // 0 = follow the sound
    // Moves time on by dt seconds; energy[band] is each band's current energy (follow mode only).
    void advance(float dt, float bpm, const float* energy, int count);
    void hit(int band, float strength, float energy);
    float value(int band) const { return band >= 0 && band < kTriggerMaxBands ? mB[band].v : 0.0f; }

private:
    struct B { float s = 0, t = 1e9f, level = 0, v = 0; };
    float mBeats = 0.5f;
    B mB[kTriggerMaxBands];
};

class TriggerBands {
public:
    void reset(uint32_t sampleRate);
    void setBands(int count, const float* lo, const float* hi);
    void setDecayBeats(float beats) { mEnv.setDecayBeats(beats); }
    // One hop of audio; bpm (0 = unknown, 120 is assumed) times the tempo-locked decay.
    void process(const float* x, uint32_t n, float bpm);
    float value(int band) const { return mEnv.value(band); }
    int count() const { return mCount; }
    bool instruments() const { return mCount == kTriggerInstrumentBands; }

private:
    uint32_t mSr = 48000;
    int mCount = 0;
    float mLo[kTriggerMaxBands] = {}, mHi[kTriggerMaxBands] = {};
    int64_t mT = 0; // µs of audio processed (DrumOnsets wants time stamps)
    DrumOnsets mDrums;
    BandOnsets mBands;
    TriggerEnvelope mEnv;
};
