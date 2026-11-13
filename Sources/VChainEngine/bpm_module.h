// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once

#include "beat_engine.h"
#include "module.h"
#include "nn_front_end.h"
#include "real_link_port.h"
#include "vchain_engine.h"
#include <memory>

// BPM detection + Ableton Link via VChainDSP's BeatEngine: the tempo is the
// grid fit to kick/snare onsets (aubio only as the coarse estimate and octave guard), committed to Link with hysteresis;
// the phase is steered by small tempo nudges from that grid while it is locked (otherwise held), with one jump only at
// the first lock or a new track. See docs/beat-tracking.md.
class BpmModule : public Module {
public:
    BpmModule();
    ~BpmModule() override;

    const char* name() const override { return "BPM Detection"; }

    void init(uint32_t sampleRate, uint32_t hopSize) override;
    void shutdown() override;
    void reinit(uint32_t sampleRate, uint32_t hopSize) override;
    void process(ModuleContext& ctx) override;

    void setGenrePreset(int index);
    // Beat offset (Settings): positive puts Link's beats earlier, for Resolume/projector video latency. -50..+150 ms.
    void setBeatOffsetMs(float ms);

    // Live state for the UI snapshot (call from the engine thread, while enabled)
    float bpm() const;
    float confidence() const;
    int linkPeers() const;
    int beatState() const;          // VCBeatState
    bool barLocked() const;         // Link's beat 0 is the music's 1
    // Link beat phase (0..quantum) and tempo right now
    void linkPhase(double& phase, double& tempo) const;

private:
    std::unique_ptr<BeatEngine> mEngine;
    std::unique_ptr<ableton::Link> mLink;
    std::unique_ptr<RealLinkPort> mPort;
    NNFrontEnd mNN;               // Beat This! on its own thread; hybrid once the model is ready
    bool mHybridOn = false;

    uint32_t mSampleRate = 0;
    int mGenreIndex = 0;
    float mBeatOffsetMs = 0;
    bool mCompensated = false;     // the last hop had capture time stamps
    double mInputDelayUs = 0;      // processing minus capture time of a hop's last sample, smoothed (logged)
    int64_t mLastDelayLog = 0;

    static constexpr double kQuantum = VC_BEATS_PER_BAR;
};
