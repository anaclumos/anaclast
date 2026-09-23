# Anaclast agent guide

Setup, layout and behavior live in [README.md](README.md). Lessons with dates live in [.memory/MEMORY.md](.memory/MEMORY.md), one file per fact.

## Commands

| Task | Command |
|---|---|
| Core tests | `make test` |
| App build | `make build` |
| Build, copy to /Applications, restart | `make install` |
| Read-only machine diff | `build/Build/Products/Release/Anaclast.app/Contents/MacOS/Anaclast plan` |

- `DEVELOPER_DIR` defaults to Xcode-beta in the Makefile. Plain `swift` or `xcodebuild` outside make needs `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer`.
- `make build` is the gate. The Xcode build runs strict region isolation checks that a bare `swiftc -typecheck` skips.

## Rules

- macOS 27 only. Use the 27 SDK directly and add no availability fallbacks ([memory](.memory/target-macos-golden-gate.md)).
- The keyboard never bricks. No HID seize. Caps Lock is mapped only while the event tap runs and is reset on quit ([memory](.memory/keyboard-never-bricks.md)).
- Never post a synthetic chord to reach a system hotkey. Call the API, or rewrite the real event inside the tap ([memory](.memory/synthesized-keys-and-system-hotkeys.md)).
- Keyboard and config logic belongs in `Core/` with a Swift Testing case. `App/` holds only the platform glue.
- Private symbols go through `PrivateFramework` in `App/PrivateAPI.swift`, and their signatures come from disassembly or source, never from a guess.
- Before any live test that posts keys, check that the screen is unlocked and the target app is frontmost ([memory](.memory/synthetic-input-needs-unlocked-target.md)).
- `Anaclast plan` is safe to run anytime. `Anaclast apply`, `make install` and anything that changes HID properties, preferences or launchd on the owner's Mac need the owner's go-ahead first.
- Before calling something done, probe the running app ([memory](.memory/report-live-state.md)).
