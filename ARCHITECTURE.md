# vChain — Architecture

Two layers: a C++ **engine** that captures audio and runs analysis modules, and a SwiftUI **app** that
shows it and changes its settings. They meet at one plain-C header, `Sources/VChainEngine/include/vchain_engine.h`.

## Stack

| Layer | Technology |
|-------|------------|
| Audio input | Core Audio (HAL input unit) for interfaces/mics; ScreenCaptureKit for System Audio |
| Beat analysis | `VChainDSP` (C++17, shared with the bench): drum onsets, a grid fitted to them, the beat tracker and the Link driver (`docs/beat-tracking.md`) |
| Neural network | `VChainNN`: [Beat This!](https://github.com/CPJKU/beat_this) (MIT) as a bundled Core ML model on the Neural Engine, Objective-C++; with the drum-onset grid it forms the hybrid tempo/phase/bar tracker |
| aubio | [aubio](https://aubio.org/) 0.4.9, git submodule `lib/aubio`, compiled in (`Sources/CAubio`): only the coarse tempo estimate and octave guard (before the first lock), and FFT/filter helpers |
| Audio descriptors | own code in `audio_analyzer.cpp` (Energy CCs) and `VChainDSP/trigger_bands.*` (trigger CCs) |
| Tempo sync | [Ableton Link](https://github.com/Ableton/link), header-only, git submodule `lib/link` |
| MIDI output | CoreMIDI virtual source, 14-bit CC |
| Engine language | C++17 + Objective-C++ (ScreenCaptureKit, Core ML), exposed through a plain C API |
| UI | SwiftUI (macOS 15+) with AppKit where needed (menu bar image, transparent panel, offscreen renders); a `MenuBarExtra` app. Pure UI logic in `VChainKit` |
| Updates | [Sparkle 2](https://sparkle-project.org) (SwiftPM), feed at bitmapbabe.com/vchain/appcast.xml |
| Build | Swift Package Manager (`Package.swift`, `--build-system native`) + `build.sh` for the .app bundle; Command Line Tools only |
| Checks | `VChainChecks` (plain-assert executable) and `VChainBench` (offline beat bench), both run by `scripts/check.sh` |

SwiftPM targets: `CAubio` (aubio sources), `VChainDSP` (beat analysis, C++), `VChainNN` (Core ML front end),
`VChainEngine` (inputs, modules, C API), `VChainKit` (pure Swift logic), `VChain` (the app, + the Sparkle package),
`VChainChecks` and `VChainBench` (executables for checks and the bench).

```
 Core Audio input ─┐                       ┌──────────── VCEngine (engine.cpp) ────────────┐
 ScreenCaptureKit ─┼─► lock-free ring ───► │ processing thread, every ~3 ms:               │
 test file (dev) ──┘    buffers            │   drain 512-sample hops → modules in order:   │
                                           │     BpmModule  (BeatEngine + NN + Link)       │
                                           │     MidiAnalysisModule (AudioAnalyzer + port) │
                                           │   fill VCSnapshot ─► snapshot mutex           │
                                           └───────────────▲───────────────┬──────────────┘
                                    settings via C API     │               │ vc_engine_get_snapshot
                                    (engine mutex)         │               ▼
                                           ┌────────── EngineModel (@Observable, main actor) ─┐
                                           │ settings ↔ UserDefaults · model.input (devices)  │
                                           │ live() → LiveState (Swift copy of the snapshot)  │
                                           └───────────────┬──────────────────────────────────┘
                                                           ▼
                                SwiftUI: menu bar readout + keychain · Settings
```

## Threads

| Thread | Does | Never does |
|--------|------|------------|
| Core Audio IO / SCK sample queue / file feeder | copies samples into its input's `RingBuffer` | lock, allocate, call modules |
| Engine thread (`VCEngine::run`) | drains hops, runs modules (aubio, Link session updates, CoreMIDI send), publishes the snapshot | touch UI |
| Main thread | polls the snapshot per frame, applies settings through the C API | audio processing |
| Background task | `vc_engine_select_*` from `InputController` (ScreenCaptureKit start can block up to 5 s, stop up to 3 s) | hold the engine mutex while an input starts or stops |
| NN thread (`NNFrontEnd`) | Core ML predictions (Beat This!), once a second | touch Link, lock anything the engine holds |

Every input (`AudioInput`, `SystemAudio`, `FileInput`) implements `AudioSource` (audio_source.h) and fills its own
lock-free `RingBuffer` (ring_buffer.h) on its own thread. The engine thread reads through one `AudioSource*`
(`VCEngine::input`), nullptr while an input is being selected, in hops of `BeatEngine::kHopSize` (512) samples.

`VCEngine::mutex` guards modules and inputs; the engine thread holds it while processing a batch of hops
and API calls take it to change configuration. Input selection holds its own `selectMutex` (one switch at a time)
and takes `mutex` only twice: to detach the engine thread from every input (`input` = nullptr, so it reads none; the snapshot shows
`STARTING`) and, after stopping, draining and starting the inputs unlocked, to attach the new one and reinit the
modules. So a slow ScreenCaptureKit start or stop never stalls the engine thread or the setters. Disabling BPM
(`BpmModule::shutdown`, under `mutex`) doesn't wait for a Core ML model load either: `NNFrontEnd::stop` lets a
thread that is still loading go (it exits after the load without touching the module) and joins only a running
worker (at most one prediction, ~50 ms). `snapshotMutex` only guards a small copy, so the UI never waits on audio
work. Audio callbacks don't take any of these locks.


## Modules

```cpp
class Module {
    virtual const char* name() const = 0;
    virtual void init(uint32_t sampleRate, uint32_t hopSize) = 0;   // create resources
    virtual void shutdown() = 0;                                    // destroy them
    virtual void reinit(uint32_t sampleRate, uint32_t hopSize) = 0; // sample-rate change
    virtual void process(ModuleContext& ctx) = 0;                   // every hop while enabled
    void setEnabled(bool, uint32_t sampleRate, uint32_t hopSize);   // init()/shutdown()
};
```

`ModuleContext` carries the hop (`samples`, `count`), its capture time (`captureValid`, `captureTicks`,
`fixedLatencyUs`) and `bpm`, the shown tempo the BPM module writes for MIDI analysis.

- **BpmModule** owns a `BeatEngine` (VChainDSP, below) and an `ableton::Link` session (created on enable, so turning BPM
  detection off leaves the Link session), wrapped in `RealLinkPort` (`real_link_port.h`: one Link commit per hop).
  The tempo is a grid fitted to kick/snare onsets
  (aubio only as the coarse estimate and octave guard), committed to Link with hysteresis; the phase is steered by
  small tempo nudges from that grid while it is locked (held otherwise), with one jump only at the first lock or a
  new track.
  With the bundled Beat This! model (build.sh copies `beat_this_final0_T600_fp16.mlpackage` into Resources), BpmModule
  also runs `NNFrontEnd` (Sources/VChainNN): the log-mel spectrogram on the engine thread, the network on its own
  thread via Core ML on the Neural Engine (one 12 s window a second, ~50 ms), beats handed back lock-free and merged;
  the engine then runs the hybrid (drum tracker + NN tracker, an arbiter picks the grid). Without the model:
  drum-only. The compiled model is cached in ~/Library/Application Support/vChain/NN. Writes the shown tempo
  (`bpm`) into the context; exposes confidence, beat state, bar lock, Link peers and `linkPhase()` for the snapshot.
  Genre preset survives disable/enable.
- **MidiAnalysisModule** owns `AudioAnalyzer` and `MidiSender` (virtual CoreMIDI source, created on
  enable; trigger and descriptor CCs each on their own channel, `vc_engine_set_trigger_channel` /
  `vc_engine_set_descriptor_channel`, default `VC_MIDI_CHANNEL` = 16). Reads `ctx.bpm`. Keeps port name, the trigger-only pause (the MIDI strip's plug, off with the strip's slide too) and the
  descriptor-only pause (the Energy module's plug), the MIDI learn sweep (`vc_engine_send_learn_sweep`: one CC, 0 → 127 → 0,
  sent even while paused), trigger band count, trigger decay (`vc_engine_set_trigger_decay`) and descriptor
  toggles itself and applies them to each new analyzer. The trigger CCs come from `TriggerBands` (VChainDSP,
  `trigger_bands.*`): 3 bands = kick / snare / hat from `DrumOnsets`, other counts = `BandOnsets` (one band-pass
  onset detector per band, with click, spill and cross-band masking), then `TriggerEnvelope` (tempo-locked decay
  from `ctx.bpm`, or following the band's energy).

Modules contribute no UI or menus; the Swift app reads their state through the snapshot.

## VChainDSP and the bench

`Sources/VChainDSP` is pure C++ (aubio only; no Core Audio, no real Link, no clock reads), shared by the engine and
`VChainBench`. `BeatEngine::process(hop, n, captureUs, LinkPort&)` runs `BpmDetector` (aubio: coarse
tempo and octave guard), `DrumOnsets` (kick/snare/hat onsets), `BeatTracker` (`GridFit` + `BeatPhase`:
committed grid, searching/settling/locked/holding), with NN beats a second `BeatTracker` and an arbiter (the hybrid),
`BarVote` (the 1, from NN downbeats) and `LinkDriver` (everything written to Link). The NN's input and output
helpers live here too (`LogMel`, `pickNNPeaks`, `NNBeatMerger`), so the bench uses the app's code. `VChainBench`
runs the same code offline against a simulated Link (`LinkSim`: Link's own SessionState math) on synthetic scenarios
and annotated CC audio; see `bench/README.md` and `docs/beat-tracking.md`.

## MIDI output

Virtual source **"vChain"** (hosts like Resolume key mappings by device name). It exists
whenever vChain runs: no master MIDI switch, each module has its own power and MIDI OUT plug. Each module sends on its **own configurable channel** (Settings › BandsDance and › Annalisa, 1–16; `stripChannel` /
`energyChannel` in UserDefaults → `vc_engine_set_trigger_channel` / `vc_engine_set_descriptor_channel`). A learn sweep goes
out on its CC's channel. Default **16**
(`VC_MIDI_CHANNEL` in vchain_engine.h; not 1, so it doesn't collide with
hardware controllers that default to ch 1), 14-bit CC (MSB on the CC, LSB on CC + 32):

| CC | Value |
|----|-------|
| 1–8 | Trigger bands (number set in Settings › BandsDance, default 3). **3 = instruments**: CC 1 kick, CC 2 snare/clap, CC 3 hats (`DrumOnsets`, the beat grid's detector, with trigger-only options: kicks under a rumble (only within 1 s of a snare or hat, not from a bassline in a drumless break), a 150–400 Hz punch check that rejects offbeat bass (or, for kicks with little punch, a downward pitch sweep: the attack through 150–400 Hz first, or a loud hit whose zero-crossing pitch falls ≥ 0.5 octave), and snares/claps that need a 1–5 kHz tail 16–21 ms on so a kick's beater click isn't one; LCDs read bd / Sd / HH; measured by `bench/tools/kick_eval.sh`). **2, 4–8 = frequency bands** (`vc_trigger_band_edges`), each with its own detector (`BandOnsets`; a rise too small for the band's threshold, e.g. a kick under a rumble, counts when another band hits clearly at the same moment, a higher band up to ~40 ms earlier, amid other bands' hits). A hit jumps to its strength (relative to the band's recent hits), then falls to 0 over Settings › BandsDance › Trigger decay (1/16–1 beat at the current BPM, default 1/2, or follow the sound). `VChainDSP/trigger_bands.*`, checked by the bench's `triggers*` unit tests |
| 9 | Loudness (400 ms, K-weighted, −30…−6 dB) |
| 10 | Intensity (3 s, drum hits from `DrumOnsets` per second × noisiness) |
| 11 | Brightness (5 s, 85 % spectral rolloff, 200 Hz–10 kHz log) |
| 12 | Tone (1 s, treble 2–16 kHz vs. bass < 250 Hz, −30…0 dB; fades to 0 over 1 s when the music stops) |
| 13 | Change (8 beats in beat-long blocks, tonal change) |
| 14 | Texture (3 s, spectral entropy). Ranges set from the bench tracks (constants at the top of audio_analyzer.cpp); Brightness, Tone and Texture use the 4096-point Hann spectrum and read 0 below ≈ −70 dB (silence) |

What goes out, per module: the MIDI strip's slide is the strip on/off (`stripEnabled`; off = dark and its
CCs silent) and its MIDI OUT plug pauses only CCs 1–8 (`triggersSending`); the Energy module's power key is the module
on/off (`energyEnabled`, the descriptors not even computed) and its plug pauses only CCs 9–14 (`energySending` →
`vc_engine_set_midi_descriptors_sending`). Unplugged, a module keeps analysing and showing; Settings › BandsDance and › Annalisa show each module's power
(header switch) and its plug as a **MIDI out: Live | Learn** switch (Learn = unplugged). Clicking a plug in means "send": it also turns the module back on.
Clicking a plug switches instantly; hovering one eases it a little out of its socket (`PlugMotion`, shows its pin).
**MIDI learn:** while a module is unplugged (and in front), clicking one of its bands (strip) or rows (Energy) sends just
that CC once as a 0 → 127 → 0 sweep (`vc_engine_send_learn_sweep`, `VC_LEARN_SWEEP_SECONDS` = 0.4 s, sent even while
unplugged or paused; `EngineModel.sendLearnSweep`), and that ladder or line runs with it (`LearnPlayer` in KeychainPlayers.swift).
Hints while unplugged: the strip's channel LCD reads "LRn", the Energy header "UNPLUGGED · LEARN".

## C API (vchain_engine.h)

The header is grouped: constants (`VC_BEATS_PER_BAR`, `VC_MIN_TRIGGER_BANDS`…`VC_MAX_TRIGGER_BANDS`, `VC_CC_TRIGGER_BASE` /
`VC_CC_DESCRIPTOR_BASE`, `VC_MIDI_CHANNEL`…), types (`VCSnapshot` with `numTriggerBands` / `triggers[]`, descriptors and
spectrum), the engine's functions (engine.cpp) and the engine-free functions (api_functions.cpp).

- Lifecycle: `vc_engine_create(portName)`, `vc_engine_destroy`.
- Configuration: `vc_engine_set_module_enabled`, `vc_engine_set_genre`, `vc_engine_set_beat_offset_ms`,
  `vc_engine_set_midi_triggers_sending` (CC 1–8) / `vc_engine_set_midi_descriptors_sending` (CC 9–14),
  `vc_engine_set_trigger_channel` / `vc_engine_set_descriptor_channel`, `vc_engine_set_num_trigger_bands`,
  `vc_engine_set_trigger_decay`, `vc_engine_set_descriptor_enabled`, `vc_engine_send_learn_sweep`.
- Input (blocking, return `VCInputState`): `vc_engine_select_system_audio`, `vc_engine_select_device`,
  `vc_engine_select_file` (developer input).
- Live: `vc_engine_get_snapshot(VCSnapshot*)`, `vc_now_micros()` (the clock `phaseMicros` uses; the UI
  extrapolates the Link phase between engine updates).
- Engine-free (api_functions.cpp): genres, descriptor names, `vc_list_input_devices`, and the pure functions `vc_spectrum_bands` / `vc_spectrum_band_edges` / `vc_spectrum_fft_size` (display
  spectrum), `vc_trigger_band_edges(count, lo, hi)` (the trigger band ranges in Hz, from VChainDSP's
  `triggerBandEdges`; the analyzer's `initTriggerBands` uses it too, and the MIDI strip's range LCDs show it). Checked by `VChainChecks`.

Swift never sees C++: the header is plain C (`extern "C"`), so no Swift/C++ interop mode is needed.

## Swift app

- `VChainApp`: a menu bar app that keeps its Dock icon (Dock click → `applicationShouldHandleReopen`
  opens the keychain; the Help menu is empty, there's no help book). A `MenuBarExtra`
  (`.window` style) shows `KeychainView`, made transparent by `TransparentPanel`; a `Window` scene only for
  the suppressed developer gallery (`-debugOpen modules`); `Settings` scene with General / BPM Tag / MIDI Strip / Energy tabs.
  Windows open through `WindowOpener`, which activates the app first.
- `Keychain/`: `KeychainView` hangs three modules (BPM tag, MIDI strip, Energy module) from a split ring (`RingPiece`,
  Ring.swift) at the places `KeychainLayout` computes; the right-click menu is `KeychainMenu`.
  Each is a pendulum (`Pendulum` in VChainKit, period 0.5 s) swung about its keyring hole; opening drops
  all three in (shared ring drop) swung 11° to the right (`KeychainMotion`); the short click-started motions (power-ons,
  strip eject/add, plug hover, learn sweeps) are players in KeychainPlayers.swift. Modules are Canvas drawings
  (`PartCanvas` and helpers in `Drawing.swift`, parts in `Hardware.swift`, `StripParts.swift`, `Stickers.swift`, `MIDIOut.swift`;
  hit areas in `ModuleDrawing.swift`) wrapped in `Equatable`
  `Frozen` views so a frame where nothing visible changed doesn't redraw. The timeline pauses while the
  panel is closed. The BPM tag and the MIDI strip share the segment-LCD drawing (`SegmentLCD.swift`: glass,
  ghosts, glow, glare, `sevenSeg`); each MIDI channel module has a range LCD and a `CC n` LCD. Pure logic
  (`BPMTagState`, `KeychainState`, `KeyringGeometry`, `SevenSegment`, `BandLCD`, `DescriptorMask`, the power-on timelines
  with `StripPowerOn.withLearn` / `withSettle`) is in `VChainKit` and checked by `VChainChecks`.
- `MenuBarReadout`: the menu bar label, the mascot (the dancer, posed by `BPMTagState` like the tag's LCD; `Mascot.menuArt`) + BPM drawn into a fixed-width template image, polled
  at 10 Hz on a timer (not the animation timeline, so it runs with the keychain closed), plus a one-shot update exactly
  on each beat change (`BeatTicker`: the next beat, or the end of the move on the 1), and redrawn only when
  what it shows changes. With the keychain closed only this runs, ≈ 7 % CPU vs. ≈ 50 % with live views open.
- `EngineModel`: the only object that talks to the engine. Settings are observable properties persisted
  in UserDefaults (keys: `SettingsKey`) and pushed to the engine in `didSet`; `pushAll()` sends the restored ones at
  launch. It owns `InputController` (`model.input`, below). Live values are *not* observed: views read them
  with `model.live()` inside a `TimelineView` (the keychain's, the menu bar readout's poll), so display-rate redraws
  don't invalidate the rest of the UI (`LiveState`, LiveState.swift). `model.input.health` (`InputHealth`) is the
  exception — a 4 Hz poll, because the animation timeline stops while the display sleeps.
- The snapshot carries a 24-band spectrum (`VCSnapshot.spectrum`, log-spaced 40 Hz–16 kHz, each band the peak
  bin magnitude mapped from −60…0 dB to 0…1, smoothed attack 0.5 / release 0.08 per hop; `AudioAnalyzer`, bands from `vc_spectrum_bands`). It
  comes from its own Hann-windowed FFT over the last `vc_spectrum_fft_size()` samples (4096 at 48 kHz, ≤ 12 Hz
  bins, so each low band has a bin of its own), recomputed every hop; the descriptors keep their one-hop FFT (the trigger bands use band-pass filters). Zero while MIDI analysis is off. The Energy module draws it as 24 vertical bars.
- `InputController` (`model.input`): the selected and remembered source, the device list, `isSwitching`, `deviceMissing`,
  `retry()`, and the health poll; it restarts a System Audio capture the display's sleep stopped (every 5 s and on screen
  wake). Input devices refresh on `kAudioHardwarePropertyDevices` changes; a remembered device that's unplugged
  shows as "Not Connected" and is picked up again when it returns. Inputs are remembered by name
  (device IDs change between boots).
- Permissions: Screen & System Audio Recording for System Audio (checked with
  `CGPreflightScreenCaptureAccess` in the engine after a failed start), Microphone for devices (`AVCaptureDevice`, in
  `InputController`).
  Both show an inline explanation with Open Privacy Settings… and Try Again.

## Future module ideas

OSC output module, a recorder for offline descriptor analysis. A new module:
subclass `Module`, add it to `VCEngine::modules`, extend `VCSnapshot` and the C API, then the UI.
