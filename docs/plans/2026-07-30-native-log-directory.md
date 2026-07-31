# Native Log Directory Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Space initialize native logging to a deliberate user log directory instead of creating `gl.log` in arbitrary current working directories.

**Architecture:** Add a Space-specific C++ log path resolver that chooses `SPACE_LOG_DIR` or `get_user_log_dir("space")`, then wire that path into native logger configuration before the first `log_init`. Keep the generic logger reusable by adding explicit `LogConfig::output_path` plumbing, and keep Fennel app startup aligned by preserving the native-selected path.

**Tech Stack:** C++17, `std::filesystem`, existing `appdirs`, spdlog, CMake/CTest, Fennel logging binding.

## Global Constraints

- Make native logging choose a deliberate log path before the first C++ `log_init` call.
- Preserve non-empty `SPACE_LOG_DIR` as the explicit log directory override.
- Default to `get_user_log_dir("space") / "space.log"` when no override is set.
- Ensure CLI, stdin, file, REPL, and module modes do not write `gl.log` in an arbitrary current working directory.
- Fail loudly if the selected log directory cannot be created or used.
- Keep the existing Lua/Fennel `logging.init {:path ...}` API usable.
- Do not add `LOGS_DIR` or other environment variable aliases.
- Do not change runtime asset discovery behavior.
- Do not redesign auxiliary logs such as terrain issue logs.
- Do not change the existing spdlog rotation policy.
- Keep C++17 compatibility and add no third-party dependencies.

---

## File Structure

- Create `src/space_log_path.h`: public Space log path resolver interface.
- Create `src/space_log_path.cpp`: `SPACE_LOG_DIR`/appdirs resolution and directory creation checks.
- Modify `src/log.h`: add `LogConfig::output_path`.
- Modify `src/log.cpp`: make `log_init` and `log_set_output_path` use the explicit output path consistently.
- Modify `src/lua_logging.cpp`: parse `logging.init {:path ...}` into `LogConfig::output_path` without parse-time reinitialization side effects.
- Modify `apps/space/main.cpp`: resolve, create, and assign the log path before first `log_init`.
- Modify `assets/lua/main.fnl`: preserve the native-selected output path during normal app logging setup.
- Create `tests/test_space_log_path.cpp`: unit coverage for path resolution and directory checks.
- Create `tests/test_native_logging_integration.cpp`: spawned runtime coverage for arbitrary-CWD logging behavior.
- Modify `CMakeLists.txt`: register the new tests.
- Modify `docs/dev/building.md`: document native log location and `SPACE_LOG_DIR`.

## Acceptance Criteria

- Running `space --no-dotenv -c ...` from an unrelated directory does not create `gl.log` there.
- Default native logs go to `get_user_log_dir("space") / "space.log"`.
- Non-empty `SPACE_LOG_DIR` sends native logs to `<SPACE_LOG_DIR>/space.log`.
- Invalid log directory setup exits non-zero with stderr containing `failed to initialize logging`.
- Existing `logging.init {:path ...}` API remains usable.
- `docs/dev/building.md` documents the operational behavior.

## Validation Ladder

1. Focused during implementation:
   ```bash
   make cmake
   cmake --build build --target test_space_log_path test_native_logging_integration space -- -j"$(nproc)"
   ctest --test-dir build -R 'test_space_log_path|test_native_logging_integration|test_runtime_asset_discovery_integration' --output-on-failure
   ```
2. Complete relevant suite:
   ```bash
   python3 scripts/ctest-summary.py --test-dir build --output-on-failure
   ```
3. Final startup/logging risk check:
   ```bash
   SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH="$(pwd)/assets" make test
   ```
4. E2E, if the outside-sandbox graphical environment is available:
   ```bash
   SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH="$(pwd)/assets" make test-e2e
   ```

## Out of Scope

- Changing runtime asset discovery behavior.
- Adding `LOGS_DIR` compatibility.
- Renaming Lua/Fennel logging APIs.
- Redesigning auxiliary logs such as `terrain-issue.log`.
- Changing log rotation size, file count, or formatting.

---

### Task 1: Native Log Path Resolver and Logger Configuration Plumbing

**Files:**
- Create: `src/space_log_path.h`
- Create: `src/space_log_path.cpp`
- Create: `tests/test_space_log_path.cpp`
- Modify: `src/log.h`
- Modify: `src/log.cpp`
- Modify: `src/lua_logging.cpp`
- Modify: `CMakeLists.txt`

**Interfaces:**
- Consumes: `std::string get_user_log_dir(const std::string& app_name)` from `src/appdirs.h`.
- Produces:
  - `std::filesystem::path space_log::resolve_log_dir()`
  - `std::filesystem::path space_log::resolve_log_path()`
  - `void space_log::ensure_log_directory(const std::filesystem::path& logPath)`
  - `LogConfig::output_path: std::string`

- [ ] **Step 1: Write the failing log path unit test**

Create `tests/test_space_log_path.cpp` with coverage for override, default, empty override, and invalid parent behavior:

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

#include "space_log_path.h"

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

fs::path make_temp_root(const std::string& name)
{
    auto stamp = std::chrono::steady_clock::now().time_since_epoch().count();
    fs::path root = fs::temp_directory_path() / (name + "_" + std::to_string(stamp));
    fs::create_directories(root);
    return root;
}

bool check(bool condition, const std::string& message)
{
    if (!condition) {
        std::cerr << "FAIL: " << message << "\n";
        return false;
    }
    return true;
}

bool test_space_log_dir_override()
{
    fs::path root = make_temp_root("space_log_override");
    ScopedEnv logDir("SPACE_LOG_DIR", (root / "logs").string());
    ScopedEnv xdg("XDG_CACHE_HOME", (root / "cache").string());
    return check(space_log::resolve_log_path() == root / "logs" / "space.log",
                 "SPACE_LOG_DIR should select <dir>/space.log");
}

bool test_empty_space_log_dir_uses_default()
{
    fs::path root = make_temp_root("space_log_empty_override");
    ScopedEnv logDir("SPACE_LOG_DIR", std::string(""));
    ScopedEnv xdg("XDG_CACHE_HOME", (root / "cache").string());
    return check(space_log::resolve_log_path() == root / "cache" / "space" / "log" / "space.log",
                 "empty SPACE_LOG_DIR should use appdirs default");
}

bool test_default_uses_user_log_dir()
{
    fs::path root = make_temp_root("space_log_default");
    ScopedEnv logDir("SPACE_LOG_DIR", std::nullopt);
    ScopedEnv xdg("XDG_CACHE_HOME", (root / "cache").string());
    return check(space_log::resolve_log_path() == root / "cache" / "space" / "log" / "space.log",
                 "default should use XDG cache app log dir on Linux-style appdirs");
}

bool test_ensure_log_directory_creates_parent()
{
    fs::path root = make_temp_root("space_log_create");
    fs::path path = root / "new" / "logs" / "space.log";
    space_log::ensure_log_directory(path);
    return check(fs::is_directory(path.parent_path()), "ensure_log_directory should create parent dirs");
}

bool test_ensure_log_directory_rejects_file_parent()
{
    fs::path root = make_temp_root("space_log_invalid");
    fs::path fileParent = root / "not-a-dir";
    std::ofstream out(fileParent);
    out << "not a directory\n";
    out.close();

    try {
        space_log::ensure_log_directory(fileParent / "space.log");
    } catch (const std::runtime_error& e) {
        std::string message = e.what();
        return check(message.find("not a directory") != std::string::npos ||
                         message.find(fileParent.string()) != std::string::npos,
                     "invalid parent error should mention the parent path");
    }

    std::cerr << "FAIL: ensure_log_directory should throw for file parent\n";
    return false;
}

} // namespace

int main()
{
    bool ok = true;
    ok = test_space_log_dir_override() && ok;
    ok = test_empty_space_log_dir_uses_default() && ok;
    ok = test_default_uses_user_log_dir() && ok;
    ok = test_ensure_log_directory_creates_parent() && ok;
    ok = test_ensure_log_directory_rejects_file_parent() && ok;
    return ok ? 0 : 1;
}
```

- [ ] **Step 2: Register the failing unit test**

Add near other C++ tests in `CMakeLists.txt`:

```cmake
add_executable(test_space_log_path
    tests/test_space_log_path.cpp
    src/space_log_path.cpp
    src/appdirs.cpp
)
target_include_directories(test_space_log_path PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/src)
add_test(NAME test_space_log_path COMMAND test_space_log_path)
set_tests_properties(test_space_log_path PROPERTIES
    WORKING_DIRECTORY ${CMAKE_BINARY_DIR}
)
```

- [ ] **Step 3: Run the focused test and verify failure**

Run:

```bash
make cmake
cmake --build build --target test_space_log_path -- -j"$(nproc)"
```

Expected: build fails because `src/space_log_path.h` and `src/space_log_path.cpp` do not exist.

- [ ] **Step 4: Add the log path resolver header**

Create `src/space_log_path.h`:

```cpp
#pragma once

#include <filesystem>

namespace space_log {

std::filesystem::path resolve_log_dir();
std::filesystem::path resolve_log_path();
void ensure_log_directory(const std::filesystem::path& logPath);

} // namespace space_log
```

- [ ] **Step 5: Add the log path resolver implementation**

Create `src/space_log_path.cpp`:

```cpp
#include "space_log_path.h"

#include <cstdlib>
#include <stdexcept>
#include <string>
#include <system_error>

#include "appdirs.h"

namespace fs = std::filesystem;

namespace space_log {

fs::path resolve_log_dir()
{
    if (const char* envLogDir = std::getenv("SPACE_LOG_DIR")) {
        if (envLogDir[0] != '\0') {
            return fs::path(envLogDir);
        }
    }
    return fs::path(get_user_log_dir("space"));
}

fs::path resolve_log_path()
{
    return resolve_log_dir() / "space.log";
}

void ensure_log_directory(const fs::path& logPath)
{
    fs::path parent = logPath.parent_path();
    if (parent.empty()) {
        throw std::runtime_error("log path has no parent directory: " + logPath.string());
    }

    std::error_code ec;
    if (fs::exists(parent, ec)) {
        if (!fs::is_directory(parent, ec)) {
            throw std::runtime_error("log directory is not a directory: " + parent.string());
        }
        return;
    }

    if (!fs::create_directories(parent, ec) && ec) {
        throw std::runtime_error("failed to create log directory " + parent.string() + ": " + ec.message());
    }
    if (!fs::is_directory(parent, ec)) {
        throw std::runtime_error("log directory is not a directory after creation: " + parent.string());
    }
}

} // namespace space_log
```

- [ ] **Step 6: Add output path to `LogConfig`**

Modify `src/log.h` so `LogConfig` includes the selected path:

```cpp
struct LogConfig {
    LogLevel reporting_level = Info;
    bool restart = false;
    std::string output_path;
};
```

- [ ] **Step 7: Update native logger path plumbing**

Modify `src/log.cpp` so `log_init` selects and persists the configured path before constructing the rotating sink. Insert this block immediately after `spdlog::shutdown();`:

```cpp
std::string selected_output_path = config.output_path.empty()
    ? log_output_path
    : config.output_path;
if (selected_output_path.empty()) {
    selected_output_path = std::string(GL_LOG_FILE);
}
log_output_path = selected_output_path;
```

Keep the existing `rotating_file_sink_mt(log_output_path, 5 * 1024 * 1024, 3)` construction. Replace the current `LOG_CONFIG.reporting_level = config.reporting_level;` assignment with all three persisted fields before `log_ready = true;`:

```cpp
LOG_CONFIG.reporting_level = config.reporting_level;
LOG_CONFIG.restart = config.restart;
LOG_CONFIG.output_path = log_output_path;
```

Update `log_set_output_path` to reinitialize through `LogConfig::output_path`:

```cpp
void log_set_output_path(const std::string& path)
{
    LogConfig config = LOG_CONFIG;
    config.output_path = path.empty() ? std::string(GL_LOG_FILE) : path;
    config.restart = false;
    log_init(config);
}
```

- [ ] **Step 8: Remove parse-time logging side effects from Lua logging config**

Modify `src/lua_logging.cpp::parse_config` so `:path` fills `config.output_path` instead of calling `log_set_output_path`:

```cpp
sol::object path_obj = table["path"];
if (path_obj.is<std::string>()) {
    config.output_path = path_obj.as<std::string>();
}
```

Keep `logging_table.set_function("get-output-path", &log_get_output_path);` unchanged.

- [ ] **Step 9: Run focused unit validation**

Run:

```bash
cmake --build build --target test_space_log_path -- -j"$(nproc)"
ctest --test-dir build -R test_space_log_path --output-on-failure
```

Expected: `test_space_log_path` passes.

- [ ] **Step 10: Run existing logging-related coverage**

Run:

```bash
ctest --test-dir build -R 'test_space_log_path|space_fnl_tests' --output-on-failure
```

Expected: both selected tests pass.

- [ ] **Step 11: Commit Task 1**

```bash
git add CMakeLists.txt src/space_log_path.h src/space_log_path.cpp src/log.h src/log.cpp src/lua_logging.cpp tests/test_space_log_path.cpp
git commit -m "feat(engine): add native log path configuration"
```

---

### Task 2: Bootstrap Wiring, Integration Tests, and Documentation

**Files:**
- Modify: `apps/space/main.cpp`
- Modify: `assets/lua/main.fnl`
- Create: `tests/test_native_logging_integration.cpp`
- Modify: `CMakeLists.txt`
- Modify: `docs/dev/building.md`

**Interfaces:**
- Consumes:
  - `space_log::resolve_log_path() -> std::filesystem::path`
  - `space_log::ensure_log_directory(const std::filesystem::path&) -> void`
  - `LogConfig::output_path`
  - `logging.get-output-path` from the existing Lua logging module
- Produces:
  - Space executable initializes native logging to a resolved `space.log` before any runtime mode executes.

- [ ] **Step 1: Write the failing native logging integration test**

Create `tests/test_native_logging_integration.cpp`:

```cpp
#include <array>
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <filesystem>
#include <fstream>
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

fs::path make_temp_root(const std::string& name)
{
    auto stamp = std::chrono::steady_clock::now().time_since_epoch().count();
    fs::path root = fs::temp_directory_path() / (name + "_" + std::to_string(stamp));
    fs::create_directories(root);
    return root;
}

bool check(bool condition, const std::string& message)
{
    if (!condition) {
        std::cerr << "FAIL: " << message << "\n";
        return false;
    }
    return true;
}

fs::path space_executable()
{
#if defined(_WIN32)
    return fs::current_path() / "space.exe";
#else
    return fs::current_path() / "space";
#endif
}

std::string logging_command(const fs::path& cwd, const fs::path& executable)
{
    return "cd " + shell_quote(cwd.string()) + " && " +
        shell_quote(executable.string()) + " --no-dotenv -c " +
        shell_quote("(do (local logging (require :logging)) (logging.info \"native logging integration\") (logging.flush))");
}

bool run_space_with_env(const fs::path& cwd, const fs::path& executable, std::string& output, int& exitCode)
{
    return run_command_capture(logging_command(cwd, executable), output, exitCode);
}

bool test_default_log_path()
{
    fs::path root = make_temp_root("space_native_log_default");
    fs::path cwd = root / "cwd";
    fs::path xdg = root / "xdg-cache";
    fs::create_directories(cwd);
    unset_env_var("SPACE_LOG_DIR");
    set_env_var("XDG_CACHE_HOME", xdg.string());
    set_env_var("SPACE_DISABLE_AUDIO", "1");

    std::string output;
    int exitCode = 1;
    if (!check(run_space_with_env(cwd, space_executable(), output, exitCode), "run default logging command")) {
        return false;
    }
    if (!check(exitCode == 0, "default logging command should exit 0")) {
        std::cerr << output << "\n";
        return false;
    }
    return check(fs::exists(xdg / "space" / "log" / "space.log"), "default log file should exist") &&
        check(!fs::exists(cwd / "gl.log"), "default run should not create cwd gl.log");
}

bool test_space_log_dir_override()
{
    fs::path root = make_temp_root("space_native_log_override");
    fs::path cwd = root / "cwd";
    fs::path logs = root / "custom-logs";
    fs::create_directories(cwd);
    set_env_var("SPACE_LOG_DIR", logs.string());
    set_env_var("XDG_CACHE_HOME", (root / "xdg-cache").string());
    set_env_var("SPACE_DISABLE_AUDIO", "1");

    std::string output;
    int exitCode = 1;
    if (!check(run_space_with_env(cwd, space_executable(), output, exitCode), "run override logging command")) {
        return false;
    }
    if (!check(exitCode == 0, "override logging command should exit 0")) {
        std::cerr << output << "\n";
        return false;
    }
    return check(fs::exists(logs / "space.log"), "SPACE_LOG_DIR log file should exist") &&
        check(!fs::exists(cwd / "gl.log"), "override run should not create cwd gl.log");
}

bool test_invalid_log_directory_fails_loudly()
{
    fs::path root = make_temp_root("space_native_log_invalid");
    fs::path cwd = root / "cwd";
    fs::path notADir = root / "not-a-dir";
    fs::create_directories(cwd);
    std::ofstream out(notADir);
    out << "not a directory\n";
    out.close();

    set_env_var("SPACE_LOG_DIR", (notADir / "child").string());
    set_env_var("XDG_CACHE_HOME", (root / "xdg-cache").string());
    set_env_var("SPACE_DISABLE_AUDIO", "1");

    std::string output;
    int exitCode = 0;
    if (!check(run_space_with_env(cwd, space_executable(), output, exitCode), "run invalid logging command")) {
        return false;
    }
    return check(exitCode != 0, "invalid logging command should fail") &&
        check(output.find("failed to initialize logging") != std::string::npos,
              "invalid logging command should print explicit startup error") &&
        check(!fs::exists(cwd / "gl.log"), "invalid run should not create cwd gl.log");
}

} // namespace

int main()
{
    if (!check(fs::exists(space_executable()), "space executable should exist in build dir")) {
        return 1;
    }
    bool ok = true;
    ok = test_default_log_path() && ok;
    ok = test_space_log_dir_override() && ok;
    ok = test_invalid_log_directory_fails_loudly() && ok;
    return ok ? 0 : 1;
}
```

- [ ] **Step 2: Register the failing integration test**

Add to `CMakeLists.txt`:

```cmake
add_executable(test_native_logging_integration
    tests/test_native_logging_integration.cpp
)
add_test(NAME test_native_logging_integration COMMAND test_native_logging_integration)
set_tests_properties(test_native_logging_integration PROPERTIES
    WORKING_DIRECTORY ${CMAKE_BINARY_DIR}
)
```

- [ ] **Step 3: Run the integration test and verify failure before wiring**

Run:

```bash
cmake --build build --target space test_native_logging_integration -- -j"$(nproc)"
ctest --test-dir build -R test_native_logging_integration --output-on-failure
```

Expected before wiring: the test fails because default CLI logging creates `gl.log` in the unrelated CWD or does not create the expected appdirs log.

- [ ] **Step 4: Wire native log path before first `log_init`**

Modify `apps/space/main.cpp`:

```cpp
#include "space_log_path.h"
```

At the start of `main`, before `log_init(LOG_CONFIG)`, resolve and validate the path:

```cpp
int main(int argc, char *argv[])
{
    LOG_CONFIG.reporting_level = Debug;
    LOG_CONFIG.restart = true;
    try {
        std::filesystem::path logPath = space_log::resolve_log_path();
        space_log::ensure_log_directory(logPath);
        LOG_CONFIG.output_path = logPath.string();
        log_init(LOG_CONFIG);
    }
    catch (const std::exception& e) {
        std::cerr << "error: failed to initialize logging: " << e.what() << "\n";
        return 1;
    }
```

Keep the existing asset executable-path setup after logging initialization.

- [ ] **Step 5: Keep Fennel main aligned with native-selected path**

Modify the startup logging block in `assets/lua/main.fnl` from recomputing `SPACE_LOG_DIR` to preserving the native path:

```fennel
(local log-path (logging.get-output-path))
(logging.init {:path log-path})
```

Do not remove the existing `(local appdirs (require :appdirs))`, because later code in `main.fnl` uses it for cache and data directories.

- [ ] **Step 6: Document runtime log location**

Update `docs/dev/building.md` near the runtime asset discovery section with:

```markdown
### Runtime log location

Native logging is configured during C++ startup before any entry mode runs. By default, logs are written to `get_user_log_dir("space") / "space.log"`; on Linux this is `${XDG_CACHE_HOME:-~/.cache}/space/log/space.log`.

Set `SPACE_LOG_DIR` to a non-empty directory to override the log directory. The runtime writes `space.log` inside that directory. `LOGS_DIR` is not used by Space. Direct CLI modes such as `space --no-dotenv -c ...` do not write `gl.log` into the current working directory as part of normal startup.
```

- [ ] **Step 7: Run focused validation**

Run:

```bash
cmake --build build --target test_space_log_path test_native_logging_integration space -- -j"$(nproc)"
ctest --test-dir build -R 'test_space_log_path|test_native_logging_integration|test_runtime_asset_discovery_integration' --output-on-failure
```

Expected: focused logging and asset-discovery smoke tests pass.

- [ ] **Step 8: Run complete relevant suite**

Run:

```bash
python3 scripts/ctest-summary.py --test-dir build --output-on-failure
```

Expected: CTest suite passes.

- [ ] **Step 9: Run final startup/logging risk check**

Run:

```bash
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH="$(pwd)/assets" make test
```

Expected: full project test suite passes.

- [ ] **Step 10: Run E2E if outside-sandbox runtime is available**

Run when the environment supports outside-sandbox graphical/E2E execution:

```bash
SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH="$(pwd)/assets" make test-e2e
```

Expected: E2E suite passes. If unavailable because the environment cannot run outside-sandbox graphical tests, record that limitation in the implementation report.

- [ ] **Step 11: Commit Task 2**

```bash
git add CMakeLists.txt apps/space/main.cpp assets/lua/main.fnl tests/test_native_logging_integration.cpp docs/dev/building.md
git commit -m "feat(engine): initialize native logs in user log dir"
```
