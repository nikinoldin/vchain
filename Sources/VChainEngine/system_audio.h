// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once

#include "audio_source.h"
#include "capture_clock.h"
#include "ring_buffer.h"
#include <atomic>
#include <cstdint>

// ScreenCaptureKit-based system audio capture (macOS 13+)
// Captures all system audio output without needing a virtual audio device.
class SystemAudio : public AudioSource {
public:
    SystemAudio(uint32_t sampleRate = 48000);
    ~SystemAudio() override;

    bool start();
    void stop() override;

    size_t available() const override { return mRingBuffer.available(); }
    size_t read(float* buffer, size_t count) override;

    // The requested rate until the first buffer reports the real one.
    uint32_t sampleRate() const override { return mSampleRate.load(); }
    bool isRunning() const { return mRunning.load(); }
    // Stopped by the system (didStopWithError), or running but stalled: no buffer (audio or the 1 fps heartbeat
    // frame) for kStallSeconds. macOS stops the stream without telling the delegate when the display sleeps (SCK frame
    // status "stopped"); it never resumes by itself.
    bool lost() const override { return !isRunning() || isStalled(kStallSeconds); }

    // Capture time of the next sample read() returns (host ticks), from the sample buffers' presentation
    // time stamps; false before the first buffer.
    bool nextReadTicks(uint64_t& ticks) const override { return mClock.nextReadTicks(mSampleRate, ticks); }
    // What the listener hears comes out of the default output device after the mix SCK captures: its latency + safety
    // offset + stream latency (Core Audio, re-read every 2 s so a switched output counts). Returned negative: the
    // audible time is later than the capture time stamp. Engine thread.
    double fixedLatencyUs() override;

    // Called from Obj-C delegate — do not call directly. hostTicks: host time of the first sample (0 = unknown).
    void pushSamples(const float* data, size_t count, uint64_t hostTicks);
    void setActualSampleRate(uint32_t rate);
    void noteBuffer();
    void markStopped() { mRunning.store(false); }

private:
    static constexpr double kStallSeconds = 3.0; // the heartbeat frame comes once a second
    bool isStalled(double seconds) const;

    RingBuffer mRingBuffer;
    std::atomic<uint32_t> mSampleRate; // set on SCK's queue by the first buffer, read by the engine thread
    std::atomic<uint32_t> mActualSampleRate{0}; // detected from first buffer
    std::atomic<bool> mRunning{false};
    std::atomic<uint64_t> mLastBufferTicks{0}; // host ticks of the last buffer of any type
    CaptureClock mClock;
    uint64_t mWritten = 0; // samples written to the ring (SCK's serial queue)
    double mOutputLatencyUs = 0;
    uint64_t mOutputLatencyAt = 0; // host ticks of the last query

    // Opaque pointer to Obj-C implementation
    void* mImpl = nullptr;
};
