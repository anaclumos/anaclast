---
name: testing-now-playing
description: How to put a silent track in Now Playing to test the island without playing the owner's media
metadata:
  type: reference
---

Worked 2026-09-23.

- An unbundled command line binary never becomes the Now Playing app, even with `MPNowPlayingInfoCenter` set and audio playing.
- A minimal `.app` bundle with its own bundle ID works once it also enables `MPRemoteCommandCenter` play, pause and toggle handlers and plays audio through `AVAudioPlayer`. A file of pure digital silence at normal volume is inaudible and still counts.
- `media-control get` shows which app MediaRemote picked, which confirms the test track took over.

**How to apply:** never resume the owner's player to test media features. Publish a silent track from a scratch bundle, then confirm with `media-control get`. Related: [[report-live-state]].
