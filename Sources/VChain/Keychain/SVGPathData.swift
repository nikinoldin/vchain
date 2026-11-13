// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI

/// Minimal SVG path-data parser: M/m L/l H/h V/v C/c S/s Q/q Z/z (no T, no arcs), implicit repeats,
/// compact numbers like `65.7.4` or `2-.1`.
enum SVGPathData {
    static func parse(_ d: String) -> Path {
        var p = Path()
        let chars = Array(d.utf8)
        var i = 0
        var cmd: UInt8 = 0
        var cur = CGPoint.zero, start = CGPoint.zero
        var lastCtrl: CGPoint?  // previous cubic's second control point, for S

        func skipSeparators() {
            while i < chars.count, chars[i] == 32 || chars[i] == 44 || chars[i] == 10 || chars[i] == 9 || chars[i] == 13 { i += 1 }
        }
        func number() -> CGFloat {
            skipSeparators()
            let s = i
            if i < chars.count, chars[i] == 45 || chars[i] == 43 { i += 1 }  // sign
            var dot = false
            while i < chars.count {
                let c = chars[i]
                if c >= 48 && c <= 57 { i += 1 } else if c == 46, !dot { dot = true; i += 1 }
                else if c == 101 || c == 69 {  // exponent
                    i += 1
                    if i < chars.count, chars[i] == 45 || chars[i] == 43 { i += 1 }
                } else { break }
            }
            return CGFloat(Double(String(decoding: chars[s..<i], as: UTF8.self)) ?? 0)
        }
        func point(_ rel: Bool) -> CGPoint {
            let x = number(), y = number()
            return rel ? CGPoint(x: cur.x + x, y: cur.y + y) : CGPoint(x: x, y: y)
        }
        func hasNumber() -> Bool {
            skipSeparators()
            guard i < chars.count else { return false }
            let c = chars[i]
            return (c >= 48 && c <= 57) || c == 45 || c == 43 || c == 46
        }

        while true {
            skipSeparators()
            guard i < chars.count else { break }
            let c = chars[i]
            if (c >= 65 && c <= 90) || (c >= 97 && c <= 122) {
                cmd = c
                i += 1
            } else if !hasNumber() {
                break  // stray character
            }
            let rel = cmd >= 97
            var ctrl: CGPoint?
            switch cmd | 0x20 {  // lowercased
            case 109:  // m
                cur = point(rel); start = cur
                p.move(to: cur)
                cmd = rel ? 108 : 76  // further pairs are lineto
            case 108:  // l
                cur = point(rel); p.addLine(to: cur)
            case 104:  // h
                let x = number(); cur.x = rel ? cur.x + x : x; p.addLine(to: cur)
            case 118:  // v
                let y = number(); cur.y = rel ? cur.y + y : y; p.addLine(to: cur)
            case 99:  // c
                let c1 = point(rel), c2 = point(rel), e = point(rel)
                p.addCurve(to: e, control1: c1, control2: c2)
                cur = e; ctrl = c2
            case 115:  // s
                let c1 = lastCtrl.map { CGPoint(x: 2 * cur.x - $0.x, y: 2 * cur.y - $0.y) } ?? cur
                let c2 = point(rel), e = point(rel)
                p.addCurve(to: e, control1: c1, control2: c2)
                cur = e; ctrl = c2
            case 113:  // q
                let q = point(rel), e = point(rel)
                p.addQuadCurve(to: e, control: q)
                cur = e
            case 122:  // z
                p.closeSubpath()
                cur = start
            default:
                i += 1  // unsupported command: skip it
            }
            lastCtrl = ctrl
        }
        return p
    }
}
