// SPDX-License-Identifier: GPL-3.0-or-later
// Core engine: audio input, module chain and the processing thread behind the C API.
// Hop-by-hop processing on its own thread, so the UI never waits on audio work and vice versa.

#include "vchain_engine.h"

#include "audio_analyzer.h"
#include "audio_input.h"
#include "bpm_module.h"
#include "file_input.h"
#include "midi_analysis_module.h"
#include "system_audio.h"

#include <CoreGraphics/CoreGraphics.h>

#include <algorithm>
#include <atomic>
#include <chrono>
#include <iostream>
#include <mutex>
#include <thread>
#include <vector>

namespace {
constexpr uint32_t kHopSize = BeatEngine::kHopSize;
constexpr uint32_t kSystemAudioRate = 48000;
} // namespace

struct VCEngine {
    // Guards modules and inputs. Held by the processing thread while it drains a batch of
    // hops, and by the API calls that change configuration.
    std::mutex mutex;
    // Serializes input selections. Starting System Audio waits up to 5 s for ScreenCaptureKit and stopping it up to
    // 3 s, so selectInput() does that holding only this lock, not `mutex` (the engine thread and every setter would
    // wait): under `mutex` it detaches the engine thread from all inputs (`input` nullptr: the engine thread then
    // reads none of them), stops, drains and starts them unlocked, and attaches the new one under `mutex` again.
    std::mutex selectMutex;
    BpmModule bpm;
    MidiAnalysisModule midi;
    std::vector<Module*> modules{&bpm, &midi};

    AudioInput audioInput;
    SystemAudio systemAudio{kSystemAudioRate};
    FileInput fileInput;
    AudioSource* const inputs[3] = {&systemAudio, &audioInput, &fileInput};
    AudioSource* input = nullptr; // the one the engine thread reads (nullptr = none)
    int inputState = VC_INPUT_STATE_IDLE;
    uint32_t sampleRate = kSystemAudioRate;

    std::mutex snapshotMutex;
    VCSnapshot snapshot{};

    std::atomic<bool> running{true};
    std::thread worker;

    explicit VCEngine(const char* portName) {
        midi.setPortName(portName ? portName : "vChain");
        worker = std::thread([this] { run(); });
    }

    ~VCEngine() {
        running = false;
        if (worker.joinable()) worker.join();
        std::lock_guard<std::mutex> lock(mutex);
        stopInputs();
        for (auto* mod : modules)
            if (mod->enabled()) mod->setEnabled(false, sampleRate, kHopSize);
    }

    // --- called while the engine thread reads no input (input nullptr, or the thread stopped) ---

    // Stops every input and discards the audio left in its ring buffer.
    void stopInputs() {
        for (auto* in : inputs) in->stop();
        float scratch[kHopSize];
        for (auto* in : inputs)
            while (in->read(scratch, kHopSize) > 0) {}
    }

    // Switches to `source`: start() starts it and returns its VC_INPUT_STATE_*. See selectMutex.
    template <typename Start>
    int selectInput(AudioSource* source, Start start) {
        std::lock_guard<std::mutex> select(selectMutex);
        {
            std::lock_guard<std::mutex> lock(mutex);
            input = nullptr;
            inputState = VC_INPUT_STATE_STARTING;
        }
        stopInputs();
        uint32_t rate = 0;
        int state = start(rate);
        std::lock_guard<std::mutex> lock(mutex);
        input = source;
        inputState = state;
        sampleRate = rate;
        reinitModules();
        return state;
    }

    // --- called with `mutex` held ---

    void reinitModules() {
        for (auto* mod : modules)
            if (mod->enabled()) mod->reinit(sampleRate, kHopSize);
    }

    void processAvailable() {
        if (!input) return;
        // System audio reports its real rate only after the first buffer arrives.
        if (input->sampleRate() != sampleRate) {
            sampleRate = input->sampleRate();
            reinitModules();
            std::cout << "[Engine] Reinit at " << sampleRate << " Hz" << std::endl;
        }

        float buf[kHopSize];
        while (input->available() >= kHopSize) {
            // Capture time (host ticks) of the hop's first sample, and the input's fixed latency to subtract.
            const double fixedLatencyUs = input->fixedLatencyUs();
            uint64_t captureTicks = 0;
            const bool haveCapture = input->nextReadTicks(captureTicks);
            if (input->read(buf, kHopSize) < kHopSize) break;

            ModuleContext ctx;
            ctx.samples = buf;
            ctx.count = kHopSize;
            ctx.captureValid = haveCapture;
            ctx.captureTicks = captureTicks;
            ctx.fixedLatencyUs = fixedLatencyUs;
            for (auto* mod : modules)
                if (mod->enabled()) mod->process(ctx);
        }
    }

    void fillSnapshot(VCSnapshot& s) {
        s = VCSnapshot{};
        s.inputState = inputState;
        if (input && inputState == VC_INPUT_STATE_RUNNING && input->lost())
            s.inputState = VC_INPUT_STATE_FAILED; // stream stopped by the system (display sleep); the app retries
        s.deviceId = audioInput.currentDeviceId();

        s.bpmEnabled = bpm.enabled();
        if (s.bpmEnabled) {
            s.bpm = bpm.bpm();
            s.confidence = bpm.confidence();
            s.linkPeers = bpm.linkPeers();
            s.beatState = bpm.beatState();
            s.barLocked = bpm.barLocked();
            bpm.linkPhase(s.linkPhase, s.linkTempo);
            s.phaseMicros = vc_now_micros();
        }

        s.midiDescriptorsSending = midi.descriptorsSending();
        s.numTriggerBands = midi.numTriggerBands();
        if (const AudioAnalyzer* a = midi.analyzer()) {
            s.numTriggerBands = a->numTriggerBands();
            for (int i = 0; i < s.numTriggerBands && i < VC_MAX_TRIGGER_BANDS; i++) s.triggers[i] = a->trigger(i);
            for (int d = 0; d < VC_NUM_DESCRIPTORS; d++) s.descriptors[d] = a->descriptor(d);
            std::copy(a->spectrum(), a->spectrum() + VC_NUM_SPECTRUM, s.spectrum);
        }
    }

    void run() {
        while (running) {
            VCSnapshot s;
            {
                std::lock_guard<std::mutex> lock(mutex);
                processAvailable();
                fillSnapshot(s);
            }
            {
                std::lock_guard<std::mutex> lock(snapshotMutex);
                snapshot = s;
            }
            // A hop is ~10.7 ms at 48 kHz; polling faster keeps latency low without busy-waiting.
            std::this_thread::sleep_for(std::chrono::milliseconds(3));
        }
    }
};

extern "C" {

VCEngine* vc_engine_create(const char* midiPortName) { return new VCEngine(midiPortName); }

void vc_engine_destroy(VCEngine* engine) { delete engine; }

void vc_engine_set_module_enabled(VCEngine* e, int module, bool enabled) {
    std::lock_guard<std::mutex> lock(e->mutex);
    Module* mod = module == VC_MODULE_BPM ? static_cast<Module*>(&e->bpm) : &e->midi;
    if (mod->enabled() == enabled) return;
    mod->setEnabled(enabled, e->sampleRate, kHopSize);
    std::cout << "[Engine] " << mod->name() << (enabled ? " enabled" : " disabled") << std::endl;
}

int vc_engine_select_system_audio(VCEngine* e) {
    int state = e->selectInput(&e->systemAudio, [e](uint32_t& rate) {
        int s = VC_INPUT_STATE_RUNNING;
        if (!e->systemAudio.start())
            s = CGPreflightScreenCaptureAccess() ? VC_INPUT_STATE_FAILED : VC_INPUT_STATE_NO_PERMISSION;
        rate = e->systemAudio.sampleRate();
        return s;
    });
    std::cout << "[Engine] Input: System Audio" << std::endl;
    return state;
}

int vc_engine_select_device(VCEngine* e, uint32_t deviceId) {
    return e->selectInput(&e->audioInput, [e, deviceId](uint32_t& rate) {
        e->audioInput.switchDevice(static_cast<AudioDeviceID>(deviceId));
        int s = e->audioInput.start() ? VC_INPUT_STATE_RUNNING : VC_INPUT_STATE_FAILED;
        rate = e->audioInput.sampleRate();
        std::cout << "[Engine] Input: device " << deviceId << " at " << rate << " Hz" << std::endl;
        return s;
    });
}

int vc_engine_select_file(VCEngine* e, const char* path) {
    return e->selectInput(&e->fileInput, [e, path](uint32_t& rate) {
        int s = e->fileInput.start(path) ? VC_INPUT_STATE_RUNNING : VC_INPUT_STATE_FAILED;
        rate = e->fileInput.sampleRate();
        return s;
    });
}

void vc_engine_set_genre(VCEngine* e, int genreIndex) {
    std::lock_guard<std::mutex> lock(e->mutex);
    if (genreIndex >= 0 && genreIndex < vc_genre_count()) e->bpm.setGenrePreset(genreIndex);
}

void vc_engine_set_beat_offset_ms(VCEngine* e, float ms) {
    std::lock_guard<std::mutex> lock(e->mutex);
    e->bpm.setBeatOffsetMs(ms);
}

void vc_engine_set_midi_triggers_sending(VCEngine* e, bool sending) {
    std::lock_guard<std::mutex> lock(e->mutex);
    e->midi.setTriggersSending(sending);
}

void vc_engine_set_midi_descriptors_sending(VCEngine* e, bool sending) {
    std::lock_guard<std::mutex> lock(e->mutex);
    e->midi.setDescriptorsSending(sending);
}

bool vc_engine_send_learn_sweep(VCEngine* e, int cc) {
    std::lock_guard<std::mutex> lock(e->mutex);
    return e->midi.startLearnSweep(cc);
}

void vc_engine_set_num_trigger_bands(VCEngine* e, int count) {
    std::lock_guard<std::mutex> lock(e->mutex);
    e->midi.setNumTriggerBands(std::clamp(count, VC_MIN_TRIGGER_BANDS, VC_MAX_TRIGGER_BANDS));
}

void vc_engine_set_trigger_decay(VCEngine* e, float beats) {
    std::lock_guard<std::mutex> lock(e->mutex);
    e->midi.setTriggerDecayBeats(beats);
}

void vc_engine_set_trigger_channel(VCEngine* e, int channel) {
    std::lock_guard<std::mutex> lock(e->mutex);
    e->midi.setTriggerChannel(channel);
}

void vc_engine_set_descriptor_channel(VCEngine* e, int channel) {
    std::lock_guard<std::mutex> lock(e->mutex);
    e->midi.setDescriptorChannel(channel);
}

void vc_engine_set_descriptor_enabled(VCEngine* e, int descriptor, bool enabled) {
    std::lock_guard<std::mutex> lock(e->mutex);
    e->midi.setDescriptorEnabled(descriptor, enabled);
}

void vc_engine_get_snapshot(VCEngine* e, VCSnapshot* out) {
    std::lock_guard<std::mutex> lock(e->snapshotMutex);
    *out = e->snapshot;
}

} // extern "C"
