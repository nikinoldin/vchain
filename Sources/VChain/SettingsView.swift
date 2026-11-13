// SPDX-License-Identifier: GPL-3.0-or-later
import VChainEngine
import VChainKit
import SwiftUI

/// Settings… (right-click menu, ⌘,; SET on a module opens its tab): General (the input) plus one tab per module
/// (Beat-o-Matic, BandsDance, Annalisa: the BPM tag, the MIDI strip, the Energy module), each headed by a small picture of its module drawn from the current
/// settings (`ModuleHeader`).
struct SettingsView: View {
    @AppStorage("settingsPane") private var pane = "general"

    var body: some View {
        TabView(selection: $pane) {
            GeneralPane().tabItem { Label("General", systemImage: "gearshape") }.tag("general")
            BPMPane().tabItem { Label("Beat-o-Matic", systemImage: "metronome") }.tag("bpm")
            StripPane().tabItem { Label("BandsDance", systemImage: "figure.dance") }.tag("midi")
            EnergyPane().tabItem { Label("Annalisa", systemImage: "brain.head.profile") }.tag("energy")
        }
        .frame(width: 460)
    }
}

private struct GeneralPane: View {
    var body: some View {
        Form {
            Section {
                LabeledContent("Input") { InputPicker() }
                InputStatus()
            } footer: {
                Text("System Audio hears everything the Mac plays; a device listens to a mic or interface.")
                    .foregroundStyle(.secondary)
            }
        }
        .settingsPaneForm()
    }
}

private struct BPMPane: View {
    @Environment(EngineModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            ModuleHeader(module: .bpm, title: "Beat-o-Matic", detail: "Finds the tempo and shares it over Ableton Link.",
                         power: $model.bpmEnabled)
            Form {
                Section {
                    Picker("Genre", selection: $model.genre) {
                        ForEach(EngineModel.genres.indices, id: \.self) { i in
                            Text(EngineModel.genres[i].name).tag(i)
                        }
                    }
                } footer: {
                    Text(genreFooter).foregroundStyle(.secondary)
                }
                .disabled(!model.bpmEnabled)
                Section {
                    Stepper(value: $model.beatOffsetMs, in: EngineModel.beatOffsetRange) {
                        LabeledContent("Beat offset", value: "\(model.beatOffsetMs) ms")
                    }
                } footer: {
                    Text("Sends beats earlier to make up for video latency. Saved per input.")
                        .foregroundStyle(.secondary)
                }
                .disabled(!model.bpmEnabled)
            }
            .settingsPaneForm()
        }
    }

    private var genreFooter: String {
        if !model.bpmEnabled { return "BPM detection is off." }
        if model.genre > 0 {
            return "Prefers about \(Int(EngineModel.genres[model.genre].center)) BPM."
        }
        return "Helps avoid half and double tempo."
    }
}

private struct StripPane: View {
    @Environment(EngineModel.self) private var model
    static let decays: [(beats: Double, label: String)] = [
        (1.0 / 16, "1/16 beat"), (1.0 / 8, "1/8 beat"), (1.0 / 4, "1/4 beat"), (1.0 / 2, "1/2 beat"), (1, "1 beat"),
        (Double(VC_TRIGGER_DECAY_FOLLOW), "Follow the sound"),
    ]

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            ModuleHeader(module: .midi, title: "BandsDance", detail: "A CC for every hit in the music.",
                         power: $model.stripEnabled)
            Form {
                Section {
                    MIDIOutPicker(live: $model.triggersSending)
                    ChannelPicker(channel: $model.stripChannel)
                } footer: {
                    Text(model.triggersSending
                         ? "Every hit goes out."
                         : "Nothing goes out by itself: click a band on BandsDance to send just its CC, for MIDI learn.")
                        .foregroundStyle(.secondary)
                }
                Section {
                    Picker("Trigger bands", selection: $model.triggerBands) {
                        ForEach(Int(VC_MIN_TRIGGER_BANDS)...Int(VC_MAX_TRIGGER_BANDS), id: \.self) { n in
                            Text(n == Int(VC_INSTRUMENT_BANDS) ? "3: kick, snare, hat (CC 1–3)" : "\(n) frequency bands (CC 1–\(n))").tag(n)
                        }
                    }
                    Picker("Trigger decay", selection: $model.triggerDecay) {
                        ForEach(Self.decays, id: \.beats) { Text($0.label).tag($0.beats) }
                    }
                } footer: {
                    Text("3 bands follow the drums; other counts split the sound by frequency. Decay sets how fast a hit falls back to zero.")
                        .foregroundStyle(.secondary)
                }
                .disabled(!model.stripEnabled)
            }
            .settingsPaneForm()
        }
    }
}

private struct EnergyPane: View {
    @Environment(EngineModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            ModuleHeader(module: .energy, title: "Annalisa", detail: "Six slow descriptors of the music.",
                         power: $model.energyEnabled)
            Form {
                Section {
                    MIDIOutPicker(live: $model.energySending)
                    ChannelPicker(channel: $model.energyChannel)
                } footer: {
                    Text(model.energySending
                         ? "The descriptors go out continuously."
                         : "Nothing goes out by itself: click a row on the module to send just its CC, for MIDI learn.")
                        .foregroundStyle(.secondary)
                }
                Section("Descriptors") {
                    ForEach(EngineModel.descriptorNames.indices, id: \.self) { d in
                        Toggle(isOn: Binding(get: { model.descriptorsEnabled[d] },
                                             set: { model.setDescriptor(d, enabled: $0) })) {
                            Text(EngineModel.descriptorNames[d])
                            Text("CC \(MIDIReference.descriptorCC(d)) · \(MIDIReference.descriptorSummaries[d])")
                        }
                    }
                }
                .disabled(!model.energyEnabled)
            }
            .settingsPaneForm()
        }
    }
}

/// Live (the module's analysed values go out) or Learn (nothing goes out by itself; clicking a band or row on the
/// module sends just that CC once, for Resolume's MIDI learn). The same switch as the module's MIDI OUT plug: Live = plugged in.
private struct MIDIOutPicker: View {
    @Binding var live: Bool

    var body: some View {
        Picker("MIDI out", selection: $live) {
            Text("Live").tag(true)
            Text("Learn").tag(false)
        }
        .pickerStyle(.segmented)
    }
}

/// A module's MIDI channel (1–16). Resolume's mappings are per channel, so changing it means mapping again.
private struct ChannelPicker: View {
    @Binding var channel: Int

    var body: some View {
        Picker("MIDI channel", selection: $channel) {
            ForEach(1...16, id: \.self) { Text("\($0)").tag($0) }
        }
    }
}

/// The top of a module's Settings tab: that module, small and upright, drawn from the current settings (band count,
/// on/off; no plugs or cables) with fixed sample levels, not live audio; decoration only (not clickable, hidden from
/// VoiceOver). Beside it the module's name, what it does, and its power switch.
private struct ModuleHeader: View {
    @Environment(EngineModel.self) private var model
    var module: Module
    var title: String
    var detail: String
    /// The module's on/off, the same as its control on the keychain (rocker, slide, power key).
    @Binding var power: Bool

    /// Module units to points: the modules are drawn at about 60 % of their keychain size (without `-keychainZoom`,
    /// which enlarges only the keychain).
    private static let zoom: CGFloat = 0.6 / HardwareScale.zoom

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            picture
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.title3.weight(.semibold))
                Text(detail).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                // The standard switch at its regular size; no visible label (the header says which module).
                Toggle(isOn: $power) { Text(verbatim: "\(title) power") }
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .padding(.top, 8)
            }
            Spacer(minLength: 0)
        }
        // The text centres on the module itself; the room for its drop shadow goes around the whole header.
        .padding(EdgeInsets(top: 22, leading: 20, bottom: 16, trailing: 12))
    }

    @ViewBuilder private var picture: some View {
        switch module {
        case .bpm:
            BPMTagView(state: SampleData.tag(phase: 0.2, enabled: model.bpmEnabled),
                       isFront: true, onRocker: {}, onSet: {}, zoom: Self.zoom, showsCable: false)
        case .midi:
            MIDIStripView(bands: model.triggerBands, levels: SampleData.levels, isOn: model.stripEnabled, channel: model.stripChannel,
                          isFront: true, onSlide: {}, onSet: {}, outPlugged: model.stripPlugged, showsMIDIOut: false, zoom: Self.zoom)
        case .energy, .charms:
            EnergyModuleView(values: SampleData.values, enabled: model.descriptorsEnabled, isOn: model.energyEnabled,
                             output: model.energyOutput, channel: model.energyChannel, outPlugged: model.energyPlugged, showsMIDIOut: false,
                             spectrum: model.energyEnabled ? SampleData.spectrum : Array(repeating: 0, count: 24),
                             isFront: true, onPower: {}, onSet: {}, onToggle: { _ in }, zoom: Self.zoom)
        }
    }
}

extension View {
    /// A grouped form as tall as its content, so the Settings window fits each pane.
    func settingsPaneForm() -> some View {
        formStyle(.grouped)
            .scrollDisabled(true)
            .fixedSize(horizontal: false, vertical: true)
    }
}
