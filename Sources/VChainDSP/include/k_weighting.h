// SPDX-License-Identifier: GPL-3.0-or-later
// ITU-R BS.1770 K-weighting (loudness) at any sample rate: a high shelf (about +4 dB above ~1.7 kHz, the head) and a
// high-pass (~38 Hz, RLB weighting), as two biquads. BS.1770 publishes coefficients for 48 kHz only; these are the
// analogue prototypes (centre frequency, gain, Q) that reproduce them through the bilinear transform, the same
// derivation libebur128 uses. The bench checks 44.1/48/96 kHz (unit_kweighting.cpp).
#pragma once
#include <cmath>

struct KWeighting {
    double shelf[5];    // b0, b1, b2, a1, a2 (a0 = 1)
    double highPass[5];
};

inline KWeighting kWeighting(double sampleRate) {
    KWeighting k{};
    {
        const double f0 = 1681.974450955533, gainDb = 3.999843853973347, q = 0.7071752369554196;
        const double K = std::tan(M_PI * f0 / sampleRate);
        const double vh = std::pow(10.0, gainDb / 20.0), vb = std::pow(vh, 0.4996667741545416);
        const double a0 = 1.0 + K / q + K * K;
        k.shelf[0] = (vh + vb * K / q + K * K) / a0;
        k.shelf[1] = 2.0 * (K * K - vh) / a0;
        k.shelf[2] = (vh - vb * K / q + K * K) / a0;
        k.shelf[3] = 2.0 * (K * K - 1.0) / a0;
        k.shelf[4] = (1.0 - K / q + K * K) / a0;
    }
    {
        const double f0 = 38.13547087602444, q = 0.5003270373238773;
        const double K = std::tan(M_PI * f0 / sampleRate);
        const double a0 = 1.0 + K / q + K * K;
        k.highPass[0] = 1.0;
        k.highPass[1] = -2.0;
        k.highPass[2] = 1.0;
        k.highPass[3] = 2.0 * (K * K - 1.0) / a0;
        k.highPass[4] = (1.0 - K / q + K * K) / a0;
    }
    return k;
}
