// SPDX-License-Identifier: GPL-3.0-or-later
// Procedural club-music scenarios with exact truth, rendered in memory at 48 kHz from a fixed seed.
// No samples: every sound is synthesized here (sample packs can't be
// redistributed). See docs/beat-tracking.md, "Synthetic scenarios".
#pragma once
#include "link_sim.h"
#include "truth.h"
#include <cstdint>
#include <string>
#include <vector>

struct Scenario {
    std::string name;
    std::vector<float> audio; // mono, 48 kHz
    Annotation truth;
    std::vector<LinkSimEdit> linkEdits; // foreign edits for the `edit` Link mode
    std::vector<std::string> tags;      // section tags for per-tag totals
};

constexpr double kSynthRate = 48000.0;

std::vector<std::string> scenarioNames();
Scenario makeScenario(const std::string& name, uint32_t seed = 1);

// Linear-interpolation resampler (ratio = out rate / in rate); used for the 44.1 kHz check.
std::vector<float> resampleLinear(const std::vector<float>& in, double ratio);
