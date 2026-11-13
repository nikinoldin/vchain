// SPDX-License-Identifier: GPL-3.0-or-later
// Capture-time anchors for an audio input (design "Latency compensation"). The audio thread publishes, per buffer,
// (samples written before it, host ticks of its first sample); the engine thread counts the samples it reads and
// asks for the capture time of the next sample it will read. Lock-free: a seqlock over two atomics.
#pragma once
#include <atomic>
#include <cstdint>
#include <mach/mach_time.h>

class CaptureClock {
public:
    // Audio thread: `written` = samples written to the ring before this buffer; `hostTicks` = mach host time of the
    // buffer's first sample. Call after the ring write succeeded.
    void publish(uint64_t written, uint64_t hostTicks) {
        uint32_t s = mSeq.load(std::memory_order_relaxed);
        mSeq.store(s + 1, std::memory_order_release);   // odd: writing
        std::atomic_thread_fence(std::memory_order_release);
        mIndex.store(written, std::memory_order_relaxed);
        mHost.store(hostTicks, std::memory_order_relaxed);
        mSeq.store(s + 2, std::memory_order_release);
    }
    // Engine thread: samples consumed from the ring.
    void noteRead(uint64_t n) { mRead += n; }
    // Engine thread: host ticks of the next sample to be read; false while no anchor exists.
    bool nextReadTicks(double sampleRate, uint64_t& ticks) const {
        uint64_t idx = 0, host = 0;
        for (int tries = 0; tries < 4; tries++) {
            uint32_t s0 = mSeq.load(std::memory_order_acquire);
            if (s0 & 1) continue;
            idx = mIndex.load(std::memory_order_relaxed);
            host = mHost.load(std::memory_order_relaxed);
            std::atomic_thread_fence(std::memory_order_acquire);
            if (mSeq.load(std::memory_order_relaxed) != s0) continue;
            if (s0 == 0 || sampleRate <= 0) return false;
            double dtSec = (double(int64_t(mRead - idx))) / sampleRate;
            ticks = uint64_t(int64_t(host) + int64_t(dtSec * ticksPerSecond()));
            return true;
        }
        return false;
    }
    // Host ticks now, for inputs without their own time stamps (the file input stamps the ring write).
    static uint64_t nowTicks() { return mach_absolute_time(); }

private:
    static double ticksPerSecond() {
        static const double tps = [] {
            mach_timebase_info_data_t tb;
            mach_timebase_info(&tb);
            return 1e9 * double(tb.denom) / double(tb.numer);
        }();
        return tps;
    }
    std::atomic<uint32_t> mSeq{0};
    // Sample counts (mIndex: written, mRead: read) never reset (a restarted device keeps counting), so old samples
    // still in the ring stay consistent.
    std::atomic<uint64_t> mIndex{0}, mHost{0};
    uint64_t mRead = 0;
};
