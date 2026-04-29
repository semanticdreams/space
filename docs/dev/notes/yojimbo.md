# Yojimbo integration plan

This document is the working implementation plan for integrating `yojimbo` into Space as a hard dependency.
It is intended to be updated as the implementation progresses.

## status

- decision: vendor official upstream source under `external/yojimbo`
- decision: make yojimbo a hard dependency enabled by default in all builds
- decision: keep a single `space` runtime; Fennel decides whether it behaves like an app, client, server, or mixed runtime
- decision: keep Matrix responsible for durable/shared state and discovery; yojimbo handles fast realtime transport
- decision: share connection details through Matrix room data later, but do not block the transport integration on `matrix-world`
- decision: compose realtime feature sets from Fennel; C++ provides transport primitives and feature lifecycle hooks
- decision: support hot-plug feature activation after a client is already connected
- decision: run realtime I/O on a dedicated native thread and deliver script-facing events through the existing main-thread callback queue
- decision: add both offline tests and local online loopback tests
- decision: use signed tickets/capabilities for auth; local tests may use a dev bootstrap path with the same ticket shape
- progress: vendored upstream selected as `yojimbo` `v1.2.5`
- progress: implementation doc created

## goals

- add yojimbo as a production-ready, default-on dependency across supported Space platforms
- keep the runtime generic enough that no dedicated binary or required CLI flag is needed for server mode
- expose a script-friendly realtime API that allows Fennel to:
  - create and configure client/server instances
  - register available feature modules
  - activate or deactivate feature sets per session
  - receive events for connect, disconnect, feature activation, feature messages, and errors
- keep transport concerns separate from future world/game logic so `matrix-world` can be built on top later
- fail loudly on misconfiguration or unavailable capabilities

## non-goals for this phase

- do not build actual gameplay or world replication features yet
- do not bind transport logic directly to home-world behavior
- do not implement Matrix-side room schema yet beyond planning for future discovery/auth handoff
- do not add compatibility shims for multiple API names; expose a single canonical API

## upstream dependency facts

- upstream repository: `mas-bandwidth/yojimbo`
- chosen vendor tag: `v1.2.5`
- upstream includes its own `netcode`, `reliable`, `serialize`, `tlsf`, and `sodium` source trees inside the repository
- upstream build system is premake-oriented, so Space will compile the required source files directly from CMake instead of invoking premake
- upstream documentation expects headless server support and a fixed-step update loop with:
  - `AdvanceTime`
  - `ReceivePackets`
  - message processing
  - `SendPackets`

## architecture overview

### layer split

#### layer 1: vendored transport

Raw yojimbo source under:
- `external/yojimbo/`

This layer should remain as close to upstream as possible.
Local changes inside vendored code should be avoided unless strictly necessary.

#### layer 2: native realtime core

New native code under:
- `src/realtime/`

Responsibilities:
- initialize/shutdown yojimbo
- own client/server objects
- run network thread(s)
- own auth ticket verification and dev-ticket helpers
- map yojimbo messages/channels to Space feature/session abstractions
- queue events to Lua/Fennel via `lua_callbacks_enqueue`

#### layer 3: Lua/Fennel binding

New binding entry point:
- `src/lua_realtime.cpp`

Responsibilities:
- expose canonical module API through `package.preload["realtime"]`
- validate script arguments
- create userdata handles for services/clients/servers/registries/sessions
- surface errors loudly and consistently

#### layer 4: Fennel orchestration

New script modules under:
- `assets/lua/realtime/`

Responsibilities:
- define ergonomic wrappers around the raw native API
- assemble feature sets
- host test-only features
- later bridge Matrix discovery/auth data into realtime connection setup

## runtime model

### single runtime, no dedicated binary

Space already supports running arbitrary Fennel modules through the same executable.
This integration should preserve that model:

- app mode: normal windowed runtime
- headless server mode: Fennel starts engine in headless mode, configures realtime server, then runs loop
- client mode: Fennel starts app or headless runtime, then attaches realtime client
- mixed mode: a single process may host client + server for local testing

### engine requirement

Current headless engine startup does not enter the normal `Engine::run()` loop.
That must change so headless server/client runtimes can use the same main-thread dispatch path as the normal app.

Planned change:
- allow `Engine::run()` in headless mode
- emit the same engine tick/update/callback dispatch behavior without creating a window
- keep rendering-specific behavior gated behind `config.headless`

Why:
- simpler lifecycle
- same callback semantics in app and server modes
- no custom script-only run loop needed for production server logic

## native module shape

### top-level C++ namespaces

- `space::realtime`
- `space::realtime::auth`
- `space::realtime::features`

### proposed native types

- `RealtimeService`
  - global yojimbo init/shutdown ownership
  - owns shared config, allocators, and background worker coordination
- `RealtimeServer`
  - listens on UDP endpoint
  - owns yojimbo `Server`
  - owns connected `RealtimeSession` objects
- `RealtimeClient`
  - owns yojimbo `Client`
  - owns outbound connect/auth state
- `RealtimeFeatureRegistry`
  - owns registered feature descriptors
  - stable feature ids, names, versions
- `RealtimeFeatureDescriptor`
  - metadata and callbacks for a feature
- `RealtimeSession`
  - one connected client/server association
  - active feature set for that session
- `RealtimeAuthTicket`
  - structured connection capability payload

### proposed directory layout

- `src/realtime/core.h`
- `src/realtime/core.cpp`
- `src/realtime/auth_ticket.h`
- `src/realtime/auth_ticket.cpp`

The final implementation landed as a smaller `core.*` + `auth_ticket.*` split instead of separate service/server/client/session files.

## message and feature model

### base transport concepts

- a connection may exist before any optional realtime feature is active
- features are activated per session, not globally for the whole process
- new features may be activated after a client is already connected
- some features will eventually require specialized lag-compensation or prediction logic, so the core must not assume all features share identical semantics

### channel model

Initial canonical channels:
- reliable ordered
- unreliable unordered

The C++ core owns the real yojimbo channel configuration.
Fennel should refer to channels through explicit names or ids exposed by the binding, not ad hoc constants.

### base message families

Initial internal message families:
- handshake/auth
- feature offer
- feature ack
- feature activate
- feature deactivate
- feature payload
- error/close reason

These are transport-control concepts.
Actual gameplay or world payloads come later as feature-specific messages.

### hot-plug activation flow

Planned session flow:

1. client connects with auth ticket
2. server establishes base session
3. server advertises currently available feature ids + versions for that session
4. client acknowledges supported features
5. server activates zero or more features immediately
6. later, while connected, server may activate additional features
7. feature payload messages only flow after activation

Requirements:
- activation must be idempotent
- version mismatch must fail loudly
- deactivation must release session-local feature state cleanly
- feature activation order must be deterministic

## auth model

### production direction

Matrix room metadata will eventually provide:
- endpoint
- capability/ticket
- room/world context
- feature policy metadata

The realtime layer should not depend directly on Matrix bindings to validate tickets.
It should only consume a ticket payload produced upstream.

### phase-1 auth requirement

Phase 1 still needs authenticated flows, even for local tests.

Plan:
- define a structured auth ticket format now
- define verification hooks now
- add a dev/local ticket signer/verifier path for loopback tests
- keep the ticket format stable enough that Matrix can populate it later

### ticket fields

Planned minimum fields:
- ticket id / nonce
- subject user id
- session id / client id
- server endpoint or server scope
- allowed features or capability scope
- issue time
- expiry time
- signature or MAC

## Lua/Fennel binding shape

### module name

- canonical module name: `realtime`

No alias module should be added unless there is a strong later need.

### top-level factories

Planned top-level functions:
- `realtime.Service(opts)`
- `realtime.FeatureRegistry()`
- `realtime.make-dev-ticket(opts)`
- `realtime.version()`

### handles

Planned userdata handles:
- `RealtimeServiceHandle`
- `RealtimeServerHandle`
- `RealtimeClientHandle`
- `RealtimeFeatureRegistryHandle`
- `RealtimeSessionHandle`

### planned methods

#### service

- `create-server(opts)`
- `create-client(opts)`

#### server

- `start`
- `close`
- `is-running`
- `address`
- `activate-feature(session-id, feature-id[, opts])`
- `deactivate-feature(session-id, feature-id)`
- `broadcast-reliable(feature-id, payload-bytes)`
- `broadcast-unreliable(feature-id, payload-bytes)`
- `set-callback(name, fn)`

#### client

- `connect(opts)`
- `close`
- `is-connected`
- `send-reliable(feature-id, payload-bytes)`
- `send-unreliable(feature-id, payload-bytes)`
- `set-callback(name, fn)`

#### feature registry

- `register-feature(opts)`
- `list-features()`

### payload format

Phase 1 should expose payloads as raw byte strings/buffers.

Reason:
- avoids premature schema magic
- keeps perf characteristics explicit
- lets Fennel wrappers layer codecs later without constraining the native core

If byte-vector userdata becomes necessary for performance, that can be added later.
Start with plain Lua strings if practical.

## callback and threading model

### thread ownership

- yojimbo packet I/O runs on a dedicated native thread
- script callbacks always run on the main thread
- cross-thread delivery uses the existing callback queue

### event delivery path

1. realtime worker thread receives state/message
2. native realtime code converts it into a stable owned payload
3. native code enqueues a main-thread callback via `lua_callbacks_enqueue`
4. callback executes during normal engine callback dispatch

### callback families

Planned callback names:
- `started`
- `stopped`
- `client-connected`
- `client-disconnected`
- `connected`
- `disconnected`
- `feature-offered`
- `feature-activated`
- `feature-deactivated`
- `message`
- `error`

### lifecycle rules

- callback registration must happen before `start`/`connect` if the caller wants startup events
- callbacks must never execute on the network thread
- shutdown must join worker threads deterministically
- callback payloads must not reference temporary network-thread memory

## CMake integration plan

### build policy

- yojimbo enabled by default
- hard dependency
- no soft-disable fallback if missing
- configure/build should fail loudly if the vendored source is absent or broken

### vendor policy

- store source under `external/yojimbo`
- compile required upstream `.cpp` and `.c` sources as part of Space’s build
- avoid running premake from CMake

### planned target shape

Preferred approach:
- add a dedicated static library target such as `space_yojimbo`
- include upstream source directories privately/system as appropriate
- link `space_yojimbo` into `${PROJECT_NAME}_lib`
- set platform-specific compile definitions required by yojimbo

### packaging

Because the source will be compiled directly into Space, there should be no separate runtime library staging step analogous to Matrix unless later refactoring changes that.

## implementation phases

### phase 1: vendor and compile

- vendor `external/yojimbo`
- add `space_yojimbo` CMake target
- ensure Linux/macOS/Windows compile settings are correct
- keep compile-only smoke verification tight before higher-level code

### phase 2: headless loop support

- allow headless engine to run its main loop
- verify callbacks/jobs/http/process dispatch still work
- add targeted regression tests for headless loop behavior

### phase 3: native realtime skeleton

- add service/client/server/session/registry core
- add yojimbo init/shutdown handling
- add basic connect/disconnect flow
- no world/game features yet

### phase 4: feature activation control plane

- add feature registration and stable ids/versions
- add feature offer/ack/activate/deactivate protocol
- add test-only features

### phase 5: Lua/Fennel binding

- expose module through `package.preload`
- add handle lifecycle and callback registration
- add basic Fennel wrapper modules

### phase 6: test coverage

- offline tests
- same-process loopback online tests
- separate-process loopback online tests

### phase 7: follow-up integration

- consume Matrix-provided connection metadata later
- add `matrix-world` orchestration later
- add real feature modules later

## test strategy

### offline tests

Purpose:
- validate syntax, semantics, lifecycle, and protocol assumptions without requiring real cross-process networking

Planned coverage:
- C++ unit tests for feature registry rules
- C++ unit tests for auth ticket parsing/validation
- C++ unit tests for message/control-plane serialization
- Lua/Fennel tests for binding argument validation
- Lua/Fennel tests for lifecycle errors and callback registration semantics
- headless-loop regression tests

### local online tests: same process

Purpose:
- validate real packet exchange quickly in one process

Planned coverage:
- start server on loopback
- connect client using dev ticket
- receive connected event
- activate test feature after connect
- exchange reliable payload
- exchange unreliable payload
- clean disconnect

### local online tests: separate process

Purpose:
- validate real process lifecycle assumptions

Planned coverage:
- spawn headless server via `space -m ...`
- spawn client via `space -m ...`
- connect over loopback UDP
- exchange test feature messages
- assert clean shutdown and usable logs/errors

### test-only features

Initial test-only features:
- `ping`
- `echo`
- `counter`
- optional `blob-stream` if larger-payload coverage is needed

These should stay clearly marked as test utilities, not proto-gameplay features.

## file plan

### native

- `src/lua_realtime.cpp`
- `src/realtime/*.h`
- `src/realtime/*.cpp`
- possibly `src/realtime_test_utils.*` if setup duplication becomes large

### script

- `assets/lua/realtime/common.fnl`
- `assets/lua/realtime/test-features.fnl`
- `assets/lua/tests/test-realtime-offline.fnl`
- `assets/lua/tests/test-realtime-online.fnl`
- `assets/lua/tests/test-realtime-online-client.fnl`
- `assets/lua/tests/test-realtime-online-server.fnl`

### tests

- `tests/test_realtime_*.cpp`

Exact filenames may shift as code takes shape, but this is the intended surface area.

## progress checklist

### vendor and build

- [x] choose upstream release tag
- [x] vendor source into `external/yojimbo`
- [x] compile vendored source from CMake
- [x] link into `${PROJECT_NAME}_lib`
- [x] verify base build on current platform

### engine loop

- [x] support headless `Engine::run()`
- [x] add regression coverage for headless callback dispatch

### native realtime core

- [x] add service/client/server/session classes
- [x] add feature registry
- [x] add auth ticket structures
- [x] add network thread lifecycle
- [x] add callback queue bridging

### Lua/Fennel binding

- [x] expose `realtime` preload module
- [x] add Fennel wrappers
- [x] add dev ticket helper

### tests

- [x] offline tests pass
- [x] same-process online loopback test passes
- [x] separate-process online loopback test passes

## actual implementation notes

### landed files

- native core: `src/realtime/core.h`, `src/realtime/core.cpp`
- auth ticket support: `src/realtime/auth_ticket.h`, `src/realtime/auth_ticket.cpp`
- Lua binding: `src/lua_realtime.cpp`
- Fennel wrappers: `assets/lua/realtime/common.fnl`, `assets/lua/realtime/test-features.fnl`
- Fennel tests: `assets/lua/tests/test-realtime-offline.fnl`, `assets/lua/tests/test-realtime-online.fnl`, `assets/lua/tests/test-realtime-online-client.fnl`, `assets/lua/tests/test-realtime-online-server.fnl`
- native tests: `tests/test_realtime_core.cpp`
- scripts: `scripts/test-headless-engine-run.sh`, `scripts/test-realtime-offline.sh`, `scripts/test-realtime-online.sh`, `scripts/test-realtime-online-manual.sh`, `scripts/debug-headless-engine-run-gdb.sh`, `scripts/debug-realtime-online-client-gdb.sh`

### API deviations from the original sketch

- the canonical preload module name remains `realtime`
- wrapper helpers live in `realtime.common` and `realtime.test-features`
  because adding `assets/lua/realtime/init.fnl` would collide with the native preload module name
- service is a factory object; it does not expose lifecycle methods
- client/server handles use `close()` as the canonical lifecycle method
- `feature-deactivated` is implemented in both native callback families

### auth ticket notes

- phase-1 auth uses a structured payload plus a dev/local MAC signer/verifier
- the current helper lives under `realtime.make-dev-ticket(opts)` and `realtime.verify-dev-ticket(opts)`
- `server:create-connect-token(opts)` now requires a verified signed ticket input:
  pass `{:signed-ticket <make-dev-ticket-result> :secret <shared-secret>}`
- native connect-token issuance now requires a verified ticket object, not a raw `AuthTicket`
- `create-server(opts)` accepts:
  - `max-clients` in the enforced range `[1, 64]`
  - optional `server-scope`; when omitted, the server uses its resolved bound address as scope
  - optional `connect-addresses`; if omitted, connect tokens advertise the resolved bound address
- wildcard binds such as `0.0.0.0:0` or `[::]:0` require explicit `connect-addresses` before connect-token minting
- each `connect-addresses` entry may use port `0` to mean "reuse the actual bound port"
- `connect-addresses` must be concrete, non-wildcard addresses in the same address family as the server bind address
- connect-token minting now keeps public advertised addresses separate from the internal bound address whitelist
- `server` `client-connected` callbacks now expose the decoded ticket under `payload.auth-ticket`
- `allowed-features` is currently validated as sorted and unique so the signed payload stays canonical
- auth-ticket validation now enforces transport size/count limits during sign/verify, not only during token minting
- server-side feature activation is gated by the connected client's `allowed-features`
- `server-scope` is enforced both when minting tokens and when accepting clients
- connect-token lifetime is clamped to the verified ticket's remaining validity window
- the ticket payload currently carries:
  - `ticket-id`
  - `subject-user-id`
  - `client-id`
  - `server-scope`
  - `allowed-features`
  - `issued-at`
  - `expires-at`
  - hex-encoded signature returned alongside `payload-json`

### current remaining work

- add more focused native coverage for control-plane message serialization if the protocol grows beyond the current registry/auth checks

### current loopback coverage

- offline script covers module shape, registry rules, lifecycle guardrails, callback-name validation, wrapper helpers, and dev ticket signing/verification
- same-process online script covers connect, offer, activate, reliable payload exchange, deactivate, and payload blocking after deactivation
- separate-process online script covers the same activation/deactivation flow across real process boundaries

### headless loop regression note

- the first headless `Engine::run()` regression exposed a real null dereference:
  headless startup left `inputState.keyboardState.currentValue` unset while the run loop unconditionally copied it each frame
- fix landed in `src/engine.cpp` by initializing keyboard state for headless startup and guarding the per-frame copy
- regression coverage now lives in `assets/lua/tests/test-headless-engine-run.fnl`

## open implementation risks

- upstream yojimbo source may need careful compile-definition handling across Windows/macOS/Linux
- headless loop changes could regress existing test/profiler behavior if startup/shutdown semantics are altered carelessly
- hot-plug feature activation requires versioned control-plane messages from the start; cutting corners here will create migration pain later
- auth ticket design should not be so test-specific that Matrix integration later needs a breaking format change
- script-facing callback payloads must avoid implicit ownership/lifetime bugs from native worker threads

## update policy

As implementation proceeds, update this document with:
- completed checklist items
- actual filenames introduced
- API names that become final
- deviations from this plan and why they were necessary
- validation commands used for offline and online tests

Current validation commands:
- `rtk make build`
- `rtk ctest --test-dir build --output-on-failure -R test_realtime_core`
- `./scripts/test-headless-engine-run.sh`
- `./scripts/test-realtime-offline.sh`
- `./scripts/test-realtime-online.sh`
