# SPDX-License-Identifier: GPL-3.0-or-later
"""Causal rolling-window evaluation of Beat This! as a beat/downbeat detector for vChain.

Every STEP seconds, run the model on the last W seconds only (no future audio beyond the STFT centre padding,
~23 ms), peak-pick beats/downbeats in that window, fit a constant grid to the last <= 16 beats, pick the bar
position by majority vote of the window's downbeats, and predict the beats of the next STEP seconds. Score those
predictions against the truth: tempo, octave, phase error, bar right, lock time. Prints one JSON line per file.
usage: rolling.py model W STEP file.wav truth.beats genre [maxSeconds]
"""
import json, sys, time
import numpy as np
import torch
from beat_this.inference import load_model
from beat_this.preprocessing import LogMelSpect, load_audio
from beat_this.model.postprocessor import Postprocessor
import soxr

model_name, W, STEP, wav, beats_path, genre = sys.argv[1], float(sys.argv[2]), float(sys.argv[3]), sys.argv[4], sys.argv[5], sys.argv[6]
max_s = float(sys.argv[7]) if len(sys.argv) > 7 else 1e9
dev = "mps" if torch.backends.mps.is_available() else "cpu"
model = load_model(model_name, dev)
spect_fn = LogMelSpect(device=dev)
post = Postprocessor("minimal")

sig, sr = load_audio(wav)
if sig.ndim == 2:
    sig = sig.mean(1)
sig = sig[: int(min(len(sig) / sr, max_s) * sr)]
sig22 = soxr.resample(sig, in_rate=sr, out_rate=22050)
with torch.inference_mode():
    spect = spect_fn(torch.tensor(sig22, dtype=torch.float32, device=dev))  # (frames, 128), 50 fps
fps = 50.0
truth = np.array([[float(a), int(b)] for a, b in (l.split()[:2] for l in open(beats_path) if l.strip())])
truth = truth[truth[:, 0] < len(sig) / sr]
tb, tbar = truth[:, 0], truth[:, 1].astype(int)

def local_bpm(t):
    i = np.searchsorted(tb, t)
    lo, hi = max(1, i - 4), min(len(tb) - 1, i + 4)
    iv = np.diff(tb[lo - 1 : hi + 1])
    if len(iv) == 0:
        return 0
    m = np.median(iv)
    iv = iv[np.abs(iv / m - 1) < 0.08]
    return 60 / np.median(iv) if len(iv) else 0

n_frames = spect.shape[0]
wf = int(W * fps)
rows = []  # per evaluated truth beat: t, phase_err_ms, tempo_err, octave_ok, bar_ok(or -1), conf
infer_ms = []
t = W
while t + STEP <= len(sig) / sr:
    f1 = int(t * fps)
    chunk = spect[max(0, f1 - wf) : f1]
    t0 = time.perf_counter()
    with torch.inference_mode():
        out = model(chunk.unsqueeze(0))
    if dev == "mps":
        torch.mps.synchronize()
    infer_ms.append((time.perf_counter() - t0) * 1000)
    beat_l, down_l = out["beat"][0].float().cpu(), out["downbeat"][0].float().cpu()
    b, d = post(beat_l, down_l)
    off = (f1 - chunk.shape[0]) / fps
    b = np.asarray(b) + off
    d = np.asarray(d) + off
    est = None
    if len(b) >= 4:
        last = b[-16:]
        P = np.median(np.diff(last))
        if P > 0.25:
            idx = np.round((last - last[-1]) / P)
            A = np.vstack([np.ones_like(idx), idx]).T
            (c0, P2), *_ = np.linalg.lstsq(A, last, rcond=None)
            res = np.abs(last - (c0 + P2 * idx))
            keep = res < 0.04
            if keep.sum() >= 4:
                (c0, P2), *_ = np.linalg.lstsq(A[keep], last[keep], rcond=None)
            dres = [int(np.round((x - c0) / P2)) % 4 for x in d if np.min(np.abs(b - x)) < 0.05]
            if dres:
                vals, cnt = np.unique(dres, return_counts=True)
                r, conf = int(vals[np.argmax(cnt)]), float(cnt.max() / len(dres))
            else:
                r, conf = -1, 0.0
            est = (c0, P2, r, conf)
    # score the truth beats in (t, t + STEP]
    sel = np.where((tb > t) & (tb <= t + STEP))[0]
    for i in sel:
        bpm_t = local_bpm(tb[i])
        if est is None or bpm_t <= 0:
            rows.append([tb[i], np.nan, np.nan, 0, -1, 0])
            continue
        c0, P, r, conf = est
        k = np.round((tb[i] - c0) / P)
        err = (tb[i] - (c0 + k * P)) * 1000
        bpm_e = 60 / P
        ratio = bpm_e / bpm_t
        oct_ok = 1 if abs(ratio - 1) < 0.03 else 0
        bar_ok = -1
        if tbar[i] == 1 and r >= 0:
            bar_ok = 1 if int(k) % 4 == r else 0
        rows.append([tb[i], err, bpm_e - bpm_t, oct_ok, bar_ok, conf])
    t += STEP

R = np.array(rows, dtype=float)
first = tb[0] if len(tb) else 0
steady = R[:, 0] > first + 15
ok = steady & ~np.isnan(R[:, 1])
ph = np.abs(R[ok, 1])
tempo_err = np.abs(R[ok & (R[:, 3] == 1), 2])
bars = R[steady & (R[:, 4] >= 0), 4]
# lock time: first beat after which tempo within 0.5 BPM and phase within 20 ms hold for 8 beats
lock = np.nan
run = 0
for j in range(len(R)):
    good = (not np.isnan(R[j, 1])) and abs(R[j, 1]) < 20 and abs(R[j, 2]) < 0.5
    run = run + 1 if good else 0
    if run == 8:
        lock = R[j - 7, 0] - first
        break
print(json.dumps({
    "file": wav.split("/")[-1], "genre": genre, "model": model_name, "W": W, "step": STEP,
    "phase_med_ms": float(np.median(ph)) if len(ph) else None, "phase_p90_ms": float(np.percentile(ph, 90)) if len(ph) else None,
    "tempo_err_med": float(np.median(tempo_err)) if len(tempo_err) else None,
    "octave_ok_pct": float(100 * R[ok, 3].mean()) if ok.any() else None,
    "bar_right_pct": float(100 * bars.mean()) if len(bars) else None,
    "lock_s": None if np.isnan(lock) else float(lock),
    "infer_ms_med": float(np.median(infer_ms)), "device": dev, "n": int(ok.sum())}))
