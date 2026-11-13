// SPDX-License-Identifier: GPL-3.0-or-later
// What the engine thread reads audio from: a Core Audio input device (AudioInput), system audio (SystemAudio) or a
// file (FileInput). Each fills its RingBuffer on its own thread; these calls come from the engine thread (stop() from
// an input selection while the engine thread reads no input).
#pragma once

#include <cstddef>
#include <cstdint>

class AudioSource {
public:
    virtual ~AudioSource() = default;

    virtual void stop() = 0;
    virtual size_t available() const = 0;
    // Reads up to n mono samples; returns how many were read.
    virtual size_t read(float* out, size_t n) = 0;
    virtual uint32_t sampleRate() const = 0;
    // Capture time of the next sample read() returns (host ticks); false while unknown.
    virtual bool nextReadTicks(uint64_t& ticks) const = 0;
    // The input's fixed latency (µs) still to subtract from that capture time.
    virtual double fixedLatencyUs() { return 0; }
    // Started, but the stream has died since (system audio while the display sleeps): reported as
    // VC_INPUT_STATE_FAILED so the app retries.
    virtual bool lost() const { return false; }
};
