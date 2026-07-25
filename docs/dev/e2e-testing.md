# E2E Snapshot Tests

- Run the full suite with `SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets make test-e2e`.
- Update goldens with `SPACE_SNAPSHOT_UPDATE=name1,name2 SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets make test-e2e`.
- Individual tests can be run via `./build/space -m tests.e2e.<module>:main` (e.g. `tests.e2e.test-image:main`).
- Snapshot images live in `assets/lua/tests/data/snapshots/` and should be inspected directly when adding/debugging tests.
