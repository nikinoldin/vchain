// SPDX-License-Identifier: GPL-3.0-or-later
// Periodic Hann window (torch.hann_window's default): 0.5 - 0.5 cos(2 pi i / n), computed in T (float or double).
#pragma once
#include <cmath>
#include <cstddef>
#include <vector>

template <typename T>
std::vector<float> hannWindow(size_t n) {
    std::vector<float> w(n);
    for (size_t i = 0; i < n; i++)
        w[i] = static_cast<float>(T(0.5) - T(0.5) * std::cos(T(2) * static_cast<T>(M_PI) * static_cast<T>(i) / static_cast<T>(n)));
    return w;
}
