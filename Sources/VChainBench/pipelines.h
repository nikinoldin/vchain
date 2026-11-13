// SPDX-License-Identifier: GPL-3.0-or-later
// Pipelines the bench can run, by name. All are the app's BeatEngine with capture time stamps:
//   tempo-phase          drum onsets only (the app without the Beat This! model, or before it is loaded)
//   hy-tempo-phase       the hybrid: drum tracker + NN tracker, NN beats precomputed by bench/nn/rolling_dump.py
//                        (needs nnFile)
//   live-hy-tempo-phase  the hybrid with the app's own NN chain (LogMel + Core ML), run in step (needs the model)
#pragma once
#include "runner.h"
#include <memory>
#include <string>

// nnFile: precomputed rolling-window NN output (bench/nn/rolling_dump.py) for the section, or "" for none.
std::unique_ptr<Pipeline> makePipeline(const std::string& name, const std::string& nnFile = "");
