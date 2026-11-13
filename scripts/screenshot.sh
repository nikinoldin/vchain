#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Capture every window of a running vChain (by pid) to <out>-<n>-<title>.png. Works for windows
# behind other apps; doesn't focus anything.   scripts/screenshot.sh <pid> <out.png>
set -euo pipefail
PID="${1:?usage: screenshot.sh <pid> <out.png>}"; OUT="${2:?usage: screenshot.sh <pid> <out.png>}"
PID="$PID" swift - <<'SWIFT' | while read -r id name; do
import CoreGraphics
import Foundation
let pid = Int(ProcessInfo.processInfo.environment["PID"]!)!
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as! [[String: Any]]
for w in list where (w[kCGWindowOwnerPID as String] as? Int) == pid && (w[kCGWindowLayer as String] as? Int ?? 0) >= 0 {
    let name = (w[kCGWindowName as String] as? String ?? "window").replacingOccurrences(of: " ", with: "-")
    print(w[kCGWindowNumber as String] as! Int, name.isEmpty ? "window" : name)
}
SWIFT
  f="${OUT%.png}-$name.png"
  screencapture -x -o -l "$id" "$f" && echo "$f"
done
