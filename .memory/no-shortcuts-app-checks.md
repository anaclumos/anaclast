---
name: no-shortcuts-app-checks
description: The owner dropped confirming Siri registration through the Shortcuts app; do not open Shortcuts or read its data to verify Anaclast's actions
metadata:
  type: feedback
---

Owner ruling, 2026-09-23. After asking why the agent needed Shortcuts, the owner said "drop it".

- Anaclast does not depend on Shortcuts. The only reason to open it was to confirm that Siri lists Anaclast's App Intents.
- Proof that stands without it: `Metadata.appintents` in the installed bundle lists every intent, and the linkd audit of Anaclast's bundle ID logs no errors.
- Driving the Shortcuts window risks the owner's automations. One attempt sent typed text into the sidebar and a Return into the Automation view. No data changed, but proving that took a replay of its database history.

**Why:** the check cost more risk and time than it was worth to the owner.

**How to apply:** do not open the Shortcuts app or mine its databases to verify intents. Report Siri registration from the bundle metadata and the linkd log, and name it unconfirmed in Siri itself. Related: [[synthetic-input-needs-unlocked-target]], [[report-live-state]].
