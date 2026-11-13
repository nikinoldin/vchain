// SPDX-License-Identifier: GPL-3.0-or-later
import VChainEngine
import SwiftUI

/// Bundled typefaces (Contents/Resources/Fonts, ATSApplicationFontsPath).
enum Brand {
    /// Big Shoulders Display (SIL OFL, Fonts/), the Energy screen's tall condensed monoline face:
    /// thin for numbers, regular for labels. It's one variable font (wght 100–900); the weight goes in
    /// as an explicit `wght` variation (`.custom(…).weight()` also moves the axis on macOS 15, but
    /// this doesn't depend on SwiftUI's family matching).
    static func monoline(_ size: CGFloat, weight: Font.Weight) -> Font {
        let descriptor = CTFontDescriptorCreateWithAttributes([
            kCTFontNameAttribute: "BigShouldersDisplay-Regular",
            kCTFontVariationAttribute: [wghtAxis: monolineWeights[weight] ?? 400],
        ] as CFDictionary)
        return Font(CTFontCreateWithFontDescriptor(descriptor, size, nil))
    }

    /// OpenType tag 'wght' as Core Text's variation-axis identifier.
    private static let wghtAxis = 0x7767_6874
    /// SwiftUI's ladder (.ultraLight is lighter than .thin) mapped onto wght 100…900.
    private static let monolineWeights: [Font.Weight: Int] = [
        .ultraLight: 100, .thin: 200, .light: 300, .regular: 400, .medium: 500,
        .semibold: 600, .bold: 700, .heavy: 800, .black: 900,
    ]
}
