// SPDX-License-Identifier: GPL-3.0-or-later
#include "truth.h"
#include <algorithm>
#include <cmath>
#include <cstdlib>
#include <cstdio>
#include <fstream>
#include <sstream>

double Annotation::bpmAt(double t) const {
    if (beats.size() < 2 || t < beats.front().t || t > beats.back().t) return 0;
    auto it = std::upper_bound(beats.begin(), beats.end(), t, [](double v, const TruthBeat& b) { return v < b.t; });
    long i = long(it - beats.begin()) - 1;
    // Intervals around t, but only the contiguous run of regular intervals that t belongs to (never across a cut
    // or a gap; if t sits inside a gap, the run before it).
    long lo = std::max(0L, i - 3), hi = std::min(long(beats.size()) - 2, i + 4);
    std::vector<double> all;
    for (long k = lo; k <= hi; k++) all.push_back(beats[k + 1].t - beats[k].t);
    std::vector<double> tmp = all;
    std::nth_element(tmp.begin(), tmp.begin() + tmp.size() / 2, tmp.end());
    double med = tmp[tmp.size() / 2];
    auto regular = [&](long k) { double d = beats[k + 1].t - beats[k].t; return std::fabs(d / med - 1) < 0.08; };
    long ref = std::min(i, hi);
    if (!regular(ref)) ref = ref - 1 >= lo && regular(ref - 1) ? ref - 1 : (ref + 1 <= hi && regular(ref + 1) ? ref + 1 : ref);
    std::vector<double> iv;
    for (long k = ref; k >= lo && regular(k); k--) iv.push_back(beats[k + 1].t - beats[k].t);
    for (long k = ref + 1; k <= hi && regular(k); k++) iv.push_back(beats[k + 1].t - beats[k].t);
    if (iv.empty()) return 0;
    std::nth_element(iv.begin(), iv.begin() + iv.size() / 2, iv.end());
    return 60.0 / iv[iv.size() / 2];
}

bool Annotation::inRegion(double t, const std::string& tag) const {
    for (const auto& r : regions)
        if (r.tag == tag && t >= r.a && t < r.b) return true;
    return false;
}

bool Annotation::excluded(double t) const {
    if (beats.empty() || t < beats.front().t || t > beats.back().t) return true;
    return inRegion(t, "nobeat");
}

Annotation Annotation::cut(double offset, double length) const {
    Annotation a;
    a.genre = genre;
    for (const auto& b : beats)
        if (b.t >= offset && b.t < offset + length) a.beats.push_back({b.t - offset, b.beatInBar});
    for (const auto& r : regions) {
        double ra = std::max(0.0, r.a - offset), rb = std::min(length, r.b - offset);
        if (rb > ra) a.regions.push_back({ra, rb, r.tag});
    }
    return a;
}

bool readBeats(const std::string& path, std::vector<TruthBeat>& out) {
    std::ifstream f(path);
    if (!f) return false;
    out.clear();
    std::string line;
    while (std::getline(f, line)) {
        if (line.empty() || line[0] == '#') continue;
        std::istringstream ss(line);
        TruthBeat b{};
        if (ss >> b.t >> b.beatInBar) out.push_back(b);
    }
    return true;
}

bool writeBeats(const std::string& path, const std::vector<TruthBeat>& beats) {
    FILE* f = fopen(path.c_str(), "w");
    if (!f) return false;
    for (const auto& b : beats) fprintf(f, "%.4f\t%d\n", b.t, b.beatInBar);
    fclose(f);
    return true;
}

bool readRegions(const std::string& path, std::vector<Region>& out) {
    std::ifstream f(path);
    if (!f) return false;
    out.clear();
    std::string line;
    while (std::getline(f, line)) {
        if (line.empty() || line[0] == '#') continue;
        std::istringstream ss(line);
        Region r{};
        if (ss >> r.a >> r.b >> r.tag) out.push_back(r);
    }
    return true;
}

bool writeRegions(const std::string& path, const std::vector<Region>& regions) {
    FILE* f = fopen(path.c_str(), "w");
    if (!f) return false;
    for (const auto& r : regions) fprintf(f, "%.3f\t%.3f\t%s\n", r.a, r.b, r.tag.c_str());
    fclose(f);
    return true;
}

namespace {
double median(std::vector<double> v) {
    if (v.empty()) return 0;
    std::nth_element(v.begin(), v.begin() + v.size() / 2, v.end());
    return v[v.size() / 2];
}
} // namespace

std::vector<TruthBeat> regridBeats(const std::vector<TruthBeat>& in) {
    const size_t n = in.size();
    if (n < 4) return in;
    // Segment ids: break where an interval is off the local median by > 15 %.
    std::vector<int> seg(n, 0);
    for (size_t i = 1; i < n; i++) {
        std::vector<double> iv;
        for (size_t k = (i > 8 ? i - 8 : 1); k < std::min(n, i + 8); k++) iv.push_back(in[k].t - in[k - 1].t);
        double m = median(iv), d = in[i].t - in[i - 1].t;
        seg[i] = seg[i - 1] + (std::fabs(d - m) > 0.15 * m ? 1 : 0);
    }
    std::vector<TruthBeat> out = in;
    for (size_t i = 0; i < n; i++) {
        std::vector<std::pair<double, double>> pts; // (index offset, time)
        for (long k = long(i) - 8; k <= long(i) + 8; k++)
            if (k >= 0 && k < long(n) && seg[k] == seg[i]) pts.push_back({double(k - long(i)), in[k].t});
        if (pts.size() < 5) continue;
        for (int pass = 0; pass < 2; pass++) {
            double sx = 0, sy = 0, sxx = 0, sxy = 0;
            for (auto [x, y] : pts) { sx += x; sy += y; sxx += x * x; sxy += x * y; }
            double m = double(pts.size()), den = m * sxx - sx * sx;
            if (std::fabs(den) < 1e-9) break;
            double slope = (m * sxy - sx * sy) / den, icpt = (sy - slope * sx) / m;
            if (pass == 1) { out[i].t = icpt; break; }
            std::vector<std::pair<double, double>> keep;
            for (auto [x, y] : pts) if (std::fabs(y - (icpt + slope * x)) < 0.03) keep.push_back({x, y});
            if (keep.size() < 5) { out[i].t = icpt; break; }
            pts = keep;
        }
    }
    return out;
}

std::vector<Region> irregularBarRegions(const std::vector<TruthBeat>& b) {
    std::vector<Region> out;
    // A downbeat is trusted when the bar before and after it both have 4 beats.
    std::vector<size_t> downs;
    for (size_t i = 0; i < b.size(); i++) if (b[i].beatInBar == 1) downs.push_back(i);
    for (size_t k = 0; k + 1 < downs.size(); k++) {
        bool ok = downs[k + 1] - downs[k] == 4;
        if (!ok) {
            double a = b[downs[k]].t, e = b[downs[k + 1]].t;
            if (!out.empty() && out.back().b >= a - 1e-6) out.back().b = e;
            else out.push_back({a, e, "nobar"});
        }
    }
    return out;
}

bool readSources(const std::string& path, std::vector<SourceRow>& out) {
    std::ifstream f(path);
    if (!f) return false;
    out.clear();
    std::string line;
    bool header = true;
    while (std::getline(f, line)) {
        if (header) { header = false; continue; }
        if (line.empty()) continue;
        std::vector<std::string> c;
        std::stringstream ss(line);
        std::string cell;
        while (std::getline(ss, cell, '\t')) c.push_back(cell);
        if (c.size() < 9) continue;
        SourceRow r{c[0], c[1], c[2], c[3], c[4], c[5], c[6], c[7], atof(c[8].c_str())};
        out.push_back(r);
    }
    return true;
}
