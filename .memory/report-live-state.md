---
name: report-live-state
description: A completion claim is about the machine, so probe live state before writing shipped, removed, or working
metadata:
  type: feedback
---

Independent verifier correction in the old Nix setup (2026-08-08): "removed" and "shipped" were reported when only code had landed. Also 2026-08-10: a relinked Hammerspoon config kept running the old code until the app restarted.

**Why:** landed code is not a running behavior.

**How to apply:** after building Anaclast, relaunch the installed app and probe the behavior (event tap enabled, AX window frame changed, input source switched in a real text field) before reporting it works.
