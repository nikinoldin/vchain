// SPDX-License-Identifier: GPL-3.0-or-later
import CoreGraphics
import Foundation

/// Split-ring geometry (screen coordinates, y down; angles clockwise from +x as drawn).
public struct Ring: Sendable {
    public let center: CGPoint
    public let radius: CGFloat
}

public enum KeyringGeometry {
    // Design units (1×; the app draws them × HardwareScale.app = 1.5), origin under the status item.
    public static let ringRadius: CGFloat = 18.4
    public static let hook = CGPoint(x: 0, y: 7.6)
    public static let ringPoint = CGPoint(x: 13, y: 39)
    public static let holeOpening: CGFloat = 2.5

    /// The circle of `radius` through `hook` and `hole`, centre on the left.
    public static func ring(hook: CGPoint, hole: CGPoint, radius: CGFloat) -> Ring {
        let mid = CGPoint(x: (hook.x + hole.x) / 2, y: (hook.y + hole.y) / 2)
        let dx = hole.x - hook.x, dy = hole.y - hook.y
        let d = hypot(dx, dy)
        let h = (radius * radius - d * d / 4).squareRoot()
        let perp = CGPoint(x: -dy / d, y: dx / d)
        let a = CGPoint(x: mid.x + perp.x * h, y: mid.y + perp.y * h)
        let b = CGPoint(x: mid.x - perp.x * h, y: mid.y - perp.y * h)
        return Ring(center: a.x <= b.x ? a : b, radius: radius)
    }

    /// The MIDI strip, 1×: left cap 19, a channel module 27 per band, right cap 17; 100 tall.
    public static let stripLeftCap: CGFloat = 19, stripChannel: CGFloat = 27, stripRightCap: CGFloat = 17
    public static let stripHeight: CGFloat = 100

    /// Width of the MIDI strip: left cap, a channel module per band, right cap.
    public static func stripWidth(bands: Int, scale: CGFloat) -> CGFloat {
        (stripLeftCap + stripChannel * CGFloat(bands) + stripRightCap) * scale
    }

    /// The BPM tag: a 100 × 100 plate (corner radius 14) with its hole 9 in from the top-left corner.
    public static let bpmTagSide: CGFloat = 100
    public static let bpmTagCornerRadius: CGFloat = 14
    public static let bpmTagHole = CGPoint(x: 9, y: 9)
    /// The Energy module: 300 × 212 SVG units (its design's units, 1.9 per 1× point), hole at (26, 26) units.
    public static let energyUnitsPerPoint: CGFloat = 1.9
    public static let energyDesignSize = CGSize(width: 300, height: 212)
    public static let energySize = CGSize(width: energyDesignSize.width / energyUnitsPerPoint,
                                          height: energyDesignSize.height / energyUnitsPerPoint)
    public static let energyHole = CGPoint(x: 26 / energyUnitsPerPoint, y: 26 / energyUnitsPerPoint)

    /// Each module's body (relative to its hole) and rest angle, 1×: BPM tag, MIDI strip, Energy module.
    public static func restBodies(bands: Int, rest: (bpm: Double, midi: Double, energy: Double)) -> [(rect: CGRect, degrees: Double)] {
        let strip = stripHoleOffset(bands: bands, scale: 1)
        return [
            (CGRect(x: -bpmTagHole.x, y: -bpmTagHole.y, width: bpmTagSide, height: bpmTagSide), rest.bpm),
            (CGRect(x: -strip.x, y: -strip.y, width: stripWidth(bands: bands, scale: 1), height: stripHeight), rest.midi),
            (CGRect(origin: CGPoint(x: -energyHole.x, y: -energyHole.y), size: energySize), rest.energy),
        ]
    }

    /// Whether `p` (relative to the hole, screen axes) lies on `rect` (the module's own axes) swung `degrees`.
    public static func covers(_ rect: CGRect, degrees: Double, _ p: CGPoint) -> Bool {
        let a = -degrees * Double.pi / 180
        let c = CGFloat(cos(a)), s = CGFloat(sin(a))
        return rect.contains(CGPoint(x: p.x * c - p.y * s, y: p.x * s + p.y * c))
    }

    /// No point of `box` (sampled on a 9 × 9 grid) lies on any of the module bodies.
    public static func isClear(_ box: CGRect, of bodies: [(rect: CGRect, degrees: Double)]) -> Bool {
        for i in 0...8 {
            for j in 0...8 {
                let p = CGPoint(x: box.minX + box.width * CGFloat(i) / 8, y: box.minY + box.height * CGFloat(j) / 8)
                for b in bodies where covers(b.rect, degrees: b.degrees, p) { return false }
            }
        }
        return true
    }

    /// The strip's keyring hole, from its top-left corner.
    public static func stripHoleOffset(bands: Int, scale: CGFloat) -> CGPoint {
        CGPoint(x: stripWidth(bands: bands, scale: scale) - 8.5 * scale, y: 8.5 * scale)
    }
}

extension Ring {
    /// Front piece: from the top of the ring clockwise to the hole's far edge.
    /// Back piece: from there on round to the top again.
    public func arcs(holeOpening: CGFloat) -> (front: ClosedRange<Double>, back: ClosedRange<Double>) {
        let hole = KeyringGeometry.ringPoint
        let aH = Double(atan2(hole.y - center.y, hole.x - center.x))
        let top = -Double.pi / 2
        let far = aH + 2 * asin(Double(holeOpening / (2 * radius)))
        return (front: top...far, back: far...(top + 2 * Double.pi))
    }
}

extension KeyringGeometry {
    /// Bounding box of `rect` (in a module's own coordinates, origin at its keyring hole) after the module
    /// swings `degrees` about the hole (clockwise on screen, y down).
    public static func rotatedBounds(_ rect: CGRect, degrees: Double) -> CGRect {
        let a = degrees * Double.pi / 180
        let c = CGFloat(cos(a)), s = CGFloat(sin(a))
        let corners = [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
                       CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.maxY)]
            .map { CGPoint(x: $0.x * c - $0.y * s, y: $0.x * s + $0.y * c) }
        let xs = corners.map(\.x), ys = corners.map(\.y)
        return CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
    }
}
