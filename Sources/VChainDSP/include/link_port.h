// SPDX-License-Identifier: GPL-3.0-or-later
// The only way VChainDSP talks to Ableton Link. The engine wraps a real ableton::Link session (RealLinkPort in
// real_link_port.h, owned by BpmModule); the bench plugs in a simulated session. Times are Link-clock microseconds.
#pragma once

#include <cstddef>
#include <cstdint>

// Beats per bar: the quantum of every beat/phase query and forced beat (VC_BEATS_PER_BAR in the C API).
constexpr double kLinkQuantum = 4;

class LinkPort {
public:
    virtual ~LinkPort() = default;
    virtual double tempo() = 0;
    virtual double beatAtTime(int64_t t, double quantum) = 0;
    virtual double phaseAtTime(int64_t t, double quantum) = 0;
    // Keeps the beat at t, changes the tempo from t on.
    virtual void setTempo(double bpm, int64_t t) = 0;
    // Re-maps beat/time for every peer: beatAtTime(t, quantum) == beat afterwards.
    virtual void forceBeatAtTime(double beat, int64_t t, double quantum) = 0;
    virtual size_t numPeers() = 0;
    // End of a hop: a real session commits everything written during the hop as ONE app commit. Real Link
    // applies commits through its own thread, and back-to-back commits can overwrite each other.
    virtual void flush() {}
};
