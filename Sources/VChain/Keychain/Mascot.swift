// SPDX-License-Identifier: GPL-3.0-or-later
import VChainKit
import SwiftUI

/// The character on the BPM tag's LCD and in the menu bar. `BPMTagState` decides the pose (`MascotPose`); a mascot
/// says which of its LCD segments light for each pose and draws a menu bar template per pose. Only the dancer ships;
/// more characters can be added as further `Mascot` values.
struct Mascot {
    var name: String
    /// LCD segments in the tag LCD's 140 × 96 units, plus what's printed on the glass (the dancer's stage line).
    var elements: [LCDElement]
    /// Lit segment names per pose (`hidden` = none).
    var poses: [MascotPose: Set<String>]
    /// Menu bar template per pose, in points (18 pt tall, `menuWidth` wide, y down), and the settling variant.
    var menu: [MascotPose: Path]
    var menuSettling: Path
    var menuWidth: CGFloat

    static let dancer = MascotGeometry.dancer()
    /// The mascot in use.
    static var current: Mascot { dancer }

    func lit(_ pose: MascotPose) -> Set<String> { poses[pose] ?? [] }

    /// The menu bar drawing: `settling` adds the "?" to the still pose.
    func menuArt(_ pose: MascotPose, settling: Bool = false) -> Path {
        settling ? menuSettling : (menu[pose] ?? menu[.still] ?? Path())
    }
}

// MARK: - The dancer

extension MascotGeometry {
    /// The dancer in her "Fluffies" outfit, drawn chibi (with `DancerKit`): a big head (about a third of her
    /// height) with space buns and a fringe, a straight tube top, a puffy pleated mini skirt, short sturdy limbs with
    /// round hands, chunky fluffies and shoes. The menu bar keeps the Fluffies pictogram. Beat A: right arm up, left knee out; beat B the mirror;
    /// on the 1 a star jump, the skirt flips out and two sparkles light. Resting (no input): she meditates, seated
    /// cross-legged at her own spot right of the stage under the "?" (never lit together: the "?" only shows while
    /// settling, with the standing figure), eyes closed, two static aura arcs. Printed: a stage line under both spots.
    static func dancer() -> Mascot {
        var s = Segs()
        let X = DK.X
        s.printed("floor", DK.floor)
        // Head + buns + fringe.
        let head0 = oval(X(0), 62.6, 3.5, 3.6)
        let fringe = shape { p in p.move(to: P(X(-3.6), 63.3)); p.addQuadCurve(to: P(X(3.6), 63.1), control: P(X(0.6), 59.4)) }
        s.add("head", cut(head0, fringe, 0.5))
        s.add("buns", clear(unite([disc(X(-2.55), 58.7, 1.7), disc(X(2.55), 58.7, 1.7)]), of: head0))
        // Tube top: a straight torso, its upper edge cut across.
        let torso = Path(roundedRect: CGRect(x: X(-2.4), y: 66.9, width: 4.8, height: 4.5), cornerRadius: 1.0)
        s.add("top", cut(torso, polyline([P(X(-3), 67.9), P(X(3), 67.9)]), 0.45))
        // A puffy, flared pleated mini, like a doll's skirt.
        let skirt = shape { p in
            p.move(to: P(X(-2.5), 71.9)); p.addLine(to: P(X(2.5), 71.9))
            p.addCurve(to: P(X(5.3), 75.0), control1: P(X(3.6), 72.2), control2: P(X(5.2), 73.6))
            p.addQuadCurve(to: P(X(-5.3), 75.0), control: P(X(0), 76.5))
            p.addCurve(to: P(X(-2.5), 71.9), control1: P(X(-5.2), 73.6), control2: P(X(-3.6), 72.2)); p.closeSubpath()
        }
        s.add("skirt", [-3.0, -1.5, 0, 1.5, 3.0].reduce(skirt) { cut($0, polyline([P(X($1 * 0.55), 73.0), P(X($1), 76.0)]), 0.4) })
        /// A chunky fluffy leg warmer: a flared fuzzy cone with bumps along both edges and a fuzzy cuff on top.
        func fluffy(_ a: CGPoint, _ b: CGPoint, _ w0: CGFloat, _ w1: CGFloat) -> Path {
            var parts = [polygon([P(a.x - w0 / 2, a.y), P(a.x + w0 / 2, a.y), P(b.x + w1 / 2, b.y), P(b.x - w1 / 2, b.y)]),
                         Path(roundedRect: CGRect(x: b.x - w1 / 2, y: b.y - 0.7, width: w1, height: 1.1), cornerRadius: 0.5)]
            for k in 0...4 {
                let t = CGFloat(k) / 4, x = a.x + (b.x - a.x) * t, y = a.y + (b.y - a.y) * t, w = (w0 + (w1 - w0) * t) / 2
                parts += [disc(x - w, y, 0.45), disc(x + w, y, 0.45)]
            }
            for k in 0...3 { parts.append(disc(a.x - w0 / 2 + w0 * CGFloat(k) / 3, a.y, 0.5)) }
            return unite(parts)
        }
        func shoe(_ x: CGFloat) -> Path { Path(roundedRect: CGRect(x: X(x - 1.4), y: 85.9, width: 2.8, height: 1.4), cornerRadius: 0.6) }
        let straight = unite([limb([P(X(2.0), 76.4), P(X(2.2), 80.8)], 1.8, 1.7), fluffy(P(X(2.2), 80.9), P(X(2.2), 85.2), 2.3, 2.8), shoe(2.2)])
        let outLeg = clear(unite([limb([P(X(3.9), 76.3), P(X(6.2), 80.4)], 1.8, 1.7), fluffy(P(X(6.4), 80.9), P(X(6.6), 85.2), 2.3, 2.8), shoe(6.6)]),
                           of: straight)
        s.pair("legStraight", clear(straight, of: skirt)); s.pair("legOut", clear(outLeg, of: skirt))
        // Short sturdy arms with round hands.
        let down = clear(clear(unite([limb([P(X(3.1), 67.9), P(X(3.9), 69.9), P(X(4.3), 71.0)], 1.5, 1.3), disc(X(4.6), 71.1, 0.82)]),
                               of: torso), of: skirt)
        let up = clear(clear(unite([limb([P(X(3.3), 66.3), P(X(4.9), 64.4), P(X(5.6), 62.0)], 1.5, 1.3), disc(X(5.7), 61.3, 0.85)]),
                             of: torso), of: down)
        s.pair("armDown", down); s.pair("armUp", up)
        s.pair("flip", clear(stroked(shape { p in p.move(to: P(X(6.6), 72.6)); p.addQuadCurve(to: P(X(7.4), 76.2), control: P(X(7.9), 73.4)) }, 0.6),
                             of: skirt))
        s.add("sparkleL", sparkle(X(-11.0), 62.6, 1.6))
        s.add("sparkleR", sparkle(X(9.8), 63.4, 1.4))

        // Seated, meditating (no input): the same chibi build, cross-legged, skirt over the lap, fluffies bunched
        // at the shins, eyes closed. The "?" for settling is the LCD's own (element "q").
        let sx = SK.sx
        let sHead0 = oval(sx, 77.0, 3.5, 3.6)
        var sHead = cut(sHead0, moved(fringe, sx - DK.cx, 14.4), 0.5)
        for e in [-1.3, 1.3] as [CGFloat] {
            sHead = cut(sHead, shape { p in p.move(to: P(sx + e - 0.6, 78.2)); p.addQuadCurve(to: P(sx + e + 0.6, 78.2), control: P(sx + e, 79.0)) }, 0.35)
        }
        s.add("sitHead", sHead)
        s.add("sitHair", clear(unite([disc(sx - 2.2, 72.95, 1.55), disc(sx + 2.2, 72.95, 1.55)]), of: sHead0))
        let sTorso = Path(roundedRect: CGRect(x: sx - 2.4, y: 81.2, width: 4.8, height: 3.0), cornerRadius: 0.9)
        s.add("sitTop", cut(sTorso, polyline([P(sx - 3, 82.0), P(sx + 3, 82.0)]), 0.45))
        let drape = shape { p in
            p.move(to: P(sx - 2.5, 84.7)); p.addLine(to: P(sx + 2.5, 84.7))
            p.addQuadCurve(to: P(sx + 5.0, 86.7), control: P(sx + 4.4, 84.9))
            p.addQuadCurve(to: P(sx - 5.0, 86.7), control: P(sx, 87.4))
            p.addQuadCurve(to: P(sx - 2.5, 84.7), control: P(sx - 4.4, 84.9)); p.closeSubpath()
        }
        var sSkirt = drape
        for d in [-1.8, 0, 1.8] as [CGFloat] { sSkirt = cut(sSkirt, polyline([P(sx + d * 0.7, 85.4), P(sx + d, 87.2)]), 0.4) }
        s.add("sitSkirt", sSkirt)
        let fuzz = { (x: CGFloat) in unite([oval(sx + x, 86.3, 1.6, 1.3)] + (0...4).map { k in disc(sx + x - 1.4 + CGFloat(k) * 0.7, 85.0, 0.45) }) }
        s.add("sitLegs", clear(unite([oval(sx, 86.6, 6.0, 1.15), fuzz(5.3), fuzz(-5.3)]), of: drape))
        let sArm = unite([limb([P(sx + 2.9, 81.8), P(sx + 3.9, 83.2)], 1.4, 1.3), disc(sx + 4.3, 83.9, 0.75)])
        s.add("sitArms", clear(clear(sArm.union(mirrorX(sArm, sx)), of: sTorso), of: drape.union(fuzz(5.3)).union(fuzz(-5.3))))
        s.add("aura", SK.aura)

        let fixed: Set<String> = ["head", "buns", "top", "skirt"]
        let still = fixed.union(["armDownL", "armDownR", "legStraightL", "legStraightR"])
        let seated: Set<String> = ["sitHead", "sitTop", "sitHair", "sitSkirt", "sitLegs", "sitArms", "aura"]

        // Menu bar (16 pt wide): the same outfit as a pictogram.
        let cx = MK.cx
        let mTop = polygon([P(cx - 1.9, 8), P(cx + 1.9, 8), P(cx + 1.3, 10.6), P(cx - 1.3, 10.6)])
        let mSkirt = polygon([P(cx - 1.3, 10.6), P(cx + 1.3, 10.6), P(cx + 3.8, 13), P(cx - 3.8, 13)])
        let mLegS = box(cx + 0.5, 13, 1, 2).union(box(cx + 0.25, 14.6, 2.25, 3.4))
        let mLegO = limb([P(cx + 2.4, 13.2), P(cx + 4.0, 15)], 1.3, 1.2, roundEnds: false).union(box(cx + 3.0, 14.6, 2.4, 3.4))
        let mArmD = MK.armD(), mArmU = MK.armU(), L = MK.L
        let mFig = unite([MK.head, MK.buns, mTop, mSkirt])
        let mStill = unite([mFig, mArmD, L(mArmD), mLegS, L(mLegS)])
        let mSeated = MK.seated(head: unite([MK.head, MK.buns]), top: MK.seatTop, lap: MK.seatDrape(3.4, hem: 14.4),
                                legs: unite([oval(cx, 15.7, 5.0, 1.8), disc(cx - 5.4, 15.6, 2.0), disc(cx + 5.4, 15.6, 2.0)]))

        return Mascot(
            name: "Dancer", elements: s.els,
            poses: [
                .still: still,
                .beatA: fixed.union(["armUpR", "armDownL", "legOutL", "legStraightR"]),
                .beatB: fixed.union(["armUpL", "armDownR", "legOutR", "legStraightL"]),
                .theOne: fixed.union(["armUpL", "armUpR", "legOutL", "legOutR", "sparkleL", "sparkleR", "flipL", "flipR"]),
                .resting: seated,
                .hidden: [],
                .wave: fixed.union(["armUpR", "armDownL", "legStraightL", "legStraightR"]),  // power-on hello
            ],
            menu: [
                .still: mStill,
                .beatA: unite([mFig, mArmU, L(mArmD), mLegS, L(mLegO)]),
                .beatB: unite([mFig, L(mArmU), mArmD, L(mLegS), mLegO]),
                .theOne: unite([mFig, mArmU, L(mArmU), mLegO, L(mLegO), MK.sparkles]),
                .resting: mSeated,
                .hidden: mSeated,
                .wave: unite([mFig, mArmU, L(mArmD), mLegS, L(mLegS)]),
            ],
            menuSettling: mStill.union(menuQ(11.6, 0.4)),
            menuWidth: 16)
    }
}
