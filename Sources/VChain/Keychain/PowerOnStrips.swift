// SPDX-License-Identifier: GPL-3.0-or-later
import VChainKit
import SwiftUI

extension ModuleGallery {
    /// `-debugRenderTagPowerOn <png>`: the BPM tag's power-on (`TagPowerOn`) as a frame strip, light and dark, ending
    /// on the live display it hands over to (settling, no tempo yet).
    static func tagPowerOnStrip() -> some View {
        let times: [Double] = [0.04, 0.12, 0.24, 0.33, 0.42, 0.51, 0.60, 0.72, 0.84, 0.96, 1.04, TagPowerOn.duration]
        let live = SampleData.tag(bpm: 0, hasTempo: false, time: 0.2)
        func row(dark: Bool) -> some View {
            HStack(alignment: .top, spacing: 18) {
                ForEach(times, id: \.self) { t in
                    VStack(spacing: 6) {
                        BPMTagView(state: live, isFront: true, onRocker: {}, onSet: {}, powerOn: TagPowerOn.frame(elapsed: t))
                            .frame(width: BPMTagView.side + 12, height: BPMTagView.side + 12, alignment: .bottomLeading)
                        Text(verbatim: t >= TagPowerOn.duration ? String(format: "%.2f s live", t) : String(format: "%.2f s", t))
                            .font(.system(size: 11, weight: .semibold)).foregroundStyle(dark ? hex(0xc9c6bf) : hex(0x3a362f))
                    }
                }
            }
            .padding(20)
            .galleryBackdrop(dark: dark)
            .environment(\.colorScheme, dark ? .dark : .light)
        }
        return VStack(spacing: 0) { row(dark: false); row(dark: true) }
    }

    /// `-debugRenderEnergyPowerOn <png>`: the Energy module's power-on self-test (`EnergyPowerOn`) as a frame strip,
    /// light and dark, ending on the live screen it hands over to.
    static func energyPowerOnStrip() -> some View {
        let times: [Double] = [0.05, 0.15, 0.25, 0.31, 0.38, 0.46, 0.55, 0.64, 0.72, 0.80, 0.90, EnergyPowerOn.duration]
        let values: [Float] = [0.53, 0.43, 0.5, 0.55, 0.55, 0.5]
        let spectrum: [Float] = (0..<24).map { (c: Int) -> Float in
            let x = Double(c)
            let tilt: Double = 1.15 - x / 36
            let wobble: Double = 0.35 + 0.65 * abs(sin(2.2 + x * 1.37))
            return Float(max(0, min(1, 0.94 * tilt * wobble)))
        }
        func row(dark: Bool) -> some View {
            VStack(alignment: .leading, spacing: 26) {
                ForEach([0, 1], id: \.self) { half in
                    HStack(alignment: .top, spacing: 40) {
                        ForEach(times[(half * 6)..<(half * 6 + 6)], id: \.self) { t in
                            VStack(spacing: 8) {
                                EnergyModuleView(values: values, enabled: Array(repeating: true, count: 6), isOn: true,
                                                 spectrum: spectrum, powerOn: EnergyPowerOn.frame(elapsed: t), isFront: true,
                                                 onPower: {}, onSet: {}, onToggle: { _ in })
                                Text(verbatim: t >= EnergyPowerOn.duration ? String(format: "%.2f s live", t) : String(format: "%.2f s", t))
                                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(dark ? hex(0xc9c6bf) : hex(0x3a362f))
                            }
                        }
                    }
                }
            }
            .padding(EdgeInsets(top: 20, leading: 50, bottom: 30, trailing: 20))
            .galleryBackdrop(dark: dark)
            .environment(\.colorScheme, dark ? .dark : .light)
        }
        return VStack(spacing: 0) { row(dark: false); row(dark: true) }
    }
}
