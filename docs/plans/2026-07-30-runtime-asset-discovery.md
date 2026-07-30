# Runtime Asset Discovery Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the `space` runtime discover assets relative to its executable so direct binary execution works from arbitrary working directories while preserving existing overrides and fallbacks.

**Architecture:** Add a shared executable-path utility, configure `AssetManager` once during `apps/space/main.cpp` startup, and have asset lookup probe deduplicated roots in the spec-defined order. Reuse the executable-path utility for CEF helper/resource path logic so executable-relative behavior is centralized.

**Tech Stack:** C++17, `std::filesystem`, CMake/CTest, existing `appdirs` helpers, existing Fennel runtime CLI smoke tests.

## Global Constraints

- Allow the runtime to start from arbitrary working directories for developer builds, installed packages, and portable bundles.
- Preserve `SPACE_ASSETS_PATH` as the highest-priority explicit override.
- Preserve user data assets and existing working-directory fallback behavior.
- Avoid making `~/.profile` or wrapper scripts required for correctness.
- Fail loudly when required assets are unavailable, including enough searched path context to diagnose the problem.
- Do not remove `SPACE_ASSETS_PATH` support.
- Do not support multi-entry asset path lists.
- Do not make missing required assets a recoverable no-op.
- Equivalent candidate roots should be deduplicated before probing.
- A found root is valid only when the requested relative path exists under that root.
- Keep C++17 compatibility and add no third-party dependencies.

---

## File Structure

- Create `src/executable_path.h`: public executable path utility interface.
- Create `src/executable_path.cpp`: platform-native executable resolution plus `argv[0]`/`PATH` fallback and sibling helper.
- Modify `src/asset_manager.h`: add executable-path configuration and test reset hook.
- Modify `src/asset_manager.cpp`: implement deduplicated root search and loud missing-asset diagnostics.
- Modify `apps/space/main.cpp`: configure `AssetManager` before `LuaRuntime::init()` and use the shared sibling helper for CEF.
- Modify `src/cef_runtime.cpp`: replace duplicated executable-dir logic with the shared utility.
- Create `tests/test_executable_path.cpp`: focused utility coverage.
- Create `tests/test_asset_manager.cpp`: focused lookup-order coverage.
- Create `tests/test_runtime_asset_discovery_integration.cpp`: arbitrary-CWD `space -c` smoke test.
- Modify `CMakeLists.txt`: register tests and include the new utility source in the CEF helper target when needed.
- Modify `docs/dev/building.md`: document direct binary execution and asset search order.

## Acceptance Criteria

- `SPACE_ASSETS_PATH` wins when it contains the requested asset.
- User data assets remain searched before executable-relative assets.
- `<exe_dir>/assets` is searched before CWD fallback.
- `<exe_dir>/../share/space/assets` is searched before CWD fallback.
- Existing `<cwd>/assets` fallback still works.
- Missing required assets throw an error containing the requested relative path and searched candidate paths.
- `SPACE_ASSETS_PATH`, `XDG_DATA_HOME`, and CWD are isolated in tests.
- `space -c '(print (+ 5 3))'` succeeds from an unrelated temporary CWD with `SPACE_ASSETS_PATH` unset after a normal build copied assets next to the executable.
- CEF executable/resource path behavior continues to use executable-relative lookup.

## Validation Ladder

1. Focused implementation tests:
   ```bash
   make cmake
   cmake --build build --target test_executable_path test_asset_manager test_runtime_asset_discovery_integration space -- -j"$(nproc)"
   ctest --test-dir build -R 'test_executable_path|test_asset_manager|test_runtime_asset_discovery_integration' --output-on-failure
   ```
2. Complete relevant suite:
   ```bash
   SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH="$(pwd)/assets" make test
   ```
3. Broader startup smoke check:
   ```bash
   tmp="$(mktemp -d)"
   env -u SPACE_ASSETS_PATH SPACE_DISABLE_AUDIO=1 XDG_DATA_HOME="$tmp/xdg" \
     bash -lc "cd '$tmp' && '$(pwd)/build/space' --no-dotenv -c '(print (+ 5 3))'"
   ```
4. If an outside-sandbox graphical/E2E environment is available:
   ```bash
   SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH="$(pwd)/assets" make test-e2e
   ```

## Out of Scope

- Packaging layout rewrites.
- Hot-reload semantics.
- Shell profile or wrapper-script requirements.
- Multi-entry asset path list parsing.
- Making missing assets non-fatal.

---

### Task 1: Shared Executable Path Utility

**Files:**
- Create: `src/executable_path.h`
- Create: `src/executable_path.cpp`
- Create: `tests/test_executable_path.cpp`
- Modify: `CMakeLists.txt`

**Interfaces:**
- Consumes: C++17 `std::filesystem` and platform executable path APIs.
- Produces:
  - `std::filesystem::path executable_path::resolve(const char* argv0)`
  - `std::filesystem::path executable_path::sibling(const std::filesystem::path& executablePath, const std::filesystem::path& siblingName)`

- [ ] **Step 1: Write the failing utility test**

Create `tests/test_executable_path.cpp`:

```cpp
#include <filesystem>
#include <iostream>
#include <string>

#include "executable_path.h"

namespace fs = std::filesystem;

bool check(bool condition, const std::string& message)
{
    if (!condition) {
        std::cerr << "FAIL: " << message << "\n";
        return false;
    }
    return true;
}

int main(int argc, char** argv)
{
    fs::path resolved = executable_path::resolve(argc > 0 ? argv[0] : nullptr);
    if (!check(!resolved.empty(), "resolved executable path should not be empty")) {
        return 1;
    }
    if (!check(fs::exists(resolved), "resolved executable path should exist: " + resolved.string())) {
        return 1;
    }

    fs::path helper = executable_path::sibling(fs::path("/tmp/space-bin/space"), "space_cef_helper");
    if (!check(helper == fs::path("/tmp/space-bin/space_cef_helper"),
               "sibling should be next to executable")) {
        std::cerr << "actual: " << helper << "\n";
        return 1;
    }

    fs::path fallback = executable_path::sibling(fs::path(), "space_cef_helper");
    if (!check(fallback.is_absolute(), "empty executable sibling fallback should be absolute")) {
        return 1;
    }

    return 0;
}
```

- [ ] **Step 2: Register the failing test**

Add near other C++ test registrations in `CMakeLists.txt`:

```cmake
add_executable(test_executable_path
    tests/test_executable_path.cpp
    src/executable_path.cpp
)
target_include_directories(test_executable_path PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/src)
add_test(NAME test_executable_path COMMAND test_executable_path)
set_tests_properties(test_executable_path PROPERTIES
    WORKING_DIRECTORY ${CMAKE_BINARY_DIR}
)
```

- [ ] **Step 3: Run the focused test and verify failure**

Run:

```bash
make cmake
cmake --build build --target test_executable_path -- -j"$(nproc)"
```

Expected: configure or build fails because `src/executable_path.h` and `src/executable_path.cpp` do not exist.

- [ ] **Step 4: Add the utility header**

Create `src/executable_path.h`:

```cpp
#pragma once

#include <filesystem>

namespace executable_path {

std::filesystem::path resolve(const char* argv0);
std::filesystem::path sibling(const std::filesystem::path& executablePath,
                              const std::filesystem::path& siblingName);

} // namespace executable_path
```

- [ ] **Step 5: Add the utility implementation**

Create `src/executable_path.cpp` with these behaviors:

```cpp
#include "executable_path.h"

#include <cstdlib>
#include <cstdint>
#include <string>
#include <system_error>

#if defined(__linux__)
#include <unistd.h>
#elif defined(_WIN32)
#include <windows.h>
#elif defined(__APPLE__)
#include <mach-o/dyld.h>
#include <vector>
#endif

namespace fs = std::filesystem;

namespace {

fs::path canonical_or_absolute(const fs::path& path)
{
    if (path.empty()) {
        return fs::path();
    }
    std::error_code ec;
    fs::path absolute = path.is_absolute() ? path : fs::absolute(path, ec);
    if (ec) {
        absolute = path;
    }
    fs::path canonical = fs::weakly_canonical(absolute, ec);
    return ec ? absolute.lexically_normal() : canonical;
}

fs::path platform_executable_path()
{
#if defined(__linux__)
    std::error_code ec;
    fs::path procExe = fs::read_symlink("/proc/self/exe", ec);
    if (!ec && !procExe.empty()) {
        return procExe;
    }
#elif defined(_WIN32)
    std::string buffer(MAX_PATH, '\0');
    DWORD size = GetModuleFileNameA(nullptr, buffer.data(), static_cast<DWORD>(buffer.size()));
    if (size > 0 && size < buffer.size()) {
        buffer.resize(size);
        return fs::path(buffer);
    }
#elif defined(__APPLE__)
    uint32_t size = 0;
    _NSGetExecutablePath(nullptr, &size);
    if (size > 0) {
        std::vector<char> buffer(size);
        if (_NSGetExecutablePath(buffer.data(), &size) == 0) {
            return fs::path(buffer.data());
        }
    }
#endif
    return fs::path();
}

char path_separator()
{
#if defined(_WIN32)
    return ';';
#else
    return ':';
#endif
}

fs::path lookup_on_path(const fs::path& argvPath)
{
    const char* pathEnv = std::getenv("PATH");
    if (!pathEnv || pathEnv[0] == '\0') {
        return fs::path();
    }
    std::string searchPath(pathEnv);
    size_t start = 0;
    while (start <= searchPath.size()) {
        size_t end = searchPath.find(path_separator(), start);
        std::string dir = searchPath.substr(start, end == std::string::npos ? std::string::npos : end - start);
        if (dir.empty()) {
            dir = ".";
        }
        fs::path candidate = fs::path(dir) / argvPath;
        std::error_code ec;
        if (fs::exists(candidate, ec)) {
            return candidate;
        }
        if (end == std::string::npos) {
            break;
        }
        start = end + 1;
    }
    return fs::path();
}

} // namespace

namespace executable_path {

fs::path resolve(const char* argv0)
{
    fs::path native = platform_executable_path();
    if (!native.empty()) {
        return canonical_or_absolute(native);
    }
    if (!argv0 || argv0[0] == '\0') {
        return fs::path();
    }
    fs::path argvPath(argv0);
    if (argvPath.is_absolute() || argvPath.has_parent_path()) {
        return canonical_or_absolute(argvPath);
    }
    fs::path pathCandidate = lookup_on_path(argvPath);
    if (!pathCandidate.empty()) {
        return canonical_or_absolute(pathCandidate);
    }
    return canonical_or_absolute(argvPath);
}

fs::path sibling(const fs::path& executablePath, const fs::path& siblingName)
{
    if (executablePath.empty() || executablePath.parent_path().empty()) {
        return canonical_or_absolute(siblingName);
    }
    return canonical_or_absolute(executablePath.parent_path() / siblingName);
}

} // namespace executable_path
```

- [ ] **Step 6: Run the focused utility test**

Run:

```bash
cmake --build build --target test_executable_path -- -j"$(nproc)"
ctest --test-dir build -R test_executable_path --output-on-failure
```

Expected: `test_executable_path` passes.

- [ ] **Step 7: Commit Task 1**

```bash
git add CMakeLists.txt src/executable_path.h src/executable_path.cpp tests/test_executable_path.cpp
git commit -m "feat(assets): add executable path utility"
```

---

### Task 2: AssetManager Search Order and Diagnostics

**Files:**
- Modify: `src/asset_manager.h`
- Modify: `src/asset_manager.cpp`
- Create: `tests/test_asset_manager.cpp`
- Modify: `CMakeLists.txt`

**Interfaces:**
- Consumes: `get_user_data_dir(const std::string& app_name)` from `src/appdirs.h`.
- Produces:
  - `static void AssetManager::setExecutablePath(const std::filesystem::path& executablePath)`
  - `static void AssetManager::clearExecutablePathForTests()`
  - existing `static std::string AssetManager::getAssetPath(const std::string& relativePath)`

- [ ] **Step 1: Write the failing AssetManager test**

Create `tests/test_asset_manager.cpp` with these helpers and test cases:

```cpp
#include <chrono>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <optional>
#include <stdexcept>
#include <string>
#include <utility>
#include <vector>

#include "asset_manager.h"

namespace fs = std::filesystem;

namespace {

bool set_env_var(const std::string& key, const std::string& value)
{
#if defined(_WIN32)
    return _putenv_s(key.c_str(), value.c_str()) == 0;
#else
    return setenv(key.c_str(), value.c_str(), 1) == 0;
#endif
}

bool unset_env_var(const std::string& key)
{
#if defined(_WIN32)
    return _putenv_s(key.c_str(), "") == 0;
#else
    return unsetenv(key.c_str()) == 0;
#endif
}

class ScopedEnv {
public:
    ScopedEnv(std::string key, std::optional<std::string> value) : key_(std::move(key))
    {
        const char* existing = std::getenv(key_.c_str());
        if (existing) {
            old_ = std::string(existing);
        }
        ok_ = value ? set_env_var(key_, *value) : unset_env_var(key_);
    }

    ~ScopedEnv()
    {
        if (old_) {
            set_env_var(key_, *old_);
        } else {
            unset_env_var(key_);
        }
    }

    bool ok() const { return ok_; }

private:
    std::string key_;
    std::optional<std::string> old_;
    bool ok_ = false;
};

class ScopedCwd {
public:
    explicit ScopedCwd(const fs::path& next) : old_(fs::current_path()) { fs::current_path(next); }
    ~ScopedCwd()
    {
        std::error_code ec;
        fs::current_path(old_, ec);
    }
private:
    fs::path old_;
};

fs::path make_temp_root(const std::string& name)
{
    auto stamp = std::chrono::steady_clock::now().time_since_epoch().count();
    fs::path root = fs::temp_directory_path() / (name + "_" + std::to_string(stamp));
    fs::create_directories(root);
    return root;
}

void touch(const fs::path& path)
{
    fs::create_directories(path.parent_path());
    std::ofstream out(path);
    out << "asset\n";
}

bool check(bool condition, const std::string& message)
{
    if (!condition) {
        std::cerr << "FAIL: " << message << "\n";
        return false;
    }
    return true;
}

bool path_equals(const std::string& actual, const fs::path& expected)
{
    std::error_code ec1;
    std::error_code ec2;
    return fs::weakly_canonical(actual, ec1) == fs::weakly_canonical(expected, ec2);
}

bool test_env_override_has_highest_priority()
{
    fs::path root = make_temp_root("space_asset_env");
    ScopedEnv env("SPACE_ASSETS_PATH", (root / "env").string());
    ScopedEnv xdg("XDG_DATA_HOME", (root / "xdg").string());
    fs::create_directories(root / "cwd");
    ScopedCwd cwd(root / "cwd");
    AssetManager::clearExecutablePathForTests();
    AssetManager::setExecutablePath(root / "bin" / "space");

    touch(root / "env" / "probe.txt");
    touch(root / "xdg" / "space" / "assets" / "probe.txt");
    touch(root / "bin" / "assets" / "probe.txt");
    touch(root / "cwd" / "assets" / "probe.txt");

    return check(path_equals(AssetManager::getAssetPath("probe.txt"), root / "env" / "probe.txt"),
                 "SPACE_ASSETS_PATH should win when it contains the asset");
}

bool test_user_data_precedes_executable_assets()
{
    fs::path root = make_temp_root("space_asset_user");
    ScopedEnv env("SPACE_ASSETS_PATH", std::nullopt);
    ScopedEnv xdg("XDG_DATA_HOME", (root / "xdg").string());
    fs::create_directories(root / "cwd");
    ScopedCwd cwd(root / "cwd");
    AssetManager::clearExecutablePathForTests();
    AssetManager::setExecutablePath(root / "bin" / "space");

    touch(root / "xdg" / "space" / "assets" / "probe.txt");
    touch(root / "bin" / "assets" / "probe.txt");

    return check(path_equals(AssetManager::getAssetPath("probe.txt"), root / "xdg" / "space" / "assets" / "probe.txt"),
                 "user data assets should precede executable assets");
}

bool test_executable_sibling_assets_work_from_unrelated_cwd()
{
    fs::path root = make_temp_root("space_asset_sibling");
    ScopedEnv env("SPACE_ASSETS_PATH", std::nullopt);
    ScopedEnv xdg("XDG_DATA_HOME", (root / "xdg").string());
    fs::create_directories(root / "unrelated");
    ScopedCwd cwd(root / "unrelated");
    AssetManager::clearExecutablePathForTests();
    AssetManager::setExecutablePath(root / "bin" / "space");

    touch(root / "bin" / "assets" / "lua" / "marker.txt");
    return check(path_equals(AssetManager::getAssetPath("lua"), root / "bin" / "assets" / "lua"),
                 "executable sibling assets should be found from unrelated CWD");
}

bool test_executable_relative_share_assets_work()
{
    fs::path root = make_temp_root("space_asset_share");
    ScopedEnv env("SPACE_ASSETS_PATH", std::nullopt);
    ScopedEnv xdg("XDG_DATA_HOME", (root / "xdg").string());
    fs::create_directories(root / "work");
    ScopedCwd cwd(root / "work");
    AssetManager::clearExecutablePathForTests();
    AssetManager::setExecutablePath(root / "pkg" / "bin" / "space");

    touch(root / "pkg" / "share" / "space" / "assets" / "lua" / "marker.txt");
    return check(path_equals(AssetManager::getAssetPath("lua"), root / "pkg" / "share" / "space" / "assets" / "lua"),
                 "executable-relative ../share/space/assets should be found");
}

bool test_cwd_assets_fallback_remains()
{
    fs::path root = make_temp_root("space_asset_cwd");
    ScopedEnv env("SPACE_ASSETS_PATH", std::nullopt);
    ScopedEnv xdg("XDG_DATA_HOME", (root / "xdg").string());
    fs::create_directories(root / "work");
    ScopedCwd cwd(root / "work");
    AssetManager::clearExecutablePathForTests();
    AssetManager::setExecutablePath(root / "bin" / "space");

    touch(root / "work" / "assets" / "lua" / "marker.txt");
    return check(path_equals(AssetManager::getAssetPath("lua"), root / "work" / "assets" / "lua"),
                 "existing CWD assets fallback should remain");
}

bool test_missing_error_lists_requested_asset_and_searched_paths()
{
    fs::path root = make_temp_root("space_asset_missing");
    ScopedEnv env("SPACE_ASSETS_PATH", (root / "env").string());
    ScopedEnv xdg("XDG_DATA_HOME", (root / "xdg").string());
    fs::create_directories(root / "work");
    ScopedCwd cwd(root / "work");
    AssetManager::clearExecutablePathForTests();
    AssetManager::setExecutablePath(root / "pkg" / "bin" / "space");

    try {
        (void)AssetManager::getAssetPath("missing.asset");
    } catch (const std::runtime_error& e) {
        std::string message = e.what();
        std::vector<std::string> expected = {
            "Asset not found: missing.asset",
            (root / "env" / "missing.asset").string(),
            (root / "xdg" / "space" / "assets" / "missing.asset").string(),
            (root / "pkg" / "bin" / "assets" / "missing.asset").string(),
            (root / "pkg" / "share" / "space" / "assets" / "missing.asset").string(),
            (root / "pkg" / "Resources" / "assets" / "missing.asset").string(),
            (root / "work" / "assets" / "missing.asset").string(),
            "/usr/share/space/assets/missing.asset",
        };
        for (const std::string& text : expected) {
            if (!check(message.find(text) != std::string::npos, "missing error should include: " + text)) {
                std::cerr << "actual: " << message << "\n";
                return false;
            }
        }
        return true;
    }

    std::cerr << "FAIL: missing asset should throw\n";
    return false;
}

} // namespace

int main()
{
    bool ok = true;
    ok = test_env_override_has_highest_priority() && ok;
    ok = test_user_data_precedes_executable_assets() && ok;
    ok = test_executable_sibling_assets_work_from_unrelated_cwd() && ok;
    ok = test_executable_relative_share_assets_work() && ok;
    ok = test_cwd_assets_fallback_remains() && ok;
    ok = test_missing_error_lists_requested_asset_and_searched_paths() && ok;
    AssetManager::clearExecutablePathForTests();
    return ok ? 0 : 1;
}
```

- [ ] **Step 2: Register the failing AssetManager test**

Add to `CMakeLists.txt`:

```cmake
add_executable(test_asset_manager
    tests/test_asset_manager.cpp
    src/asset_manager.cpp
    src/appdirs.cpp
)
target_include_directories(test_asset_manager PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/src)
add_test(NAME test_asset_manager COMMAND test_asset_manager)
set_tests_properties(test_asset_manager PROPERTIES
    WORKING_DIRECTORY ${CMAKE_BINARY_DIR}
)
```

- [ ] **Step 3: Run the focused test and verify failure**

Run:

```bash
cmake --build build --target test_asset_manager -- -j"$(nproc)"
ctest --test-dir build -R test_asset_manager --output-on-failure
```

Expected: compile fails because `AssetManager::setExecutablePath` and `AssetManager::clearExecutablePathForTests` do not exist, or assertions fail with the current CWD-only behavior.

- [ ] **Step 4: Extend the AssetManager header**

Modify `src/asset_manager.h`:

```cpp
#pragma once

#include <filesystem>
#include <optional>
#include <string>

class AssetManager {
public:
    static std::string getAssetPath(const std::string& relativePath);
    static void setExecutablePath(const std::filesystem::path& executablePath);
    static void clearExecutablePathForTests();

private:
    static std::string systemAssetsRoot;
    static std::optional<std::filesystem::path> executablePath;
};
```

- [ ] **Step 5: Implement the search order and diagnostics**

Modify `src/asset_manager.cpp` so `getAssetPath` builds root candidates in this order, deduplicates by normalized root, appends `relativePath`, returns the first existing candidate, and throws with searched candidate paths when none exists:

```cpp
// Candidate root order:
// 1. non-empty SPACE_ASSETS_PATH
// 2. get_user_data_dir("space") / "assets"
// 3. executablePath->parent_path() / "assets"
// 4. executablePath->parent_path() / ".." / "share" / "space" / "assets"
// 5. executablePath->parent_path() / ".." / "Resources" / "assets"
// 6. fs::current_path() / "assets"
// 7. systemAssetsRoot
```

Use `fs::exists(candidate, ec)`, not throwing filesystem calls, during probing. The missing error must start with:

```cpp
"Asset not found: " + relativePath + "\nSearched paths:\n" + searchedPathsText
```

- [ ] **Step 6: Run the AssetManager test**

Run:

```bash
cmake --build build --target test_asset_manager -- -j"$(nproc)"
ctest --test-dir build -R test_asset_manager --output-on-failure
```

Expected: `test_asset_manager` passes.

- [ ] **Step 7: Run utility and AssetManager tests together**

Run:

```bash
ctest --test-dir build -R 'test_executable_path|test_asset_manager' --output-on-failure
```

Expected: both tests pass.

- [ ] **Step 8: Commit Task 2**

```bash
git add CMakeLists.txt src/asset_manager.h src/asset_manager.cpp tests/test_asset_manager.cpp
git commit -m "feat(assets): search executable-relative asset roots"
```

---

### Task 3: Runtime Startup Wiring and Arbitrary-CWD Smoke Test

**Files:**
- Modify: `apps/space/main.cpp`
- Modify: `src/cef_runtime.cpp`
- Modify: `CMakeLists.txt`
- Create: `tests/test_runtime_asset_discovery_integration.cpp`

**Interfaces:**
- Consumes:
  - `executable_path::resolve(const char* argv0)`
  - `executable_path::sibling(const std::filesystem::path&, const std::filesystem::path&)`
  - `AssetManager::setExecutablePath(const std::filesystem::path&)`
- Produces:
  - Runtime startup configures AssetManager before `LuaRuntime::init()`.
  - CEF helper/resource path logic uses the shared executable utility.
  - CTest `test_runtime_asset_discovery_integration`.

- [ ] **Step 1: Write the failing arbitrary-CWD integration test**

Create `tests/test_runtime_asset_discovery_integration.cpp`:

```cpp
#include <array>
#include <cstdio>
#include <cstdlib>
#include <filesystem>
#include <iostream>
#include <string>

#if !defined(_WIN32)
#include <sys/wait.h>
#endif

namespace fs = std::filesystem;

namespace {

bool set_env_var(const std::string& key, const std::string& value)
{
#if defined(_WIN32)
    return _putenv_s(key.c_str(), value.c_str()) == 0;
#else
    return setenv(key.c_str(), value.c_str(), 1) == 0;
#endif
}

bool unset_env_var(const std::string& key)
{
#if defined(_WIN32)
    return _putenv_s(key.c_str(), "") == 0;
#else
    return unsetenv(key.c_str()) == 0;
#endif
}

std::string shell_quote(const std::string& value)
{
#if defined(_WIN32)
    std::string quoted = "\"";
    for (char c : value) {
        if (c == '"') {
            quoted += "\\\"";
        } else {
            quoted.push_back(c);
        }
    }
    quoted.push_back('"');
    return quoted;
#else
    std::string quoted = "'";
    for (char c : value) {
        if (c == '\'') {
            quoted += "'\\''";
        } else {
            quoted.push_back(c);
        }
    }
    quoted.push_back('\'');
    return quoted;
#endif
}

bool run_command_capture(const std::string& command, std::string& output, int& exitCode)
{
    std::array<char, 256> buffer {};
    std::string fullCommand = command + " 2>&1";
#if defined(_WIN32)
    FILE* pipe = _popen(fullCommand.c_str(), "r");
#else
    FILE* pipe = popen(fullCommand.c_str(), "r");
#endif
    if (!pipe) {
        return false;
    }
    output.clear();
    while (fgets(buffer.data(), static_cast<int>(buffer.size()), pipe) != nullptr) {
        output.append(buffer.data());
    }
#if defined(_WIN32)
    int status = _pclose(pipe);
    exitCode = status;
    return status != -1;
#else
    int status = pclose(pipe);
    if (status == -1) {
        return false;
    }
    exitCode = WIFEXITED(status) ? WEXITSTATUS(status) : 128;
    return true;
#endif
}

bool check(bool condition, const std::string& message)
{
    if (!condition) {
        std::cerr << "FAIL: " << message << "\n";
        return false;
    }
    return true;
}

} // namespace

int main()
{
#if defined(_WIN32)
    const fs::path executable = fs::current_path() / "space.exe";
#else
    const fs::path executable = fs::current_path() / "space";
#endif
    const fs::path unrelatedCwd = fs::temp_directory_path() / "space_runtime_asset_discovery_cwd";
    const fs::path xdgHome = fs::temp_directory_path() / "space_runtime_asset_discovery_xdg";
    fs::create_directories(unrelatedCwd);
    fs::create_directories(xdgHome);

    if (!check(fs::exists(executable), "space executable should exist at " + executable.string())) {
        return 1;
    }
    if (!check(fs::exists(fs::current_path() / "assets" / "lua"),
               "build assets/lua should exist next to space executable")) {
        return 1;
    }
    if (!unset_env_var("SPACE_ASSETS_PATH") ||
        !set_env_var("SPACE_DISABLE_AUDIO", "1") ||
        !set_env_var("XDG_DATA_HOME", xdgHome.string())) {
        std::cerr << "FAIL: failed to configure test environment\n";
        return 1;
    }

    std::string command =
        "cd " + shell_quote(unrelatedCwd.string()) + " && " +
        shell_quote(executable.string()) + " --no-dotenv -c " +
        shell_quote("(print (+ 5 3))");

    std::string output;
    int exitCode = 1;
    if (!check(run_command_capture(command, output, exitCode), "run arbitrary-CWD command")) {
        return 1;
    }
    if (!check(exitCode == 0, "arbitrary-CWD command should exit 0")) {
        std::cerr << output << "\n";
        return 1;
    }
    if (!check(output.find("8") != std::string::npos, "Fennel command should print 8")) {
        std::cerr << output << "\n";
        return 1;
    }
    return 0;
}
```

- [ ] **Step 2: Register the failing integration test**

Add to `CMakeLists.txt`:

```cmake
add_executable(test_runtime_asset_discovery_integration
    tests/test_runtime_asset_discovery_integration.cpp
)
add_test(NAME test_runtime_asset_discovery_integration COMMAND test_runtime_asset_discovery_integration)
set_tests_properties(test_runtime_asset_discovery_integration PROPERTIES
    WORKING_DIRECTORY ${CMAKE_BINARY_DIR}
)
```

- [ ] **Step 3: Run the smoke test and verify failure before wiring**

Run:

```bash
cmake --build build --target space test_runtime_asset_discovery_integration -- -j"$(nproc)"
ctest --test-dir build -R test_runtime_asset_discovery_integration --output-on-failure
```

Expected before wiring: startup cannot find runtime assets from the unrelated CWD with `SPACE_ASSETS_PATH` unset.

- [ ] **Step 4: Wire AssetManager in `main.cpp`**

Modify `apps/space/main.cpp`:

```cpp
#include "asset_manager.h"
#include "executable_path.h"
```

Remove the local `sibling_path` helper. Near the start of `main`, after logging initialization and before `LuaRuntime runtime; runtime.init();`, resolve and configure:

```cpp
const std::filesystem::path executablePath = executable_path::resolve(argc > 0 ? argv[0] : nullptr);
AssetManager::setExecutablePath(executablePath);
```

Replace the CEF helper path assignment with:

```cpp
cef_config.helper_executable_path =
    executable_path::sibling(executablePath, "space_cef_helper").string();
```

- [ ] **Step 5: Reuse executable utility in CEF runtime**

Modify `src/cef_runtime.cpp`:

```cpp
#include "executable_path.h"
```

Delete the local `executable_dir_from_args` function. Implement `cef_resource_dir_for_executable(char** argv)` using the shared resolver:

```cpp
std::filesystem::path cef_resource_dir_for_executable(char** argv)
{
    std::filesystem::path executable = executable_path::resolve(argv && argv[0] ? argv[0] : nullptr);
    std::filesystem::path exeDir = executable.empty()
        ? std::filesystem::current_path()
        : executable.parent_path();

    std::filesystem::path installedResourceDir = exeDir / ".." / "lib" / "space" / "cef";
    if (std::filesystem::exists(installedResourceDir / "resources.pak")) {
        std::error_code ec;
        std::filesystem::path canonical = std::filesystem::weakly_canonical(installedResourceDir, ec);
        return ec ? installedResourceDir.lexically_normal() : canonical;
    }
    return exeDir;
}
```

- [ ] **Step 6: Ensure the CEF helper target links the utility source**

Modify the `space_cef_helper` target in `CMakeLists.txt` when `SPACE_ENABLE_CEF` is on:

```cmake
add_executable(space_cef_helper
    apps/space/cef_subprocess_main.cpp
    src/cef_runtime.cpp
    src/executable_path.cpp
)
```

The main `${PROJECT_NAME}` target links `${PROJECT_NAME}_lib`, and `src/*.cpp` is globbed into that library, so adding `src/executable_path.cpp` is enough for the main executable after rerunning CMake.

- [ ] **Step 7: Run focused runtime tests**

Run:

```bash
cmake --build build --target space test_runtime_asset_discovery_integration -- -j"$(nproc)"
ctest --test-dir build -R 'test_executable_path|test_asset_manager|test_runtime_asset_discovery_integration' --output-on-failure
```

Expected: all three tests pass.

- [ ] **Step 8: Run manual arbitrary-CWD smoke command**

Run:

```bash
tmp="$(mktemp -d)"
env -u SPACE_ASSETS_PATH SPACE_DISABLE_AUDIO=1 XDG_DATA_HOME="$tmp/xdg" \
  bash -lc "cd '$tmp' && '$(pwd)/build/space' --no-dotenv -c '(print (+ 5 3))'"
```

Expected: command exits 0 and prints `8`.

- [ ] **Step 9: Commit Task 3**

```bash
git add CMakeLists.txt apps/space/main.cpp src/cef_runtime.cpp tests/test_runtime_asset_discovery_integration.cpp
git commit -m "feat(assets): configure runtime asset discovery at startup"
```

---

### Task 4: Documentation, Validation, and Final Task Commit

**Files:**
- Modify: `docs/dev/building.md`

**Interfaces:**
- Consumes: implemented asset search order from Task 2 and startup behavior from Task 3.
- Produces: developer documentation for direct binary execution and asset lookup order.

- [ ] **Step 1: Update developer build documentation**

Modify `docs/dev/building.md` near the existing direct-run guidance after:

```markdown
To run the app directly, use `./build/space -m main`.
By default, `./build/space` also starts the main app; use `./build/space --repl` for the embedded Fennel REPL.
```

Add:

````markdown
### Runtime asset discovery

Direct binary execution is supported from arbitrary working directories. After a normal build, assets are copied next to the executable at `build/assets`, so commands such as this work even outside the repository root:

```bash
tmp="$(mktemp -d)"
cd "$tmp"
SPACE_DISABLE_AUDIO=1 /path/to/space/build/space --no-dotenv -c '(print (+ 5 3))'
```

Asset roots are searched in this order:

1. `SPACE_ASSETS_PATH`, when non-empty.
2. User data assets: `get_user_data_dir("space") / "assets"`.
3. Developer/build sibling assets: `<exe_dir>/assets`.
4. Install or portable layout: `<exe_dir>/../share/space/assets`.
5. macOS-style bundle layout, if applicable: `<exe_dir>/../Resources/assets`.
6. Working-directory fallback: `<cwd>/assets`.
7. Legacy system fallback: `/usr/share/space/assets`.

`SPACE_ASSETS_PATH` is an explicit override for custom asset roots and remains the highest-priority lookup location. It is not required for normal build, installed, or portable runtime layouts.
````

- [ ] **Step 2: Run focused validation**

Run:

```bash
cmake --build build --target test_executable_path test_asset_manager test_runtime_asset_discovery_integration space -- -j"$(nproc)"
ctest --test-dir build -R 'test_executable_path|test_asset_manager|test_runtime_asset_discovery_integration' --output-on-failure
```

Expected: focused tests pass.

- [ ] **Step 3: Run complete relevant suite**

Run:

```bash
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH="$(pwd)/assets" make test
```

Expected: full CTest suite passes.

- [ ] **Step 4: Run broader startup smoke check**

Run:

```bash
tmp="$(mktemp -d)"
env -u SPACE_ASSETS_PATH SPACE_DISABLE_AUDIO=1 XDG_DATA_HOME="$tmp/xdg" \
  bash -lc "cd '$tmp' && '$(pwd)/build/space' --no-dotenv -c '(print (+ 5 3))'"
```

Expected: command exits 0 and prints `8`.

- [ ] **Step 5: Run E2E if outside-sandbox runtime is available**

Run when the environment supports outside-sandbox graphical/E2E execution:

```bash
SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH="$(pwd)/assets" make test-e2e
```

Expected: E2E suite passes. If unavailable because the environment cannot run outside-sandbox graphical tests, record that limitation in the final implementation summary.

- [ ] **Step 6: Commit Task 4**

```bash
git add docs/dev/building.md
git commit -m "docs(assets): document runtime asset discovery"
```

- [ ] **Step 7: Final status check**

Run:

```bash
git status --short
git log --oneline -4
```

Expected: working tree is clean and recent commits correspond to the executable utility, AssetManager lookup, runtime wiring, and documentation.
