# Aubio Usage Guide

This project exposes aubio through Lua/Fennel submodules plus a set of Fennel helpers that compose common workflows. There is no aggregate `aubio` module; require the specific module you need.

## Module Map

Registered via `package.preload` in `src/lua_aubio.cpp`:

- `aubio/vec`: vector/matrix types + math utilities
- `aubio/spectral`: FFT/PVoc/MFCC/etc.
- `aubio/temporal`: pitch/onset/tempo/filters/resampler
- `aubio/io`: source/sink I/O
- `aubio/synth`: sampler/wavetable
- `aubio/utils`: parameters, conversions, logging, audio-input bridging

Fennel convenience helpers live under `assets/lua/aubio/helpers/` and are required as `:aubio/helpers/...` to avoid clashing with the C++ module names.

## Quick Start

### Pitch Detection (helper pipeline)

```fennel
(local aubio-vec (require :aubio/vec))
(local pitch-helper (require :aubio/helpers/pitch))

(local hop 512)
(local input (aubio-vec.FVec hop))
(local pipeline (pitch-helper.new {:method "yin"
                                   :buf 1024
                                   :hop hop
                                   :samplerate 44100}))

(pipeline:push input)
(local result (pipeline:result))
```

### Onset Detection From File

```fennel
(local aubio-stream (require :aubio/helpers/stream))
(local onset-helper (require :aubio/helpers/onset))

(local hop 512)
(local stream (aubio-stream.from-source {:uri "assets/sounds/on.wav"
                                         :hop hop}))
(local onset (onset-helper.new {:method "default"
                                :buf 1024
                                :hop hop
                                :samplerate (. stream :samplerate)}))

(local (read buf) ((. stream :iter)))
(when (> read 0)
  (onset:push buf))
((. stream :source):close)
```

### Low-Overhead Microphone Routing

```fennel
(local aubio-vec (require :aubio/vec))
(local aubio-utils (require :aubio/utils))
(local audio-input (require :audio-input))

(local input (aubio-vec.FVec 512))
(local mic (audio-input.AudioInput {:channels 1 :frames-per-buffer 512}))
(mic:start)

(local read (aubio-utils.audio-input-into-fvec mic input 512))
```

## Helper Modules

Use these helpers for common pipelines; they keep hot loops in C++ where possible.

- `aubio/helpers/vec`
  - `mixdown-equal`, `mixdown-weighted`
  - `normalize-peak`, `normalize-rms`
  - `apply-window`
- `aubio/helpers/source`
  - `stream` and `loop` iterators for `aubio/io.Source`
- `aubio/helpers/presets`
  - `voice`, `music` samplerate/buf/hop defaults
- `aubio/helpers/pitch`
  - `new` returns `:push`/`:result` with `:value` + `:confidence`
- `aubio/helpers/onset`
  - `new` returns `:push`/`:result` with `:onset` + timestamps
- `aubio/helpers/tempo`
  - `new` returns `:push`/`:result` with `:beat`, `:bpm`, `:period`
- `aubio/helpers/stream`
  - `from-source` returns `{ :iter :buffer :source :samplerate }`
  - `from-audio-input` returns `{ :iter :buffer :input :frames :channels }`

## Direct Module Usage

If you need complete control, call aubio directly from the C++ modules:

- `aubio/temporal.Pitch|Onset|Tempo` for detectors
- `aubio/io.Source|Sink` for file I/O
- `aubio/vec.FVec|FMat` for buffers
- `aubio/utils` for logging, conversions, and `audio-input-into-fvec`

## Logging Control

```fennel
(local aubio-utils (require :aubio/utils))
(local log-levels (. aubio-utils :log-levels))

(aubio-utils.log-set-level (. log-levels :err)
  (fn [level name message]
    (print (.. "aubio[" name "] " message))))

(aubio-utils.log-reset)
```

## Performance Notes

- Streaming reads and detector work are already in C++ via aubio bindings.
- Mixdown and normalization helpers call C++ `aubio/vec` functions.
- If a new helper does per-sample loops in Fennel, consider moving it into `aubio/vec`.

## Tests

Helpers and integration tests live in:

- `assets/lua/tests/test-aubio.fnl`
- `assets/lua/tests/test-aubio-helpers.fnl`
- `assets/lua/tests/test-aubio-pipelines.fnl`
- `assets/lua/tests/test-aubio-stream.fnl`

Audio input tests are gated behind `SPACE_TEST_AUDIO_INPUT` and skipped when `SPACE_DISABLE_AUDIO=1`.
