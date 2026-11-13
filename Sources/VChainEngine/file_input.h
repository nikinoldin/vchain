// SPDX-License-Identifier: GPL-3.0-or-later
// Developer input (vc_engine_select_file): decodes an audio file to mono float and feeds it into a ring buffer in
// real time, looped, hop by hop on its own thread.
#pragma once

#include "audio_source.h"
#include "capture_clock.h"
#include "ring_buffer.h"
#include <atomic>
#include <thread>
#include <vector>

class FileInput : public AudioSource {
public:
    FileInput();
    ~FileInput() override;

    bool start(const char* path);
    void stop() override;

    size_t available() const override { return mRing.available(); }
    size_t read(float* out, size_t n) override;
    uint32_t sampleRate() const override { return kSampleRate; }
    // "Captured" when written to the ring (the ring write time, no extra latency).
    bool nextReadTicks(uint64_t& ticks) const override { return mClock.nextReadTicks(kSampleRate, ticks); }

private:
    static constexpr uint32_t kSampleRate = 48000;
    bool decode(const char* path);
    void run();

    RingBuffer mRing;
    CaptureClock mClock;
    uint64_t mWritten = 0;
    std::vector<float> mSamples;
    std::atomic<bool> mRunning{false};
    std::thread mThread;
};
