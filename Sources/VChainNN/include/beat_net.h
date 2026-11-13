// SPDX-License-Identifier: GPL-3.0-or-later
// Beat This! (MIT) through Core ML: 600 log-mel frames (12 s at 50 frames/s, LogMel) in, beat and downbeat logits out.
// Runs on the Neural Engine (cpuAndNeuralEngine: Resolume keeps the GPU). Call from its own thread, never the audio or
// engine thread: a prediction takes ~40 ms. Plain C++ interface; the implementation is Objective-C++ (beat_net.mm).
#pragma once
#include <memory>
#include <string>

class BeatNet {
public:
    static constexpr int kFrames = 600;
    static constexpr int kBands = 128;

    BeatNet();
    ~BeatNet();
    // modelPath: the bundled .mlpackage (or a compiled .mlmodelc). The first load compiles it (a few seconds) into
    // cacheDir (Application Support in the app) and later loads reuse that. Returns false with a message on failure.
    bool load(const std::string& modelPath, const std::string& cacheDir, std::string* error);
    bool ready() const;
    // frames: kFrames x kBands floats, oldest first. Writes kFrames beat and kFrames downbeat logits.
    bool predict(const float* frames, float* beatLogits, float* downbeatLogits);

private:
    struct Impl;
    std::unique_ptr<Impl> mImpl;
};
