---
type: feature
status: shipped
parent-goal: core-platform
tags:
  - feature
  - video
  - ffmpeg
  - in-world
created: 2026-07-14
updated: 2026-07-14
---

# FFmpeg video playback

## Summary

In-world video playback via FFmpeg decoding. Frames are decoded to GL textures and rendered on any widget that accepts textures (Image, RawImage, mesh batches). Supports loop, mute, positional audio, and extensive playback telemetry.

## Motivation

In-world video complements the browser — recorded content, tutorials, demos, and media that should exist spatially in the 3D world rather than in a flat window.

## Design

- **C++ core**: Decode thread with bounded queues, GL texture upload
- **Lua bindings**: `VideoPlayer` factory with constructor options (path, loop, muted, positional-audio, audio-gain/pitch/distance)
- **Widget integration**: `player:texture()` returns a texture usable by any widget
- **VideoWidget wrapper**: Convenience widget bundling player + display
- **Telemetry**: AV drift, queued/dropped/flushed audio chunks, decode loop iterations, clock state

## Tasks

- [x] FFmpeg decode thread with bounded queues
- [x] GL texture upload from decoded frames
- [x] Lua VideoPlayer API
- [x] Positional audio via OpenAL
- [x] VideoWidget convenience wrapper
- [x] Telemetry and soak testing

## Related

- Goal: [Core Platform](/dev/features/core-platform)
- See: [Video Playback](/dev/video-playback)
- See: [Video Playback (FFmpeg)](/dev/video-playback)
