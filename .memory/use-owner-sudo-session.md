---
name: use-owner-sudo-session
description: When the owner says they authenticated sudo in a terminal session, run root steps there instead of starting new sudo prompts
metadata:
  type: feedback
---

Owner correction, 2026-09-23. The owner said "I auth'ed sudo in tmux. Use that terminal if you need more", and the agent kept calling sudo from its own shell. Each call raised a new Touch ID prompt. The owner asked why it kept triggering Touch ID.

**Why:** every prompt pulls the owner away, and the owner had already offered a session with a live sudo timestamp.

**How to apply:** before any sudo, check whether the owner named a pre-authenticated terminal. If so, send the command to that pane with `tmux send-keys` and read the result back with `tmux capture-pane`, instead of starting a new prompt. Only ask for Touch ID when no such session exists, and batch root steps into one call. Related: [[admin-steps-run-through-sudo]].
