---
name: input-source-switching
description: TISSelectInputSource from another process updates the menu extra but not the focused app's input context on macOS 26/27
metadata:
  type: reference
---

Observed in sunghyun.nix (2026-08, macOS 26/27): calling `TISSelectInputSource` from a process other than the focused app changes the menu-bar input indicator, but the focused app keeps typing in the old source. The Karabiner setup worked around it by firing the system "Select the previous input source" shortcut (^Space, symbolic hot key 60) through its virtual HID keyboard, gated on the current source so each tap was deterministic with exactly two enabled sources.

**Why:** Anaclast must switch input sources for L⌘ tap (ABC) and R⌘ tap (2-Set Korean) without Karabiner's virtual keyboard.

**How to apply:** verify a switching method end to end by typing into a real text field after the switch and reading the text back, not by reading `TISCopyCurrentKeyboardInputSource`. Related: [[synthesized-keys-and-system-hotkeys]].
