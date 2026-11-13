// SPDX-License-Identifier: GPL-3.0-or-later
#include "truth.h"
#include "unit.h"
#include <cmath>
#include <cstdio>
#include <random>

// Beat This!-like annotations: true beats on a 20 ms frame grid plus a little noise.
TEST(regridRemovesFrameQuantization) {
    std::vector<TruthBeat> truth, quant;
    std::mt19937 rng(3);
    std::normal_distribution<double> noise(0, 0.004);
    double t = 1.0;
    for (int i = 0; i < 400; i++) {
        double bpm = i < 200 ? 126.0 : 174.0;
        if (i == 200) t += 0.3; // a hard cut
        truth.push_back({t, i % 4 + 1});
        quant.push_back({std::round((t + noise(rng)) / 0.02) * 0.02, i % 4 + 1});
        t += 60.0 / bpm;
    }
    auto err = [&](const std::vector<TruthBeat>& v) {
        double s = 0; for (size_t i = 0; i < v.size(); i++) s += std::fabs(v[i].t - truth[i].t); return s / v.size() * 1000;
    };
    double before = err(quant), after = err(regridBeats(quant));
    CHECK(before > 4, "quantized annotation is off by several ms");
    CHECK(after < 2.0, "regridded annotation within 2 ms on average (" + std::to_string(after) + " ms)");
}

TEST(irregularBars) {
    std::vector<TruthBeat> b;
    for (int i = 0; i < 40; i++) b.push_back({i * 0.5, i % 4 + 1});
    b[21].beatInBar = 1; // a stray downbeat
    auto r = irregularBarRegions(b);
    CHECK(r.size() == 1, "one irregular stretch");
    CHECK(!r.empty() && r[0].a <= 10.0 && r[0].b >= 12.0, "around the stray downbeat");
}

TEST(manifestRead) {
    const char* p = "/tmp/vchainbench-sources-test.tsv";
    FILE* f = fopen(p, "w");
    fprintf(f, "set_id\tkind\tgenre\tsource_url\tlicence_url\tattribution\tsha256\tfile\tduration_s\tdownload_url\n");
    fprintf(f, "a\tset\tfourfour\thttps://x\thttps://cc\tA - B\tabc\ta.mp3\t3600.5\thttps://d\n");
    fclose(f);
    std::vector<SourceRow> rows;
    CHECK(readSources(p, rows) && rows.size() == 1, "one row");
    CHECK(!rows.empty() && rows[0].genre == "fourfour" && rows[0].file == "a.mp3" && rows[0].durationS > 3600, "fields");
    remove(p);
}
