// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI

/// The vector export (`-debugRenderVector`) is running: gradients that fade to transparent are drawn so PDF keeps
/// their transparency.
enum VectorExport {
    nonisolated(unsafe) static var active = false
}

/// A gradient fill, like `GraphicsContext.Shading.linearGradient` / `.radialGradient`, but drawn through
/// `fill(_:shaded:)` / `stroke(_:shaded:)` so the vector export can handle transparent stops. Core Graphics' PDF
/// writer drops the alpha of gradient colours (a white → clear sheen comes out solid white), so in the export a
/// gradient with any transparent stop is drawn as the same gradient made opaque, seen through a smooth alpha mask
/// (an image soft mask, which PDF keeps). In the app it is a plain SwiftUI gradient.
enum Shade {
    case linear(Gradient, start: CGPoint, end: CGPoint)
    case radial(Gradient, center: CGPoint, startRadius: CGFloat, endRadius: CGFloat)

    static func linearGradient(_ gradient: Gradient, startPoint: CGPoint, endPoint: CGPoint) -> Shade {
        .linear(gradient, start: startPoint, end: endPoint)
    }

    static func radialGradient(_ gradient: Gradient, center: CGPoint, startRadius: CGFloat, endRadius: CGFloat) -> Shade {
        .radial(gradient, center: center, startRadius: startRadius, endRadius: endRadius)
    }

    var shading: GraphicsContext.Shading {
        switch self {
        case let .linear(g, start, end): .linearGradient(g, startPoint: start, endPoint: end)
        case let .radial(g, center, r0, r1): .radialGradient(g, center: center, startRadius: r0, endRadius: r1)
        }
    }

    var gradient: Gradient {
        switch self {
        case let .linear(g, _, _), let .radial(g, _, _, _): g
        }
    }

    /// Where `p` falls along the gradient, 0…1 (clamped, like the gradient's own padding).
    func position(of p: CGPoint) -> Double {
        let t: CGFloat
        switch self {
        case let .linear(_, a, b):
            let dx = b.x - a.x, dy = b.y - a.y, len2 = dx * dx + dy * dy
            t = len2 > 0 ? ((p.x - a.x) * dx + (p.y - a.y) * dy) / len2 : 0
        case let .radial(_, c, r0, r1):
            t = r1 != r0 ? (hypot(p.x - c.x, p.y - c.y) - r0) / (r1 - r0) : 0
        }
        return Double(min(1, max(0, t)))
    }
}

extension GraphicsContext {
    func fill(_ path: Path, shaded shade: Shade, style: FillStyle = FillStyle()) {
        if VectorExport.active, let stops = Self.transparentStops(shade.gradient) {
            drawMasked(path, eoFill: style.isEOFilled, shade: shade, stops: stops)
        } else {
            fill(path, with: shade.shading, style: style)
        }
    }

    func stroke(_ path: Path, shaded shade: Shade, style: StrokeStyle) {
        if VectorExport.active, let stops = Self.transparentStops(shade.gradient) {
            drawMasked(path.strokedPath(style), eoFill: false, shade: shade, stops: stops)
        } else {
            stroke(path, with: shade.shading, style: style)
        }
    }

    func stroke(_ path: Path, shaded shade: Shade, lineWidth: CGFloat = 1) {
        stroke(path, shaded: shade, style: StrokeStyle(lineWidth: lineWidth))
    }

    private struct Stop { var location: Double; var rgb: [CGFloat]; var alpha: Double }

    /// The gradient's stops in sRGB, or nil when every stop is opaque (PDF draws those fine).
    private static func transparentStops(_ gradient: Gradient) -> [Stop]? {
        let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
        var stops = gradient.stops.sorted { $0.location < $1.location }.map { stop -> Stop in
            let cg = stop.color.resolve(in: EnvironmentValues()).cgColor
            let c = cg.converted(to: srgb, intent: .defaultIntent, options: nil)?.components ?? [0, 0, 0, 1]
            return Stop(location: Double(stop.location), rgb: Array(c.prefix(3)), alpha: Double(c.count > 3 ? c[3] : 1))
        }
        guard stops.contains(where: { $0.alpha < 0.999 }) else { return nil }
        // A fully transparent stop has no colour of its own: take its nearest visible neighbour's, so a white → clear
        // fade stays white instead of passing through black.
        for i in stops.indices where stops[i].alpha <= 0.001 {
            let visible = stops.indices.filter { stops[$0].alpha > 0.001 }
            if let j = visible.min(by: { abs($0 - i) < abs($1 - i) }) { stops[i].rgb = stops[j].rgb }
        }
        return stops
    }

    private static func alpha(_ stops: [Stop], at t: Double) -> Double {
        guard let first = stops.first, let last = stops.last else { return 1 }
        if t <= first.location { return first.alpha }
        if t >= last.location { return last.alpha }
        for (a, b) in zip(stops, stops.dropFirst()) where t <= b.location {
            let f = b.location > a.location ? (t - a.location) / (b.location - a.location) : 1
            return a.alpha + (b.alpha - a.alpha) * f
        }
        return last.alpha
    }

    /// The opaque gradient inside `path`, through an alpha mask image (about 2 px per output point, at most 1024
    /// on a side; the alpha changes smoothly, so the mask's pixels never show).
    private func drawMasked(_ path: Path, eoFill: Bool, shade: Shade, stops: [Stop]) {
        let box = path.boundingRect
        guard box.width > 0, box.height > 0 else { return }
        withCGContext { cg in
            let ctm = cg.ctm
            let scale = max(hypot(ctm.a, ctm.b), hypot(ctm.c, ctm.d), 1)
            let w = min(1024, max(4, Int((box.width * scale * 2).rounded(.up))))
            let h = min(1024, max(4, Int((box.height * scale * 2).rounded(.up))))
            var pixels = [UInt8](repeating: 0, count: w * h)
            for row in 0..<h {
                // Core Graphics puts an image's first row at the rect's maxY.
                let y = box.maxY - (CGFloat(row) + 0.5) / CGFloat(h) * box.height
                for col in 0..<w {
                    let x = box.minX + (CGFloat(col) + 0.5) / CGFloat(w) * box.width
                    let a = Self.alpha(stops, at: shade.position(of: CGPoint(x: x, y: y)))
                    pixels[row * w + col] = UInt8((min(1, max(0, a)) * 255).rounded())
                }
            }
            guard let provider = CGDataProvider(data: Data(pixels) as CFData),
                  let mask = CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: w,
                                     space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: 0),
                                     provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent),
                  let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                                            colors: stops.map { CGColor(srgbRed: $0.rgb[0], green: $0.rgb[1], blue: $0.rgb[2], alpha: 1) } as CFArray,
                                            locations: stops.map { CGFloat($0.location) })
            else { return }
            cg.addPath(path.cgPath)
            cg.clip(using: eoFill ? .evenOdd : .winding)
            cg.clip(to: box, mask: mask)
            let pad: CGGradientDrawingOptions = [.drawsBeforeStartLocation, .drawsAfterEndLocation]
            switch shade {
            case let .linear(_, start, end):
                cg.drawLinearGradient(gradient, start: start, end: end, options: pad)
            case let .radial(_, center, r0, r1):
                cg.drawRadialGradient(gradient, startCenter: center, startRadius: r0, endCenter: center, endRadius: r1, options: pad)
            }
        }
    }
}
