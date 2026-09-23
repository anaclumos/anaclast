---
name: testing-notch-panels
description: How to capture and drive the launcher and clipboard panels live; window captures show a stale collapsed island, and clipboard Return pastes into whatever app is active
metadata:
  type: reference
---

Learned 2026-09-23 while verifying the search row on macOS 27.

- `screencapture -l <window>` of an open panel returned the collapsed island while the screen showed the open launcher. Capture the screen region the panel covers with `screencapture -R` instead, and record motion with `screencapture -v -R`, which writes a frame only when the screen changes, at up to 60 per second.
- Chords posted with `CGEvent` do reach Anaclast's own event tap, so a posted Command Space opens the launcher and posted text lands in its search field. This differs from system hotkeys, which never see posted chords.
- The caret blinks, so take a burst of region captures and keep the frames where it is lit.
- Clipboard Return copies the entry, hides the panel and posts Command V to the active app. Test it against a scratch app that activates itself and holds a text field, seed throwaway entries through the pasteboard, delete them with Command Delete afterwards, and restore the pasteboard items saved before the test.
- To judge animation, track the row's pixel bounds frame by frame rather than eyeballing a montage. A one-pixel reversal is the kind of shift the owner catches.

**How to apply:** check the lock state before posting keys, and send Return only after a capture proves the typed text is in the panel. Related: [[synthetic-input-needs-unlocked-target]], [[synthesized-keys-and-system-hotkeys]], [[accessory-app-activation]].
