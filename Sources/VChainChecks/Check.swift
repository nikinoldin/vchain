// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// Tiny check harness (XCTest is not available with Command Line Tools only).
enum Checks {
    nonisolated(unsafe) static var total = 0
    nonisolated(unsafe) static var failed = 0

    static func run(_ name: String, _ body: () -> Void) {
        print("-- \(name)")
        body()
    }
}

func check(_ condition: @autoclosure () -> Bool, _ label: String,
           file: StaticString = #fileID, line: UInt = #line) {
    Checks.total += 1
    if condition() {
        print("  \(label) ✓")
    } else {
        Checks.failed += 1
        print("  \(label) ✗ FAILED (\(file):\(line))")
    }
}

func checkApprox(_ a: Double, _ b: Double, tol: Double, _ label: String,
                 file: StaticString = #fileID, line: UInt = #line) {
    check(abs(a - b) <= tol, "\(label) (\(a) ≈ \(b) ± \(tol))", file: file, line: line)
}
