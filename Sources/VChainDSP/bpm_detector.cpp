// SPDX-License-Identifier: GPL-3.0-or-later
#include "bpm_detector.h"
#include "biquad.h"
#include <algorithm>
#include <cmath>

void BpmDetector::initAubioInternal() {
    mAubioHop = mHopSize;
    uint32_t winSize = mHopSize * 2;

    mTempo = new_aubio_tempo("default", winSize, mAubioHop, mSampleRate);
    mInput = new_fvec(mAubioHop);
    mOutput = new_fvec(2);
    aubio_tempo_set_silence(mTempo, -40.0f);
    aubio_tempo_set_threshold(mTempo, 0.5f);  // less sensitive onset detection

    mTempoLow = new_aubio_tempo("hfc", winSize, mAubioHop, mSampleRate);
    mInputLow = new_fvec(mAubioHop);
    mOutputLow = new_fvec(2);
    aubio_tempo_set_silence(mTempoLow, -40.0f);
    aubio_tempo_set_threshold(mTempoLow, 0.5f);

    const BiquadCoeffs lp = rbjBiquad(BiquadType::LowPass, 200.0, 0.707, mSampleRate);
    mLowpassFilter = new_aubio_filter_biquad(lp.b0, lp.b1, lp.b2, lp.a1, lp.a2);
    aubio_filter_set_samplerate(mLowpassFilter, mSampleRate);
    mFilteredBuffer = new_fvec(mAubioHop);
}

void BpmDetector::cleanupInternal() {
    if (mTempo) { del_aubio_tempo(mTempo); mTempo = nullptr; }
    if (mInput) { del_fvec(mInput); mInput = nullptr; }
    if (mOutput) { del_fvec(mOutput); mOutput = nullptr; }
    if (mTempoLow) { del_aubio_tempo(mTempoLow); mTempoLow = nullptr; }
    if (mInputLow) { del_fvec(mInputLow); mInputLow = nullptr; }
    if (mOutputLow) { del_fvec(mOutputLow); mOutputLow = nullptr; }
    if (mLowpassFilter) { del_aubio_filter(mLowpassFilter); mLowpassFilter = nullptr; }
    if (mFilteredBuffer) { del_fvec(mFilteredBuffer); mFilteredBuffer = nullptr; }
}

BpmDetector::BpmDetector(uint32_t sampleRate, uint32_t hopSize)
    : mHopSize(hopSize)
    , mSampleRate(sampleRate)
{
    initAubioInternal();
}

BpmDetector::~BpmDetector() {
    cleanupInternal();
}

void BpmDetector::reinit(uint32_t sampleRate, uint32_t hopSize) {
    cleanupInternal();

    mSampleRate = sampleRate;
    mHopSize = hopSize;

    initAubioInternal();

    std::fill(std::begin(mHistogram), std::end(mHistogram), 0.0f);
    mStableBpm = 0.0f;
    mConfidence = 0.0f;
    mBeatDetected = false;
    mTotalSamples = 0;
    mLastBeatSample = 0;
}

void BpmDetector::setGenrePreset(int index) {
    const auto& presets = getGenrePresets();
    if (index >= 0 && index < static_cast<int>(presets.size())) {
        mGenreIndex = index;
        std::fill(std::begin(mHistogram), std::end(mHistogram), 0.0f);
        mStableBpm = 0.0f;
    }
}

namespace {

void addToHistogram(float* histogram, int numBins, float minBpm, float binWidth, float bpm, float weight) {
    int centerBin = static_cast<int>((bpm - minBpm) / binWidth);
    int spread = 4;
    for (int i = -spread; i <= spread; i++) {
        int bin = centerBin + i;
        if (bin >= 0 && bin < numBins) {
            float gaussian = std::exp(-0.5f * (i * i) / 4.0f);
            histogram[bin] += weight * gaussian;
        }
    }
}

float normalizeBpm(float bpm) {
    while (bpm > 200.0f && bpm > 1.0f) bpm *= 0.5f;
    while (bpm < 40.0f && bpm > 1.0f) bpm *= 2.0f;
    return bpm;
}

} // namespace

float BpmDetector::findHistogramPeak() const {
    const auto& presets = getGenrePresets();
    const auto& genre = presets[mGenreIndex];

    float maxVal = 0.0f;
    int maxBin = 0;

    for (int i = 0; i < kNumBins; i++) {
        float bpm = kHistMinBpm + i * kBinWidth;
        float weighted = mHistogram[i] * genre.weight(bpm);
        if (weighted > maxVal) {
            maxVal = weighted;
            maxBin = i;
        }
    }

    if (maxVal < 0.001f) return 0.0f;

    if (maxBin > 0 && maxBin < kNumBins - 1) {
        float left = mHistogram[maxBin - 1] * genre.weight(kHistMinBpm + (maxBin - 1) * kBinWidth);
        float center = mHistogram[maxBin] * genre.weight(kHistMinBpm + maxBin * kBinWidth);
        float right = mHistogram[maxBin + 1] * genre.weight(kHistMinBpm + (maxBin + 1) * kBinWidth);

        float denom = left - 2.0f * center + right;
        if (std::abs(denom) > 1e-6f) {
            float offset = 0.5f * (left - right) / denom;
            return kHistMinBpm + (maxBin + offset) * kBinWidth;
        }
    }

    return kHistMinBpm + maxBin * kBinWidth;
}

// Run one hop of aubio tempo detection
void BpmDetector::processAubioHop() {
    // Fill low-freq buffer and filter
    for (uint32_t i = 0; i < mAubioHop; i++) {
        fvec_set_sample(mFilteredBuffer, fvec_get_sample(mInput, i), i);
    }
    aubio_filter_do(mLowpassFilter, mFilteredBuffer);
    for (uint32_t i = 0; i < mAubioHop; i++) {
        fvec_set_sample(mInputLow, fvec_get_sample(mFilteredBuffer, i), i);
    }

    aubio_tempo_do(mTempo, mInput, mOutput);
    aubio_tempo_do(mTempoLow, mInputLow, mOutputLow);

    bool mainBeat = fvec_get_sample(mOutput, 0) > 0.0f;
    bool lowBeat = fvec_get_sample(mOutputLow, 0) > 0.0f;

    mTotalSamples += mAubioHop;

    // Suppress beats that are too close together (min interval = 200ms / 300 BPM)
    bool rawBeat = mainBeat || lowBeat;
    if (rawBeat && mLastBeatSample > 0) {
        float secsSinceLast = static_cast<float>(mTotalSamples - mLastBeatSample)
                            / static_cast<float>(mSampleRate);
        if (secsSinceLast < 0.2f) rawBeat = false;
    }
    mBeatDetected = rawBeat;

    // Compute BPM from actual beat intervals (bypasses aubio_tempo_get_bpm)
    if (mBeatDetected && mLastBeatSample > 0) {
        uint64_t intervalSamples = mTotalSamples - mLastBeatSample;
        float intervalSec = static_cast<float>(intervalSamples) / static_cast<float>(mSampleRate);
        float intervalBpm = 60.0f / intervalSec;

        // Only accept reasonable intervals (30-300 BPM range)
        if (intervalBpm > 30.0f && intervalBpm < 300.0f) {
            float normalizedBpm = normalizeBpm(intervalBpm);

            // Outlier rejection: if we have a stable BPM, only accept intervals
            // within 15% of it (allows half/double through normalizeBpm)
            bool accept = true;
            if (mStableBpm > 1.0f) {
                float deviation = std::abs(normalizedBpm - mStableBpm) / mStableBpm;
                accept = deviation < 0.15f;
            }

            if (accept) {
                addToHistogram(mHistogram, kNumBins, kHistMinBpm, kBinWidth,
                               normalizedBpm, 1.0f);
            }
        }
    }
    if (mBeatDetected) {
        mLastBeatSample = mTotalSamples;
    }

    // Also feed aubio's own BPM estimate into histogram (stable with complex rhythms)
    float mainConf = aubio_tempo_get_confidence(mTempo);
    float lowConf = aubio_tempo_get_confidence(mTempoLow);

    float mainBpm = aubio_tempo_get_bpm(mTempo);
    if (mainBpm > 30.0f && mainBpm < 300.0f && mainConf > 0.1f) {
        addToHistogram(mHistogram, kNumBins, kHistMinBpm, kBinWidth,
                       normalizeBpm(mainBpm), mainConf * 0.5f);
    }
    float lowBpm = aubio_tempo_get_bpm(mTempoLow);
    if (lowBpm > 30.0f && lowBpm < 300.0f && lowConf > 0.1f) {
        addToHistogram(mHistogram, kNumBins, kHistMinBpm, kBinWidth,
                       normalizeBpm(lowBpm), lowConf * 0.5f);
    }

    // Decay histogram
    for (int i = 0; i < kNumBins; i++) {
        mHistogram[i] *= kDecay;
    }

    // Confidence from aubio
    float rawConf = std::max(mainConf, lowConf);
    mConfidence = rawConf / (rawConf + 0.5f);

    float peakBpm = findHistogramPeak();
    if (peakBpm > 1.0f) {
        mStableBpm = peakBpm;
    }
}

void BpmDetector::process(const float* samples, uint32_t count) {
    uint32_t toCopy = std::min(count, mHopSize);

    // Feed audio directly to aubio
    for (uint32_t i = 0; i < toCopy; i++) {
        fvec_set_sample(mInput, samples[i], i);
    }
    processAubioHop();
}
