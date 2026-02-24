#!/usr/bin/env bash
set -euo pipefail

# Captures the front browser cube surface texture directly from OpenGL and writes a PNG.
# This validates CEF -> browser surface -> texture upload even when scene framebuffer capture is unreliable.

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

OUT_PATH="${1:-/tmp/space/tests/cef/browser-front-texture.png}"
ENDPOINT="ipc:///tmp/space-rc-browser.sock"
SOCKET_PATH="${ENDPOINT#ipc://}"
LOG_PATH="/tmp/space-cef-texdump.log"

mkdir -p "$(dirname "$OUT_PATH")"
rm -rf /tmp/space/cef-cache
rm -f "$SOCKET_PATH"

CEF_REL=$(echo build/_deps/cef/cef_binary_*_linux64/Release)
cp -f build/icudtl.dat "$CEF_REL/icudtl.dat"
cp -f build/resources.pak "$CEF_REL/resources.pak"
cp -f build/chrome_100_percent.pak "$CEF_REL/chrome_100_percent.pak"
cp -f build/chrome_200_percent.pak "$CEF_REL/chrome_200_percent.pak"
mkdir -p "$CEF_REL/locales"
cp -af build/locales/. "$CEF_REL/locales/"

SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH="$ROOT_DIR/assets" SPACE_BROWSER_CUBE_DEMO=1 \
  xvfb-run -a -s "-screen 0 1280x720x24" "$ROOT_DIR/build/space" -m main --remote-control="$ENDPOINT" \
  >"$LOG_PATH" 2>&1 &
SERVER_PID=$!
cleanup() {
  kill "$SERVER_PID" 2>/dev/null || true
}
trap cleanup EXIT

for _ in $(seq 1 200); do
  [[ -S "$SOCKET_PATH" ]] && break
  sleep 0.1
done
if [[ ! -S "$SOCKET_PATH" ]]; then
  echo "error: remote control socket not ready: $SOCKET_PATH" >&2
  tail -n 120 "$LOG_PATH" || true
  exit 2
fi

REQUEST_REPLY=$(SPACE_SKIP_CEF=1 "$ROOT_DIR/build/space" -m tools.remote-control-client:main -- --endpoint "$ENDPOINT" -c "(do
  (local id (remote_control.create))
  (local gl (require :gl))
  (local ImageIO (require :image-io))
  (var info nil)
  (var frames 0)
  (var tick nil)
  (set tick (fn []
    (set frames (+ frames 1))
    (set info ((. app.engine.browser \"texture-info\") \"browser-cube-front\"))
    (local stats ((. app.engine.browser \"surface-stats\") \"browser-cube-front\"))
    (if (and info stats (> (. stats \"upload-count\") 0) (>= frames 60))
        (do
          (gl.glBindTexture gl.GL_TEXTURE_2D (. info \"id\"))
          (local bytes (gl.glGetTexImage gl.GL_TEXTURE_2D 0 gl.GL_RGBA gl.GL_UNSIGNED_BYTE (. info \"width\") (. info \"height\")))
          (local flipped (ImageIO.flip-vertical (. info \"width\") (. info \"height\") 4 bytes))
          (ImageIO.write-png \"$OUT_PATH\" (. info \"width\") (. info \"height\") 4 flipped)
          (remote_control.resolve id {:frames frames :info info :stats stats :path \"$OUT_PATH\"}))
        (app.next-frame tick))))
  (app.next-frame tick)
  id)")

REQUEST_ID="${REQUEST_REPLY#ok }"
if [[ -z "$REQUEST_ID" || "$REQUEST_REPLY" == "$REQUEST_ID" ]]; then
  echo "error: unexpected request reply: $REQUEST_REPLY" >&2
  exit 3
fi

for _ in $(seq 1 300); do
  RESP=$(SPACE_SKIP_CEF=1 "$ROOT_DIR/build/space" -m tools.remote-control-client:main -- --endpoint "$ENDPOINT" -c "(do
    (local e (remote_control.poll \"$REQUEST_ID\" true))
    (if (= e.status \"ok\") (fennel.view e.value) \"pending\"))")
  if [[ "$RESP" != "ok pending" ]]; then
    echo "$RESP"
    break
  fi
  sleep 0.1
done

if [[ ! -f "$OUT_PATH" ]]; then
  echo "error: output image missing: $OUT_PATH" >&2
  tail -n 120 "$LOG_PATH" || true
  exit 4
fi

file "$OUT_PATH"
