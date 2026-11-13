// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// Removing or adding a MIDI strip channel module, as motion (≈0.6 s). The strip hangs by the keyring
/// hole in its right end cap, so the right cap stays put and everything else moves:
/// - **Remove module j:** it goes dark and falls out of the strip with gravity (straight down in the world,
///   accelerating, tumbling a little) and out of the panel; meanwhile the modules left of it and the left cap
///   slide right and close the gap with a small magnetic snap.
/// - **Add:** the left part slides left (as if the end cap were pulled out to the right), opening a gap
///   before the right cap; the new module drops into it and snaps in.
/// Positions are in channel widths from the right cap's left edge (a module at x occupies x…x + 1, so at
/// rest module k of n sits at k − n); lifts in 1× units (negative = up); a fall in 1× units straight down
/// in the world (`fallOffset` turns it into the strip's own, rotated coordinates).
public struct StripEdit: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// Remove module j (0 = left).
        case remove(Int)
        /// Add a module at the right end.
        case add
    }

    public var from: Int
    public var kind: Kind

    public init(from: Int, kind: Kind) { self.from = from; self.kind = kind }

    public var to: Int {
        switch kind {
        case .remove: from - 1
        case .add: from + 1
        }
    }

    /// One channel module in the picture.
    public struct Slot: Equatable, Sendable {
        /// Its index among `from` modules (nil for the one being added) and among `to` (nil for the one removed).
        public var old: Int?
        public var new: Int?
        public var x: Double
        public var lift: Double
        public var opacity: Double
        /// Falling out (remove): distance straight down in the world, and the tumble in degrees.
        public var fall: Double = 0
        public var spin: Double = 0
    }

    public struct Pose: Equatable, Sendable {
        public var slots: [Slot]
        /// Where the left cap's right edge is (channel widths from the right cap's left edge, ≤ 0).
        public var leftEdge: Double
        /// The modules have snapped together in their new arrangement: show the new band count's ranges.
        public var snapped: Bool
    }

    /// Where an added module drops in from (1× units above its slot).
    public static let lift = 34.0
    /// Remove: gravity for the fall (1× units/s²; ≈ 330 units, beyond any panel, by the end), its tumble, and
    /// the gap closing once the module has mostly cleared the strip.
    public static let gravity = 1800.0, tumble = 24.0, closeStart = 0.24, closeTime = 0.36
    /// Add: the end opening, then the new module dropping in.
    public static let openTime = 0.28, dropStart = 0.2, dropTime = 0.34

    public var duration: Double {
        switch kind {
        case .remove: Self.closeStart + Self.closeTime
        case .add: Self.dropStart + Self.dropTime
        }
    }

    /// After the snap (`t` seconds after it): each module of the new count as it re-tunes (`StripPowerOn.retune`) and, after
    /// an add, the new module's own start-up (`StripPowerOn.moduleBoot`); nil once everything shows its live state.
    public func settle(at t: Double) -> [StripPowerOn.Module]? {
        let n = to
        var any = false
        let frame: [StripPowerOn.Module] = (0..<n).map { i in
            let m: StripPowerOn.Module?
            switch kind {
            case .add where i == n - 1: m = StripPowerOn.moduleBoot(elapsed: t)
            case .add: m = StripPowerOn.retune(i, bands: n, elapsed: t, ccChanged: false)
            case .remove(let j): m = StripPowerOn.retune(i, bands: n, elapsed: t, ccChanged: i >= j)
            }
            if m != nil { any = true }
            return m ?? .live
        }
        return any ? frame : nil
    }

    /// The strip at rest with `bands` modules.
    public static func rest(bands: Int) -> Pose {
        Pose(slots: (0..<bands).map { Slot(old: $0, new: $0, x: Double($0 - bands), lift: 0, opacity: 1) },
             leftEdge: Double(-bands), snapped: true)
    }

    public func pose(at t: Double) -> Pose {
        if t >= duration { return Self.rest(bands: to) }
        let n = from
        switch kind {
        case .remove(let j):
            let close = Self.snap(clamp((t - Self.closeStart) / Self.closeTime))
            var slots: [Slot] = []
            for k in 0..<n {
                let rest = Double(k - n)
                if k == j {
                    // Free fall from rest; the tumble builds up with it.
                    let p = t / duration
                    slots.append(Slot(old: k, new: nil, x: rest, lift: 0, opacity: 1,
                                      fall: Self.gravity * t * t / 2, spin: Self.tumble * p * p))
                } else {
                    slots.append(Slot(old: k, new: k < j ? k : k - 1, x: k < j ? rest + close : rest, lift: 0, opacity: 1))
                }
            }
            return Pose(slots: slots, leftEdge: Double(-n) + close, snapped: false)
        case .add:
            let open = Self.easeInOut(clamp(t / Self.openTime))
            let d = clamp((t - Self.dropStart) / Self.dropTime)
            var slots = (0..<n).map { k in Slot(old: k, new: k, x: Double(k - n) - open, lift: 0, opacity: 1) }
            slots.append(Slot(old: nil, new: n, x: -1, lift: -Self.lift * (1 - Self.snap(d)), opacity: clamp(d / 0.35)))
            return Pose(slots: slots, leftEdge: Double(-n) - open, snapped: false)
        }
    }

    /// How far below the hole (straight down in the world, same units) the lowest corner of `rect` (relative to the
    /// hole, unturned) is when the strip hangs turned `hangDegrees`.
    public static func lowestBelowHole(_ rect: CGRect, hangDegrees: Double) -> Double {
        let a = hangDegrees * .pi / 180
        let corners = [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
                       CGPoint(x: rect.minX, y: rect.maxY), CGPoint(x: rect.maxX, y: rect.maxY)]
        return corners.map { Double($0.x) * sin(a) + Double($0.y) * cos(a) }.max()!
    }

    /// Opacity of a falling module: 1 until it is `fadeOver` from having fallen `clearance` (when its lowest point would
    /// reach the panel's edge), then down to 0 by then, so the panel never cuts it off.
    public static func fallOpacity(fall: Double, clearance: Double, fadeOver: Double) -> Double {
        let p = (fall - (clearance - fadeOver)) / fadeOver
        return 1 - min(1, max(0, p))
    }

    /// A fall straight down in the world as an offset in the strip's own coordinates, for a strip drawn turned
    /// `degrees` (SwiftUI's rotation: clockwise, y down): (f sin θ, f cos θ).
    public static func fallOffset(_ fall: Double, hangDegrees degrees: Double) -> (x: Double, y: Double) {
        let a = degrees * .pi / 180
        return (fall * sin(a), fall * cos(a))
    }
    static func easeInOut(_ p: Double) -> Double { p < 0.5 ? 4 * p * p * p : 1 - pow(-2 * p + 2, 3) / 2 }
    /// Into place with a small magnetic overshoot (≈2 %), settled at 1.
    static func snap(_ p: Double) -> Double {
        guard p < 1 else { return 1 }
        let s = 0.7
        let q = p - 1
        return 1 + (s + 1) * q * q * q + s * q * q
    }

    private func clamp(_ x: Double) -> Double { min(1, max(0, x)) }
}
