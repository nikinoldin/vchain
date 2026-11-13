// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI
import VChainKit

/// Where everything hangs in the panel, in points. The panel's top edge is the menu bar's bottom edge;
/// the design hangs the keychain 1 pt below the top of a 24 pt menu bar with the ring point at y 39
/// (1×, ×1.5), so the ring point sits 35.5 pt below the menu bar and the ring's top (the hook) is
/// cut off by the panel's top edge. The panel is just big enough for every module at rest, ± a swing.
struct KeychainLayout {
    static let scale = HardwareScale.app
    static let ringPointBelowMenuBar: CGFloat = 1 + KeyringGeometry.ringPoint.y * scale - 24
    /// Extra swing the panel leaves room for, degrees either side of rest.
    static let swingMargin = 12.0

    let bands: Int
    let size: CGSize
    /// The ring point (every module's hole) at rest, before the drop.
    let ringPoint: CGPoint

    init(bands: Int) {
        self.bands = bands
        let rest = Pendulum.restAngles()
        var box = Self.ringBounds
        for (rect, angle) in Self.extents(bands: bands, rest: rest) {
            for d in [-Self.swingMargin, 0, Self.swingMargin] {
                box = box.union(KeyringGeometry.rotatedBounds(rect, degrees: angle + d))
            }
        }
        ringPoint = CGPoint(x: ceil(-box.minX), y: Self.ringPointBelowMenuBar)
        size = CGSize(width: ceil(-box.minX) + ceil(box.maxX), height: ceil(Self.ringPointBelowMenuBar + box.maxY))
    }

    /// A point in design hang units (1×, the hook at (0, 7.6)) in the panel.
    func point(hang p: CGPoint) -> CGPoint {
        CGPoint(x: ringPoint.x + (p.x - KeyringGeometry.ringPoint.x) * Self.scale,
                y: ringPoint.y + (p.y - KeyringGeometry.ringPoint.y) * Self.scale)
    }

    /// Where the ring's top meets the menu bar: lines up with the middle of the status item.
    var hook: CGPoint { point(hang: KeyringGeometry.hook) }

    /// Each module's body plus its shadows and overhanging parts, relative to its hole, with its rest angle.
    private static func extents(bands: Int, rest: (bpm: Double, midi: Double, energy: Double)) -> [(CGRect, Double)] {
        let tag = BPMTagView.holeCenter, side = BPMTagView.side
        // The tag: sticker over the top edge, jack + cable out on the right, drop shadow below.
        let bpm = CGRect(x: -tag.x - 15, y: -tag.y - 16, width: side + 15 + 66, height: side + 16 + 30)
        let strip = MIDIStripView.holeCenter(bands: bands), width = MIDIStripView.width(bands: bands)
        // The strip's MIDI OUT cable hangs ≈ 34 pt out past its left cap; the Energy module's plug sticks ≈ 19 pt out of
        // its left edge and its cable sags ≈ 30 pt below it.
        let midi = CGRect(x: -strip.x - 38, y: -strip.y - 6, width: width + 53, height: MIDIStripView.height + 6 + 27)
        let e = EnergyModuleView.holeCenter, size = EnergyModuleView.size
        let energy = CGRect(x: -e.x - 24, y: -e.y - 10, width: size.width + 40, height: size.height + 10 + 36)
        // The bead charms: (chain,) jump ring and strands hanging from the ring point.
        let c = BeadCharms.hang.bounds
        let charms = CGRect(x: c.minX * scale, y: c.minY * scale, width: c.width * scale, height: c.height * scale)
        return [(bpm, rest.bpm), (midi, rest.midi), (energy, rest.energy), (charms, 0)]
    }

    /// The ring (with its shadow), relative to the ring point.
    private static var ringBounds: CGRect {
        let b = RingPiece.box
        return CGRect(x: (b.minX - KeyringGeometry.ringPoint.x) * scale, y: (b.minY - KeyringGeometry.ringPoint.y) * scale,
                      width: b.width * scale, height: b.height * scale)
    }

    /// How far the ring's top (its outer edge, with a margin) reaches above the layout's top edge: the part the
    /// menu bar hides while attached.
    var ringTopRoom: CGFloat {
        let ring = KeyringGeometry.ring(hook: KeyringGeometry.hook, hole: KeyringGeometry.ringPoint, radius: KeyringGeometry.ringRadius)
        let top = point(hang: CGPoint(x: ring.center.x, y: ring.center.y - ring.radius - 2.5)).y
        return ceil(max(0, -top)) + 4
    }

    /// The keyring and the disc inside it (the detached keychain's drag area), in the layout's coordinates.
    var ringDisc: (center: CGPoint, radius: CGFloat) {
        let ring = KeyringGeometry.ring(hook: KeyringGeometry.hook, hole: KeyringGeometry.ringPoint, radius: KeyringGeometry.ringRadius)
        return (point(hang: ring.center), (ring.radius + 2.5) * HardwareScale.app)
    }
}

extension View {
    /// Hung by `hole` (a point in its own `size` frame) from `point`, swung `angle` degrees about it.
    func hung(size: CGSize, hole: CGPoint, angle: Double, at point: CGPoint) -> some View {
        frame(width: size.width, height: size.height, alignment: .topLeading)
            .rotationEffect(.degrees(angle), anchor: UnitPoint(x: hole.x / size.width, y: hole.y / size.height))
            .offset(x: point.x - hole.x, y: point.y - hole.y)
    }
}
