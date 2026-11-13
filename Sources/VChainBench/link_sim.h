// SPDX-License-Identifier: GPL-3.0-or-later
// Simulated Link session for the bench. It runs Link's own SessionState math (ableton::Link::SessionState over
// an ApiState), so tempo/force behave exactly like a real session; peers only change whether the
// quantum is respected. Scheduled foreign edits model someone tapping or typing a BPM in Resolume.
#pragma once
#include "link_port.h"
#include <ableton/Link.hpp>
#include <vector>

struct LinkSimEdit {
    enum Kind { Tempo, Phase, Join } kind;
    int64_t at;      // µs
    double value;    // Tempo: new BPM; Phase: beats to shift; Join: the joining peer's phase (beats)
};

class LinkSim : public LinkPort {
public:
    LinkSim(size_t peers = 1, double initialPhaseBeats = 0.37, std::vector<LinkSimEdit> edits = {});
    // Applies scheduled foreign edits up to `now`; returns how many fired.
    int advanceTo(int64_t now);

    double tempo() override;
    double beatAtTime(int64_t t, double quantum) override;
    double phaseAtTime(int64_t t, double quantum) override;
    void setTempo(double bpm, int64_t t) override;
    void forceBeatAtTime(double beat, int64_t t, double quantum) override;
    size_t numPeers() override { return mPeers; }

    // Counters of what vChain wrote (foreign edits are not counted).
    int tempoWrites = 0, forceWrites = 0;

private:
    ableton::Link::SessionState state() const;
    void store(const ableton::Link::SessionState& s);
    ableton::link::ApiState mApi;
    size_t mPeers;
    std::vector<LinkSimEdit> mEdits;
    size_t mNextEdit = 0;
};
