# Repository Guidelines

Be extra rigorous; I'm at risk of losing my job at my hospital.
Don't be afraid; Hesitancy will hold us back.
Clean design is important, refactor when reasonable.

## Project Structure & Modules
- `src/` holds the C++17 engine modules (rendering, physics, audio, bindings). Add new systems as matching `.cpp`/`.h` pairs. Engine Lua bindings live in `src/lua_engine.cpp`.
- `apps/space/main.cpp` is the executable entry point; bootstrap other front ends here.
- `assets/` includes Lua, Fennel, Python, textures, and audio. Runtime and tests rely on `SPACE_ASSETS_PATH` pointing here.
- During the Python-to-Fennel/C++ migration, treat `assets/python/` as historical prototypes only. Reference them to understand behavior, but base new features, tests, and architecture decisions on the canonical Fennel modules in `assets/lua/` and the C++ engine in `src/`.
- `tests/` contains CTest targets; keep fixtures aligned with the asset layout.
- `scripts/` bundles utilities (`seed.py`), while `external/` houses vendored dependencies consumed by CMake.
- `archive/` contains some old python bindings that are no longer used but may be used for reference when building new features.

## OpenAI API Docs
- OpenAI API reference lives in `doc/openai/`; start at `doc/openai/index.md` for a map to chat/responses, assistants/threads/runs, uploads/vector stores, realtime events, and project/admin endpoints.
- Endpoint files follow the action name inside each folder (`create.md`, `list.md`, `object.md`, etc.). Use `rg "POST /responses"` (or similar) from the repo root to jump to the exact endpoint when wiring code to the API.

## Fennel Architecture & Widgets
- `assets/lua/` is organized by widget responsibility: low-level render backs (`raw-rectangle.fnl`, `renderers.fnl`), layout primitives (`layout.fnl`, `flex.fnl`, `stack.fnl`, `padding.fnl`, `sized.fnl`), and leaf widgets (`rectangle.fnl`, `text-span.fnl`, `button.fnl`, etc.). `assets/lua/main.fnl` wires these pieces together, seeds the layout tree, and exposes `app.init/update/drop` consumed by the Fennel-side lifecycle.
- Each widget module exports a constructor that captures options and returns a `build` closure. The closure receives the renderer context from `app.init` (triangle buffers, text vectors, helpers), instantiates child widgets by calling their constructors with the same context, and produces an entity table containing at least `layout` and `drop` (see `assets/lua/rectangle.fnl`, `assets/lua/text-span.fnl`).
- Layouts are explicit objects from `layout.fnl`. Widgets create a `Layout` with custom `measurer` and `layouter` closures, add child layouts via `:children`, and mark themselves dirty so the `LayoutRoot` in `app.init` can call `:update`. Always set a layout’s root, propagate size/position/rotation to children, and clean up registrations inside `drop`.
- When propagating transforms inside a `layouter`, assign `child.layout.position/rotation/size` directly; do not call `set-position`/`set-rotation` there or you will re-dirty the tree mid-pass.
- Dirt rules: marking `mark-measure-dirty` on a node implies its layout is also dirty and every descendant will be visited; use the shallowest possible node to avoid extra work. `mark-layout-dirty` only queues layout work for that node/subtree. Avoid calling dirt methods during a layout pass (`assert-not-in-pass` will throw). In layouters, mutate child layout fields directly rather than via setters to avoid re-dirtying mid-pass.
- Depth offsets: respect `layout.depth-offset-index` for ordering; backgrounds usually inherit the parent index, while foreground/content elements (e.g., chart series) should be bumped to `parent + 1` (or higher) to avoid z-fighting. When passing render frames, carry the depth offset forward so leaf widgets write it into their layouts/buffers.
- Composition happens by nesting widgets’ layouts: builders like `Stack` and `Flex` collect their children’s layouts and control measurement (e.g., stacking max axes, distributing flex space) before writing child positions; utility wrappers like `Padding` and `Sized` adjust the child’s layout contract; higher-level widgets (e.g., `Button`) are just compositions of primitives. Follow this pattern when introducing new widgets so measurement/layout passes and `drop` cascades remain consistent.
- For form layouts that use `Grid`, order children so labels occupy the first column (non-stretch) and inputs/controls occupy the second column (stretch). This means listing all label widgets first, then the input widgets, since `Grid` fills by column.
- Layouters that own children must call their children’s layouters; a layout node being marked dirty implies the subtree beneath it will be handled within that pass (no separate dirt propagation needed to descendants).
- Interactive widgets that depend on input routing (buttons, inputs, scroll views, terminal widgets) require `clickables`/`hoverables` in the build context; assert if missing rather than guarding with `when`.
- Graph nodes must stay decoupled from views: set `:view` to the view constructor (no per-instance builders), keep business logic/state on the node, emit updates via signals (`items-changed`, `rows-changed`, etc.), and let `graph/views` own view lifecycles so multiple views can attach later.
- `app.engine.events.updated` is for updates that need to run every frame, for other updates try to connect directly to the update source possibly through signals.

## Lua/Fennel Bindings
- C++ bindings register modules via `package.preload`; Lua/Fennel must `require` them (e.g. `(local glm (require :glm))`) rather than relying on globals.
- Keep module names stable and direct (no root namespace); wrapper modules use descriptive suffixes such as `*-widget`, `*-manager`, or `*-router` when needed.
- Use module factory functions (`terminal.Terminal(...)`, `VectorBuffer(...)`, `ForceLayout(...)`, `bt.Vector3(...)`) instead of `.new`; usertypes remain `sol::no_constructor` while still exposing type methods.
- Engine bindings are accessed via `(require :engine)` to get the factory; create instances with `(EngineModule.Engine {:headless true})` and store them on `app.engine` so scripts use instance methods/fields (`events`, `get-asset-path`, `input`, `physics`, etc.).

## Data Persistence
- Use `assets/lua/json-utils.fnl` (`JsonUtils.write-json!`) for JSON writes so updates are atomic and do not leave corrupt files behind.

## Build, Run & Test
- `make cmake` primes the `build/` directory; rerun after editing CMake files.
- `make build` compiles a Release build in `build/`.
- `make run` executes `space` with `SPACE_ASSETS_PATH=../assets` (via `./space -m main`).
- When running Lua/Fennel tests from the CLI, always set `SPACE_ASSETS_PATH` to the absolute `assets` path (e.g. ``SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tests.fast:main``) so path-sensitive suites like `FsView` can resolve fixtures correctly.
- Fennel macros live under `assets/lua`; when invoking tests directly with `./build/space -m ...` set `FENNEL_PATH` and `FENNEL_MACRO_PATH` to `$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl` to ensure `(import-macros ...)` resolves.
- Default test invocation is `make test` (or `ctest --test-dir build --output-on-failure -V`) after a build; prefer this unless you specifically need a narrowed `./build/space -m tests.test-...` run.
- Disable audio for CLI test runs by default to avoid sandbox/PortAudio warnings: prefix commands with `SPACE_DISABLE_AUDIO=1` (e.g. `SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tests.fast:main`).
- When running tests, point `XDG_DATA_HOME` outside the repo to avoid littering the workspace (use `XDG_DATA_HOME=/tmp/space/tests/xdg-data` unless otherwise specified). Agents should always skip keyring-backed tests (`SKIP_KEYRING_TESTS=1`). Standard full-suite command: `SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets make test`.
- `make debug` configures `build/debug/` and launches `gdb ./space`.
- `make test` or `ctest --test-dir build --output-on-failure -V` runs all registered tests once the build is up to date.
- When Lua/Fennel work needs additional bindings or host scaffolding, update the relevant C++ (e.g. `apps/space/main.cpp`, `src/` modules) yourself and rerun `make build` to confirm the harness still compiles before handing the change back.
- On parentheses imbalance in Fennel code, especially when the code is deeply nested, don't try to fix it directly. Instead restructure the code by moving logic into helper functions in order to simplify the code structure and reduce nesting.
- For live debugging, `space` supports `--remote-control=<zmq endpoint>` which evaluates Fennel code inside the running app; use `./build/space -m tools.remote-control-client:main -- --endpoint <endpoint> -c "<code>"` to send commands, and only enable it on trusted machines. The eval environment exposes `remote_control.create/resolve/reject/poll` for async results (create an id, resolve it inside a signal callback, then poll by id). Use `scripts/remote-control-heavy.sh` to exercise the async flow against a live app.
- When asked to debug a running app, prefer using the remote-control endpoint if the app was started with `--remote-control`; `make run` defaults to `ipc:///tmp/space-rc.sock`, otherwise ask for the endpoint, then send Fennel snippets via the client to inspect or modify state.
- Use `scripts/remote-control-debug.sh` for repeatable live-debug or live-inspect queries; update it as needed instead of ad-hoc client invocations, and run it outside the sandbox so IPC access works.
- `scripts/remote-control-debug.sh` should always contain only the latest debug query; replace its contents for new questions instead of adding flags or multiple modes.
- Use `app.next-frame` when remote-control scripts need to wait for a frame to render before reading state or running render-capture.

## E2E Snapshot Testing
- E2E snapshot tests live under `assets/lua/tests/e2e/` and are composed by `assets/lua/tests/e2e.fnl`; run the suite with `SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets make test-e2e`.
- Always run `make test-e2e` outside the sandbox (escalated/unrestricted): Xvfb needs to bind Unix sockets and the sandbox blocks `AF_UNIX` binds, causing false failures.
- Update goldens with `SPACE_SNAPSHOT_UPDATE=name1,name2` and `make test-e2e`. Goldens live in `assets/lua/tests/data/snapshots/`.
- Individual tests are runnable via `./build/space -m tests.e2e.<module>:main` (e.g. `tests.e2e.test-image:main`).
- Shared test utilities belong in `assets/lua/tests/e2e/harness.fnl`; prefer reusing it over adding overrides in app code.
- HUD snapshots must use test-owned control/status content (via `HudLayout` + `hud-control-panel-layout`/`hud-status-panel-layout`) to avoid unstable main app labels/buttons.
- When creating or debugging snapshots, always inspect the PNGs directly (e.g. open the file or use the image viewer tools) to confirm visual intent. Do not analyze the image data, always view the images.
- Snapshot images don't need to be deleted, just let them be overwritten.
- E2E test failures will create `*.actual.png` files that you can inspect for debugging.

## Profiling & Flamegraphs
- All flamegraph profilers live under `assets/lua/prof-*.fnl`. Run them via `make prof target=<name>` (e.g. `target=scene`). This invokes `scripts/prof.py` which executes `./build/space -m prof-<name>` with `SPACE_FENNEL_FLAMEGRAPH` pointing to `prof/<name>.folded`.
- The helper automatically writes `prof/<name>.folded`, `prof/<name>.svg`, and `prof/<name>.png`, and prints a textual summary of the hottest stacks/leaf frames. Pass `args="--skip-images"` to `make prof` (or `--no-summary`/`--top N`/`--skip-images` directly to `scripts/prof.py`) when assets such as SVGs aren’t useful in this environment.
- When diagnosing a performance issue, prefer an existing profiler whose name matches the subsystem (`prof-scene`, `prof-update`, etc.). If none fit, create a new `assets/lua/prof-<feature>.fnl` using `FlamegraphProfiler` with the standard default output path (`prof/<feature>.folded`). Ensure it wires up the relevant workload (e.g. repeatedly calling a widget update) and exits cleanly so the helper script can run it.
- Keep profiler scripts deterministic, respect the `SPACE_FENNEL_FLAMEGRAPH` env var, and avoid graphics dependencies beyond what `FlamegraphProfiler` already fakes in `prof-scene`. Register additional profilers in docs/readme so `make prof target=<name>` is discoverable.

## Coding Style & Naming
- Use four-space indentation, brace-on-new-line for functions, and group includes as system `<...>` first, then project `"..."`.
- Classes stay UpperCamelCase (`Engine`); free/static functions use snake_case (`lua_bind_tree_sitter`); filenames remain lowercase.
- Favor `std::unique_ptr`/`std::shared_ptr` over raw ownership and keep headers minimal to limit rebuild time.
- Match the existing layout (roughly 120-character limit). Run `clang-format` if available or format manually.
- In Fennel code, don't use guards and fallbacks unless necessary or asked for.
- Keep option keys canonical (one name). Don’t add “legacy” aliases (e.g. `:foo` vs `:foo?`) or compatibility shims; migrate existing call sites instead. Only add an alias if the user explicitly asks for it.
- Do not paper over missing required bindings or data with fallbacks. If a binding like `glm.project` or a required projection/view/viewport is absent, fail loudly instead of silently substituting defaults.
- Build Fennel classes by constructing the `self` table at the end in a single literal (methods included) instead of creating it early and mutating it with `set`.
- Avoid using `let` in Fennel, use `local` instead.
- Note that `if` in Fennel is like `cond` in other lisps, so you can pass it pairs of conditions and expressions. if you pass an uneven number of forms, the last one is the default expression executed when none other matched.
- Fennel does not provide `cond`; prefer multi-branch `if` forms instead of nesting, letting the final expression act as the default branch.
- Do not add silent fallbacks; only introduce a fallback path when an existing caller explicitly requires it, and make that intent obvious in the code.
- When destructuring multiple return values (e.g., from `pcall`), bind them directly with multiple locals `(ok err) = (pcall ...)`; do not index a table or assume `pcall` returns a list object.
- Factor out reusable logic into separate modules (or find a suitable module for them).
- In Fennel (or sol2 bindings) use factory functions instead of constructors (`new`).

## Testing Expectations
- Add new C++ test binaries under `tests/` and register them in `CMakeLists.txt` with `add_executable` and `add_test`.
- Mirror runtime asset setup; see `apps/space/main.cpp` for configuring package paths before executing scripts.
- Keep integration tests deterministic, documenting required seeds or fixtures inside `scripts/`.

### Lua/Fennel Test Harness
- `apps/space/main.cpp` triggered by ctest boots `assets/lua/tests/fast.fnl` via `tests.fast:main`; extend coverage by adding new `assets/lua/tests/test-*.fnl` modules and listing them in `assets/lua/tests/fast.fnl` so `make test` picks them up automatically.
- You can unit-test widgets by instantiating them with a dummy context table `{}`; the builders only touch `ctx` when they need renderer handles.
- To assert layout contracts (as done in `assets/lua/tests/test-sized.fnl`), create instrumented child widgets that expose their `Layout` via a builder, override `:measurer`/`:layouter` to capture incoming size/transform, and drop them to ensure ownership is released.
- Run Fennel scripts (including quick experiments) via `build/space`; pass the module name (e.g. `./build/space -m tests.fast:main`) instead of using the system `fennel` binary; to avoid issues with your sandbox, disable audio by passing `SPACE_DISABLE_AUDIO=1`.
-  Fennel tests may use the mock opengl feature but everything else should not be mocked, real objects created by real app code should be used instead. No synthetic objects or stubs.

## Assets & Configuration Tips
- When adding assets, ensure `AssetManager::getAssetPath` can locate them and verify packaging copies from `assets/`.
