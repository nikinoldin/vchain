// SPDX-License-Identifier: GPL-3.0-or-later
// vChain engine — the C API the Swift front end uses.
//
// The engine owns audio capture (system audio or an input device), the module chain
// (BPM detection + Ableton Link, MIDI analysis + virtual port) and a processing thread.
// Audio threads only write into lock-free ring buffers; the engine thread drains them hop
// by hop, runs the modules and publishes a VCSnapshot the UI polls (copying it is cheap).
// All functions are safe to call from any thread. Input selection can block for a few
// seconds (ScreenCaptureKit start), so call those off the main thread.
#pragma once

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// --- Constants ---

#define VC_BEATS_PER_BAR 4
// Trigger bands (CCs 1-8): VC_MIN_TRIGGER_BANDS..VC_MAX_TRIGGER_BANDS; VC_INSTRUMENT_BANDS (3) = kick / snare / hat,
// any other count = frequency bands (vc_trigger_band_edges).
#define VC_MAX_TRIGGER_BANDS 8
#define VC_MIN_TRIGGER_BANDS 2
#define VC_INSTRUMENT_BANDS 3
#define VC_NUM_DESCRIPTORS 6
#define VC_NUM_SPECTRUM 24
// First CC of the trigger bands (1-8) and of the descriptors (9-14).
#define VC_CC_TRIGGER_BASE 1
#define VC_CC_DESCRIPTOR_BASE 9
// Default MIDI channel, 1-based (set at run time with vc_engine_set_trigger_channel / _descriptor_channel). 16 keeps
// clear of controllers, which mostly use channel 1.
#define VC_MIDI_CHANNEL 16
// How a trigger CC falls back to zero after a hit (vc_engine_set_trigger_decay): in this many beats at the current BPM
// (tempo-locked), or VC_TRIGGER_DECAY_FOLLOW = with the sound's own energy. VC_TRIGGER_DECAY_BEATS until set.
#define VC_TRIGGER_DECAY_FOLLOW 0.0f
#define VC_TRIGGER_DECAY_BEATS 0.5f
// Length of a MIDI learn sweep (vc_engine_send_learn_sweep, vc_learn_sweep_value).
#define VC_LEARN_SWEEP_SECONDS 0.4f

// --- Types ---

typedef enum {
    VC_INPUT_STATE_IDLE = 0,
    VC_INPUT_STATE_STARTING = 1,
    VC_INPUT_STATE_RUNNING = 2,
    VC_INPUT_STATE_NO_PERMISSION = 3, // Screen Recording permission missing (system audio)
    VC_INPUT_STATE_FAILED = 4,
} VCInputState;

typedef enum { VC_MODULE_BPM = 0, VC_MODULE_MIDI = 1 } VCModule;

typedef enum { VC_BEAT_SEARCHING = 0, VC_BEAT_SETTLING = 1, VC_BEAT_LOCKED = 2, VC_BEAT_HOLDING = 3 } VCBeatState;

typedef struct {
    // Input
    int inputState;         // VCInputState
    uint32_t deviceId;      // the current Core Audio input device (0 = none)

    // BPM detection + Link (zeros while the module is off)
    bool bpmEnabled;
    float bpm;              // 0 until detected
    float confidence;       // 0..1
    int linkPeers;
    double linkTempo;
    double linkPhase;       // 0..VC_BEATS_PER_BAR at phaseMicros
    uint64_t phaseMicros;   // vc_now_micros() when linkPhase was taken

    // MIDI analysis (values 0..1, as sent as 14-bit CC)
    int numTriggerBands;
    float triggers[VC_MAX_TRIGGER_BANDS];
    float descriptors[VC_NUM_DESCRIPTORS];
    float spectrum[VC_NUM_SPECTRUM]; // log-spaced 40 Hz-16 kHz, 0..1 (-60..0 dB); zeros while MIDI analysis is off
    bool midiDescriptorsSending; // false while the descriptor CCs (9-14) are paused (the Energy module's plug)

    // Beat grid (BPM module): VCBeatState, and whether Link's beat 0 is the music's 1 (the fish may leap only then)
    int beatState;
    bool barLocked;
} VCSnapshot;

typedef struct {
    uint32_t id;
    char name[256];
} VCDevice;

typedef struct VCEngine VCEngine;

// --- Engine ---

// midiPortName: name of the virtual CoreMIDI source ("vChain").
// Starts with no input and both modules off; configure, then select an input.
VCEngine* vc_engine_create(const char* midiPortName);
void vc_engine_destroy(VCEngine* engine);

void vc_engine_set_module_enabled(VCEngine* engine, int module, bool enabled);

// Each returns the resulting VCInputState. Blocking (up to ~5 s for system audio).
int vc_engine_select_system_audio(VCEngine* engine);
int vc_engine_select_device(VCEngine* engine, uint32_t deviceId);
// Developer input: plays an audio file (looped, real time) into the engine instead of capture.
int vc_engine_select_file(VCEngine* engine, const char* path);

void vc_engine_set_genre(VCEngine* engine, int genreIndex);
// Beat offset calibration, ms (-50..+150): positive puts Link's beats (and vChain's beat display) earlier.
void vc_engine_set_beat_offset_ms(VCEngine* engine, float ms);
// Pauses only the trigger-band CCs 1-8; the descriptor CCs keep sending.
void vc_engine_set_midi_triggers_sending(VCEngine* engine, bool sending);
// Pauses only the descriptor CCs 9-14; the trigger CCs keep sending. Analysis (and the snapshot) carries on.
void vc_engine_set_midi_descriptors_sending(VCEngine* engine, bool sending);
// MIDI learn: sends one CC (1-31, 14-bit like all CCs: LSB on cc + 32) as a single sweep 0 -> 127 -> 0 over VC_LEARN_SWEEP_SECONDS, once, even while that
// CC's continuous sending is paused (its module unplugged); needs the MIDI module enabled (the
// port). While the sweep runs, the continuous value of that CC is held back. A new call restarts the sweep (any CC).
// Thread-safe like the other settings. Returns false if the MIDI module is off or cc is out of range.
bool vc_engine_send_learn_sweep(VCEngine* engine, int cc);
// Number of trigger bands (clamped to VC_MIN_TRIGGER_BANDS..VC_MAX_TRIGGER_BANDS).
void vc_engine_set_num_trigger_bands(VCEngine* engine, int count);
// Trigger decay in beats, or VC_TRIGGER_DECAY_FOLLOW.
void vc_engine_set_trigger_decay(VCEngine* engine, float beats);
// MIDI channels, 1-16 (clamped), VC_MIDI_CHANNEL until set: the trigger CCs 1-8 (BandsDance) and the descriptor CCs
// 9-14 (Annalisa) each go out on their own. A learn sweep goes out on its CC's channel.
void vc_engine_set_trigger_channel(VCEngine* engine, int channel);
void vc_engine_set_descriptor_channel(VCEngine* engine, int channel);
void vc_engine_set_descriptor_enabled(VCEngine* engine, int descriptor, bool enabled);

void vc_engine_get_snapshot(VCEngine* engine, VCSnapshot* out);

// --- Engine-free functions (api_functions.cpp) ---

// Monotonic clock used for phaseMicros.
uint64_t vc_now_micros(void);

// Static info
int vc_genre_count(void);
const char* vc_genre_name(int index);
float vc_genre_center_bpm(int index);
const char* vc_descriptor_name(int descriptor);

// Core Audio input devices; returns how many were written (at most maxCount).
int vc_list_input_devices(VCDevice* out, int maxCount);

// Log-spaced bands (40 Hz-16 kHz): each is the peak magnitude in its bins, in dB, mapped
// -60..0 dB -> 0..1 (magnitude 1.0 = full scale). magnitudes has numBins bins of binHz each.
void vc_spectrum_bands(const float* magnitudes, int numBins, float binHz, float* out, int numBands);
// The numBands + 1 band edges in Hz (count = numBands + 1).
void vc_spectrum_band_edges(float* out, int count);
// FFT size of the display spectrum at a sample rate (Hann-windowed, the last N samples; separate from the analyzer's
// one-hop FFT, which only feeds Change): the smallest power of two with bins of at most 12 Hz (4096 at 48 kHz),
// so each of the 24 bands has a bin of its own.
int vc_spectrum_fft_size(uint32_t sampleRate);

// Trigger band ranges in Hz for count bands (VC_MIN_TRIGGER_BANDS..VC_MAX_TRIGGER_BANDS): fills lo[0..count) and
// hi[0..count). Zones 50-200-2000-16000 Hz split log-spaced per a fixed table (2 bands skip the mid zone,
// from 3 on the bands are contiguous). The analyzer uses this too, so the UI can show ranges from the count.
void vc_trigger_band_edges(int count, float* lo, float* hi);

// The learn sweep's value (0..1) at t seconds into it: up and back down, smooth at both ends; 0 outside.
float vc_learn_sweep_value(float t);

#ifdef __cplusplus
}
#endif
