// SPDX-License-Identifier: GPL-3.0-or-later
#include "nn_front_end.h"
#include "beat_net.h"
#include "nn_peaks.h"
#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdio>
#include <mutex>

namespace {
// One model load at a time: a load stop() let go of may still be compiling into the cache a new start() loads from.
// Never destroyed (a detached load may still hold it at exit).
std::mutex& loadMutex() { static std::mutex* m = new std::mutex; return *m; }
} // namespace

NNFrontEnd::NNFrontEnd() : mFrames(size_t(kRing) * LogMel::kBands, 0.0f), mFrameTime(kRing, 0) {}
NNFrontEnd::~NNFrontEnd() { stop(); }

void NNFrontEnd::start(const std::string& modelPath, const std::string& cacheDir) {
    stop();
    mRunning = true;
    auto load = std::make_shared<std::atomic<int>>(kLoading);
    mLoad = load;
    mThread = std::thread([this, load, modelPath, cacheDir] {
        auto net = std::make_unique<BeatNet>();
        std::string err;
        bool ok;
        {
            std::lock_guard<std::mutex> lock(loadMutex());
            ok = net->load(modelPath, cacheDir, &err);
        }
        int expected = kLoading;
        if (!load->compare_exchange_strong(expected, kLoaded)) return; // stop() let this thread go: `this` may be gone
        if (!ok) {
            fprintf(stderr, "[NNFrontEnd] no model (%s): drum-only\n", err.c_str());
            return;
        }
        run(*net);
    });
}

// Never waits for a model load (the first one compiles the model, seconds; stop() runs under the engine mutex): a
// thread still loading is detached and exits after the load without touching this object. A running worker is
// joined (at most one prediction, ~50 ms).
void NNFrontEnd::stop() {
    mRunning = false;
    if (mThread.joinable()) {
        int expected = kLoading;
        if (mLoad && mLoad->compare_exchange_strong(expected, kAbandoned)) mThread.detach();
        else mThread.join();
    }
    mLoad.reset();
    mReady = false;
}

void NNFrontEnd::pushHop(const float* x, uint32_t n, int64_t captureUs, uint32_t sampleRate) {
    if (sampleRate != mRate) {
        mRate = sampleRate;
        mLogMel.reset(sampleRate);
        mSamples = 0;
        mGeneration.fetch_add(1, std::memory_order_acq_rel);
        mWritten.store(0, std::memory_order_release);
        mMerger.reset();
        mDownMerger.reset();
    }
    float buf[LogMel::kBands * 8];
    int k = mLogMel.process(x, n, buf, 8);
    int64_t w = mWritten.load(std::memory_order_relaxed);
    for (int i = 0; i < k; i++) {
        int64_t f = w + i;
        // Frame f is centred at 22.05 kHz sample f * 441, i.e. input sample f * 441 * rate / 22050; place it in time
        // from this hop (re-anchored every hop, so clock drift doesn't accumulate).
        double s = double(f) * LogMel::kHop * double(sampleRate) / LogMel::kRate;
        int64_t t = captureUs + int64_t(std::llround((s - double(mSamples)) * 1e6 / sampleRate));
        std::copy(buf + i * LogMel::kBands, buf + (i + 1) * LogMel::kBands, mFrames.begin() + (f % kRing) * LogMel::kBands);
        mFrameTime[f % kRing] = t;
    }
    mSamples += n;
    mWritten.store(w + k, std::memory_order_release);
}

int NNFrontEnd::popBeats(Onset* out, int maxOut, int64_t* downbeats, int maxDown, int* nDown) {
    int k = 0, d = 0;
    const uint32_t gen = mGeneration.load(std::memory_order_acquire);
    while (mQTail.load(std::memory_order_relaxed) != mQHead.load(std::memory_order_acquire)) {
        const Window& w = mQueue[mQTail.load(std::memory_order_relaxed) % kQueue];
        if (w.generation == gen) {
            if (k < maxOut) k += mMerger.addWindow(w.tEnd, w.beats, w.n, out + k, maxOut - k);
            Onset tmp[kMaxBeats];
            int m = mDownMerger.addWindow(w.tEnd, w.downbeats, w.nd, tmp, kMaxBeats);
            for (int i = 0; i < m && downbeats && d < maxDown; i++) downbeats[d++] = tmp[i].t;
        }
        mQTail.fetch_add(1, std::memory_order_release);
    }
    if (nDown) *nDown = d;
    return k;
}

void NNFrontEnd::run(BeatNet& net) {
    mReady = true;
    std::vector<float> frames(size_t(BeatNet::kFrames) * BeatNet::kBands);
    std::vector<int64_t> times(BeatNet::kFrames);
    float beatL[BeatNet::kFrames], downL[BeatNet::kFrames];
    int64_t last = 0;
    uint32_t lastGen = mGeneration.load();
    while (mRunning) {
        std::this_thread::sleep_for(std::chrono::milliseconds(20));
        uint32_t gen = mGeneration.load(std::memory_order_acquire);
        if (gen != lastGen) { lastGen = gen; last = 0; }
        int64_t w = mWritten.load(std::memory_order_acquire);
        if (w < 50 || w - last < 50) continue; // a window per second (50 frames)
        last = w;
        // The newest 600 frames (zeros before the start). No lock: the engine thread writes frames mWritten.. (up to 8
        // per hop) into slot frame % kRing, so it reaches a slot copied here only after lapping it, kRing - kFrames
        // frames (29 s) later; a reset (sample-rate change) restarts at slot 0 but bumps the generation. Both are
        // re-checked below and such a window dropped.
        for (int i = 0; i < BeatNet::kFrames; i++) {
            int64_t f = w - BeatNet::kFrames + i;
            float* dst = frames.data() + size_t(i) * BeatNet::kBands;
            if (f < 0) { std::fill(dst, dst + BeatNet::kBands, 0.0f); times[i] = 0; continue; }
            std::copy(mFrames.begin() + (f % kRing) * LogMel::kBands, mFrames.begin() + (f % kRing + 1) * LogMel::kBands, dst);
            times[i] = mFrameTime[f % kRing];
        }
        if (!net.predict(frames.data(), beatL, downL)) { mProcessed.store(w, std::memory_order_release); continue; }
        double peaks[256];
        int np = pickNNPeaks(beatL, BeatNet::kFrames, peaks, 256);
        std::atomic_thread_fence(std::memory_order_acquire); // the copy above happens before these loads
        if (mGeneration.load(std::memory_order_relaxed) != gen) continue; // reset meanwhile: the next pass starts over
        if (mWritten.load(std::memory_order_relaxed) - w >= kRing - BeatNet::kFrames - 8) { mProcessed.store(w); continue; }
        int head = mQHead.load(std::memory_order_relaxed);
        if (head - mQTail.load(std::memory_order_acquire) >= kQueue) { mProcessed.store(w); continue; } // not drained: drop
        Window& out = mQueue[head % kQueue];
        out.n = 0;
        out.nd = 0;
        out.generation = gen;
        out.tEnd = times[BeatNet::kFrames - 1];
        for (int p = 0; p < np && out.n < kMaxBeats; p++) {
            int lo = int(std::floor(peaks[p])), hi = std::min(lo + 1, BeatNet::kFrames - 1);
            if (lo < 6 || times[lo] == 0) continue; // left border / before the start
            double frac = peaks[p] - lo;
            out.beats[out.n++] = times[lo] + int64_t(std::llround(frac * double(times[hi] - times[lo])));
        }
        np = pickNNPeaks(downL, BeatNet::kFrames, peaks, 256);
        for (int p = 0; p < np && out.nd < kMaxBeats; p++) {
            int lo = int(std::floor(peaks[p])), hi = std::min(lo + 1, BeatNet::kFrames - 1);
            if (lo < 6 || times[lo] == 0) continue;
            double frac = peaks[p] - lo;
            out.downbeats[out.nd++] = times[lo] + int64_t(std::llround(frac * double(times[hi] - times[lo])));
        }
        mQHead.store(head + 1, std::memory_order_release);
        mProcessed.store(w, std::memory_order_release);
    }
}
