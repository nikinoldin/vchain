// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// What hangs on the keychain: the three modules and the bead charms (decoration, no controls).
public enum Module: CaseIterable, Sendable { case bpm, midi, energy, charms }

extension Module {
    /// Its name in settings and launch arguments (`-keychainFront bpm|midi|energy|charms`).
    public var name: String {
        switch self {
        case .bpm: "bpm"
        case .midi: "midi"
        case .energy: "energy"
        case .charms: "charms"
        }
    }

    public init?(name: String) {
        guard let module = Module.allCases.first(where: { $0.name == name }) else { return nil }
        self = module
    }
}

public enum TapResult: Sendable { case broughtToFront, passToControl }

public struct KeychainState: Sendable {
    public var front: Module = .bpm

    public init() {}

    /// Controls respond only while their module is in front: a tap on a back module just brings it forward.
    public mutating func tap(on m: Module) -> TapResult {
        if m == front { return .passToControl }
        front = m
        return .broughtToFront
    }

    /// Back to front: the others in fixed order (energy, midi, charms, bpm), then the front module.
    /// The charms sit over the Energy module and the strip's right end cap, under the BPM tag.
    public func zOrder() -> [Module] {
        [Module.energy, .midi, .charms, .bpm].filter { $0 != front } + [front]
    }
}
