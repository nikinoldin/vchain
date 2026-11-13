// SPDX-License-Identifier: GPL-3.0-or-later
import VChainKit

func runKeychainStateChecks() {
    Checks.run("Keychain state") {
        var s = KeychainState()
        check(s.front == .bpm, "bpm starts in front")
        check(s.tap(on: .midi) == .broughtToFront, "tap on back module brings it forward")
        check(s.front == .midi, "midi now in front")
        check(s.tap(on: .midi) == .passToControl, "second tap passes to the control")
        check(s.front == .midi, "front unchanged by control tap")
        for front in Module.allCases {
            var k = KeychainState()
            k.front = front
            let z = k.zOrder()
            check(z.last == front, "\(front): front module is last")
            check(z.count == Module.allCases.count && Set(z).count == z.count, "\(front): each item once")
        }
        var k = KeychainState()
        k.front = .midi
        check(k.zOrder() == [.energy, .charms, .bpm, .midi], "midi front: energy, charms, bpm, midi")
        k.front = .bpm
        check(k.zOrder() == [.energy, .midi, .charms, .bpm], "bpm front: energy, midi, charms, bpm")
        check(k.tap(on: .charms) == .broughtToFront && k.front == .charms, "a tap on the charms brings them to the front")
        check(k.zOrder() == [.energy, .midi, .bpm, .charms], "charms front: energy, midi, bpm, charms")
    }

    Checks.run("Module names") {
        check(Set(Module.allCases.map(\.name)).count == Module.allCases.count, "every module has its own name")
        check(Module.allCases.allSatisfy { Module(name: $0.name) == $0 }, "names read back as the same module")
        check(Module(name: "midi") == .midi && Module(name: "strip") == nil, "-keychainFront midi; unknown names: nil")
    }
}
