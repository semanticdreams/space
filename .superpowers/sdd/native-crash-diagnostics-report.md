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
