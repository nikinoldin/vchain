# SPDX-License-Identifier: GPL-3.0-or-later
"""Writes a reference for unit_logmel.cpp: Beat This!'s own log-mel spectrogram (soxr resampling + LogMelSpect) of
the synthetic `house-mix` scenario, frames 200..259, as TSV (one frame per line, 128 values).
usage: logmel_fixture.py house-mix.wav out.tsv   (render the WAV with `VChainBench --render house-mix x.wav`)"""
import sys, numpy as np, soundfile as sf, soxr, torch
from beat_this.preprocessing import LogMelSpect
x, sr = sf.read(sys.argv[1], dtype="float32")
y = soxr.resample(x, in_rate=sr, out_rate=22050)
with torch.inference_mode():
    s = LogMelSpect()(torch.tensor(y)).numpy()
np.savetxt(sys.argv[2], s[200:260], fmt="%.5f", delimiter="\t")
print(s.shape)
