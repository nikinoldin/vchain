// SPDX-License-Identifier: GPL-3.0-or-later
// Metrics from docs/beat-tracking.md ("Metrics"), pooled per section, genre, tag and in total.
#pragma once
#include "runner.h"
#include <map>
#include <string>
#include <vector>

struct Pool {
    std::vector<double> phaseLateMs;           // signed: > 0 = Link's beat after the music's (steady time)
    std::vector<double> bpmErr, octaveOk, phaseErrMs, barOk, barOkAfterLock, barPrecision, barCoverage;
    std::vector<double> lockS, cutLockS, barLockBars, holdReturnMs, hopUs;
    std::vector<double> dispStd, dispRange;  // per 30 s steady block
    int dispChanges = 0;                     // changes of the shown value (0.1 BPM) in steady time
    std::vector<double> jumps;               // visible phase jumps (beats)
    double jumpMinutes = 0;
    std::vector<double> shownSpread;         // p95-p5 of the shown tempo per 60 s block after the first lock (all states)
    int ticks = 0, truthBeats = 0, matched = 0;
    int commits = 0, phaseForces = 0, barForces = 0, wrongBarForces = 0, forcesAfterForeign = 0, holdCommits = 0;
    int neverLocked = 0, neverBarLocked = 0, sections = 0;
    double minutes = 0;
    void merge(const Pool& o);
};

// One table row. NaN = not measurable in this section.
struct Summary {
    std::string name, genre;
    int sections = 0;
    double bpmErrMed, bpmErrMax, octaveOkPct, phaseMedMs, phaseP90Ms, beatF, barOkPct, barOkAfterLockPct, barPrecPct,
        barCovPct, lockMedS, lockP90S, cutLockMedS, barLockMedBars, barLockP90Bars, commitsPerMin, holdReturnMs, usMean, usP99,
        dispChangesPerMin, dispStd, dispRange, shownSpreadMed, shownSpreadP90, jumpsPerMin, jumpMeanBeats, phaseLateMedMs;
    int phaseForces, barForces, wrongBarForces, forcesAfterForeign, holdCommits, neverLocked, neverBarLocked;
};

Pool measure(const RunTrace& tr, const Annotation& truth, double warmupS);
Summary summarize(const std::string& name, const std::string& genre, const Pool& p);
void printHeader(FILE* f, bool tsv);
void printRow(FILE* f, const Summary& s, bool tsv);

// The shipped pipeline's targets (docs/beat-tracking.md, "Targets") for a synthetic scenario (stage >= 1); returns the failed checks (empty = pass).
std::vector<std::string> checkStage(int stage, const std::string& scenario, const Summary& s);
