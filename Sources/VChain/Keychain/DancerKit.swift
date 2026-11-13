// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI

// The dancer's shared kit, in sq units (see MascotGeometry): the standing and seated spots, the stage and the aura, and the menu bar pictogram kit (points).
// The seated (meditating) figure for no input sits at its own spot right of the standing one, on the same stage,
// under the "?" (segments never share glass, so it can't reuse the standing figure's).
extension MascotGeometry {
    /// Where the standing dancer stands, and the stage.
    enum DK {
        static let cx: CGFloat = 16.4
        static func X(_ d: CGFloat) -> CGFloat { cx + d }
        /// The printed stage line, under both the standing and the seated spot.
        static let floor = unite([stroked(polyline([P(4.0, 87.9), P(40.0, 87.9)]), 0.7),
                                  stroked(polyline([P(8.0, 89.6), P(13.0, 89.6)]), 0.6), stroked(polyline([P(20.0, 89.6), P(25.0, 89.6)]), 0.6)])
    }

    /// Where the seated (meditating) figure sits: right of the dancer, under the "?"; its static aura arcs.
    enum SK {
        static let sx = DK.cx + 16.1
        static func X(_ d: CGFloat) -> CGFloat { sx + d }
        /// Two arcs beside the seated head (static).
        static let aura = unite([
            stroked(shape { p in p.move(to: P(X(-4.6), 72.8)); p.addQuadCurve(to: P(X(-4.6), 78.4), control: P(X(-6.2), 75.6)) }, 0.5),
            stroked(shape { p in p.move(to: P(X(4.6), 72.8)); p.addQuadCurve(to: P(X(4.6), 78.4), control: P(X(6.2), 75.6)) }, 0.5),
        ])
    }

    /// Menu bar pictogram kit: points, 18 tall, the figure centred on x 7.5, legs on whole points.
    enum MK {
        static let cx: CGFloat = 7.5
        static let head = disc(cx, 4.9, 2.4)
        static let buns = unite([disc(cx - 1.8, 1.7, 1.25), disc(cx + 1.8, 1.7, 1.25)])
        static func armD(_ w0: CGFloat = 1.3, _ w1: CGFloat = 1.1, dx: CGFloat = 0) -> Path { limb([P(cx + 2.0 + dx, 8.6), P(cx + 3.3 + dx, 12.2)], w0, w1) }
        static func armU(_ w0: CGFloat = 1.3, _ w1: CGFloat = 1.1) -> Path { limb([P(cx + 2.0, 8.4), P(cx + 4.4, 5.6), P(cx + 4.9, 2.2)], w0, w1) }
        static let sparkles = unite([sparkle(cx + 7.0, 8.4, 1.4, 0.25), sparkle(cx - 6.1, 10.2, 1.3, 0.25)])
        static func L(_ p: Path) -> Path { mirrorX(p, cx) }
        static let seatTop = polygon([P(cx - 1.9, 8), P(cx + 1.9, 8), P(cx + 1.3, 11.6), P(cx - 1.3, 11.6)])
        static func seatDrape(_ half: CGFloat, hem: CGFloat = 15.4) -> Path {
            polygon([P(cx - 1.3, 11.8), P(cx + 1.3, 11.8), P(cx + half, hem), P(cx - half, hem)])
        }
        /// Seated pictogram: `head` (hair included), `top` from y 8, crossed legs, arms to the knees, aura arcs, eyes closed.
        static func seated(head: Path, top: Path, lap: Path? = nil, legs: Path? = nil) -> Path {
            let lotus = legs ?? oval(cx, 15.7, 6.6, 1.9)
            let arm = limb([P(cx + 2.0, 8.8), P(cx + 4.0, 11.4), P(cx + 5.2, 13.0)], 1.2, 1.1)
            let aura = unite([stroked(shape { p in p.move(to: P(cx - 4.4, 2.4)); p.addQuadCurve(to: P(cx - 4.4, 7.6), control: P(cx - 6.0, 5)) }, 1),
                              stroked(shape { p in p.move(to: P(cx + 4.4, 2.4)); p.addQuadCurve(to: P(cx + 4.4, 7.6), control: P(cx + 6.0, 5)) }, 1)])
            var fig = unite([head, top, arm, L(arm), lotus, aura])
            if let lap { fig = fig.subtracting(stroked(lap, 1.2)).union(lap) }
            return fig.subtracting(box(cx - 1.6, 5.4, 1.2, 0.8)).subtracting(box(cx + 0.4, 5.4, 1.2, 0.8))
        }
    }
}

extension MascotGeometry.Segs {
    /// Adds `<n>R` and its mirror `<n>L` (mirrored about the standing dancer's centre).
    mutating func pair(_ n: String, _ p: Path) {
        add(n + "R", p); add(n + "L", MascotGeometry.mirrorX(p, MascotGeometry.DK.cx))
    }
}
