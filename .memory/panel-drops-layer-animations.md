---
name: panel-drops-layer-animations
description: AppKit removes Core Animation animations from a hosted view's sublayers when the panel is ordered in, so they must be re-added once the window is visible
metadata:
  type: reference
---

Found 2026-09-23 building the now-playing island's soundwave.

- `CABasicAnimation`s added to sublayers of an `NSViewRepresentable` view were gone within a second of `orderFrontRegardless()`, whether added in `init`, `viewDidMoveToWindow` or `updateNSView`. The bars sat still at full height.
- Adding them after the panel is on screen works, and re-adding on `NSWindow.didChangeOcclusionStateNotification` when `occlusionState` contains `.visible` survives every hide and show.
- Core Animation bars cost Anaclast 0.0% CPU while playing. A SwiftUI `TimelineView` at 30 fps cost about 5%, and kept rendering while the panel was never ordered in.

**How to apply:** drive always-on decoration with Core Animation, attach animations on visibility, and verify motion by comparing several screenshots rather than one. Related: [[swiftui-scale-distorts-appkit-text-field]].
