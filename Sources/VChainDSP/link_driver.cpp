// SPDX-License-Identifier: GPL-3.0-or-later
#include "link_driver.h"
#include <algorithm>
#include <cmath>

namespace {
constexpr double kQuantum = kLinkQuantum;
// Phase steering (phaseStep), per locked grid beat. e = Link's phase error in beats (> 0 = Link is ahead).
constexpr float kMinStability = 0.1f;   // a poorer fit holds the phase (the lock already needs a good one)
constexpr double kForceBeats = 0.25;    // a jump only when Link is more than this off (first lock / new tempo)
constexpr double kStickyBeats = 0.4;    // near half a beat the sign flips from beat to beat: keep the pull's way
constexpr double kPullSignBeats = 0.05; // the pull's direction is remembered above this
constexpr double kPullGain = 0.5;       // pulling in: tempo x (1 - kPullGain * e) ...
constexpr double kPullMax = 0.03;       // ... clamped to ±3 %
constexpr double kPullDeadbandUs = 5000; // ... and no pull within 5 ms
constexpr double kNudge = 0.002;        // locked: a fixed 0.2 % nudge ...
constexpr double kNudgeStartUs = 8000;  // ... that starts above 8 ms ...
constexpr double kNudgeStopUs = 1000;   // ... and runs until the error is under 1 ms
constexpr double kDriftUs = 20000;      // off by more: pull in again; on it for kGoodBeats beats: pulled in
constexpr int kGoodBeats = 4;
} // namespace

void LinkDriver::reset() {
    int64_t offset = mOffsetUs;
    *this = LinkDriver();
    mOffsetUs = offset;
}

void LinkDriver::rebase(int64_t now, LinkPort& link) {
    mExpTempo = link.tempo();
    mExpBeat = link.beatAtTime(now, kQuantum);
    mExpT = now;
    mHaveBase = true;
}

void LinkDriver::commitTempo(double bpm, int64_t now, LinkPort& link) {
    link.setTempo(bpm, now);
    rebase(now, link);
}

uint8_t LinkDriver::update(int64_t now, BeatTracker& tr, LinkPort& link) {
    uint8_t ev = 0;
    // Foreign edits: Link moved in a way vChain's own writes don't explain.
    size_t peers = link.numPeers();
    if (!mHaveBase || peers != mPeers) {
        mPeers = peers;
        rebase(now, link);
    } else {
        double expect = mExpBeat + double(now - mExpT) * mExpTempo / 60e6;
        if (std::fabs(link.tempo() - mExpTempo) > 0.01 || std::fabs(link.beatAtTime(now, kQuantum) - expect) > 0.02) {
            ev |= EvForeign;
            rebase(now, link);
            double beat = tr.committed().beatUs > 0 ? tr.committed().beatUs : 500000;
            mNoForceUntil = now + int64_t(8 * beat);
            mForcePending = false; // a forced jump never answers someone's edit
        }
    }

    ev |= tempoStep(now, tr, link);
    link.flush();
    return ev;
}

double LinkDriver::displayTempo() const {
    if (mShown > 0) return mShown; // set only after the driver's first lock (any tracker, hybrid included)
    return mCoarseBpm > 1 && mCoarseConf >= 0.15f ? mCoarseBpm : 0;
}

// The tempo: Link gets the committed grid tempo, smoothed over ~20 beats and rounded to 0.01 BPM, re-committed only
// when it moves by >= 0.03 BPM. Before the first lock, aubio's tempo (rounded to 0.1, changes >= 0.5 BPM, at most
// every 2 s) so Link is never stuck at 120. Phase steering (phaseStep) and the bar move run from here.
uint8_t LinkDriver::tempoStep(int64_t now, BeatTracker& tr, LinkPort& link) {
    uint8_t ev = 0;
    auto commitIfNeeded = [&](double bpm, double tol) {
        if (bpm > 1 && std::fabs(link.tempo() - bpm) > tol) { commitTempo(bpm, now, link); ev |= EvCommit; }
    };
    // The driver's first lock: the tracker's lock event, or (hybrid) a tracker that locked while it was passive, whose
    // event the engine dropped, and has since become the active one.
    bool lockEvent = tr.takeLockEvent();
    bool firstLock = mBase <= 0 && (lockEvent || tr.state() == BeatState::Locked);
    if (firstLock) {
        mSmooth = tr.committed().bpm();
        mBase = std::round(mSmooth * 100) / 100;
        mLastJudged = tr.committed().beatAtOrBefore(now);
        commitIfNeeded(mBase, 0.001);
        mForcePending = true;
        mPullIn = true;
        mGoodBeats = 0;
    }
    // Before the driver's first lock: aubio. Not "the tracker never locked": in the hybrid the arbiter can hand over a
    // tracker that has not locked yet, and the last locked tempo must hold then too.
    if (mBase <= 0) {
        double c = std::round(mCoarseBpm * 10) / 10;
        if (c > 1 && mCoarseConf >= 0.15f && std::fabs(c - mLastFallback) >= 0.5 &&
            (mLastSettlingCommit < 0 || now - mLastSettlingCommit > 2000000)) {
            mLastFallback = c;
            mLastSettlingCommit = now;
            commitIfNeeded(c, 0.001);
        }
        return ev;
    }
    // After the first lock the tempo only moves while the tracker is locked: holding, settling and searching keep the
    // last locked tempo (it would wander in breakdowns), and a relock never snaps it.
    if (tr.state() == BeatState::Locked) {
        const Grid& g = tr.committed();
        double tc = mTempoSource > 1 ? mTempoSource : g.bpm();
        int64_t latest = g.beatAtOrBefore(now);
        if (latest - mLastJudged > int64_t(g.beatUs / 2)) { // once per beat
            mLastJudged = latest;
            double dev = tc / mSmooth - 1;
            if (std::fabs(dev) <= 0.004) {
                mPendingBeats = 0; mRampBeats = 0;
                mSmooth += 0.05 * (tc - mSmooth); // ~20-beat smoothing of fit jitter
            } else if (std::fabs(dev) <= 0.015) {
                // A DJ pitch ramp: a small deviation that keeps one direction for 8 beats is followed quickly.
                mPendingBeats = 0;
                int sign = dev > 0 ? 1 : -1;
                mRampBeats = (sign == mRampSign) ? mRampBeats + 1 : 1;
                mRampSign = sign;
                if (mRampBeats >= 8) mSmooth += 0.3 * (tc - mSmooth);
            } else {
                // A jump (new track, or a wrong grid such as 5:4): adopt it only once it has held for 16 locked
                // beats, and for four-on-the-floor only if aubio agrees up to an octave.
                mRampBeats = 0;
                if (mPendingBeats == 0 || std::fabs(tc / mPending - 1) > 0.008) { mPending = tc; mPendingBeats = 0; }
                mPending += 0.2 * (tc - mPending);
                bool aubioOk = true;
                if (tr.family() == GrooveFamily::FourFour && mCoarseBpm > 1) {
                    auto fold = [](double b) { while (b >= 150) b /= 2; while (b < 75) b *= 2; return b; };
                    double r = fold(mPending) / fold(mCoarseBpm);
                    aubioOk = std::fabs(r - 1) < 0.04 || std::fabs(r - 2) < 0.08 || std::fabs(r - 0.5) < 0.02;
                }
                if (++mPendingBeats >= 16 && aubioOk) {
                    mSmooth = mPending; mPendingBeats = 0;
                    mForcePending = true; // a new track: one phase jump is allowed
                    mPullIn = true;
                }
            }
            if (std::fabs(mSmooth - mBase) >= 0.03) mBase = std::round(mSmooth * 100) / 100;
            phaseStep(now, latest, tr, link, ev);
        }
    } else {
        mPendingBeats = 0;
        mNudge = 1; // holding / unlocked: hold the phase, no steering
    }
    barMoveStep(now, tr, link, ev);
    mPrevNow = now;
    // The shown value (0.1 BPM on the tag) moves only when the base is more than 0.06 % (at least 0.07 BPM) away from it:
    // 0.075 at 125, 0.105 at 175 (DnB fits wander a few hundredths more).
    if (mShown <= 0 || std::fabs(mBase - mShown) > std::max(0.07, 0.0006 * mBase)) mShown = std::round(mBase * 10) / 10;
    // Locked or holding: keep Link at the base tempo (also takes over again after someone's edit).
    double target = std::round(mBase * mNudge * 1000) / 1000;
    if (now - mLastBaseCommit > 500000 || std::fabs(link.tempo() - target) >= 0.005) {
        double before = link.tempo();
        commitIfNeeded(target, 0.005);
        if (std::fabs(before - target) > 0.005) { mLastBaseCommit = now; if (mNudge != 1) ev |= EvNudge; }
    }
    return ev;
}

// Phase steering, once per tracker beat while locked: Link's phase at the grid's latest beat, pulled in
// with tempo nudges (up to 3 % after a lock, then fixed 0.2 % corrections from 8 ms down to 1 ms). Only while the
// grid is confident; otherwise hold. One jump (> 1/4 beat off) only at the first lock or a new tempo.
void LinkDriver::phaseStep(int64_t now, int64_t latest, const BeatTracker& tr, LinkPort& link, uint8_t& ev) {
    const Grid& g = tr.committed();
    if (tr.stability() < kMinStability) { mNudge = 1; return; }
    int64_t tb = latest - mOffsetUs;
    double L = link.beatAtTime(tb, kQuantum);
    double e = L - std::round(L); // beats; > 0 = Link is ahead
    double eUs = e * g.beatUs;
    if (mForcePending) {
        mForcePending = false;
        // Without capture time stamps the jump lands late by the input latency, but so would the nudges: the jump is
        // still the better start (a nudge would need many beats for a quarter beat); capture time stamps and the beat
        // offset take care of the latency.
        if (std::fabs(e) > kForceBeats && now >= mNoForceUntil) {
            link.forceBeatAtTime(std::round(L), tb, kQuantum);
            rebase(now, link);
            ev |= EvForcePhase;
            e = 0; eUs = 0;
        }
    }
    // Near half a beat the error's sign flips from beat to beat: keep pulling the way we started.
    if (std::fabs(e) > kStickyBeats && mPullSign != 0) e = mPullSign * std::fabs(e);
    mPullSign = std::fabs(e) > kPullSignBeats ? (e > 0 ? 1 : -1) : 0;
    eUs = e * g.beatUs;
    double nudge = 1;
    if (mPullIn) {
        if (std::fabs(eUs) > kPullDeadbandUs) nudge = 1 - std::clamp(kPullGain * e, -kPullMax, kPullMax);
    } else {
        if (std::fabs(eUs) > kNudgeStartUs && mNudgeSign == 0) mNudgeSign = e > 0 ? 1 : -1;
        else if (mNudgeSign && (std::fabs(eUs) < kNudgeStopUs || (e > 0) != (mNudgeSign > 0))) mNudgeSign = 0;
        if (mNudgeSign) nudge = 1 - mNudgeSign * kNudge;
    }
    if (std::fabs(eUs) < kDriftUs) { if (++mGoodBeats >= kGoodBeats) mPullIn = false; } else mGoodBeats = 0;
    if (std::fabs(eUs) > kDriftUs) { mPullIn = true; mNudgeSign = 0; }
    mNudge = nudge;
    // The 1 (Link's 1 = the music's downbeat): once the bar vote has been locked on the same position for 8 beats and the beat is on
    // the grid (< 20 ms), one whole-beat jump puts Link's beat 0 on the music's 1. At most every 30 s, never right
    // after a foreign edit; holding never gets here.
    if (mBar.locked && mBar.residue == mBarLastResidue) mBarStableBeats++;
    else mBarStableBeats = 0;
    mBarLastResidue = mBar.locked ? mBar.residue : -1;
    if (mBar.locked && mBar.residue > 0 && mBarStableBeats >= 8 && std::fabs(eUs) < kDriftUs && now >= mNoForceUntil &&
        (mLastBarForce < 0 || now - mLastBarForce > 30000000)) {
        // The shortest way (2: forward). Done at the next Link beat that becomes the new 1 (barMoveStep).
        mBarShift = mBar.residue == 1 ? -1 : (mBar.residue == 3 ? 1 : 2);
        mBarShiftUntil = now + int64_t(8 * g.beatUs);
        mLastBarForce = now;
        mBarStableBeats = 0;
    }
}

// A scheduled bar move, once per hop: a whole-beat shift of Link's beat count (the fraction is untouched, so beat
// times do not move), made in the hop where Link crosses the beat that becomes the new 1. The bar count then changes
// on the downbeat itself (at most one hop, ~11 ms, after it), not mid-bar.
void LinkDriver::barMoveStep(int64_t now, const BeatTracker& tr, LinkPort& link, uint8_t& ev) {
    if (mBarShift == 0) return;
    if (tr.state() != BeatState::Locked || now > mBarShiftUntil || mPrevNow <= 0) {
        if (tr.state() != BeatState::Locked || now > mBarShiftUntil) mBarShift = 0;
        return;
    }
    double Lp = link.beatAtTime(mPrevNow, kQuantum), Ln = link.beatAtTime(now, kQuantum);
    double k = std::floor(Ln);
    int bar = int(std::lround(k + mBarShift)) % 4;
    if (bar < 0) bar += 4;
    if (Lp < k && bar == 0) {
        link.forceBeatAtTime(Ln + mBarShift, now, kQuantum);
        rebase(now, link);
        mBarShift = 0;
        ev |= EvForceBar;
    }
}
