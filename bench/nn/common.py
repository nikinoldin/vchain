# SPDX-License-Identifier: GPL-3.0-or-later
import time, statistics, torch
from rotary_embedding_torch import RotaryEmbedding
from beat_this.inference import load_model

def _rot_pure(self, t, seq_dim=None, offset=0, scale=None):
    # stateless replacement (no cache buffers) — numerically identical
    n = t.shape[-2]
    seq = torch.arange(n, device=t.device, dtype=torch.float32)
    f = seq[:, None] * self.freqs[None, :].float()          # (n, d/2)
    f = torch.repeat_interleave(f, 2, dim=-1)               # (n, d) interleaved
    cos, sin = f.cos().to(t.dtype), f.sin().to(t.dtype)
    x = t.reshape(*t.shape[:-1], t.shape[-1] // 2, 2)
    x1, x2 = x[..., 0], x[..., 1]
    rh = torch.stack((-x2, x1), dim=-1).reshape(t.shape)
    return t * cos + rh * sin

def patch_rotary():
    RotaryEmbedding.rotate_queries_or_keys = _rot_pure

def get_model(name, patch=True):
    if patch: patch_rotary()
    m = load_model(name, "cpu").eval()
    return m

class Wrap(torch.nn.Module):
    def __init__(self, m): super().__init__(); self.m = m
    def forward(self, x):
        o = self.m(x); return o["beat"], o["downbeat"]

def bench(fn, n=20, warm=3):
    for _ in range(warm): fn()
    ts = []
    for _ in range(n):
        t0 = time.perf_counter(); fn(); ts.append((time.perf_counter() - t0) * 1000)
    return statistics.median(ts)
