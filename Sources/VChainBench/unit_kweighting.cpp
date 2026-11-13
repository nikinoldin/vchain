// SPDX-License-Identifier: GPL-3.0-or-later
#include "k_weighting.h"
#include "unit.h"
#include <algorithm>
#include <cmath>
#include <complex>
#include <string>

namespace {
// |H| in dB of the two stages at f Hz.
double gainDb(const KWeighting& k, double rate, double f) {
    const std::complex<double> z = std::polar(1.0, -2.0 * M_PI * f / rate), z2 = z * z; // z^-1, z^-2
    auto h = [&](const double* c) { return (c[0] + c[1] * z + c[2] * z2) / (1.0 + c[3] * z + c[4] * z2); };
    return 20.0 * std::log10(std::abs(h(k.shelf) * h(k.highPass)));
}

void checkCoefficients(const KWeighting& k, const double (&shelf)[5], const double (&highPass)[5], const std::string& what) {
    double err = 0;
    for (int i = 0; i < 5; i++) err = std::max({err, std::fabs(k.shelf[i] - shelf[i]), std::fabs(k.highPass[i] - highPass[i])});
    CHECK(err < 1e-9, what + " (max error " + std::to_string(err) + ")");
}
} // namespace

// BS.1770's published 48 kHz coefficients, and a 44.1 kHz reference table.
TEST(kWeightingReference) {
    checkCoefficients(kWeighting(48000),
                      {1.53512485958697, -2.69169618940638, 1.19839281085285, -1.69065929318241, 0.73248077421585},
                      {1.0, -2.0, 1.0, -1.99004745483398, 0.99007225036621}, "48 kHz = BS.1770 table");
    checkCoefficients(kWeighting(44100),
                      {1.5308412300498355, -2.6509799951547297, 1.1690790799215869, -1.6636551132560204, 0.7125954280732254},
                      {1.0, -2.0, 1.0, -1.9891696736297957, 0.9891990357870394}, "44.1 kHz = previous table");
}

// The same curve at other rates: within 0.05 dB of the 48 kHz reference up to 10 kHz (the bilinear transform only
// bends it near Nyquist), and the shape itself: about −5.6 dB at 40 Hz (the high-pass: 38 Hz, Q 0.5), +4 dB at 10 kHz.
TEST(kWeightingOtherRates) {
    const KWeighting ref = kWeighting(48000);
    for (double rate : {44100.0, 88200.0, 96000.0, 192000.0}) {
        const KWeighting k = kWeighting(rate);
        double worst = 0;
        for (double f : {20.0, 40.0, 100.0, 500.0, 1000.0, 2000.0, 4000.0, 10000.0})
            worst = std::max(worst, std::fabs(gainDb(k, rate, f) - gainDb(ref, 48000, f)));
        CHECK(worst < 0.05, std::to_string(int(rate)) + " Hz matches 48 kHz's curve (max " + std::to_string(worst) + " dB)");
    }
    const KWeighting k96 = kWeighting(96000);
    CHECK_NEAR(gainDb(k96, 96000, 40), -5.6, 0.2, "96 kHz: 40 Hz cut by the high-pass");
    CHECK_NEAR(gainDb(k96, 96000, 10000), 4.0, 0.2, "96 kHz: +4 dB shelf at 10 kHz");
}
