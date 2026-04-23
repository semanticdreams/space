# space

[![.github/workflows/test.yml](https://github.com/semanticdreams/space/actions/workflows/test.yml/badge.svg?branch=main)](https://github.com/semanticdreams/space/actions/workflows/test.yml)
[![.github/workflows/build.yml](https://github.com/semanticdreams/space/actions/workflows/build.yml/badge.svg?branch=)](https://github.com/semanticdreams/space/actions/workflows/build.yml)
[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](https://opensource.org/license/gpl-3-0)

Check out the <a href="https://spaceui.org/" target="_blank">docs</a> for more information.

## Setup

### Install from latest GitHub release

Use prebuilt packages from the latest release:
[Latest release page](https://github.com/semanticdreams/space/releases/latest)

Direct downloads:
- Windows installer (.exe): [space-windows-setup.exe](https://github.com/semanticdreams/space/releases/latest/download/space-windows-setup.exe)
- Windows (.zip): [space-windows.zip](https://github.com/semanticdreams/space/releases/latest/download/space-windows.zip)
- AppImage: [space-linux-x86_64.AppImage](https://github.com/semanticdreams/space/releases/latest/download/space-linux-x86_64.AppImage)
- Debian/Ubuntu (.deb): [space-linux-amd64.deb](https://github.com/semanticdreams/space/releases/latest/download/space-linux-amd64.deb)
- Fedora/RHEL/openSUSE (.rpm): [space-linux-x86_64.rpm](https://github.com/semanticdreams/space/releases/latest/download/space-linux-x86_64.rpm)
- Minimal AppImage: [space-minimal-linux-x86_64.AppImage](https://github.com/semanticdreams/space/releases/latest/download/space-minimal-linux-x86_64.AppImage)
- Minimal Debian/Ubuntu (.deb): [space-minimal-linux-amd64.deb](https://github.com/semanticdreams/space/releases/latest/download/space-minimal-linux-amd64.deb)
- Minimal Fedora/RHEL/openSUSE (.rpm): [space-minimal-linux-x86_64.rpm](https://github.com/semanticdreams/space/releases/latest/download/space-minimal-linux-x86_64.rpm)

Install guidance:
- Windows installer: run `space-windows-setup.exe` and follow the installer.
- Windows: extract `space-windows.zip` and run `space.exe`.
- AppImage: mark executable and run it (`chmod +x <file>.AppImage`, then `./<file>.AppImage`).
- Debian/Ubuntu: install the downloaded `.deb` with your standard package workflow (`apt`/`dpkg`).
- Fedora/RHEL/openSUSE: install the downloaded `.rpm` with your standard package workflow (`dnf`/`yum`/`zypper`/`rpm`).

### Build from source

Linux package names differ by distro. Use the dependency set that matches your system.

Ubuntu/Pop!_OS:

<!-- CI_DEPS_START -->
```bash
sudo apt install cmake libbullet-dev libglm-dev libopenal-dev libepoxy-dev portaudio19-dev libvterm-dev libnotify-dev libcurl4-openssl-dev libzmq3-dev python3 python3-pil python3-zmq cargo libaubio-dev libboost-dev libxapian-dev libtorrent-rasterbar-dev ripgrep ffmpeg libavcodec-dev libavformat-dev libavutil-dev libswscale-dev libswresample-dev libgccjit-11-dev
```
<!-- CI_DEPS_END -->

Fedora:

```bash
sudo dnf install \
  cmake \
  bullet-devel \
  glm-devel \
  openal-soft-devel \
  libepoxy-devel \
  portaudio-devel \
  libvterm-devel \
  libnotify-devel \
  libcurl-devel \
  zeromq-devel \
  python3 \
  python3-pillow \
  python3-zmq \
  cargo \
  aubio-devel \
  boost-devel \
  xapian-core-devel \
  rb_libtorrent-devel \
  ripgrep \
  ffmpeg-free \
  ffmpeg-free-devel \
  libgccjit-devel \
  libsecret \
  libsecret-devel \
  libdecor-devel \
  wayland-devel \
  libxkbcommon-devel \
  libXi-devel
```

Build and run:

```bash
make build
make run
```

To run the app directly, use `./build/space -m main`.
By default, `./build/space` also starts the main app; use `./build/space --repl` for the embedded Fennel REPL.

Optional packaging dependencies (only needed for `make pack`):

Ubuntu/Pop!_OS:

```bash
sudo apt install dpkg-dev rpm
```

Fedora:

```bash
sudo dnf install dpkg-dev rpm-build
```

- `dpkg-dev` is needed for `.deb` dependency scanning (`dpkg-shlibdeps`).
- `rpm`/`rpm-build` is needed for `.rpm` output (`rpmbuild`).
- Use `make install-deb` to install a built `.deb` locally.
- Use `make install-rpm` to install a built `.rpm` locally.

Build an AppImage (portable Linux bundle):

```
make appimage
```

This writes `build/space-<version>-x86_64.AppImage`.

Build Linux release artifacts with selectable profiles:

```bash
# full profile (default)
scripts/build-linux.sh --profile full

# minimal profile (currently disables CEF; extend via SPACE_MINIMAL_DISABLED_OPTIONS)
scripts/build-linux.sh --profile minimal
```

Stable outputs are written as:
- Full: `build/space-linux-x86_64.AppImage`, `build/space-linux-amd64.deb`, `build/space-linux-x86_64.rpm`
- Minimal: `build/space-minimal-linux-x86_64.AppImage`, `build/space-minimal-linux-amd64.deb`, `build/space-minimal-linux-x86_64.rpm`

Windows release builds currently publish:
- `space-windows-setup.exe`
- `space-windows.zip`

The Matrix FFI library (`ffi/matrix`) is built by default and requires `cargo`. To skip it, configure
with `-DSPACE_BUILD_MATRIX=OFF` (e.g. `make cmake` then `cmake -DSPACE_BUILD_MATRIX=OFF ..`).

Wallet-core integration is disabled by default. Enable it by configuring with `-DSPACE_ENABLE_WALLET_CORE=ON`
(e.g. `make cmake` then `cmake -DSPACE_ENABLE_WALLET_CORE=ON ..`).

CEF embedded browser integration is Linux-only right now and enabled by default in the project `make cmake` flow.
The pinned defaults are baked into CMake, so no extra flags are required for standard builds:

```bash
make cmake
make build
```

If you need to override the pinned build, you can still pass:
`-DSPACE_CEF_VERSION=... -DSPACE_CEF_URL=... -DSPACE_CEF_SHA256=...`

CEF setup in `cmake/cef.cmake` is structured with a platform dispatcher (`space_setup_cef_for_target`) and Linux-specific implementation (`space_setup_cef_for_target_linux`) so Windows/macOS support can be added as separate platform handlers later.

At runtime, browser surfaces are created from Fennel via `app.engine.browser`:

```fennel
(app.engine.browser:create-surface {:id "cube-face-1"
                                    :url "https://example.com"
                                    :texture-name "browser/cube-face-1"
                                    :width 1024
                                    :height 1024
                                    :max-fps 30})
```

Bind `:texture-name` to any mesh/material texture slot to render web content on arbitrary geometry (planes, cube faces, UV-mapped meshes).
Use `app.engine.browser:send-mouse-move`, `:send-mouse-click`, `:send-mouse-wheel`, and `:set-focus` to route world-space hit input into the surface.

For an opt-in in-world cube demo (6 browser faces), run with:

```bash
SPACE_BROWSER_CUBE_DEMO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m main
```

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

## In-World Video (FFmpeg)

Use the `video` Lua module to decode frames into a regular texture, then pass that texture to any widget that already accepts textures (`Image`, `RawImage`, mesh batches, etc.):

```fennel
(local Video (require :video))
(local Image (require :image))

(local player
  (Video.VideoPlayer {:path "lua/tests/data/test-videos/sample.mp4"
                      :loop true
                      :muted false
                      :positional-audio true
                      :audio-gain 1.0
                      :audio-pitch 1.0
                      :audio-max-distance 300.0
                      :audio-rolloff-factor 0.05
                      :audio-reference-distance 10.0
                      :audio-min-gain 0.0
                      :audio-max-gain 1.0
                      :audio-cone-inner-angle 360.0
                      :audio-cone-outer-angle 360.0
                      :audio-cone-outer-gain 0.0}))

;; anywhere you build widgets:
((Image {:texture (player:texture)
         :width 32}) ctx)
```

The engine-owned `VideoManager` updates all active players every frame, so playback stays in sync without per-widget update hooks.
Implementation details and operations guide: `docs/dev/video-playback.md`.

`player:status()` returns playback and telemetry fields, including:
`ready`, `ended`, `playing`, `has-error`, `clock-seconds`, `has-audio-clock`,
`audio-available`, `audio-active`, `positional-audio`, `queued-audio-chunks`, `dropped-audio-chunks`,
`flushed-audio-chunks`, `av-drift-seconds`, `max-av-drift-seconds`,
`recent-max-av-drift-seconds`, `av-drift-window-seconds`, `dropped-video-frames`,
`decode-loop-iterations`, and `decode-wait-ms`.

You can also use the built-in wrapper widget:

```fennel
(local VideoWidget (require :video-widget))
((VideoWidget {:path "lua/tests/data/test-videos/01_baseline_h264_with_audio.mp4"
               :width 32
               :loop true
               :positional-audio true
               :audio-rolloff-factor 0.08
               :audio-reference-distance 8.0}) ctx)
```

For long-duration drift checks, run the manual soak module (default is 600 seconds / 10 minutes):

```bash
SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tests.test-video-soak:main
```

For real audio-clock validation on a machine with working audio output, run the same soak without
`SPACE_DISABLE_AUDIO=1`:

```bash
SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tests.test-video-soak:main
```

Override duration (seconds) and polling interval:

```bash
SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets \
SPACE_VIDEO_SOAK_SECONDS=120 SPACE_VIDEO_SOAK_SLEEP_SECONDS=0.01 \
./build/space -m tests.test-video-soak:main
```

Soak thresholds (optional):

- `SPACE_VIDEO_SOAK_MAX_RECENT_DRIFT_SECONDS` (default `0.35`)
- `SPACE_VIDEO_SOAK_MAX_DECODE_WAIT_MS` (default disabled)

## Contribute

Create a [discussion here on GitHub](https://github.com/semanticdreams/space/discussions). Join the community on [Matrix](https://matrix.to/#/#spaceui.org:matrix.org).

## Profiling the Fennel Runtime

- Set `SPACE_FENNEL_PROFILE=1` (or any truthy value) to enable the existing frame profiler that logs section timings to stdout when a frame exceeds the configured threshold.
- Run `./build/space -m prof-scene` to profile scene creation plus the first update with the flamegraph profiler. Without configuration the script writes `prof/space-scene-profile.folded`; override the destination via `SPACE_FENNEL_FLAMEGRAPH=/tmp/scene.folded` or disable the run entirely by setting it to `0`, `false`, or `off`. The output is a collapsed stack file compatible with standard flamegraph tooling like `flamegraph.pl`.
- Run `./build/space -m prof-object-browser-drag` (or `make prof target=object-browser-drag`) to profile the Movables-driven drag loop for the object-browser dialog. The script reconfigures the scene to focus on the widget, simulates a long drag path, and records stacks to `prof/object-browser-drag.folded` by default.
- Run `./build/space -m prof-scroll-inputs` (or `make prof target=scroll-inputs`) to profile scrolling a list of 100 multiline input widgets (100 lines each) from top to bottom, writing to `prof/scroll-inputs.folded` by default.
- After running a profiler script, generate SVG/PNG visualizations with `make prof target=scene` (or call `python3 scripts/prof.py scene` directly). The helper ensures folded, SVG, and PNG files (`prof/<target>.folded|.svg|.png`) live together in the `prof/` directory, prints a concise textual summary of the heaviest stacks/leaf frames, and supports any `prof-*` module. Pass additional args via `make prof target=scene args="--skip-images"` to only keep the folded data/summary when flamegraph tooling is unavailable.


## License

[GNU General Public License version 3](https://opensource.org/license/gpl-3-0)
