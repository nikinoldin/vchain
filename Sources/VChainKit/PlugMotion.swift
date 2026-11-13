// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// Hovering a MIDI OUT plug (a hover affordance; unplugging itself is instant): while the pointer is over a plugged
/// plug it eases a little out of its socket, showing a sliver of the chrome pin, and eases back when the pointer leaves.
/// `peek` 0 = fully in, 1 = out by `peekUnits`.
public enum PlugMotion {
    /// How long the ease takes, and how far the plug comes out (1× units).
    public static let hoverTime = 0.12, peekUnits = 2.5

    /// The peek `elapsed` seconds after the pointer entered (`hovered`) or left, starting from `from`.
    public static func peek(from: Double, hovered: Bool, elapsed t: Double) -> Double {
        let target = hovered ? 1.0 : 0.0
        let p = min(1, max(0, t / hoverTime))
        let e = p * p * (3 - 2 * p)
        return from + (target - from) * e
    }
}
