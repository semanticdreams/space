# In-World Video Playback (FFmpeg)

This document describes the current FFmpeg video playback integration end-to-end:
implementation architecture, Lua API and widget usage, telemetry, testing, operations, and targeted next improvements.

## Goals

- Decode video frames and expose them as regular engine textures.
- Support playback in arbitrary widgets that consume textures.
- Keep A/V clocking stable with explicit observability.
- Fail loudly when required dependencies/features are unavailable.

## Build and Runtime Requirements

Enable FFmpeg integration with `SPACE_ENABLE_FFMPEG=ON` (default in this repo), and install:

- `ffmpeg`
- `libavcodec-dev`
- `libavformat-dev`
- `libavutil-dev`
- `libswscale-dev`
- `libswresample-dev`

When unavailable at build time, the Lua `video` module exposes:

- `video.available = false`
- `video.missing-reason = "..."`

Attempting to construct `VideoPlayer` fails with a clear runtime error.

## Architecture

## C++ Core

- `src/video_player.h`
- `src/video_player.cpp`
- `src/video_telemetry.h`

`VideoPlayer` owns:

- Decode thread (`decode_loop`) for FFmpeg demux/decode.
- Bounded queues for decoded video frames and audio chunks.
- GL texture upload path (`upload_frame`).
- Playback state (`play/pause/seek/stop`, `position`, loop/end handling).
- Audio streaming source lifecycle via engine `Audio`.
- Thread-safe telemetry for status inspection.

`VideoManager` owns:

- Registered `VideoPlayer` instances.
- Engine-wide per-frame `update_all` and lifecycle coordination.
- Audio backend reset fanout to players.

## Lua Bindings

- `src/lua_video.h`
- `src/lua_video.cpp`

Binding model:

- `require :video` returns `VideoPlayer` factory + availability flags.
- `VideoPlayer` is engine-owned and constructed via options table.
- `status()` returns structured playback + telemetry fields.

## Widget Integration

- `assets/lua/video-widget.fnl`

The integration path is texture-first:

1. Create a `VideoPlayer`.
2. Use `player:texture()` anywhere a texture is accepted (`Image`, `RawImage`, etc.).
3. Let `VideoManager` drive updates each frame globally.

This avoids coupling playback lifecycle to individual widget update hooks and allows arbitrary widget placement/composition.

## Lua API

## Constructor

```fennel
(local Video (require :video))
(local player
  (Video.VideoPlayer {:path "lua/tests/data/test-videos/01_baseline_h264_with_audio.mp4"
                      :loop true
                      :autoplay true
                      :muted false}))
```

Options:

- `:path` (required)
- `:loop` (optional, default `false`)
- `:autoplay` (optional, default `true`)
- `:muted` (optional, default `false`)

## Methods

- `play()`
- `pause()`
- `stop()`
- `seek(seconds)`
- `update(dt-ms)` (normally manager-driven)
- `drop()`
- `ready()`
- `ended()`
- `playing()`
- `duration()`
- `position()`
- `texture()`
- `status()`

## Status Telemetry Fields

Playback state:

- `ready`
- `ended`
- `playing`
- `has-error`
- `error`

Clocking:

- `clock-seconds`
- `has-audio-clock`
- `av-drift-seconds`
- `max-av-drift-seconds`
- `recent-max-av-drift-seconds`
- `av-drift-window-seconds`

Queue/backpressure:

- `queued-audio-chunks`
- `dropped-audio-chunks` (queue-overflow drops)
- `flushed-audio-chunks` (explicit seek/stop flushes)
- `dropped-video-frames`

Decode-thread telemetry:

- `decode-loop-iterations`
- `decode-wait-ms`

Audio presence:

- `audio-available`
- `audio-active`

## Telemetry Semantics

- `dropped-audio-chunks` means chunks evicted due to bounded queue pressure.
- `flushed-audio-chunks` means chunks intentionally discarded on control operations (`seek`, `stop`).
- `recent-max-av-drift-seconds` is the max absolute drift seen within a rolling window (`av-drift-window-seconds`, currently 2.0).
- `decode-wait-ms` is cumulative decode-thread wait time while buffers are full (useful backpressure signal, monotonic counter).
- `decode-loop-iterations` is cumulative decode-loop iterations (liveness/throughput signal, monotonic counter).

## Tests

## Lua/Fennel

- `assets/lua/tests/test-video.fnl`
- `assets/lua/tests/test-video-widget.fnl`
- `assets/lua/tests/test-video-soak.fnl`

Coverage includes:

- Decode-to-texture readiness.
- Seek/end/loop behavior.
- Pause/resume stability.
- Multi-player concurrency.
- Structured status field contracts.
- Audio flush telemetry on seek.
- Decode telemetry monotonicity under buffered and consuming phases.
- Audio drift budget checks (when audio clock available).

## Native C++

- `tests/test_video_telemetry.cpp`

Deterministic checks:

- Drift window and absolute max math (`VideoAvDriftTracker`).
- Dropped/flushed chunk counter correctness (`VideoAudioChunkCounters`).

## Soak Validation

Run soak:

```bash
SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tests.test-video-soak:main
```

Defaults:

- Duration: `600s`
- Poll sleep: `0.01s`
- Max recent drift budget: `0.35s`
- Decode wait budget: disabled unless configured

Override knobs:

- `SPACE_VIDEO_SOAK_SECONDS`
- `SPACE_VIDEO_SOAK_SLEEP_SECONDS`
- `SPACE_VIDEO_SOAK_MAX_RECENT_DRIFT_SECONDS`
- `SPACE_VIDEO_SOAK_MAX_DECODE_WAIT_MS`

Example:

```bash
SPACE_ASSETS_PATH=$(pwd)/assets \
SPACE_VIDEO_SOAK_SECONDS=120 \
SPACE_VIDEO_SOAK_SLEEP_SECONDS=0.01 \
SPACE_VIDEO_SOAK_MAX_RECENT_DRIFT_SECONDS=0.25 \
SPACE_VIDEO_SOAK_MAX_DECODE_WAIT_MS=5000 \
./build/space -m tests.test-video-soak:main
```

Note: `SPACE_DISABLE_AUDIO=1` is still useful for deterministic CI/sandbox runs, but audio drift realism requires audio enabled.

## Known Constraints

- Decode and queue metrics are cumulative; interpret them as trend counters, not instantaneous gauges.
- `decode-wait-ms` can increase during healthy operation when decoder is ahead and waiting on bounded queues.
- Audio-clock strictness in tests is gated to avoid false failures when audio is disabled/unavailable.

## Potential Improvements

- Add instantaneous/rate telemetry (per-second deltas for queue pressure and decode wait).
- Add explicit decode stall detector (`no iterations advanced over N ms while playing`).
- Add live in-world telemetry panel for active players.
- Add targeted audio-device reset/replug scripted validation.
- Add adaptive queue sizing based on stream properties and measured jitter.
