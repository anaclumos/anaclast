---
name: safari-link-is-hidden
description: /Applications/Safari.app is a hidden-flagged link into the Safari cryptex, so a scan that skips hidden files misses Safari
metadata:
  type: reference
---

Found 2026-09-23 when the owner typed "saf" and the launcher never showed Safari.

- On macOS 27, `/Applications/Safari.app` is a symlink to `../System/Cryptexes/App/System/Applications/Safari.app` with the `restricted,hidden` flags (`ls -lO`).
- `FileManager.contentsOfDirectory(... options: .skipsHiddenFiles)` drops it, and the real bundle is not under `/System/Applications`.
- The app index scans `/System/Cryptexes/App/System/Applications` as its own root. That folder holds only Safari today.

**How to apply:** when an Apple app is missing from any file-system scan, check `ls -lO` for the hidden flag before blaming search ranking. Related: [[target-macos-golden-gate]].
