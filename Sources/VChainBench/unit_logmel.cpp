// SPDX-License-Identifier: GPL-3.0-or-later
#include "log_mel.h"
#include "synth.h"
#include "unit.h"
#include <cmath>
#include <fstream>
#include <sstream>
#include <vector>

// The engine's log-mel front end against Beat This!'s own (soxr + LogMelSpect, bench/nn/logmel_fixture.py) on the
// synthetic house-mix, frames 200..259.
TEST(logMelMatchesBeatThis) {
    std::ifstream f("bench/nn/fixtures/logmel-house-mix-200.tsv");
    std::vector<std::vector<float>> ref;
    std::string line;
    while (std::getline(f, line)) {
        std::istringstream ss(line);
        std::vector<float> row;
        float v;
        while (ss >> v) row.push_back(v);
        if (row.size() == LogMel::kBands) ref.push_back(row);
    }
    CHECK(ref.size() == 60, "fixture read (run from the repo root)");
    if (ref.size() != 60) return;
    Scenario sc = makeScenario("house-mix");
    LogMel lm;
    lm.reset(kSynthRate);
    std::vector<float> frames;
    std::vector<float> buf(LogMel::kBands * 64);
    for (size_t pos = 0; pos + 512 <= sc.audio.size() && lm.framesDone() < 270; pos += 512) {
        int k = lm.process(&sc.audio[pos], 512, buf.data(), 64);
        frames.insert(frames.end(), buf.begin(), buf.begin() + size_t(k) * LogMel::kBands);
    }
    double sum = 0, mx = 0, refSum = 0;
    for (int i = 0; i < 60; i++)
        for (int m = 0; m < LogMel::kBands; m++) {
            double d = std::fabs(frames[size_t(200 + i) * LogMel::kBands + m] - ref[i][m]);
            sum += d; refSum += std::fabs(ref[i][m]);
            if (m < 120) mx = std::max(mx, d); // the top bands (10-11 kHz, at Nyquist) follow soxr's own roll-off
        }
    double meanAbs = sum / (60 * LogMel::kBands), refMean = refSum / (60 * LogMel::kBands);
    CHECK(meanAbs < 0.02 * refMean + 0.01, "mean |diff| " + std::to_string(meanAbs) + " (values ~" + std::to_string(refMean) + ")");
    CHECK(mx < 0.3, "max |diff| below 10 kHz " + std::to_string(mx));
}
