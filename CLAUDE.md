# vChain

macOS menu bar app (keeps its Dock icon; clicking it opens the keychain) for live VJ use next to Link/MIDI software such as Resolume Arena: detects BPM from audio, shares tempo and beat phase
over Ableton Link, and sends drum triggers and audio-analysis values as 14-bit MIDI CC. Code names: targets `VChain*`, C API
`vc_*` / `VC*` (include/vchain_engine.h), executable `Contents/MacOS/VChain` (dev copy process `VChainDev`), bundle id
`com.bitmapbabe.vchain`, support folder `~/Library/Application Support/vChain`, signing certificate "vChain Dev". The BPM
tag module is called **Beat-o-Matic** in the UI (code: `BPMTagView`, `.bpm`, Settings pane id "bpm"), the MIDI strip
**BandsDance** (`MIDIStripView`, `.midi`, "midi") and the Energy module **Annalisa** (`EnergyModuleView`, `.energy`,
"energy"; its six values are the Energy descriptors). Repo: github.com/nikinoldin/vchain.
Licence GPL-3.0-or-later (LICENSE, THIRD_PARTY_NOTICES.md).

## Project Structure

```
vchain/
├── Package.swift             <- SwiftPM: 8 targets (below) + the Sparkle package
├── build.sh                  <- swift build + hand-assembled "build/vChain.app" (Sparkle.framework, NN model) + signing
├── Info.plist                <- bundle metadata (mic, screen capture, local network, fonts path, Sparkle feed + key)
├── README.md                 <- usage, build, dev workflow, release
├── ARCHITECTURE.md           <- stack, engine, threads, modules, MIDI output (CC table), C API, Swift app
├── docs/beat-tracking.md     <- the beat pipeline (tempo, phase, the 1), bench metrics, targets, results
├── THIRD_PARTY_NOTICES.md    <- licences of everything bundled (shipped in the app)
├── assets/                   <- AppIcon.icns/.png (scripts/make-icon.sh), Credits.html (About panel), dmg/ (DMG background),
│                                readme-hero.png (the README's top picture, scripts/readme/hero.py)
├── bench/                    <- VChainBench data: test-audio list, machine-made beat annotations, baselines, nn/ (model
│                                scripts, make_model.sh), tools/; bench/README.md
├── lib/link/                 <- Ableton Link SDK (git submodule)
├── lib/aubio/                <- aubio 0.4.9 (git submodule, tag 0.4.9)
├── scripts/                  <- check.sh (VChainChecks + bench), run-dev.sh, release.sh (+ dmg/: dmgbuild settings,
│                                background), readme/hero.py, make-icon.sh, export-vector.sh, screenshot.sh, menu-dump.applescript
└── Sources/
    ├── CAubio/               <- compiles aubio 0.4.9 (submodule lib/aubio, symlinked as aubio/) into the app: config.h
    │                            (Accelerate FFT, no libsndfile), module map, README
    ├── VChainKit/            <- pure logic for the keychain (Foundation/CoreGraphics only): BPMTagState, KeychainState,
    │                            KeyringGeometry, Pendulum, BeadCharms, SevenSegment, BandLCD, DescriptorMask, PlugMotion,
    │                            StripPowerOn / TagPowerOn / EnergyPowerOn (power-on timelines), StripEdit (eject/add motion)
    ├── VChainChecks/         <- executable that checks VChainKit + the engine's pure C functions (scripts/check.sh)
    ├── VChainEngine/         <- C++/ObjC++ engine; include/vchain_engine.h is the only header Swift sees (grouped:
    │   │                        constants, types, engine, engine-free functions)
    │   ├── engine.cpp        <- VCEngine: inputs, module chain, processing thread, snapshot, the engine's C API
    │   ├── api_functions.cpp <- the engine-free C functions (clock, static info, devices, spectrum bands, trigger band
    │   │                        ranges, the learn sweep)
    │   ├── module.h          <- Module base class + ModuleContext
    │   ├── bpm_module.*      <- BeatEngine (TempoPhase) + NNFrontEnd + Ableton Link session (real_link_port.h)
    │   ├── midi_analysis_module.* <- AudioAnalyzer + MidiSender (virtual port)
    │   ├── audio_analyzer.*  <- trigger bands, Energy descriptors and the 24-band display spectrum; midi_sender.*
    │   ├── audio_source.h    <- AudioSource, the one interface the engine thread reads an input through
    │   ├── ring_buffer.h     <- the lock-free RingBuffer every input fills
    │   └── audio_input.* (Core Audio device), system_audio.* (ScreenCaptureKit), file_input.* (developer input),
    │                            capture_clock.h
    ├── VChainDSP/            <- pure C++ beat analysis + Link driving (BpmDetector, DrumOnsets, GridFit, BeatPhase,
    │                            BeatTracker, BarVote, LinkDriver, BeatEngine; LogMel, nn_peaks, NNBeatMerger for the NN;
    │                            trigger_bands for the MIDI strip; helpers biquad.h, hann.h, k_weighting.h; link_port.h:
    │                            LinkPort + kLinkQuantum); shared by the engine and the bench
    ├── VChainNN/             <- Beat This! via Core ML (BeatNet, Objective-C++) + NNFrontEnd (its own thread); model made
    │                            by bench/nn/make_model.sh, bundled by build.sh
    ├── VChainBench/          <- offline bench (simulated Link, synthetic scenarios, real CC audio); bench/README.md
    └── VChain/               <- SwiftUI app
        ├── VChainApp.swift   <- scenes: MenuBarExtra keychain, Settings
        ├── MenuBarReadout.swift <- the menu bar item: the mascot (dancer, posed like the tag's LCD) + BPM as a template image,
        │                        10 Hz poll + an update exactly on each beat change (BeatTicker.swift, shared with the keychain)
        ├── EngineModel.swift <- @Observable model over the engine: settings (SettingsKey, UserDefaults, pushAll), live()
        ├── InputController.swift <- the input (`model.input`): source, devices, health (4 Hz poll), isSwitching,
        │                        deviceMissing, retry(); restarts System Audio that the display's sleep stopped
        ├── LiveState.swift   <- LiveState (the views' Swift copy of VCSnapshot) + InputHealth
        ├── SampleData.swift  <- fixed sample values for module pictures without live audio (Settings, icon, export)
        ├── Keychain/         <- the menu bar drop-down:
        │                        KeychainView (ring + 3 modules + bead charms, KeychainMotion), KeychainLayout (where
        │                        everything hangs), KeychainPlayers (PowerOnPlayer, StripEditor, PlugHover, LearnPlayer:
        │                        the short click-started motions), Ring (RingPiece), KeychainMenu (right-click menu),
        │                        TransparentPanel, DetachedKeychain (KeychainDock: right-click › Detach floats it in its
        │                        own window, dragged by the ring), BPMTagView, MIDIStripView, EnergyModuleView,
        │                        BeadCharmsView + BeadArt (bead strands on a chain, decoration), SegmentLCD (shared LCD
        │                        glass), Mascot + MascotGeometry + DancerKit (the LCD/menu bar character: the dancer,
        │                        outfit Fluffies (cute redraw); poses from BPMTagState.mascot, more characters can be
        │                        added), Drawing (PartCanvas, hex, insetShadow/dropShadow, clipOut…), Hardware (parts),
        │                        ModuleDrawing (key style, hit areas, ModuleOutline), StripParts (StripGeometry, eject
        │                        and add keys), TagScrew / TagGrille / TagSetButton (the BPM tag's flush Phillips screws,
        │                        drilled grille, ribbed side SET key), Stickers (SmileySticker, BitmapBabeSticker on the
        │                        strip's right cap, PrideFlagSticker over its bottom end), SVGPathData (path parser),
        │                        MIDIOut (MIDIOutJack, the right-angle MIDI OUT plug on the strip and the Energy module;
        │                        MIDIOutHit), ModuleGallery (debug window, `-debugOpen modules`; `-modulesPage keychain`
        │                        shows the whole keychain at rest; `-debugRenderKeychain <png>` renders offscreen, no
        │                        window) + PowerOnStrips (`-debugRenderTagPowerOn` / `-debugRenderEnergyPowerOn` frame
        │                        strips), AppIconRender (the app icon: the BPM tag on a white grid squircle,
        │                        `-debugRenderIcon <dir>`), ExportShading (vector export)
        ├── Updates.swift      <- Sparkle updates (feed bitmapbabe.com/vchain/appcast.xml → latest GitHub release)
        ├── WindowOpener.swift, InputControls.swift, Brand.swift (bundled fonts), ViewState.swift
        ├── MIDIReference.swift (CC numbers, descriptor summaries), SettingsView.swift
        ├── DebugLaunch.swift, DebugSnapshot.swift <- developer launch switches
        └── Fonts/            <- Big Shoulders Display (Annalisa's lettering) + its OFL licence; the only font in the app
```

## Building

`./build.sh` → build/vChain.app (details, the NN model, signing and release needs: README.md). Command Line Tools are
enough (no Xcode); SwiftPM needs `--build-system native` (the scripts pass it). With CLT only, SwiftUI's `@State`
macro plugin is missing: use `@ViewState` (typealias in ViewState.swift). `build.sh` signs with the persistent
"vChain Dev" certificate so macOS keeps the Screen Recording/Microphone grants across rebuilds (ad-hoc without it).
A failed build fails `build.sh` and `scripts/check.sh`.

## Architecture in one paragraph

Audio callbacks (Core Audio / ScreenCaptureKit) only write into lock-free ring buffers (`RingBuffer`, one per input;
every input is an `AudioSource`). The engine thread (`engine.cpp`) reads the selected one in 512-sample hops
(`BeatEngine::kHopSize`), runs the enabled modules in order (BPM → MIDI analysis,
sharing a `ModuleContext`), and publishes a `VCSnapshot` under a tiny mutex. SwiftUI polls it:
the keychain's `TimelineView` calls `model.live()`, which hands views a Swift `LiveState`. Settings
calls go through the C API and take the engine mutex. See ARCHITECTURE.md; the beat pipeline is in
docs/beat-tracking.md.

## Key patterns and gotchas

- **Never pass the C struct `VCSnapshot` through SwiftUI views or view closures.** It crashed
  AttributeGraph during body diffing (EXC_BAD_ACCESS in `LayoutDescriptor::Compare::Enum`) whenever a
  live closure captured anything. Convert to `LiveState` (LiveState.swift) first.
- Live views redraw at display rate: keep their structure constant (no `if` subtrees, no GeometryReader)
  and use `Text(verbatim:)`.
- `TimelineView(.animation)` stops while the display sleeps; state that must always be current (input
  problems) is polled into `model.input.health` (InputController) by a 4 Hz timer instead.
- Input selection blocks (ScreenCaptureKit start waits up to 5 s): `InputController` calls it off the main thread. The engine
  holds its own `selectMutex` for the switch and the engine mutex only to detach/attach the input (ARCHITECTURE.md, Threads).
- ScreenCaptureKit stops the System Audio stream when the display sleeps (frame status "stopped", usually no
  `didStopWithError`) and never resumes it. The stream also carries the 1 fps 2×2 video frames as a heartbeat; no buffer
  for 3 s reads as `VC_INPUT_STATE_FAILED` (`AudioSource::lost`), and `InputController` restarts it every 5 s and on
  screen wake (not while the screens sleep).
- Module lifecycle: enabling calls `init()` (creates Link session / MIDI port), disabling `shutdown()`.
  Settings that must survive (genre, trigger bands, descriptor toggles, send/pause) live in the module,
  not in the recreated analyzer.
- In a MenuBarExtra window SwiftUI's semantic `.primary` / `.background` styles render vibrant: solid
  fills came out light gray. Use concrete colors (e.g. `Color(nsColor:)`) for lit fills.
- The keychain is a `MenuBarExtra(.window)` made transparent by `TransparentPanel` (clear window, no
  shadow; on macOS 26 it hides the Liquid Glass `CABackdropLayer`, a private class matched by name) and
  pinned under the status item. SwiftUI keeps a closed MenuBarExtra's `TimelineView` running, so the
  keychain pauses its timeline while the panel isn't visible.
- The keychain is a `MenuBarExtra`, so opening a window from it must activate the app first
  (`WindowOpener`), or it opens behind the app in front. The Dock icon opens the keychain by clicking the status
  item (`MenuBarReadout.openPanel`, no SwiftUI API for it).
- `scripts/run-dev.sh` copies run as menu bar items too; open the keychain with
  `osascript -e 'tell application "System Events" to tell process "VChainDev" to perform action "AXPress" of menu bar item 1 of menu bar 2'`
  (it toggles), then `scripts/screenshot.sh`.
- XCTest isn't available with the Command Line Tools: logic worth testing lives in `VChainKit` (no SwiftUI/AppKit,
  no engine) and is checked by `VChainChecks` (`scripts/check.sh`, plain asserts, prints each check and a total).
  Run it before committing; the spectrum bands and trigger band ranges (`vc_trigger_band_edges`) are checked there too
  through the engine's C functions.
- The spectrum (`VCSnapshot.spectrum`, 24 log-spaced bands 40 Hz–16 kHz, 0…1 over −60…0 dB, smoothed per hop) has its
  own 4096-point Hann FFT (at 48 kHz; display only, the CC FFT stays one hop) and is zero while MIDI analysis is off;
  `LiveState.spectrum` feeds the Energy module's spectrum bars.
- Keychain positions that settle on a spring (the drop) must be rounded to the pixel grid: a tail flipping sign
  by millionths of a point made the MIDI strip (half a pixel off the grid) snap a pixel up/down every frame.
  To measure motion without screenshotting the user's screen, capture only the panel window:
  `screencapture -x -o -l <CGWindowID>` (layer-101 window of the dev copy's pid) and compare edges per frame.
- Module controls use `moduleControl(isFront:label:grow:)` (ModuleDrawing.swift): live only while the module is in front,
  `grow` enlarges the hit area (≥ ≈28 pt) without moving the drawing. `-debugHitAreas YES` draws the live hit areas.
  Never put `.contentShape` on a whole module (or any container): it clips its children's hit areas, cursor and hover
  to that shape, and the eject keys and MIDI OUT plugs stick out of the outline.
  A module's own hit area (bring to front) is `ModuleOutline`, the bottom layer of each module view: a path of exactly
  where it's drawn (body, rotated with it, plus protruding rocker/jack/plug/cable/eject keys); `PartCanvas` never hit-tests
  (its frame includes the bleed: shadows, transparent margins), so new drawn parts outside the outline need adding to the
  module's `outline`. `-debugHitAreas` draws the outlines in blue. Padding inside a `ButtonStyle` label needs its own
  `.contentShape` inside the style. To test clicks for real: the dev copy with `-bpmEnabled NO`, then post mouse
  events at the panel window's current position (it moves with the menu bar item's width). Posted events are dropped
  silently without the Accessibility/Post Event grant (`CGPreflightPostEventAccess()`); the dev keychain opening pops
  over the user's apps, so ask before testing that way.
- `-keychainZoom <n>` (launch argument, 1…4) draws the whole keychain n× as large, sharp, for close-up recordings.
- The debug gallery (`-debugOpen modules`) is a `Window` scene with `.defaultLaunchBehavior(.suppressed)` and
  `.commandsRemoved()`: not in the Window menu, never at launch. `-debugSnapshot <dir>` renders it offscreen.
- App icon: one icon everywhere (Finder, Dock closed and running): the BPM tag (locked at 128.0, beat 3 lit, no cable,
  a few LCD ghosts like NO INPUT left out) on a flat white rounded square on the macOS icon grid (824 px
  body at 100…924 of 1024, radius 185, drop shadow offset 18 / blur 18 / black 110), the tag's plate 72 % of the body. White rather than black/off-white because macOS 26 adds its own glass rim
  to non-glass icons (can't be removed), which shows as a bright band on black and is practically invisible on white.
  Rendered by the app's own views (`AppIconRender`, `scripts/make-icon.sh` → assets/AppIcon.icns/.png; rerun it when
  the BPM tag changes). Why the grid: macOS 26 puts a free-form icon (e.g. the tag alone on transparency) on a grey
  tile ("icon jail") in Finder and the Dock; a plain icns whose body fills the grid isn't jailed (checked with
  `NSWorkspace.icon(forFile:)`). An Icon
  Composer `.icon` would need Xcode's actool; a Finder custom icon (`NSWorkspace.setIcon`) breaks the code signature.
- Vector export (`scripts/export-vector.sh`, `-debugRenderVector`): draw keychain gradients with `fill(_:shaded:)` /
  `stroke(_:shaded:)` (ExportShading.swift), not `with: .linearGradient`: Core Graphics' PDF writer drops gradient alpha,
  so the export draws fading gradients through a mask. Cut holes with `ctx.clipOut(_:)`, never `.destinationOut`
  (PDF can't express it, so the whole canvas would become one bitmap).
- Updates: Sparkle 2 (SwiftPM; build.sh copies Sparkle.framework into Contents/Frameworks and signs its XPC services,
  Autoupdate, Updater.app and the framework before the app). Feed and public key in Info.plist (SUFeedURL,
  SUPublicEDKey); the private EdDSA key is in the login keychain under the account "vchain" (Sparkle's
  `generate_keys --account vchain -x <file>` exports a backup). `scripts/release.sh` builds the DMG, the source zip
  and appcast.xml; `--publish` asks patch/minor/major, raises CFBundleShortVersionString and CFBundleVersion (Sparkle
  compares the latter) and commits "Release x.y.z" before building.
  Developer copies (other bundle id, `-testAudioFile`) don't start the updater.
- `system_audio.mm` uses manual retain/release → `-fno-objc-arc` in Package.swift.
- Ableton Link needs `LINK_PLATFORM_MACOSX=1` and the asio-standalone include path (Package.swift).

## MIDI output

Virtual source **"vChain"**, always there while vChain runs (no master switch; each module has its own power and MIDI
OUT plug), 14-bit CC (MSB on the CC, LSB on CC + 32), each module on its own channel (`stripChannel` /
`energyChannel`, default 16, `VC_MIDI_CHANNEL`). CC 1–8 trigger bands
(BandsDance), CC 9–14 the Energy descriptors (Annalisa). The CC table, what each plug/power switch pauses and MIDI
learn: ARCHITECTURE.md, "MIDI output".

## Testing without touching the live setup

`scripts/run-dev.sh <audio file> [args]` launches "vChain Dev" (own bundle id and prefs, MIDI port
"vChain Dev", plays the file instead of capturing, never takes focus). It **does join Ableton Link**:
check `lsof -nP -iUDP:20808` first if other Link software (e.g. Resolume) might be in a session. Screenshots:
`scripts/screenshot.sh <pid> out.png`, or `-debugSnapshot <dir>` when the screen is locked (grouped
Forms render blank that way). Menus: `osascript scripts/menu-dump.applescript VChainDev` (only useful while a window like Settings is open).
More switches in DebugLaunch.swift.

## Platform

macOS 15+, Apple Silicon and Intel (releases are universal: `UNIVERSAL=1 ./build.sh`; everyday builds are arm64 only). Frameworks: SwiftUI, AppKit, Core Audio, AudioToolbox, CoreMIDI,
ScreenCaptureKit, CoreMedia, AVFoundation (mic permission).
