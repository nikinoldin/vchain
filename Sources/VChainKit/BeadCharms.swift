// SPDX-License-Identifier: GPL-3.0-or-later
import CoreGraphics
import Foundation

/// The three bead charms (decoration only): a small gold jump ring threaded on the split
/// ring at the ring point, carrying three strands of beads on stiff gold eye pins. Each strand swings
/// as one rigid pendulum about its top loop. Bead units are 1× points as measured from the photos
/// (1 mm ≈ 0.9 pt, a bead 6–9 pt next to the 100 pt BPM tag); the keychain draws them × `displayScale`
/// (and × 1.5 like everything).
public enum BeadCharms {
    public enum Strand: Int, CaseIterable, Sendable { case tulip, mushroom, millefiori }

    /// One bead, top to bottom on the pin. Each kind draws its own way (BeadCharmsView).
    public enum Bead: Equatable, Sendable {
        // Tulip strand
        case redRound, daisy, heartDisc, pearl, ribbedCube, tulip, leaf
        // Mushroom strand
        case roseQuartz, carnelian, aqua, lilacBarrel, jade, kyanite, mushroomHeart
        /// Flat round glass disc, pattern 0…9 (top to bottom on the strand).
        case millefiori(Int)

        /// Width × height in 1× points, as it sits on the pin (height along the wire).
        public var size: CGSize {
            switch self {
            case .redRound: CGSize(width: 7.6, height: 7.6)
            case .daisy: CGSize(width: 9, height: 8.6)
            case .heartDisc: CGSize(width: 7.2, height: 7.2)
            case .pearl: CGSize(width: 7.4, height: 7.4)
            case .ribbedCube: CGSize(width: 8, height: 8.6)
            case .tulip: CGSize(width: 7.6, height: 8.8)
            case .leaf: CGSize(width: 12.5, height: 5.6)
            case .roseQuartz, .aqua, .jade: CGSize(width: 7.4, height: 7.4)
            case .carnelian: CGSize(width: 7.8, height: 7.8)
            case .lilacBarrel: CGSize(width: 7.4, height: 6.2)
            case .kyanite: CGSize(width: 7, height: 7)
            case .mushroomHeart: CGSize(width: 15.5, height: 14.5)
            case .millefiori: CGSize(width: 5.9, height: 5.6)
            }
        }
    }

    public static func beads(_ s: Strand) -> [Bead] {
        switch s {
        case .tulip: [.redRound, .daisy, .heartDisc, .pearl, .ribbedCube, .tulip, .leaf]
        case .mushroom: [.roseQuartz, .carnelian, .aqua, .lilacBarrel, .jade, .kyanite, .mushroomHeart]
        case .millefiori: (0..<10).map { .millefiori($0) }
        }
    }

    // MARK: Wire

    /// The eye pin's loops: outer radius and wire thickness.
    public static let loopRadius: CGFloat = 1.25
    public static let wire: CGFloat = 0.45
    /// Bare wire between the top loop and the first bead.
    public static let neck: CGFloat = 1.0
    /// Bare wire between two beads (they sit loose on the pin, so the gold shows a little).
    public static let gap: CGFloat = 0.35

    /// A bead placed on its strand: centre on the wire (x = 0), the top loop's centre is the origin.
    public struct Placed: Sendable {
        public let bead: Bead
        public let center: CGPoint
        public let size: CGSize
    }

    /// The beads stacked from just under the top loop down, `gap` apart.
    public static func stack(_ s: Strand) -> [Placed] {
        var y = loopRadius + neck
        return beads(s).map { b in
            let h = b.size.height
            defer { y += h + gap }
            return Placed(bead: b, center: CGPoint(x: 0, y: y + h / 2), size: b.size)
        }
    }

    /// Centre of the bottom loop (the pin's end turned into a loop under the last bead).
    public static func bottomLoop(_ s: Strand) -> CGPoint {
        let last = stack(s).last!
        return CGPoint(x: 0, y: last.center.y + last.size.height / 2 + neck * 0.6 + loopRadius)
    }

    /// From the pivot (top loop centre) to the bottom loop's lower edge.
    public static func length(_ s: Strand) -> CGFloat { bottomLoop(s).y + loopRadius }

    /// The widest bead.
    public static func width(_ s: Strand) -> CGFloat { beads(s).map(\.size.width).max()! }

    /// Everything the strand draws (beads, loops, a little shadow room), relative to its pivot.
    public static func bounds(_ s: Strand) -> CGRect {
        let w = width(s) + 3
        return CGRect(x: -w / 2, y: -loopRadius - 1, width: w, height: length(s) + loopRadius + 3)
    }

    // MARK: Jump ring

    /// The jump ring's radius (to the wire's centre), in bead units like the strands.
    public static let jumpRadius: CGFloat = 3.1

    /// Where each strand's top loop hangs on the jump ring, relative to the jump ring's centre before
    /// it swings (bead units): spread over its bottom arc, tulip on the left, millefiori on the right.
    public static func pivot(_ s: Strand) -> CGPoint {
        let spread: Double = switch s { case .tulip: 26; case .mushroom: 0; case .millefiori: -26 }
        let r = jumpRadius + loopRadius - wire * 1.5   // the two wires interlock
        let a = spread * Double.pi / 180
        return CGPoint(x: -r * CGFloat(sin(a)), y: r * CGFloat(cos(a)))
    }

    /// The jump ring's centre below the ring point, in bead units, when it hangs straight on the split
    /// ring: the split ring passes through it near its top.
    public static let jumpDrop: CGFloat = 2.2

    /// An optional short gold cable chain between the split ring and the jump ring. Keychain 1× points
    /// (not scaled with the beads), hanging straight down from the ring point: links alternate face on /
    /// edge on, the first one face on and threaded on the split ring like a module's hole.
    public enum Chain {
        /// One link's outer length and (face on) width, and its wire.
        public static let linkLength: CGFloat = 6.4
        public static let linkWidth: CGFloat = 4.2
        public static let linkWire: CGFloat = 1.0
        /// Link to link: each hangs in the one above, wire touching wire.
        public static var pitch: CGFloat { linkLength - 2 * linkWire }
        /// The split ring's winding the top link hangs on (half its thickness above the ring point).
        static let ringWire: CGFloat = 1.6

        /// Where the top link's inside rests when it hangs on the split ring (its winding's top).
        public static let ringTop: CGFloat = -ringWire / 2

        /// Centre of link `i` (0 = the top one) below the ring point; the top link's inside rests at `top`.
        public static func linkCenter(_ i: Int, top: CGFloat = ringTop) -> CGFloat {
            top + linkLength / 2 - linkWire + CGFloat(i) * pitch
        }

        public static func isFaceOn(_ i: Int) -> Bool { i.isMultiple(of: 2) }

        /// The inside of the last of `links` links' bottom end, where the jump ring hangs.
        public static func end(links: Int, top: CGFloat = ringTop) -> CGFloat {
            linkCenter(links - 1, top: top) + linkLength / 2 - linkWire
        }
    }

    /// A gold lobster clasp with a swivel, hooked on the split ring: the claw (a round head with a teardrop opening
    /// and the spring gate down its left, a solid body below with the rivet and the gate's lever sticking out right),
    /// a narrow neck, the swivel's flange and a D-ring whose rounded bottom the chain or the jump ring hangs in. Keychain 1× points, hanging straight down from the ring point.
    public enum Clasp {
        /// Its size against the beads: about four beads long, like a real swivel clasp on bead charms.
        public static let size: CGFloat = 1.8
        /// The claw's band (stamped metal around the opening) and its outer size.
        public static let band: CGFloat = 1.15 * size
        public static let width: CGFloat = 9.6 * size
        public static let clawLength: CGFloat = 16 * size
        /// The claw's outer top: its opening rests on the split ring's winding.
        public static let top: CGFloat = Chain.ringTop - band
        public static var clawBase: CGFloat { top + clawLength }
        public static let collar = CGSize(width: 3.2 * size, height: 1.4 * size)
        public static let barrel = CGSize(width: 7 * size, height: 1.8 * size)
        public static var barrelTop: CGFloat { clawBase + collar.height }
        /// The D-ring: flat top on the swivel, rounded bottom; its wire and its centre line's half width.
        public static let dWire: CGFloat = 1.3 * size
        public static let dHalf: CGFloat = 3.3 * size
        public static var dTop: CGFloat { barrelTop + barrel.height }
        /// Where the D-ring's straight sides end and its round bottom begins (centre line).
        public static var dRound: CGFloat { dTop + dWire / 2 + 3.2 * size }
        /// The inside of the D-ring's bottom, where the next piece hangs.
        public static var end: CGFloat { dRound + dHalf - dWire / 2 }
    }

    /// How the charms hang: drawn `scale` × their measured size, from a lobster clasp on the split ring (or
    /// straight on it) and then a chain of `chainLinks` links (0: no chain). Positions at rest, relative to the
    /// ring point, keychain 1× points.
    public struct Hang: Equatable, Sendable {
        public var scale: CGFloat
        public var chainLinks: Int
        public var clasp: Bool

        public init(scale: CGFloat, chainLinks: Int = 0, clasp: Bool = false) {
            self.scale = scale
            self.chainLinks = chainLinks
            self.clasp = clasp
        }

        /// Where the chain's top link (or the jump ring) hangs: the clasp's D-ring, or the split ring.
        public var chainTop: CGFloat { clasp ? Clasp.end : Chain.ringTop }

        /// The jump ring's centre below the ring point.
        public var jumpCenter: CGFloat {
            if chainLinks > 0 { return Chain.end(links: chainLinks, top: chainTop) + (jumpRadius - wire) * scale }
            return clasp ? Clasp.end + (jumpRadius - wire) * scale : jumpDrop * scale
        }

        /// A strand's top loop at rest.
        public func pivot(_ s: Strand) -> CGPoint {
            let p = BeadCharms.pivot(s)
            return CGPoint(x: p.x * scale, y: jumpCenter + p.y * scale)
        }

        /// Each bead's box at rest (jump ring straight down, strands at their rest angles).
        public func beads(_ s: Strand) -> [CGRect] {
            let top = pivot(s), k = scale
            return stack(s).map { b in
                let r = CGRect(x: (b.center.x - b.size.width / 2) * k, y: (b.center.y - b.size.height / 2) * k,
                               width: b.size.width * k, height: b.size.height * k)
                return KeyringGeometry.rotatedBounds(r, degrees: restAngle(s)).offsetBy(dx: top.x, dy: top.y)
            }
        }

        /// Chain, jump ring and strands with a little room for shadows.
        public var bounds: CGRect {
            let r = (jumpRadius + 1) * scale
            var box = CGRect(x: -r, y: jumpCenter - r, width: r * 2, height: r * 2)
            if clasp {
                box = box.union(CGRect(x: -Clasp.width / 2 - 3, y: Clasp.top - 1, width: Clasp.width + 7, height: Clasp.end - Clasp.top + 4))
            }
            if chainLinks > 0 {
                let top = Chain.linkCenter(0, top: chainTop) - Chain.linkLength / 2
                box = box.union(CGRect(x: -Chain.linkWidth / 2 - 1, y: top - 1,
                                       width: Chain.linkWidth + 3, height: Chain.end(links: chainLinks, top: chainTop) - top + 3))
            }
            for s in Strand.allCases {
                let b = BeadCharms.bounds(s), top = pivot(s), k = scale
                let r = CGRect(x: b.minX * k, y: b.minY * k, width: b.width * k, height: b.height * k)
                box = box.union(KeyringGeometry.rotatedBounds(r, degrees: restAngle(s)).offsetBy(dx: top.x, dy: top.y))
            }
            return box
        }

        /// The lower `fraction` of each strand's last bead (leaf, heart, last disc) hangs `margin` clear of every
        /// module's body at rest, whichever is in front, for every band count (fraction 1: the whole bead).
        public func showsBelowEveryModule(fraction: CGFloat = 1, margin: CGFloat = 2) -> Bool {
            let rest = Pendulum.restAngles()
            return (2...8).allSatisfy { bands in
                let bodies = KeyringGeometry.restBodies(bands: bands, rest: rest)
                return Strand.allCases.allSatisfy { s in
                    let b = beads(s).last!
                    let part = CGRect(x: b.minX, y: b.maxY - b.height * fraction, width: b.width, height: b.height * fraction)
                    return KeyringGeometry.isClear(part.insetBy(dx: -margin, dy: -margin), of: bodies)
                }
            }
        }

        /// The shortest chain (in links, 0 = none) that lets the charms at `scale` show below every module.
        public static func shortestChain(scale: CGFloat, clasp: Bool = false, fraction: CGFloat = 1, margin: CGFloat = 2) -> Int {
            (0...60).first { Hang(scale: scale, chainLinks: $0, clasp: clasp).showsBelowEveryModule(fraction: fraction, margin: margin) } ?? 60
        }
    }

    /// How the keychain hangs them.
    public static let hang = Hang(scale: displayScale, chainLinks: chainLinks, clasp: true)
    /// Drawn 1.6× the measured size, from a gold lobster
    /// clasp on the split ring and a 3-link chain: the shortest that lets the lower 60 % of each strand's last bead
    /// (leaf, heart, last disc) hang clear below every module at rest (checked in VChainChecks); the heart's top
    /// tucks under the Energy module's edge when that is in front.
    public static let displayScale: CGFloat = 1.6
    /// Chain links between the clasp and the jump ring.
    public static let chainLinks = 3

    /// Rest angles in degrees, the modules' convention (0 hangs straight down from its top loop, positive
    /// swings the lower end to the left). The middle strand (mushroom) hangs straight down, the tulip
    /// a little to the left and the millefiori a little to the right, so the leaf and the last discs show
    /// beside the heart.
    public static func restAngle(_ s: Strand) -> Double {
        switch s {
        case .tulip: 7
        case .mushroom: 0
        case .millefiori: -7
        }
    }

    /// Swing period of a stiff strand about its top loop (its own small wobble): a rigid rod about its end,
    /// T = 2π √(2L / 3g), with 1 pt read as 1 mm (the real thing is about that size).
    public static func period(_ s: Strand) -> Double {
        let metres = Double(length(s)) / 1000
        return 2 * Double.pi * (2 * metres / (3 * 9.81)).squareRoot()
    }

    /// Swing period of the whole bunch about the ring point: a pendulum to the strands' middle,
    /// T = 2π √(L / g), 1 pt read as 1 mm (slower than the modules, being longer).
    public static var bunchPeriod: Double {
        let middle = Double(hang.jumpCenter) + Double(strandLengthMean * displayScale) / 2
        return 2 * Double.pi * (middle / 1000 / 9.81).squareRoot()
    }

    static var strandLengthMean: CGFloat { Strand.allCases.map(length).reduce(0, +) / CGFloat(Strand.allCases.count) }

    /// `p` swung `degrees` about the origin, clockwise on screen.
    static func rotate(_ p: CGPoint, _ degrees: Double) -> CGPoint {
        let a = degrees * Double.pi / 180
        let c = CGFloat(cos(a)), s = CGFloat(sin(a))
        return CGPoint(x: p.x * c - p.y * s, y: p.x * s + p.y * c)
    }
}

/// The bead charms' motion, angles in degrees (0 = hanging straight down, positive swings the lower end to
/// the left, as for the modules). The whole bunch (jump ring and strands) swings as one pendulum about
/// the ring point, damped so it settles in about the modules' time; each strand also swings a little on its
/// own about its top loop, nudged by the bunch's changes of speed (it lags behind them).
public struct CharmsSwing: Sendable {
    public private(set) var bunch = Pendulum(rest: 0, damping: CharmsSwing.bunchDamping, period: BeadCharms.bunchPeriod)
    /// Each strand's angle relative to the bunch.
    public private(set) var strands = BeadCharms.Strand.allCases.map { Pendulum(rest: BeadCharms.restAngle($0), period: BeadCharms.period($0)) }

    /// The bunch is longer than a module (slower swing): damped harder so it is still as soon.
    public static let bunchDamping = 0.35
    /// How much of a change in the bunch's angular speed a strand lags by.
    public static let lag = 0.5

    public init() {}

    /// The jump ring's angle (the bunch as a whole).
    public var bunchAngle: Double { bunch.angle }
    public func angle(_ s: BeadCharms.Strand) -> Double { bunch.angle + strands[s.rawValue].angle }

    /// Dropped in with the keychain: the bunch swung `Pendulum.releaseSwing` out, the strands at rest on it.
    public mutating func release() {
        bunch.release()
        for i in strands.indices { strands[i].settleImmediately() }
    }

    public mutating func settleImmediately() {
        bunch.settleImmediately()
        for i in strands.indices { strands[i].settleImmediately() }
    }

    /// Brought to the front: a push on the bunch; the strands lag behind it.
    public mutating func push(_ dv: Double) {
        bunch.push(dv)
        for i in strands.indices { strands[i].push(-Self.lag * dv) }
    }

    public mutating func step(_ dt: Double) {
        let before = bunch.velocity
        bunch.step(dt)
        let dv = bunch.velocity - before
        for i in strands.indices {
            strands[i].push(-Self.lag * dv)
            strands[i].step(dt)
        }
    }

    /// Nothing visibly moving (the same thresholds as the modules').
    public var isSettled: Bool {
        abs(bunch.angle) < 0.05 && abs(bunch.velocity) < 0.5
            && strands.allSatisfy { abs($0.angle - $0.rest) < 0.05 && abs($0.velocity) < 0.5 }
    }
}
