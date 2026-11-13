// SPDX-License-Identifier: GPL-3.0-or-later
// band_eval: BandsDance in frequency-band mode (TriggerBands → BandOnsets) against the bench's annotated beats.
// Build and run: bench/tools/band_eval.sh [tracks...]; BANDS=n picks the band count (default 5; 3 is the drum mode,
// measured by kick_eval instead).
//
// Per track:
//   low-rec  4/4 only: share of annotated beats with a hit in the lowest band (−30…+70 ms): the kick lands there,
//            whatever else plays (a rumble can bury it)
//   low-off  4/4 only: same on half-beats. A bassline there is a legitimate sound in this mode: informational
//   offgrid  all tracks: share of all bands' hits more than 45 ms from every 16th-note position (noise)
//   rate     hits per second, summed over the bands
// Genre from the file name: fourfour-*, mixotic*, monographic*, djnon* count as 4/4.
#include "trigger_bands.h"
#include "decode.h"
#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <fstream>
#include <sstream>
#include <string>
#include <vector>

static bool fourFour(const std::string& n) {
    return n.rfind("fourfour", 0) == 0 || n.rfind("mixotic", 0) == 0 || n.rfind("monographic", 0) == 0 || n.rfind("djnon", 0) == 0;
}

int main(int argc, char** argv) {
    const double SR = 48000;
    const int bands = getenv("BANDS") ? std::clamp(atoi(getenv("BANDS")), 2, 8) : 5;
    double sumRec = 0, sumOff = 0, sumGridFF = 0, sumGridOther = 0, sumRateFF = 0, sumRateOther = 0;
    int nFF = 0, nOther = 0;
    printf("%d bands\n%-46s %8s %8s %8s %6s\n", bands, "track", "low-rec", "low-off", "offgrid", "rate");
    for (int a = 1; a + 1 < argc; a += 2) {
        std::string audio = argv[a], ann = argv[a + 1];
        std::string name = audio.substr(audio.rfind('/') + 1); name = name.substr(0, name.rfind('.'));
        std::vector<float> x;
        if (!decodeFile(audio, SR, x)) { printf("%-46s decode failed\n", name.c_str()); continue; }
        std::vector<double> beats; std::ifstream f(ann); std::string line;
        while (std::getline(f, line)) { std::istringstream s(line); double t; if (s >> t) beats.push_back(t); }
        if (beats.size() < 16) continue;

        float lo[8], hi[8]; triggerBandEdges(bands, lo, hi);
        TriggerBands tb; tb.reset(uint32_t(SR)); tb.setBands(bands, lo, hi); tb.setDecayBeats(0.25f);
        std::vector<std::vector<double>> hits(bands); std::vector<float> prev(bands, 0);
        for (size_t p = 0; p + 512 <= x.size(); p += 512) {
            tb.process(&x[p], 512, 0);
            for (int i = 0; i < bands; i++) {
                if (tb.value(i) > prev[i] + 0.05f) hits[i].push_back((p + 512) / SR);
                prev[i] = tb.value(i);
            }
        }
        auto near = [](const std::vector<double>& v, double t, double before, double after) {
            auto it = std::lower_bound(v.begin(), v.end(), t - before);
            return it != v.end() && *it < t + after;
        };
        int on = 0, off = 0, offN = 0;
        for (size_t i = 0; i < beats.size(); i++) {
            on += near(hits[0], beats[i], 0.03, 0.07);
            if (i + 1 < beats.size()) { offN++; off += near(hits[0], (beats[i] + beats[i + 1]) / 2, 0.03, 0.07); }
        }
        int total = 0, offGrid = 0;
        for (int b = 0; b < bands; b++)
            for (double t : hits[b]) {
                total++;
                auto it = std::upper_bound(beats.begin(), beats.end(), t);
                if (it == beats.begin() || it == beats.end()) continue;
                double b0 = *(it - 1), b1 = *it, best = 1e9;
                for (int k = 0; k <= 4; k++) best = std::min(best, std::fabs((t - 0.025) - (b0 + (b1 - b0) * k / 4)));
                offGrid += best > 0.045;
            }
        double secs = x.size() / SR, rate = total / secs, grid = 100.0 * offGrid / std::max(total, 1);
        if (fourFour(name)) {
            double rec = 100.0 * on / beats.size(), lowOff = 100.0 * off / std::max(offN, 1);
            printf("%-46s %7.0f%% %7.0f%% %7.0f%% %6.2f\n", name.c_str(), rec, lowOff, grid, rate);
            sumRec += rec; sumOff += lowOff; sumGridFF += grid; sumRateFF += rate; nFF++;
        } else {
            printf("%-46s %8s %8s %7.0f%% %6.2f\n", name.c_str(), "-", "-", grid, rate);
            sumGridOther += grid; sumRateOther += rate; nOther++;
        }
        fflush(stdout);
    }
    if (nFF) printf("MEAN 4/4 (%d tracks): low-rec %.1f%%  low-off %.1f%%  offgrid %.1f%%  rate %.2f/s\n",
                    nFF, sumRec / nFF, sumOff / nFF, sumGridFF / nFF, sumRateFF / nFF);
    if (nOther) printf("MEAN DnB/breaks (%d tracks): offgrid %.1f%%  rate %.2f/s\n", nOther, sumGridOther / nOther, sumRateOther / nOther);
}
