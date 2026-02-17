# libtorrent integration and Fennel binding

This document describes the libtorrent integration used by Space today.
It is the authoritative reference for the `libtorrent` Fennel module exposed by `src/lua_libtorrent.cpp`.

## overview

Space binds libtorrent-rasterbar into Lua/Fennel through `package.preload["libtorrent"]`.
The binding is implemented in C++ and exposed as hyphen-case APIs.

Design goals:
- expose a practical, script-friendly control surface for torrent/session operations
- keep data model explicit (`SessionHandle`, `AddTorrentParamsHandle`, `SessionParamsHandle`)
- support both offline and online integration tests
- fail loudly when a capability is unavailable

## build and availability

The module is conditionally compiled:
- enabled build: real libtorrent implementation is exported
- disabled build: module still exists with `available = false` and all API calls throw a clear error

Runtime fields:
- `libtorrent.available` -> boolean
- `libtorrent.missing-reason` -> string or `nil`

Missing dependency message:
- `libtorrent unavailable (install libtorrent-rasterbar-dev and rebuild)`

## naming conventions

All exposed API names are hyphen-case.
Examples:
- `parse-magnet-uri`
- `wait-for-alert`
- `save-state-flags`

No snake_case aliases are intentionally provided except explicit compatibility helpers we expose (for example `parse-magnet-uri-dict`).

## object model

### `SessionHandle`
Created by:
- `(libtorrent.Session opts)`
- `(libtorrent.session [opts])`

Lifecycle:
- `drop`
- `is-closed`

Primary responsibilities:
- add/remove/find torrents
- session/torrent controls
- DHT operations
- alert polling
- status and completion waiting

### `AddTorrentParamsHandle`
Created by parsing/loading helpers, for example:
- `parse-magnet-uri-params`
- `load-torrent-file-params`
- `load-torrent-buffer-params`
- `load-torrent-parsed`
- `read-resume-data` / `read-resume-data-params`

Primary responsibilities:
- mutable add-torrent parameters
- serialization to resume/torrent buffers
- table inspection with `to-table`

### `SessionParamsHandle`
Created by:
- `session-params`
- `read-session-params`
- `ses:session-state`

Primary responsibilities:
- session bootstrap settings/ext-state
- session params serialization roundtrip

## top-level module api

### factory and utility
- `Session(opts)`
- `session([opts])`
- `session-params([opts])`
- `version()`

### torrent metadata and magnet
- `create-torrent(opts)`
- `parse-magnet-uri(uri)`
- `parse-magnet-uri-dict(uri)`
- `make-magnet-uri(torrent-path)`
- `make-magnet-uri-from-params(params-handle)`
- `load-torrent-file(path)`
- `load-torrent-buffer(buffer)`

### params/serialization helpers
- `parse-magnet-uri-params(uri)`
- `load-torrent-file-params(path)`
- `load-torrent-buffer-params(buffer)`
- `load-torrent-parsed(parsed-table)`
- `read-resume-data(buffer)`
- `read-resume-data-params(buffer)`
- `write-resume-data(params-handle)`
- `write-resume-data-buf(params-handle)`
- `write-torrent-file(params-handle)`
- `write-torrent-file-buf(params-handle)`
- `read-session-params(buffer[, flags])`
- `write-session-params(session-params-handle[, flags])`
- `write-session-params-buf(session-params-handle[, flags])`

### bencode helpers
- `bencode(value)`
- `bdecode(buffer)`

### settings/metrics presets
- `default-settings()`
- `high-performance-seed()`
- `min-memory-usage()`
- `session-stats-metrics()`
- `find-metric-idx(name)`

### ed25519 / mutable item signing helpers
- `ed25519-create-seed()`
- `ed25519-create-keypair(seed-hex)`
- `sign-mutable-item(opts)`
- `verify-mutable-item(opts)`

### operation/error helpers
- `operation-name(op-code)`
- `libtorrent-category-name()`
- `http-category-name()`
- `socks-category-name()`
- `upnp-category-name()`
- `i2p-category-name()`
- `system-category-name()`
- `generic-category-name()`
- `bdecode-category-name()`

### constants tables
- `torrent-flags`
- `storage-modes`
- `save-state-flags`
- `dht-announce-flags`

## `SessionHandle` api summary

### add/remove/find
- `add-torrent-file(opts)`
- `add-info-hash(opts)`
- `add-magnet-uri(uri[, opts])`
- `add-torrent-params(opts)`
- `get-torrents()`
- `find-torrent(info-hash-hex)`
- `remove-torrent(handle-id[, opts])`

### per-torrent control
- `pause-torrent(handle-id)`
- `resume-torrent(handle-id)`
- `set-torrent-download-limit(handle-id, value)` / `torrent-download-limit(handle-id)`
- `set-torrent-upload-limit(handle-id, value)` / `torrent-upload-limit(handle-id)`
- `set-torrent-max-connections(handle-id, value)` / `torrent-max-connections(handle-id)`
- `set-torrent-max-uploads(handle-id, value)` / `torrent-max-uploads(handle-id)`
- `set-torrent-piece-priorities(handle-id, priorities)` / `torrent-piece-priorities(handle-id)`
- `set-torrent-file-priorities(handle-id, priorities)` / `torrent-file-priorities(handle-id)`
- `force-reannounce(handle-id)`
- `force-dht-announce(handle-id)`
- `status(handle-id)`
- `torrent-info(handle-id)`
- `make-magnet-uri(handle-id)`
- `wait-for-complete(handle-id[, opts])`

### session control/settings
- `apply-settings(settings)`
- `get-settings()`
- `pause()` / `resume()` / `is-paused()`
- `session-status()`
- `session-state([flags])`

### alerts
- `set-alert-mask(mask)`
- `set-alert-queue-size-limit(limit)`
- `wait-for-alert(timeout-ms)`
- `pop-alerts()`
- `post-session-stats()`
- `post-dht-stats()`
- `post-torrent-updates()`

### DHT operations
- `start-dht()` / `stop-dht()` / `is-dht-running()`
- `add-dht-node({:host ... :port ...})`
- `add-dht-router({:host ... :port ...})`
- `dht-get-peers(info-hash-hex)`
- `dht-announce({:info-hash ... :port ... :flags ...})`
- `dht-live-nodes(node-id-hex)`
- `dht-sample-infohashes({:host ... :port ... :target ...})`
- `dht-get-item(target-hex)`
- `dht-put-item(item-table)` -> target hex
- `dht-get-mutable-item({:public-key ... [:salt ...]})`
- `dht-put-mutable-item({:public-key ... :secret-key ... [:salt ...] :seq ... :item ...})`
- `dht-direct-request({:host ... :port ... :request ...})`

## alert table enrichment

All alerts include base fields:
- `type`, `message`, `category`, `alert-type`, `timestamp-ms`

The binding enriches several alert families with additional keys (when present), including:
- add/session/state alerts
- DHT stats alerts
- immutable/mutable DHT item alerts
- DHT put alerts
- DHT get-peers/live-nodes/sample-infohashes replies
- DHT direct response alerts

Callers should treat optional fields as optional and type-check before use.

## testing strategy

Tests are implemented in Fennel modules under `assets/lua/tests/`.

Primary suites:
- `tests.test-libtorrent-offline:main` (fast enough for regular runs, no network requirement)
- `tests.test-libtorrent-online:main` (real network roundtrip; intentionally slow)
- `tests.test-libtorrent:main` (combined; includes online only when `SPACE_LIBTORRENT_INCLUDE_ONLINE=1`)

Typical commands:
- `SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tests.test-libtorrent-offline:main`
- `SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tests.test-libtorrent-online:main`
- `SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_LIBTORRENT_INCLUDE_ONLINE=1 SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tests.test-libtorrent:main`

## known limitations

- `verify-mutable-item` is not available in this environment's libtorrent binary (symbol declared in headers but not exported by the installed package). The binding throws a clear runtime error.
- `add-dht-router` is ABI-dependent and throws a clear runtime error when unavailable in the active libtorrent ABI.

## review findings (open)

- `bencode` empty-list ambiguity: empty Lua table currently encodes as dictionary, not list. In `src/lua_libtorrent.cpp`, list detection requires at least one numeric key, so `{}` cannot be represented as an empty bencoded list (`le`).
- `dht-direct-request` userdata gap: alert decoding exposes `userdata` on `dht-direct-response-alert`, but request submission currently has no user-facing way to set userdata, so this field is effectively always `nil`.

## source of truth

For exact function names and behavior, use:
- `src/lua_libtorrent.cpp`
- `assets/lua/tests/test-libtorrent-offline.fnl`
- `assets/lua/tests/test-libtorrent-online.fnl`
