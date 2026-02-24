#!/usr/bin/env bash
set -euo pipefail

# Captures the browser cube as rendered in-scene.
# Uses app.viewport dimensions by omitting explicit width/height in RenderCapture.

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

OUT_PATH="${1:-/tmp/space/tests/cef/browser-cube-visible.png}"
URL_ARG="${2:-}"
DEFAULT_SMOKE_URL="data:text/html,%3Chtml%3E%3Cbody%20style%3D%27margin%3A0%3Bbackground%3A%23f8fafc%3Bfont-family%3Asans-serif%3Bdisplay%3Aflex%3Balign-items%3Acenter%3Bjustify-content%3Acenter%3Bheight%3A100vh%3B%27%3E%3Cdiv%20style%3D%27font-size%3A96px%3Bcolor%3A%230f172a%3Bfont-weight%3A700%3B%27%3ECEF%20OK%3C/div%3E%3C/body%3E%3C/html%3E"
URL="${URL_ARG:-$DEFAULT_SMOKE_URL}"

ENDPOINT="ipc:///tmp/space-rc-browser-visible.sock"
SOCKET_PATH="${ENDPOINT#ipc://}"
LOG_PATH="/tmp/space-cef-visible.log"

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

SPACE_SKIP_CEF=1 "$ROOT_DIR/build/space" -m tools.remote-control-client:main -- --endpoint "$ENDPOINT" -c "(do
  (local glm (require :glm))
  (local BrowserCubeSurface (require :browser-cube-surface))
  (when app.browser-cube-surface
    (app.browser-cube-surface:drop))
  (set app.browser-cube-surface
       (BrowserCubeSurface {:center (glm.vec3 0 0 0)
                            :size 10.0
                            :width 1024
                            :height 1024
                            :url \"$URL\"}))
  (when app.camera
    (app.camera:set-position (glm.vec3 0 0 14))
    (app.camera:look-at (glm.vec3 0 0 0)))
  \"scene-reset\")" >/dev/null

REQUEST_REPLY=$(SPACE_SKIP_CEF=1 "$ROOT_DIR/build/space" -m tools.remote-control-client:main -- --endpoint "$ENDPOINT" -c "(do
  (local id (remote_control.create))
  (local RenderCapture (require :render-capture))
  (var frames 0)
  (var tick nil)
  (set tick (fn []
    (set frames (+ frames 1))
    (if (< frames 150)
        (app.next-frame tick)
        (do
          (RenderCapture.capture {:mode \"final\" :path \"$OUT_PATH\"})
          (remote_control.resolve id {:frames frames :path \"$OUT_PATH\" :viewport app.viewport})))))
  (app.next-frame tick)
  id)")

REQUEST_ID="${REQUEST_REPLY#ok }"
if [[ -z "$REQUEST_ID" || "$REQUEST_REPLY" == "$REQUEST_ID" ]]; then
  echo "error: unexpected request reply: $REQUEST_REPLY" >&2
  exit 3
fi

for _ in $(seq 1 400); do
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

SPACE_SKIP_CEF=1 "$ROOT_DIR/build/space" -m tools.remote-control-client:main -- --endpoint "$ENDPOINT" -c "(do
  (local rows [])
  (each [_ id (ipairs ((. app.engine.browser \"list-surfaces\")))]
    (local s ((. app.engine.browser \"surface-stats\") id))
    (table.insert rows {:id id
                        :paint (and s (. s \"paint-count\"))
                        :upload (and s (. s \"upload-count\"))}))
  (fennel.view rows))"

file "$OUT_PATH"
