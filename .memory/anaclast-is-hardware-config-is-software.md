---
name: anaclast-is-hardware-config-is-software
description: Anaclast ships to other people, so the owner's own apps, keys, hosts and habits live in config, never in the app's code
metadata:
  type: feedback
---

Owner ruling, 2026-09-23: "Anaclast should be a hardware, and my configs are pluggable software." The app must be flexible enough to cover the owner's use cases, but those use cases must not be hard coded.

**Why:** the app is meant to be distributed. Anything owner-specific in `App/` or `Core/` breaks for the next user and cannot be changed without a rebuild.

**How to apply:**
- Put owner-specific behavior in `config.json` or `machine.json`: apps, bundle IDs, key bindings, input sources, hosts, packages, paths.
- Code adds capabilities, such as "open an app" or "send a keystroke", not named instances of them. A command that exists for one app the owner uses belongs in config as a binding of a generic command.
- Treat any literal in code that names the owner's tools, machines or accounts as a defect to remove.
- When a feature needs a default, ship a neutral one and let config override it. Related: [[anaclast-replaces-nix-setup]].
