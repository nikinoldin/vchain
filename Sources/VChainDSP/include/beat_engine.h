// SPDX-License-Identifier: GPL-3.0-or-later
// The beat pipeline the engine and the bench share: hop in (with its capture time), Link written.
// BpmDetector (aubio) gives the coarse tempo; DrumOnsets + BeatTracker give the committed grid (with the NN front
// end's beats: a second tracker and an arbiter); BarVote finds the 1; LinkDriver writes Link.
#pragma once
#include "bar_vote.h"
#include "beat_tracker.h"
#include "bpm_detector.h"
#include "drum_onsets.h"
#include "link_driver.h"
#include "link_port.h"
#include <memory>

struct BeatEngineState {
    BeatState state = BeatState::Searching;
    float displayBpm = 0;      // what the tag shows: Link's base tempo, or aubio's before the first lock
    float coarseBpm = 0, aubioConfidence = 0;
    bool barLocked = false;
    float downbeatConfidence = 0;
    GrooveFamily family = GrooveFamily::Unknown;
    uint8_t events = 0;        // LinkEvent bits of the last hop
};

class BeatEngine {
public:
    // Samples per process() call: the engine and the bench feed hops of this size (aubio's tempo hop).
    static constexpr uint32_t kHopSize = 512;
    explicit BeatEngine(uint32_t sampleRate);
    void reset(uint32_t sampleRate);
    void setGenre(int index);
    void setBeatOffsetMs(float ms) { mDriver.setBeatOffsetUs(int64_t(ms * 1000)); }
    // captureUs: capture time of hop[0] on the Link clock (the processing time while there are no capture time stamps).
    void process(const float* hop, uint32_t n, int64_t captureUs, LinkPort& link);
    // Beats from the neural network front end (OnsetClass::Beat, capture times), handed in as they arrive. Without
    // hybrid mode they join the one tracker; in hybrid mode they feed the second tracker only.
    void addExternalBeats(const Onset* beats, int n) { (mHybrid ? mNNTracker : mTracker).addOnsets(beats, n); mHaveNN = true; }
    // Downbeats from the NN front end (merged, capture times): votes for where the 1 is (BarVote).
    void addExternalDownbeats(const int64_t* t, int n) { for (int i = 0; i < n; i++) mBarVote.addDownbeat(t[i]); }
    // Hybrid: two trackers (drum hits only; drum hits + NN beats) and an arbiter choosing whose grid drives Link.
    void setHybrid(bool on) { mHybrid = on; }
    // 0 = the drum tracker drives Link, 1 = the NN tracker.
    int activeTracker() const { return mActive; }
    const BeatEngineState& state() const { return mState; }

private:
    void arbitrate(int64_t now);
    double kickSupport(const Grid& g, int64_t now) const;
    BeatTracker& active() { return mActive == 1 ? mNNTracker : mTracker; }
    uint32_t mSampleRate;
    int mGenre = 0;
    std::unique_ptr<BpmDetector> mDetector;
    DrumOnsets mOnsets;
    BeatTracker mTracker;
    BeatTracker mNNTracker;
    BarVote mBarVote;
    bool mHybrid = false, mHaveNN = false;
    int mActive = 0, mWant = 0, mWantCount = 0;
    int64_t mLastArbitration = 0;
    int64_t mKicks[64] = {};
    int mKickHead = 0;
    LinkDriver mDriver;
    BeatEngineState mState;
};
