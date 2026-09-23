---
name: do-it-covers-the-final-click
description: A named go-ahead covers its Save and confirm steps, and "don't ask" means decide open choices with the recommended default
metadata:
  type: feedback
---

Three owner corrections on 2026-09-23, same thread.

- The owner said to use the browser to reach the WeatherKit App ID setting "and do it". The agent checked the box, then stopped before Save to show a before and after and ask again. The owner replied that it was already approved and to finish the task.
- Asked which undeclared brews and casks to keep before an `apply` cleanup, the owner named a few and added "whatever needed. don't ask".
- The owner answered "both approved" to a push and to retiring Karabiner. The agent pushed the named commits, did the retirement, then asked again to push the commits that retirement produced. The owner replied that everything was already approved.

**Why:** a named instruction like "go there and do it" already is the specific yes for that one write, and a standing "finish all open items" goal with "don't ask" means the owner wants the work carried to the end, not a chain of confirmation prompts.

**How to apply:**
- Once the owner has named the exact change and told you to do it, carry it through Save and any confirmation dialog that only restates that change. Stop only if the dialog reveals a consequence the owner has not seen, and state that in the report rather than blocking on it.
- For choices inside a task the owner already approved, such as which tools a machine keeps, pick the option you would recommend, apply it and list the picks in the report.
- An approved task includes pushing the commits it produces to this repo's main. Do not ask again for a push of follow-up commits from work the owner already approved.
- This still does not widen approval to writes outside the approved work, such as other repos, issues or account changes. Related: [[report-live-state]], [[use-owner-sudo-session]].
