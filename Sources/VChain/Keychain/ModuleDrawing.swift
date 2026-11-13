// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI

// What the three module views (BPMTagView, MIDIStripView, EnergyModuleView) share besides drawing (Drawing.swift): the
// press-aware button style the hardware keys use, the controls' and modules' hit areas, and unit conversions.

/// Button style for drawn hardware keys: the label is ignored; `face` draws the key, pressed or not.
struct HardwareKeyStyle<Face: View>: ButtonStyle {
    var face: (Bool) -> Face

    func makeBody(configuration: Configuration) -> some View {
        // Its own hit shape: the faces are drawn with PartCanvas, which doesn't hit-test, so without it the key
        // (SET, Annalisa's power key) would take no clicks at all.
        face(configuration.isPressed).contentShape(Rectangle())
    }
}

/// `-debugHitAreas`: every module control draws its hit area (translucent red) so the sizes can be checked.
enum DebugHitAreas {
    nonisolated(unsafe) static var on = UserDefaults.standard.bool(forKey: "debugHitAreas")
    static let fill = Color.red.opacity(0.22), edge = Color.red.opacity(0.85)
}

extension View {
    /// A module control: hit-testable (and showing the link pointer) only while its module is in front, so a tap on a
    /// module behind still reaches the module and brings it forward. `grow` (points) enlarges the hit area past the
    /// drawn control without moving it: for a control placed by its top-left corner (`.offset`) the padded view is
    /// shifted back by the leading/top growth; for one placed by its centre (`.position`, `centered`) keep `grow` even.
    func moduleControl(isFront: Bool, label: String, grow: EdgeInsets = EdgeInsets(), centered: Bool = false) -> some View {
        self
            .padding(grow)
            .contentShape(Rectangle())
            .overlay {
                let show = DebugHitAreas.on && isFront  // only the areas that are live right now
                Rectangle().fill(show ? DebugHitAreas.fill : .clear).border(show ? DebugHitAreas.edge : .clear).allowsHitTesting(false)
            }
            .allowsHitTesting(isFront)
            .pointerStyle(isFront ? .link : nil)
            .accessibilityLabel(Text(verbatim: label))
            .offset(x: centered ? 0 : -grow.leading, y: centered ? 0 : -grow.top)
    }
}

/// A module's own hit area, the bottom layer of its view: exactly where the module is drawn (`path`, in the module's
/// frame, points), so a click on the module brings it forward and a click next to it, on its shadow or on the
/// transparent part of its frame, reaches whatever is underneath. A shape of its own instead of `.contentShape` on the
/// module (which would clip the controls sticking out of it); the module's drawings (`PartCanvas`) don't hit-test.
struct ModuleOutline: View {
    var path: Path
    var size: CGSize
    @Environment(\.keychainDetached) private var detached

    var body: some View {
        path.fill(Color.clickCatcher(detached))
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .contentShape(path)
            .accessibilityHidden(true)
    }

    /// `-debugHitAreas`: the outline in blue, on top of the module (doesn't hit-test).
    static func debug(_ path: Path, size: CGSize) -> some View {
        path.stroke(DebugHitAreas.on ? Color.blue.opacity(0.9) : .clear, lineWidth: 1)
            .background(path.fill(DebugHitAreas.on ? Color.blue.opacity(0.12) : .clear))
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

extension Path {
    /// Scaled from 1× module units to points.
    func scaled(_ s: CGFloat) -> Path { applying(CGAffineTransform(scaleX: s, y: s)) }
}

extension EdgeInsets {
    /// Insets in points from 1× module units.
    static func units(top: CGFloat = 0, leading: CGFloat = 0, bottom: CGFloat = 0, trailing: CGFloat = 0, scale: CGFloat) -> EdgeInsets {
        EdgeInsets(top: top * scale, leading: leading * scale, bottom: bottom * scale, trailing: trailing * scale)
    }
    static func all(_ v: CGFloat) -> EdgeInsets { EdgeInsets(top: v, leading: v, bottom: v, trailing: v) }
}
