// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

public enum Segment: CaseIterable, Sendable {
    case a, b, c, d, e, f, g   // a top, b top right, c bottom right, d bottom, e bottom left, f top left, g middle
}

public enum SevenSegment {
    public static let dash: Set<Segment> = [.g]
    /// The letter C (segments a, d, e, f), for the MIDI strip's "CC n" display.
    public static let letterC: Set<Segment> = [.a, .d, .e, .f]
    /// The letter H (segments b, c, e, f, g), for the MIDI strip's "CH16" channel display.
    public static let letterH: Set<Segment> = [.b, .c, .e, .f, .g]

    public static func segments(for digit: Int) -> Set<Segment> {
        switch digit {
        case 0: return [.a, .b, .c, .d, .e, .f]
        case 1: return [.b, .c]
        case 2: return [.a, .b, .d, .e, .g]
        case 3: return [.a, .b, .c, .d, .g]
        case 4: return [.b, .c, .f, .g]
        case 5: return [.a, .c, .d, .f, .g]
        case 6: return [.a, .c, .d, .e, .f, .g]
        case 7: return [.a, .b, .c]
        case 8: return [.a, .b, .c, .d, .e, .f, .g]
        case 9: return [.a, .b, .c, .d, .f, .g]
        default: return []
        }
    }
}
