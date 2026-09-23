---
name: dotenvx-2-dropped-p-shorthand
description: dotenvx 2.x removed the -p alias for --plain on `set`; old scripts silently write a wrong key
metadata:
  type: reference
---

Checked 2026-09-23. dotenvx 1.66 lists `-p, --plain` under `set`. dotenvx 2.30 lists only `--plain`. With 2.30, `dotenvx set -f FILE -p --plain -- KEY VALUE` writes `-p="--"` into the file and exits 0, so the failure is silent.

**Why:** `config/dotfiles/zsh/bin/secrets-set` carried `-p --plain` from sunghyun.nix, and machine.json installs dotenvx 2.x from the latest release.

**How to apply:** pass only `--plain`, which works on both majors. After any dotenvx major bump, check `dotenvx set --help` before trusting a script's flags.
