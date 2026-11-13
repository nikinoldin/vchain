// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once

#include <aubio/aubio.h>
#include <cstdint>
#include "genre.h"

class BpmDetector {
public:
    BpmDetector(uint32_t sampleRate = 44100, uint32_t hopSize = 512);
    ~BpmDetector();

    // Feed audio samples. Call with hopSize samples at a time.
    void process(const float* samples, uint32_t count);

    float bpm() const { return mStableBpm; }
    float confidence() const { return mConfidence; }

    // Genre prior
    void setGenrePreset(int index);

    // Reinitialize with new sample rate (e.g. after device switch)
    void reinit(uint32_t sampleRate, uint32_t hopSize);

private:
    void initAubioInternal();
    void cleanupInternal();
    void processAubioHop();
    float findHistogramPeak() const;

    // Main detector (full spectrum, specflux)
    aubio_tempo_t* mTempo = nullptr;
    fvec_t* mInput = nullptr;
    fvec_t* mOutput = nullptr;

    // Low-frequency detector (kick range, hfc)
    aubio_tempo_t* mTempoLow = nullptr;
    fvec_t* mInputLow = nullptr;
    fvec_t* mOutputLow = nullptr;
    aubio_filter_t* mLowpassFilter = nullptr;
    fvec_t* mFilteredBuffer = nullptr;

    uint32_t mHopSize;
    uint32_t mSampleRate;
    uint32_t mAubioHop = 0;

    float mStableBpm = 0.0f;
    float mConfidence = 0.0f;
    bool mBeatDetected = false;

    // Beat interval tracking (sample-accurate BPM from onset times)
    uint64_t mTotalSamples = 0;      // running sample counter
    uint64_t mLastBeatSample = 0;    // sample position of last detected beat

    // Decaying BPM histogram
    static constexpr int kHistMinBpm = 40;
    static constexpr int kHistMaxBpm = 200;
    static constexpr float kBinWidth = 0.5f; // BPM per bin
    static constexpr int kNumBins = (kHistMaxBpm - kHistMinBpm) * 2; // 320 bins
    static constexpr float kDecay = 0.995f;
    float mHistogram[kNumBins] = {};

    // Genre prior
    int mGenreIndex = 0; // default: Auto
};
