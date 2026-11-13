// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI

/// Drawing helpers for the LCD mascots.
/// A mascot is drawn in square units ("sq"): 1 sq = 0.625 pt at the LCD's 1× size, equal in x and y, so circles are
/// circles; `lcd()` stretches x by 1.122 into the tag LCD's squashed 140 × 96 units. Its corner of the LCD is sq
/// x 1.8…42.8, y 56.5…88: below the dotted divider, above the printed strip, clear of the "?" (sq x 33.4…39.7,
/// y 60.5…70.5) and left of the beat blocks. Segments keep `gap` of clear glass between them (a real segment LCD
/// never puts two electrodes on the same glass). Menu bar art is drawn in points, 18 pt tall, y down.
enum MascotGeometry {
    static let K: CGFloat = 0.625 / (78.0 / 140)
    /// Clear glass between two segments (sq).
    static let GAP: CGFloat = 0.6

    static func lcd(_ p: Path) -> Path { p.applying(CGAffineTransform(scaleX: K, y: 1)) }
    static func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }
    static func disc(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat) -> Path { Path(ellipseIn: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r)) }
    static func oval(_ x: CGFloat, _ y: CGFloat, _ rx: CGFloat, _ ry: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: x - rx, y: y - ry, width: 2 * rx, height: 2 * ry))
    }
    static func box(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> Path { Path(CGRect(x: x, y: y, width: w, height: h)) }
    static func shape(_ build: (inout Path) -> Void) -> Path { var p = Path(); build(&p); return p }
    static func polyline(_ pts: [CGPoint]) -> Path { Path { p in p.addLines(pts) } }
    static func polygon(_ pts: [CGPoint]) -> Path { Path { p in p.addLines(pts); p.closeSubpath() } }
    static func moved(_ p: Path, _ dx: CGFloat, _ dy: CGFloat) -> Path { p.applying(CGAffineTransform(translationX: dx, y: dy)) }
    static func mirrorX(_ p: Path, _ x: CGFloat) -> Path { p.applying(CGAffineTransform(translationX: 2 * x, y: 0).scaledBy(x: -1, y: 1)) }

    static func stroked(_ p: Path, _ w: CGFloat, cap: CGLineCap = .round, join: CGLineJoin = .round) -> Path {
        p.strokedPath(StrokeStyle(lineWidth: w, lineCap: cap, lineJoin: join, miterLimit: 3))
    }
    /// Cuts a line of clear glass through a segment.
    static func cut(_ p: Path, _ line: Path, _ w: CGFloat = GAP) -> Path { p.subtracting(stroked(line, w)) }
    /// `p` with clear glass of width `g` kept between it and `other`.
    static func clear(_ p: Path, of other: Path, _ g: CGFloat = GAP) -> Path { p.subtracting(other.union(stroked(other, 2 * g))) }
    static func unite(_ ps: [Path]) -> Path { ps.dropFirst().reduce(ps.first ?? Path()) { $0.union($1) } }

    /// A limb along a polyline, `w0` wide at the start and `w1` at the end, round joints and ends.
    static func limb(_ pts: [CGPoint], _ w0: CGFloat, _ w1: CGFloat, roundEnds: Bool = true) -> Path {
        var total: CGFloat = 0
        var lens: [CGFloat] = [0]
        for i in 1..<pts.count { total += hypot(pts[i].x - pts[i - 1].x, pts[i].y - pts[i - 1].y); lens.append(total) }
        func w(_ i: Int) -> CGFloat { w0 + (w1 - w0) * lens[i] / max(total, 0.001) }
        var parts: [Path] = []
        for i in 1..<pts.count {
            let a = pts[i - 1], b = pts[i]
            let dx = b.x - a.x, dy = b.y - a.y, l = max(hypot(dx, dy), 0.001)
            let nx = -dy / l, ny = dx / l
            let ra = w(i - 1) / 2, rb = w(i) / 2
            parts.append(polygon([P(a.x + nx * ra, a.y + ny * ra), P(b.x + nx * rb, b.y + ny * rb),
                                  P(b.x - nx * rb, b.y - ny * rb), P(a.x - nx * ra, a.y - ny * ra)]))
        }
        for i in pts.indices where roundEnds || (i > 0 && i < pts.count - 1) { parts.append(disc(pts[i].x, pts[i].y, w(i) / 2)) }
        return unite(parts)
    }

    /// A leaf/blade from `a` to tip `b`, widest (`w`) at `at` of the way, bent by `bend` (+ = left of a→b).
    static func blade(_ a: CGPoint, _ b: CGPoint, _ w: CGFloat, at: CGFloat = 0.45, bend: CGFloat = 0, rootW: CGFloat = 0) -> Path {
        let dx = b.x - a.x, dy = b.y - a.y, l = hypot(dx, dy)
        let nx = dy / l, ny = -dx / l
        let m = P(a.x + dx * at + nx * bend, a.y + dy * at + ny * bend)
        let r0 = rootW / 2
        return shape { p in
            p.move(to: P(a.x + nx * r0, a.y + ny * r0))
            p.addQuadCurve(to: b, control: P(m.x + nx * w, m.y + ny * w))
            p.addQuadCurve(to: P(a.x - nx * r0, a.y - ny * r0), control: P(m.x - nx * w, m.y - ny * w))
            p.closeSubpath()
        }
    }

    /// A four-point sparkle.
    static func sparkle(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat, _ waist: CGFloat = 0.28) -> Path {
        shape { p in
            let k = r * waist
            p.move(to: P(x, y - r))
            p.addQuadCurve(to: P(x + r, y), control: P(x + k, y - k))
            p.addQuadCurve(to: P(x, y + r), control: P(x + k, y + k))
            p.addQuadCurve(to: P(x - r, y), control: P(x - k, y + k))
            p.addQuadCurve(to: P(x, y - r), control: P(x - k, y - k))
            p.closeSubpath()
        }
    }

    /// Collects a mascot's LCD elements from sq paths.
    struct Segs {
        var els: [LCDElement] = []
        mutating func add(_ n: String, _ p: Path) { els.append(LCDElement(name: n, kind: .fill(MascotGeometry.lcd(p)))) }
        mutating func printed(_ n: String, _ p: Path) { els.append(LCDElement(name: n, kind: .fill(MascotGeometry.lcd(p)), printed: true)) }
    }

    // MARK: Menu bar marks (points, 18 pt tall)

    /// "?" for settling: a hook and a dot, top-left at (x, y), 6 pt tall.
    static func menuQ(_ x: CGFloat, _ y: CGFloat) -> Path {
        let hook = stroked(shape { p in
            p.move(to: P(x + 0.6, y + 1.9))
            p.addCurve(to: P(x + 3.9, y + 1.6), control1: P(x + 0.7, y - 0.4), control2: P(x + 3.8, y - 0.5))
            p.addCurve(to: P(x + 2.5, y + 4.2), control1: P(x + 4.0, y + 2.9), control2: P(x + 2.5, y + 3.0))
        }, 1.25, cap: .butt)
        return hook.union(box(x + 1.9, y + 5, 1.25, 1.25))
    }
}
