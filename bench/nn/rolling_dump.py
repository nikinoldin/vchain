# SPDX-License-Identifier: GPL-3.0-or-later
"""Precompute what a rolling Beat This! window reports, for VChainBench's `nn` pipelines.

Every STEP s, the model sees the last W s of audio only (as the app would) and its peak-picked beats and downbeats
are written as `t_end<TAB>time<TAB>kind<TAB>logit` (kind 0 = beat, 1 = downbeat; times in s from the file start).
usage: rolling_dump.py model W STEP out.nn.tsv file [file ...]   (one output file per input: out.nn.tsv is a
       directory if several files are given; outputs are named <stem>.nn.tsv)
"""
import os, sys
import numpy as np
import torch
import soxr
from beat_this.inference import load_model
from beat_this.preprocessing import LogMelSpect, load_audio
from beat_this.model.postprocessor import Postprocessor

model_name, W, STEP, out = sys.argv[1], float(sys.argv[2]), float(sys.argv[3]), sys.argv[4]
files = sys.argv[5:]
dev = "mps" if torch.backends.mps.is_available() else "cpu"
model = load_model(model_name, dev)
spect_fn = LogMelSpect(device=dev)
post = Postprocessor("minimal")
fps = 50.0
for path in files:
    stem = os.path.splitext(os.path.basename(path))[0]
    dst = os.path.join(out, stem + ".nn.tsv") if len(files) > 1 or os.path.isdir(out) else out
    if os.path.exists(dst):
        continue
    sig, sr = load_audio(path)
    if sig.ndim == 2:
        sig = sig.mean(1)
    sig22 = soxr.resample(sig, in_rate=sr, out_rate=22050)
    with torch.inference_mode():
        spect = spect_fn(torch.tensor(sig22, dtype=torch.float32, device=dev))
    wf = int(W * fps)
    lines = []
    t = STEP
    dur = len(sig) / sr
    while t <= dur:
        f1 = int(t * fps)
        chunk = spect[max(0, f1 - wf):f1]
        if chunk.shape[0] >= 50:
            with torch.inference_mode():
                o = model(chunk.unsqueeze(0))
            bl, dl = o["beat"][0].float().cpu(), o["downbeat"][0].float().cpu()
            b, d = post(bl, dl)
            off = (f1 - chunk.shape[0]) / fps
            for kind, times, logits in ((0, b, bl), (1, d, dl)):
                for x in np.asarray(times):
                    fi = min(len(logits) - 1, int(round(x * fps)))
                    lines.append(f"{t:.3f}\t{x + off:.4f}\t{kind}\t{float(logits[fi]):.2f}")
        t += STEP
    tmp = dst + ".tmp"
    with open(tmp, "w") as f:
        f.write("\n".join(lines) + "\n")
    os.replace(tmp, dst)
    print(stem, len(lines), flush=True)
