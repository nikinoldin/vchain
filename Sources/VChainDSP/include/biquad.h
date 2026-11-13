// SPDX-License-Identifier: GPL-3.0-or-later
// Second-order IIR filters: RBJ cookbook coefficients and one biquad (transposed direct form II), with the state and
// coefficients in float (the drum detectors, many filters per sample) or double (K-weighting, the bench's synth).
#pragma once
#include <cmath>

struct BiquadCoeffs {
    double b0, b1, b2, a1, a2; // a0 = 1
};

enum class BiquadType { LowPass, HighPass, BandPass }; // band-pass: constant 0 dB peak gain

// RBJ cookbook ("Audio EQ Cookbook") coefficients at corner/centre frequency f, quality q.
inline BiquadCoeffs rbjBiquad(BiquadType type, double f, double q, double sampleRate) {
    const double w = 2 * M_PI * f / sampleRate, al = std::sin(w) / (2 * q), c = std::cos(w), a0 = 1 + al;
    double b0 = 0, b1 = 0, b2 = 0;
    switch (type) {
        case BiquadType::LowPass: b0 = (1 - c) / 2; b1 = 1 - c; b2 = (1 - c) / 2; break;
        case BiquadType::HighPass: b0 = (1 + c) / 2; b1 = -(1 + c); b2 = (1 + c) / 2; break;
        case BiquadType::BandPass: b0 = al; b1 = 0; b2 = -al; break;
    }
    return {b0 / a0, b1 / a0, b2 / a0, -2 * c / a0, (1 - al) / a0};
}

template <typename T>
struct Biquad {
    T b0 = 1, b1 = 0, b2 = 0, a1 = 0, a2 = 0, z1 = 0, z2 = 0;

    // New coefficients, state cleared.
    void set(const BiquadCoeffs& c) {
        b0 = T(c.b0); b1 = T(c.b1); b2 = T(c.b2); a1 = T(c.a1); a2 = T(c.a2);
        z1 = z2 = 0;
    }
    void set(BiquadType type, double f, double q, double sampleRate) { set(rbjBiquad(type, f, q, sampleRate)); }
    void reset() { z1 = z2 = 0; }

    float run(float x) {
        T y = b0 * x + z1;
        z1 = b1 * x - a1 * y + z2;
        z2 = b2 * x - a2 * y;
        return static_cast<float>(y);
    }
};
