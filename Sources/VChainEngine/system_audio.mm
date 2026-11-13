// SPDX-License-Identifier: GPL-3.0-or-later
#import <ScreenCaptureKit/ScreenCaptureKit.h>
#import <CoreMedia/CoreMedia.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreGraphics/CoreGraphics.h>
#include "system_audio.h"
#include <CoreAudio/CoreAudio.h>
#include <cmath>
#include <vector>
#include <iostream>

// Obj-C delegate that receives audio sample buffers from SCStream
@interface SystemAudioDelegate : NSObject <SCStreamOutput, SCStreamDelegate>
@property (nonatomic, assign) SystemAudio* owner;
@end

@implementation SystemAudioDelegate

- (void)stream:(SCStream *)stream didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer ofType:(SCStreamOutputType)type {
    if (!self.owner) return;
    // Any buffer, the 1 fps 2×2 video frame included, shows the stream is alive (it keeps coming in silence).
    self.owner->noteBuffer();
    if (type != SCStreamOutputTypeAudio) return;

    // Get the audio buffer
    CMBlockBufferRef blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer);
    if (!blockBuffer) return;

    // Get format description to know the audio format
    CMFormatDescriptionRef formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer);
    const AudioStreamBasicDescription* asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc);
    if (!asbd) return;

    size_t totalLength = 0;
    char* dataPointer = nullptr;
    OSStatus status = CMBlockBufferGetDataPointer(blockBuffer, 0, nullptr, &totalLength, &dataPointer);
    if (status != noErr || !dataPointer) return;

    if (asbd->mBytesPerFrame == 0) return;
    size_t frameCount = totalLength / asbd->mBytesPerFrame;

    // Detect actual sample rate from first buffer
    self.owner->setActualSampleRate(static_cast<uint32_t>(asbd->mSampleRate));

    // Capture time of the first sample: the presentation time stamp is on the host time clock.
    uint64_t hostTicks = 0;
    CMTime pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer);
    if (CMTIME_IS_NUMERIC(pts)) hostTicks = CMClockConvertHostTimeToSystemUnits(pts);

    // The stream is configured mono (channelCount = 1): 32-bit float, one channel.
    if ((asbd->mFormatFlags & kAudioFormatFlagIsFloat) && asbd->mBitsPerChannel == 32 && asbd->mChannelsPerFrame == 1)
        self.owner->pushSamples(reinterpret_cast<float*>(dataPointer), frameCount, hostTicks);
}

- (void)stream:(SCStream *)stream didStopWithError:(NSError *)error {
    std::cerr << "[SystemAudio] Stream stopped: "
              << [[error localizedDescription] UTF8String] << std::endl;
    if (self.owner) self.owner->markStopped();
}

@end

// Obj-C wrapper that holds the SCStream and delegate
@interface SystemAudioImpl : NSObject
@property (nonatomic, strong) SCStream* stream;
@property (nonatomic, strong) SystemAudioDelegate* delegate;
@property (nonatomic, strong) dispatch_queue_t audioQueue;
@end

@implementation SystemAudioImpl
@end

// C++ implementation

SystemAudio::SystemAudio(uint32_t sampleRate)
    : mRingBuffer(sampleRate * 2) // 2 seconds buffer
    , mSampleRate(sampleRate)
{
    SystemAudioImpl* impl = [[SystemAudioImpl alloc] init];
    impl.delegate = [[SystemAudioDelegate alloc] init];
    impl.delegate.owner = this;
    impl.audioQueue = dispatch_queue_create("com.bitmapbabe.vchain.systemaudio",
                                             DISPATCH_QUEUE_SERIAL);
    mImpl = (void*)impl;
    [impl retain];
}

SystemAudio::~SystemAudio() {
    stop();
    SystemAudioImpl* impl = (SystemAudioImpl*)mImpl;
    impl.delegate.owner = nullptr;
    [impl release];
    mImpl = nullptr;
}

bool SystemAudio::start() {
    if (mRunning.load()) return false;

    // Request screen capture access (needed for ScreenCaptureKit)
    if (!CGPreflightScreenCaptureAccess()) {
        std::cout << "[SystemAudio] Requesting screen capture permission..." << std::endl;
        if (!CGRequestScreenCaptureAccess()) {
            std::cerr << "[SystemAudio] Screen capture permission not granted. "
                      << "Please enable in System Settings > Privacy & Security > Screen Recording"
                      << std::endl;
            return false;
        }
    }

    __block bool success = false;
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    SystemAudioImpl* impl = (SystemAudioImpl*)mImpl;
    uint32_t requestedSampleRate = mSampleRate;
    SystemAudio* capturedThis = this;

    // Get shareable content — we need a display for the content filter
    [SCShareableContent getShareableContentExcludingDesktopWindows:YES
                                             onScreenWindowsOnly:NO
                                               completionHandler:^(SCShareableContent* content, NSError* error) {
        if (error || content.displays.count == 0) {
            std::cerr << "[SystemAudio] Could not get shareable content: "
                      << (error ? [[error localizedDescription] UTF8String] : "no displays")
                      << std::endl;
            dispatch_semaphore_signal(sem);
            return;
        }

        // Use the main display
        SCDisplay* display = content.displays.firstObject;

        // Configure stream — audio only
        SCStreamConfiguration* config = [[SCStreamConfiguration alloc] init];
        config.capturesAudio = YES;
        config.excludesCurrentProcessAudio = YES;

        // Minimal video to keep SCStream happy
        config.width = 2;
        config.height = 2;
        config.minimumFrameInterval = CMTimeMake(1, 1);
        config.showsCursor = NO;

        // Audio format
        config.sampleRate = requestedSampleRate;
        config.channelCount = 1;

        // Create content filter — use display-based filter
        SCContentFilter* filter = [[SCContentFilter alloc]
            initWithDisplay:display
            excludingApplications:@[]
            exceptingWindows:@[]];

        // Create stream
        impl.stream = [[SCStream alloc] initWithFilter:filter
                                         configuration:config
                                              delegate:impl.delegate];

        // Audio, plus the tiny video frames as a heartbeat (without a screen output SCK also logs an error for
        // every dropped frame).
        NSError* addError = nil;
        [impl.stream addStreamOutput:impl.delegate
                                type:SCStreamOutputTypeAudio
                  sampleHandlerQueue:impl.audioQueue
                               error:&addError];
        if (!addError)
            [impl.stream addStreamOutput:impl.delegate
                                    type:SCStreamOutputTypeScreen
                      sampleHandlerQueue:impl.audioQueue
                                   error:&addError];
        if (addError) {
            std::cerr << "[SystemAudio] Could not add stream output: "
                      << [[addError localizedDescription] UTF8String] << std::endl;
            dispatch_semaphore_signal(sem);
            return;
        }

        [impl.stream startCaptureWithCompletionHandler:^(NSError* startError) {
            if (startError) {
                std::cerr << "[SystemAudio] Could not start capture: "
                          << [[startError localizedDescription] UTF8String] << std::endl;
            } else {
                capturedThis->noteBuffer();
                capturedThis->mRunning.store(true);
                success = true;
                std::cout << "[SystemAudio] Capturing system audio at "
                          << requestedSampleRate << " Hz" << std::endl;
            }
            dispatch_semaphore_signal(sem);
        }];
    }];

    dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC));
    return success;
}

void SystemAudio::stop() {
    // Also when the system already stopped the stream (display sleep): release it either way.
    SystemAudioImpl* impl = (SystemAudioImpl*)mImpl;
    if (!mRunning.load() && !impl.stream) return;
    if (impl.stream) {
        dispatch_semaphore_t sem = dispatch_semaphore_create(0);
        [impl.stream stopCaptureWithCompletionHandler:^(NSError* error) {
            if (error) {
                std::cerr << "[SystemAudio] Error stopping: "
                          << [[error localizedDescription] UTF8String] << std::endl;
            }
            dispatch_semaphore_signal(sem);
        }];
        dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC));
        impl.stream = nil;
    }

    mRunning.store(false);
    std::cout << "[SystemAudio] Stopped" << std::endl;
}

void SystemAudio::noteBuffer() { mLastBufferTicks.store(CaptureClock::nowTicks()); }

bool SystemAudio::isStalled(double seconds) const {
    if (!mRunning.load()) return false;
    static const double ticksPerSecond = [] {
        mach_timebase_info_data_t tb;
        mach_timebase_info(&tb);
        return 1e9 * tb.denom / tb.numer;
    }();
    uint64_t last = mLastBufferTicks.load(), now = CaptureClock::nowTicks();
    return now > last && (now - last) / ticksPerSecond > seconds;
}

size_t SystemAudio::read(float* buffer, size_t count) {
    size_t n = mRingBuffer.read(buffer, count);
    mClock.noteRead(n);
    return n;
}

void SystemAudio::pushSamples(const float* data, size_t count, uint64_t hostTicks) {
    if (!mRingBuffer.write(data, count)) return;
    if (hostTicks) mClock.publish(mWritten, hostTicks);
    mWritten += count;
}

// The default output device's latency after the mix: device latency + safety offset + first output stream's
// latency, in µs. (The IO buffer is left out: whether SCK's time stamp is before or after it is not known; the Beat
// offset covers the rest.)
static double defaultOutputLatencyUs() {
    AudioObjectID dev = 0;
    UInt32 size = sizeof(dev);
    AudioObjectPropertyAddress a = {kAudioHardwarePropertyDefaultOutputDevice, kAudioObjectPropertyScopeGlobal,
                                    kAudioObjectPropertyElementMain};
    if (AudioObjectGetPropertyData(kAudioObjectSystemObject, &a, 0, nullptr, &size, &dev) != noErr || !dev) return 0;
    auto get = [](AudioObjectID o, AudioObjectPropertySelector s, AudioObjectPropertyScope sc) -> UInt32 {
        UInt32 v = 0, n = sizeof(v);
        AudioObjectPropertyAddress p = {s, sc, kAudioObjectPropertyElementMain};
        return AudioObjectGetPropertyData(o, &p, 0, nullptr, &n, &v) == noErr ? v : 0;
    };
    Float64 rate = 0;
    size = sizeof(rate);
    AudioObjectPropertyAddress ra = {kAudioDevicePropertyNominalSampleRate, kAudioObjectPropertyScopeGlobal,
                                     kAudioObjectPropertyElementMain};
    if (AudioObjectGetPropertyData(dev, &ra, 0, nullptr, &size, &rate) != noErr || rate <= 0) return 0;
    UInt32 frames = get(dev, kAudioDevicePropertyLatency, kAudioObjectPropertyScopeOutput) +
                    get(dev, kAudioDevicePropertySafetyOffset, kAudioObjectPropertyScopeOutput);
    AudioObjectPropertyAddress sa = {kAudioDevicePropertyStreams, kAudioObjectPropertyScopeOutput,
                                     kAudioObjectPropertyElementMain};
    if (AudioObjectGetPropertyDataSize(dev, &sa, 0, nullptr, &size) == noErr && size >= sizeof(AudioStreamID)) {
        std::vector<AudioStreamID> streams(size / sizeof(AudioStreamID));
        if (AudioObjectGetPropertyData(dev, &sa, 0, nullptr, &size, streams.data()) == noErr)
            frames += get(streams[0], kAudioStreamPropertyLatency, kAudioObjectPropertyScopeGlobal);
    }
    return frames * 1e6 / rate;
}

double SystemAudio::fixedLatencyUs() {
    uint64_t now = CaptureClock::nowTicks();
    static const uint64_t twoSeconds = [] {
        mach_timebase_info_data_t tb;
        mach_timebase_info(&tb);
        return uint64_t(2e9 * tb.denom / tb.numer);
    }();
    if (mOutputLatencyAt == 0 || now - mOutputLatencyAt > twoSeconds) {
        double us = defaultOutputLatencyUs();
        if (std::abs(us - mOutputLatencyUs) > 500)
            std::cout << "[SystemAudio] output latency " << us / 1000.0 << " ms (default output device)" << std::endl;
        mOutputLatencyUs = us;
        mOutputLatencyAt = now;
    }
    return -mOutputLatencyUs;
}

void SystemAudio::setActualSampleRate(uint32_t rate) {
    uint32_t prev = mActualSampleRate.exchange(rate);
    if (prev == 0 && rate != mSampleRate) {
        std::cout << "[SystemAudio] Actual sample rate from device: " << rate
                  << " Hz (requested " << mSampleRate.load() << ")" << std::endl;
        mSampleRate.store(rate);
    } else if (prev == 0) {
        std::cout << "[SystemAudio] Confirmed sample rate: " << rate << " Hz" << std::endl;
    }
}
