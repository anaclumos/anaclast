---
name: synthesized-keys-and-system-hotkeys
description: macOS 26+ drops keystrokes synthesized from a CLI before the system hotkey matcher; system hotkeys cannot be verified with synthetic keys
metadata:
  type: reference
---

Observed in sunghyun.nix (2026-08-08 and 2026-08-10, macOS 26/27): keystrokes synthesized from a CLI process never reach the WindowServer symbolic-hotkey matcher, so posting ⌘Space, ^Space or ⌃↑ does not open Spotlight, switch input source, or open Mission Control. Karabiner worked because its DriverKit virtual keyboard is real HID input.

**Why:** any Anaclast action that relies on a system shortcut must call the underlying API instead of posting the chord.

**How to apply:** prefer direct calls (SkyLight, CoreDock, login.framework, TIS) over posted chords, and verify system-hotkey behavior with a live-state probe such as `CGSIsSymbolicHotKeyEnabled`, never with synthetic keys. Related: [[input-source-switching]].
