# Repository Guidelines

Be extra rigorous; I'm at risk of losing my job at my hospital.
Don't be afraid; Hesitancy will hold us back.
Clean design is important, refactor when reasonable.

## Branch Convention

The default base branch for pull requests and merges is `main`.

For final validation and PR diff/base checks, use `origin/main` as the base
branch reference — not local `main`. Local `main` may be stale or contain
unrelated local commits. Use local `main` only when explicitly performing a
local merge or integration operation that requires it.

After implementation is complete — reviewed, committed, tests passing, tree
clean — the default integration action is to push the current branch and create a
pull request targeting `main`. Do this automatically; do not present an
integration menu or ask the user which action to take. Only deviate when the user
explicitly requests a different integration action or when the branch state is
unsafe (uncommitted changes, failing tests, unresolved merge conflicts with
`main`).

## Project Structure & Modules

- `src/` holds the C++17 engine modules (rendering, physics, audio, bindings). Add new systems as matching `.cpp`/`.h` pairs. Engine Lua bindings live in `src/lua_engine.cpp`.
- `apps/space/main.cpp` is the executable entry point; bootstrap other front ends here.
- `assets/` includes Lua, Fennel, Python, textures, and audio. Runtime and tests rely on `SPACE_ASSETS_PATH` pointing here.
- During the Python-to-Fennel/C++ migration, treat `assets/python/` as historical prototypes only. Reference them to understand behavior, but base new features, tests, and architecture decisions on the canonical Fennel modules in `assets/lua/` and the C++ engine in `src/`.
- `tests/` contains CTest targets; keep fixtures aligned with the asset layout.
- `scripts/` bundles utilities (`seed.py`), while `external/` houses vendored dependencies consumed by CMake.
- `archive/` contains some old python bindings that are no longer used but may be used for reference when building new features.

## OpenAI API Docs

- OpenAI API reference lives in `docs/dev/openai/`; start at `docs/dev/openai/index.md` for a map to chat/responses, assistants/threads/runs, uploads/vector stores, realtime events, and project/admin endpoints.
- Endpoint files follow the action name inside each folder (`create.md`, `list.md`, `object.md`, etc.). Use `rg "POST /responses"` (or similar) from the repo root to jump to the exact endpoint when wiring code to the API.

## Project-Specific OpenCode Skills

OpenCode users: restart after `.opencode/**` changes.

- Use `space-fennel-ui` for Fennel widgets, layout, rendering adapters, interaction widgets, widget lifecycle, or widget tests. See `docs/dev/fennel/style.md`.
- Use `space-graph-doctrine` for graph nodes, graph maps, graph views, graph persistence/topology, key loaders, or graph terminology. See `docs/dev/notes/graph.md`.
- Use `space-testing-runtime` for tests, E2E snapshots, remote-control debugging, profiling, build commands, or runtime harnesses. See `docs/dev/features/development-tooling.md`.

## Build, Run & Test

- `make cmake` primes the `build/` directory; rerun after editing CMake files.
- `make build` compiles a Release build in `build/`.
- **Build timeouts:** A cold `make build` can take hours. Always pass an explicit `timeout` parameter:
  - `make build`: `timeout: 14400000` (4 hours).
  - `make cmake`: `timeout: 600000` (10 minutes).
  - Err on the high side rather than restarting from scratch.
- `make run` executes `space` with `SPACE_ASSETS_PATH=../assets`.
- Default test invocation: `make test` or `python3 scripts/ctest-summary.py --test-dir build --output-on-failure`.
- Standard full-suite command: `SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets make test`.
- E2E tests: `SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets make test-e2e` (must run outside sandbox).
- Add C++ tests under `tests/` with `CMakeLists.txt` registration; mirror runtime asset setup from `apps/space/main.cpp`.
- For live debugging: use `--remote-control=<zmq endpoint>`; the `space-testing-runtime` skill covers remote-control and profiling workflows.
- Profilers: `make prof target=<name>`; the `space-testing-runtime` skill covers profiling workflows.

## Coding Style & High-Risk Rules

- **No silent failures:** If required data, bindings, or operations fail, surface an explicit error immediately — never convert failures into quiet no-ops or clean exits.
- **Fennel classes:** Construct `self` in a final literal with all methods included; do not create early and mutate with `set`.
- Use `local` instead of `let` in Fennel.
- Use factory functions instead of constructors (`.new`).
- **Canonical option keys only:** Do not add legacy aliases or compatibility shims; migrate existing call sites instead.
- Use `assets/lua/json-utils.fnl` for atomic JSON writes.
- For C/C++: four-space indent, brace-on-new-line for functions, `std::unique_ptr`/`std::shared_ptr` over raw ownership, minimal headers.
- Fennel: multi-branch `if` forms instead of nesting; bind multiple return values directly with `local`.
- Graph nodes stay decoupled from views; use signals to emit updates.
- Fennel parse errors: the reported location is often misleading — isolate bad forms by temporarily removing chunks of logic.

## Commit Conventions

- Use the `type(scope)` format as described by the `git-commit` skill.
- Scopes: `engine`, `render`, `physics`, `audio`, `lua`, `ui`, `assets`, `scripts`.
- Before committing, run the full test suite (see Build, Run & Test above).

## Assets & Configuration Tips

- When adding assets, ensure `AssetManager::getAssetPath` can locate them and verify packaging copies from `assets/`.
- For icon names used by UI buttons/widgets, validate availability against `assets/material-design-icons/icons.txt` before committing. Use `rg` on that file and prefer exact icon-name matches from the start of each line.
