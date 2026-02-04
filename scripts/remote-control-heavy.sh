#!/usr/bin/env bash
set -euo pipefail

endpoint="${1:-ipc:///tmp/space-rc.sock}"
socket_path="${endpoint#ipc://}"
log_dir="${SPACE_LOG_DIR:-/tmp/space/log}"

rm -f "$socket_path"

SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH="$(pwd)/assets" SPACE_LOG_DIR="$log_dir" \
  ./build/space -m main --remote-control="$endpoint" >/tmp/space-rc.log 2>&1 &
server_pid=$!

cleanup() {
  kill "$server_pid" 2>/dev/null || true
}
trap cleanup EXIT

for _ in $(seq 1 50); do
  if [[ -S "$socket_path" ]]; then
    break
  fi
  sleep 0.1
done

if [[ ! -S "$socket_path" ]]; then
  echo "error: remote control socket not created at $socket_path" >&2
  exit 2
fi

request_reply=$(
  ./build/space -m tools.remote-control-client:main -- --endpoint "$endpoint" -c \
    "(do
       (local id (remote_control.create))
       (when app.remote_control_handler
         (app.camera.debounced-changed:disconnect app.remote_control_handler true))
       (set app.remote_control_handler
         (app.camera.debounced-changed:connect
           (fn [payload]
             (local pos (and payload payload.position))
             (when (and pos (> pos.x 4.5) (< pos.x 5.5))
               (remote_control.resolve id {:position pos})
               (app.camera.debounced-changed:disconnect app.remote_control_handler true)
               (set app.remote_control_handler nil)))))
       id)"
)

request_id="${request_reply#ok }"
if [[ -z "$request_id" || "$request_reply" == "$request_id" ]]; then
  echo "error: unexpected request reply: $request_reply" >&2
  exit 3
fi

./build/space -m tools.remote-control-client:main -- --endpoint "$endpoint" -c \
  "(do
     (local glm (require :glm))
     (app.camera:set-position (glm.vec3 5 0 0))
     \"moved\")" >/dev/null

for _ in $(seq 1 50); do
  poll_reply=$(
    ./build/space -m tools.remote-control-client:main -- --endpoint "$endpoint" -c \
      "(do
         (local entry (remote_control.poll \"$request_id\" true))
         (if (= entry.status \"ok\")
             (string.format \"ok %.2f %.2f %.2f\"
                            (. entry.value.position :x)
                            (. entry.value.position :y)
                            (. entry.value.position :z))
             \"pending\"))"
  )
  if [[ "$poll_reply" == ok\ * ]]; then
    echo "$poll_reply"
    exit 0
  fi
  sleep 0.1
done

echo "error: timed out waiting for remote control response" >&2
exit 4
