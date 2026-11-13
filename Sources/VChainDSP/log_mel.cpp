// SPDX-License-Identifier: GPL-3.0-or-later
// Ported from Beat This! (MIT), see THIRD_PARTY_NOTICES.md
#include "log_mel.h"
#include "hann.h"
#include <algorithm>
#include <cmath>

namespace {
// Slaney mel scale as torchaudio's _hz_to_mel / _mel_to_hz(mel_scale="slaney").
double hzToMel(double f) {
    const double fSp = 200.0 / 3, minLogHz = 1000, minLogMel = minLogHz / fSp, logStep = std::log(6.4) / 27;
    return f < minLogHz ? f / fSp : minLogMel + std::log(f / minLogHz) / logStep;
}
double melToHz(double m) {
    const double fSp = 200.0 / 3, minLogHz = 1000, minLogMel = minLogHz / fSp, logStep = std::log(6.4) / 27;
    return m < minLogMel ? m * fSp : minLogHz * std::exp(logStep * (m - minLogMel));
}
void fft(std::vector<float>& re, std::vector<float>& im) {
    const int n = int(re.size());
    for (int i = 1, j = 0; i < n; i++) {
        int bit = n >> 1;
        for (; j & bit; bit >>= 1) j ^= bit;
        j ^= bit;
        if (i < j) { std::swap(re[i], re[j]); std::swap(im[i], im[j]); }
    }
    for (int len = 2; len <= n; len <<= 1) {
        double ang = -2 * M_PI / len;
        float wr = float(std::cos(ang)), wi = float(std::sin(ang));
        for (int i = 0; i < n; i += len) {
            float cr = 1, ci = 0;
            for (int k = 0; k < len / 2; k++) {
                float ur = re[i + k], ui = im[i + k];
                float vr = re[i + k + len / 2] * cr - im[i + k + len / 2] * ci;
                float vi = re[i + k + len / 2] * ci + im[i + k + len / 2] * cr;
                re[i + k] = ur + vr; im[i + k] = ui + vi;
                re[i + k + len / 2] = ur - vr; im[i + k + len / 2] = ui - vi;
                float nr = cr * wr - ci * wi; ci = cr * wi + ci * wr; cr = nr;
            }
        }
    }
}
} // namespace

void LogMel::reset(double inputRate) {
    mInRate = inputRate;
    mStep = inputRate / kRate;
    mPos = 0;
    mInCount = 0;
    mOutCount = 0;
    mFrames = 0;
    mHistBase = 0;
    mHist.assign(256, 0.0f);
    mBuf.assign(4096, 0.0f);
    // Windowed sinc (Kaiser, beta 8.6), cut-off a little under the output Nyquist.
    const double fc = 0.5 * std::min(1.0, kRate / inputRate) * 0.98;
    auto bessel0 = [](double x) { double s = 1, t = 1; for (int k = 1; k < 30; k++) { t *= (x / (2 * k)) * (x / (2 * k)); s += t; } return s; };
    const double beta = 8.6, i0b = bessel0(beta);
    mKernel.assign((kPhases + 1) * 2 * kTaps, 0.0f);
    for (int p = 0; p <= kPhases; p++) {
        double frac = double(p) / kPhases;
        double sum = 0;
        for (int k = 0; k < 2 * kTaps; k++) {
            double d = (k - kTaps + 1) - frac; // tap distance in input samples
            double s = d == 0 ? 2 * fc : std::sin(2 * M_PI * fc * d) / (M_PI * d);
            double r = d / kTaps;
            double w = std::fabs(r) < 1 ? bessel0(beta * std::sqrt(1 - r * r)) / i0b : 0;
            mKernel[p * 2 * kTaps + k] = float(s * w);
            sum += s * w;
        }
        for (int k = 0; k < 2 * kTaps; k++) mKernel[p * 2 * kTaps + k] = float(mKernel[p * 2 * kTaps + k] / sum);
    }
    // Periodic Hann and the mel filterbank (torchaudio melscale_fbanks, norm None, slaney).
    mWindow = hannWindow<double>(kFft);
    mNorm = float(1.0 / std::sqrt(double(kFft))); // torchaudio normalized="frame_length": divide by sqrt(n_fft)
    const int nFreq = kFft / 2 + 1;
    std::vector<double> fpts(kBands + 2);
    double mMin = hzToMel(30), mMax = hzToMel(11000);
    for (int i = 0; i < kBands + 2; i++) fpts[i] = melToHz(mMin + (mMax - mMin) * i / (kBands + 1));
    mFb.assign(nFreq * kBands, 0.0f);
    mFbLo.assign(kBands, nFreq);
    mFbHi.assign(kBands, -1);
    for (int f = 0; f < nFreq; f++) {
        double hz = 11025.0 * f / (nFreq - 1); // torch.linspace(0, sample_rate // 2, n_freqs)
        for (int m = 0; m < kBands; m++) {
            double down = (hz - fpts[m]) / (fpts[m + 1] - fpts[m]);
            double up = (fpts[m + 2] - hz) / (fpts[m + 2] - fpts[m + 1]);
            double v = std::max(0.0, std::min(down, up));
            if (v > 0) { mFb[f * kBands + m] = float(v); mFbLo[m] = std::min(mFbLo[m], f); mFbHi[m] = std::max(mFbHi[m], f); }
        }
    }
    mRe.assign(kFft, 0.0f);
    mIm.assign(kFft, 0.0f);
}

int LogMel::process(const float* x, uint32_t n, float* out, int maxFrames) {
    int made = 0;
    const int H = int(mHist.size());
    for (uint32_t i = 0; i < n; i++) {
        mHist[mInCount % H] = x[i];
        mInCount++;
        // Output samples whose kernel window is now complete.
        while (mPos + kTaps <= double(mInCount - 1)) {
            int64_t base = int64_t(std::floor(mPos));
            double frac = mPos - base;
            int p = int(std::lround(frac * kPhases));
            const float* k = &mKernel[p * 2 * kTaps];
            float acc = 0;
            for (int t = 0; t < 2 * kTaps; t++) {
                int64_t idx = base - kTaps + 1 + t;
                acc += (idx >= 0 ? mHist[idx % H] : 0.0f) * k[t];
            }
            pushResampled(acc, out, maxFrames, made);
            mPos += mStep;
        }
    }
    return made;
}

void LogMel::pushResampled(float v, float* out, int maxFrames, int& made) {
    const int B = int(mBuf.size());
    mBuf[mOutCount % B] = v;
    mOutCount++;
    // Frame i is centred at sample i * kHop and needs samples up to i * kHop + kFft / 2 - 1.
    while (mFrames * kHop + kFft / 2 <= mOutCount) {
        if (made < maxFrames) makeFrame(out + size_t(made++) * kBands);
        mFrames++;
    }
}

void LogMel::makeFrame(float* dst) {
    const int B = int(mBuf.size());
    const int64_t c = mFrames * kHop;
    for (int i = 0; i < kFft; i++) {
        int64_t idx = c - kFft / 2 + i;
        if (idx < 0) idx = -idx; // reflect padding at the start (as torch's center=True, pad_mode="reflect")
        mRe[i] = mBuf[idx % B] * mWindow[i];
        mIm[i] = 0;
    }
    fft(mRe, mIm);
    float mag[kFft / 2 + 1];
    for (int f = 0; f <= kFft / 2; f++) mag[f] = std::sqrt(mRe[f] * mRe[f] + mIm[f] * mIm[f]) * mNorm;
    for (int m = 0; m < kBands; m++) {
        float s = 0;
        for (int f = mFbLo[m]; f <= mFbHi[m]; f++) s += mag[f] * mFb[f * kBands + m];
        dst[m] = std::log1p(1000.0f * s);
    }
}
