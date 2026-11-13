// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once

#include <cstdint>

// Shared context passed through the module processing chain.
// Earlier modules populate fields that later modules can read.
struct ModuleContext {
    const float* samples = nullptr;
    uint32_t count = 0;
    // Capture time of samples[0] (mach host ticks) when the input has time stamps, and the input's fixed latency
    // (µs) still to subtract from it (latency compensation).
    bool captureValid = false;
    uint64_t captureTicks = 0;
    double fixedLatencyUs = 0;

    // Populated by the BPM module: the shown tempo (MIDI analysis: tempo-locked trigger decay, Change's beat blocks)
    float bpm = 0;
};

// A unit of audio processing. Resources (Link session, MIDI port, …) exist only while enabled.
// UI and menus live in the Swift front end; modules expose state through accessors.
class Module {
public:
    virtual ~Module() = default;

    virtual const char* name() const = 0;

    // Lifecycle
    virtual void init(uint32_t sampleRate, uint32_t hopSize) = 0;
    virtual void shutdown() = 0;
    virtual void reinit(uint32_t sampleRate, uint32_t hopSize) = 0;

    // Audio processing — called every hop when enabled
    virtual void process(ModuleContext& ctx) = 0;

    bool enabled() const { return mEnabled; }

    void setEnabled(bool e, uint32_t sampleRate, uint32_t hopSize) {
        if (e == mEnabled) return;
        mEnabled = e;
        if (e) init(sampleRate, hopSize);
        else shutdown();
    }

private:
    bool mEnabled = false;
};
