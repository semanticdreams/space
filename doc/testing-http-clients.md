# HTTP client testing

We keep both online and offline coverage for HTTP clients so we can validate network behaviour when available while still running fast, deterministic tests in CI and locally without external calls.

- Online tests hit the real service and are intentionally opt-in (see `assets/lua/tests/test-hackernews-online.fnl`).
- Offline tests replay recorded responses from `assets/lua/tests/data/*.json` through a mock `http` binding so we still exercise the full client code path, including caching, status handling, and headers.

## Recording fixtures

`assets/lua/tests/http-fixtures.fnl` includes `record-responses!` to capture HTTP replies into JSON fixtures. Example for the Hacker News client:

```sh
SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -c '(do
  (local fixtures (require :tests/http-fixtures))
  (fixtures.record-responses!
    [{:key "topstories" :url "https://hacker-news.firebaseio.com/v0/topstories.json"}
     {:key "item/8863" :url "https://hacker-news.firebaseio.com/v0/item/8863.json"}
     {:key "user/dhouston" :url "https://hacker-news.firebaseio.com/v0/user/dhouston.json"}
     {:key "updates" :url "https://hacker-news.firebaseio.com/v0/updates.json"}
     {:key "maxitem" :url "https://hacker-news.firebaseio.com/v0/maxitem.json"}]
    (app.engine.get-asset-path \"lua/tests/data/hackernews-fixture.json\")))'
```

The helper asserts that the `http`, `fs`, and `json` bindings are present, waits for each response, and writes a single JSON file containing status codes, headers, and bodies. We keep fixtures small and representative so they remain readable in version control.

## Replaying fixtures in tests

Use `install-mock` from the same helper to replace `_G.http` with a replay-only binding:

```fennel
(local fixtures (require :tests/http-fixtures))
(local fixture (fixtures.read-json (app.engine.get-asset-path "lua/tests/data/hackernews-fixture.json")))
(local handle (fixtures.install-mock fixture))
;; run client code
(handle.restore) ;; always restore in a finally block
```

The mock:

- Matches requests by URL (after stripping `.json` and the `/v0/` prefix) or by explicit `key`.
- Returns recorded `status`, `headers`, `body`, and `ok` flags.
- Surfaces requests through `mock.requests` so tests can assert on headers and status codes in addition to parsed bodies.

## Hacker News offline coverage

`assets/lua/tests/test-hackernews-offline.fnl` installs the mock, runs the real client against `assets/lua/tests/data/hackernews-fixture.json`, and asserts:

- Lists and items parse from the recorded bodies.
- Status codes and `content-type` headers survive the replay.
- Caching is exercised by fetching an item twice and verifying the second hit comes from disk.
- Updates and `maxitem` parsing work without network access.

The module is registered in `assets/lua/tests/fast.fnl`, so the offline tests run with the rest of the suite by default. Refresh fixtures and rerun the suite whenever the client changes its request surface or response expectations.
