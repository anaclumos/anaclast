---
name: brew-bundle-cleanup-removes-mas-apps
description: Homebrew 7 `brew bundle cleanup --force` also uninstalls App Store apps missing from the Brewfile
metadata:
  type: reference
---

Checked 2026-09-23 against Homebrew 7.0.4. `Library/Homebrew/bundle/extensions/mac_app_store.rb` implements `cleanup!` with `mas uninstall`, so a Brewfile that has any `mas` line makes cleanup remove every App Store app it does not list.

**Why:** `Anaclast apply` runs cleanup from machine.json, so an App Store app installed by hand disappears on the next apply.

**How to apply:** declare every App Store app to keep in `homebrew.mas`, and read the cleanup lines in `Anaclast plan` before applying.
