# Audio Notes

## OpenAL device selection and PipeWire/JACK

We have seen intermittent segfaults in the PipeWire JACK shim when running
audio alongside other players (e.g. Spotify). The backtrace shows the crash
in the `pw-data-loop` thread inside `libjack.so.0` via OpenAL.

To avoid binding to the unstable JACK backend, the engine now:

- Sets `ALSOFT_DRIVERS=pulse,alsa` at startup if it is not already set.
- Prefers OpenAL devices containing `pulse`, then `pipewire`, then `alsa`.
- Allows explicit override via `SPACE_AUDIO_DEVICE`.

This keeps audio working out of the box on common Linux setups while avoiding
the PipeWire JACK shim. If you need JACK specifically (e.g. a JACK-only
system), set `ALSOFT_DRIVERS` or `SPACE_AUDIO_DEVICE` before launching.

Example overrides:

```sh
ALSOFT_DRIVERS=jack ./build/space -m main
SPACE_AUDIO_DEVICE="JACK Audio Connection Kit" ./build/space -m main
```
