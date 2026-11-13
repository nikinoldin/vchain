// SPDX-License-Identifier: GPL-3.0-or-later
// Ported from Beat This! (MIT), see THIRD_PARTY_NOTICES.md
// The neural network's input, computed in the engine: Beat This!'s log-mel spectrogram (beat_this LogMelSpect /
// torchaudio MelSpectrogram), streaming. Mono in at the input rate -> windowed-sinc resampling to 22050 Hz ->
// centred STFT (n_fft 1024, periodic Hann 1024, hop 441 = 50 frames/s), magnitude divided by sqrt(n_fft)
// -> 128 Slaney mel bands 30-11000 Hz (no area norm) -> log1p(1000 x). A frame is ready 512 samples (23 ms) after
// its centre. Checked against the Python front end in unit_logmel.cpp.
#pragma once
#include <cstdint>
#include <vector>

class LogMel {
public:
    static constexpr int kBands = 128;
    static constexpr int kFft = 1024;
    static constexpr int kHop = 441;
    static constexpr double kRate = 22050;

    void reset(double inputRate);
    // Feeds n input samples; writes finished frames (kBands floats each) to out, at most maxFrames; returns how many.
    int process(const float* x, uint32_t n, float* out, int maxFrames);
    // Frames produced since reset (frame i is centred at 22.05 kHz sample i * kHop).
    int64_t framesDone() const { return mFrames; }

private:
    void pushResampled(float v, float* out, int maxFrames, int& made);
    void makeFrame(float* dst);
    double mInRate = 48000, mStep = 48000 / kRate; // input samples per output sample
    double mPos = 0;                               // position of the next output sample, in input samples
    int64_t mInCount = 0;                          // input samples received
    static constexpr int kTaps = 32;               // per side
    static constexpr int kPhases = 512;
    std::vector<float> mKernel;                    // (kPhases + 1) x (2 kTaps)
    std::vector<float> mHist;                      // input history ring
    int64_t mHistBase = 0;
    std::vector<float> mBuf;                       // 22.05 kHz samples ring (for frames)
    int64_t mOutCount = 0;                         // 22.05 kHz samples produced
    int64_t mFrames = 0;
    std::vector<float> mWindow, mFb;               // window (kFft), filterbank (513 x kBands, sparse ranges below)
    std::vector<int> mFbLo, mFbHi;
    std::vector<float> mRe, mIm;
    float mNorm = 1;
};
