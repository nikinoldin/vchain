// SPDX-License-Identifier: GPL-3.0-or-later
#include "capture_clock.h"
#include "unit.h"
#include <cmath>
#include <mach/mach_time.h>

// Latency compensation: the capture time of the next sample read comes from the newest anchor, offset by the
// samples between the anchor and the read position (either side of it).
TEST(captureClockTimesTheReadPosition) {
    mach_timebase_info_data_t tb;
    mach_timebase_info(&tb);
    const double ticksPerSec = 1e9 * tb.denom / tb.numer;
    const double sr = 48000;
    CaptureClock c;
    uint64_t t = 0;
    CHECK(!c.nextReadTicks(sr, t), "no time before the first anchor");
    const uint64_t host0 = 1'000'000'000ull;
    c.publish(0, host0);                                 // buffer 1: samples 0..511
    c.publish(512, host0 + uint64_t(512 / sr * ticksPerSec)); // buffer 2: samples 512..1023
    CHECK(c.nextReadTicks(sr, t), "time once anchored");
    CHECK_NEAR((double(int64_t(t - host0))) / ticksPerSec * 1e6, 0.0, 1.0, "read position 0 = first buffer's time (µs)");
    c.noteRead(512);
    c.nextReadTicks(sr, t);
    CHECK_NEAR((double(int64_t(t - host0))) / ticksPerSec * 1e6, 512 / sr * 1e6, 1.0, "after one hop: +10.67 ms");
    c.noteRead(1024);                                    // past the newest anchor: extrapolated
    c.nextReadTicks(sr, t);
    CHECK_NEAR((double(int64_t(t - host0))) / ticksPerSec * 1e6, 1536 / sr * 1e6, 1.0, "extrapolated past the anchor");
}
