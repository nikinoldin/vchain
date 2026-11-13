# Beat tracking: tempo, phase and the 1

How vChain finds the beat in live audio and puts it into Ableton Link: the design, the reasons behind it, how it is
measured (`VChainBench`, `bench/README.md`) and what it reaches. Code: `Sources/VChainDSP` (analysis and Link driving,
shared by the app and the bench), `Sources/VChainNN` (the Beat This! network), `Sources/VChainEngine/bpm_module.*`
(the app's glue to real Link).

## Goal

vChain tells Link software such as Resolume where the beat is. Three things have to be right:

1. **The tempo**, exact (within 0.05 BPM in steady sections) and steady: Link's tempo and the shown value change only
   when the music does. At 128 BPM a tempo 1.5 % off slides a whole beat against the music about every 37 s.
2. **The phase**: Link's beat lands on the music's beat, with Resolume connected, and does not visibly jump during a
   groove (every jump skips Resolume's beat-synced clips).
3. **The 1**: Link's beat 1 is the music's downbeat, moved there at most about once per new track.

Three genre families must lock reliably: **4/4** (house, techno: kick on every beat), **DnB** (drum & bass and jungle,
160–178 BPM, mostly kick on 1 and snare on 2 and 4; it must read 170–175, not 85–87.5) and **breaks** (breakbeat,
120–140 BPM, syncopated kick, snare on 2 and 4). Other genres get whatever falls out; they should at worst stay
unsettled, never lock confidently on something wrong.

Non-goals: half/double, tap, resync or nudge buttons; meters other than 4 beats per bar (`VC_BEATS_PER_BAR`); a
"vChain leads Link" setting. A fixed latency calibration in Settings (Beat offset) is the only manual control.

Anti-goals (failures even if the numbers look good):
- **A wrong 1 shown confidently.** Worse than none, in Link and on the tag. Bar-lock precision beats coverage.
- **Visible Link jumps during a groove.** Jumps only at a new lock, a new track or a bar correction.
- **Fighting a person in Resolume.** A tap or a typed BPM is never answered with a forced jump.
- **Tempo wobble** visible in Resolume's BPM display: commits are rare, nudges small and short.

## Pipeline

```
 audio hop (512 samples) + capture time (µs, Link clock)
        │
        ├──────────────────────────────────────────────┐
        ▼                                              ▼
 ┌──────────── BeatEngine (VChainDSP) ─────────────┐   NNFrontEnd (VChainNN)
 │ BpmDetector  aubio: coarse tempo, octave guard   │   LogMel on the engine thread;
 │                                                  │   Beat This! (Core ML) once a second
 │ DrumOnsets   kick / snare / hat onsets           │   on its own thread; peaks merged
 │ BeatTracker  ×2 in hybrid mode:                  │   across windows (NNBeatMerger)
 │   drum onsets only │ drum onsets + NN beats  ◄───┼─── beats
 │   (GridFit + BeatPhase + states each)            │
 │ arbiter      picks the grid that drives Link     │
 │ BarVote      where the 1 is                 ◄────┼─── downbeats
 │ LinkDriver   TempoPhase: tempo, phase nudges,    │
 │              one jump per lock, bar move,        │
 │              foreign-edit guard                  │──► LinkPort
 └──────────────────────────────────────────────────┘
        LinkPort = RealLinkPort over ableton::Link (app) | LinkSim (bench: alone / Resolume-like peer)
```

The same `BeatEngine` runs in the app and in the bench; only the source of hops and capture times and the `LinkPort`
differ. Without the bundled model (or `VCHAIN_NN_MODEL`) `NNFrontEnd::ready()` stays false and the engine runs
drum-only: one tracker, same driver.

Everything on the engine thread is real time and causal: hop by hop, nothing but captured audio, 512-sample hops (`BeatEngine::kHopSize`)
(10.67 ms at 48 kHz; 44.1 kHz works too), no allocation, locks or logging per hop, fixed-size rings. CPU budget for
the beat DSP: 0.3 ms per hop mean, 2 ms p99 (it runs at about 50 µs on Apple Silicon).

### BpmDetector (aubio)

aubio's beat trackers give the **coarse tempo** (used before the first lock, as a tie-breaker for the grid step and
as an octave guard), nothing else. aubio's tempo
is never what Link gets after a lock: its comb filterbank reads 1.2–1.5 % high on every tempo (it centres the k-th
multiple of lag i at `k*(i+1)-1`; the error halves at hop 256), it drifts in pad breakdowns, and it reads jungle at
about 114 and DnB at half tempo.

### DrumOnsets

Our own allocation-free detector, so its timing is ours. Each hop is processed in 128-sample sub-hops (2.7 ms) through
four band-passes: kick 40–150 Hz, snare body 150–400 Hz, snare/clap noise 1–5 kHz, hat above 6 kHz. Per band: an
energy envelope, a log-energy rise, an adaptive threshold, local-max peak picking. An onset carries its capture time,
class (kick / snare / hat; NN beats use the same struct as class `Beat`) and strength. Onsets are decided about
24 ms late so a clap's bursts count together, timed at 10 % of the attack; a kick-band peak right after a snare is
the snare's body and dropped. The MIDI strip's triggers reuse this detector with extra options (rumble kicks, body
check, pitch sweep, snare tail); the beat grid keeps the defaults.

### GridFit

Fits a constant grid `t = origin + m·step` to the kick and snare onsets of the last ~10 s (hats never: an off-beat
open hat pulls the phase reference ~200 ms off).
- **Step:** `estimateGridStep` finds the step from the onsets themselves (the tempo in 75–190 BPM whose quarter-beat
  grid fits best, circular statistic; ties go to the plain 8th/16th grid, aubio's tempo breaks near-ties). aubio is
  used only when there are too few onsets.
- **Fit:** 121 step candidates within ±3 %, then iteratively reweighted least squares on the inliers (gate
  min(40 ms, step/4)). If the last 6 s fit clearly better (a DJ pitch ramp), that fit wins.
- Syncopated kicks on the "and" (breaks, DnB two-step) sit on the half grid and help the fit.

### BeatPhase

Decides what the grid leaves open:
- **Octave:** beat = k grid steps (k = 2, 4 or 8) within 60–180 BPM.
- **Beat vs. off-beat:** which grid positions are the beats.
- **Groove family:** `FourFour` (kick on ≥ 80 % of beats) or `Backbeat` (snare on ≥ 70 % of every second beat, < 30 %
  of the others: DnB, breaks).
- **The backbeat rule:** the right octave puts the snare on every *second* beat. DnB read at 87 would have the snare on
  every beat, so 174 wins; breaks at 132 read at 66 have the same problem. The genre preset (`genre.h`) only breaks
  ties; with genre Auto it must stay weak, or DnB would fold to 87.
- **Hysteresis:** within a lock the octave changes only after 64 beats of contrary evidence (a DnB half-time section,
  snare on 3, lasts 8–16 bars and must keep 174), the beat/off-beat choice after 16.
- With NN beats in the window, their median interval is the beat and decides the octave.

### BeatTracker

Keeps a **committed** grid separate from the latest fit, and a state (`VCBeatState` in the snapshot):

| State | Meaning | Link |
|---|---|---|
| `searching` | no grid yet, or lost (60 s of holding without the drums returning) | aubio's tempo before the first lock, afterwards the last locked tempo |
| `settling` | a candidate grid, not yet consistent long enough | as searching |
| `locked` | the committed grid explains the kick/snare onsets (inlier share, residual RMS < 15 ms) | tempo, phase nudges, the one jump per lock, the bar move |
| `holding` | was locked; the drums are gone (breakdown, echo-out) or the inlier share fell | **nothing written**: Link runs on; beats and bars keep counting |

- **Inliers:** snares and four-on-the-floor kicks must sit on whole beats; only backbeat kicks may sit on the half
  beat. Otherwise a track resumed half a beat late would pass as "on the grid".
- **Jump rejection:** a challenger grid must explain the onsets better for 8 beats before it replaces the committed
  one. Spinbacks, echo-outs and fills (1–4 beats) never qualify.
- **Hard cut:** consecutive strong off-grid onsets that share one offset (circular spread < 20 ms) and fit a grid:
  accepted after 4 consistent beats as a new lock.
- **Back from holding:** onsets on the counted grid again → `locked`, nudges only (no new lock).
- **Octave guard:** in 4/4 the committed tempo must agree with aubio's up to an octave; a 5:4, 4:3 or 3:2
  disagreement for 8 s means a wrong grid, and the tracker searches again. Not for backbeat grooves, where aubio
  itself is wrong.

### The NN front end (Beat This!)

[Beat This!](https://github.com/CPJKU/beat_this) (JKU Linz, MIT code and weights), model `final0` (20 M parameters),
converted by `bench/nn/make_model.sh` to a Core ML fp16 `.mlpackage` (39 MB) with a fixed window of 600 frames (12 s).
`build.sh` bundles it; the app compiles it at first launch with `MLModel.compileModel(at:)` into
`~/Library/Application Support/vChain/NN` (about 3.4 s, off the main thread). `VCHAIN_NN_MODEL` points to another copy.

- **Engine thread, every hop:** `LogMel` computes the network's input, ported from Beat This!'s front end: resample to
  22050 Hz, centred STFT (n_fft 1024, periodic Hann, hop 441 = 50 frames/s), magnitude / √1024, 128 Slaney mel bands
  30–11000 Hz, `log1p(1000·x)`. Frames and their capture times go into a ring. Checked against the Python front end
  (`unit_logmel.cpp`, fixtures from `bench/nn/logmel_fixture.py`).
- **Worker thread, once a second:** the newest 600 frames → Core ML on `.cpuAndNeuralEngine` (about 42 ms on the
  Neural Engine, under 1 ms of CPU; `.all` would pick the GPU, which Resolume needs) → peak picking ported from Beat
  This! (`nn_peaks`: a frame is a peak when its logit is the maximum within ±3 frames and above 0) → beat and downbeat
  times back through a lock-free single-producer/single-consumer queue.
- **Merging (`NNBeatMerger`):** each beat is seen by up to 12 windows; its position is averaged over the windows that
  report it, the window's last 0.25 s is skipped, and a beat is handed on once 3 windows have seen it. Without this the
  20 ms frames and window-to-window changes jitter the grid (2–3× the tempo commits). Downbeats are merged the same way.

**Why a hybrid and not the network alone:** the two front ends fail on different tracks. The drum-onset path is
sub-frame precise and steady when the hits are clean, but on compressed club masters its kick detector misses many
kicks and reads rumble and reese basses as kicks, so it locks wrong grids and reads most real DnB at 87. The network
gets the octave and the bar without hand-made rules (real DnB 90–100 % octave right), but its beats sit on 20 ms frames
(tempo alone only within 0.1–0.3 BPM), it needs a full window before its first answer, and it names a wrong 1
confidently when there is no cue for it (the `minimal` scenario: 5 % right).

### The hybrid arbiter

In hybrid mode two trackers run: one on drum onsets only, one on drum onsets plus NN beats (the drum onsets refine the
phase below the NN's frames). Twice a second the arbiter picks the grid that drives Link:
- grids agree (same period within 1 %, phase within min(40 ms, beat/8)) → the drum grid (sub-frame precise);
- an octave disagreement → the NN grid (it is right on DnB where the drum rules fail);
- any other disagreement → the NN grid, unless the drum grid is clearly four-on-the-floor and explains the recent
  strong kicks much better (≥ 0.6 within 35 ms, and 0.25 above the NN grid: the NN sits a quarter beat off on some
  techno).

A switch needs 8 consecutive verdicts (about 4 s). The tempo for Link and the tag comes from the drum tracker whenever
it agrees with the active grid within 1 %, up to an octave: its fit is steadier.

### BarVote: the 1

The merged NN downbeats vote for the Link beat (count mod 4) they land on, re-read against Link's current mapping so a
bar move re-reads every vote correctly. Over the last 16 s the bar locks when one position has ≥ 85 % of at least 4
votes, and unlocks below 60 %. Stricter settings (0.85–1.0, 4–10 votes) only lose coverage, they gain no precision.
Without a consistent 1 (the minimal case) nothing locks. While holding, the bar keeps what it had.

`barLocked` in the snapshot means Link's beat 0 is the music's 1; only then does the tag's mascot do its move on the 1.
The beat blocks always follow Link's bar.

There is no heuristic bar finder (bass-change, snare-parity and bar-pattern cues were designed but not built): the NN
votes reached the bar targets on the independent reference, and drum-only mode simply never claims the 1.

### LinkDriver (TempoPhase)

Everything vChain writes to Link.

**Tempo.**
- Before the driver's first lock: aubio's tempo, rounded to 0.1 BPM, re-committed on moves ≥ 0.5 BPM at most every 2 s
  (so Link is never stuck at 120).
- After it, the tempo only moves while the tracker is locked; holding, settling and searching keep the last locked tempo,
  and a relock never snaps it. Once per beat the grid tempo is compared with the smoothed one:
  - within 0.4 % (fit jitter): ~20-beat smoothing;
  - 0.4–1.5 % in one direction for 8 beats (a DJ pitch ramp): followed quickly;
  - more than 1.5 % (a new track, or a wrong grid such as 5:4): adopted only after 16 locked beats, and in 4/4 only if
    aubio agrees up to an octave. An adopted new tempo allows one phase jump.
- Link gets the smoothed base rounded to 0.01 BPM, changed only on moves ≥ 0.03 BPM. The shown value (0.1 BPM) moves
  only when the base is more than 0.06 % (at least 0.07 BPM) away from it.

**Phase**, once per tracker beat while locked and the fit is confident (otherwise hold): the error is Link's beat
position at the grid's latest beat (minus the Beat offset).
- **Pull-in** after a lock: tempo nudge `T·(1 − clamp(0.5·e, ±3 %))` while the error is > 5 ms.
- **Steady:** a fixed 0.2 % nudge that starts when Link is > 8 ms off and runs until it is < 1 ms off. Peers follow tempo
  changes smoothly, so Resolume's grid slides onto the beat without a jump.
- **One jump:** at the first lock or an adopted new tempo, if Link is more than 1/4 beat off, one `forceBeatAtTime` to
  the nearest beat (at most half a beat). A nudge at 3 % would need many beats to fix a quarter beat; one jump at a
  track start is the lesser evil.

**The bar move:** once BarVote has stayed on the same position for 8 beats and the beat is within 20 ms, Link's beat
count is shifted by whole beats (the shortest way, 2 = forward) so Link's 1 becomes the music's 1. It is made in the hop
where Link crosses the beat that becomes the new 1, so the bar count changes on the downbeat, not mid-bar. At most every
30 s, never while holding.

**Foreign edits:** after each hop the driver compares Link with the timeline its own writes imply. A tempo off by
> 0.01 BPM or a beat mapping shifted by > 0.02 beat is someone else's edit (a tap or typed BPM in Resolume): it is
reported (`EvForeign`, counted by the bench), the expected timeline is re-based, pending jumps are cancelled and no jump is made for 8
beats. Tempo commits go on, so vChain's tempo takes over again. A change in the number of peers re-bases without
counting (joining a session adopts its timeline).

### Latency compensation and the Beat offset

"Now" on the engine thread is processing time, not capture time. Each input publishes capture-time anchors (sample
index, host time) from its callback: the Core Audio device's IO time stamp minus the device's fixed input latency, or
the ScreenCaptureKit buffer's presentation time stamp plus the default output device's latency (system audio is
captured before it reaches the speakers). The engine converts the hop's capture time to Link's clock. Time stamps more
than 1 s old or 0.5 s ahead are not believed; without anchors the processing time is used and no jumps are made.

The **Beat offset** in Settings (−50…+150 ms, remembered per input; `vc_engine_set_beat_offset_ms`) moves Link's beats
earlier to make up for video latency downstream. It is calibration only, not a resync.

## Link semantics that shaped the design

- `setTempo` goes to every peer; peers follow smoothly. That is why phase is steered with small tempo nudges.
- `requestBeatAtTime` **with peers keeps the phase** (it only waits for the next matching phase), so it cannot align
  anything once Resolume is connected. Snapping the nearest beat to every aubio detection with it (the snap baseline
  in "Where it stands") jumps alone in Link (off-beats and hats included, about 73 visible jumps a minute on real audio) and
  never corrects with Resolume connected (90–220 ms off). vChain never calls `requestBeatAtTime`; TempoPhase is the
  only driver.
- `forceBeatAtTime(beat, time, quantum)` re-maps every peer at once and is the only way to move the phase or the bar.
  Link's header calls it anti-social except for synchronising a session to an external clock, which is vChain's role.
  Every peer jumps, so it is used once per lock and once per bar correction.
- Each peer has its own quantum; Resolume uses 4 and keeps the position in the measure in sync (vChain's is `kLinkQuantum` = 4, link_port.h).

## Measuring it: VChainBench

`VChainBench` (`bench/README.md`) runs `BeatEngine` offline, faster than real time, against `LinkSim`, a simulation of
Link's timeline math (tempo, beat/time origin, `phaseAtTime`/`beatAtTime` with a quantum, `forceBeatAtTime` as closest
phase match). `unit_reallink.cpp` checks the same
engine through `RealLinkPort` against a real, never-enabled `ableton::Link`.

Link scenarios (`--link`): `alone`; `peer` (default: one passive follower like Resolume, started at a seeded random
phase vs. the music); `edit` (peer plus one foreign tempo and one foreign phase edit). Input latency is simulated
(`--latency`, `--jitter`) and compensated as in the app: every pipeline uses the capture time stamps.

### Metrics

Computed per section, only inside beat-carrying regions (not `nobeat`).

| Metric | Definition |
|---|---|
| BPM error | Link tempo vs. the local true tempo (median of the 8 surrounding beat intervals); median and max |
| Octave right | share of beat-locked time with the tempo in the true octave (DnB 170–175, breaks not doubled) |
| Phase error | at each true beat: distance of Link's beat position to the nearest integer, in ms; median and p90 |
| Beat F (±70 ms) | Link's beat ticks vs. true beats |
| Visible jumps / min | how often Link's beat position at one instant moves by > 0.02 beat when vChain writes (modulo the bar), with mean size |
| Shown changes / min, spread60 | changes of the shown 0.1-BPM value per steady minute; p95 − p5 of the shown tempo per 60 s block after the first lock |
| Tempo commits / min | Link tempo commits per steady minute (nudges included); reported, not asserted (the phase is steered by nudges, so the headline metrics say more) |
| Lock time | from a cold start or hard cut until tempo error < 0.05 BPM and phase error < 20 ms hold for 8 beats |
| Hold quality | at the drums' return after holding: phase error of the first hits; tempo commits during the hold (should be 0) |
| Bar right / precision / coverage | share of true downbeats where Link's beat mod 4 is 0; the same only while `barLocked`; share of time `barLocked` |
| Forces | phase jumps and bar moves; forces within 8 beats after a foreign edit (must be 0) |
| CPU | µs per hop, mean and p99 |

`--headline` leads every comparison: visible jumps, phase error, beat F, shown changes, spread, tempo error and octave,
per genre, each pipeline alone in Link and with a peer.

### Synthetic scenarios

Every sound is synthesized from a fixed seed in memory (kick sweeps, band-passed noise claps/snares/hats, crashes,
saw/sine bass, detuned pads); the generator writes the exact truth. Deterministic, so the asserts in `scripts/check.sh`
sit just under what the pipeline reaches.

| Scenario | Tests |
|---|---|
| `house-mix` | 126 groove → 16-bar pad breakdown with an 8-bar clap build → groove → ramp 126→128 → 16-bar blend with a bass swap → hard cut 0.3 beat off-grid into 122 |
| `loop-off-one` | a track whose audio starts on beat 3, minimal for 16 bars, then full |
| `minimal` | kick + closed hat only: the beat locks, the bar must never lock on a wrong 1 |
| `half-time-break` | 8 bars with kick on 1 and 3 only |
| `spinback` | a 2-beat spinback/echo-out, then a new track: nothing committed from the spinback |
| `silence-gap` | 5 s of silence mid-groove, same track resumes |
| `techno-140` | octave guard at a fast 4/4 tempo |
| `dnb-174` | two-step DnB with a hats-only intro, a pad breakdown and a re-drop: must read 174, not 87 |
| `dnb-blend` | two DnB tracks at 172 and 174, a long blend with a pitch ramp, then half-time drums: tempo stays 174 |
| `jungle-170` | a chopped Amen-like break with ghost snares and a displaced kick |
| `breaks-132` | syncopated kick, snare on 2 and 4, a kick-on-1-only section, a hard cut into 4/4 at 128 |
| `peer-edit` | `house-mix` with foreign tempo and phase edits: logged, never answered by a force |

### Real audio

`bench/sources.tsv` lists 34 Creative Commons files (13.4 h: DJ sets and single tracks in all three families). The
audio is never committed; `bench/tools/fetch.sh` downloads it to `~/Music/vChainBench/audio`. The annotations in
`bench/annotations/` are machine-made beat times (Beat This! offline, `bench/tools/annotate.sh`), not hand-checked: on
the synthetic scenarios they reach beat F 0.90–1.00 and 97–100 % right downbeats, with −2…+13 ms timing offset, so
real-audio phase numbers carry about ±10 ms of systematic uncertainty and are partly circular for the NN path (the same
model made them). An independent check used All-In-One annotations on 8 tracks (not in the repo).

### Targets

Stage 1 (the beat; `--assert 1` checks these on the synthetic scenarios, per family; `scripts/check.sh` runs it on
`tempo-phase`):

| Metric | 4/4 | DnB | Breaks |
|---|---|---|---|
| BPM error, steady | median ≤ 0.05, max ≤ 0.15 (ramps and the spinback: max ≤ 1.5, a guard) | same | same |
| Octave right | ≥ 99 % | ≥ 99 % (half-time included) | ≥ 98 % |
| Phase error | median < 15 ms, p90 < 30 ms | < 20 / 40 ms | < 20 / 40 ms |
| Beat F | ≥ 0.95 | ≥ 0.93 | ≥ 0.92 |
| Visible jumps | ≤ 3 per minute (synthetic sections are 1–2 min, where the first lock's jump and one bar move already read as 1–2) | same | same |
| Shown-value changes, steady | ≤ 4 per minute | same | same |
| Lock time, track start | ≤ 8 s median | ≤ 10 s | ≤ 10 s |
| Lock time, hard cut | ≤ 5 s median (asserted as a 16 s regression guard; 45 s after the spinback) | ≤ 6 s | ≤ 6 s |
| Breakdown hold | 0 commits; phase error at the return < 30 ms | < 40 ms | < 40 ms |
| Forces | ≤ 1 phase jump per lock, none answering a foreign edit | same | same |
| CPU | ≤ 0.3 ms per hop mean, ≤ 2 ms p99 | | |

Stage 2 (the 1):

| Metric | Target |
|---|---|
| Bar right after the first bar lock | 4/4 ≥ 85 %, DnB ≥ 85 %, breaks ≥ 75 % |
| Precision (bar right while `barLocked`) | ≥ 97 % |
| `minimal` | never `barLocked` with a wrong 1 for more than 2 bars |
| Wrong bar moves | ≤ 1 per 10 sections |
| Foreign edits | each logged; no force within 8 beats after one |

### Where it stands

Synthetic: `tempo-phase` passes every stage 1 assert; `hy-tempo-phase` fails 2, on `dnb-174`. Relock after a hard
cut still misses the 5–6 s target (13.8–14.8 s: the tempo holds through the cut, only the grid relocks; 39 s after the
spinback), hence the guards. Phase error is
1–6 ms median with no input latency, tempo within 0.01 BPM, DnB at 174 with genre Auto, about one jump per lock, about
50 µs per hop.

Real audio, hybrid TempoPhase against the snap baseline (`requestBeatAtTime` on every aubio detection; 34 files, `--headline`):

| | Visible jumps / min | Phase median / p90 (ms) | Beat F | Shown changes / min | Octave |
|---|---|---|---|---|---|
| Snap baseline, alone in Link | 73 | 58 / 205 | 0.49 | 1.1 | 81 % |
| Snap baseline, with a peer | 0.03 | 96 / 194 | 0.35 | 1.1 | 81 % |
| Drum-only TempoPhase | 0.12 | 33 / 180 | 0.67 | 1.1 | 81 % |
| **Hybrid TempoPhase** | **0.06** | **28 / 125** | **0.81** | 1.6 | **90 %** |

On the 8 independently annotated tracks the hybrid reaches 41 / 98 ms and beat F 0.83 (drum-only 44 / 177 ms, 0.65).
The bar from NN downbeats on those tracks: right after the first lock 90 % (4/4), 99 % (DnB), 95 % (breaks), precision
98–100 %, no wrong bar moves; synthetic breaks fall short (71 %) because `breaks-132` cuts into a 4/4 track while the
vote is still on the old bar.

Known limits:
- A wrong first lock can stay until a better grid has held for 16 beats.
- Drum-only mode (no model) keeps the drum front end's weaknesses on real masters: wrong grids on some tracks, DnB often
  at 87, no bar.
- Real-audio numbers are against machine annotations; a few DnB annotations look wrong (snares on "2 and 3+").
- Input latency figures per device are from Core Audio and ScreenCaptureKit, not measured with a loopback click;
  Resolume's own video latency comes on top (the Beat offset is the fix).
