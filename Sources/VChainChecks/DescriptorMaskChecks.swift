// SPDX-License-Identifier: GPL-3.0-or-later
import VChainKit

func runDescriptorMaskChecks() {
    Checks.run("descriptor mask") {
        let chosen = [true, false, true]
        check(DescriptorMask.engineMask(energyEnabled: true, chosen: chosen) == chosen, "on restores choices")
        check(DescriptorMask.engineMask(energyEnabled: false, chosen: chosen) == [false, false, false], "off disables all")
    }
}
