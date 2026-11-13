// SPDX-License-Identifier: GPL-3.0-or-later
#include "pipelines.h"
#include "beat_engine.h"
#include "beat_net.h"
#include "log_mel.h"
#include "nn_beats.h"
#include "nn_peaks.h"
#include <algorithm>
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <cmath>
#include <fstream>
#include <sstream>
#include <vector>

namespace {
// BeatEngine as the bench sees it: hops come with their capture times (the engine's job), "now" is ignored.
// What the rolling NN window reported: per window end, its beats (kind 0) and downbeats (kind 1).
struct NNEvent { double tEnd, time; int kind; float logit; };

class BeatPipeline : public Pipeline {
public:
    explicit BeatPipeline(std::string nnFile = "", bool hybrid = false, bool live = false)
        : mLive(live), mNNFile(std::move(nnFile)), mHybrid(hybrid) {
        if (!mNNFile.empty()) {
            std::ifstream f(mNNFile);
            std::string line;
            while (std::getline(f, line)) {
                std::istringstream ss(line);
                NNEvent e{};
                if (ss >> e.tEnd >> e.time >> e.kind >> e.logit) mNN.push_back(e);
            }
        }
    }
    const char* name() const override {
        if (mLive) return "live-hy-tempo-phase";
        return mHybrid ? "hy-tempo-phase" : "tempo-phase";
    }
    void reset(uint32_t sr) override {
        if (!mEngine) mEngine = std::make_unique<BeatEngine>(sr);
        mEngine->setHybrid(mHybrid);
        mEngine->reset(sr);
        mNext = 0;
        mMerger.reset();
        mDownMerger.reset();
        if (mLive) {
            mLogMel.reset(sr);
            mFrames.assign(size_t(BeatNet::kFrames) * BeatNet::kBands, 0.0f);
            mFramesDone = 0;
            mT0 = -1;
            if (!mNet.ready()) {
                const char* env = getenv("VCHAIN_NN_MODEL");
                std::string home = getenv("HOME");
                std::string model = env ? env : home + "/Music/vChainBench/models/beat_this_final0_T600_fp16.mlpackage";
                std::string err;
                if (!mNet.load(model, home + "/Music/vChainBench/models/cache", &err)) fprintf(stderr, "BeatNet: %s\n", err.c_str());
            }
        }
    }
    void process(const float* hop, uint32_t n, int64_t capture, int64_t, LinkPort& link) override {
        if (!mNN.empty()) deliverNN(capture);
        if (mLive) runLiveNN(hop, n, capture);
        mEngine->process(hop, n, capture, link);
        const auto& s = mEngine->state();
        mView.state = int(s.state);
        mView.displayBpm = s.displayBpm;
        mView.barLocked = s.barLocked;
        mView.downbeatConfidence = s.downbeatConfidence;
        mView.family = int(s.family);
        mView.events = s.events;
    }
    PipelineView view() const override { return mView; }
private:
    // Hands the NN thread's results to the engine as the app would: a window ending at tEnd arrives 50 ms later
    // (inference + hand-off); NNBeatMerger (VChainDSP, shared with the app) averages each beat over the windows that
    // see it and hands it on once.
    void deliverNN(int64_t capture) {
        double now = (capture - kBenchBaseUs) / 1e6;
        while (mNext < mNN.size() && mNN[mNext].tEnd + 0.05 <= now) {
            double tEnd = mNN[mNext].tEnd;
            size_t start = mNext;
            int64_t beats[256];
            int n = 0;
            for (; mNext < mNN.size() && mNN[mNext].tEnd == tEnd; mNext++)
                if (mNN[mNext].kind == 0 && n < 256) beats[n++] = kBenchBaseUs + int64_t(std::llround(mNN[mNext].time * 1e6));
            Onset out[64];
            int64_t tEndUs = kBenchBaseUs + int64_t(std::llround(tEnd * 1e6));
            int k = mMerger.addWindow(tEndUs, beats, n, out, 64);
            if (k) mEngine->addExternalBeats(out, k);
            int nd = 0;
            for (size_t j = start; j < mNext; j++)
                if (mNN[j].kind == 1 && nd < 256) beats[nd++] = kBenchBaseUs + int64_t(std::llround(mNN[j].time * 1e6));
            k = mDownMerger.addWindow(tEndUs, beats, nd, out, 64);
            int64_t dt[64];
            for (int j = 0; j < k; j++) dt[j] = out[j].t;
            if (k) mEngine->addExternalDownbeats(dt, k);
        }
    }
    NNBeatMerger mDownMerger;
    NNBeatMerger mMerger;

    // The app's NN chain, synchronously: LogMel on every hop; every 50 frames (1 s) the last 600 frames through Core ML,
    // peaks picked, merged into beats. (In the app the prediction runs on its own thread and arrives ~50 ms later.)
    void runLiveNN(const float* hop, uint32_t n, int64_t capture) {
        if (!mNet.ready()) return;
        if (mT0 < 0) mT0 = capture;
        float buf[LogMel::kBands * 8];
        int k = mLogMel.process(hop, n, buf, 8);
        for (int i = 0; i < k; i++) {
            std::copy(mFrames.begin() + LogMel::kBands, mFrames.end(), mFrames.begin());
            std::copy(buf + i * LogMel::kBands, buf + (i + 1) * LogMel::kBands, mFrames.end() - LogMel::kBands);
            mFramesDone++;
            if (mFramesDone % 50 != 0 || mFramesDone < 50) continue;
            float beatL[BeatNet::kFrames], downL[BeatNet::kFrames];
            auto c0 = std::chrono::steady_clock::now();
            if (!mNet.predict(mFrames.data(), beatL, downL)) continue;
            mInferMs.push_back(std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - c0).count());
            double peaks[256];
            int np = pickNNPeaks(beatL, BeatNet::kFrames, peaks, 256);
            int64_t beats[256];
            int nb = 0;
            const int64_t first = mFramesDone - BeatNet::kFrames; // frame index of the window's first frame
            for (int p = 0; p < np; p++) {
                double f = first + peaks[p];
                if (f < 0 || f < first + 6) continue; // padding before the start / the left border
                beats[nb++] = mT0 + int64_t(std::llround(f * 1e6 / 50.0));
            }
            int64_t tEnd = mT0 + int64_t(std::llround((mFramesDone - 1) * 1e6 / 50.0));
            Onset out[64];
            int m = mMerger.addWindow(tEnd, beats, nb, out, 64);
            if (m) mEngine->addExternalBeats(out, m);
            int nd = pickNNPeaks(downL, BeatNet::kFrames, peaks, 256), md = 0;
            for (int p = 0; p < nd; p++) {
                double f = first + peaks[p];
                if (f >= 0 && f >= first + 6) beats[md++] = mT0 + int64_t(std::llround(f * 1e6 / 50.0));
            }
            m = mDownMerger.addWindow(tEnd, beats, md, out, 64);
            int64_t dt[64];
            for (int j = 0; j < m; j++) dt[j] = out[j].t;
            if (m) mEngine->addExternalDownbeats(dt, m);
        }
    }
public:
    ~BeatPipeline() override {
        if (!mInferMs.empty()) {
            std::vector<double> v = mInferMs;
            std::sort(v.begin(), v.end());
            fprintf(stderr, "BeatNet: %zu predictions, median %.1f ms, p95 %.1f ms\n", v.size(), v[v.size() / 2], v[size_t(v.size() * 0.95)]);
        }
    }
private:
    bool mLive = false;
    BeatNet mNet;
    LogMel mLogMel;
    std::vector<float> mFrames;
    int64_t mFramesDone = 0, mT0 = -1;
    std::vector<double> mInferMs;

    std::string mNNFile;
    std::vector<NNEvent> mNN;
    size_t mNext = 0;
    bool mHybrid = false;
    std::unique_ptr<BeatEngine> mEngine;
    PipelineView mView;
};
} // namespace

std::unique_ptr<Pipeline> makePipeline(const std::string& name, const std::string& nnFile) {
    if (name == "tempo-phase") return std::make_unique<BeatPipeline>();
    if (name == "hy-tempo-phase") return std::make_unique<BeatPipeline>(nnFile, true);
    if (name == "live-hy-tempo-phase") return std::make_unique<BeatPipeline>("", true, true);
    return nullptr;
}
