// SPDX-License-Identifier: GPL-3.0-or-later
// VChainBench: offline bench for VChainDSP (see bench/README.md). Never joins real Link.
//   --unit [prefix]                         unit checks
//   --synthetic <name|all> [options]        run scenarios
//   --manifest bench/sources.tsv [--id s] [--genre g] [--kind set|track] [--raw]   real audio (whole files)
//   --render <scenario> <out.wav> [.beats]  write a scenario for listening (scratch folder, not the repo)
//   --regrid in.beats out.beats             smooth Beat This! frame quantization
//   --headline --pipeline a,b,c (with --synthetic or --manifest)   headline metrics, both Link situations
//   --stdin-tempo <bpm> --pipeline a,b,c    tempo vs a listed BPM, mono f32 PCM piped on stdin (commercial previews)
// options: --pipeline tempo-phase|hy-tempo-phase|live-hy-tempo-phase (pipelines.h)  --link alone|peer|edit  --latency ms  --jitter ms  --rate 44100
//          --summary out.tsv  --csv out.csv (per hop, single scenario)  --clicks out.wav  --assert <stage>
#include "decode.h"
#include "drum_onsets.h"
#include "metrics.h"
#include "pipelines.h"
#include "synth.h"
#include "unit.h"
#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cstring>
#include <map>
#include <memory>
#include <sstream>
#include <string>

namespace {

struct Args {
    std::string manifest, only, genre, kind, raw, nnDir;
    bool headline = false, quiet = false;
    std::vector<Summary>* collect = nullptr; // per-genre and total rows, for --headline
    std::string synthetic, pipeline = "tempo-phase", link = "peer", summary, csv, clicks;
    double latency = 25, jitter = 0, rate = 48000, target = 0;
    int assertStage = -1;
};

void renderClicks(const std::string& path, const std::vector<float>& audio, double sr, const Annotation& truth,
                  const RunTrace& tr) {
    std::vector<float> st(audio.size() * 2);
    for (size_t i = 0; i < audio.size(); i++) st[2 * i] = st[2 * i + 1] = 0.5f * audio[i];
    auto click = [&](double t, bool high, int ch) {
        long s = lround(t * sr);
        double f = high ? 2000 : 1000;
        for (long k = 0; k < long(0.012 * sr); k++) {
            long j = s + k;
            if (j < 0 || j >= long(audio.size())) continue;
            st[2 * j + ch] += 0.5f * float(std::sin(2 * M_PI * f * k / sr) * std::exp(-k / (0.003 * sr)));
        }
    };
    for (const auto& b : truth.beats) click(b.t, b.beatInBar == 1, 0);
    for (const auto& t : tr.ticks) click(t.t, t.beatInBar == 1, 1);
    writeWav(path, st, sr, 2);
}

void writeCsv(const std::string& path, const RunTrace& tr) {
    // Per truth beat: <path>.beats.csv
    if (FILE* fb = fopen((path + ".beats.csv").c_str(), "w")) {
        fprintf(fb, "t,beatInBar,bpm,phaseErrMs,barOk,barLocked,state,displayBpm\n");
        for (const auto& b : tr.beats)
            fprintf(fb, "%.4f,%d,%.3f,%.2f,%d,%d,%d,%.3f\n", b.t, b.beatInBar, b.bpm, b.phaseErrMs, b.barOk, b.barLocked, b.state, b.displayBpm);
        fclose(fb);
    }
    FILE* f = fopen(path.c_str(), "w");
    if (!f) return;
    fprintf(f, "t,truthBpm,state,bpm,linkTempo,barLocked,dbConf,family,events\n");
    for (const auto& r : tr.rows)
        fprintf(f, "%.4f,%.3f,%d,%.3f,%.4f,%d,%.3f,%d,%d\n", r.t, r.truthBpm, r.state, r.bpm, r.linkTempo,
                r.barLocked, r.dbConf, r.family, r.events);
    fclose(f);
}

// hy-tempo-phase reads <nnDir>/<stem>.nn.tsv (bench/nn/rolling_dump.py; default ~/Music/vChainBench/nn-final0-w12).
std::string nnFileFor(const Args& a, const std::string& stem) {
    if (a.pipeline.rfind("hy", 0) != 0) return "";
    std::string dir = !a.nnDir.empty() ? a.nnDir : std::string(getenv("HOME")) + "/Music/vChainBench/nn-final0-w12";
    return dir + "/" + stem + ".nn.tsv";
}

int runSynthetic(const Args& a) {
    std::vector<std::string> names;
    if (a.synthetic == "all") names = scenarioNames();
    else names.push_back(a.synthetic);
    std::map<std::string, Pool> byGenre;
    Pool total;
    std::vector<Summary> rows;
    std::vector<std::string> failures;
    for (const auto& name : names) {
        Scenario sc = makeScenario(name);
        if (sc.audio.empty()) { fprintf(stderr, "unknown scenario %s\n", name.c_str()); return 2; }
        if (a.rate != kSynthRate) sc.audio = resampleLinear(sc.audio, a.rate / kSynthRate);
        auto p = makePipeline(a.pipeline, nnFileFor(a, name));
        if (!p) { fprintf(stderr, "unknown pipeline %s\n", a.pipeline.c_str()); return 2; }
        RunOptions o;
        o.latencyMs = a.latency; o.jitterMs = a.jitter; o.sampleRate = a.rate;
        o.peers = a.link == "alone" ? 0 : 1;
        if (a.link == "edit" || name == "peer-edit") o.edits = sc.linkEdits;
        o.keepRows = !a.csv.empty();
        RunTrace tr = runSection(*p, sc.audio, sc.truth, o);
        Pool pool = measure(tr, sc.truth, 0);
        Summary s = summarize(name, sc.truth.genre, pool);
        rows.push_back(s);
        byGenre[sc.truth.genre].merge(pool);
        total.merge(pool);
        if (a.assertStage >= 0)
            for (auto& f : checkStage(a.assertStage, name, s)) failures.push_back(f);
        if (!a.csv.empty()) writeCsv(a.csv, tr);
        if (!a.clicks.empty()) renderClicks(a.clicks, sc.audio, a.rate, sc.truth, tr);
    }
    if (a.collect) {
        for (const auto& [g, pool] : byGenre) a.collect->push_back(summarize("[" + g + "]", g, pool));
        a.collect->push_back(summarize("[total]", "", total));
    }
    if (!a.quiet) {
        printf("pipeline %s, Link %s, latency %.0f ms, %.0f Hz\n", a.pipeline.c_str(), a.link.c_str(), a.latency, a.rate);
        printHeader(stdout, false);
        for (const auto& s : rows) printRow(stdout, s, false);
        if (rows.size() > 1) {
            for (const auto& [g, pool] : byGenre) printRow(stdout, summarize("[" + g + "]", g, pool), false);
            printRow(stdout, summarize("[total]", "", total), false);
        }
    }
    if (!a.summary.empty()) {
        FILE* f = fopen(a.summary.c_str(), "w");
        printHeader(f, true);
        for (const auto& s : rows) printRow(f, s, true);
        for (const auto& [g, pool] : byGenre) printRow(f, summarize("[" + g + "]", g, pool), true);
        printRow(f, summarize("[total]", "", total), true);
        fclose(f);
    }
    if (a.assertStage >= 0) {
        for (const auto& f : failures) printf("ASSERT FAILED %s\n", f.c_str());
        printf("stage %d asserts: %zu failed\n", a.assertStage, failures.size());
        return failures.empty() ? 0 : 1;
    }
    return 0;
}

// Loads an annotation for a real file: Beat This! beats, regridded (unless --raw), plus regions: the optional
// <id>.regions file, gaps without beats (> 2 s) as nobeat, irregular bars as nobar.
Annotation loadAnnotation(const std::string& dir, const std::string& id, const std::string& genre, bool raw) {
    Annotation a;
    a.genre = genre;
    std::vector<TruthBeat> b;
    readBeats(dir + "/" + id + ".beats", b);
    a.beats = raw ? b : regridBeats(b);
    readRegions(dir + "/" + id + ".regions", a.regions);
    for (size_t i = 1; i < a.beats.size(); i++)
        if (a.beats[i].t - a.beats[i - 1].t > 2.0) a.regions.push_back({a.beats[i - 1].t, a.beats[i].t, "nobeat"});
    for (auto& r : irregularBarRegions(a.beats)) a.regions.push_back(r);
    return a;
}

int runManifest(const Args& a) {
    std::vector<SourceRow> rows;
    if (!readSources(a.manifest, rows)) { fprintf(stderr, "can't read %s\n", a.manifest.c_str()); return 2; }
    std::string dir = a.manifest.substr(0, a.manifest.find_last_of('/')) + "/annotations";
    const char* env = getenv("VCHAIN_BENCH_AUDIO");
    std::string audioDir = env ? env : std::string(getenv("HOME")) + "/Music/vChainBench/audio";
    std::map<std::string, Pool> byGenre;
    std::map<std::string, Pool> byKind;
    Pool total;
    std::vector<Summary> out;
    for (const auto& r : rows) {
        if (!a.only.empty() && r.id.find(a.only) == std::string::npos) continue;
        if (!a.genre.empty() && r.genre != a.genre) continue;
        if (!a.kind.empty() && r.kind != a.kind) continue;
        std::vector<float> audio;
        if (!decodeFile(audioDir + "/" + r.file, a.rate, audio)) { fprintf(stderr, "can't decode %s\n", r.file.c_str()); continue; }
        Annotation ann = loadAnnotation(dir, r.id, r.genre, !a.raw.empty());
        if (ann.beats.empty()) { fprintf(stderr, "no annotation for %s\n", r.id.c_str()); continue; }
        std::string stem = r.file.substr(0, r.file.find_last_of('.'));
        auto p = makePipeline(a.pipeline, nnFileFor(a, stem));
        if (!p) { fprintf(stderr, "unknown pipeline %s\n", a.pipeline.c_str()); return 2; }
        RunOptions o;
        o.latencyMs = a.latency; o.jitterMs = a.jitter; o.sampleRate = a.rate;
        o.peers = a.link == "alone" ? 0 : 1;
        o.keepRows = !a.csv.empty();
        RunTrace tr = runSection(*p, audio, ann, o);
        Pool pool = measure(tr, ann, 0);
        out.push_back(summarize(r.id, r.genre, pool));
        byGenre[r.genre].merge(pool);
        byKind[r.kind].merge(pool);
        total.merge(pool);
        if (!a.csv.empty()) writeCsv(a.csv, tr);
        if (!a.clicks.empty()) renderClicks(a.clicks, audio, a.rate, ann, tr);
        fprintf(stderr, ".");
    }
    fprintf(stderr, "\n");
    if (a.collect) {
        for (const auto& [g, pool] : byGenre) a.collect->push_back(summarize("[" + g + "]", g, pool));
        a.collect->push_back(summarize("[total]", "", total));
    }
    if (!a.quiet) {
        printf("pipeline %s, Link %s, latency %.0f ms, manifest %s\n", a.pipeline.c_str(), a.link.c_str(), a.latency, a.manifest.c_str());
        printHeader(stdout, false);
        for (const auto& s : out) printRow(stdout, s, false);
        for (const auto& [g, pool] : byGenre) printRow(stdout, summarize("[" + g + "]", g, pool), false);
        for (const auto& [k, pool] : byKind) printRow(stdout, summarize("[" + k + "s]", "", pool), false);
        printRow(stdout, summarize("[total]", "", total), false);
    }
    if (!a.summary.empty()) {
        FILE* f = fopen(a.summary.c_str(), "w");
        printHeader(f, true);
        for (const auto& s : out) printRow(f, s, true);
        for (const auto& [g, pool] : byGenre) printRow(f, summarize("[" + g + "]", g, pool), true);
        for (const auto& [k, pool] : byKind) printRow(f, summarize("[" + k + "s]", "", pool), true);
        printRow(f, summarize("[total]", "", total), true);
        fclose(f);
    }
    return 0;
}

// --onsetdiag: for one file, how often each onset class lands on each 8th position of the annotated bar
// (1, 1+, 2, 2+, ...), plus how many land nowhere near the grid. Tells whether the detector sees the drums.
int onsetDiag(const Args& a) {
    std::vector<SourceRow> rows;
    readSources(a.manifest, rows);
    std::string dir = a.manifest.substr(0, a.manifest.find_last_of('/')) + "/annotations";
    const char* env = getenv("VCHAIN_BENCH_AUDIO");
    std::string audioDir = env ? env : std::string(getenv("HOME")) + "/Music/vChainBench/audio";
    for (const auto& r : rows) {
        if (r.id.find(a.only) == std::string::npos) continue;
        std::vector<float> audio;
        if (!decodeFile(audioDir + "/" + r.file, 48000, audio)) continue;
        Annotation ann = loadAnnotation(dir, r.id, r.genre, false);
        DrumOnsets d; d.reset(48000);
        Onset buf[32];
        int hist[3][9] = {}, nbars = 0; // 8 positions + off-grid
        std::vector<Onset> all;
        for (size_t pos = 0; pos + 512 <= audio.size(); pos += 512) {
            int n = d.process(&audio[pos], 512, int64_t(pos * 1e6 / 48000), buf, 32);
            all.insert(all.end(), buf, buf + n);
        }
        const auto& b = ann.beats;
        for (const auto& o : all) {
            double t = o.t / 1e6;
            auto it = std::upper_bound(b.begin(), b.end(), t, [](double v, const TruthBeat& x) { return v < x.t; });
            if (it == b.begin() || it == b.end()) continue;
            const TruthBeat& p = *(it - 1);
            double ibi = it->t - p.t;
            if (ibi > 1.5 || ann.inRegion(t, "nobar")) continue;
            double frac = (t - p.t) / ibi; // 0..1 within the beat
            int half = frac < 0.25 ? 0 : frac < 0.75 ? 1 : 2;
            double dist = std::min({std::fabs(frac), std::fabs(frac - 0.5), std::fabs(frac - 1)}) * ibi;
            int beatIn = p.beatInBar - 1 + (half == 2 ? 1 : 0);
            int slot = (beatIn % 4) * 2 + (half == 1 ? 1 : 0);
            hist[int(o.cls)][dist < 0.035 ? slot : 8]++;
        }
        for (const auto& x : b) nbars += x.beatInBar == 1;
        // Where kicks land relative to the nearest annotated beat (ms, 10 ms bins from -150 to +150).
        int th[31] = {};
        for (const auto& o : all) {
            if (o.cls != OnsetClass::Kick) continue;
            double t = o.t / 1e6;
            auto it = std::lower_bound(b.begin(), b.end(), t, [](const TruthBeat& x, double v) { return x.t < v; });
            double best = 1e9;
            if (it != b.end()) best = it->t - t;
            if (it != b.begin() && std::fabs((it - 1)->t - t) < std::fabs(best)) best = (it - 1)->t - t;
            int bin = int(std::floor((-best * 1000 + 155) / 10));
            if (bin >= 0 && bin < 31) th[bin]++;
        }
        printf("kick offset vs annotated beat (ms):");
        for (int k = 0; k < 31; k++) if (th[k]) printf(" %+d:%d", k * 10 - 150, th[k]);
        printf("\n");
        printf("%s (%d bars, onsets per bar)\n        1    1+   2    2+   3    3+   4    4+   off\n", r.id.c_str(), nbars);
        const char* names[3] = {"kick ", "snare", "hat  "};
        for (int c = 0; c < 3; c++) {
            printf("%s ", names[c]);
            for (int k = 0; k < 9; k++) printf(" %4.2f", nbars ? double(hist[c][k]) / nbars : 0.0);
            printf("\n");
        }
    }
    return 0;
}

// --headline: the metrics every comparison leads with (the beat must not jump visibly; the tempo must stay steady), for
// each pipeline given with --pipeline a,b,c, in both Link situations (alone, Resolume-like peer), per genre.
int runHeadline(Args a) {
    std::vector<std::string> pipes;
    std::stringstream ss(a.pipeline);
    std::string item;
    while (std::getline(ss, item, ',')) pipes.push_back(item);
    printf("%-14s %-6s %-11s %8s %8s %13s %6s %10s %9s %9s %7s\n", "pipeline", "Link", "group", "jumps/m", "jumpBt",
           "phase med/p90", "beatF", "shown/min", "spread90", "tempoErr", "octave");
    // late: signed median phase error, ms; > 0 = Link's beat comes after the music's (printed last)
    for (const auto& pl : pipes) {
        for (const char* link : {"alone", "peer"}) {
            std::vector<Summary> rows;
            Args b = a;
            b.pipeline = pl; b.link = link; b.quiet = true; b.collect = &rows; b.summary = "";
            int rc = !b.synthetic.empty() ? runSynthetic(b) : runManifest(b);
            if (rc != 0 && rc != 1) return rc;
            for (const auto& r : rows)
                printf("%-14s %-6s %-11s %8.2f %8.2f %6.1f/%6.0f %6.2f %10.2f %9.2f %9.2f %6.0f%%  late %+5.1f\n", pl.c_str(), link,
                       r.name.c_str(), r.jumpsPerMin, r.jumpMeanBeats, r.phaseMedMs, r.phaseP90Ms, r.beatF,
                       r.dispChangesPerMin, r.shownSpreadP90, r.bpmErrMed, r.octaveOkPct, r.phaseLateMedMs);
        }
    }
    return 0;
}

} // namespace

// --stdin-tempo <bpm>: mono float32 PCM at --rate on stdin (piped from ffmpeg; nothing touches disk), each
// --pipeline (comma list) run vChain-alone against a fixed listed tempo. One line per pipeline:
// pipeline lock_s median_bpm last_bpm share_within_0.5 shown_changes_per_min (after the first lock).
int runStdinTempo(const Args& a) {
    std::vector<float> audio;
    float buf[4096];
    size_t n;
    while ((n = fread(buf, sizeof(float), 4096, stdin)) > 0) audio.insert(audio.end(), buf, buf + n);
    if (audio.size() < size_t(a.rate * 10)) { fprintf(stderr, "too little audio on stdin\n"); return 2; }
    const double target = a.target;
    std::stringstream names(a.pipeline);
    std::string name;
    Annotation none;
    while (std::getline(names, name, ',')) {
        auto p = makePipeline(name);
        if (!p) { fprintf(stderr, "unknown pipeline %s\n", name.c_str()); return 2; }
        RunOptions o;
        o.latencyMs = a.latency; o.sampleRate = a.rate; o.peers = 0;
        o.keepRows = !a.csv.empty();
        RunTrace tr = runSection(*p, audio, none, o);
        if (!a.csv.empty()) writeCsv(a.csv + "." + name + ".csv", tr);
        size_t lock = tr.states.size();
        for (size_t i = 0; i < tr.states.size(); i++) if (tr.states[i] == 2) { lock = i; break; }
        std::vector<float> after;
        size_t within = 0, changes = 0;
        for (size_t i = lock; i < tr.display.size(); i++) {
            float d = tr.display[i];
            after.push_back(d);
            if (std::fabs(d - target) <= 0.5) within++;
            if (i > lock && d != tr.display[i - 1]) changes++;
        }
        double med = NAN;
        if (!after.empty()) {
            std::vector<float> s2 = after;
            std::nth_element(s2.begin(), s2.begin() + s2.size() / 2, s2.end());
            med = s2[s2.size() / 2];
        }
        double mins = after.size() * tr.hopS / 60.0;
        printf("%s %.2f %.2f %.2f %.3f %.2f\n", name.c_str(), lock < tr.states.size() ? lock * tr.hopS : NAN, med,
               tr.display.empty() ? NAN : tr.display.back(), after.empty() ? 0.0 : double(within) / after.size(),
               mins > 0 ? changes / mins : NAN);
        fflush(stdout);
    }
    return 0;
}

int main(int argc, char** argv) {
    Args a;
    for (int i = 1; i < argc; i++) {
        std::string k = argv[i];
        auto next = [&]() -> std::string { return i + 1 < argc ? argv[++i] : ""; };
        if (k == "--unit") return unit::runAll(i + 1 < argc && argv[i + 1][0] != '-' ? argv[i + 1] : nullptr);
        if (k == "--render" && i + 2 < argc) {
            Scenario sc = makeScenario(argv[i + 1]);
            if (sc.audio.empty()) { fprintf(stderr, "unknown scenario %s\n", argv[i + 1]); return 2; }
            writeWav(argv[i + 2], sc.audio, kSynthRate, 1);
            if (i + 3 < argc) writeBeats(argv[i + 3], sc.truth.beats);
            return 0;
        }
        if (k == "--regrid" && i + 2 < argc) { // --regrid in.beats out.beats
            std::vector<TruthBeat> b;
            if (!readBeats(argv[i + 1], b)) return 2;
            return writeBeats(argv[i + 2], regridBeats(b)) ? 0 : 2;
        }
        if (k == "--synthetic") a.synthetic = next();
        else if (k == "--manifest") a.manifest = next();
        else if (k == "--nn-dir") a.nnDir = next();
        else if (k == "--headline") a.headline = true;
        else if (k == "--id") a.only = next();
        else if (k == "--genre") a.genre = next();
        else if (k == "--kind") a.kind = next();
        else if (k == "--raw") a.raw = "1";
        else if (k == "--onsetdiag") a.raw = "diag";
        else if (k == "--pipeline") a.pipeline = next();
        else if (k == "--link") a.link = next();
        else if (k == "--latency") a.latency = atof(next().c_str());
        else if (k == "--jitter") a.jitter = atof(next().c_str());
        else if (k == "--rate") a.rate = atof(next().c_str());
        else if (k == "--summary") a.summary = next();
        else if (k == "--csv") a.csv = next();
        else if (k == "--clicks") a.clicks = next();
        else if (k == "--stdin-tempo") a.target = atof(next().c_str());
        else if (k == "--assert") a.assertStage = atoi(next().c_str());
        else { fprintf(stderr, "unknown option %s (see the comment at the top of main.cpp)\n", k.c_str()); return 2; }
    }
    if (a.target > 0) return runStdinTempo(a);
    if (a.headline) return runHeadline(a);
    if (!a.synthetic.empty()) return runSynthetic(a);
    if (!a.manifest.empty() && a.raw == "diag") return onsetDiag(a);
    if (!a.manifest.empty()) return runManifest(a);
    fprintf(stderr, "usage: VChainBench --unit | --synthetic <name|all> [...] | --render <scenario> <out.wav>\n");
    return 2;
}
