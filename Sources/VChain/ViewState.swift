// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI

/// With Command Line Tools only, `@State` resolves to a macro whose plugin ships with Xcode.
/// The property-wrapper form works; use `@ViewState` instead of `@State`.
typealias ViewState = SwiftUI.State
