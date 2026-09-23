---
name: install-before-schema-edits
description: Install the build that understands a new config key before writing that key into the live config, because the running app reloads on save and alerts on a decode failure
metadata:
  type: feedback
---

2026-09-24: adding the `window` action, the owner's `config.json` was edited before the new build was installed. The running app reloads the linked file on every save, failed to decode the unknown action, logged "Anaclast kept the previous config" and raised an alert on the owner's screen until the reinstall replaced the process.

**Why:** `~/.config/anaclast/config.json` links into the repo, so editing the repo copy is editing the live config of the running app.

**How to apply:** for a schema change, run `make install` first, then edit the owner's config, then confirm with `Anaclast settings get` that the file matches the encoder byte for byte. Related: [[report-live-state]], [[anaclast-is-hardware-config-is-software]].
