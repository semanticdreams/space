---
type: subsystem
tags:
  - subsystem
  - audio
created: 2026-07-14
---

# Audio system

OpenAL/PortAudio-based positional audio playback and microphone input. Aubio bindings for FFT, pitch/onset/tempo detection, MFCC, spectral descriptors, and wavetable synthesis.

## Key files

- `src/audio.h`, `src/audio_input.h` — C++ audio engine
- `src/lua_aubio_types.h`, `src/lua_aubio_bindings.h` — aubio C++ bindings
- `assets/lua/aubio/` — Fennel audio analysis helpers

## Dependencies

- Depends on: [Core Platform](/dev/features/core-platform)
- Depended on by: [FFmpeg Video Playback](/dev/features/ffmpeg-video-playback)

## Dev notes

- [Audio](/dev/notes/audio) — audio subsystem architecture
- [Aubio](/dev/notes/aubio) — audio analysis with aubio

## See also

- [Core Platform](/dev/features/core-platform)
- [Subsystems](/dev/subsystems/)
