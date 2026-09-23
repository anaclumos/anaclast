---
name: swiftui-scale-distorts-appkit-text-field
description: Any SwiftUI scale on a view holding a TextField resizes the AppKit field, so a field focused while shrunk keeps a short, shifted line
metadata:
  type: reference
---

Measured 2026-09-23 on macOS 27 with frame captures of the notch panels. The panel content springs from about 0.28 scale to 1, and the search field gains focus as it opens. With `.scaleEffect` the focused field's caret came out 20 pt tall instead of 23 pt, and the placeholder sat 4 pt above the row center, so the icon looked low. The owner flagged it as "not aligned properly". `.visualEffect`, `.projectionEffect`, `.compositingGroup()` and `.geometryGroup()` all gave the same distortion. How big it gets depends on the scale at the moment the field editor attaches, so one panel can look fine while the other is off.

**Why:** SwiftUI applies the scale by resizing the hosted NSTextField. Its field editor lays out the line at that size, and the field keeps first responder across hide and show, so the bad line never gets laid out again.

**How to apply:** scale content that holds AppKit text through a layer transform, which is `LayerScaled` in `App/Panel.swift`: a nested `NSHostingView` whose container layer carries `sublayerTransform`. Never put `.scaleEffect` back on panel content. Check alignment with a focused, on-screen capture. An offscreen `cacheDisplay` render draws the placeholder through the cell and hides the bug.
