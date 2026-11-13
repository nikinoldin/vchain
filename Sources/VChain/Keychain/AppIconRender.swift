// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import VChainKit
import SwiftUI

/// The app icon: the BPM tag (locked at 128.0, beat 3 lit, no cable) on a flat white rounded square on the macOS icon
/// grid: an 824 px body at 100…924 of 1024 with
/// radius 185 and a soft drop shadow (offset 18, blur 18, black at 110/255). A free-form icon gets macOS 26's grey
/// tile; a body on the grid doesn't, so the bundle icon is the one icon everywhere (Finder, Dock closed and running).
/// `-debugRenderIcon <dir>` writes the iconset (scripts/make-icon.sh → assets/AppIcon.icns).
enum AppIconRender {
    /// Canvas in 1024ths: the grid's body and its corner radius.
    static let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    static let radius: CGFloat = 185
    /// The tag's metal plate as a fraction of the body's side.
    static let plate: CGFloat = 0.72
    /// The canvas side in points: the tag is drawn at app size (its plate `BPMTagView.side`), the rest scales to it.
    static let canvas: CGFloat = BPMTagView.side / plate * 1024 / body.width

    /// The iconset files: (file name, pixel size).
    static let iconset: [(String, Int)] = [16, 32, 128, 256, 512].flatMap { pt in
        [("icon_\(pt)x\(pt).png", pt), ("icon_\(pt)x\(pt)@2x.png", pt * 2)]
    }

    /// LCD elements that are only noise at icon size: "NO INPUT", the "?" and the meditating figure's ghost.
    private static let hiddenLCD: Set<String> = ["noin", "q", "sitHead", "sitTop", "sitHair", "sitSkirt", "sitLegs", "sitArms", "aura"]

    @MainActor private static func content() -> some View {
        var state = SampleData.tag()
        state.plugIn = false
        let u = canvas / 1024  // points per 1024th
        let squircle = RoundedRectangle(cornerRadius: radius * u, style: .circular)
        return ZStack(alignment: .topLeading) {
            squircle.fill(Color.black.opacity(110.0 / 255))
                .frame(width: body.width * u, height: body.height * u)
                .blur(radius: 18 * u)
                .offset(x: body.minX * u, y: (body.minY + 18) * u)
            squircle.fill(Color.white)
                .frame(width: body.width * u, height: body.height * u)
                .offset(x: body.minX * u, y: body.minY * u)
            BPMTagView(state: state, isFront: true, onRocker: {}, onSet: {}, hiddenLCD: hiddenLCD)
                .frame(width: BPMTagView.side, height: BPMTagView.side, alignment: .topLeading)
                .offset(x: (canvas - BPMTagView.side) / 2, y: (canvas - BPMTagView.side) / 2)  // the plate centred
        }
        .frame(width: canvas, height: canvas, alignment: .topLeading)
        .environment(\.colorScheme, .light)
    }

    /// The icon at `pixels` × `pixels`, rendered at that size (not downsampled).
    @MainActor static func image(pixels: Int) -> CGImage? {
        let side = canvas
        let view = content().clipped()
        let renderer = ImageRenderer(content: view)
        renderer.scale = CGFloat(pixels) / side
        renderer.isOpaque = false
        guard let cg = renderer.cgImage else { return nil }
        // ImageRenderer rounds the pixel size; redraw onto an exact canvas when it's off by one.
        if cg.width == pixels && cg.height == pixels { return cg }
        let ctx = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        ctx?.interpolationQuality = .high
        ctx?.draw(cg, in: CGRect(x: 0, y: 0, width: pixels, height: pixels))
        return ctx?.makeImage()
    }

    /// Writes every iconset size into `dir` (make it `<name>.iconset` for iconutil).
    @MainActor static func writeIconset(to dir: String) {
        let url = URL(fileURLWithPath: dir)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        for (name, px) in iconset {
            guard let cg = image(pixels: px) else { continue }
            try? NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])?
                .write(to: url.appendingPathComponent(name))
        }
    }
}
