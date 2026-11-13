// SPDX-License-Identifier: GPL-3.0-or-later
#include "beat_tracker.h"
#include <algorithm>
#include <cmath>

namespace {
constexpr double kWindowUs = 10e6;
constexpr double kRefitUs = 250000;     // refit at least every 250 ms while onsets arrive
constexpr double kMaxRmsUs = 15000;
constexpr double kHoldingSearchUs = 60e6;
// No music vChain follows is faster than this: a faster reading is the double (hi-hats, a stale octave choice on a
// finer refit) and counts every second beat instead.
constexpr double kMaxBpm = 200;

double fold(double bpm) {
    if (bpm <= 1) return 0;
    while (bpm >= 150) bpm /= 2;
    while (bpm < 75) bpm *= 2;
    return bpm;
}
double phaseDist(int64_t a, int64_t b, double period) {
    double d = std::fmod(std::fabs(double(a - b)), period);
    return std::min(d, period - d);
}
} // namespace

int64_t Grid::beatAtOrBefore(int64_t t) const {
    if (beatUs <= 0) return t;
    return anchor + int64_t(std::floor(double(t - anchor) / beatUs) * beatUs);
}

void BeatTracker::reset() { *this = BeatTracker(); }

void BeatTracker::addOnsets(const Onset* o, int n) {
    for (int i = 0; i < n; i++) {
        if (o[i].cls == OnsetClass::Hat) continue;
        mRing[mHead] = o[i];
        mHead = (mHead + 1) % kRing;
        mCount = std::min(mCount + 1, kRing);
        mNewSinceFit++;
        // Judge the onset against the committed grid (locked / holding / searching after a lock).
        if (mCommitted.beatUs <= 0) continue;
        const Onset& on = o[i];
        // Snares (2 and 4) and four-on-the-floor kicks belong on whole beats; only backbeat kicks (DnB, breaks)
        // may sit on the half beat. Otherwise a track resumed half a beat off would pass as "on the grid".
        bool halfOk = on.cls == OnsetClass::Kick && mPhase.choice().family != GrooveFamily::FourFour; // NN beats: whole beats
        double unit = halfOk ? mCommitted.beatUs / 2 : mCommitted.beatUs;
        double x = double(on.t - mCommitted.anchor) / unit;
        double r = (x - std::round(x)) * unit;
        bool inlier = std::fabs(r) <= gateUs();
        mShare += 0.1f * ((inlier ? 1.0f : 0.0f) - mShare); // ~ the last 10 onsets
        if (inlier) {
            mInlierRun++;
            mLastInlier = std::max(mLastInlier, on.t);
            mOffGrid = 0;
        } else if (on.strength >= 0.5f) {
            mInlierRun = 0;
            mOffGridOffsets[mOffGrid % 4] = r / unit; // phase in units, compared circularly below
            if (mOffGrid == 0 && mChallengerStart < 0) mChallengerStart = on.t;
            mOffGrid++;
            if (mOffGrid >= 3) {
                // Hard cut: the off-grid hits share one offset (circular spread < 20 ms; a track resumed half a beat
                // late shows as +0.5 and -0.5 of a unit, the same phase).
                double sx = 0, sy = 0;
                int nOff = std::min(mOffGrid, 4);
                for (int k = 0; k < nOff; k++) { sx += std::cos(2 * M_PI * mOffGridOffsets[k]); sy += std::sin(2 * M_PI * mOffGridOffsets[k]); }
                double R = std::hypot(sx, sy) / nOff;                    // 1 = identical phases
                double spreadUs = std::sqrt(std::max(0.0, -2 * std::log(std::max(R, 1e-9)))) / (2 * M_PI) * unit;
                mChallengerHardCut = spreadUs < 20000;
            }
        }
    }
}

double BeatTracker::gateUs() const { return std::min(40000.0, mCommitted.beatUs / 8); }

bool BeatTracker::consistent(const Grid& a, const Grid& b, double tolUs) const {
    if (a.beatUs <= 0 || b.beatUs <= 0) return false;
    return std::fabs(a.beatUs / b.beatUs - 1) < 0.01 && phaseDist(a.anchor, b.anchor, b.beatUs) < tolUs;
}

BeatTracker::Candidate BeatTracker::evaluate(int64_t now, double approxStep, int64_t since, float pc, float ps,
                                             BeatPhase& phase) {
    Candidate c;
    Onset buf[kRing];
    int n = 0;
    for (int i = 0; i < mCount; i++) {
        const Onset& o = mRing[(mHead - mCount + i + kRing) % kRing];
        if (o.t >= since && o.t >= now - int64_t(kWindowUs) && o.t <= now) buf[n++] = o;
    }
    GridFit fit = fitGrid(buf, n, approxStep, now, kWindowUs);
    if (!fit.ok) return c;
    BeatChoice ch = phase.update(fit, buf, n, now, pc, ps);
    if (ch.k == 0) return c;
    c.grid = Grid{ch.k * fit.step, ch.beatAnchor};
    while (c.grid.bpm() > kMaxBpm) c.grid.beatUs *= 2; // the anchor stays a beat
    c.family = ch.family;
    c.decided = ch.decided;
    float minShare = ch.family == GrooveFamily::Backbeat ? 0.55f : 0.7f;
    c.ok = fit.inlierShare >= minShare && fit.residualRms < kMaxRmsUs && fit.spanUs >= 4 * c.grid.beatUs;
    mStability = c.ok ? float(fit.inlierShare * std::clamp(1.0 - fit.residualRms / kMaxRmsUs, 0.0, 1.0)) : 0.0f;
    return c;
}

void BeatTracker::lockOn(const Grid& g, int64_t now) {
    mCommitted = g;
    mState = BeatState::Locked;
    mLockEvent = true;
    mLastInlier = now;
    mShare = 1;
    mInlierRun = 3;
    mOffGrid = 0;
    mChallengerStart = mChallengerOkSince = -1;
    mConsistentSince = -1;
    mCoarseOffSince = -1;
    mGuardSince = -1;
}

void BeatTracker::tick(int64_t now, float coarseBpm, float pc, float ps) {
    bool refit = mNewSinceFit > 0 && (mNewSinceFit >= 2 || now - mLastTick >= int64_t(kRefitUs));
    if (refit) { mNewSinceFit = 0; mLastTick = now; }
    // The grid step from the onsets themselves; aubio's coarse tempo only when there are too few onsets.
    auto stepFor = [&](int64_t since) {
        Onset buf[kRing];
        int n = 0;
        for (int i = 0; i < mCount; i++) buf[n++] = mRing[(mHead - mCount + i + kRing) % kRing];
        // NN beats in the window: their median interval is the beat, the grid step its half.
        double nnT[kRing];
        int nnN = 0;
        for (int i = 0; i < n; i++)
            if (buf[i].cls == OnsetClass::Beat && buf[i].t >= since && buf[i].t <= now && now - buf[i].t < 8000000) nnT[nnN++] = double(buf[i].t);
        if (nnN >= 5) {
            std::sort(nnT, nnT + nnN);
            double iv[kRing];
            for (int i = 1; i < nnN; i++) iv[i - 1] = nnT[i] - nnT[i - 1];
            std::nth_element(iv, iv + (nnN - 1) / 2, iv + nnN - 1);
            double beat = iv[(nnN - 1) / 2];
            if (beat > 250000 && beat < 1100000) return beat / 2;
        }
        double s = estimateGridStep(buf, n, now, 8e6, since, coarseBpm > 1 ? fold(coarseBpm) : 0);
        return s > 0 ? s : (coarseBpm > 1 ? 15e6 / fold(coarseBpm) : 0);
    };

    if (mState == BeatState::Searching || mState == BeatState::Settling) {
        mState = (coarseBpm > 1 || mCount > 0) ? BeatState::Settling : BeatState::Searching;
        if (!refit) return;
        double step = stepFor(0);
        if (step <= 0) return;
        Grid prev = mCandidate;
        Candidate c = evaluate(now, step, 0, pc, ps, mPhase);
        if (!c.ok) { mConsistentSince = -1; return; }
        mCandidate = c.grid;
        if (mConsistentSince < 0 || !consistent(c.grid, prev, 15000)) mConsistentSince = now;
        if (c.decided && now - mConsistentSince >= int64_t(6 * c.grid.beatUs)) {
            mPhase.newLock();
            lockOn(c.grid, now);
        }
        return;
    }

    // Locked or holding.
    const double beat = mCommitted.beatUs;
    if (refit) {
        // Follow the committed grid (drift, DJ ramps) with fits that agree with it.
        Candidate c = evaluate(now, 15e6 / fold(mCommitted.bpm()), 0, pc, ps, mPhase);
        if (c.ok && consistent(c.grid, mCommitted, gateUs())) {
            mCommitted = c.grid;
        } else if (c.ok && c.decided && phaseDist(c.grid.anchor, mCommitted.anchor, std::min(c.grid.beatUs, beat)) < gateUs() &&
                   (std::fabs(c.grid.beatUs / beat - 2) < 0.02 || std::fabs(c.grid.beatUs / beat - 0.5) < 0.01)) {
            lockOn(c.grid, now); // BeatPhase changed the octave after its hysteresis
            return;
        }
        // A possible new grid (hard cut, new track, different tempo).
        if (mChallengerStart >= 0) {
            if (mChallengerOkSince < 0 && mOffGrid == 0 && mInlierRun >= 3) {
                mChallengerStart = -1; // the off-grid hits were a passing thing (spinback, fill)
            } else {
                double step = stepFor(mChallengerStart);
                if (step <= 0) step = 15e6 / fold(mCommitted.bpm());
                Candidate ch = evaluate(now, step, mChallengerStart, pc, ps, mChallengerPhase);
                if (!ch.ok) ch = evaluate(now, 15e6 / fold(mCommitted.bpm()), mChallengerStart, pc, ps, mChallengerPhase);
                if (ch.ok && !consistent(ch.grid, mCommitted, gateUs())) {
                    if (mChallengerOkSince < 0 || !consistent(ch.grid, mCandidate, 15000)) mChallengerOkSince = now;
                    mCandidate = ch.grid;
                    double need = (mChallengerHardCut ? 4 : 8) * ch.grid.beatUs;
                    if (ch.decided || mChallengerHardCut) {
                        if (now - mChallengerOkSince >= int64_t(need)) {
                            mPhase = mChallengerPhase;
                            mPhase.newLock();
                            mChallengerPhase.reset();
                            lockOn(ch.grid, now);
                            return;
                        }
                    }
                } else if (ch.ok) {
                    mChallengerStart = -1; // it was the committed grid after all
                    mChallengerOkSince = -1;
                }
            }
        }
    }
    if (mChallengerStart < 0) { mChallengerPhase.reset(); mChallengerOkSince = -1; }

    const double share = mShare;
    int64_t noDrums = int64_t(std::max(4 * beat, 2e6));
    if (mState == BeatState::Locked) {
        if (now - mLastInlier > noDrums || share < 0.4) {
            mState = BeatState::Holding;
            mHoldingSince = now;
        }
    } else { // holding
        if (now - mLastInlier < int64_t(beat) && mInlierRun >= 3 && mChallengerStart < 0) {
            mState = BeatState::Locked; // the drums are back on the counted grid: nudge only, no new lock
        } else if (now - mHoldingSince > int64_t(kHoldingSearchUs)) {
            mState = BeatState::Searching;
        }
    }
    // (No exit on aubio's coarse tempo moving: in a pad breakdown it drifts while there is nothing to contradict
    // the held grid. New grids come through the challenger, from onsets.)
    // Octave guard from aubio: while locked, the committed tempo and aubio's must agree up to an octave (DnB at 174
    // vs aubio's 87 is fine). A 5:4, 4:3 or 3:2 disagreement for 8 s means a wrong grid: search again. Only for
    // four-on-the-floor grooves: on breakbeats aubio itself is off (jungle at 170 reads 114).
    if (mState == BeatState::Locked && coarseBpm > 1 && mPhase.choice().family == GrooveFamily::FourFour) {
        double r = fold(mCommitted.bpm()) / fold(coarseBpm); // in (0.5, 2)
        bool agree = std::fabs(r - 1) < 0.04 || std::fabs(r - 2) < 0.08 || std::fabs(r - 0.5) < 0.02;
        if (!agree) {
            if (mGuardSince < 0) mGuardSince = now;
            if (now - mGuardSince > 8000000) { mState = BeatState::Searching; mGuardSince = -1; }
        } else {
            mGuardSince = -1;
        }
    }
    if (mState == BeatState::Searching) {
        mCandidate = Grid{};
        mConsistentSince = -1;
        mPhase.newLock();
    }
    if (mState != BeatState::Locked) mStability = 0;
}
