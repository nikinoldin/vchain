// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI

/// The BPM tag's SET button (opens Settings › Beat-o-Matic): a tall moulded black key with fine grip ribs, seated in a
/// slot low on the tag's right edge below the rocker and jack, in the rocker's black plastic, with "SETTINGS" printed in
/// the gutter beside it like the rocker's I/O (TagShell). Drawn over the plate's edge so the Button can show the press;
/// its frame is the generous hit area.
struct TagSetButton: View {
    var pressed: Bool
    var scale: CGFloat

    /// The button's span on the right edge (1× plate units).
    static let span: ClosedRange<CGFloat> = 62...83
    /// The hit area, 1× units: 16 wide (from 6 inside the edge) and the button's span ± 5.
    static let hitArea = CGRect(x: 94, y: span.lowerBound - 5, width: 16, height: span.upperBound - span.lowerBound + 10)

    var body: some View {
        let hit = Self.hitArea, span = Self.span
        PartCanvas(size: hit.size, bleed: 1, scale: scale) { ctx in
            // Local coordinates: plate edge at x = 6, the button's top at y = 5.
            let edge: CGFloat = 100 - hit.minX, top = span.lowerBound - hit.minY, h = span.upperBound - span.lowerBound
            Self.mouldedKey(&ctx, edge: edge, top: top, h: h, pressed: pressed)
        }
        .accessibilityHidden(true)
    }

    /// The moulded black key: seated in a dark slot cut into the case edge, rounded ends, a convex face with a long
    /// specular line and fine grip ribs, a fine chamfer, the rocker's lit outer edge.
    private static func mouldedKey(_ ctx: inout GraphicsContext, edge: CGFloat, top: CGFloat, h: CGFloat, pressed: Bool) {
        // The slot in the case (on the plate's edge): lit lip below, black opening, shadow under its top.
        let slot = Path(roundedRect: CGRect(x: edge - 1.2, y: top - 1.0, width: 2.0, height: h + 2.0), cornerRadius: 0.9, style: .continuous)
        ctx.fill(slot.offsetBy(dx: 0, dy: 0.3), with: .color(.white.opacity(0.45)))
        ctx.fill(slot, with: .color(hex(0x050506)))
        ctx.insetShadow(in: slot, dy: 0.6, blur: 0.5, color: .black.opacity(0.9))
        let out: CGFloat = 3.4 - (pressed ? 1.0 : 0)
        let cap = CGRect(x: edge - 0.7, y: top, width: out + 0.7, height: h)
        let r: CGFloat = 1.45
        let body = Path(roundedRect: cap, cornerRadius: r, style: .continuous)
        ctx.dropShadow(of: cap, radius: r, dx: 0.2, dy: 0.7, blur: 1.0, color: .black.opacity(0.45))
        // Convex across its depth: dark at the case, a sheen past the middle, rolling off at the face.
        ctx.fill(body, shaded: .linearGradient(
            Gradient(stops: [.init(color: hex(0x0b0b0c), location: 0), .init(color: hex(0x242427), location: 0.3),
                             .init(color: hex(0x48484d), location: 0.62), .init(color: hex(0x1d1d1f), location: 0.88),
                             .init(color: hex(0x101011), location: 1)]),
            startPoint: CGPoint(x: cap.minX, y: 0), endPoint: CGPoint(x: cap.maxX, y: 0)))
        // Rounded ends: the top end catches the light, the bottom end turns away.
        ctx.fill(body, shaded: .linearGradient(
            Gradient(stops: [.init(color: .white.opacity(0.12), location: 0), .init(color: .clear, location: 0.12),
                             .init(color: .clear, location: 0.85), .init(color: .black.opacity(0.45), location: 1)]),
            startPoint: CGPoint(x: 0, y: cap.minY), endPoint: CGPoint(x: 0, y: cap.maxY)))
        var inside = ctx
        inside.clip(to: body)
        let mid = CGPoint(x: 0, y: cap.midY)
        // Fine moulded ribs, fading towards the ends.
        var y = cap.minY + 2.3
        while y < cap.maxY - 2.3 {
            let fade = Double(1 - abs(y - mid.y) / (h / 2)) * 0.9 + 0.1
            inside.fill(Path(CGRect(x: cap.minX + 0.9, y: y, width: cap.width, height: 0.32)), with: .color(.black.opacity(0.55 * fade)))
            inside.fill(Path(CGRect(x: cap.minX + 0.9, y: y + 0.32, width: cap.width, height: 0.2)), with: .color(.white.opacity(0.14 * fade)))
            y += 0.95
        }
        // A long soft specular line along the convex face.
        let sx = cap.minX + cap.width * 0.6
        inside.stroke(Path { p in p.move(to: CGPoint(x: sx, y: cap.minY + 1.3)); p.addLine(to: CGPoint(x: sx, y: cap.maxY - 1.3)) },
                      shaded: .linearGradient(Gradient(colors: [.clear, .white.opacity(0.42), .white.opacity(0.3), .clear]),
                                            startPoint: CGPoint(x: 0, y: cap.minY), endPoint: CGPoint(x: 0, y: cap.maxY)), lineWidth: 0.4)
        // Fine chamfer all round, and the rocker's lit outer edge.
        ctx.stroke(Path(roundedRect: cap.insetBy(dx: 0.18, dy: 0.18), cornerRadius: r - 0.18, style: .continuous), shaded: .linearGradient(
            Gradient(colors: [.white.opacity(0.3), .white.opacity(0.06), .black.opacity(0.5)]),
            startPoint: CGPoint(x: 0, y: cap.minY), endPoint: CGPoint(x: 0, y: cap.maxY)), lineWidth: 0.3)
        ctx.stroke(Path { p in
            p.move(to: CGPoint(x: cap.maxX - r, y: cap.minY + 0.22))
            p.addQuadCurve(to: CGPoint(x: cap.maxX - 0.22, y: cap.minY + r), control: CGPoint(x: cap.maxX - 0.22, y: cap.minY + 0.22))
            p.addLine(to: CGPoint(x: cap.maxX - 0.22, y: cap.maxY - r))
        }, with: .color(.white.opacity(0.35)), lineWidth: 0.4)
        ctx.stroke(body, with: .color(.black.opacity(0.6)), lineWidth: 0.15)
    }
}
