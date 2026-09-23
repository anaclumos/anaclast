---
name: hid-matching-without-open
description: IOHIDManager device matching callbacks fire without IOHIDManagerOpen, so keyboard arrival needs no Input Monitoring
metadata:
  type: reference
---

Checked live 2026-09-23 on macOS 27. An IOHIDManager with keyboard matching, a registered matching callback, and run loop scheduling fires the callback once per attached keyboard without `IOHIDManagerOpen`. Opening is what needs Input Monitoring.

**Why:** `CapsRemap` re-asserts `UserKeyMapping` when a keyboard attaches, and it must not trigger a new permission prompt.

**How to apply:** never call `IOHIDManagerOpen` just to learn about device arrival. The system-level `IOHIDEventSystemClientSetProperty` already reaches new keyboards, so the re-assert is a backstop. Related: [[keyboard-never-bricks]].
