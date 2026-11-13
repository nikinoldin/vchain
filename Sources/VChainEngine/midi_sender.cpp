// SPDX-License-Identifier: GPL-3.0-or-later
#include "midi_sender.h"
#include <CoreMIDI/CoreMIDI.h>
#include <algorithm>
#include <iostream>

struct MidiSender::Impl {
    MIDIClientRef client = 0;
    MIDIEndpointRef endpoint = 0;
};

MidiSender::MidiSender(const char* portName)
    : mImpl(std::make_unique<Impl>())
{
    CFStringRef name = CFStringCreateWithCString(nullptr, portName, kCFStringEncodingUTF8);

    OSStatus status = MIDIClientCreate(name, nullptr, nullptr, &mImpl->client);
    if (status != noErr) {
        std::cerr << "[MIDI] Failed to create client: " << status << std::endl;
        CFRelease(name);
        return;
    }

    status = MIDISourceCreate(mImpl->client, name, &mImpl->endpoint);
    if (status != noErr) {
        std::cerr << "[MIDI] Failed to create source: " << status << std::endl;
    } else {
        std::cout << "[MIDI] Virtual port created: " << portName << std::endl;
    }

    CFRelease(name);
}

MidiSender::~MidiSender() {
    if (mImpl->endpoint) MIDIEndpointDispose(mImpl->endpoint);
    if (mImpl->client) MIDIClientDispose(mImpl->client);
}

void MidiSender::sendCC(uint8_t channel, uint8_t cc, float value) {
    if (!mImpl->endpoint) return;

    uint16_t val14 = static_cast<uint16_t>(std::clamp(value, 0.0f, 1.0f) * 16383.0f);
    uint8_t msb = (val14 >> 7) & 0x7F;
    uint8_t lsb = val14 & 0x7F;
    uint8_t status = 0xB0 | (channel & 0x0F);

    // Send MSB then LSB (cc+32) in one packet for 14-bit CC
    MIDIPacketList packetList;
    MIDIPacket* packet = MIDIPacketListInit(&packetList);
    uint8_t msbData[3] = { status, cc, msb };
    packet = MIDIPacketListAdd(&packetList, sizeof(packetList), packet, 0, 3, msbData);
    uint8_t lsbData[3] = { status, static_cast<uint8_t>(cc + 32), lsb };
    MIDIPacketListAdd(&packetList, sizeof(packetList), packet, 0, 3, lsbData);
    MIDIReceived(mImpl->endpoint, &packetList);
}
