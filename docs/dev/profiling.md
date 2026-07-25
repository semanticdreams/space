# Profiling the Fennel Runtime

- Set `SPACE_FENNEL_PROFILE=1` (or any truthy value) to enable the existing frame profiler that logs section timings to stdout when a frame exceeds the configured threshold.
- Run `./build/space -m prof-scene` to profile scene creation plus the first update with the flamegraph profiler. Without configuration the script writes `prof/space-scene-profile.folded`; override the destination via `SPACE_FENNEL_FLAMEGRAPH=/tmp/scene.folded` or disable the run entirely by setting it to `0`, `false`, or `off`. The output is a collapsed stack file compatible with standard flamegraph tooling like `flamegraph.pl`.
