# vChain bench

Offline test bench for the beat/downbeat work (`Sources/VChainBench`, design:
`docs/beat-tracking.md`). It runs the app's own DSP (`Sources/VChainDSP`)
hop by hop, faster than real time, against a simulated Link session. It never joins real Link.

```bash
swift build --build-system native -c release --product VChainBench
B=.build/release/VChainBench
$B --unit                                     # unit checks (also run by scripts/check.sh)
$B --synthetic all --pipeline tempo-phase --assert 1 # synthetic scenarios + stage asserts (check.sh)
$B --manifest bench/sources.tsv --pipeline tempo-phase --genre dnb   # real audio
$B --synthetic dnb-174 --clicks /tmp/x.wav    # L = truth clicks, R = vChain's Link grid (high click on the 1)
```

**Headline metrics** (lead every comparison with these; what a user notices first is the beat dot jumping and a
wandering tempo): `$B --synthetic all --headline --pipeline tempo-phase,hy-tempo-phase` (or `--manifest
bench/sources.tsv`). It runs each pipeline alone in Link and with a Resolume-like peer, and prints per genre: visible
phase jumps per minute (and size in beats), phase error vs. the music (median/p90 ms), beat F, shown-value changes per
minute, shown-tempo spread (p90 of 60 s blocks), tempo error and octave. Metric definitions, scenarios and targets:
`docs/beat-tracking.md`.

Pipelines (`--pipeline`, comma-separated for `--headline`; all of them use capture time stamps, as the app does):
- `hy-tempo-phase`: **what the app runs** with the bundled model: drum and NN trackers with the arbiter, TempoPhase
  Link driving and the bar vote. Reads precomputed NN output (below).
- `live-hy-tempo-phase`: the same with the network run live through Core ML, as in the app (needs the model).
- `tempo-phase` (the default): what the app runs without the model (drum-only). `scripts/check.sh` asserts stage 1
  on it.

NN pipelines read the rolling-window Beat This! output that `bench/nn/rolling_dump.py` precomputes per file, from
`~/Music/vChainBench/nn-final0-w12/<id>.nn.tsv` (`--nn-dir` for another folder). The live pipeline and
`unit_reallink` load the model from `~/Music/vChainBench/models/beat_this_final0_T600_fp16.mlpackage`
(`VCHAIN_NN_MODEL` overrides; `bench/nn/make_model.sh` makes it).

Options: `--pipeline <name>`, `--link alone|peer|edit`, `--latency ms`, `--jitter ms`, `--rate 44100`,
`--summary out.tsv`, `--csv out.csv`, `--id`, `--kind set|track`, `--raw` (no annotation smoothing), `--nn-dir`.
`bench/baseline/phase-{tempo-phase,hy-tempo-phase}-{alone,peer}-real.tsv` are committed `--summary` outputs (real
audio, each Link situation) to compare against.

## Files outside the repo

Everything large or licensed stays in `~/Music/vChainBench/` (never in git):

| Path | What | Made by |
|---|---|---|
| `audio/` (`$VCHAIN_BENCH_AUDIO`) | the test audio | `bench/tools/fetch.sh` |
| `.venv/` | Python venv: torch, beat-this, coremltools (via uv) | `bench/tools/annotate.sh`, `bench/nn/make_model.sh` |
| `models/beat_this_final0_T600_fp16.mlpackage` | the Core ML model the app bundles | `bench/nn/make_model.sh` |
| `models/cache/` | the bench's compiled model | VChainBench |
| `nn-final0-w12/` | precomputed rolling-window NN output | `bench/nn/rolling_dump.py` |

`$VCHAIN_BENCH_HOME` moves the whole folder for the scripts that read it (annotate.sh, make_model.sh).

## Test audio (not in git)

- `sources.tsv`: one row per file, with source page, licence URL, attribution, sha256 and download URL. Every item
  is CC or CC0, checked on 2026-11-05. CC allows private local listening and analysis; the audio, cuts and click
  renders must never be committed, uploaded or shared.
- Audio lives in `${VCHAIN_BENCH_AUDIO:-~/Music/vChainBench/audio}`: `bench/tools/fetch.sh` downloads what's
  missing and checks the sha256.
- `annotations/<id>.beats`: machine-made beat times (no audio in them): Beat This! run offline over each whole file
  (`time<TAB>beatInBar`, 1 = downbeat), made by
  `bench/tools/annotate.sh` (venv in `~/Music/vChainBench/.venv`, torch + beat-this via uv; about 27 s per hour of
  audio on CPU). Optional `<id>.regions` (`start<TAB>end<TAB>tag`) adds hand-made regions.
- At load the bench smooths Beat This!'s 20 ms frame grid with a local constant-tempo fit (`--raw` to skip), turns
  gaps > 2 s into `nobeat`, and marks stretches whose bars aren't 4 beats long as `nobar` (excluded from bar metrics).

How good the pre-annotations are, measured on the synthetic scenarios (exact truth):
- beat F 0.90–1.00
- downbeats 97–100 % right
- timing offset vs. the true onset −2 to +13 ms by sound, p90 10–22 ms after smoothing

So phase numbers on real audio carry about ±10 ms of systematic uncertainty; the synthetic scenarios are the
precise check. On real files the downbeats are often irregular (many `nobar` stretches). Real-audio bar numbers
mean "agrees with Beat This!", not hand-checked truth. The files were picked by tags without listening.
Doubtful annotations to check by ear: `dnb-badmanmoriarty-babalon-boi` (≈ 220 BPM), `dnb-troublesome-metal-mickiy`
(≈ 126), `breaks-ratpack2-*` (159–168, DnB tempo or double time?).
