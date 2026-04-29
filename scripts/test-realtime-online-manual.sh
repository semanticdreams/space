#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d /tmp/space-realtime-manual-XXXXXX)"
TOKEN_PATH="$TMP_DIR/token.bin"
CLIENT_ID="${SPACE_REALTIME_CLIENT_ID:-9898}"
SERVER_PID=""

cleanup() {
    if [[ -n "$SERVER_PID" ]] && kill -0 "$SERVER_PID" 2>/dev/null; then
        kill "$SERVER_PID" 2>/dev/null || true
        wait "$SERVER_PID" 2>/dev/null || true
    fi
    rm -rf "$TMP_DIR"
}
trap cleanup EXIT

export SPACE_LOG_DIR="${SPACE_LOG_DIR:-/tmp/space/log}"
export SPACE_DISABLE_AUDIO="${SPACE_DISABLE_AUDIO:-1}"
export SPACE_ASSETS_PATH="${SPACE_ASSETS_PATH:-$ROOT_DIR/assets}"
export FENNEL_PATH="${FENNEL_PATH:-$ROOT_DIR/assets/lua/?.fnl;$ROOT_DIR/assets/lua/?/init.fnl}"
export FENNEL_MACRO_PATH="${FENNEL_MACRO_PATH:-$ROOT_DIR/assets/lua/?.fnl;$ROOT_DIR/assets/lua/?/init.fnl}"
export XDG_DATA_HOME="${XDG_DATA_HOME:-/tmp/space/tests/xdg-data}"
export SKIP_KEYRING_TESTS="${SKIP_KEYRING_TESTS:-1}"
export SPACE_REALTIME_TOKEN_PATH="$TOKEN_PATH"
export SPACE_REALTIME_CLIENT_ID="$CLIENT_ID"

cd "$ROOT_DIR"

./build/space -m tests.test-realtime-online-server:main &
SERVER_PID=$!

for _ in $(seq 1 500); do
    if [[ -f "$TOKEN_PATH" ]]; then
        break
    fi
    sleep 0.01
done

if [[ ! -f "$TOKEN_PATH" ]]; then
    echo "server did not produce token file" >&2
    exit 1
fi

./build/space -m tests.test-realtime-online-client:main
wait "$SERVER_PID"
