// SPDX-License-Identifier: GPL-3.0-or-later
import CoreGraphics
import Foundation
import VChainKit

func runKeyringChecks() {
    let hook = KeyringGeometry.hook
    let hole = KeyringGeometry.ringPoint
    let r = KeyringGeometry.ringRadius

    Checks.run("Keyring: constants") {
        check(r == 18.4 && hook == CGPoint(x: 0, y: 7.6) && hole == CGPoint(x: 13, y: 39)
              && KeyringGeometry.holeOpening == 2.5, "ring 18.4, hook (0,7.6), hole (13,39), opening 2.5")
    }
    Checks.run("Keyring: ring through hook and hole") {
        let ring = KeyringGeometry.ring(hook: hook, hole: hole, radius: r)
        func dist(_ p: CGPoint) -> Double { Double(hypot(p.x - ring.center.x, p.y - ring.center.y)) }
        checkApprox(dist(hook), Double(r), tol: 0.01, "hook on ring")
        checkApprox(dist(hole), Double(r), tol: 0.01, "hole on ring")
        check(ring.center.x < hole.x, "centre on the left of the hole")
        check(ring.radius == r, "radius kept")

        let aH = Double(atan2(hole.y - ring.center.y, hole.x - ring.center.x))
        let arcs = ring.arcs(holeOpening: KeyringGeometry.holeOpening)
        check(arcs.front.upperBound > aH, "front arc runs past the hole centre")
        check(arcs.back.lowerBound == arcs.front.upperBound, "back starts where front ends")
        checkApprox(arcs.front.upperBound, aH + 2 * asin(Double(KeyringGeometry.holeOpening / (2 * r))),
                    tol: 1e-9, "front ends at the hole's far edge")
        checkApprox(arcs.front.lowerBound, -Double.pi / 2, tol: 1e-9, "front starts at the top")
        checkApprox((arcs.front.upperBound - arcs.front.lowerBound)
                    + (arcs.back.upperBound - arcs.back.lowerBound), 2 * Double.pi, tol: 1e-9, "arcs span 2π")
    }
    Checks.run("Keyring: strip") {
        check(KeyringGeometry.stripWidth(bands: 3, scale: 1) == 117, "3 bands = 117")
        check(KeyringGeometry.stripWidth(bands: 8, scale: 1) == 252, "8 bands = 252")
        let off = KeyringGeometry.stripHoleOffset(bands: 8, scale: 1.5)
        // The hole sits 8.5 units in from the right cap's right and top edges: (width - 8.5*scale, 8.5*scale).
        checkApprox(Double(off.x), 365.25, tol: 1e-9, "hole x = width - 8.5*scale")
        checkApprox(Double(off.y), 12.75, tol: 1e-9, "hole y = 8.5*scale")
    }
    Checks.run("Keyring: swung bounds") {
        let r = CGRect(x: -10, y: -10, width: 100, height: 50)
        check(KeyringGeometry.rotatedBounds(r, degrees: 0) == r, "0° keeps the rect")
        let b = KeyringGeometry.rotatedBounds(r, degrees: 90)
        checkApprox(Double(b.minX), -40, tol: 1e-9, "90°: left = -(bottom)")
        checkApprox(Double(b.maxX), 10, tol: 1e-9, "90°: right = -(top)")
        checkApprox(Double(b.minY), -10, tol: 1e-9, "90°: top = left")
        checkApprox(Double(b.maxY), 90, tol: 1e-9, "90°: clockwise, the right end hangs down")
        let e = KeyringGeometry.rotatedBounds(CGRect(x: 0, y: 0, width: 10, height: 10), degrees: 45)
        checkApprox(Double(e.maxY), 10 * 2.0.squareRoot(), tol: 1e-9, "45°: square hangs diagonal")
    }
}
