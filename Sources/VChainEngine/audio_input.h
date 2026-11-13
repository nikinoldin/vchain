// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once

#include "audio_source.h"
#include "capture_clock.h"
#include "ring_buffer.h"
#include <AudioToolbox/AudioToolbox.h>
#include <CoreAudio/CoreAudio.h>
#include <atomic>
#include <cstdint>
#include <string>
#include <vector>

// Core Audio input capture from a chosen input device.
// No device is opened until a device is selected and start() is called.
class AudioInput : public AudioSource {
public:
    AudioInput(uint32_t sampleRate = 44100, uint32_t bufferSize = 512);
    ~AudioInput() override;

    bool start();
    void stop() override;

    size_t available() const override { return mRingBuffer.available(); }
    size_t read(float* buffer, size_t count) override;

    uint32_t sampleRate() const override { return mSampleRate; }
    bool isRunning() const { return mRunning; }

    // Capture time of the next sample read() returns (host ticks), from the IO callbacks' time stamps; false
    // before the first callback. fixedLatencyUs: the device's input latency + safety offset + stream latency, to
    // subtract (the time stamp is when the buffer reached the HAL, not when the sound reached the input).
    bool nextReadTicks(uint64_t& ticks) const override { return mClock.nextReadTicks(mSampleRate, ticks); }
    double fixedLatencyUs() override { return mFixedLatencyUs.load(std::memory_order_relaxed); }

    // Device enumeration and switching
    struct DeviceInfo {
        AudioDeviceID id;
        std::string name;
    };
    static std::vector<DeviceInfo> listInputDevices();
    bool switchDevice(AudioDeviceID deviceId);
    AudioDeviceID currentDeviceId() const { return mCurrentDeviceId; }

private:
    bool setupAudioUnit(AudioDeviceID deviceId);
    void teardownAudioUnit();
    static OSStatus inputCallback(void* inRefCon,
                                  AudioUnitRenderActionFlags* ioActionFlags,
                                  const AudioTimeStamp* inTimeStamp,
                                  UInt32 inBusNumber,
                                  UInt32 inNumberFrames,
                                  AudioBufferList* ioData);

    AudioUnit mAudioUnit = nullptr;
    AudioBufferList* mInputBufferList = nullptr;
    RingBuffer mRingBuffer;
    uint32_t mSampleRate;
    uint32_t mBufferSize;
    std::atomic<AudioDeviceID> mCurrentDeviceId{0}; // read by the engine thread's snapshot while a selection switches
    bool mRunning = false;
    CaptureClock mClock;
    uint64_t mWritten = 0;                    // samples written to the ring (audio thread)
    std::atomic<double> mFixedLatencyUs{0};
};
