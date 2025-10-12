# Repository Guidelines

## Project Structure & Modules
- `src/` holds the C++17 engine modules (rendering, physics, audio, bindings). Add new systems as matching `.cpp`/`.h` pairs.
- `apps/space/main.cpp` is the executable entry point; bootstrap other front ends here.
- `assets/` includes Lua, Fennel, Python, textures, and audio. Runtime and tests rely on `SPACE_ASSETS_PATH` pointing here.
- `tests/` contains CTest targets like `test_lua.cpp`; keep fixtures aligned with the asset layout.
- `scripts/` bundles utilities (`seed.py`), while `external/` houses vendored dependencies consumed by CMake.

## Build, Run & Test
- `make cmake` primes the `build/` directory; rerun after editing CMake files.
- `make build` compiles a Release build in `build/`.
- `make run` executes `space` with `SPACE_ASSETS_PATH=../assets`.
- `make debug` configures `build/debug/` and launches `gdb ./space`.
- `make test` or `ctest --test-dir build --output-on-failure -V` runs all registered tests once the build is up to date.

## Coding Style & Naming
- Use four-space indentation, brace-on-new-line for functions, and group includes as system `<...>` first, then project `"..."`.
- Classes stay UpperCamelCase (`Engine`); free/static functions use snake_case (`lua_bind_tree_sitter`); filenames remain lowercase.
- Favor `std::unique_ptr`/`std::shared_ptr` over raw ownership and keep headers minimal to limit rebuild time.
- Match the existing layout (roughly 120-character limit). Run `clang-format` if available or format manually.

## Testing Expectations
- Add new C++ test binaries under `tests/` and register them in `CMakeLists.txt` with `add_executable` and `add_test`.
- Mirror runtime asset setup; see `tests/test_lua.cpp` for configuring package paths before executing scripts.
- Keep integration tests deterministic, documenting required seeds or fixtures inside `scripts/`.

## Commit & PR Process
- Write imperative, one-line commit subjects similar to `Fix regression` or `Update target fbo`; stay under 72 characters.
- Mention related issues in the commit body (`Refs #123`) and call out asset or API changes explicitly.
- PR descriptions should cover problem, solution, and validation (`make test`, manual run). Attach screenshots or GIFs for visual updates.
- Confirm CI is green before requesting review and list any follow-up tasks or known risks.

## Assets & Configuration Tips
- When adding assets, ensure `AssetManager::getAssetPath` can locate them and verify packaging copies from `assets/`.
