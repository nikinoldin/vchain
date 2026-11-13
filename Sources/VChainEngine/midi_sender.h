// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once

#include <cstdint>
#include <memory>

class MidiSender {
public:
    MidiSender(const char* portName);
    ~MidiSender();

    // Send a 14-bit CC message (MSB on cc, LSB on cc+32). Value is 0.0-1.0.
    void sendCC(uint8_t channel, uint8_t cc, float value);

private:
    struct Impl;
    std::unique_ptr<Impl> mImpl;
};
