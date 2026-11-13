// SPDX-License-Identifier: GPL-3.0-or-later
import AVFoundation
import AppKit
import CoreAudio
import VChainEngine
import Observation

/// Where the audio comes from.
enum InputSource: Hashable {
    case systemAudio
    case device(name: String)
    case file(path: String)  // developer input (-testAudioFile)

    var title: String {
        switch self {
        case .systemAudio: "System Audio"
        case .device(let name): name
        case .file(let path): (path as NSString).lastPathComponent
        }
    }

    /// Stored as "system" or "device:<name>" (device IDs change between boots; names don't).
    var storageValue: String? {
        switch self {
        case .systemAudio: "system"
        case .device(let name): "device:" + name
        case .file: nil
        }
    }

    init(storageValue: String) {
        self = storageValue.hasPrefix("device:") ? .device(name: String(storageValue.dropFirst(7))) : .systemAudio
    }
}

struct InputDevice: Hashable, Identifiable {
    let id: UInt32
    let name: String
}

/// The engine's input (`EngineModel.input`): which source is selected and remembered, the devices to choose from
/// (watched for plugging and unplugging), the microphone permission, and the input's health, polled at 4 Hz (not
/// tied to the display-rate timeline, which stops while the display sleeps) so problems always show. Restarts a
/// System Audio capture that the display's sleep stopped.
@MainActor @Observable
final class InputController {
    private(set) var devices: [InputDevice] = []
    private(set) var source: InputSource = .systemAudio
    private(set) var isSwitching = false
    private(set) var microphoneDenied = false
    private(set) var health = InputHealth.idle
    /// Called on every selection, right after `source` changed (the model loads that input's beat offset).
    @ObservationIgnored var onSelect: (InputSource) -> Void = { _ in }

    @ObservationIgnored private let handle: EngineHandle
    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored private var lastAutoRetry = Date.distantPast
    @ObservationIgnored private var screensAsleep = false

    init(handle: EngineHandle) {
        self.handle = handle
    }

    /// Lists the devices and starts watching them, the input's health and the displays' sleep.
    func watch() {
        refreshDevices()
        watchDevices()
        Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let health = DebugLaunch.inputProblem.map { InputHealth(Int32($0)) } ?? InputHealth(self.handle.snapshot().inputState)
                if health != self.health { self.health = health }
                self.retryStoppedSystemAudio()
            }
        }
        // The display waking: restart a capture its sleep stopped right away instead of at the next retry.
        // While it sleeps, retrying would only start a stream that stops again.
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.screensAsleep = true }
        }
        center.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.screensAsleep = false
                self?.retryStoppedSystemAudio(now: true)
            }
        }
    }

    /// System Audio stops when the display sleeps (ScreenCaptureKit) and never resumes by itself: the engine
    /// reports it as failed, and this restarts it every 5 s (and on wake) until it runs again.
    private func retryStoppedSystemAudio(now: Bool = false) {
        guard source == .systemAudio, health == .failed, !screensAsleep, !isSwitching, DebugLaunch.inputProblem == nil,
              now || Date().timeIntervalSince(lastAutoRetry) >= 5 else { return }
        lastAutoRetry = Date()
        retry()
    }

    /// Starts the remembered input (or the developer test file).
    func start() {
        if let path = DebugLaunch.testAudioFile {
            select(.file(path: path))
            return
        }
        var source = InputSource(storageValue: defaults.string(forKey: SettingsKey.input.rawValue) ?? "system")
        if case .device(let name) = source, !devices.contains(where: { $0.name == name }) {
            source = .systemAudio  // remembered device isn't connected
        }
        select(source, remember: false)
    }

    func select(_ source: InputSource, remember: Bool = true) {
        if remember, let value = source.storageValue { defaults.set(value, forKey: SettingsKey.input.rawValue) }
        self.source = source
        onSelect(source)
        isSwitching = true
        microphoneDenied = false
        let handle = handle
        Task {
            if case .device = source, !(await Self.microphoneAllowed()) {
                microphoneDenied = true
            }
            let deviceID = devices.first { if case .device(let n) = source { $0.name == n } else { false } }?.id
            _ = await Task.detached { () -> Int32 in
                switch source {
                case .systemAudio: vc_engine_select_system_audio(handle.pointer)
                case .device: vc_engine_select_device(handle.pointer, deviceID ?? 0)
                case .file(let path): vc_engine_select_file(handle.pointer, path)
                }
            }.value
            // A newer selection may have started meanwhile.
            guard source == self.source else { return }
            isSwitching = false
        }
    }

    /// Retries the current input (after granting permission, or replugging a device).
    func retry() {
        select(source, remember: false)
    }

    private static func microphoneAllowed() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: true
        case .notDetermined: await AVCaptureDevice.requestAccess(for: .audio)
        default: false
        }
    }

    func refreshDevices() {
        var buffer = [VCDevice](repeating: VCDevice(), count: 64)
        let count = Int(vc_list_input_devices(&buffer, Int32(buffer.count)))
        devices = buffer.prefix(count).map { d in
            var d = d
            let name = withUnsafeBytes(of: &d.name) { String(cString: $0.bindMemory(to: CChar.self).baseAddress!) }
            return InputDevice(id: d.id, name: name)
        }
        // The chosen device came back (replugged): pick it up again.
        if case .device(let name) = source, let device = devices.first(where: { $0.name == name }),
           handle.snapshot().deviceId != device.id || handle.snapshot().inputState != Int32(VC_INPUT_STATE_RUNNING.rawValue) {
            select(source, remember: false)
        }
    }

    var deviceMissing: Bool {
        if case .device(let name) = source { return !devices.contains { $0.name == name } }
        return false
    }

    private func watchDevices() {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.refreshDevices() }
        }
    }
}
