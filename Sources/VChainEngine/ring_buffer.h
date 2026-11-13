// SPDX-License-Identifier: GPL-3.0-or-later
// Lock-free single-producer single-consumer ring buffer for audio samples: an audio thread writes, the engine
// thread reads. Holds capacity - 1 samples.
#pragma once

#include <algorithm>
#include <atomic>
#include <cstddef>
#include <cstring>
#include <memory>

class RingBuffer {
public:
    explicit RingBuffer(size_t capacity) : mCapacity(capacity), mBuffer(new float[capacity]) {}

    size_t available() const {
        size_t w = mWritePos.load(std::memory_order_acquire);
        size_t r = mReadPos.load(std::memory_order_relaxed);
        return (w >= r) ? (w - r) : (mCapacity - r + w);
    }

    // All or nothing: false (nothing written) if count samples don't fit.
    bool write(const float* data, size_t count) {
        size_t w = mWritePos.load(std::memory_order_relaxed);
        size_t r = mReadPos.load(std::memory_order_acquire);
        size_t space = (r > w) ? (r - w - 1) : (mCapacity - w + r - 1);
        if (count > space) return false;

        size_t firstChunk = std::min(count, mCapacity - w);
        std::memcpy(mBuffer.get() + w, data, firstChunk * sizeof(float));
        if (count > firstChunk) std::memcpy(mBuffer.get(), data + firstChunk, (count - firstChunk) * sizeof(float));
        mWritePos.store((w + count) % mCapacity, std::memory_order_release);
        return true;
    }

    // Reads up to count samples; returns how many were read.
    size_t read(float* data, size_t count) {
        size_t toRead = std::min(count, available());
        if (toRead == 0) return 0;

        size_t r = mReadPos.load(std::memory_order_relaxed);
        size_t firstChunk = std::min(toRead, mCapacity - r);
        std::memcpy(data, mBuffer.get() + r, firstChunk * sizeof(float));
        if (toRead > firstChunk) std::memcpy(data + firstChunk, mBuffer.get(), (toRead - firstChunk) * sizeof(float));
        mReadPos.store((r + toRead) % mCapacity, std::memory_order_release);
        return toRead;
    }

private:
    size_t mCapacity;
    std::unique_ptr<float[]> mBuffer;
    std::atomic<size_t> mReadPos{0};
    std::atomic<size_t> mWritePos{0};
};
