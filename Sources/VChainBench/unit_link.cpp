// SPDX-License-Identifier: GPL-3.0-or-later
#include "link_sim.h"
#include "unit.h"
#include <random>
#include <thread>

using std::chrono::microseconds;

// The simulator must agree with a real (never enabled, so offline and alone) ableton::Link session.
TEST(linkSimMatchesRealLinkAlone) {
    ableton::Link real(120.0);  // not enabled: no network
    LinkSim sim(0, 0.0);
    const int64_t t0 = real.clock().micros().count();
    // Real Link applies app commits through its own thread: back-to-back commits within microseconds can be
    // overwritten by an older state. Give each commit a moment (vChain commits rarely anyway).
    auto commitReal = [&](auto fn) {
        auto s = real.captureAppSessionState(); fn(s); real.commitAppSessionState(s);
        std::this_thread::sleep_for(std::chrono::milliseconds(15));
    };
    // Same starting point on both.
    commitReal([&](auto& s) { s.setTempo(120.0, microseconds{t0}); s.forceBeatAtTime(0.0, microseconds{t0}, 4); });
    sim.setTempo(120.0, t0); sim.forceBeatAtTime(0.0, t0, 4);

    std::mt19937 rng(7);
    std::uniform_real_distribution<double> bpm(60, 180), beat(-8, 64), dt(0, 3e6);
    int64_t t = t0;
    double worst = 0;
    for (int i = 0; i < 60; i++) {
        t += int64_t(dt(rng));
        int op = i % 2;
        double v = op == 0 ? bpm(rng) : beat(rng);
        if (op == 0) { commitReal([&](auto& s) { s.setTempo(v, microseconds{t}); }); sim.setTempo(v, t); }
        if (op == 1) { commitReal([&](auto& s) { s.forceBeatAtTime(v, microseconds{t}, 4); }); sim.forceBeatAtTime(v, t, 4); }
        auto rs = real.captureAppSessionState();
        for (int k = 0; k < 5; k++) {
            int64_t q = t + k * 250000;
            worst = std::max(worst, std::fabs(rs.beatAtTime(microseconds{q}, 4) - sim.beatAtTime(q, 4)));
        }
    }
    CHECK(real.numPeers() == 0, "real Link stays alone (never enabled)");
    CHECK_NEAR(worst, 0.0, 1e-3, "beatAtTime agrees after 60 commands (worst diff, beats)");
}

TEST(linkSimForceWithPeersMoves) {
    LinkSim sim(1, 0.37);
    sim.forceBeatAtTime(8.0, 5'000'000, 4);
    CHECK_NEAR(sim.beatAtTime(5'000'000, 4), 8.0, 1e-6, "force with peers sets the beat");
    sim.setTempo(128.0, 6'000'000);
    CHECK_NEAR(sim.beatAtTime(6'000'000 + 468'750, 4) - sim.beatAtTime(6'000'000, 4), 1.0, 1e-4, "128 BPM beat length");
}

TEST(linkSimForeignEdits) {
    LinkSim sim(1, 0.0, {{LinkSimEdit::Tempo, 2'000'000, 100.0}, {LinkSimEdit::Phase, 3'000'000, 0.5}});
    CHECK(sim.advanceTo(2'500'000) == 1, "one edit by 2.5 s");
    double b = sim.beatAtTime(3'000'000, 4);
    CHECK_NEAR(sim.tempo(), 100.0, 1e-9, "foreign tempo applied");
    sim.advanceTo(3'000'000);
    CHECK_NEAR(sim.beatAtTime(3'000'000, 4) - b, 0.5, 1e-3, "foreign phase shift applied");
    CHECK(sim.tempoWrites == 0 && sim.forceWrites == 0, "foreign edits are not counted as vChain writes");
}
