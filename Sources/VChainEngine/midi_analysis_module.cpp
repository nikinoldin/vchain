// SPDX-License-Identifier: GPL-3.0-or-later
#include "midi_analysis_module.h"
#include <iostream>

MidiAnalysisModule::MidiAnalysisModule() {}

MidiAnalysisModule::~MidiAnalysisModule() {
    if (enabled()) shutdown();
}

void MidiAnalysisModule::init(uint32_t sampleRate, uint32_t hopSize) {
    mSampleRate = sampleRate;
    mHopSize = hopSize;
    mAnalyzer = std::make_unique<AudioAnalyzer>(sampleRate, hopSize, mNumTriggerBands);
    for (int d = 0; d < AudioAnalyzer::DESC_COUNT; d++)
        mAnalyzer->setDescriptorEnabled(d, mDescEnabled[d]);
    mAnalyzer->setTriggerDecayBeats(mTriggerDecayBeats);
    mMidiSender = std::make_unique<MidiSender>(mPortName.c_str());
    std::cout << "[MidiAnalysis] Initialized with " << mNumTriggerBands << " trigger bands" << std::endl;
}

void MidiAnalysisModule::shutdown() {
    mMidiSender.reset();
    mAnalyzer.reset();
    std::cout << "[MidiAnalysis] Shutdown" << std::endl;
}

void MidiAnalysisModule::reinit(uint32_t sampleRate, uint32_t hopSize) {
    mSampleRate = sampleRate;
    mHopSize = hopSize;
    if (mAnalyzer) mAnalyzer->reinit(sampleRate, hopSize);
}

void MidiAnalysisModule::process(ModuleContext& ctx) {
    if (!mAnalyzer || !mMidiSender) return;

    mAnalyzer->process(ctx.samples, ctx.count, ctx.bpm);
    const uint8_t triggerCh = static_cast<uint8_t>(mTriggerChannel - 1);
    const uint8_t descCh = static_cast<uint8_t>(mDescriptorChannel - 1);

    // Send MIDI (unless paused; the trigger and descriptor CCs each have their own pause). A CC being learned is held
    // back while its sweep runs.
    if (!mTriggersMuted) {
        for (int i = 0; i < mAnalyzer->numTriggerBands(); i++)
            if (kCcTriggerBase + i != mLearnCC)
                mMidiSender->sendCC(triggerCh, kCcTriggerBase + i, mAnalyzer->trigger(i));
    }
    if (!mDescriptorsMuted) {
        for (int d = 0; d < AudioAnalyzer::DESC_COUNT; d++) {
            if (mAnalyzer->descriptorEnabled(d) && kCcDescBase + d != mLearnCC)
                mMidiSender->sendCC(descCh, kCcDescBase + d, mAnalyzer->descriptor(d));
        }
    }

    // MIDI learn sweep: one CC, 0 -> 1 -> 0, whatever is paused; on the channel of the module that CC belongs to.
    if (mLearnCC > 0) {
        const uint8_t channel = mLearnCC < kCcDescBase ? triggerCh : descCh;
        mMidiSender->sendCC(channel, static_cast<uint8_t>(mLearnCC), vc_learn_sweep_value(static_cast<float>(mLearnTime)));
        mLearnTime += mSampleRate > 0 ? static_cast<double>(mHopSize) / mSampleRate : 0.01;
        if (mLearnTime > VC_LEARN_SWEEP_SECONDS) {
            mMidiSender->sendCC(channel, static_cast<uint8_t>(mLearnCC), 0);
            mLearnCC = 0;
        }
    }
}

bool MidiAnalysisModule::startLearnSweep(int cc) {
    if (!mMidiSender || cc < 1 || cc > 31) return false;  // 14-bit: the LSB goes out on cc + 32
    mLearnCC = cc;
    mLearnTime = 0;
    return true;
}

void MidiAnalysisModule::setNumTriggerBands(int n) {
    mNumTriggerBands = n;
    if (mAnalyzer) mAnalyzer->setNumTriggerBands(n);
}

void MidiAnalysisModule::setTriggerDecayBeats(float beats) {
    mTriggerDecayBeats = beats > 0 ? beats : 0;
    if (mAnalyzer) mAnalyzer->setTriggerDecayBeats(mTriggerDecayBeats);
}

void MidiAnalysisModule::setDescriptorEnabled(int d, bool enabled) {
    if (d < 0 || d >= AudioAnalyzer::DESC_COUNT) return;
    mDescEnabled[d] = enabled;
    if (mAnalyzer) mAnalyzer->setDescriptorEnabled(d, enabled);
}
