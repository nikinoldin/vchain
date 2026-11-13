// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once

#include <aubio/aubio.h>
#include "biquad.h"
#include <cstdint>
#include <vector>
#include "vchain_engine.h"
#include "trigger_bands.h"

class AudioAnalyzer {
public:
    static constexpr int kMaxTriggerBands = VC_MAX_TRIGGER_BANDS;
    static constexpr int kMinTriggerBands = VC_MIN_TRIGGER_BANDS;

    // Descriptor indices — ordered by usefulness for VJ mapping
    enum Descriptor {
        DESC_LOUDNESS = 0,   // K-weighted loudness (400ms momentary)
        DESC_INTENSITY,      // Onset density × spectral entropy (3s)
        DESC_BRIGHTNESS,     // Spectral rolloff 85% (5s)
        DESC_LOW_HIGH,       // Bass/treble energy ratio (1s)
        DESC_CHANGE,         // Spectral centroid block stddev (8 beats; 4s while the tempo is unknown)
        DESC_TEXTURE,        // Spectral entropy (3s)
        DESC_COUNT
    };
    static_assert(DESC_COUNT == VC_NUM_DESCRIPTORS, "the snapshot carries every descriptor");

    static const char* descriptorName(int d);

    AudioAnalyzer(uint32_t sampleRate, uint32_t hopSize, int numTriggerBands = VC_INSTRUMENT_BANDS);
    ~AudioAnalyzer();

    // bpm (0 = unknown) times the trigger decay and Change's beat-long blocks.
    void process(const float* samples, uint32_t count, float bpm);
    void reinit(uint32_t sampleRate, uint32_t hopSize);

    // Trigger CCs (TriggerBands: 3 = kick / snare / hat, other counts = frequency bands)
    int numTriggerBands() const { return mNumTriggerBands; }
    float trigger(int index) const;
    void setNumTriggerBands(int n);
    // Trigger decay in beats; 0 = follow the sound (TriggerEnvelope).
    void setTriggerDecayBeats(float beats) { mTriggerBands.setDecayBeats(beats); }

    // Descriptor values (0-1)
    float descriptor(int d) const;
    bool descriptorEnabled(int d) const;
    void setDescriptorEnabled(int d, bool enabled);

    // Smoothed display spectrum (VC_NUM_SPECTRUM bands, 0-1)
    const float* spectrum() const { return mSpectrumBands; }

private:
    void cleanup();
    void init();
    void initTriggerBands();

    // K-weighting (EBU R128 / ITU-R BS.1770) for this rate
    void initKWeighting();

    // Per-frame raw data stored in ring buffer
    struct FrameData {
        float rolloff85 = 0;        // Hz: frequency below which 85% of energy lives (display spectrum; Brightness)
        float spectralCentroid = 0; // Hz, from the one-hop FFT (Change)
        float kWeightedPower = 0;   // mean squared K-weighted amplitude
        // From the display spectrum (4096-point Hann, ≤ 12 Hz bins) and the drum detector, for the descriptors:
        float entropy = 0;          // spectral entropy 40 Hz–16 kHz, 0..1 (Texture, Intensity)
        float bassPower = 0;        // power below 250 Hz (Tone)
        float treblePower = 0;      // power 2–16 kHz (Tone)
        int drumHits = 0;           // kick, snare and hat hits found this hop (Intensity)
        bool silent = false;        // spectrum below kSilencePower (≈ −70 dB)
    };

    int framesForSeconds(float seconds) const;
    void computeDescriptors();
    void updateSpectrumBands(const float* samples, uint32_t count);
    static constexpr float kSpectrumAttack = 0.5f;   // per hop
    static constexpr float kSpectrumRelease = 0.08f; // per hop

    uint32_t mSampleRate;
    uint32_t mHopSize;
    int mNumTriggerBands;

    // FFT (one hop, unwindowed): only Change's spectral centroid
    aubio_fft_t* mFft = nullptr;
    fvec_t* mFftIn = nullptr;
    cvec_t* mSpectrum = nullptr;

    // A longer Hann-windowed FFT over the last vc_spectrum_fft_size() samples, so the low bands get bins of their own:
    // the display spectrum, and the rolloff, entropy and bass/treble power behind Brightness, Texture, Intensity, Tone.
    aubio_fft_t* mDisplayFft = nullptr;
    fvec_t* mDisplayIn = nullptr;
    cvec_t* mDisplaySpectrum = nullptr;
    std::vector<float> mDisplayRing;   // last N samples, circular
    std::vector<float> mDisplayWindow; // Hann
    std::vector<float> mDisplayMags;   // scaled magnitudes
    uint32_t mDisplayWrite = 0;


    // Zone-based trigger bands (no calibration needed)
    float mTriggerBandLo[kMaxTriggerBands] = {};  // low freq edge per band
    float mTriggerBandHi[kMaxTriggerBands] = {};  // high freq edge per band
    TriggerBands mTriggerBands;
    DrumOnsets mDrums;      // drum hits for Intensity (its own instance: the trigger bands may be frequency bands)
    int64_t mDrumTime = 0;  // µs of audio fed to mDrums
    float mBpm = 0;         // current tempo (0 = unknown), for Change's beat-long blocks
    float mLastTone = 0;    // Tone's value from the last music, faded out over silence

    float mSpectrumBands[VC_NUM_SPECTRUM] = {};

    // Descriptors
    float mDescriptors[DESC_COUNT] = {};
    bool mDescEnabled[DESC_COUNT] = {};

    // Frame data ring buffer (~5.5 sec at 48k/512)
    static constexpr int kFrameBufferSize = 512;
    FrameData mFrameBuffer[kFrameBufferSize] = {};
    int mFrameIdx = 0;
    int mFrameCount = 0;

    // K-weighting filter (two cascaded biquads)
    Biquad<double> mKStage1;
    Biquad<double> mKStage2;
};
