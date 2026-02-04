# Loop Abstraction Plan

## Context
- `callbacks.run-loop` in `src/lua_callbacks.cpp` is a polling loop that dispatches jobs/http/callbacks.
- Async producers (jobs/http) run in worker threads and enqueue results back to Lua.
- There is no shared event-loop abstraction today.

## Goals
- Add a shared loop abstraction so Fennel can select a backend (default vs libuv).
- Improve latency and reduce busy-waiting by waking the loop when callbacks arrive.
- Keep main-thread callback dispatch as the single execution path for Lua.

## Non-goals (initial)
- Full migration of HTTP/jobs/FS to libuv.
- Changing the frame update model of the engine.

## Proposed Abstraction
Introduce a minimal `Loop` interface with:
- `run_once(max_work_ms)` or `poll(max_work_ms)` for stepping in the engine frame.
- `wake()` for cross-thread notification when new callbacks are enqueued.
- `schedule_timer(delay_ms, repeat, fn)` or a minimal timer API if needed.

The "default" backend keeps current behavior but uses `wake()` to avoid sleep polling.

## Backend: Default (current loop)
- Keep current polling logic.
- Replace `sleep_ms` with "wait until wake or timeout" using a `std::condition_variable`.
- `lua_callbacks_enqueue` calls `loop.wake()` so `callbacks.run-loop` can respond immediately.

## Backend: Libuv (future)
- Own a `uv_loop_t` plus:
  - `uv_async_t` for `wake()` and cross-thread notifications.
  - `uv_timer_t` for timeouts and scheduled timers.
- Provide `poll(max_work_ms)` via `uv_run(loop, UV_RUN_NOWAIT)` or bounded `UV_RUN_ONCE`.
- Keep callbacks dispatched on the main thread; only wake/queue from worker threads.

## Engine Integration
- Add a loop instance to the engine runtime (e.g., `Engine.loop` or runtime singleton).
- In the main frame update, call `loop.poll(max_work_ms)`; budget can be small.
- Keep the existing explicit `callbacks.run-loop` for tests and scripts.

## Lua/Fennel API
- Add `callbacks.run-loop` option `:loop` (`:default` or `:uv`) or a separate
  `callbacks.set-loop :uv` that updates the runtime default.
- `callbacks.run-loop` continues to return `true/false` based on `:until`/timeout.

## Migration Steps
1) Add `Loop` interface and default backend backed by condition variable.
2) Store a loop instance in runtime/engine and expose selection to Lua.
3) Update `lua_callbacks_enqueue` to call `loop.wake()`.
4) Update tests (`assets/lua/tests/test-callbacks.fnl`) to validate wake behavior.
5) (Optional) Add libuv backend and make selection available to scripts.

## Risks
- Waking and dispatching from worker threads must remain thread-safe.
- Frame budget in `loop.poll` must be enforced to avoid spikes.
- Lua callback dispatch must remain on the main thread.

## Validation
- Existing `callbacks.run-loop` tests should pass.
- Add a new test that enqueues a callback and ensures `run-loop` returns quickly
  without `sleep-ms`.
