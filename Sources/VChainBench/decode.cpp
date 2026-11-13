// SPDX-License-Identifier: GPL-3.0-or-later
#include "decode.h"
#include <AudioToolbox/AudioToolbox.h>
#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstring>

bool decodeFile(const std::string& path, double sampleRate, std::vector<float>& out) {
    CFURLRef url = CFURLCreateFromFileSystemRepresentation(nullptr, reinterpret_cast<const UInt8*>(path.c_str()),
                                                           CFIndex(path.size()), false);
    ExtAudioFileRef file = nullptr;
    OSStatus err = ExtAudioFileOpenURL(url, &file);
    CFRelease(url);
    if (err != noErr) return false;
    AudioStreamBasicDescription fmt = {};
    fmt.mSampleRate = sampleRate;
    fmt.mFormatID = kAudioFormatLinearPCM;
    fmt.mFormatFlags = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked;
    fmt.mChannelsPerFrame = 1;
    fmt.mBitsPerChannel = 32;
    fmt.mBytesPerFrame = 4;
    fmt.mFramesPerPacket = 1;
    fmt.mBytesPerPacket = 4;
    ExtAudioFileSetProperty(file, kExtAudioFileProperty_ClientDataFormat, sizeof(fmt), &fmt);
    out.clear();
    std::vector<float> chunk(32768);
    for (;;) {
        AudioBufferList list;
        list.mNumberBuffers = 1;
        list.mBuffers[0].mNumberChannels = 1;
        list.mBuffers[0].mDataByteSize = UInt32(chunk.size() * sizeof(float));
        list.mBuffers[0].mData = chunk.data();
        UInt32 frames = UInt32(chunk.size());
        if (ExtAudioFileRead(file, &frames, &list) != noErr || frames == 0) break;
        out.insert(out.end(), chunk.begin(), chunk.begin() + frames);
    }
    ExtAudioFileDispose(file);
    return !out.empty();
}

bool writeWav(const std::string& path, const std::vector<float>& samples, double sampleRate, int channels) {
    FILE* f = fopen(path.c_str(), "wb");
    if (!f) return false;
    uint32_t sr = uint32_t(sampleRate), dataBytes = uint32_t(samples.size() * 2);
    auto u32 = [&](uint32_t v) { fwrite(&v, 4, 1, f); };
    auto u16 = [&](uint16_t v) { fwrite(&v, 2, 1, f); };
    fwrite("RIFF", 1, 4, f); u32(36 + dataBytes); fwrite("WAVEfmt ", 1, 8, f);
    u32(16); u16(1); u16(uint16_t(channels)); u32(sr); u32(sr * channels * 2); u16(uint16_t(channels * 2)); u16(16);
    fwrite("data", 1, 4, f); u32(dataBytes);
    for (float v : samples) {
        int16_t s = int16_t(std::lround(std::clamp(v, -1.0f, 1.0f) * 32767.0f));
        fwrite(&s, 2, 1, f);
    }
    fclose(f);
    return true;
}
