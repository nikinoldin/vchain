// SPDX-License-Identifier: GPL-3.0-or-later
// The engine-free part of the C API (include/vchain_engine.h): the clock, static info, input devices, and the pure
// functions the UI shares with the analyzer (spectrum bands, trigger band ranges, the learn sweep).
#include "vchain_engine.h"

#include "audio_analyzer.h"
#include "audio_input.h"
#include "genre.h"
#include "trigger_bands.h"

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstring>

namespace {
// Display spectrum bands: log-spaced over 40 Hz-16 kHz, -60..0 dB.
constexpr float kLoHz = 40.0f;
constexpr float kHiHz = 16000.0f;
constexpr float kFloorDb = -60.0f;

float edgeHz(int i, int numBands) {
    return kLoHz * std::pow(kHiHz / kLoHz, static_cast<float>(i) / static_cast<float>(numBands));
}
} // namespace

extern "C" {

uint64_t vc_now_micros(void) {
    using namespace std::chrono;
    return static_cast<uint64_t>(duration_cast<microseconds>(steady_clock::now().time_since_epoch()).count());
}

// --- Static info ---

int vc_genre_count(void) { return static_cast<int>(getGenrePresets().size()); }

const char* vc_genre_name(int index) {
    if (index < 0 || index >= vc_genre_count()) return "";
    return getGenrePresets()[index].name.c_str();
}

float vc_genre_center_bpm(int index) {
    if (index < 0 || index >= vc_genre_count()) return 0;
    return getGenrePresets()[index].centerBpm;
}

const char* vc_descriptor_name(int descriptor) { return AudioAnalyzer::descriptorName(descriptor); }

int vc_list_input_devices(VCDevice* out, int maxCount) {
    auto devices = AudioInput::listInputDevices();
    int n = 0;
    for (const auto& d : devices) {
        if (n >= maxCount) break;
        out[n].id = static_cast<uint32_t>(d.id);
        strlcpy(out[n].name, d.name.c_str(), sizeof(out[n].name));
        n++;
    }
    return n;
}

// --- Display spectrum ---

int vc_spectrum_fft_size(uint32_t sampleRate) {
    // Bins of at most ~12 Hz: the narrowest (lowest) bands are ~11 Hz wide.
    int size = 1024;
    while (size < 65536 && static_cast<float>(sampleRate) / static_cast<float>(size) > 12.0f) size *= 2;
    return size;
}

void vc_spectrum_band_edges(float* out, int count) {
    int numBands = count - 1;
    if (!out || numBands < 1) return;
    for (int i = 0; i <= numBands; i++) out[i] = edgeHz(i, numBands);
}

void vc_spectrum_bands(const float* magnitudes, int numBins, float binHz, float* out, int numBands) {
    if (!out || numBands < 1) return;
    for (int b = 0; b < numBands; b++) out[b] = 0.0f;
    if (!magnitudes || numBins < 1 || binHz <= 0.0f) return;

    for (int b = 0; b < numBands; b++) {
        float lo = edgeHz(b, numBands), hi = edgeHz(b + 1, numBands);
        int first = std::max(0, static_cast<int>(std::ceil(lo / binHz)));
        int last = std::min(numBins - 1, static_cast<int>(std::floor(hi / binHz)));
        if (first > last) {
            // Band narrower than one bin: take the bin nearest its geometric centre.
            int nearest = static_cast<int>(std::lround(std::sqrt(lo * hi) / binHz));
            first = last = std::clamp(nearest, 0, numBins - 1);
        }
        float peak = 0.0f;
        for (int i = first; i <= last; i++) peak = std::max(peak, magnitudes[i]);
        float db = peak > 1e-9f ? 20.0f * std::log10(peak) : kFloorDb;
        out[b] = std::clamp((db - kFloorDb) / -kFloorDb, 0.0f, 1.0f);
    }
}

// --- Trigger bands and MIDI learn ---

void vc_trigger_band_edges(int count, float* lo, float* hi) {
    if (lo && hi) triggerBandEdges(count, lo, hi);
}

float vc_learn_sweep_value(float t) {
    if (!(t > 0) || t >= VC_LEARN_SWEEP_SECONDS) return 0;
    const float p = t / VC_LEARN_SWEEP_SECONDS;     // 0..1
    const float x = p < 0.5f ? p * 2 : (1 - p) * 2; // 0 -> 1 -> 0
    return x * x * (3 - 2 * x);                     // smoothstep each way
}

} // extern "C"
