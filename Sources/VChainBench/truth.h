// SPDX-License-Identifier: GPL-3.0-or-later
// Ground truth for a section: beats with their position in the bar, plus tagged regions.
// File formats (bench/annotations/): <id>.beats = "time\tbeatInBar" per line (madmom / Beat This! style,
// 1 = downbeat), <id>.regions = "start\tend\ttag". Times in seconds.
#pragma once
#include <string>
#include <vector>

struct TruthBeat {
    double t;
    int beatInBar; // 1..4, 1 = downbeat
};

struct Region {
    double a, b;
    std::string tag; // nobeat, breakdown, blend, swap, cut, ramp, trackstart, halftime, intro, ...
};

struct Annotation {
    std::vector<TruthBeat> beats;
    std::vector<Region> regions;
    std::string genre; // fourfour | dnb | breaks

    // Local tempo at t: 60 / median of the up to 8 beat intervals around t (0 outside the beats).
    double bpmAt(double t) const;
    // True when t is in a `nobeat` region or outside the annotated beats.
    bool excluded(double t) const;
    bool inRegion(double t, const std::string& tag) const;
    // Shifts all times by -offset and keeps only [0, length).
    Annotation cut(double offset, double length) const;
};

bool readBeats(const std::string& path, std::vector<TruthBeat>& out);
bool writeBeats(const std::string& path, const std::vector<TruthBeat>& beats);
bool readRegions(const std::string& path, std::vector<Region>& out);
bool writeRegions(const std::string& path, const std::vector<Region>& regions);

// Beat This! times sit on a 20 ms frame grid. Club tracks hold a constant tempo, so each beat is replaced by a
// robust local line fit over its ±8 neighbours (within one grid segment: a new segment starts where an interval
// differs from the local median by > 15 %). Measured on synthetic truth: see unit_truth.cpp.
std::vector<TruthBeat> regridBeats(const std::vector<TruthBeat>& in);
// Regions where the annotated bars are not 4 beats long, so bar metrics can't trust the downbeats ("nobar").
std::vector<Region> irregularBarRegions(const std::vector<TruthBeat>& beats);

// One row of bench/sources.tsv (one section per file: the whole file).
struct SourceRow {
    std::string id, kind, genre, sourceUrl, licenceUrl, attribution, sha256, file;
    double durationS = 0;
};
bool readSources(const std::string& path, std::vector<SourceRow>& out);
