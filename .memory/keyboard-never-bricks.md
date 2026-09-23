---
name: keyboard-never-bricks
description: Hard invariant that a remapper failure must mean "no remap", never "no keys"
metadata:
  type: feedback
---

A remapper that exclusively seizes the keyboard and then loses its output path drops every key, including the on-screen Accessibility Keyboard (Kanata incident 2026-08-07, Karabiner Core-Service wedge 2026-08-08, both in sunghyun.nix).

**Why:** the owner cannot type a password to recover a bricked keyboard.

**How to apply:** Anaclast never seizes HID devices. It uses a session CGEventTap, which the system disables on timeout and which passes events through when Anaclast is gone, plus a `UserKeyMapping` Caps Lock remap that Anaclast clears when it quits. Never uninstall the Karabiner-Elements cask as a side effect: its uninstall script removes the shared DriverKit VirtualHIDDevice files. Retiring Karabiner is an owner-approved step of its own.
