// SPDX-License-Identifier: GPL-3.0-or-later
#include "bpm_module.h"
#include <CoreFoundation/CoreFoundation.h>
#include <algorithm>
#include <cstdlib>
#include <iostream>

static_assert(VC_BEATS_PER_BAR == kLinkQuantum, "the C API's bar is VChainDSP's Link quantum");

namespace {
// The bundled Core ML model (build.sh copies it into Contents/Resources), or $VCHAIN_NN_MODEL.
std::string nnModelPath() {
    if (const char* env = getenv("VCHAIN_NN_MODEL")) return env;
    std::string path;
    if (CFBundleRef b = CFBundleGetMainBundle()) {
        if (CFURLRef url = CFBundleCopyResourceURL(b, CFSTR("beat_this_final0_T600_fp16"), CFSTR("mlpackage"), nullptr)) {
            char buf[4096];
            if (CFURLGetFileSystemRepresentation(url, true, reinterpret_cast<UInt8*>(buf), sizeof buf)) path = buf;
            CFRelease(url);
        }
    }
    return path;
}
std::string nnCacheDir() {
    const char* home = getenv("HOME");
    return std::string(home ? home : "/tmp") + "/Library/Application Support/vChain/NN";
}
} // namespace

BpmModule::BpmModule() {}

BpmModule::~BpmModule() {
    if (enabled()) shutdown();
}

void BpmModule::init(uint32_t sampleRate, uint32_t) {
    mSampleRate = sampleRate;
    mEngine = std::make_unique<BeatEngine>(sampleRate);
    mEngine->setGenre(mGenreIndex);
    mEngine->reset(sampleRate);
    mEngine->setBeatOffsetMs(mBeatOffsetMs);
    mLink = std::make_unique<ableton::Link>(120.0);
    mLink->enable(true);
    mPort = std::make_unique<RealLinkPort>(*mLink);
    mHybridOn = false;
    std::string model = nnModelPath();
    if (!model.empty()) mNN.start(model, nnCacheDir());
    else std::cout << "[BpmModule] no Beat This! model bundled: drum-only" << std::endl;
    std::cout << "[BpmModule] Initialized" << std::endl;
}

void BpmModule::shutdown() {
    mNN.stop();
    mPort.reset();
    if (mLink) {
        mLink->enable(false);
        mLink.reset();
    }
    mEngine.reset();
    std::cout << "[BpmModule] Shutdown" << std::endl;
}

void BpmModule::reinit(uint32_t sampleRate, uint32_t) {
    mSampleRate = sampleRate;
    if (mEngine) mEngine->reset(sampleRate);
}

void BpmModule::setBeatOffsetMs(float ms) {
    mBeatOffsetMs = std::clamp(ms, -50.0f, 150.0f);
    if (mEngine) mEngine->setBeatOffsetMs(mBeatOffsetMs);
}

void BpmModule::setGenrePreset(int index) {
    mGenreIndex = index;
    if (mEngine) mEngine->setGenre(index);
}

void BpmModule::process(ModuleContext& ctx) {
    if (!mEngine || !mLink) return;

    // Latency compensation: the capture time of the hop's first sample (the input's time stamps, minus its fixed
    // latency), on Link's clock. Without time stamps (first buffers), the processing time.
    int64_t now = mLink->clock().micros().count();
    int64_t capture = now;
    mCompensated = ctx.captureValid;
    if (ctx.captureValid) {
        capture = mLink->clock().ticksToMicros(ctx.captureTicks).count() - int64_t(ctx.fixedLatencyUs);
        // A time stamp more than 1 s old or 0.5 s ahead (Bluetooth output latency is up to ~0.25 s) is not believable
        // (another clock, a stall): processing time.
        if (capture < now - 1'000'000 || capture > now + 500'000) { capture = now; mCompensated = false; }
    }
    if (mCompensated) {
        double delay = double(now - (capture + int64_t(ctx.count * 1e6 / std::max(1u, mSampleRate))));
        mInputDelayUs = mInputDelayUs == 0 ? delay : mInputDelayUs + 0.02 * (delay - mInputDelayUs);
        // Every 30 s, for measuring the real input path (launch the app from a terminal to see it).
        if (now - mLastDelayLog > 30'000'000) {
            mLastDelayLog = now;
            std::cout << "[BpmModule] latency: processing is " << mInputDelayUs / 1000.0
                      << " ms after the hop's last sample; fixed correction " << -ctx.fixedLatencyUs / 1000.0
                      << " ms (+ = output device after the capture, - = input device latency); beat offset "
                      << mBeatOffsetMs << " ms" << std::endl;
        }
    }
    // The NN front end: spectrogram here (cheap), the network on its own thread; its beats join the hybrid.
    mNN.pushHop(ctx.samples, ctx.count, capture, mSampleRate);
    if (mNN.ready()) {
        if (!mHybridOn) { mEngine->setHybrid(true); mHybridOn = true; std::cout << "[BpmModule] NN ready: hybrid" << std::endl; }
        Onset beats[64];
        int64_t downs[64];
        int nd = 0;
        int n = mNN.popBeats(beats, 64, downs, 64, &nd);
        if (n) mEngine->addExternalBeats(beats, n);
        if (nd) mEngine->addExternalDownbeats(downs, nd);
    }
    mEngine->process(ctx.samples, ctx.count, capture, *mPort);
    const BeatEngineState& s = mEngine->state();

    ctx.bpm = s.displayBpm;
}

float BpmModule::bpm() const { return mEngine ? mEngine->state().displayBpm : 0.0f; }

// The tag shows "settling" below 0.15 (BPMTagState.lockConfidence): a locked or holding beat grid counts as sure;
// before the first lock it's aubio's confidence.
float BpmModule::confidence() const {
    if (!mEngine) return 0.0f;
    const auto& s = mEngine->state();
    if (s.state == BeatState::Locked || s.state == BeatState::Holding) return 1.0f;
    return s.aubioConfidence;
}

int BpmModule::beatState() const { return mEngine ? int(mEngine->state().state) : 0; }
bool BpmModule::barLocked() const { return mEngine && mEngine->state().barLocked; }
int BpmModule::linkPeers() const { return mLink ? static_cast<int>(mLink->numPeers()) : 0; }

void BpmModule::linkPhase(double& phase, double& tempo) const {
    phase = 0;
    tempo = 0;
    if (!mLink) return;
    auto state = mLink->captureAppSessionState();
    auto now = mLink->clock().micros();
    phase = state.phaseAtTime(now, kQuantum);
    tempo = state.tempo();
}
