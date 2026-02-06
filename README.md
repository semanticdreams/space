# space

[![.github/workflows/test.yml](https://github.com/semanticdreams/space/actions/workflows/test.yml/badge.svg?branch=main)](https://github.com/semanticdreams/space/actions/workflows/test.yml)
[![.github/workflows/build.yml](https://github.com/semanticdreams/space/actions/workflows/build.yml/badge.svg?branch=)](https://github.com/semanticdreams/space/actions/workflows/build.yml)
[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](https://opensource.org/license/gpl-3-0)

Check out the <a href="https://semanticdreams.com/projects/space/" target="_blank">docs</a> for more information.

## Setup

<!--
### AppImage for Linux

*Tested on: Pop!_OS 22.04 LTS*
-->

### Build from source

*Tested on: Pop!_OS 22.04 LTS*

<!-- CI_DEPS_START -->
```
sudo apt install cmake libsdl2-dev libbullet-dev libglm-dev libopenal-dev libepoxy-dev portaudio19-dev libvterm-dev libnotify-dev libcurl4-openssl-dev libzmq3-dev cargo libaubio-dev libboost-dev
make build
make run
```
<!-- CI_DEPS_END -->

To run the app directly, use `./build/space -m main`.

The Matrix FFI library (`ffi/matrix`) is built by default and requires `cargo`. To skip it, configure
with `-DSPACE_BUILD_MATRIX=OFF` (e.g. `make cmake` then `cmake -DSPACE_BUILD_MATRIX=OFF ..`).

Wallet-core integration is disabled by default. Enable it by configuring with `-DSPACE_ENABLE_WALLET_CORE=ON`
(e.g. `make cmake` then `cmake -DSPACE_ENABLE_WALLET_CORE=ON ..`).

## Remote Control (Debugging)

Run the app with a ZeroMQ endpoint to evaluate Fennel code inside the live process:

```
SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m main --remote-control=ipc:///tmp/space-rc.sock
```

Send code from another process using the bundled Fennel client:

```
./build/space -m tools.remote-control-client:main -- --endpoint ipc:///tmp/space-rc.sock -c "(+ 1 2)"
```

This executes in `_G` (so `app`, `logging`, etc. are available) and replies with `ok ...` or `error ...`.
Only enable this on trusted machines; it executes arbitrary code in the running app.

Async results are supported via the `remote_control` helper exposed to the eval environment:

```
;; returns a request id immediately
(local id (remote_control.create))
(app.engine.events.window-resized:connect
  (fn [e]
    (remote_control.resolve id {:width e.width :height e.height})))
id
```

Poll from a client:

```
./build/space -m tools.remote-control-client:main -- --endpoint ipc:///tmp/space-rc.sock \
  -c "(remote_control.poll \"<id>\")"
```

To exercise the async flow against a live app, run the heavy test script:

```
scripts/remote-control-heavy.sh ipc:///tmp/space-rc.sock
```

## Terminal widget

- Terminal sessions spawn `/bin/sh` by default; override with `SPACE_TERMINAL_PROGRAM` (whitespace-split) such as `SPACE_TERMINAL_PROGRAM="bash -l" make run`.
- In sandboxed environments where a PTY cannot be created, the widget renders a placeholder grid with a status banner and leaves scrollback navigation disabled so the UI stays stable.

## E2E Snapshot Tests

- Run the full suite with `SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets make test-e2e`.
- Update goldens with `SPACE_SNAPSHOT_UPDATE=name1,name2 SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets make test-e2e`.
- Individual tests can be run via `./build/space -m tests.e2e.<module>:main` (e.g. `tests.e2e.test-image:main`).
- Snapshot images live in `assets/lua/tests/data/snapshots/` and should be inspected directly when adding/debugging tests.

## Contribute

Create a [discussion here on GitHub](https://github.com/semanticdreams/space/discussions). Join the community on [Matrix](https://matrix.to/#/#semanticdreams42:matrix.org).

## Profiling the Fennel Runtime

- Set `SPACE_FENNEL_PROFILE=1` (or any truthy value) to enable the existing frame profiler that logs section timings to stdout when a frame exceeds the configured threshold.
- Run `./build/space -m prof-scene` to profile scene creation plus the first update with the flamegraph profiler. Without configuration the script writes `prof/space-scene-profile.folded`; override the destination via `SPACE_FENNEL_FLAMEGRAPH=/tmp/scene.folded` or disable the run entirely by setting it to `0`, `false`, or `off`. The output is a collapsed stack file compatible with standard flamegraph tooling like `flamegraph.pl`.
- Run `./build/space -m prof-object-browser-drag` (or `make prof target=object-browser-drag`) to profile the Movables-driven drag loop for the object-browser dialog. The script reconfigures the scene to focus on the widget, simulates a long drag path, and records stacks to `prof/object-browser-drag.folded` by default.
- Run `./build/space -m prof-scroll-inputs` (or `make prof target=scroll-inputs`) to profile scrolling a list of 100 multiline input widgets (100 lines each) from top to bottom, writing to `prof/scroll-inputs.folded` by default.
- After running a profiler script, generate SVG/PNG visualizations with `make prof target=scene` (or call `python3 scripts/prof.py scene` directly). The helper ensures folded, SVG, and PNG files (`prof/<target>.folded|.svg|.png`) live together in the `prof/` directory, prints a concise textual summary of the heaviest stacks/leaf frames, and supports any `prof-*` module. Pass additional args via `make prof target=scene args="--skip-images"` to only keep the folded data/summary when flamegraph tooling is unavailable.


## License

[GNU General Public License version 3](https://opensource.org/license/gpl-3-0)
