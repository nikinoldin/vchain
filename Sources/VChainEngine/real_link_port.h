// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once

#include "link_port.h"
#include <ableton/Link.hpp>
#include <optional>

// LinkPort over a real ableton::Link session: the app session state is captured once per hop and everything written
// during the hop goes out as ONE commit on flush() (real Link applies commits on its own thread; back-to-back commits
// can overwrite each other).
class RealLinkPort : public LinkPort {
public:
    explicit RealLinkPort(ableton::Link& link) : mLink(link) {}
    double tempo() override { return state().tempo(); }
    double beatAtTime(int64_t t, double q) override { return state().beatAtTime(std::chrono::microseconds{t}, q); }
    double phaseAtTime(int64_t t, double q) override { return state().phaseAtTime(std::chrono::microseconds{t}, q); }
    void setTempo(double bpm, int64_t t) override { state().setTempo(bpm, std::chrono::microseconds{t}); mDirty = true; }
    void forceBeatAtTime(double beat, int64_t t, double q) override {
        state().forceBeatAtTime(beat, std::chrono::microseconds{t}, q); mDirty = true;
    }
    size_t numPeers() override { return mLink.numPeers(); }
    void flush() override {
        if (mDirty && mState) mLink.commitAppSessionState(*mState);
        mState.reset();
        mDirty = false;
    }

private:
    ableton::Link::SessionState& state() {
        if (!mState) mState.emplace(mLink.captureAppSessionState());
        return *mState;
    }
    ableton::Link& mLink;
    std::optional<ableton::Link::SessionState> mState;
    bool mDirty = false;
};
