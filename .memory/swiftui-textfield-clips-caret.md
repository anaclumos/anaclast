---
name: swiftui-textfield-clips-caret
description: A 20pt SwiftUI TextField lays out its NSTextField one point shorter than the field editor, so the caret's top is clipped; the search rows use an NSTextField representable instead
metadata:
  type: reference
---

Measured 2026-09-23 on macOS 27 with a geometry lab that read the view frames directly. The owner flagged it as the caret's bottom being rounded while its top was flat.

- SwiftUI's plain `TextField` at 20pt gives its `NSTextField` a 23pt frame while the field editor and caret are 24pt, so the caret's top point falls outside the field and is clipped. `.frame(height:)`, baseline alignment and `axis: .vertical` do not change the field's height.
- A plain `NSTextField` in an `NSViewRepresentable` takes AppKit's own 24pt height, and field, editor and caret all match. That is `SearchField` in `App/SearchField.swift`. Keys arrive through `control(_:textView:doCommandBy:)` as `insertNewline:`, `moveUp:`, `moveDown:`, `cancelOperation:` and `deleteToBeginningOfLine:` for Command Delete.
- Writing the binding back into the field while the field editor holds marked text drops the syllable the IME just started. Typing 한글 commits 한 and marks ㄱ in one keystroke, and the SwiftUI update that follows would reset the field to 한. `updateNSView` skips the write while `hasMarkedText()` is true.
- `makeFirstResponder` only works once the field is in a window, so focus follows the panel's presentation counter, not the first `updateNSView`.

**How to apply:** keep the search rows on `SearchField`. Test IME changes by driving `setMarkedText` and `insertText` on the field editor, because a synthesized input source switch does not reach the focused app. Related: [[swiftui-scale-distorts-appkit-text-field]], [[input-source-switching]].
