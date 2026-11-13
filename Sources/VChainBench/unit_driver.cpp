// SPDX-License-Identifier: GPL-3.0-or-later
#include "beat_tracker.h"
#include "link_driver.h"
#include "link_sim.h"
#include "runner.h"
#include "unit.h"
#include <cmath>
#include <string>

// Hybrid: the arbiter can hand the driver a tracker that has never locked (the NN tracker early on, or after its
// reset). Once the driver has locked, it must keep the shown and Link tempo, not fall back to aubio's raw reading
// (otherwise the tag flickers between aubio's reading and the locked tempo, e.g. 131.6 and 130 on a UKG track,
// ~2000 times a minute).
TEST(driverHoldsTempoWhenActiveTrackerNeverLocked) {
    BeatTracker a, b;
    LinkDriver d;
    LinkSim link(0, 0.0);
    const double beatUs = 60e6 / 130.0, hopUs = 512 / 48000.0 * 1e6;
    int64_t t = kBenchBaseUs, nextKick = t;
    for (; t < kBenchBaseUs + 20'000'000; t += int64_t(hopUs)) {
        while (nextKick <= t) { Onset o{nextKick, OnsetClass::Kick, 1.0f}; a.addOnsets(&o, 1); nextKick += int64_t(beatUs); }
        a.tick(t, 130.0f, 130.0f, 0.2f);
        link.advanceTo(t);
        d.setCoarse(130.0, 0.8f);
        d.update(t, a, link);
    }
    CHECK(a.everLocked(), "tracker A locked on the 130 kicks");
    CHECK_NEAR(d.displayTempo(), 130.0, 0.05, "shown 130 after the lock");
    int changes = 0;
    double last = d.displayTempo();
    for (int64_t end = t + 10'000'000; t < end; t += int64_t(hopUs)) {
        b.tick(t, 131.66f, 130.0f, 0.2f);
        link.advanceTo(t);
        d.setCoarse(131.66, 0.8f);
        d.update(t, b, link);
        double s = d.displayTempo();
        if (s != last) changes++;
        last = s;
    }
    CHECK(!b.everLocked(), "tracker B never locked");
    CHECK_NEAR(d.displayTempo(), 130.0, 0.05, "shown value held at 130");
    CHECK(changes == 0, "shown value never changed");
    CHECK_NEAR(link.tempo(), 130.0, 0.05, "Link tempo held at 130");
}

// Hybrid: the NN tracker locks while it is still passive (its lock event is dropped), then the arbiter makes it
// active. The driver must still take that as its first lock instead of staying on aubio for the whole track.
TEST(driverLocksOnTrackerWhoseLockEventWasTaken) {
    BeatTracker a;
    LinkDriver d;
    LinkSim link(0, 0.0);
    const double beatUs = 60e6 / 130.0, hopUs = 512 / 48000.0 * 1e6;
    int64_t t = kBenchBaseUs, nextKick = t;
    int changes = 0;
    double last = 0;
    for (; t < kBenchBaseUs + 30'000'000; t += int64_t(hopUs)) {
        while (nextKick <= t) { Onset o{nextKick, OnsetClass::Kick, 1.0f}; a.addOnsets(&o, 1); nextKick += int64_t(beatUs); }
        a.tick(t, 131.66f, 130.0f, 0.2f);
        link.advanceTo(t);
        d.setCoarse(131.66, 0.8f);
        if (t < kBenchBaseUs + 15'000'000) { a.takeLockEvent(); continue; } // passive: the engine drops its events
        d.update(t, a, link);
        double s = d.displayTempo();
        if (t > kBenchBaseUs + 20'000'000 && s != last) changes++;
        last = s;
    }
    CHECK(a.state() == BeatState::Locked, "tracker locked");
    CHECK_NEAR(d.displayTempo(), 130.0, 0.05, "shown 130, not aubio's 131.7");
    CHECK(changes == 0, "shown value steady");
    CHECK_NEAR(link.tempo(), 130.0, 0.05, "Link at 130");
}

// The bar move: a whole-beat shift the shortest way (-1, +2, +1 for the 1 on Link beat 1, 2, 3), the beat
// fraction untouched, made on the beat that becomes the new 1 (within one hop after it), exactly once.
TEST(barMoveIsWholeBeatOnTheNewDownbeat) {
    const double expect[4] = {0, -1, 2, 1};
    for (int residue = 1; residue <= 3; residue++) {
        BeatTracker a;
        LinkDriver d;
        LinkSim link(0, 0.0);
        const double beatUs = 60e6 / 130.0, hopUs = 512 / 48000.0 * 1e6;
        int64_t t = kBenchBaseUs, nextKick = t;
        int moves = 0;
        double prevL = NAN, shift = 0, fracJump = 1, landedFrac = 1;
        int landedBar = -1;
        for (; t < kBenchBaseUs + 40'000'000; t += int64_t(hopUs)) {
            while (nextKick <= t) { Onset o{nextKick, OnsetClass::Kick, 1.0f}; a.addOnsets(&o, 1); nextKick += int64_t(beatUs); }
            a.tick(t, 130.0f, 130.0f, 0.2f);
            link.advanceTo(t);
            d.setCoarse(130.0, 0.8f);
            if (a.state() == BeatState::Locked && t > kBenchBaseUs + 10'000'000) d.setBar(BarState{true, residue, 1.0f});
            double before = link.beatAtTime(t, 4);
            uint8_t ev = d.update(t, a, link);
            double after = link.beatAtTime(t, 4);
            if (ev & EvForceBar) {
                moves++;
                shift = std::round(after - before);
                double fb = before - std::floor(before), fa = after - std::floor(after);
                fracJump = std::fabs(fa - fb);
                landedFrac = fa;
                landedBar = int(std::floor(after + 1e-9)) % 4;
                if (landedBar < 0) landedBar += 4;
            }
            prevL = after;
        }
        (void)prevL;
        std::string r = " (1 on Link beat " + std::to_string(residue) + ")";
        CHECK(moves == 1, ("exactly one bar move" + r).c_str());
        CHECK_NEAR(shift, expect[residue], 1e-6, ("shortest whole-beat shift" + r).c_str());
        CHECK(fracJump < 1e-6, ("beat fraction untouched" + r).c_str());
        CHECK(landedBar == 0 && landedFrac < 0.03, ("made on the new 1, within a hop" + r).c_str());
    }
}
