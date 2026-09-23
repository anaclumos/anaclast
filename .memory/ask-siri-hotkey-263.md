---
name: ask-siri-hotkey-263
description: Symbolic hotkey 263 (⌘⇧Space Ask Siri about window) re-enables itself live; kill it on launch, every 60 s and on wake
metadata:
  type: reference
---

Symbolic hot key 263 (`screenshots.ask-siri-active-window`, key 49, modifiers 1179648) steals ⌘⇧Space from 1Password Quick Access. Writing `enabled = false` into `com.apple.symbolichotkeys` `AppleSymbolicHotKeys` and running `activateSettings -u` is honored at login, but Siri re-enables 263 live afterwards (observed 2026-08-10: plist disabled while `CGSIsSymbolicHotKeyEnabled(263)` returned true).

**Why:** a one-shot fix silently regresses.

**How to apply:** read-modify-write only entry 263 in the dictionary, never replace the whole `AppleSymbolicHotKeys` dictionary (that wipes every other system shortcut). Also probe with `CGSIsSymbolicHotKeyEnabled` and re-kill with `CGSSetSymbolicHotKeyEnabled` on launch, every 60 s, and on wake or unlock.
