---
name: synthetic-input-needs-unlocked-target
description: Before posting synthetic keystrokes in a live test, prove the screen is unlocked and the intended app is frontmost, or abort
metadata:
  type: feedback
---

2026-09-23: an input-source test posted `gksrmf` keystrokes while the owner's screen was locked. `open -a TextEdit` silently did not activate, the key-focus process was loginwindow, and the characters went into the lock screen's password field (no Return was sent, so no unlock attempt). The test output looked like "switching failed", which was false.

**Why:** synthetic keys go to whatever holds key focus. On a locked or unattended Mac that can be a password field or the owner's own prompt.

**How to apply:** every live typing test first checks `CGSessionCopyCurrentDictionary()["CGSSessionScreenIsLocked"]` is absent or 0 and that `NSWorkspace.shared.frontmostApplication` is the intended app (and the AX focused element belongs to it), and exits without posting anything otherwise. Related: [[input-source-switching]].
