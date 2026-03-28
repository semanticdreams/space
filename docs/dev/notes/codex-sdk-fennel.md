# Codex SDK For Fennel

## Goal

Create a Fennel SDK for Codex that follows the official TypeScript SDK closely at the API level while fitting the conventions of this codebase.

The SDK should:

- wrap the `codex` CLI through a subprocess boundary
- preserve the upstream feature set
- expose Fennel-native data shapes and method names
- remain easy to extend when the CLI adds new event or item types

The SDK should not:

- embed Codex internals directly
- depend on Rust FFI bindings
- invent a large abstraction layer above the CLI contract in v1

## Upstream baseline

The official TypeScript SDK is a thin wrapper over:

```text
codex exec --experimental-json
```

The runtime contract is:

- send the prompt over stdin
- optionally pass images as `--image`
- optionally resume a thread with `resume <thread-id>`
- read stdout as JSONL, one event per line
- read stderr only for diagnostics and process-failure reporting
- treat a non-zero exit or signal as failure even if stdout produced data first

We should keep that boundary intact. The Fennel SDK should rely on the CLI as the implementation of agent behavior and treat the JSONL stream as the stable integration surface.

## Existing repo primitives

The repo already has the main low-level pieces needed for this SDK:

- `process` for child-process execution and lifecycle control
- `tempfile` for temporary schema directories/files
- `json-utils` for JSON serialization to disk when needed

That means v1 can be implemented entirely in Fennel without adding new C++ bindings just to get subprocess support.

## V1 decisions

### Public API shape

Stay close to the upstream TypeScript surface, but use Fennel factory tables and colon methods.

Proposed shape:

```fennel
(local Codex (require :codex-sdk))

(local client
  (Codex.Codex {:codex-path "/custom/codex"
                :base-url "https://example.test/v1"
                :api-key "secret"}))

(local thread
  (client:start-thread {:model "gpt-5"
                        :sandbox-mode "workspace-write"}))

(local result
  (thread:run "Diagnose the failing test"))
```

And for resume:

```fennel
(local resumed (client:resume-thread thread.id))
```

Primary constructors/methods:

- `Codex.Codex(opts)`
- `client:start-thread(opts)`
- `client:resume-thread(id opts)`
- `thread:run(input opts)`
- `thread:run-streamed(input opts)`

### Data shape

Results, events, and items should be normalized into idiomatic Fennel keys.

Examples:

- `thread_id` -> `:thread-id`
- `exit_code` -> `:exit-code`
- `finalResponse` equivalent -> `:final-response`

Recommended normalized event types:

- `:thread-started`
- `:turn-started`
- `:item-started`
- `:item-updated`
- `:item-completed`
- `:turn-completed`
- `:turn-failed`
- `:error`

Recommended normalized item types:

- `:agent-message`
- `:reasoning`
- `:command-execution`
- `:file-change`
- `:mcp-tool-call`
- `:web-search`
- `:todo-list`
- `:error`

The SDK may preserve the original raw payload internally for debugging, but normalized Fennel tables are the main API.

### Input shape

Match upstream semantics:

- plain string input is a prompt
- structured input may contain text and local images
- text items are joined into one prompt body
- image items become repeated `--image` flags

Recommended input forms:

```fennel
"Summarize this repository"
```

```fennel
[{:type :text :text "Describe these screenshots"}
 {:type :local-image :path "./a.png"}
 {:type :local-image :path "./b.png"}]
```

The SDK should normalize these into:

- prompt string for stdin
- image path list for argv

### `run` return shape

`thread:run` should buffer the turn and return a Fennel-style result table:

```fennel
{:items [...]
 :final-response "..."
 :usage {:input-tokens 0
         :cached-input-tokens 0
         :output-tokens 0}}
```

Failure behavior:

- throw on `:turn-failed`
- throw on malformed JSON lines
- throw on CLI spawn/exit failure
- do not silently downgrade failures into `nil` results

### Streaming API

The primary streaming interface should be callback-based because it fits the existing `process` module and the rest of the codebase better than an async-iterator-style API.

Proposed shape:

```fennel
(local handle
  (thread:run-streamed
    "Diagnose the test failure"
    {:on-event (fn [event]
                 (print event.type))
     :on-complete (fn [result]
                    (print result.final-response))
     :on-error (fn [err]
                 (print err))}))
```

The exact callback names may still be adjusted, but v1 should be centered on callback delivery.

### Streaming handle and cancellation

`run-streamed` should return a handle representing the active turn.

Recommended handle capabilities:

- `handle:cancel`
- `handle:running?`
- `handle.id` or `handle.process-id` if useful for debugging

Recommended rule:

- one active turn per `Thread`
- starting another turn while one is still active should fail loudly

Cancellation recommendation:

- cancellation belongs on the active turn handle, not on `run` itself in v1
- if we later want convenience, `thread:cancel-active-turn` can delegate to the handle

This keeps cancellation aligned with the actual subprocess lifecycle and avoids ambiguous thread-wide semantics.

### Binary resolution

The TypeScript SDK resolves a bundled platform-specific binary unless the caller overrides it.

We should not implement bundling in v1.

Recommended v1 resolution order:

1. explicit `:codex-path`
2. fallback to `"codex"` on `PATH`
3. fail clearly if the executable cannot be started

This keeps the public API future-proof. If we later bundle binaries, we can insert bundled resolution between steps 1 and 2 without changing caller code.

### Configuration surface

Callers should primarily configure the SDK through params, not by constructing environment variables themselves.

Recommended `Codex` options:

- `:codex-path`
- `:base-url`
- `:api-key`
- `:env`
- `:clear-env`
- `:originator`

Recommended `Thread` options:

- `:model`
- `:sandbox-mode`
- `:working-directory`
- `:additional-directories`
- `:skip-git-repo-check`
- `:model-reasoning-effort`
- `:network-access-enabled`
- `:web-search-mode`
- `:approval-policy`

Recommended turn options:

- `:output-schema`
- callback hooks for streaming

Internally, the SDK should still translate params into CLI-facing env vars when needed:

- `:base-url` -> `OPENAI_BASE_URL`
- `:api-key` -> `CODEX_API_KEY`
- `:originator` -> `CODEX_INTERNAL_ORIGINATOR_OVERRIDE`

Default originator should be:

```text
codex_sdk_fennel
```

unless the caller explicitly overrides it.

### Structured output

V1 should accept plain Lua/Fennel tables that serialize to a JSON object.

Example:

```fennel
(thread:run
  "Summarize repository status"
  {:output-schema {:type "object"
                   :properties {:summary {:type "string"}
                                :status {:type "string"
                                         :enum ["ok" "action_required"]}}
                   :required ["summary" "status"]
                   :additionalProperties false}})
```

The SDK should:

- require the schema root to be a JSON object
- write it to a temporary file
- pass `--output-schema <path>`
- clean up the temporary file/directory afterward

V1 should not add a schema DSL or helper compiler.

That avoids creating a second abstraction that we would need to maintain. If schema authoring becomes repetitive, we can add a helper module later.

### Extensibility for new event/item types

We want forward compatibility without empty placeholders.

Recommended behavior:

- normalize and expose known event/item types
- preserve unknown event/item payloads as generic normalized values
- avoid crashing only because the CLI introduced a new item kind that v1 does not know yet

One reasonable shape for unknown values:

```fennel
{:type :unknown-event
 :raw parsed-event}
```

or

```fennel
{:type :unknown-item
 :raw parsed-item}
```

The SDK should still fail on malformed JSON or contract violations that prevent safe parsing at all.

## Proposed module layout

One reasonable v1 layout under `assets/lua/`:

```text
assets/lua/
  codex-sdk.fnl
  codex-sdk/
    exec.fnl
    thread.fnl
    events.fnl
    items.fnl
    input.fnl
    schema-file.fnl
```

Suggested responsibilities:

- `codex-sdk.fnl`: public entry point and `Codex.Codex`
- `codex-sdk/exec.fnl`: argv/env construction and subprocess management
- `codex-sdk/thread.fnl`: thread object, `run`, `run-streamed`, id management
- `codex-sdk/events.fnl`: event normalization
- `codex-sdk/items.fnl`: item normalization
- `codex-sdk/input.fnl`: prompt/image normalization
- `codex-sdk/schema-file.fnl`: temp schema creation and cleanup

This keeps the code modular without creating premature layers.

## Proposed execution flow

### `thread:run`

1. Normalize input into prompt text plus image paths.
2. Create a temporary schema file when `:output-schema` is present.
3. Build argv:
   - `exec`
   - `--experimental-json`
   - CLI options derived from thread options
   - repeated `--image`
   - `resume <thread-id>` when resuming
4. Build child env from caller params plus inherited env rules.
5. Execute the CLI.
6. Read stdout line-by-line.
7. Parse each line as JSON.
8. Normalize events/items into Fennel tables.
9. Update `thread.id` as soon as `:thread-started` arrives.
10. Accumulate completed items, final response, and usage.
11. Throw on turn/process failure.
12. Clean up schema temp files in a `finally`-style path.

### `thread:run-streamed`

1. Perform the same normalization and process setup as `run`.
2. Spawn asynchronously.
3. Stream parsed normalized events into callbacks.
4. Return a handle that owns:
   - process id
   - cancellation
   - running state
   - final completion/error callbacks
5. Clean up schema temp files when the stream exits, whether success, failure, or cancellation.

## Error model

The SDK should fail loudly in these cases:

- unsupported input shape
- invalid output schema root
- failure to create schema temp files
- child process spawn failure
- malformed stdout JSON line
- non-zero CLI exit code
- process termination by signal
- `:turn-failed` event from Codex
- attempting to start a second concurrent turn on the same thread

The SDK should not:

- merge stdout and stderr
- ignore stderr on non-zero exit
- ignore process failure because some events already arrived
- silently coerce bad input into a weaker request

## Testing plan

The implementation should be covered with both fast deterministic tests and separate live online integration tests.

### Fast local tests

Fast tests should be part of the normal suite and should not require network access, existing Codex login state, or a real OpenAI account.

Recommended test areas:

- input normalization from string and structured input
- argv construction from thread options
- env construction and `:clear-env` behavior
- schema temp-file creation and cleanup
- thread id capture from `:thread-started`
- `run` result aggregation
- `run` failure on `:turn-failed`
- parse failure on malformed JSONL
- streaming callback order and completion behavior
- cancellation through the streaming handle
- unknown event/item preservation

Recommended testing strategy:

- use a tiny fake executable or scripted fixture process to emit controlled JSONL
- assert both stdout event handling and stderr/exit failure handling
- keep tests offline and deterministic

These tests should be the default protection against:

- broken input or option mapping
- malformed event parsing
- result aggregation bugs
- cleanup bugs around temp schema files
- concurrency and cancellation mistakes

### Live online integration tests

We also want a separate live test layer that talks to a real `codex` binary and real authentication state. These tests should be opt-in and should not run as part of `make test`.

The purpose of the live layer is to catch problems that fixtures cannot fully validate:

- real subprocess behavior against the installed `codex` binary
- compatibility with actual CLI auth handling, including ambient login state
- thread persistence and resume behavior against the real CLI
- structured output behavior end-to-end
- regressions in the CLI JSON event stream

Recommended characteristics:

- gated behind an explicit env var or dedicated test command
- skipped by default in CI and local fast runs
- require either valid Codex login state or explicit API credentials
- use small prompts and narrow assertions to control cost and runtime

Recommended live test areas:

- basic `thread:run` succeeds and returns a final response
- `thread.id` is populated and `resume-thread` continues the same conversation
- structured output with `:output-schema` works end-to-end
- image input works when a local image fixture is provided
- streaming callbacks observe a valid event sequence
- failure reporting is surfaced correctly for an intentionally bad invocation

Recommended operational split:

- fast tests live in the normal Fennel test suite
- live tests live in dedicated modules and a dedicated command
- live tests should be documented as requiring local auth and should print a clear skip reason when credentials are absent

This split keeps the default suite fast and reliable while still giving us real integration coverage before shipping changes.

## Non-goals for v1

- bundled per-platform `codex` binaries
- a schema authoring DSL
- pull-style async iteration API
- concurrent turns on one thread
- compatibility shims for multiple key spellings

## Recommendation summary

Build v1 as a thin, process-based SDK with an upstream-shaped object model and Fennel-native tables.

The key design choices are:

- subprocess boundary over `codex exec --experimental-json`
- `Codex` and `Thread` factory objects with colon methods
- callback-based streaming
- handle-based cancellation
- params-first configuration with internal env translation
- plain-table JSON schema support only
- normalized kebab-case result/event/item keys
- forward-compatible handling of unknown event/item kinds

This gives us a reliable first implementation that fits the repo, stays close to the official SDK, and leaves clear room for future extension without over-designing v1.
