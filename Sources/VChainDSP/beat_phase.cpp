// SPDX-License-Identifier: GPL-3.0-or-later
#include "beat_phase.h"
#include <algorithm>
#include <cmath>

namespace {
constexpr double kWindowUs = 12e6;
constexpr int kMaxBeats = 256;
}

void BeatPhase::reset() { mChoice = {}; mStableSince = 0; mContraSince = -1; mLockedOnce = false; }
void BeatPhase::newLock() { mChoice.decided = false; mLockedOnce = false; mContraSince = -1; }

BeatPhase::Eval BeatPhase::evaluate(const GridFit& fit, const Onset* on, int n, int k, int64_t now) const {
    Eval e{k, 0, GrooveFamily::Unknown, false, false, 0};
    const double g = fit.step, gate = std::min(40000.0, g / 4);
    double score[8] = {}, scoreBb[8] = {}, nn[8] = {};
    for (int i = 0; i < n; i++) {
        if (on[i].cls == OnsetClass::Hat || on[i].t < now - kWindowUs || on[i].t > now) continue;
        double x = double(on[i].t - fit.origin) / g;
        double m = std::round(x);
        if (std::fabs((x - m) * g) > gate) continue;
        int r = int(((long long)m % k + k) % k);
        double w = 0.3 + std::min(1.0f, on[i].strength);
        score[r] += w;
        scoreBb[r] += on[i].cls == OnsetClass::Snare ? 1.5 * w : w;
        if (on[i].cls == OnsetClass::Beat) nn[r] += 1;
    }
    // Beat residue (backbeat weighting first; the families are judged on it).
    int best = 0, bestBb = 0;
    for (int r = 1; r < k; r++) { if (score[r] > score[best]) best = r; if (scoreBb[r] > scoreBb[bestBb]) bestBb = r; }
    auto stats = [&](int r, double& kickShare, double& snareEven, double& snareOdd) {
        // Distinct beats (grid index ≡ r mod k) in the window with a kick / a snare, by beat parity.
        bool kick[kMaxBeats] = {}, snare[kMaxBeats] = {};
        double beatUs = k * g;
        int nb = std::min(kMaxBeats, int(std::min(kWindowUs, fit.spanUs + beatUs) / beatUs));
        if (nb < 4) { kickShare = snareEven = snareOdd = 0; return; }
        int64_t last = fit.origin + int64_t(std::llround(r * g)); // a beat near now
        while (last > now) last -= int64_t(beatUs);
        for (int i = 0; i < n; i++) {
            if (on[i].cls == OnsetClass::Hat) continue;
            double q = double(last - on[i].t) / beatUs;
            double qi = std::round(q);
            if (qi < 0 || qi >= nb || std::fabs((q - qi) * beatUs) > gate) continue;
            if (on[i].cls == OnsetClass::Beat) continue;
            (on[i].cls == OnsetClass::Kick ? kick : snare)[int(qi)] = true;
        }
        int kc = 0, se = 0, so = 0;
        for (int q = 0; q < nb; q++) { kc += kick[q]; (q % 2 ? so : se) += snare[q]; }
        kickShare = double(kc) / nb;
        snareEven = se / std::ceil(nb / 2.0);
        snareOdd = so / std::floor(nb / 2.0);
    };
    // With NN beats in the window they decide which grid positions are beats.
    double nnTotal = 0;
    for (int r = 0; r < k; r++) nnTotal += nn[r];
    if (nnTotal >= 4) {
        int bn = 0;
        for (int r = 1; r < k; r++) if (nn[r] > nn[bn]) bn = r;
        best = bestBb = bn;
        e.nnShare = nn[bn] / nnTotal;
    }
    double ks, se, so;
    stats(best, ks, se, so);
    e.kickOk = ks >= 0.8;
    double ks2, se2, so2;
    stats(bestBb, ks2, se2, so2);
    e.backbeatOk = std::max(se2, so2) >= 0.7 && std::min(se2, so2) < 0.3 && ks2 < 0.8;
    int r = e.kickOk ? best : bestBb;
    e.anchor = fit.origin + int64_t(std::llround(r * g));
    e.family = e.kickOk ? GrooveFamily::FourFour : e.backbeatOk ? GrooveFamily::Backbeat : GrooveFamily::Unknown;
    return e;
}

BeatChoice BeatPhase::update(const GridFit& fit, const Onset* on, int n, int64_t now, float priorCenter, float priorSigma) {
    if (!fit.ok) return mChoice;
    // Candidates: beat = k grid steps, k = 2, 4, 8 (fastest first), tempo within 60-180 BPM.
    Eval cand[3];
    int nc = 0;
    for (int k : {2, 4, 8}) {
        double bpm = 60e6 / (k * fit.step);
        if (bpm >= 60 && bpm <= 180) cand[nc++] = evaluate(fit, on, n, k, now);
    }
    if (nc == 0) return mChoice;
    // NN front end: the network names the beat directly, so the octave is the one whose beats it hits (all NN beats
    // on one residue); the drum rules only break a tie.
    for (int i = 0; i < nc; i++) if (cand[i].nnShare >= 0.8 && cand[i].k == 2) { cand[i].kickOk = true; break; }
    // Precedence: the fastest four-on-the-floor reading... unless a faster backbeat reading exists (DnB at 174 has
    // a kick on every beat of the 87 reading), then a backbeat, then the genre prior.
    const Eval* pick = nullptr;
    for (int i = 0; i < nc && !pick; i++) {
        if (cand[i].kickOk) pick = &cand[i];
        else if (cand[i].backbeatOk) pick = &cand[i];
    }
    bool unknown = !pick;
    if (!pick) {
        auto prior = [&](const Eval& e) {
            double d = 60e6 / (e.k * fit.step) - priorCenter;
            return std::exp(-0.5 * d * d / (priorSigma * priorSigma));
        };
        pick = &cand[0];
        for (int i = 1; i < nc; i++) if (prior(cand[i]) > prior(*pick)) pick = &cand[i];
    }
    const double beatUs = pick->k * fit.step;
    // Keep a choice's beats but place them on the newest fit (its anchor would drift with an old fit).
    auto reanchor = [&]() {
        double r = std::round(double(mChoice.beatAnchor - fit.origin) / fit.step);
        long long ri = ((long long)r % mChoice.k + mChoice.k) % mChoice.k;
        mChoice.beatAnchor = fit.origin + int64_t(std::llround(ri * fit.step));
    };
    auto sameBeat = [&](int64_t a, int64_t b) {
        double d = std::fmod(std::fabs(double(a - b)), beatUs);
        return std::min(d, beatUs - d) < fit.step / 2;
    };
    if (mChoice.k == 0) {
        mChoice = {pick->k, pick->anchor, pick->family, false};
        mStableSince = now;
        return mChoice;
    }
    bool sameOctave = pick->k == mChoice.k, samePhase = sameOctave && sameBeat(pick->anchor, mChoice.beatAnchor);
    if (sameOctave && samePhase) {
        mContraSince = -1;
        mChoice.beatAnchor = pick->anchor; // follow the fit
        if (!unknown) mChoice.family = pick->family;
        if (!mChoice.decided && now - mStableSince >= int64_t(6 * beatUs)) { mChoice.decided = true; mLockedOnce = true; }
        return mChoice;
    }
    // Contrary evidence. Unknown grooves never overturn a decided choice.
    if (mLockedOnce && unknown) { reanchor(); return mChoice; }
    if (!mLockedOnce) {
        mChoice = {pick->k, pick->anchor, pick->family, false};
        mStableSince = now;
        mContraSince = -1;
        return mChoice;
    }
    if (mContraSince < 0) mContraSince = now;
    double need = (sameOctave ? 16 : 64) * beatUs;
    reanchor();
    if (now - mContraSince >= int64_t(need)) {
        mChoice = {pick->k, pick->anchor, pick->family, true};
        mStableSince = now;
        mContraSince = -1;
    }
    return mChoice;
}
