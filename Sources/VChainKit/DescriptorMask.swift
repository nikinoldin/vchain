// SPDX-License-Identifier: GPL-3.0-or-later
/// Which descriptors the engine runs: the Energy module switch gates the user's per-descriptor choices
/// without overwriting them.
public enum DescriptorMask {
    /// What to send to the engine for each descriptor: all off while Energy is off, else the choices.
    public static func engineMask(energyEnabled: Bool, chosen: [Bool]) -> [Bool] {
        energyEnabled ? chosen : chosen.map { _ in false }
    }
}
