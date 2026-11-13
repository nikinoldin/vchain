// SPDX-License-Identifier: GPL-3.0-or-later
#include "file_input.h"
#include "beat_engine.h"

#include <AudioToolbox/AudioToolbox.h>

#include <chrono>
#include <cstring>
#include <iostream>

namespace {
constexpr uint32_t kChunk = BeatEngine::kHopSize; // samples per ring write (one engine hop)
} // namespace

FileInput::FileInput() : mRing(kSampleRate * 2) {}

FileInput::~FileInput() { stop(); }

bool FileInput::start(const char* path) {
    stop();
    if (!decode(path)) return false;
    mRunning = true;
    mThread = std::thread([this] { run(); });
    return true;
}

void FileInput::stop() {
    mRunning = false;
    if (mThread.joinable()) mThread.join();
}

size_t FileInput::read(float* out, size_t n) {
    size_t k = mRing.read(out, n);
    mClock.noteRead(k);
    return k;
}

bool FileInput::decode(const char* path) {
    CFURLRef url = CFURLCreateFromFileSystemRepresentation(nullptr, reinterpret_cast<const UInt8*>(path),
                                                           static_cast<CFIndex>(strlen(path)), false);
    ExtAudioFileRef file = nullptr;
    OSStatus err = ExtAudioFileOpenURL(url, &file);
    CFRelease(url);
    if (err != noErr) {
        std::cerr << "[FileInput] Could not open " << path << ": " << err << std::endl;
        return false;
    }
    AudioStreamBasicDescription fmt = {};
    fmt.mSampleRate = kSampleRate;
    fmt.mFormatID = kAudioFormatLinearPCM;
    fmt.mFormatFlags = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked;
    fmt.mChannelsPerFrame = 1;
    fmt.mBitsPerChannel = 32;
    fmt.mBytesPerFrame = 4;
    fmt.mFramesPerPacket = 1;
    fmt.mBytesPerPacket = 4;
    ExtAudioFileSetProperty(file, kExtAudioFileProperty_ClientDataFormat, sizeof(fmt), &fmt);

    mSamples.clear();
    std::vector<float> chunk(8192);
    for (;;) {
        AudioBufferList list;
        list.mNumberBuffers = 1;
        list.mBuffers[0].mNumberChannels = 1;
        list.mBuffers[0].mDataByteSize = static_cast<UInt32>(chunk.size() * sizeof(float));
        list.mBuffers[0].mData = chunk.data();
        UInt32 frames = static_cast<UInt32>(chunk.size());
        if (ExtAudioFileRead(file, &frames, &list) != noErr || frames == 0) break;
        mSamples.insert(mSamples.end(), chunk.begin(), chunk.begin() + frames);
    }
    ExtAudioFileDispose(file);
    std::cout << "[FileInput] " << path << ": " << mSamples.size() / double(kSampleRate) << " s" << std::endl;
    return !mSamples.empty();
}

void FileInput::run() {
    size_t pos = 0;
    auto next = std::chrono::steady_clock::now();
    const auto hop = std::chrono::microseconds(kChunk * 1000000ull / kSampleRate);
    float buf[kChunk];
    while (mRunning) {
        for (uint32_t i = 0; i < kChunk; i++) {
            buf[i] = mSamples[pos];
            pos = (pos + 1) % mSamples.size();
        }
        uint64_t t = CaptureClock::nowTicks();
        if (mRing.write(buf, kChunk)) { mClock.publish(mWritten, t); mWritten += kChunk; }
        next += hop;
        std::this_thread::sleep_until(next);
    }
}
