// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once

#include "module.h"
#include "audio_analyzer.h"
#include "midi_sender.h"
#include <memory>
#include <string>
#include "vchain_engine.h"

class MidiAnalysisModule : public Module {
public:
    MidiAnalysisModule();
    ~MidiAnalysisModule() override;

    const char* name() const override { return "MIDI Analysis"; }

    void init(uint32_t sampleRate, uint32_t hopSize) override;
    void shutdown() override;
    void reinit(uint32_t sampleRate, uint32_t hopSize) override;
    void process(ModuleContext& ctx) override;

    // Settings — kept across disable/enable
    void setPortName(const char* name) { mPortName = name; }
    const char* portName() const { return mPortName.c_str(); }
    // Pauses only the trigger-band CCs (1-8); the descriptors keep going (the keychain's MIDI strip slide).
    void setTriggersSending(bool sending) { mTriggersMuted = !sending; }
    // Pauses only the descriptor CCs (9+); analysis carries on (the keychain's Energy module plug).
    void setDescriptorsSending(bool sending) { mDescriptorsMuted = !sending; }
    bool descriptorsSending() const { return !mDescriptorsMuted; }
    // MIDI learn: one sweep of a single CC (see vc_engine_send_learn_sweep). False if disabled or cc out of range.
    bool startLearnSweep(int cc);
    // 1-16 (clamped): the trigger CCs (1-8, BandsDance) and the descriptor CCs (9+, Annalisa) each have their own.
    void setTriggerChannel(int channel) { mTriggerChannel = clampChannel(channel); }
    void setDescriptorChannel(int channel) { mDescriptorChannel = clampChannel(channel); }
    void setNumTriggerBands(int n);
    int numTriggerBands() const { return mNumTriggerBands; }
    // Trigger decay in beats (VC_TRIGGER_DECAY_FOLLOW = follow the sound).
    void setTriggerDecayBeats(float beats);
    float triggerDecayBeats() const { return mTriggerDecayBeats; }
    void setDescriptorEnabled(int d, bool enabled);

    // Live analyzer state (nullptr while disabled)
    const AudioAnalyzer* analyzer() const { return mAnalyzer.get(); }

    static constexpr uint8_t kCcTriggerBase = VC_CC_TRIGGER_BASE;  // CC 1-8 for the trigger bands
    static constexpr uint8_t kCcDescBase = VC_CC_DESCRIPTOR_BASE;  // CC 9+ for descriptors

private:
    std::unique_ptr<AudioAnalyzer> mAnalyzer;
    std::unique_ptr<MidiSender> mMidiSender;

    uint32_t mSampleRate = 0;
    uint32_t mHopSize = 0;
    int mNumTriggerBands = VC_INSTRUMENT_BANDS;
    float mTriggerDecayBeats = VC_TRIGGER_DECAY_BEATS;
    static int clampChannel(int c) { return c < 1 ? 1 : (c > 16 ? 16 : c); }
    int mTriggerChannel = VC_MIDI_CHANNEL;    // 1-based
    int mDescriptorChannel = VC_MIDI_CHANNEL; // 1-based
    bool mTriggersMuted = false; // trigger CCs 1-8 only
    bool mDescriptorsMuted = false; // descriptor CCs only
    int mLearnCC = 0;              // 0 = no learn sweep running
    double mLearnTime = 0;         // seconds into it
    bool mDescEnabled[AudioAnalyzer::DESC_COUNT] = {true, true, true, true, true, true};
    std::string mPortName = "vChain";
};
