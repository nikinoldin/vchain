// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI

/// The BPM tag's speaker grille, centred in the bottom row: 42 × 7 at (29, 86.5) on the 100 × 100 plate (1×), drawn by
/// TagShell. Three rows of drilled holes in a hex pattern, each with a small countersink; light from the top left.
enum TagGrille {
    static let rect = CGRect(x: 29, y: 86.5, width: 42, height: 7)

    static func draw(ctx: GraphicsContext, dark: Bool) {
        let rect = Self.rect
        let pitch: CGFloat = 2.15, rowGap: CGFloat = 2.05
        // Centred in `rect`: outer rows `cols` holes, the middle row one fewer, offset by half a pitch.
        let cols = Int(((rect.width - 2.1) / pitch).rounded(.down)) + 1
        for row in 0..<3 {
            let y = rect.midY + CGFloat(row - 1) * rowGap
            let n = row == 1 ? cols - 1 : cols
            for i in 0..<n {
                let x = rect.midX + (CGFloat(i) - CGFloat(n - 1) / 2) * pitch
                let c = CGPoint(x: x, y: y)
                func disc(_ r: CGFloat) -> Path { Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)) }
                // countersink: shaded top left, lit bottom right
                ctx.fill(disc(0.92), shaded: .linearGradient(
                    Gradient(colors: [.black.opacity(dark ? 0.5 : 0.35), .white.opacity(dark ? 0.2 : 0.6)]),
                    startPoint: CGPoint(x: c.x - 0.6, y: c.y - 0.75), endPoint: CGPoint(x: c.x + 0.6, y: c.y + 0.75)))
                ctx.fill(disc(0.58), with: .color(hex(0x0d0e10)))
                ctx.insetShadow(in: disc(0.58), dy: -0.18, color: hex(0x8d9196).opacity(dark ? 0.25 : 0.4))
            }
        }
    }
}
