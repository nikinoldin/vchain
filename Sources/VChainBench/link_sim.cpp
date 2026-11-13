// SPDX-License-Identifier: GPL-3.0-or-later
#include "link_sim.h"
#include <algorithm>

using std::chrono::microseconds;

LinkSim::LinkSim(size_t peers, double initialPhaseBeats, std::vector<LinkSimEdit> edits)
    : mPeers(peers), mEdits(std::move(edits)) {
    // Session created at t = 0 at 120 BPM; a peer that was there first brings its own phase.
    mApi.timeline = ableton::link::Timeline{ableton::link::Tempo(120.0), ableton::link::Beats{-initialPhaseBeats},
                                            microseconds{0}};
    std::sort(mEdits.begin(), mEdits.end(), [](auto& a, auto& b) { return a.at < b.at; });
}

ableton::Link::SessionState LinkSim::state() const { return ableton::Link::SessionState(mApi, mPeers > 0); }
void LinkSim::store(const ableton::Link::SessionState& s) { mApi = ableton::detail::linkApiState(s); }

int LinkSim::advanceTo(int64_t now) {
    int fired = 0;
    while (mNextEdit < mEdits.size() && mEdits[mNextEdit].at <= now) {
        const auto& e = mEdits[mNextEdit++];
        auto s = state();
        switch (e.kind) {
            case LinkSimEdit::Tempo: s.setTempo(e.value, microseconds{e.at}); store(s); break;
            case LinkSimEdit::Phase: {
                ableton::Link::SessionState f(mApi, false); // a peer forcing ignores the quantum
                f.forceBeatAtTime(f.beatAtTime(microseconds{e.at}, 4) + e.value, microseconds{e.at}, 4);
                store(f);
                break;
            }
            case LinkSimEdit::Join: {
                // The joining session wins: its own timeline, keeping the current tempo.
                double bpm = mApi.timeline.tempo.bpm();
                double beatNow = s.beatAtTime(microseconds{e.at}, 4);
                mApi.timeline = ableton::link::Timeline{ableton::link::Tempo(bpm),
                                                        ableton::link::Beats{beatNow + e.value}, microseconds{e.at}};
                mPeers = std::max<size_t>(mPeers, 1);
                break;
            }
        }
        fired++;
    }
    return fired;
}

double LinkSim::tempo() { return mApi.timeline.tempo.bpm(); }
double LinkSim::beatAtTime(int64_t t, double q) { return state().beatAtTime(microseconds{t}, q); }
double LinkSim::phaseAtTime(int64_t t, double q) { return state().phaseAtTime(microseconds{t}, q); }
void LinkSim::setTempo(double bpm, int64_t t) { auto s = state(); s.setTempo(bpm, microseconds{t}); store(s); tempoWrites++; }
void LinkSim::forceBeatAtTime(double beat, int64_t t, double q) {
    auto s = state(); s.forceBeatAtTime(beat, microseconds{t}, q); store(s); forceWrites++;
}
