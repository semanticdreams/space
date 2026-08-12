Native crash diagnostics report
================================

What changed
------------
- Added gated direct-`stderr` lifecycle diagnostics in `src/lua_http_server.cpp`.
  - Enable with `SPACE_HTTP_LIFECYCLE_DEBUG=1`.
  - Logs HttpServer ctor/dtor/register/unregister, `stop()` entry/exit and phase boundaries around `close_streams`, `svr_.stop`, `fail_pending`, and join, `lua_http_server_shutdown_all` copied server pointers, and gated SSE route/on-close callback begin/end.
  - Entries include server pointer, hashed thread id, running state, pending queue size, and active SSE weak-list size where safely available.
- Added gated direct-`stderr` diagnostics in `src/http_client.cpp`.
  - Enable with `SPACE_HTTP_CLIENT_DEBUG=1`.
  - Logs request submit/cancel, worker start/exit, perform begin/end, shutdown begin/end, and active request count.
- Added gated direct-`stderr` diagnostics in `src/log.cpp`.
  - Enable with `SPACE_LOG_LIFECYCLE_DEBUG=1`.
  - Logs `log_init` begin/end, `log_shutdown` begin/end, and attempts to ensure/get loggers after shutdown begins.
- Diagnostics intentionally avoid spdlog and flush immediately so they can survive suspected spdlog/mutex teardown paths.

Tests and validation
--------------------
- `rtk make build` with 14400000 ms timeout: passed.
- `SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tests.test-http-server:main`: passed, `Executed 13 Lua tests`.
- `SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tests.test-mcp-http:main`: passed, `Executed 11 Lua tests`.
- `SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tests.test-agent-layer:main`: passed, `Executed 97 Lua tests`.

Coverage rationale
------------------
- Build validates the touched C++ compiles and links.
- HTTP server and MCP HTTP tests exercise native server lifecycle and repeated MCP start/stop paths near the reported crash boundary.
- Agent-layer tests exercise the OpenCode/MCP bridge and HTTP client subscription lifecycle touched by diagnostics.

Constraint Impact
-----------------
- not applicable (native diagnostic-only instrumentation; no Fennel behavior or constraint contract changed).

TDD Evidence
------------
- TDD was not used. This task requested diagnostic-only crash-path instrumentation and explicitly allowed narrow existing focused tests at minimum; adding assertions over opt-in stderr diagnostics would be fragile and low value.

Files changed
-------------
- `src/lua_http_server.cpp`
- `src/http_client.cpp`
- `src/http_client.h`
- `src/log.cpp`
- `.superpowers/sdd/native-crash-diagnostics-report.md`

Design/refactor decisions
-------------------------
- Kept diagnostics env-gated to avoid normal runtime noise.
- Used file-local helpers and no shared abstraction to keep scope narrow and avoid broad refactors.
- Used `std::fprintf(stderr, ...)` plus `std::fflush(stderr)` rather than spdlog.
- Did not attempt to fix suspected user-code/native lifecycle behavior.

Self-review findings
--------------------
- Confirmed no edits to `.opencode/opencode.json` or bubbles/user-code areas.
- Confirmed diagnostics are sparse by default and opt-in.

Concerns
--------
- Diagnostics add mutex-protected count sampling around lifecycle events. They are gated and should be low risk, but when enabled they may slightly perturb timing of shutdown races.

Review fix R1-1
================

What changed
------------
- Fixed disabled-path diagnostics in `src/lua_http_server.cpp` and `src/http_client.cpp` so call sites check the env-gated diagnostic flag before sampling mutex-protected counts.
- Added/used object-local `diagnostic_emit` wrappers so disabled `SPACE_HTTP_LIFECYCLE_DEBUG` and `SPACE_HTTP_CLIENT_DEBUG` paths return before calling `pending_count()`, `stream_count()`, or `active_count()`.
- Kept diagnostic-only scope; no behavior fix attempted.

Validation
----------
- `rtk make build` with 14400000 ms timeout: passed.
- `SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tests.test-http-server:main`: passed, `Executed 13 Lua tests`.
- `SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tests.test-mcp-http:main`: passed, `Executed 11 Lua tests`.
- `SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tests.test-agent-layer:main`: passed, `Executed 97 Lua tests`.

Coverage rationale
------------------
- Build validates the C++ signature and call-site changes compile/link.
- The same focused HTTP/MCP/agent tests cover the native lifecycle surfaces where diagnostics were amended.

Constraint Impact
-----------------
- not applicable.

Concerns
--------
- None beyond the existing note that diagnostics can perturb timing when explicitly enabled.

Follow-up: always-on sparse lifecycle markers
=============================================

What changed
------------
- Changed sparse native lifecycle diagnostics from opt-in to default-on so spontaneous crashes capture evidence without prior environment setup.
- Added `SPACE_NATIVE_LIFECYCLE_DIAGNOSTICS=0` as a shared opt-out for always-on sparse lifecycle markers.
- Kept potentially high-volume callback/request diagnostics gated by the existing variables:
  - `SPACE_HTTP_LIFECYCLE_DEBUG=1` still gates SSE route/on-close callback markers.
  - `SPACE_HTTP_CLIENT_DEBUG=1` still gates submit/cancel/perform request markers.
  - `SPACE_LOG_LIFECYCLE_DEBUG=1` still gates `log_init` begin/end markers.
- Always-on direct-`stderr` markers now cover:
  - `src/lua_http_server.cpp`: HttpServer ctor/dtor/register/unregister, `stop()` entry/exit and close_streams/svr.stop/fail_pending/join phase boundaries, and `lua_http_server_shutdown_all` copied server pointers plus per-server stop boundaries.
  - `src/http_client.cpp`: shutdown begin/end/already-stopped and worker start/exit.
  - `src/log.cpp`: `log_shutdown` begin/end and late ensure/get-logger-after-shutdown markers.
- Preserved `std::fprintf(stderr, ...)` plus `std::fflush(stderr)` and did not route diagnostics through spdlog.
- Preserved disabled-path thread safety for high-volume gated diagnostics by retaining early flag checks before mutex-protected count sampling. Always-on lifecycle paths sample only the existing lifecycle counts immediately before direct emission.

Validation
----------
- `rtk make build` with 14400000 ms timeout: passed.
- `SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tests.test-http-server:main`: passed, `Executed 13 Lua tests`.
- `SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tests.test-mcp-http:main`: passed, `Executed 11 Lua tests`.
- `SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tests.test-agent-layer:main`: passed, `Executed 97 Lua tests`.

Coverage rationale
------------------
- Build validates the changed C++ diagnostics compile and link.
- HTTP server tests exercise native server lifecycle, repeated stop/dtor/shutdown-all paths, and demonstrate the default-on lifecycle markers are emitted without opt-in variables.
- MCP HTTP tests exercise repeated MCP server start/stop and SSE lifecycle paths near the suspected crash boundary.
- Agent-layer tests exercise HTTP client worker startup/shutdown and the OpenCode/MCP bridge surfaces touched by diagnostics.

Constraint Impact
-----------------
- not applicable (native diagnostic-only instrumentation; no Fennel behavior or constraint contract changed).

TDD Evidence
------------
- TDD was not used. This diagnostic-only follow-up changes native stderr instrumentation defaults and was validated through the requested focused runtime/build checks rather than fragile assertions over incidental stderr output.

Files changed
-------------
- `src/lua_http_server.cpp`
- `src/http_client.cpp`
- `src/http_client.h`
- `src/log.cpp`
- `.superpowers/sdd/native-crash-diagnostics-report.md`

Design/refactor decisions
-------------------------
- Used a small file-local `native_lifecycle_diagnostics_enabled()` helper in each touched native file to keep scope narrow and avoid cross-file refactors.
- Split sparse lifecycle emission from high-volume diagnostics so per-request/callback code remains env-gated while lifecycle/shutdown markers are captured by default.
- Added only an opt-out environment variable, not new config files, to preserve spontaneous crash evidence by default and avoid editing `.opencode/opencode.json`.

Self-review findings
--------------------
- Confirmed no edits to `.opencode/opencode.json` or bubbles/user-code areas.
- Confirmed submit/cancel/perform and SSE callback diagnostics remain gated and still avoid mutex count sampling when disabled.

Concerns
--------
- Always-on HTTP client worker start/exit emits one line per worker. This is default-on as requested when low volume; current tests show up to hardware-concurrency worker lines at process startup/shutdown, but no per-request diagnostics are default-on.

Review fix R1-1
================

What changed
------------
- Moved HTTP client `worker-start` and `worker-exit` markers back behind `SPACE_HTTP_CLIENT_DEBUG=1`.
- Preserved default-on HTTP client lifecycle summary markers for `shutdown-begin`, `shutdown-end`, and `shutdown-already-stopped`.
- Kept diagnostic-only scope; no runtime lifecycle behavior was changed.

Validation
----------
- `rtk make build` with 14400000 ms timeout: passed.
- `SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tests.test-agent-layer:main`: passed, `Executed 97 Lua tests`.

Coverage rationale
------------------
- Build validates the C++ diagnostic routing change compiles and links.
- Agent-layer tests exercise HTTP client construction/shutdown paths and confirm the focused surface still runs with sparse default-on shutdown markers only.

Constraint Impact
-----------------
- not applicable.

Files changed
-------------
- `src/http_client.cpp`
- `.superpowers/sdd/native-crash-diagnostics-report.md`

Self-review findings
--------------------
- Confirmed HTTP client per-worker markers now use `diagnostic_emit`, which returns before `active_count()` unless `SPACE_HTTP_CLIENT_DEBUG=1` is enabled.
- Confirmed default-on shutdown begin/end/already-stopped markers remain intact.

Concerns
--------
- None.
