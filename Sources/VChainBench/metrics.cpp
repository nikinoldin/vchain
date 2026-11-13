// SPDX-License-Identifier: GPL-3.0-or-later
#include "metrics.h"
#include <algorithm>
#include <cmath>
#include <cstdio>

namespace {

double pct(std::vector<double> v, double p) {
    if (v.empty()) return NAN;
    std::sort(v.begin(), v.end());
    return v[size_t(p * (v.size() - 1) + 0.5)];
}
double mean(const std::vector<double>& v) {
    if (v.empty()) return NAN;
    double s = 0;
    for (double x : v) s += x;
    return s / v.size();
}
void append(std::vector<double>& a, const std::vector<double>& b) { a.insert(a.end(), b.begin(), b.end()); }

// Starts of beat grids the tracker has to (re)find: the first beat, the end of an intro, cuts, ends of nobeat gaps.
std::vector<double> lockReferences(const Annotation& a, double warmupS) {
    std::vector<double> refs;
    double first = a.beats.empty() ? 0 : a.beats.front().t;
    for (const auto& r : a.regions)
        if (r.tag == "intro" && r.a <= first + 1) first = r.b;
    refs.push_back(std::max(first, warmupS));
    for (const auto& r : a.regions)
        if (r.tag == "cut" && r.a > warmupS) refs.push_back(r.a);
    std::sort(refs.begin(), refs.end());
    return refs;
}

} // namespace

void Pool::merge(const Pool& o) {
    append(phaseLateMs, o.phaseLateMs);
    append(bpmErr, o.bpmErr); append(octaveOk, o.octaveOk); append(phaseErrMs, o.phaseErrMs); append(barOk, o.barOk);
    append(barOkAfterLock, o.barOkAfterLock); append(barPrecision, o.barPrecision); append(barCoverage, o.barCoverage);
    append(lockS, o.lockS); append(cutLockS, o.cutLockS); append(barLockBars, o.barLockBars);
    append(holdReturnMs, o.holdReturnMs); append(hopUs, o.hopUs);
    append(dispStd, o.dispStd); append(dispRange, o.dispRange); dispChanges += o.dispChanges;
    append(shownSpread, o.shownSpread); append(jumps, o.jumps); jumpMinutes += o.jumpMinutes;
    ticks += o.ticks; truthBeats += o.truthBeats; matched += o.matched; commits += o.commits;
    phaseForces += o.phaseForces; barForces += o.barForces; wrongBarForces += o.wrongBarForces;
    forcesAfterForeign += o.forcesAfterForeign; holdCommits += o.holdCommits; neverLocked += o.neverLocked;
    neverBarLocked += o.neverBarLocked; sections += o.sections; minutes += o.minutes;
}

Pool measure(const RunTrace& tr, const Annotation& truth, double warmupS) {
    Pool p;
    p.sections = 1;
    p.jumps = tr.jumps;
    p.jumpMinutes = std::max(0.0, tr.length - warmupS) / 60.0;
    p.hopUs = tr.hopMicros;
    const auto refs = lockReferences(truth, warmupS);

    // Steady = not within 15 s of a grid start, not in ramp/swap.
    auto steady = [&](double t) {
        if (t < refs.front()) return false; // before the drums start (intro)
        for (double r : refs) if (t >= r && t < r + 15) return false;
        return !truth.inRegion(t, "ramp") && !truth.inRegion(t, "swap");
    };
    double firstBarLock = NAN;
    for (const auto& b : tr.beats) {
        if (b.beatInBar == 1 && b.barLocked && std::isnan(firstBarLock)) firstBarLock = b.t;
        if (b.beatInBar == 1 && !truth.inRegion(b.t, "nobar")) {
            p.barOk.push_back(b.barOk);
            if (!std::isnan(firstBarLock)) p.barOkAfterLock.push_back(b.barOk);
            p.barCoverage.push_back(b.barLocked && (b.state == 2 || b.state == 3));
            if (b.barLocked) p.barPrecision.push_back(b.barOk);
        }
        if (!steady(b.t)) continue;
        if (b.state == 2 || b.state == 3) p.octaveOk.push_back(std::fabs(b.displayBpm / b.bpm - 1) < 0.03);
        p.bpmErr.push_back(std::fabs(b.displayBpm - b.bpm));
        p.phaseErrMs.push_back(std::fabs(b.phaseErrMs));
        p.phaseLateMs.push_back(-b.phaseErrMs); // phaseErrMs > 0 = Link ahead (early)
    }

    // Beat lock: 8 consecutive beats with tempo within 0.05 BPM and phase within 20 ms.
    for (size_t r = 0; r < refs.size(); r++) {
        double ref = refs[r], end = r + 1 < refs.size() ? refs[r + 1] : 1e18;
        double locked = NAN, barLocked = NAN;
        int run = 0;
        for (size_t i = 0; i < tr.beats.size(); i++) {
            const auto& b = tr.beats[i];
            if (b.t < ref || b.t >= end) continue;
            bool ok = std::fabs(b.displayBpm - b.bpm) < 0.05 && std::fabs(b.phaseErrMs) < 20;
            run = ok ? run + 1 : 0;
            if (run == 1) locked = b.t;
            if (run >= 8) break;
            if (!ok) locked = NAN;
        }
        if (run < 8) locked = NAN;
        for (const auto& b : tr.beats)
            if (b.t >= ref && b.t < end && b.beatInBar == 1 && b.barLocked && b.barOk) { barLocked = b.t; break; }
        auto& dst = r == 0 ? p.lockS : p.cutLockS;
        if (std::isnan(locked)) p.neverLocked++; else dst.push_back(locked - ref);
        if (std::isnan(barLocked)) p.neverBarLocked++;
        else p.barLockBars.push_back((barLocked - ref) / (4 * 60.0 / std::max(1.0, truth.bpmAt(barLocked))));
    }

    // Beat F at ±70 ms between Link's grid ticks and the truth beats, in steady time (transitions: lock times).
    std::vector<double> tb;
    for (const auto& b : truth.beats) if (b.t >= warmupS && !truth.excluded(b.t) && steady(b.t)) tb.push_back(b.t);
    std::vector<double> tk;
    for (const auto& t : tr.ticks) if (!truth.excluded(t.t) && steady(t.t)) tk.push_back(t.t);
    size_t j = 0;
    int matched = 0;
    for (double t : tb) {
        while (j < tk.size() && tk[j] < t - 0.07) j++;
        if (j < tk.size() && std::fabs(tk[j] - t) <= 0.07) { matched++; j++; }
    }
    p.ticks = int(tk.size()); p.truthBeats = int(tb.size()); p.matched = matched;

    // Link writes. Tempo commits are counted in steady grooves only: from 30 s after a grid start (the lock and its
    // pull-in are measured by the lock times), outside ramps, swaps and gaps.
    auto steadyGroove = [&](double t) {
        for (double r : refs) if (t >= r && t < r + 30) return false;
        for (const auto& rg : truth.regions) if (rg.tag == "ramp" && t >= rg.b && t < rg.b + 8) return false; // catching up
        return steady(t) && !truth.excluded(t);
    };
    double steadyS = 0;
    for (double t = warmupS; t < tr.length; t += 0.1) if (steadyGroove(t)) steadyS += 0.1;
    p.minutes = steadyS / 60.0;
    for (const auto& e : tr.events) {
        double t = e.t; uint8_t ev = e.bits;
        if (t < warmupS) continue;
        if ((ev & (EvCommit | EvNudge)) && steadyGroove(t)) p.commits++;
        if (ev & EvForcePhase) p.phaseForces++;
        if (ev & EvForceBar) {
            p.barForces++;
            int seen = 0; bool wrong = false;
            for (const auto& b : tr.beats)
                if (b.t > t + 0.5 && b.beatInBar == 1 && seen < 4) { seen++; wrong |= !b.barOk; }
            if (wrong) p.wrongBarForces++;
        }
        for (double tf : tr.foreignTimes) {
            double win = 8 * 60.0 / std::max(60.0, truth.bpmAt(tf));
            if ((ev & (EvForcePhase | EvForceBar)) && t > tf && t <= tf + win) p.forcesAfterForeign++;
        }
    }
    // Steadiness of the shown tempo: changes of the 0.1-BPM value per steady minute, and the
    // spread (std, max - min) of the shown BPM in 30 s steady blocks.
    {
        int last = -1;
        std::vector<double> block;
        double blockStart = -1;
        auto flush = [&]() {
            if (block.size() > 100) {
                double m = mean(block), ss = 0, lo = 1e9, hi = -1e9;
                for (double v : block) { ss += (v - m) * (v - m); lo = std::min(lo, v); hi = std::max(hi, v); }
                p.dispStd.push_back(std::sqrt(ss / block.size()));
                p.dispRange.push_back(hi - lo);
            }
            block.clear();
        };
        for (size_t i = 0; i < tr.display.size(); i++) {
            double t = i * tr.hopS;
            if (!steadyGroove(t) || tr.display[i] <= 1) { flush(); blockStart = -1; last = -1; continue; }
            int shown = int(std::lround(tr.display[i] * 10));
            if (last >= 0 && shown != last) p.dispChanges++;
            last = shown;
            if (blockStart < 0) blockStart = t;
            block.push_back(tr.display[i]);
            if (t - blockStart >= 30) { flush(); blockStart = t; }
        }
        flush();
    }
    // Spread of the shown tempo after the first lock, in every state (holding, settling, searching included): catches
    // the shown value wandering in breakdowns (e.g. 125.1-126.1). Per 60 s block: p95 - p5 of the shown value (octave
    // readings and the 15 s after a cut left out; a DJ ramp or a new track inside a block shows up as spread too).
    {
        bool locked = false;
        std::vector<double> block;
        double blockStart = -1;
        auto flush = [&]() {
            if (block.size() > 500) {
                std::sort(block.begin(), block.end());
                p.shownSpread.push_back(block[size_t(0.95 * (block.size() - 1))] - block[size_t(0.05 * (block.size() - 1))]);
            }
            block.clear();
        };
        double ref = 0;
        for (size_t i = 0; i < tr.display.size(); i++) {
            double t = i * tr.hopS;
            if (tr.states[i] == 2) locked = true;
            if (!locked || tr.display[i] <= 1) continue;
            bool transition = false;
            for (double r : refs) if (t >= r && t < r + 15) transition = true;
            if (transition) { flush(); blockStart = -1; continue; }
            if (blockStart < 0) { blockStart = t; ref = tr.display[i]; }
            double v = tr.display[i];
            if (std::fabs(v / ref - 0.5) < 0.03) v *= 2; else if (std::fabs(v / ref - 2) < 0.06) v /= 2;
            block.push_back(v);
            if (t - blockStart >= 60) { flush(); blockStart = -1; }
        }
        flush();
    }
    // Holding through breakdowns: commits inside (after its first 2 s), and the error of the first 4 beats after.
    for (const auto& r : truth.regions) {
        if (r.tag != "breakdown") continue;
        for (const auto& e : tr.events)
            if (e.t > r.a && e.t < r.b && e.state == 3 && (e.bits & (EvCommit | EvNudge))) p.holdCommits++;
        std::vector<double> after;
        for (const auto& b : tr.beats) if (b.t >= r.b && after.size() < 4) after.push_back(std::fabs(b.phaseErrMs));
        if (!after.empty()) p.holdReturnMs.push_back(mean(after));
    }
    return p;
}

Summary summarize(const std::string& name, const std::string& genre, const Pool& p) {
    Summary s{};
    s.name = name; s.genre = genre; s.sections = p.sections;
    s.bpmErrMed = pct(p.bpmErr, 0.5); s.bpmErrMax = pct(p.bpmErr, 1.0);
    s.octaveOkPct = 100 * mean(p.octaveOk);
    s.phaseLateMedMs = pct(p.phaseLateMs, 0.5);
    s.phaseMedMs = pct(p.phaseErrMs, 0.5); s.phaseP90Ms = pct(p.phaseErrMs, 0.9);
    double prec = p.ticks ? double(p.matched) / p.ticks : 0, rec = p.truthBeats ? double(p.matched) / p.truthBeats : 0;
    s.beatF = prec + rec > 0 ? 2 * prec * rec / (prec + rec) : 0;
    s.barOkPct = 100 * mean(p.barOk); s.barOkAfterLockPct = 100 * mean(p.barOkAfterLock);
    s.barPrecPct = 100 * mean(p.barPrecision); s.barCovPct = 100 * mean(p.barCoverage);
    s.lockMedS = pct(p.lockS, 0.5); s.lockP90S = pct(p.lockS, 0.9); s.cutLockMedS = pct(p.cutLockS, 0.5);
    s.barLockMedBars = pct(p.barLockBars, 0.5); s.barLockP90Bars = pct(p.barLockBars, 0.9);
    s.commitsPerMin = p.minutes > 0 ? p.commits / p.minutes : 0;
    s.holdReturnMs = pct(p.holdReturnMs, 1.0);
    s.usMean = mean(p.hopUs); s.usP99 = pct(p.hopUs, 0.99);
    s.dispChangesPerMin = p.minutes > 0 ? p.dispChanges / p.minutes : 0;
    s.dispStd = pct(p.dispStd, 0.5); s.dispRange = pct(p.dispRange, 0.5);
    s.jumpsPerMin = p.jumpMinutes > 0 ? p.jumps.size() / p.jumpMinutes : 0;
    s.jumpMeanBeats = mean(p.jumps);
    s.shownSpreadMed = pct(p.shownSpread, 0.5);
    s.shownSpreadP90 = pct(p.shownSpread, 0.9);
    s.phaseForces = p.phaseForces; s.barForces = p.barForces; s.wrongBarForces = p.wrongBarForces;
    s.forcesAfterForeign = p.forcesAfterForeign; s.holdCommits = p.holdCommits;
    s.neverLocked = p.neverLocked; s.neverBarLocked = p.neverBarLocked;
    return s;
}

void printHeader(FILE* f, bool tsv) {
    const char* cols[] = {"section", "genre", "n", "bpmErrMed", "bpmErrMax", "octOk%", "phMed", "phP90", "beatF",
                          "bar%", "barAfterLk%", "barPrec%", "barCov%", "lockMed", "lockP90", "cutLock", "barLkBars",
                          "barLkP90", "commit/min", "phForce", "barForce", "wrongBar", "forceAfterEdit", "holdCommit",
                          "holdRetMs", "noLock", "noBarLock", "usMean", "usP99", "shown/min", "shownStd", "shownRange", "spread60Med", "spread60P90", "jumps/min", "jumpBeats"};
    for (size_t i = 0; i < sizeof(cols) / sizeof(cols[0]); i++)
        fprintf(f, tsv ? (i ? "\t%s" : "%s") : (i == 0 ? "%-22s" : i == 1 ? " %-8s" : " %9s"), cols[i]);
    fprintf(f, "\n");
}

void printRow(FILE* f, const Summary& s, bool tsv) {
    if (tsv) fprintf(f, "%s\t%s\t%d", s.name.c_str(), s.genre.c_str(), s.sections);
    else fprintf(f, "%-22s %-8s %9d", s.name.c_str(), s.genre.c_str(), s.sections);
    const char* fmt = tsv ? "\t%.3f" : " %9.2f";
    for (double v : {s.bpmErrMed, s.bpmErrMax, s.octaveOkPct, s.phaseMedMs, s.phaseP90Ms, s.beatF, s.barOkPct,
                     s.barOkAfterLockPct, s.barPrecPct, s.barCovPct, s.lockMedS, s.lockP90S, s.cutLockMedS,
                     s.barLockMedBars, s.barLockP90Bars, s.commitsPerMin})
        fprintf(f, fmt, v);
    const char* ifmt = tsv ? "\t%d" : " %9d";
    for (int v : {s.phaseForces, s.barForces, s.wrongBarForces, s.forcesAfterForeign, s.holdCommits}) fprintf(f, ifmt, v);
    fprintf(f, fmt, s.holdReturnMs);
    for (int v : {s.neverLocked, s.neverBarLocked}) fprintf(f, ifmt, v);
    fprintf(f, fmt, s.usMean);
    fprintf(f, fmt, s.usP99);
    for (double v : {s.dispChangesPerMin, s.dispStd, s.dispRange, s.shownSpreadMed, s.shownSpreadP90, s.jumpsPerMin, s.jumpMeanBeats}) fprintf(f, fmt, v);
    fprintf(f, "\n");
}

std::vector<std::string> checkStage(int stage, const std::string& sc, const Summary& s) {
    std::vector<std::string> fail;
    auto need = [&](bool ok, const char* what, double v) {
        if (!ok) { char buf[160]; snprintf(buf, sizeof buf, "%s: %s (got %.3f)", sc.c_str(), what, v); fail.push_back(buf); }
    };
    if (stage < 1) return fail;
    // The shipped pipeline's targets (docs/beat-tracking.md, "Targets"), per genre family. The phase is steered by tempo nudges,
    // so tempo commits per minute say little; the headline metrics (visible jumps, shown-value changes) take their place.
    bool four = s.genre == "fourfour";
    double phMed = four ? 15 : 20, phP90 = four ? 30 : 40, beatF = four ? 0.95 : (s.genre == "dnb" ? 0.93 : 0.92);
    double lockMed = four ? 8 : 10;
    need(s.bpmErrMed <= 0.05, "BPM error median <= 0.05", s.bpmErrMed);
    // house-mix / peer-edit (same audio): B's tempo is reached after the ramp; dnb-blend: ramp into the half-time part;
    // spinback: the shown tempo follows the slowed record for a moment. Those get a guard instead.
    bool ramp = sc == "dnb-blend" || sc == "house-mix" || sc == "peer-edit" || sc == "spinback";
    need(s.bpmErrMax <= (ramp ? 1.5 : 0.15), ramp ? "BPM error max <= 1.5 (ramp guard)" : "BPM error max <= 0.15", s.bpmErrMax);
    need(s.octaveOkPct >= (s.genre == "breaks" ? 98 : 99), "octave right", s.octaveOkPct);
    need(s.phaseMedMs < phMed, "phase median", s.phaseMedMs);
    need(s.phaseP90Ms < phP90, "phase p90", s.phaseP90Ms);
    need(s.beatF >= beatF, "beat F", s.beatF);
    // Synthetic sections are 1-2 min, where the first lock's jump and one bar move already read as ~1-2/min.
    need(std::isnan(s.jumpsPerMin) || s.jumpsPerMin <= 3, "visible phase jumps per minute <= 3", s.jumpsPerMin);
    need(std::isnan(s.dispChangesPerMin) || s.dispChangesPerMin <= 4, "shown-value changes per steady minute <= 4", s.dispChangesPerMin);
    need(s.neverLocked == 0, "every grid locks", s.neverLocked);
    need(std::isnan(s.lockMedS) || s.lockMedS <= lockMed, "lock time median", s.lockMedS);
    // Regression guard (the tempo holds through a cut, the grid relocks in 13.8-14.8 s; 39 s after the spinback).
    need(std::isnan(s.cutLockMedS) || s.cutLockMedS <= (sc == "spinback" ? 45 : 16), "lock time after a cut (guard)", s.cutLockMedS);
    need(s.holdCommits == 0, "no commits while holding a breakdown", s.holdCommits);
    need(std::isnan(s.holdReturnMs) || s.holdReturnMs < (four ? 30 : 40), "phase error when the drums return", s.holdReturnMs);
    need(s.forcesAfterForeign == 0, "no force answers a foreign edit", s.forcesAfterForeign);
    need(s.usMean <= 300 && s.usP99 <= 2000, "CPU per hop", s.usMean);
    return fail;
}
