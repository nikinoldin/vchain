// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import SwiftUI

/// Input picker and its problem status (Settings › General).
struct InputPicker: View {
    @Environment(EngineModel.self) private var model

    var body: some View {
        let binding = Binding<InputSource>(get: { model.input.source }, set: { model.input.select($0) })
        Picker("Input", selection: binding) {
            Label("System Audio", systemImage: "macbook").tag(InputSource.systemAudio)
            if !model.input.devices.isEmpty { Divider() }
            ForEach(model.input.devices) { device in
                Label(device.name, systemImage: "mic").tag(InputSource.device(name: device.name))
            }
            if case .device(let name) = model.input.source, model.input.deviceMissing {
                Text("\(name) (Not Connected)").tag(model.input.source)
            }
            if case .file = model.input.source {
                Divider()
                Text("Test File: \(model.input.source.title)").tag(model.input.source)
            }
        }
        .labelsHidden()
        .frame(minWidth: 120, maxWidth: 200)
    }
}

/// Only shown when the input needs attention: starting, permission missing, failed, unplugged, or silent.
struct InputStatus: View {
    @Environment(EngineModel.self) private var model

    var body: some View {
        Group {
            if let problem = InputProblem.current(model) {
                VStack(alignment: .leading, spacing: 6) {
                    // Orange only on the symbol: orange text is ~2.2:1 on a light window.
                    Label {
                        Text(problem.message)
                    } icon: {
                        Image(systemName: problem.symbol)
                            .foregroundStyle(problem.isWarning ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                    }
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                    if let settingsURL = problem.settingsURL {
                        HStack {
                            Button("Open Privacy Settings…") { NSWorkspace.shared.open(settingsURL) }
                            Button("Try Again") { model.input.retry() }
                        }
                        .controlSize(.small)
                    } else if problem.canRetry {
                        Button("Try Again") { model.input.retry() }
                            .controlSize(.small)
                    }
                }
            }
        }
    }
}

/// What's wrong with the input right now, and how to fix it (Settings › General and the keychain's
/// right-click menu). "Starting…" is a status, not a warning.
struct InputProblem {
    var message: String
    var symbol = "exclamationmark.triangle.fill"
    var settingsURL: URL?
    var canRetry = false
    var isWarning: Bool { symbol == "exclamationmark.triangle.fill" }

    @MainActor static func current(_ model: EngineModel) -> InputProblem? {
        let privacy = "x-apple.systempreferences:com.apple.preference.security?"
        if model.input.isSwitching {
            return InputProblem(message: "Starting \(model.input.source.title)…", symbol: "hourglass")
        }
        if model.input.deviceMissing {
            return InputProblem(message: "\(model.input.source.title) isn’t connected. vChain switches back when you plug it in.")
        }
        if model.input.microphoneDenied {
            return InputProblem(message: "vChain can’t hear this input. Allow Microphone access in Privacy & Security.",
                                settingsURL: URL(string: privacy + "Privacy_Microphone"))
        }
        switch model.input.health {
        case .noPermission:
            return InputProblem(message: "To hear System Audio, allow vChain under Screen & System Audio Recording.",
                                settingsURL: URL(string: privacy + "Privacy_ScreenCapture"))
        case .failed:
            return InputProblem(message: "\(model.input.source.title) stopped or couldn’t start.", canRetry: true)
        default:
            return nil
        }
    }
}
