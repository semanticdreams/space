---
type: subsystem
tags:
  - subsystem
  - networking
created: 2026-07-14
---

# Networking system

yojimbo-based realtime client/server with feature protocol and auth ticketing, Matrix federation bridge, libtorrent P2P asset distribution, and HTTP client/server infrastructure.

## Key files

- `src/realtime/` — yojimbo C++ networking layer
- `src/lua_matrix.h` — Matrix bindings
- `src/lua_libtorrent.cpp` — libtorrent bindings
- `src/http_client.h`, `src/lua_http_server.h` — HTTP infrastructure

## Dependencies

- Depends on: [[core-platform]]

## Dev notes

- [[dev-notes/yojimbo]] — realtime networking with yojimbo
- [[dev-notes/matrix]] — Matrix messaging integration
- [[dev-notes/libtorrent]] — P2P asset distribution

## See also

- [[core-platform]]
- [[subsystems]]
