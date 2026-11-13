// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once

#include <cmath>
#include <string>
#include <vector>

struct GenrePreset {
    std::string name;
    float centerBpm;
    float sigma; // standard deviation for Gaussian prior

    // Compute Gaussian weight for a given BPM
    float weight(float bpm) const {
        float diff = bpm - centerBpm;
        return std::exp(-0.5f * (diff * diff) / (sigma * sigma));
    }
};

inline const std::vector<GenrePreset>& getGenrePresets() {
    static const std::vector<GenrePreset> presets = {
        {"Auto",    120.0f, 50.0f},
        {"House",   125.0f, 15.0f},
        {"Techno",  135.0f, 15.0f},
        {"D&B",     170.0f, 10.0f},
        {"Hip-Hop",  90.0f, 15.0f},
        {"Pop",     115.0f, 25.0f},
    };
    return presets;
}
