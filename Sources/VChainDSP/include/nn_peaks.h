// SPDX-License-Identifier: GPL-3.0-or-later
// Ported from Beat This! (MIT), see THIRD_PARTY_NOTICES.md
// Beat This!'s "minimal" postprocessing: a frame is a peak when its logit is the maximum within +/- 3 frames
// (+/- 60 ms at 50 frames/s) and above 0 (probability > 0.5); runs of adjacent peak frames merge into their mean.
#pragma once

// logits: n frames. Writes peak positions in frames (fractional when merged) to out; returns how many (<= maxOut).
int pickNNPeaks(const float* logits, int n, double* out, int maxOut);
