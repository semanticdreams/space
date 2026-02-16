# Matrix SDK Bridge Plan

This plan outlines the work to expose matrix-rust-sdk features through the Rust FFI bridge, sol2 bindings, and Fennel APIs. The goal is to keep the core engine stable while expanding Matrix features in phases.

## Current Status

- Rust FFI library: `libmatrix.so` built from `ffi/matrix` with C ABI.
- C ABI: `init`, `client_create`, `login_password`, `sync_once`, `rooms`, plus string/result/list free helpers.
- Lua binding: `matrix` module with `create-client`, `login-password`, `sync-once`, `rooms`.
- Fennel test: opt-in `test-matrix` covering login + sync + room list.
- Packaging: CMake installs `libmatrix.so` to `lib/` and sets `$ORIGIN`-based RUNPATH.

## Goals

- Provide a stable C ABI with opaque handles and callback-based async results.
- Expose a Lua/Fennel API that follows existing module patterns.
- Keep long-running tasks off the main thread and deliver results via the central callback registry.
- Package `libmatrix.so` with the app for distribution via CPack.

## Phase 1: Core Session & Sync

- Configuration
  - Homeserver URL, user ID, device name, device ID, proxy settings.
  - Persisted session import/export (JSON blob) to skip login.
- Authentication
  - Password login (done).
  - Token login.
  - SSO login URL flow (return URL, allow caller to open browser).
  - Logout (local + server).
- Sync
  - `sync_once` with configurable timeout and filters (done basic).
  - `sync_loop_start/stop` with callback for incremental updates.
  - Event handler registration (message events, state events, receipts).
- State
  - Expose user ID, device ID, homeserver, sync token.

## Phase 2: Rooms & Messaging

- Rooms
  - List joined/invited/left rooms with IDs and basic metadata (basic IDs done).
  - Join/leave/invite/forget.
  - Room display name/alias updates.
- Messaging
  - Send text message.
  - Send edit/reply/notice.
  - Send typing notifications.
  - Fetch message history (pagination).
- Read receipts
  - Mark read, read markers.

## Phase 3: E2EE & Devices

- E2EE
  - Enable/disable encryption and check room encryption state.
  - Upload device keys and manage one-time keys.
  - Decrypt/verify events.
- Device management
  - List devices.
  - Delete devices.
  - Set display name.

## Phase 4: Media & Files

- Upload/download media (with progress callbacks).
- Thumbnails and caching controls.
- Avatar set/get for user and room.

## Phase 5: Presence, Profile, and Account

- Presence set/get.
- Profile display name/avatar.
- Account data (per-user and per-room).

## Phase 6: Advanced APIs

- Sliding sync support (if needed for performance).
- Push rules and notification settings.
- Room directory search and public room listing.

## FFI Design Guidelines

- Keep ABI minimal and stable: opaque handles, structs for simple data, callbacks for async.
- All allocations returning strings/arrays must have explicit free functions.
- Each async call must return immediately and finish on the runtime thread.
- Avoid silent fallbacks; return errors with code/message.

## Lua/Fennel API Shape

- Module name: `matrix`
- Constructors return userdata handles: `client = matrix.create-client {...}`
- Async operations accept a callback and deliver payload tables via callbacks registry.
- Keep payloads consistent: `{ ok, error, ... }` with `error = { code, message }`.

## Test Strategy

- Unit tests for bindings:
  - Validate argument checking and error paths in Lua.
  - Ensure callbacks are delivered before update.
- End-to-end Fennel tests (opt-in):
  - Login, sync, list rooms (done).
  - Send message + fetch history.
  - Media upload/download (small file).
- Add a test harness doc section describing required env vars.

## Packaging

- Ensure `libmatrix.so` is installed under `lib/` via CMake install rules.
- Keep `$ORIGIN`-based RUNPATH so the executable resolves bundled libs.

## Incremental Delivery

- Expand in vertical slices:
  - Add one feature area in Rust FFI.
  - Expose in Lua binding.
  - Add a targeted Fennel test.
  - Update docs with new API and test usage.
