// SPDX-License-Identifier: GPL-3.0-or-later
import VChainKit
import SwiftUI

// The MIDI strip's parts: where they sit (StripGeometry), the modules' eject keys and the right cap's add button.

/// Where the parts sit for a pose, 1×: the right cap at the frame's right edge, everything else from it.
struct StripGeometry {
    static let leftCap = KeyringGeometry.stripLeftCap, channel = KeyringGeometry.stripChannel, rightCap = KeyringGeometry.stripRightCap
    static let height = KeyringGeometry.stripHeight
    /// The SET key's top: directly under the slide switch (9…26).
    static let setTop: CGFloat = 29
    /// The channel LCD's centre on the left cap, below SET.
    static let channelLCDCenterY: CGFloat = 82.5
    /// The MIDI OUT socket's axis on the left cap's left edge, beside the channel LCD (the head spans ≈ 71…81, the
    /// strain relief ends at ≈ 87 where the corner starts).
    static let midiOutY: CGFloat = 76
    var width: CGFloat
    var pose: StripEdit.Pose

    var rightX: CGFloat { width - Self.rightCap }
    func moduleX(_ x: Double) -> CGFloat { rightX + CGFloat(x) * Self.channel }
    var leftX: CGFloat { moduleX(pose.leftEdge) - Self.leftCap }
}

/// A module's eject key: a small plain black plastic key sticking `out` 1× units out of its top edge through a
/// slot, `width` wide. Pressed it sinks in; locked (2 bands, nothing to eject) it sits nearly flush, greyed.
struct EjectKey: View {
    var pressed = false
    var locked = false
    var scale: CGFloat = HardwareScale.app

    static let width: CGFloat = 11, out: CGFloat = 3
    /// Extra hit area (≈ 27 × 19 units, 40 × 28 pt): the module's whole width, so neighbours' areas just meet, well
    /// above the edge and a little over the face (the range LCD isn't a control).
    static let hitPadding = EdgeInsets(top: 10, leading: 8, bottom: 6, trailing: 8)

    var body: some View {
        PartCanvas(size: CGSize(width: Self.width, height: Self.out), bleed: 1.5, scale: scale) { ctx in
            Self.draw(ctx, pressed: pressed, locked: locked)
        }
        .accessibilityHidden(true)
    }

    /// Drawn with its slot's top-left at (0, 0) and the module's top edge at y = `out`.
    static func draw(_ ctx: GraphicsContext, pressed: Bool = false, locked: Bool = false) {
        let base = out
        let o: CGFloat = locked ? 1 : pressed ? 1.7 : out
        let key = cornerPath(CGRect(x: 0, y: base - o, width: width, height: o), 1.2, 1.2, 0, 0)
        var shadow = ctx
        shadow.addFilter(.blur(radius: 0.6))
        shadow.fill(key.offsetBy(dx: 0, dy: 0.5), with: .color(.black.opacity(0.25)))
        ctx.fill(key, shaded: .linearGradient(Gradient(colors: locked ? [hex(0x5c5c60), hex(0x48484b)] : [hex(0x4a4a4e), hex(0x1c1c1e)]),
                                            startPoint: CGPoint(x: 0, y: base - o), endPoint: CGPoint(x: 0, y: base)))
        var face = ctx
        face.clip(to: key)
        face.fill(Path(CGRect(x: 0, y: base - o, width: width, height: 0.45)), with: .color(.white.opacity(locked ? 0.1 : 0.22)))
        face.fill(Path(CGRect(x: 0, y: base - o, width: 0.45, height: o)), with: .color(.white.opacity(locked ? 0.06 : 0.13)))
        // The slot in the plastic the key comes out of.
        ctx.fill(Path(roundedRect: CGRect(x: -0.5, y: base - 0.45, width: width + 1, height: 0.8), cornerRadius: 0.4),
                 with: .color(.black.opacity(0.6)))
    }
}

/// The right cap's add button: a raised polished bezel ring
/// in the plastic, a thin dark gap, and inside it a slightly convex cap with a spun (conic) brushed-chrome face
/// that stands proud of the bezel: a visible side wall and a soft shadow. Pressed it sinks to about a third of its
/// height; locked (8 bands) it sits flush and dimmed, still a button. The frame is the bezel (`radius` × 2).
struct AddButton: View {
    var pressed = false
    var locked = false
    var scale: CGFloat = HardwareScale.app

    static let radius: CGFloat = 4.5
    /// Centre on the right cap, 1× (cap-local: x from its left edge).
    static let center = CGPoint(x: 8.5, y: 91)
    /// Where taps count: a circle round it (28 pt across), reaching a little over the pride flag sticker above (which ends at ≈ 85).
    static let hitRadius: CGFloat = 9.5

    /// Spun metal: light rays round the centre.
    private static let spun = [0xf4f5f6, 0xa7abaf, 0xe6e8ea, 0x7f8388, 0xf0f1f2, 0xb4b7ba, 0xdcdee0, 0x8c9095,
                               0xf4f5f6, 0xadb0b4, 0xe9ebec, 0x84888d, 0xf4f5f6].map { hex($0) }

    var body: some View {
        let r = Self.radius
        PartCanvas(size: CGSize(width: r * 2, height: r * 2), bleed: 2, scale: scale) { ctx in
            let c = CGPoint(x: r, y: r)
            func disc(_ radius: CGFloat, at p: CGPoint) -> Path {
                Path(ellipseIn: CGRect(x: p.x - radius, y: p.y - radius, width: radius * 2, height: radius * 2))
            }
            let gapR: CGFloat = 3.75, capR: CGFloat = 3.3
            // How far the cap stands proud: its top face sits up and a little left of its foot (lit from the top left).
            let height: CGFloat = locked ? 0.12 : pressed ? 0.4 : 1.1
            let top = CGPoint(x: c.x - height * 0.3, y: c.y - height)

            // Raised polished bezel: a shadow below it on the plastic, then a rounded ring lit top left, dark bottom right.
            var drop = ctx
            drop.addFilter(.blur(radius: 0.5))
            drop.fill(disc(r, at: CGPoint(x: c.x + 0.2, y: c.y + 0.55)), with: .color(.black.opacity(0.3)))
            var bezel = Path()
            bezel.addPath(disc(r, at: c))
            bezel.addPath(disc(gapR, at: c))
            ctx.fill(bezel, shaded: .linearGradient(Gradient(colors: [hex(0xfbfbfc), hex(0xc4c7cb), hex(0x7e8287)]),
                                                  startPoint: CGPoint(x: c.x - r, y: c.y - r), endPoint: CGPoint(x: c.x + r, y: c.y + r)),
                     style: FillStyle(eoFill: true))
            var bevel = ctx
            bevel.clip(to: bezel, style: FillStyle(eoFill: true))
            bevel.stroke(disc(r - 0.35, at: CGPoint(x: c.x - 0.15, y: c.y - 0.15)), with: .color(.white.opacity(0.7)), lineWidth: 0.3)
            ctx.stroke(disc(r, at: c), with: .color(.black.opacity(0.35)), lineWidth: 0.2)

            // The thin dark gap the cap moves in.
            ctx.fill(disc(gapR, at: c), with: .color(hex(0x1c1d1f)))

            // Soft shadow of the raised cap down-right in the gap.
            var shadow = ctx
            shadow.clip(to: disc(gapR, at: c))
            shadow.addFilter(.blur(radius: 0.4))
            shadow.fill(disc(capR, at: CGPoint(x: c.x + 0.3 + height * 0.3, y: c.y + 0.35 + height * 0.5)),
                        with: .color(.black.opacity(locked ? 0.2 : 0.55)))

            // Side wall: from the cap's foot up to its top face, darker turned metal.
            let wall = disc(capR, at: c).union(disc(capR, at: top))
            ctx.fill(wall, shaded: .linearGradient(Gradient(colors: [hex(0xb9bcc0), hex(0x60646a)]),
                                                 startPoint: CGPoint(x: c.x - capR, y: c.y - capR), endPoint: CGPoint(x: c.x + capR, y: c.y + capR)))

            // Face: spun brushed chrome, slightly convex (lighter towards the top left, darker round the lower right rim).
            let face = disc(capR, at: top)
            ctx.fill(face, with: .conicGradient(Gradient(colors: Self.spun), center: top, angle: .degrees(20)))
            var shade = ctx
            shade.clip(to: face)
            shade.fill(face, shaded: .radialGradient(
                Gradient(stops: [.init(color: .white.opacity(0.35), location: 0), .init(color: .white.opacity(0), location: 0.5),
                                 .init(color: .black.opacity(0.28), location: 1)]),
                center: CGPoint(x: top.x - 1, y: top.y - 1.1), startRadius: 0, endRadius: capR * 2.1))
            if locked { shade.fill(face, with: .color(hex(0x6c7075).opacity(0.35))) }
            ctx.stroke(face, with: .color(.white.opacity(locked ? 0.25 : 0.55)), lineWidth: 0.2)
            ctx.stroke(disc(capR, at: top), with: .color(.black.opacity(0.25)), lineWidth: 0.12)
        }
        .accessibilityHidden(true)
    }
}
