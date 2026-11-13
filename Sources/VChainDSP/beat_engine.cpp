// SPDX-License-Identifier: GPL-3.0-or-later
#include "beat_engine.h"
#include "genre.h"
#include <algorithm>
#include <cmath>

BeatEngine::BeatEngine(uint32_t sampleRate) : mSampleRate(sampleRate) { reset(sampleRate); }

void BeatEngine::reset(uint32_t sampleRate) {
    mSampleRate = sampleRate;
    if (!mDetector) mDetector = std::make_unique<BpmDetector>(sampleRate, kHopSize);
    else mDetector->reinit(sampleRate, kHopSize);
    mDetector->setGenrePreset(mGenre);
    mOnsets.reset(sampleRate);
    mTracker.reset();
    mNNTracker.reset();
    mBarVote.reset();
    mHaveNN = false;
    mActive = mWant = mWantCount = 0;
    mLastArbitration = 0;
    std::fill(std::begin(mKicks), std::end(mKicks), 0);
    mDriver.reset();
    mState = {};
}

void BeatEngine::setGenre(int index) {
    mGenre = index;
    if (mDetector) mDetector->setGenrePreset(index);
}

void BeatEngine::process(const float* hop, uint32_t n, int64_t captureUs, LinkPort& link) {
    mDetector->process(hop, n);
    Onset found[32];
    int k = mOnsets.process(hop, n, captureUs, found, 32);
    mTracker.addOnsets(found, k);
    for (int i = 0; i < k; i++)
        if (found[i].cls == OnsetClass::Kick && found[i].strength >= 0.5f) { mKicks[mKickHead] = found[i].t; mKickHead = (mKickHead + 1) % 64; }
    const auto& g = getGenrePresets()[mGenre];
    int64_t end = captureUs + int64_t(n * 1e6 / mSampleRate);
    mTracker.tick(end, mDetector->bpm(), g.centerBpm, g.sigma);
    if (mHybrid) {
        mNNTracker.addOnsets(found, k);
        mNNTracker.tick(end, mDetector->bpm(), g.centerBpm, g.sigma);
        arbitrate(end);
        (mActive == 1 ? mTracker : mNNTracker).takeLockEvent(); // the passive tracker's lock events don't count
    }
    BeatTracker& tr = mHybrid ? active() : mTracker;
    mDriver.setCoarse(mDetector->bpm(), mDetector->confidence());
    if (mHybrid) {
        // Tempo from the drum tracker whenever it agrees with the active grid (within 1 %, up to an octave): it is the
        // steadier fit.
        double src = 0;
        const BeatState ds = mTracker.state();
        if (mActive == 1 && (ds == BeatState::Locked || ds == BeatState::Holding) && tr.committed().beatUs > 0) {
            // ... also an octave apart (the drum rules read DnB at 87): its fit, doubled or halved.
            double r = tr.committed().bpm() / mTracker.committed().bpm();
            for (double m : {1.0, 2.0, 0.5})
                if (std::fabs(r / m - 1) < 0.01) { src = mTracker.committed().bpm() * m; break; }
        }
        mDriver.setTempoSource(src);
    }
    if (tr.state() == BeatState::Locked) {
        const BarState& bar = mBarVote.update(link, end, tr.committed().beatUs);
        mDriver.setBar(bar);
    } else {
        mDriver.setBar(BarState{mBarVote.state().locked && tr.state() == BeatState::Holding, mBarVote.state().residue,
                                mBarVote.state().confidence}); // holding keeps the bar it had
    }
    mState.events = mDriver.update(end, tr, link);
    // barLocked = Link's beat 0 is the music's 1 (the vote is locked on Link's beat 0): what the fish leap may claim.
    mState.barLocked = mDriver.bar().locked && mDriver.bar().residue == 0 &&
                       (tr.state() == BeatState::Locked || tr.state() == BeatState::Holding);
    mState.downbeatConfidence = mDriver.bar().confidence;
    mState.state = tr.state();
    mState.displayBpm = float(mDriver.displayTempo());
    mState.coarseBpm = mDetector->bpm();
    mState.aubioConfidence = mDetector->confidence();
    mState.family = tr.family();
}

// Share of the recent strong kicks (last 8 s) within 35 ms of the grid's whole beats.
double BeatEngine::kickSupport(const Grid& g, int64_t now) const {
    if (g.beatUs <= 0) return 0;
    int n = 0, on = 0;
    for (int64_t t : mKicks) {
        if (t <= 0 || now - t > 8000000 || t > now) continue;
        n++;
        double x = double(t - g.anchor) / g.beatUs;
        if (std::fabs(x - std::round(x)) * g.beatUs < 35000) on++;
    }
    return n >= 6 ? double(on) / n : -1;
}

// Hybrid arbiter, twice a second. Agreeing grids: the drum grid (sub-frame precise). An octave disagreement: the NN
// (it is right on DnB where the drum rules fail). Any other disagreement: the NN, unless the drum grid is clearly
// four-on-the-floor and explains the kicks much better (the NN sits a quarter beat off on some techno). A switch needs
// 8 consecutive verdicts (~4 s).
void BeatEngine::arbitrate(int64_t now) {
    if (now - mLastArbitration < 500000) return;
    mLastArbitration = now;
    auto usable = [](const BeatTracker& t) { return t.state() == BeatState::Locked || t.state() == BeatState::Holding; };
    int want = mActive;
    bool d = usable(mTracker), nn = usable(mNNTracker) && mHaveNN;
    if (d && !nn) want = 0;
    else if (nn && !d) want = 1;
    else if (d && nn) {
        const Grid& a = mTracker.committed();
        const Grid& b = mNNTracker.committed();
        double ratio = b.beatUs / a.beatUs;
        double gate = std::min(40000.0, a.beatUs / 8);
        double pd = std::fmod(std::fabs(double(a.anchor - b.anchor)), a.beatUs);
        pd = std::min(pd, a.beatUs - pd);
        bool samePeriod = std::fabs(ratio - 1) < 0.01;
        if (samePeriod && pd < gate) want = 0;
        else if (!samePeriod && (std::fabs(ratio - 2) < 0.04 || std::fabs(ratio - 0.5) < 0.01)) want = 1;
        else {
            double ks = kickSupport(a, now), kn = kickSupport(b, now);
            bool drumClear = mTracker.family() == GrooveFamily::FourFour && ks >= 0.6 && ks > kn + 0.25;
            want = drumClear ? 0 : 1;
        }
    }
    if (want == mActive) { mWantCount = 0; return; }
    if (want != mWant) { mWant = want; mWantCount = 0; }
    if (++mWantCount >= 8) { mActive = want; mWantCount = 0; }
}
