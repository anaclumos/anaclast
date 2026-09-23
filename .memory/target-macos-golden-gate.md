---
name: target-macos-golden-gate
description: Anaclast targets macOS 27 Golden Gate only and should use its SDK features
metadata:
  type: user
---

Owner, 2026-09-23: "Build for macOS Golden Gate. They have a lot of optimized features that help us a lot." macOS 27 is named Golden Gate (announced WWDC 2026-06-08, public 2026-09-14, [apple.com/os/macos](https://www.apple.com/os/macos/), [release notes](https://developer.apple.com/documentation/macos-release-notes/macos-27-release-notes)).

**Why:** the owner's Macs all run 27, so there is no older OS to support.

**How to apply:** deployment target 27.0 everywhere. Prefer the 27 SDK's own surfaces (SwiftUI `glassEffect`, `ConcentricRectangle`, AppKit `NSGlassEffectView`) over hand-rolled vibrancy or compatibility shims. No availability checks for older macOS.
