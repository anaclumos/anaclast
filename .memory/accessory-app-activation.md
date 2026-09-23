---
name: accessory-app-activation
description: A launchd-started accessory app is refused by NSApp.activate(); windows need activateIgnoringOtherApps and text fields need a main menu Edit menu
metadata:
  type: reference
---

Measured live on 2026-09-23.

- Anaclast runs as an accessory app started by its login agent. Opening Settings from the launcher left the window behind the frontmost app with gray traffic lights. `NSApp.activate()` is cooperative, and the macOS 27 SDK header says the framework does not guarantee activation. `activate(ignoringOtherApps: true)` activates regardless and is only marked to-be-deprecated, so it builds without a warning.
- A scratch process launched from a shell does not reproduce the refusal, because a freshly launched app counts as active. Test activation in the installed app.
- With no main menu, Command A, C, V, X and Z do nothing in any text field. An Edit menu set as `NSApp.mainMenu` fixes it, and an accessory app still shows no menu bar.
- A posted Command V goes to whichever window is key. The clipboard panel stays key while its hide animation runs, so the paste must post after the panel orders out.

**How to apply:** route window presentation through `NSApp.bringForward()`, keep the Edit menu, and post synthetic keys only after Anaclast's own panels are gone. Related: [[synthetic-input-needs-unlocked-target]], [[synthesized-keys-and-system-hotkeys]].
