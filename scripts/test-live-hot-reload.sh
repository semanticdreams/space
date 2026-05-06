#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

export SPACE_LOG_DIR="${SPACE_LOG_DIR:-/tmp/space/log}"
export SPACE_DISABLE_AUDIO="${SPACE_DISABLE_AUDIO:-1}"
export SPACE_ASSETS_PATH="${SPACE_ASSETS_PATH:-$ROOT_DIR/assets}"
export FENNEL_PATH="${FENNEL_PATH:-$ROOT_DIR/assets/lua/?.fnl;$ROOT_DIR/assets/lua/?/init.fnl}"
export FENNEL_MACRO_PATH="${FENNEL_MACRO_PATH:-$ROOT_DIR/assets/lua/?.fnl;$ROOT_DIR/assets/lua/?/init.fnl}"
export XDG_DATA_HOME="${XDG_DATA_HOME:-/tmp/space/tests/xdg-data}"
export SKIP_KEYRING_TESTS="${SKIP_KEYRING_TESTS:-1}"

cd "$ROOT_DIR"
./build/space -m tests.test-live-hot-reload:main "$@"
