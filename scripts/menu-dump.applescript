-- SPDX-License-Identifier: GPL-3.0-or-later
-- Prints a running app's menu bar (titles, shortcuts, checkmarks, submenus) via Accessibility.
-- Doesn't focus the app.   osascript scripts/menu-dump.applescript VChainDev
on run argv
  set procName to item 1 of argv
  tell application "System Events" to tell process procName
    set out to ""
    repeat with m in menu bar items of menu bar 1
      set out to out & "== " & (name of m) & linefeed
      try
        repeat with mi in menu items of menu 1 of m
          set out to out & my describe(mi, "   ")
          try
            repeat with sub in menu items of menu 1 of mi
              set out to out & my describe(sub, "      - ")
            end repeat
          end try
        end repeat
      end try
    end repeat
    return out
  end tell
end run

on describe(mi, indent)
  tell application "System Events"
    set n to name of mi
    if n is missing value then return indent & "---" & linefeed
    set k to ""
    try
      set c to value of attribute "AXMenuItemCmdChar" of mi
      if c is not missing value then set k to " [" & c & " mods=" & (value of attribute "AXMenuItemCmdModifiers" of mi) & "]"
    end try
    set mark to ""
    try
      if value of attribute "AXMenuItemMarkChar" of mi is not missing value then set mark to "✓ "
    end try
    set en to ""
    if not (enabled of mi) then set en to " (disabled)"
    return indent & mark & n & k & en & linefeed
  end tell
end describe
