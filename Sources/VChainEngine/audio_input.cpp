// SPDX-License-Identifier: GPL-3.0-or-later
#include "audio_input.h"
#include <iostream>

// Max frames per input callback we can hold (Core Audio may deliver more than requested).
static constexpr uint32_t kMaxCallbackFrames = 4096;

// The constructor touches no audio hardware. Opening an input device (especially
// a Bluetooth headset mic) makes macOS switch the headset into its call profile,
// which changes the system output volume. The device is only opened in start().
AudioInput::AudioInput(uint32_t sampleRate, uint32_t bufferSize)
    : mRingBuffer(sampleRate * 2) // 2 seconds of buffer
    , mSampleRate(sampleRate)
    , mBufferSize(bufferSize)
{
    mInputBufferList = static_cast<AudioBufferList*>(calloc(1, sizeof(AudioBufferList)));
    mInputBufferList->mNumberBuffers = 1;
    mInputBufferList->mBuffers[0].mNumberChannels = 1;
    mInputBufferList->mBuffers[0].mDataByteSize = kMaxCallbackFrames * sizeof(float);
    mInputBufferList->mBuffers[0].mData = calloc(kMaxCallbackFrames, sizeof(float));
}

AudioInput::~AudioInput() {
    stop();
    free(mInputBufferList->mBuffers[0].mData);
    free(mInputBufferList);
}

static uint32_t queryDeviceSampleRate(AudioDeviceID deviceId) {
    Float64 rate = 0;
    UInt32 size = sizeof(rate);
    AudioObjectPropertyAddress prop = {
        kAudioDevicePropertyNominalSampleRate,
        kAudioObjectPropertyScopeGlobal,
        kAudioObjectPropertyElementMain
    };
    AudioObjectGetPropertyData(deviceId, &prop, 0, nullptr, &size, &rate);
    return static_cast<uint32_t>(rate);
}

// Input-side latency the HAL time stamp does not include: device latency + safety offset + the first input
// stream's latency, in frames at the device rate.
static double queryInputLatencyUs(AudioDeviceID deviceId, uint32_t rate) {
    if (rate == 0) return 0;
    auto get = [&](AudioObjectID obj, AudioObjectPropertySelector sel, AudioObjectPropertyScope scope) -> UInt32 {
        UInt32 v = 0, size = sizeof(v);
        AudioObjectPropertyAddress a = {sel, scope, kAudioObjectPropertyElementMain};
        return AudioObjectGetPropertyData(obj, &a, 0, nullptr, &size, &v) == noErr ? v : 0;
    };
    UInt32 frames = get(deviceId, kAudioDevicePropertyLatency, kAudioObjectPropertyScopeInput) +
                    get(deviceId, kAudioDevicePropertySafetyOffset, kAudioObjectPropertyScopeInput);
    AudioObjectPropertyAddress sa = {kAudioDevicePropertyStreams, kAudioObjectPropertyScopeInput, kAudioObjectPropertyElementMain};
    UInt32 size = 0;
    if (AudioObjectGetPropertyDataSize(deviceId, &sa, 0, nullptr, &size) == noErr && size >= sizeof(AudioStreamID)) {
        std::vector<AudioStreamID> streams(size / sizeof(AudioStreamID));
        if (AudioObjectGetPropertyData(deviceId, &sa, 0, nullptr, &size, streams.data()) == noErr)
            frames += get(streams[0], kAudioStreamPropertyLatency, kAudioObjectPropertyScopeGlobal);
    }
    return frames * 1e6 / rate;
}

bool AudioInput::setupAudioUnit(AudioDeviceID deviceId) {
    AudioComponentDescription desc = {};
    desc.componentType = kAudioUnitType_Output;
    desc.componentSubType = kAudioUnitSubType_HALOutput;
    desc.componentManufacturer = kAudioUnitManufacturer_Apple;

    AudioComponent component = AudioComponentFindNext(nullptr, &desc);
    if (!component) {
        std::cerr << "[AudioInput] Could not find HAL output component" << std::endl;
        return false;
    }
    if (AudioComponentInstanceNew(component, &mAudioUnit) != noErr) {
        std::cerr << "[AudioInput] Could not create audio unit" << std::endl;
        mAudioUnit = nullptr;
        return false;
    }

    // Input only: enable bus 1, disable output bus 0
    UInt32 enableInput = 1, disableOutput = 0;
    AudioUnitSetProperty(mAudioUnit, kAudioOutputUnitProperty_EnableIO,
        kAudioUnitScope_Input, 1, &enableInput, sizeof(enableInput));
    AudioUnitSetProperty(mAudioUnit, kAudioOutputUnitProperty_EnableIO,
        kAudioUnitScope_Output, 0, &disableOutput, sizeof(disableOutput));

    OSStatus result = AudioUnitSetProperty(mAudioUnit,
        kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
        &deviceId, sizeof(deviceId));
    if (result != noErr) {
        std::cerr << "[AudioInput] Could not set input device: " << result << std::endl;
        teardownAudioUnit();
        return false;
    }

    if (uint32_t rate = queryDeviceSampleRate(deviceId)) mSampleRate = rate;
    mFixedLatencyUs.store(queryInputLatencyUs(deviceId, mSampleRate), std::memory_order_relaxed);

    AudioStreamBasicDescription asbd = {};
    asbd.mFormatID = kAudioFormatLinearPCM;
    asbd.mFormatFlags = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked | kAudioFormatFlagIsNonInterleaved;
    asbd.mSampleRate = mSampleRate;
    asbd.mChannelsPerFrame = 1; // mono
    asbd.mBitsPerChannel = 32;
    asbd.mBytesPerFrame = sizeof(float);
    asbd.mBytesPerPacket = sizeof(float);
    asbd.mFramesPerPacket = 1;
    AudioUnitSetProperty(mAudioUnit, kAudioUnitProperty_StreamFormat,
        kAudioUnitScope_Output, 1, &asbd, sizeof(asbd));

    UInt32 frames = mBufferSize;
    AudioUnitSetProperty(mAudioUnit, kAudioDevicePropertyBufferFrameSize,
        kAudioUnitScope_Global, 0, &frames, sizeof(frames));

    AURenderCallbackStruct callbackStruct = {inputCallback, this};
    AudioUnitSetProperty(mAudioUnit, kAudioOutputUnitProperty_SetInputCallback,
        kAudioUnitScope_Global, 0, &callbackStruct, sizeof(callbackStruct));

    result = AudioUnitInitialize(mAudioUnit);
    if (result != noErr) {
        std::cerr << "[AudioInput] Could not initialize audio unit: " << result << std::endl;
        teardownAudioUnit();
        return false;
    }
    return true;
}

void AudioInput::teardownAudioUnit() {
    if (!mAudioUnit) return;
    AudioUnitUninitialize(mAudioUnit);
    AudioComponentInstanceDispose(mAudioUnit);
    mAudioUnit = nullptr;
}

bool AudioInput::start() {
    if (mRunning || mCurrentDeviceId == 0) return false;
    if (!setupAudioUnit(mCurrentDeviceId)) return false;
    OSStatus result = AudioOutputUnitStart(mAudioUnit);
    if (result != noErr) {
        std::cerr << "[AudioInput] Could not start: " << result << std::endl;
        teardownAudioUnit();
        return false;
    }
    mRunning = true;
    std::cout << "[AudioInput] Started capturing (" << mSampleRate << " Hz, input latency "
              << fixedLatencyUs() / 1000.0 << " ms)" << std::endl;
    return true;
}

// Fully releases the device so a Bluetooth headset can return to its normal profile.
void AudioInput::stop() {
    if (mAudioUnit) {
        if (mRunning) AudioOutputUnitStop(mAudioUnit);
        teardownAudioUnit();
    }
    if (mRunning) std::cout << "[AudioInput] Stopped" << std::endl;
    mRunning = false;
}

size_t AudioInput::read(float* buffer, size_t count) {
    size_t n = mRingBuffer.read(buffer, count);
    mClock.noteRead(n);
    return n;
}

std::vector<AudioInput::DeviceInfo> AudioInput::listInputDevices() {
    std::vector<DeviceInfo> devices;

    AudioObjectPropertyAddress prop = {
        kAudioHardwarePropertyDevices,
        kAudioObjectPropertyScopeGlobal,
        kAudioObjectPropertyElementMain
    };
    UInt32 dataSize = 0;
    AudioObjectGetPropertyDataSize(kAudioObjectSystemObject, &prop, 0, nullptr, &dataSize);
    int deviceCount = dataSize / sizeof(AudioDeviceID);
    std::vector<AudioDeviceID> deviceIds(deviceCount);
    AudioObjectGetPropertyData(kAudioObjectSystemObject, &prop, 0, nullptr, &dataSize, deviceIds.data());

    for (auto devId : deviceIds) {
        // Check if device has input channels
        AudioObjectPropertyAddress streamProp = {
            kAudioDevicePropertyStreamConfiguration,
            kAudioObjectPropertyScopeInput,
            kAudioObjectPropertyElementMain
        };
        UInt32 streamSize = 0;
        if (AudioObjectGetPropertyDataSize(devId, &streamProp, 0, nullptr, &streamSize) != noErr)
            continue;

        std::vector<uint8_t> buf(streamSize);
        auto* bufList = reinterpret_cast<AudioBufferList*>(buf.data());
        if (AudioObjectGetPropertyData(devId, &streamProp, 0, nullptr, &streamSize, bufList) != noErr)
            continue;

        uint32_t inputChannels = 0;
        for (UInt32 i = 0; i < bufList->mNumberBuffers; i++)
            inputChannels += bufList->mBuffers[i].mNumberChannels;
        if (inputChannels == 0) continue;

        // Get device name
        AudioObjectPropertyAddress nameProp = {
            kAudioDevicePropertyDeviceNameCFString,
            kAudioObjectPropertyScopeGlobal,
            kAudioObjectPropertyElementMain
        };
        CFStringRef nameRef = nullptr;
        UInt32 nameSize = sizeof(nameRef);
        if (AudioObjectGetPropertyData(devId, &nameProp, 0, nullptr, &nameSize, &nameRef) == noErr && nameRef) {
            char name[256] = {};
            CFStringGetCString(nameRef, name, sizeof(name), kCFStringEncodingUTF8);
            CFRelease(nameRef);
            devices.push_back({devId, name});
        }
    }
    return devices;
}

// Selects the device. Only opens it if capture is already running.
bool AudioInput::switchDevice(AudioDeviceID deviceId) {
    bool wasRunning = mRunning;
    stop();
    mCurrentDeviceId = deviceId;
    if (uint32_t rate = queryDeviceSampleRate(deviceId)) mSampleRate = rate;
    return wasRunning ? start() : true;
}

OSStatus AudioInput::inputCallback(void* inRefCon,
                                   AudioUnitRenderActionFlags* ioActionFlags,
                                   const AudioTimeStamp* inTimeStamp,
                                   UInt32 inBusNumber,
                                   UInt32 inNumberFrames,
                                   AudioBufferList* ioData)
{
    AudioInput* self = static_cast<AudioInput*>(inRefCon);

    if (inNumberFrames > kMaxCallbackFrames) return kAudioUnitErr_TooManyFramesToProcess;
    self->mInputBufferList->mBuffers[0].mDataByteSize = inNumberFrames * sizeof(float);

    // Render input audio into our buffer
    OSStatus result = AudioUnitRender(self->mAudioUnit, ioActionFlags,
        inTimeStamp, inBusNumber, inNumberFrames, self->mInputBufferList);
    if (result != noErr) return result;

    // Write to ring buffer
    float* samples = static_cast<float*>(self->mInputBufferList->mBuffers[0].mData);
    if (self->mRingBuffer.write(samples, inNumberFrames)) {
        if (inTimeStamp && (inTimeStamp->mFlags & kAudioTimeStampHostTimeValid))
            self->mClock.publish(self->mWritten, inTimeStamp->mHostTime);
        self->mWritten += inNumberFrames;
    }

    return noErr;
}
