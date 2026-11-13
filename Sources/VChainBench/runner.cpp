// SPDX-License-Identifier: GPL-3.0-or-later
#include "runner.h"
#include "beat_engine.h"
#include <algorithm>
#include <chrono>
#include <cmath>
#include <random>

namespace {
inline int64_t us(double s) { return kBenchBaseUs + int64_t(std::llround(s * 1e6)); }
} // namespace

RunTrace runSection(Pipeline& p, const std::vector<float>& audio, const Annotation& truth, const RunOptions& o) {
    RunTrace tr;
    const uint32_t hop = BeatEngine::kHopSize;
    const double sr = o.sampleRate;
    p.reset(uint32_t(sr));
    std::vector<LinkSimEdit> edits = o.edits;
    for (auto& e : edits) { tr.foreignTimes.push_back(e.at / 1e6); e.at = us(e.at / 1e6); }
    LinkSim link(o.peers, o.peerPhase, edits);
    std::mt19937 rng(11);
    std::normal_distribution<double> jitter(0.0, o.jitterMs > 0 ? o.jitterMs : 1.0);

    size_t nextBeat = 0;
    double prevLinkBeatEnd = NAN;
    tr.length = audio.size() / sr;
    tr.hopS = hop / sr;
    for (size_t pos = 0; pos + hop <= audio.size(); pos += hop) {
        double t0 = pos / sr, t1 = (pos + hop) / sr;
        int64_t capture = us(t0) + (o.jitterMs > 0 ? int64_t(jitter(rng) * 1000) : 0);
        int64_t now = us(t1) + int64_t(o.latencyMs * 1000);
        link.advanceTo(now);
        // A visible phase jump: where Link puts the beat at one instant moves when vChain writes (force, request);
        // tempo changes keep the beat at their own time, so they barely move it (and Resolume follows them smoothly).
        double before = link.beatAtTime(now, kLinkQuantum);
        auto c0 = std::chrono::steady_clock::now();
        p.process(&audio[pos], hop, capture, now, link);
        auto c1 = std::chrono::steady_clock::now();
        double moved = std::fmod(link.beatAtTime(now, kLinkQuantum) - before, kLinkQuantum); // a whole-bar shift is invisible
        if (moved > 2) moved -= 4;
        if (moved < -2) moved += 4;
        if (std::fabs(moved) > 0.02 && t0 >= o.warmupS) tr.jumps.push_back(std::fabs(moved));
        tr.hopMicros.push_back(std::chrono::duration<double, std::micro>(c1 - c0).count());
        PipelineView v = p.view();
        if (v.events) tr.events.push_back({t0, v.events, v.state});
        tr.display.push_back(float(v.displayBpm));
        tr.states.push_back(uint8_t(v.state));

        // Truth beats inside this hop, judged against Link's mapping as it stands now.
        while (nextBeat < truth.beats.size() && truth.beats[nextBeat].t < t1) {
            const auto& b = truth.beats[nextBeat++];
            if (b.t < o.warmupS || truth.excluded(b.t)) continue;
            double L = link.beatAtTime(us(b.t), kLinkQuantum);
            double bpm = truth.bpmAt(b.t);
            double frac = L - std::round(L);
            double ph = link.phaseAtTime(us(b.t), kLinkQuantum);
            int barPos = int(std::lround(ph)) % 4;
            tr.beats.push_back({b.t, b.beatInBar, bpm, frac * 60.0 / std::max(bpm, 1.0) * 1000.0,
                                b.beatInBar != 1 || barPos == 0, v.barLocked, v.state, v.displayBpm});
        }
        // Link grid ticks inside this hop.
        double Lb = link.beatAtTime(us(t0), kLinkQuantum), Le = link.beatAtTime(us(t1), kLinkQuantum);
        if (!std::isnan(prevLinkBeatEnd)) Lb = std::min(Lb, Le);
        for (double k = std::ceil(Lb); k < Le; k += 1.0) {
            double tt = t0 + (k - Lb) / (Le - Lb) * (t1 - t0);
            double ph = link.phaseAtTime(us(tt), kLinkQuantum);
            int idx = int(std::lround(ph)) % 4;
            if (tt >= o.warmupS) tr.ticks.push_back({tt, idx + 1});
        }
        prevLinkBeatEnd = Le;
        if (o.keepRows) {
            tr.rows.push_back({t0, truth.bpmAt(t0), v.state, v.displayBpm, link.tempo(), v.barLocked,
                               v.downbeatConfidence, v.family, v.events});
        }
    }
    return tr;
}
