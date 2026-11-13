// SPDX-License-Identifier: GPL-3.0-or-later
// kick_eval: BandsDance's kick CC (3 trigger bands = CC1, TriggerBands → DrumOnsets) against the bench's annotated beats.
// Build and run: bench/tools/kick_eval.sh [tracks...]  (default: every track in bench/annotations with audio).
//
// Per track:
//   recall   4/4 tracks only: share of annotated beats with a CC1 hit from 30 ms before to 70 ms after (CC1 lags by up
//            to ~40 ms: DrumOnsets decides late, the CC updates per 512-sample hop)
//   offbeat  4/4 only: share of half-beat positions (beat + 0.5) with a CC1 hit in the same window: kicks there are
//            mostly false (offbeat hats, basslines)
//   offgrid  all tracks: share of CC1 hits more than 45 ms from every 16th-note position: noise
//   rate     CC1 hits per second
//   r-main   4/4 only: recall over the beats where the 40-150 Hz band is within 6 dB of the track's loudest stretch
//            (the main parts, where a rumble can hide the kick)
//   sn24     4/4 only: share of beats 2 and 4 (from the annotation's beat-in-bar) with a CC2 (snare/clap) hit
//   sn13     4/4 only: share of beats 1 and 3 with a CC2 hit: mostly false (a kick's click read as a snare)
// Genre from the file name: fourfour-*, mixotic*, monographic*, djnon* count as 4/4.
#include "trigger_bands.h"
#include "decode.h"
#include <algorithm>
#include <cmath>
#include <cstdio>
#include <fstream>
#include <sstream>
#include <string>
#include <vector>

static bool fourFour(const std::string& n) {
    return n.rfind("fourfour", 0) == 0 || n.rfind("mixotic", 0) == 0 || n.rfind("monographic", 0) == 0 || n.rfind("djnon", 0) == 0;
}

int main(int argc, char** argv) {
    const double SR = 48000;
    double sumRecall = 0, sumOff = 0, sumMain = 0, sumGridFF = 0, sumGridOther = 0, sumS24 = 0, sumS13 = 0; int nFF = 0, nOther = 0;
    printf("%-46s %7s %7s %7s %7s %6s %6s %6s\n", "track", "recall", "r-main", "offbeat", "offgrid", "rate", "sn24", "sn13");
    for (int a = 1; a + 1 < argc; a += 2) {
        std::string audio = argv[a], ann = argv[a + 1];
        std::string name = audio.substr(audio.rfind('/') + 1); name = name.substr(0, name.rfind('.'));
        std::vector<float> x;
        if (!decodeFile(audio, SR, x)) { printf("%-46s decode failed\n", name.c_str()); continue; }
        std::vector<double> beats; std::vector<int> pos; std::ifstream f(ann); std::string line;
        while (std::getline(f, line)) { std::istringstream s(line); double t; int b = 0; if (s >> t) { s >> b; beats.push_back(t); pos.push_back(b); } }
        if (beats.size() < 16) continue;

        float lo[8], hi[8]; triggerBandEdges(3, lo, hi);
        TriggerBands tb; tb.reset(uint32_t(SR)); tb.setBands(3, lo, hi); tb.setDecayBeats(0.25f);
        DrumOnsets::Biquad bp[2]; bp[0].set(1, 40, 0.707, SR); bp[1].set(0, 150, 0.707, SR);
        std::vector<double> hits, snares; std::vector<float> lowDb; float prev = 0, prevSn = 0;
        for (size_t p = 0; p + 512 <= x.size(); p += 512) {
            tb.process(&x[p], 512, 0);
            if (tb.value(0) > prev + 0.05f) hits.push_back((p + 512) / SR);
            prev = tb.value(0);
            if (tb.value(1) > prevSn + 0.05f) snares.push_back((p + 512) / SR);
            prevSn = tb.value(1);
            double e = 0; for (int i = 0; i < 512; i++) { float y = bp[1].run(bp[0].run(x[p + i])); e += y * y; }
            lowDb.push_back(float(10 * std::log10(e / 512 + 1e-12)));
        }
        std::sort(hits.begin(), hits.end());
        std::sort(snares.begin(), snares.end());
        auto near = [](const std::vector<double>& v, double t, double before, double after) {
            auto it = std::lower_bound(v.begin(), v.end(), t - before);
            return it != v.end() && *it < t + after;
        };
        auto hitNear = [&](double t, double before, double after) { return near(hits, t, before, after); };
        // Main parts: beats whose surrounding beat has a 40-150 Hz level within 6 dB of the track's 90th percentile.
        auto beatLow = [&](size_t i) {
            double a = beats[i], b = i + 1 < beats.size() ? beats[i + 1] : a + 0.5; double s = 0; int c = 0;
            for (size_t h = size_t(a * SR / 512); h < size_t(b * SR / 512) && h < lowDb.size(); h++) { s += lowDb[h]; c++; }
            return c ? s / c : -120.0;
        };
        std::vector<double> lows; for (size_t i = 0; i < beats.size(); i++) lows.push_back(beatLow(i));
        std::vector<double> sorted = lows; std::sort(sorted.begin(), sorted.end());
        double p90 = sorted[size_t(0.9 * (sorted.size() - 1))];

        int on = 0, off = 0, mainN = 0, mainOn = 0, offN = 0, n24 = 0, s24 = 0, n13 = 0, s13 = 0;
        for (size_t i = 0; i < beats.size(); i++) {
            bool sn = near(snares, beats[i], 0.03, 0.07);
            if (pos[i] == 2 || pos[i] == 4) { n24++; s24 += sn; } else if (pos[i] == 1 || pos[i] == 3) { n13++; s13 += sn; }
            bool h = hitNear(beats[i], 0.03, 0.07); on += h;
            if (lows[i] > p90 - 6) { mainN++; mainOn += h; }
            if (i + 1 < beats.size()) { offN++; off += hitNear((beats[i] + beats[i + 1]) / 2, 0.03, 0.07); }
        }
        // Off-grid: hits more than 45 ms (after the lag) from every 16th.
        int offGrid = 0;
        for (double t : hits) {
            auto it = std::upper_bound(beats.begin(), beats.end(), t);
            if (it == beats.begin() || it == beats.end()) continue;
            double b0 = *(it - 1), b1 = *it, best = 1e9;
            for (int k = 0; k <= 4; k++) best = std::min(best, std::fabs((t - 0.025) - (b0 + (b1 - b0) * k / 4)));
            offGrid += best > 0.045;
        }
        double secs = x.size() / SR;
        double recall = 100.0 * on / beats.size(), offbeat = 100.0 * off / std::max(offN, 1);
        double rmain = 100.0 * mainOn / std::max(mainN, 1), grid = 100.0 * offGrid / std::max<size_t>(hits.size(), 1);
        double sn24 = 100.0 * s24 / std::max(n24, 1), sn13 = 100.0 * s13 / std::max(n13, 1);
        if (fourFour(name)) {
            printf("%-46s %6.0f%% %6.0f%% %6.0f%% %6.0f%% %6.2f %5.0f%% %5.0f%%\n", name.c_str(), recall, rmain, offbeat, grid,
                   hits.size() / secs, sn24, sn13);
            sumRecall += recall; sumMain += rmain; sumOff += offbeat; sumGridFF += grid; sumS24 += sn24; sumS13 += sn13; nFF++;
        } else {
            printf("%-46s %7s %7s %7s %6.0f%% %6.2f\n", name.c_str(), "-", "-", "-", grid, hits.size() / secs);
            sumGridOther += grid; nOther++;
        }
        fflush(stdout);
    }
    if (nFF) printf("MEAN 4/4 (%d tracks): recall %.1f%%  r-main %.1f%%  offbeat %.1f%%  offgrid %.1f%%  sn24 %.1f%%  sn13 %.1f%%\n",
                    nFF, sumRecall / nFF, sumMain / nFF, sumOff / nFF, sumGridFF / nFF, sumS24 / nFF, sumS13 / nFF);
    if (nOther) printf("MEAN DnB/breaks (%d tracks): offgrid %.1f%%\n", nOther, sumGridOther / nOther);
}
