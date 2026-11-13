// SPDX-License-Identifier: GPL-3.0-or-later
#include "beat_engine.h"
#include "nn_front_end.h"
#include <chrono>
#include <cstdlib>
#include <sys/stat.h>
#include <thread>
#include "real_link_port.h"
#include "synth.h"
#include "unit.h"
#include <algorithm>
#include <cmath>
#include <vector>

// The app's path: BeatEngine writing through RealLinkPort into a real (never enabled, so offline) ableton::Link
// session. Link's tempo and beats land on the music's and nothing jumps after the lock.
TEST(appTempoPhasePathOnRealLink) {
    ableton::Link link(120.0);
    RealLinkPort port(link);
    Scenario sc = makeScenario("techno-140");
    BeatEngine engine(48000);
    engine.reset(48000);
    int64_t t0 = link.clock().micros().count();
    int jumps = 0;
    size_t nextBeat = 0;
    std::vector<double> err;
    for (size_t pos = 0; pos + 512 <= sc.audio.size(); pos += 512) {
        int64_t now = t0 + int64_t(pos * 1e6 / 48000);
        double before = link.captureAppSessionState().beatAtTime(std::chrono::microseconds{now}, 4);
        engine.process(&sc.audio[pos], 512, now, port);
        double moved = link.captureAppSessionState().beatAtTime(std::chrono::microseconds{now}, 4) - before;
        moved = std::fmod(moved, 4.0); if (moved > 2) moved -= 4; if (moved < -2) moved += 4;
        double t = pos / 48000.0;
        if (t > 20 && std::fabs(moved) > 0.02) jumps++;
        while (nextBeat < sc.truth.beats.size() && sc.truth.beats[nextBeat].t < t) {
            double tb = sc.truth.beats[nextBeat++].t;
            if (tb < 20) continue;
            double L = link.captureAppSessionState().beatAtTime(std::chrono::microseconds{t0 + int64_t(tb * 1e6)}, 4);
            err.push_back(std::fabs(L - std::round(L)) * 60000.0 / 140);
        }
    }
    std::sort(err.begin(), err.end());
    double med = err.empty() ? 1e9 : err[err.size() / 2];
    CHECK(jumps == 0, "no visible phase jumps after the lock (" + std::to_string(jumps) + ")");
    CHECK(med < 15, "Link's beats on the music's beats (median " + std::to_string(med) + " ms)");
    CHECK(link.numPeers() == 0, "offline");
    CHECK_NEAR(link.captureAppSessionState().tempo(), 140.0, 0.3, "Link tempo 140 (within a 0.2 % phase nudge)");
    CHECK_NEAR(engine.state().displayBpm, 140.0, 0.05, "shown tempo 140.0");
}

// The app's hybrid path: NNFrontEnd (its own thread, Core ML) + BeatEngine (hybrid) into a real, offline
// Link session, on DnB (where the drum rules read 87). Skipped when the model isn't on disk.
TEST(appHybridPathOnRealLink) {
    std::string home = getenv("HOME");
    std::string model = home + "/Music/vChainBench/models/beat_this_final0_T600_fp16.mlpackage";
    struct stat st {};
    if (stat(model.c_str(), &st) != 0) { CHECK(true, "skipped: no model at " + model); return; }
    NNFrontEnd nn;
    nn.start(model, home + "/Music/vChainBench/models/cache");
    for (int i = 0; i < 400 && !nn.ready(); i++) std::this_thread::sleep_for(std::chrono::milliseconds(25));
    CHECK(nn.ready(), "model loaded");
    ableton::Link link(120.0);
    RealLinkPort port(link);
    Scenario sc = makeScenario("dnb-174");
    BeatEngine engine(48000);
    engine.reset(48000);
    engine.setHybrid(true);
    int64_t t0 = link.clock().micros().count();
    int barChecks = 0, barOk = 0;
    for (size_t pos = 0; pos + 512 <= sc.audio.size(); pos += 512) {
        int64_t now = t0 + int64_t(pos * 1e6 / 48000);
        nn.pushHop(&sc.audio[pos], 512, now, 48000);
        // Faster than real time: wait for the worker at each window, as if a second had passed.
        int64_t w = nn.written();
        if (w >= 50 && w % 50 == 0)
            for (int i = 0; i < 400 && nn.processed() < w; i++) std::this_thread::sleep_for(std::chrono::milliseconds(2));
        Onset b[64];
        int64_t d[64];
        int nd = 0;
        int k = nn.popBeats(b, 64, d, 64, &nd);
        if (k) engine.addExternalBeats(b, k);
        if (nd) engine.addExternalDownbeats(d, nd);
        engine.process(&sc.audio[pos], 512, now, port);
        double tb = pos / 48000.0;
        if (tb > 40 && tb < 55) { // the groove (bars 8-39), well after the lock: Link's 1 should be the music's 1
            int idx = int(std::lround((tb - 0.5) / (60.0 / 174)));
            if (idx % 4 == 0 && std::fabs(tb - (0.5 + idx * 60.0 / 174)) < 0.006) {
                double ph = link.captureAppSessionState().phaseAtTime(std::chrono::microseconds{now}, 4);
                barChecks++; if (std::fabs(ph - std::round(ph)) < 0.1 && int(std::lround(ph)) % 4 == 0) barOk++;
            }
        }
    }
    nn.stop();
    CHECK_NEAR(engine.state().displayBpm, 174.0, 0.15, "DnB shown at 174");
    CHECK(engine.state().barLocked, "bar locked");
    CHECK(barChecks > 5 && barOk >= barChecks * 0.9, "Link's 1 on the music's 1 (" + std::to_string(barOk) + "/" + std::to_string(barChecks) + ")");
    CHECK(engine.activeTracker() == 0 || engine.activeTracker() == 1, "arbiter running");
}
