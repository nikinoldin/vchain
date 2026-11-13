// SPDX-License-Identifier: GPL-3.0-or-later
#include "audio_analyzer.h"
#include "hann.h"
#include "k_weighting.h"
#include "trigger_bands.h"
#include <algorithm>
#include <cmath>
#include <cstring>
#include <iostream>


namespace {
// Descriptor ranges, set from the bench tracks (house, techno, DnB, breaks, dub).
constexpr float kLoudLo = -30.0f, kLoudHi = -6.0f;       // Loudness, K-weighted dB
constexpr float kHitsPerSecHi = 10.0f;                   // Intensity: drum hits per second at full density
constexpr float kEntropyLo = 0.20f, kEntropyHi = 0.70f;  // Texture / Intensity: windowed spectral entropy
constexpr float kBalanceLo = -30.0f, kBalanceHi = 0.0f;  // Tone: treble minus bass, dB
constexpr float kRolloffLo = 200.0f, kRolloffHi = 10000.0f; // Brightness: 85 % rolloff, Hz (log scale)
// Below this spectrum power (≈ −70 dB full scale) a frame is silence: Brightness, Tone and Texture read 0 instead of
// measuring the shape of the noise floor (which would read as full treble, full noise).
constexpr float kSilencePower = 1e-7f;
constexpr float kToneFadeSeconds = 1.0f; // Tone fades to 0 over this when the music stops
} // namespace

const char* AudioAnalyzer::descriptorName(int d) {
    switch (d) {
        case DESC_BRIGHTNESS: return "Brightness";
        case DESC_LOUDNESS:   return "Loudness";
        case DESC_INTENSITY:  return "Intensity";
        case DESC_TEXTURE:    return "Texture";
        case DESC_LOW_HIGH:   return "Tone";
        case DESC_CHANGE: return "Change";
        default: return "?";
    }
}

AudioAnalyzer::AudioAnalyzer(uint32_t sampleRate, uint32_t hopSize, int numTriggerBands)
    : mSampleRate(sampleRate), mHopSize(hopSize)
    , mNumTriggerBands(std::clamp(numTriggerBands, kMinTriggerBands, kMaxTriggerBands))
{
    for (int i = 0; i < DESC_COUNT; i++)
        mDescEnabled[i] = true;
    init();
}

AudioAnalyzer::~AudioAnalyzer() {
    cleanup();
}

void AudioAnalyzer::initKWeighting() {
    // ITU-R BS.1770 K-weighting for this rate: two cascaded biquads
    // Stage 1: high shelf (head-related transfer function)
    // Stage 2: high-pass (RLB weighting, ~38 Hz)
    const KWeighting k = kWeighting(mSampleRate);
    mKStage1.set({k.shelf[0], k.shelf[1], k.shelf[2], k.shelf[3], k.shelf[4]});
    mKStage2.set({k.highPass[0], k.highPass[1], k.highPass[2], k.highPass[3], k.highPass[4]});
}

void AudioAnalyzer::init() {
    mFft = new_aubio_fft(mHopSize);
    mFftIn = new_fvec(mHopSize);
    mSpectrum = new_cvec(mHopSize);

    uint32_t displaySize = static_cast<uint32_t>(vc_spectrum_fft_size(mSampleRate));
    mDisplayFft = new_aubio_fft(displaySize);
    mDisplayIn = new_fvec(displaySize);
    mDisplaySpectrum = new_cvec(displaySize);
    mDisplayRing.assign(displaySize, 0.0f);
    mDisplayWindow = hannWindow<float>(displaySize);
    mDisplayMags.assign(displaySize / 2 + 1, 0.0f);
    mDisplayWrite = 0;


    initKWeighting();
    mTriggerBands.reset(mSampleRate);
    mDrums.reset(mSampleRate);
    mDrumTime = 0;
    initTriggerBands();

    // Reset frame buffer and previous spectra
    std::memset(mFrameBuffer, 0, sizeof(mFrameBuffer));
    std::memset(mSpectrumBands, 0, sizeof(mSpectrumBands));
    mFrameIdx = 0;
    mFrameCount = 0;

}

void AudioAnalyzer::cleanup() {
    if (mFft) { del_aubio_fft(mFft); mFft = nullptr; }
    if (mFftIn) { del_fvec(mFftIn); mFftIn = nullptr; }
    if (mSpectrum) { del_cvec(mSpectrum); mSpectrum = nullptr; }
    if (mDisplayFft) { del_aubio_fft(mDisplayFft); mDisplayFft = nullptr; }
    if (mDisplayIn) { del_fvec(mDisplayIn); mDisplayIn = nullptr; }
    if (mDisplaySpectrum) { del_cvec(mDisplaySpectrum); mDisplaySpectrum = nullptr; }
}

void AudioAnalyzer::reinit(uint32_t sampleRate, uint32_t hopSize) {
    cleanup();
    mSampleRate = sampleRate;
    mHopSize = hopSize;
    init();
}

void AudioAnalyzer::setNumTriggerBands(int n) {
    mNumTriggerBands = std::clamp(n, kMinTriggerBands, kMaxTriggerBands);
    initTriggerBands();
}

// --- Zone-based trigger band initialization ---

void AudioAnalyzer::initTriggerBands() {
    vc_trigger_band_edges(mNumTriggerBands, mTriggerBandLo, mTriggerBandHi);
    mTriggerBands.setBands(mNumTriggerBands, mTriggerBandLo, mTriggerBandHi);

    std::cout << "[Analyzer] " << mNumTriggerBands << " trigger bands:";
    for (int i = 0; i < mNumTriggerBands; i++) {
        float c = std::sqrt(mTriggerBandLo[i] * mTriggerBandHi[i]); // log-midpoint
        if (c >= 1000)
            std::cout << " " << static_cast<int>(c / 1000) << "." << static_cast<int>(c) % 1000 / 100 << "kHz";
        else
            std::cout << " " << static_cast<int>(c) << "Hz";
    }
    std::cout << std::endl;
}

float AudioAnalyzer::trigger(int index) const {
    if (index < 0 || index >= mNumTriggerBands) return 0.0f;
    return mTriggerBands.value(index);
}

float AudioAnalyzer::descriptor(int d) const {
    if (d < 0 || d >= DESC_COUNT) return 0.0f;
    return mDescriptors[d];
}

bool AudioAnalyzer::descriptorEnabled(int d) const {
    if (d < 0 || d >= DESC_COUNT) return false;
    return mDescEnabled[d];
}

void AudioAnalyzer::setDescriptorEnabled(int d, bool enabled) {
    if (d >= 0 && d < DESC_COUNT) {
        mDescEnabled[d] = enabled;
        if (!enabled) mDescriptors[d] = 0.0f;
    }
}

int AudioAnalyzer::framesForSeconds(float seconds) const {
    int frames = static_cast<int>(seconds * static_cast<float>(mSampleRate) / static_cast<float>(mHopSize));
    return std::min(frames, kFrameBufferSize);
}

// --- Descriptor computation from ring buffer ---

void AudioAnalyzer::computeDescriptors() {
    int available = mFrameCount;
    if (available < 2) return;

    // Helper to get frame at offset from most recent (0 = newest)
    auto getFrame = [this](int offset) -> const FrameData& {
        int idx = (mFrameIdx - 1 - offset + kFrameBufferSize) % kFrameBufferSize;
        return mFrameBuffer[idx];
    };

    // Brightness: the 85 % spectral rolloff (frequency below which 85 % of the energy lives), averaged over 5 s,
    // on a log scale from kRolloffLo to kRolloffHi. Dark tracks sit low but still move (the floor is under them).
    if (mDescEnabled[DESC_BRIGHTNESS]) {
        int n = std::min(available, framesForSeconds(5.0f));
        float sum = 0;
        for (int i = 0; i < n; i++) sum += getFrame(i).rolloff85;
        float logRolloff = std::log2(std::max(sum / n, 1.0f));
        mDescriptors[DESC_BRIGHTNESS] = std::clamp(
            (logRolloff - std::log2(kRolloffLo)) / (std::log2(kRolloffHi) - std::log2(kRolloffLo)), 0.0f, 1.0f);
    }

    // Loudness: K-weighted mean power over 400ms (EBU R128 momentary), mapped from dB
    if (mDescEnabled[DESC_LOUDNESS]) {
        int n = std::min(available, framesForSeconds(0.4f));
        float sum = 0;
        for (int i = 0; i < n; i++)
            sum += getFrame(i).kWeightedPower;
        float meanPower = sum / n;
        // Where mastered club music lives (checked on the bench tracks): kLoudLo dB → 0, kLoudHi dB → 1.
        float db = (meanPower > 1e-10f) ? 10.0f * std::log10(meanPower) : -100.0f;
        mDescriptors[DESC_LOUDNESS] = std::clamp((db - kLoudLo) / (kLoudHi - kLoudLo), 0.0f, 1.0f);
    }

    // Intensity: drum density × noisiness over 3 s, geometric mean (both must be high: a busy, dense mix).
    // Drum hits come from DrumOnsets (kick, snare, hat), not from every detected beat.
    if (mDescEnabled[DESC_INTENSITY]) {
        int n = std::min(available, framesForSeconds(3.0f));
        int hits = 0;
        float entropySum = 0;
        for (int i = 0; i < n; i++) {
            const auto& f = getFrame(i);
            hits += f.drumHits;
            entropySum += f.entropy;
        }
        float windowSec = static_cast<float>(n) * static_cast<float>(mHopSize) / static_cast<float>(mSampleRate);
        float density = std::clamp(static_cast<float>(hits) / std::max(windowSec, 0.01f) / kHitsPerSecHi, 0.0f, 1.0f);
        float noisy = std::clamp((entropySum / n - kEntropyLo) / (kEntropyHi - kEntropyLo), 0.0f, 1.0f);
        mDescriptors[DESC_INTENSITY] = std::sqrt(density * noisy);
    }

    // Texture: mean spectral entropy over 3 s from the windowed spectrum: low = tonal/clean, high = noisy/dense.
    if (mDescEnabled[DESC_TEXTURE]) {
        int n = std::min(available, framesForSeconds(3.0f));
        float sum = 0;
        for (int i = 0; i < n; i++) sum += getFrame(i).entropy;
        mDescriptors[DESC_TEXTURE] = std::clamp((sum / n - kEntropyLo) / (kEntropyHi - kEntropyLo), 0.0f, 1.0f);
    }

    // Tone: treble (2–16 kHz) vs bass (below 250 Hz) over 1 s, as a balance in dB: 0 = bass-heavy, 1 = bright.
    // When the music stops it fades from its last value to 0 over kToneFadeSeconds (silence has no balance; the ratio
    // alone would hold and then jump).
    if (mDescEnabled[DESC_LOW_HIGH]) {
        int n = std::min(available, framesForSeconds(1.0f));
        float bass = 0, treble = 0;
        for (int i = 0; i < n; i++) {
            bass += getFrame(i).bassPower;
            treble += getFrame(i).treblePower;
        }
        if (bass + treble > 0) {
            float balanceDb = 10.0f * std::log10((treble + 1e-12f) / (bass + 1e-12f));
            mLastTone = std::clamp((balanceDb - kBalanceLo) / (kBalanceHi - kBalanceLo), 0.0f, 1.0f);
        }
        int fade = std::min(available, framesForSeconds(kToneFadeSeconds)), music = 0;
        for (int i = 0; i < fade; i++) music += getFrame(i).silent ? 0 : 1;
        mDescriptors[DESC_LOW_HIGH] = mLastTone * static_cast<float>(music) / static_cast<float>(std::max(fade, 1));
    }

    // Change: stddev of the spectral centroid across beat-long blocks over 8 beats (0.5 s blocks over 4 s while the
    // tempo is unknown). Averaging per beat smooths out the per-beat variation.
    // Stddev of those blocks captures section-level tonal shifts.
    // Low = same timbre throughout, High = changing timbre (transitions, drops)
    if (mDescEnabled[DESC_CHANGE]) {
        float beat = mBpm > 20.0f ? 60.0f / mBpm : 0.5f;
        int blockFrames = std::max(1, framesForSeconds(beat));
        int totalFrames = std::min(available, framesForSeconds(8.0f * beat));
        int numBlocks = totalFrames / std::max(blockFrames, 1);
        if (numBlocks >= 2) {
            float blockAvgs[16] = {};
            int maxBlocks = std::min(numBlocks, 16);
            for (int b = 0; b < maxBlocks; b++) {
                float sum = 0;
                for (int i = 0; i < blockFrames; i++)
                    sum += getFrame(b * blockFrames + i).spectralCentroid;
                blockAvgs[b] = sum / blockFrames;
            }
            float sum = 0, sumSq = 0;
            for (int b = 0; b < maxBlocks; b++) {
                sum += blockAvgs[b];
                sumSq += blockAvgs[b] * blockAvgs[b];
            }
            float mean = sum / maxBlocks;
            float variance = sumSq / maxBlocks - mean * mean;
            float stddev = std::sqrt(std::max(0.0f, variance));

            constexpr float kLo = 0.0f;
            constexpr float kHi = 1500.0f;
            mDescriptors[DESC_CHANGE] = std::clamp(
                (stddev - kLo) / (kHi - kLo), 0.0f, 1.0f);
        }
    }
}

// --- Main process ---

void AudioAnalyzer::updateSpectrumBands(const float* samples, uint32_t count) {
    uint32_t size = static_cast<uint32_t>(mDisplayRing.size());
    for (uint32_t i = 0; i < count; i++) {
        mDisplayRing[mDisplayWrite] = samples[i];
        mDisplayWrite = (mDisplayWrite + 1) % size;
    }
    // Oldest sample first, windowed.
    for (uint32_t i = 0; i < size; i++)
        mDisplayIn->data[i] = mDisplayRing[(mDisplayWrite + i) % size] * mDisplayWindow[i];
    aubio_fft_do(mDisplayFft, mDisplayIn, mDisplaySpectrum);

    // aubio's FFT is unnormalised and the Hann window halves a sine's peak (a full-scale sine peaks
    // near size/4): scale so 1.0 = full scale.
    float scale = 4.0f / static_cast<float>(size);
    int bins = static_cast<int>(std::min<size_t>(mDisplaySpectrum->length, mDisplayMags.size()));
    for (int i = 0; i < bins; i++) mDisplayMags[i] = mDisplaySpectrum->norm[i] * scale;
    float binHz = static_cast<float>(mSampleRate) / static_cast<float>(size);
    float bands[VC_NUM_SPECTRUM];
    vc_spectrum_bands(mDisplayMags.data(), bins, binHz, bands, VC_NUM_SPECTRUM);
    for (int b = 0; b < VC_NUM_SPECTRUM; b++) {
        float coeff = bands[b] > mSpectrumBands[b] ? kSpectrumAttack : kSpectrumRelease;
        mSpectrumBands[b] += (bands[b] - mSpectrumBands[b]) * coeff;
    }
}

void AudioAnalyzer::process(const float* samples, uint32_t count, float bpm) {
    uint32_t n = std::min(count, mHopSize);

    // One-hop FFT (Change's spectral centroid)
    for (uint32_t i = 0; i < mHopSize; i++)
        fvec_set_sample(mFftIn, i < n ? samples[i] : 0.0f, i);
    aubio_fft_do(mFft, mFftIn, mSpectrum);

    updateSpectrumBands(samples, n);

    uint32_t fftSize = mSpectrum->length;
    float binHz = static_cast<float>(mSampleRate) / static_cast<float>(mHopSize); // the FFT is one hop long

    mTriggerBands.process(samples, n, bpm);

    // --- Collect per-frame data for ring buffer ---
    FrameData frame;
    mBpm = bpm;

    // Drum hits (Intensity): the beat grid's detector, kick + snare + hat.
    {
        Onset hits[16];
        frame.drumHits = mDrums.process(samples, n, mDrumTime, hits, 16);
        mDrumTime += static_cast<int64_t>(std::llround(n * 1e6 / mSampleRate));
    }

    // From the display spectrum (Hann-windowed, fine bins): entropy and the bass / treble power.
    {
        float binHz = static_cast<float>(mSampleRate) / static_cast<float>(mDisplayRing.size());
        int lo = std::max(1, static_cast<int>(40.0f / binHz));
        int hi = std::min(static_cast<int>(mDisplayMags.size()) - 1, static_cast<int>(16000.0f / binHz));
        float total = 0;
        for (int i = lo; i <= hi; i++) {
            float p = mDisplayMags[i] * mDisplayMags[i];
            total += p;
            float f = static_cast<float>(i) * binHz;
            if (f < 250.0f) frame.bassPower += p;
            else if (f >= 2000.0f) frame.treblePower += p;
        }
        frame.silent = total < kSilencePower;
        if (frame.silent) frame.bassPower = frame.treblePower = 0;
        if (total >= kSilencePower) {
            // 85 % rolloff (Brightness) on the fine bins: dark tracks sit at 200–1000 Hz, which 94 Hz bins can't resolve.
            float cum = 0;
            frame.rolloff85 = static_cast<float>(lo) * binHz;
            for (int i = lo; i <= hi; i++) {
                cum += mDisplayMags[i] * mDisplayMags[i];
                if (cum >= 0.85f * total) { frame.rolloff85 = static_cast<float>(i) * binHz; break; }
            }
            float h = 0;
            for (int i = lo; i <= hi; i++) {
                float p = mDisplayMags[i] * mDisplayMags[i] / total;
                if (p > 1e-20f) h -= p * std::log2(p);
            }
            frame.entropy = h / std::log2(static_cast<float>(hi - lo + 1));
        }
    }

    // Spectral centroid (Change); the rolloff (Brightness) comes from the display spectrum above.
    {
        float weightedSum = 0.0f, totalMag = 0.0f;
        for (uint32_t i = 1; i < fftSize; i++) {
            float mag = mSpectrum->norm[i];
            weightedSum += mag * static_cast<float>(i) * binHz;
            totalMag += mag;
        }

        frame.spectralCentroid = (totalMag > 1e-10f) ? (weightedSum / totalMag) : 0.0f;
    }

    // K-weighted power (EBU R128 perceptual loudness)
    {
        float power = 0.0f;
        for (uint32_t i = 0; i < n; i++) {
            float k = mKStage2.run(mKStage1.run(samples[i]));
            power += k * k;
        }
        frame.kWeightedPower = power / static_cast<float>(n);
    }

    // Store in ring buffer
    mFrameBuffer[mFrameIdx] = frame;
    mFrameIdx = (mFrameIdx + 1) % kFrameBufferSize;
    if (mFrameCount < kFrameBufferSize) mFrameCount++;

    // Compute descriptors from ring buffer windows
    computeDescriptors();
}
