// SPDX-License-Identifier: GPL-3.0-or-later
// The NN half of the hybrid front end in the app (docs/beat-tracking.md, "The NN front end").
// - Engine thread, every hop: pushHop() runs LogMel (cheap) and stores frames with their capture times in a ring.
// - Worker thread (its own, started by start()): loads the bundled Core ML model (compiles it once into cacheDir),
//   then once a second takes the newest 600 frames, predicts on the Neural Engine (~50 ms), picks the beats and
//   hands the window back through a single-producer/single-consumer queue.
// - Engine thread: popBeats() merges the windows (NNBeatMerger) into beats for BeatEngine::addExternalBeats.
// No locks between the threads; the audio thread is never involved. Without a model, ready() stays false and the
// engine runs drum-only.
#pragma once
#include "drum_onsets.h"
#include "log_mel.h"
#include "nn_beats.h"
#include <atomic>
#include <cstdint>
#include <memory>
#include <string>
#include <thread>
#include <vector>

class BeatNet;

class NNFrontEnd {
public:
    NNFrontEnd();
    ~NNFrontEnd();
    void start(const std::string& modelPath, const std::string& cacheDir);
    void stop();
    bool ready() const { return mReady.load(std::memory_order_acquire); }
    // Engine thread. captureUs: capture (or processing) time of x[0].
    void pushHop(const float* x, uint32_t n, int64_t captureUs, uint32_t sampleRate);
    // Engine thread: beats that became ready (OnsetClass::Beat, capture times), and downbeats (capture times) into
    // downbeats/nDown when given.
    int popBeats(Onset* out, int maxOut, int64_t* downbeats = nullptr, int maxDown = 0, int* nDown = nullptr);
    // Frames the worker has run a window up to (tests wait on it).
    int64_t processed() const { return mProcessed.load(std::memory_order_acquire); }
    int64_t written() const { return mWritten.load(std::memory_order_acquire); }

private:
    void run(BeatNet& net);

    static constexpr int kRing = 2048;   // frames (41 s)
    static constexpr int kQueue = 8;     // windows
    static constexpr int kMaxBeats = 64; // per window
    struct Window { int64_t tEnd; int n, nd; int64_t beats[kMaxBeats], downbeats[kMaxBeats]; uint32_t generation; };

    LogMel mLogMel;
    uint32_t mRate = 0;
    int64_t mSamples = 0;                // input samples since the last reset
    std::vector<float> mFrames;          // kRing x 128
    std::vector<int64_t> mFrameTime;     // capture time of each frame's centre
    std::atomic<int64_t> mWritten{0};    // frames written since the last reset
    std::atomic<uint32_t> mGeneration{0};// bumped on a reset (sample-rate change)
    Window mQueue[kQueue];
    std::atomic<int> mQHead{0}, mQTail{0};
    NNBeatMerger mMerger, mDownMerger;
    std::atomic<bool> mRunning{false}, mReady{false};
    std::atomic<int64_t> mProcessed{0};
    std::thread mThread;
    // The worker's model load: kLoading until it finishes (kLoaded) or stop() abandons it (kAbandoned, detached).
    enum { kLoading, kLoaded, kAbandoned };
    std::shared_ptr<std::atomic<int>> mLoad;
};
