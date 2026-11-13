// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// A hanging module: a damped spring on its angle (degrees) plus a vertical drop offset (points at 1x).
public struct Pendulum: Sendable {
    public var angle: Double
    public var velocity: Double
    public var drop: Double
    public var dropVelocity: Double
    public let rest: Double
    /// Damping ratio of the swing; long modules damp harder so their far end stops sooner.
    public let damping: Double
    /// Seconds per swing; the modules all use `Pendulum.period`, the bead strands their own.
    public let period: Double

    public static let period = 0.5
    public static let damping = 0.25
    /// The MIDI strip is ~2.5× as long as the BPM tag: the same tail angle moves its far end 2.5× as far.
    public static let longDamping = 0.4
    public static let dropPeriod = 0.16
    public static let dropDamping = 0.38
    /// Points at 1x; callers scale with 1.5.
    public static let dropStart = -34.0
    /// Opening drops the keychain in mid-swing: every module starts this far (degrees) out to the right
    /// (counterclockwise, so its free end is right of rest) and first swings right to left.
    /// The panel leaves room for 12° either way (KeychainLayout.swingMargin).
    public static let releaseSwing = -11.0
    /// Longest integration substep (s): long frames are split so stepping stays stable.
    static let maxSubstep = 0.004

    public init(rest: Double, damping: Double = Pendulum.damping, period: Double = Pendulum.period) {
        self.rest = rest
        self.damping = damping
        self.period = period
        angle = rest
        velocity = 0
        drop = 0
        dropVelocity = 0
    }

    public static func restAngles() -> (bpm: Double, midi: Double, energy: Double) {
        (bpm: 2.0, midi: -38.0, energy: 45.0)
    }

    /// Let go of the module: dropping in from above, swung `releaseSwing` degrees out to the right.
    public mutating func release() {
        angle = rest + Self.releaseSwing
        velocity = 0
        drop = Self.dropStart
        dropVelocity = 0
    }

    /// Angular kick in degrees per second.
    public mutating func push(_ dv: Double) {
        velocity += dv
    }

    public mutating func step(_ dt: Double) {
        let substeps = max(1, Int((dt / Self.maxSubstep).rounded(.up)))
        let h = dt / Double(substeps)
        let w = 2 * Double.pi / period
        let wd = 2 * Double.pi / Self.dropPeriod
        for _ in 0..<substeps {
            velocity += (-w * w * (angle - rest) - 2 * damping * w * velocity) * h
            angle += velocity * h
            dropVelocity += (-wd * wd * drop - 2 * Self.dropDamping * wd * dropVelocity) * h
            drop += dropVelocity * h
        }
    }

    /// Reduce Motion: skip the swing and the drop.
    public mutating func settleImmediately() {
        angle = rest
        velocity = 0
        drop = 0
        dropVelocity = 0
    }
}
