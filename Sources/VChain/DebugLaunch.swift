// SPDX-License-Identifier: GPL-3.0-or-later
import VChainEngine
import VChainKit
import AppKit
import SwiftUI

/// Developer launch switches (scripts/run-dev.sh and the render scripts pass them):
/// - `-testAudioFile <path>`: play a file into the engine instead of capturing (no permissions needed)
/// - `-midiPortName <name>`: virtual MIDI port name, so a dev copy doesn't clash with the real app
/// - `-forceAppearance dark|light`: for screenshots
/// - `-debugOpen settings|modules`: open that window at launch (the menu bar label does it, being the one view that
///   exists at launch); `modules` is the keychain module gallery (`-modulesPage bpm|midi|power|energy|keychain` picks
///   its page; `keychain` is the whole keychain at rest)
/// - `-settingsPane general|bpm|midi|energy`: with `-debugOpen settings`
/// - `-keychainFront bpm|midi|energy|charms`: which module hangs in front when the keychain opens (the app
///   also remembers the last one under this key)
/// - `-triggerBands 2…8`: start with that many MIDI strip modules (overrides the saved setting)
/// - `-debugSnapshot <dir>`: save every window offscreen every 2 s (works with a locked screen)
/// - `-debugRenderKeychain <png>`: render the whole keychain at rest (Modules › KEYCHAIN) offscreen to that file
///   and quit (no window opens); light unless `-forceAppearance dark`
/// - `-debugRenderVector <dir>`: the three modules and the whole keychain at rest as vector PDFs (scripts/export-vector.sh),
///   and quit
/// - `-debugRenderMenuBar <png>`: the menu bar readout's states (mascot poses, settling, no input, off) on light and dark menu
///   bars, real size and 3×, offscreen, and quit
/// - `-debugRenderTagPowerOn <png>`: the BPM tag's power-on as a frame strip (light, dark) and quit
/// - `-debugRenderEnergyPowerOn <png>`: the Energy module's power-on self-test as a frame strip (light, dark) and quit
/// - `-debugRenderIcon <dir>`: write the app icon (the BPM tag on a white grid squircle; AppIconRender) as iconset PNGs
///   into that folder and quit (scripts/make-icon.sh)
/// - `-keychainZoom <n>`: draw the whole keychain n× as large (1…4) for close-up recordings (HardwareScale.zoom)
/// - `-debugHitAreas YES`: draw every module control's hit area (translucent red), in the app and the gallery
/// - `-debugRenderHitAreas <png>`: each module with its controls' hit areas drawn, and quit
/// - `-debugFakeBeat <bpm>`: fake a locked tempo and Link grid from the clock (BPM module off: never joins Link),
///   to measure the keychain's and the menu bar's beat timing and CPU
/// - `-debugInputProblem 3|4`: show the input as VCInputState 3 (no permission) or 4 (failed)
enum DebugLaunch {
    static var inputProblem: UInt32? {
        let v = UserDefaults.standard.integer(forKey: "debugInputProblem")
        return v > 0 ? UInt32(v) : nil
    }
    static var testAudioFile: String? { UserDefaults.standard.string(forKey: "testAudioFile") }
    /// `-debugFakeBeat <bpm>`: a locked tempo and Link grid from the clock (`applyFakeBeat`, in EngineModel.live), with BPM
    /// detection off.
    static let fakeBeat: Double? = {
        let v = UserDefaults.standard.double(forKey: "debugFakeBeat")
        return v > 0 ? v : nil
    }()
    /// `-debugFakeBeat <bpm>`: puts a locked tempo and Link grid from the clock into `s`, for measuring the keychain and
    /// the menu bar without the BPM module (so a dev copy never joins Link). Leaves `s` alone without the switch.
    static func applyFakeBeat(_ s: inout VCSnapshot) {
        guard let bpm = fakeBeat else { return }
        let now = vc_now_micros()
        s.bpmEnabled = true; s.bpm = Float(bpm); s.confidence = 1
        s.linkTempo = bpm; s.phaseMicros = now
        s.linkPhase = (Double(now) / 1_000_000 * bpm / 60).truncatingRemainder(dividingBy: Double(VC_BEATS_PER_BAR))
        s.beatState = Int32(VC_BEAT_LOCKED.rawValue); s.barLocked = true
    }
    static var openWindow: String? { UserDefaults.standard.string(forKey: "debugOpen") }

    @MainActor static func openRequestedWindow(_ open: WindowOpener) {
        switch openWindow {
        case "settings": open.openSettings()
        case "modules": open.openWindow(id: WindowID.modules)
        default: break
        }
    }

    /// `-debugRenderKeychain <png>`, `-debugRenderIcon <dir>` and the other `-debugRender…` switches: writes the
    /// picture(s) offscreen and quits. Returns false when none is requested.
    @MainActor static func renderIfRequested() -> Bool {
        let defaults = UserDefaults.standard
        if let dir = defaults.string(forKey: "debugRenderVector") {
            renderVector(to: dir)
        } else if let path = defaults.string(forKey: "debugRenderKeychain") {
            let dark = defaults.string(forKey: "forceAppearance") == "dark"
            render(ModuleGallery.keychainOverview(dark: dark).padding(20)
                    .galleryBackdrop(dark: dark)
                    .environment(\.colorScheme, dark ? .dark : .light), scale: 2, to: path)
        } else if let path = defaults.string(forKey: "debugRenderHitAreas") {
            DebugHitAreas.on = true
            render(ModuleGallery.hitAreasRender(), scale: 2, to: path)
        } else if let path = defaults.string(forKey: "debugRenderMenuBar") {
            MenuBarReadout.renderPreview(to: path)
        } else if let path = defaults.string(forKey: "debugRenderTagPowerOn") {
            render(ModuleGallery.tagPowerOnStrip(), scale: 2, to: path)
        } else if let path = defaults.string(forKey: "debugRenderEnergyPowerOn") {
            render(ModuleGallery.energyPowerOnStrip(), scale: 2, to: path)
        } else if let path = defaults.string(forKey: "debugRenderIcon") {
            AppIconRender.writeIconset(to: path)
        } else {
            return false
        }
        NSApp.terminate(nil)
        return true
    }

    /// `-debugRenderVector <dir>`: the three modules and the whole keychain at rest as vector PDFs (bpm-tag.pdf,
    /// midi-strip.pdf, energy.pdf, keychain.pdf; light unless `-forceAppearance dark`). Shapes, gradients and text stay
    /// vectors; blurred shadows and glows come out as embedded images (all drawn 4× as large so those stay sharp). scripts/export-vector.sh runs it and turns the PDFs into SVGs.
    @MainActor private static func renderVector(to dir: String) {
        let dark = UserDefaults.standard.string(forKey: "forceAppearance") == "dark"
        let scheme: ColorScheme = dark ? .dark : .light
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        VectorExport.active = true
        func pdf<V: View>(_ name: String, _ view: V, margin: CGFloat = 30) {
            let renderer = ImageRenderer(content: view.padding(margin).environment(\.colorScheme, scheme))
            let url = URL(fileURLWithPath: dir).appendingPathComponent(name)
            renderer.render { size, draw in
                var box = CGRect(origin: .zero, size: size)
                guard let ctx = CGContext(url as CFURL, mediaBox: &box, nil) else { return }
                ctx.beginPDFPage(nil)
                draw(ctx)
                ctx.endPDFPage()
                ctx.closePDF()
            }
        }
        // Drawn 4× as large: blurred shadows and glows are rasterized at the drawing's size, so this keeps them sharp.
        let zoom: CGFloat = 4
        pdf("bpm-tag.pdf", BPMTagView(state: SampleData.tag(), isFront: true, onRocker: {}, onSet: {}, zoom: zoom), margin: 30 * zoom)
        pdf("midi-strip.pdf", MIDIStripView(bands: 3, levels: SampleData.levels, isOn: true, isFront: true, onSlide: {}, onSet: {}, zoom: zoom),
            margin: 30 * zoom)
        pdf("energy.pdf", EnergyModuleView(values: SampleData.values, enabled: Array(repeating: true, count: 6),
                                           isOn: true, spectrum: SampleData.spectrum, isFront: true, onPower: {}, onSet: {}, onToggle: { _ in },
                                           zoom: zoom), margin: 30 * zoom)
        let layout = KeychainLayout(bands: 3)
        pdf("keychain.pdf", ModuleGallery.restingKeychain(front: .bpm, bands: 3, ringPoint: layout.ringPoint, size: layout.size)
            .scaleEffect(zoom, anchor: .topLeading)
            .frame(width: layout.size.width * zoom, height: layout.size.height * zoom, alignment: .topLeading),
            margin: 30 * zoom)
    }

    @MainActor private static func render<V: View>(_ view: V, scale: CGFloat, to path: String) {
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        if let cg = renderer.cgImage {
            try? NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
        }
    }

    @MainActor static func applyAppearance() {
        switch UserDefaults.standard.string(forKey: "forceAppearance") {
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        default: break
        }
    }
}
