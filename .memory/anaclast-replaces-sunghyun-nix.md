---
name: anaclast-replaces-sunghyun-nix
description: Why Anaclast exists, its name, and the owner's scope decisions from 2026-09-23
metadata:
  type: project
---

Anaclast is the owner's Raycast-like macOS app that replaces the nix-darwin flake `anaclumos/sunghyun.nix`, which the owner wants to delete (2026-09-23). It was first named waycast; the owner renamed it Anaclast the same day because the waycast name is taken. Owner scope decisions, 2026-09-23:

- Launcher and commands, window tiling and Hyper app keys (formerly Hammerspoon), system fixes (dark toggle, Ask Siri hotkey 263 kill, Mail shortcuts), and its own clipboard history are all in Anaclast.
- Anaclast replaces Karabiner-Elements for key-level remaps, chosen after being told posted events may not reach system hotkeys. See [[synthesized-keys-and-system-hotkeys]] and [[input-source-switching]].
- Packages, defaults and dotfiles are declared in Anaclast's own config and applied by Anaclast.
- Signing uses the owner's Apple Development certificate, so the Accessibility grant survives rebuilds.
- Losing the Linux Home Manager configurations that sunghyun.nix carried is accepted ("losing Linux is fine"). Anaclast is macOS only.

**Why:** the owner wants the custom behavior without Nix.

**How to apply:** treat the sunghyun.nix README outcome ledger as the behavior spec until the repo is deleted; keep the keyboard invariant in [[keyboard-never-bricks]]; do not add Linux support.
