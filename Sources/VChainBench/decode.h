// SPDX-License-Identifier: GPL-3.0-or-later
// Audio files for the bench: decode anything ExtAudioFile reads (mp3, wav, flac, aac) to mono float at a
// given rate, and write 16-bit WAV renders (scratch files only, never into the repo).
#pragma once
#include <string>
#include <vector>

bool decodeFile(const std::string& path, double sampleRate, std::vector<float>& out);
// channels = 1 (mono) or 2 (interleaved stereo in `samples`).
bool writeWav(const std::string& path, const std::vector<float>& samples, double sampleRate, int channels);
