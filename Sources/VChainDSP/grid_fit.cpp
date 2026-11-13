// SPDX-License-Identifier: GPL-3.0-or-later
#include "grid_fit.h"
#include <algorithm>
#include <cmath>

namespace {
constexpr int kMaxPts = 256;

struct Pt { double t; double w; };

GridFit fitPoints(const Pt* p, int n, double approxStep, int64_t now) {
    GridFit g;
    g.total = n;
    if (n < 6 || approxStep <= 0) return g;
    // 1. Step and phase by the circular statistic.
    double bestR = -1, bestStep = approxStep, bestPhase = 0;
    for (int c = 0; c <= 120; c++) {
        double h = approxStep * (0.97 + 0.0005 * c);
        double sx = 0, sy = 0, sw = 0;
        for (int i = 0; i < n; i++) {
            double a = 2 * M_PI * p[i].t / h;
            sx += p[i].w * std::cos(a); sy += p[i].w * std::sin(a); sw += p[i].w;
        }
        double R = std::hypot(sx, sy) / sw;
        if (R > bestR) { bestR = R; bestStep = h; bestPhase = std::atan2(sy, sx); }
    }
    double h = bestStep;
    double a0 = bestPhase / (2 * M_PI) * h; // time of a grid index (relative to now)
    double b = h;
    // 2. IRLS on the inliers.
    double gate = std::min(40000.0, h / 4);
    for (int it = 0; it < 4; it++) {
        double S = 0, Sx = 0, Sy = 0, Sxx = 0, Sxy = 0;
        int in = 0;
        for (int i = 0; i < n; i++) {
            double m = std::round((p[i].t - a0) / b);
            double r = p[i].t - (a0 + m * b);
            if (std::fabs(r) > gate) continue;
            double w = p[i].w * (std::fabs(r) < 5000 ? 1.0 : 5000 / std::fabs(r)); // Huber
            S += w; Sx += w * m; Sy += w * p[i].t; Sxx += w * m * m; Sxy += w * m * p[i].t;
            in++;
        }
        double den = S * Sxx - Sx * Sx;
        if (in < 6 || std::fabs(den) < 1e-9) return g;
        double nb = (S * Sxy - Sx * Sy) / den;
        if (nb < approxStep * 0.96 || nb > approxStep * 1.04) break;
        b = nb;
        a0 = (Sy - b * Sx) / S;
    }
    // 3. Stats.
    double ss = 0, tmin = 1e300, tmax = -1e300, wIn = 0, wAll = 0;
    int in = 0;
    for (int i = 0; i < n; i++) {
        wAll += p[i].w;
        double m = std::round((p[i].t - a0) / b);
        double r = p[i].t - (a0 + m * b);
        if (std::fabs(r) > gate) continue;
        ss += r * r; in++; wIn += p[i].w;
        tmin = std::min(tmin, p[i].t); tmax = std::max(tmax, p[i].t);
    }
    if (in < 6) return g;
    g.ok = true;
    g.step = b;
    g.origin = now + int64_t(std::llround(a0 + std::round(-a0 / b) * b));
    g.residualRms = std::sqrt(ss / in);
    g.inliers = in;
    g.inlierShare = float(wIn / wAll); // weighted: strong hits count more than weak stray onsets
    g.spanUs = tmax - tmin;
    return g;
}
} // namespace

GridFit fitGrid(const Onset* onsets, int n, double approxStep, int64_t now, double windowUs) {
    Pt pts[kMaxPts];
    int m = 0, mRecent = 0;
    Pt recent[kMaxPts];
    for (int i = 0; i < n && m < kMaxPts; i++) {
        const Onset& o = onsets[i];
        if (o.cls == OnsetClass::Hat) continue;
        double t = double(o.t - now);
        if (t < -windowUs || t > 0) continue;
        // NN beats weigh more than single drum hits; drum hits near the grid still refine the phase (the NN's
        // times sit on 20 ms frames).
        double w = o.cls == OnsetClass::Beat ? 2.0 : 0.3 + std::min(1.0f, o.strength);
        pts[m++] = {t, w};
        if (t >= -5e6) recent[mRecent++] = {t, w};
    }
    GridFit full = fitPoints(pts, m, approxStep, now);
    if (mRecent >= 8 && windowUs > 5e6) {
        GridFit last = fitPoints(recent, mRecent, approxStep, now);
        if (last.ok && (!full.ok || last.residualRms < 0.7 * full.residualRms)) return last;
    }
    return full;
}

double estimateGridStep(const Onset* onsets, int n, int64_t now, double windowUs, int64_t since, double hintS) {
    double t[kMaxPts], w[kMaxPts];
    int m = 0;
    for (int i = 0; i < n && m < kMaxPts; i++) {
        const Onset& o = onsets[i];
        if (o.cls == OnsetClass::Hat || o.t < since || o.t > now || double(now - o.t) > windowUs) continue;
        t[m] = double(o.t - now);
        w[m] = 0.3 + std::min(1.0f, o.strength);
        m++;
    }
    if (m < 8) return 0;
    {   // gaps below need time order (late NN beats can sit out of order in the tracker's ring)
        int idx[kMaxPts];
        for (int i = 0; i < m; i++) idx[i] = i;
        std::sort(idx, idx + m, [&](int a, int b) { return t[a] < t[b]; });
        double t2[kMaxPts], w2[kMaxPts];
        for (int i = 0; i < m; i++) { t2[i] = t[idx[i]]; w2[i] = w[idx[i]]; }
        std::copy(t2, t2 + m, t); std::copy(w2, w2 + m, w);
    }
    // Circular statistic for every S in [75,190] BPM (0.1 steps; the grid step is a quarter beat of S).
    constexpr int kN = 1151;
    static thread_local double R[kN];
    double Rmax = 0;
    for (int c = 0; c < kN; c++) {
        double h = 15e6 / (75.0 + 0.1 * c);
        double sx = 0, sy = 0, sw = 0;
        for (int i = 0; i < m; i++) {
            double a = 2 * M_PI * t[i] / h;
            sx += w[i] * std::cos(a); sy += w[i] * std::sin(a); sw += w[i];
        }
        R[c] = std::hypot(sx, sy) / sw;
        Rmax = std::max(Rmax, R[c]);
    }
    if (Rmax < 0.5) return 0;
    // Hits only on the beats fit beat/3, beat/4, beat/5 ... equally well. Among the near-best steps keep those whose
    // gaps between hits, in steps, are mostly 1, 2, 4, 8 or 16 (a plain 8th/16th grid), and take the coarsest.
    auto plain = [&](double h) {
        int ok = 0, all = 0;
        for (int i = 1; i < m; i++) {
            double u = (t[i] - t[i - 1]) / h;
            long k = std::lround(u);
            if (k < 1 || std::fabs(u - k) > 0.2) continue;
            all++;
            ok += (k == 1 || k == 2 || k == 4 || k == 8 || k == 16);
        }
        return all > 0 ? double(ok) / all : 0.0;
    };
    // Agreement with aubio's tempo up to an octave (S, 2S, S/2 of the hint), as a ratio distance.
    auto hintDist = [&](double S) {
        if (hintS <= 0) return 1.0;
        double d = 1e9;
        for (double m : {0.5, 1.0, 2.0}) d = std::min(d, std::fabs(S / (hintS * m) - 1));
        return d;
    };
    int best = -1, fallback = 0, hinted = -1;
    for (int c = 0; c < kN; c++) {
        if (R[c] > R[fallback]) fallback = c;
        bool peak = (c == 0 || R[c] >= R[c - 1]) && (c == kN - 1 || R[c] >= R[c + 1]);
        if (!peak || R[c] < 0.9 * Rmax) continue;
        if (plain(15e6 / (75.0 + 0.1 * c)) < 0.6) continue;
        if (best < 0) best = c;          // ascending S: the first plain peak is the coarsest grid
        if (hintDist(75.0 + 0.1 * c) < 0.04 && hinted < 0) hinted = c;
    }
    if (hinted >= 0) best = hinted;
    if (best < 0) best = fallback;
    return 15e6 / (75.0 + 0.1 * best);
}
