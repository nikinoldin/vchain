// SPDX-License-Identifier: GPL-3.0-or-later
// Runs a pipeline (the app's BeatEngine, pipelines.h) hop by hop over a section with known truth,
// against a LinkSim, as fast as the CPU goes, and collects what the metrics need.
#pragma once
#include "link_driver.h"
#include "link_sim.h"
#include "truth.h"
#include <cstdint>
#include <string>
#include <vector>

// Link writes a pipeline made during one hop: LinkEvent bits (link_driver.h).

struct PipelineView {
    int state = 0;             // 0 searching, 1 settling, 2 locked, 3 holding
    double displayBpm = 0;
    bool barLocked = false;
    float downbeatConfidence = 0;
    int family = 0;            // 0 unknown, 1 fourfour, 2 backbeat
    uint8_t events = 0;        // LinkEvent bits of the last hop
};

class Pipeline {
public:
    virtual ~Pipeline() = default;
    virtual const char* name() const = 0;
    virtual void reset(uint32_t sampleRate) = 0;
    // captureUs: capture time of the hop's first sample; nowUs: when the engine processes it (capture + latency).
    virtual void process(const float* hop, uint32_t n, int64_t captureUs, int64_t nowUs, LinkPort& link) = 0;
    virtual PipelineView view() const = 0;
};

// Link-clock time of section time 0 (keeps all times positive).
constexpr int64_t kBenchBaseUs = 100'000'000;

struct RunOptions {
    double latencyMs = 25;     // input latency + processing delay the pipeline must compensate
    double jitterMs = 0;       // capture-time jitter
    double warmupS = 0;        // audio fed before measuring (metrics ignore it)
    size_t peers = 1;          // 0 = vChain alone in Link
    double peerPhase = 0.37;   // session phase vs. the music when Resolume was there first
    std::vector<LinkSimEdit> edits;
    double sampleRate = 48000;
    bool keepRows = false;
};

struct HopRow {
    double t;          // section time of the hop start, s
    double truthBpm;
    int state;
    double bpm, linkTempo;
    bool barLocked;
    float dbConf;
    int family;
    uint8_t events;
};

struct Tick { double t; int beatInBar; }; // a Link grid beat (beatInBar 1 = Link beat 0 of the bar)

struct RunTrace {
    // Per truth beat, evaluated when its hop was processed (Link's mapping at that moment).
    struct BeatEval { double t; int beatInBar; double bpm; double phaseErrMs; bool barOk; bool barLocked; int state; double displayBpm; };
    std::vector<BeatEval> beats;
    std::vector<Tick> ticks;
    std::vector<HopRow> rows;          // only with keepRows
    struct Event { double t; uint8_t bits; int state; };
    std::vector<Event> events;         // hops with Link writes (LinkEvent bits) and the state then
    std::vector<double> foreignTimes;  // section times of foreign edits
    std::vector<double> hopMicros;     // processing time per hop, µs
    std::vector<float> display;        // displayed BPM per hop (steadiness)
    std::vector<uint8_t> states;       // pipeline state per hop
    std::vector<double> jumps;         // visible phase jumps: |Link beat moved at one instant| > 0.02 beat, in beats
    double hopS = 512 / 48000.0;
    double length = 0;
};

RunTrace runSection(Pipeline& p, const std::vector<float>& audio, const Annotation& truth, const RunOptions& o);
