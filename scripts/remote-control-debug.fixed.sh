#!/usr/bin/env bash
set -euo pipefail

endpoint="${SPACE_RC_ENDPOINT:-ipc:///tmp/space-rc.sock}"

if [[ "${1:-}" == "--endpoint" ]]; then
  endpoint="$2"
  shift 2
fi

code='(do
  (local nodes [])
  (when (and app app.graph app.graph.nodes)
    (each [k node (pairs app.graph.nodes)]
      (table.insert nodes (or node.label node.key k))))
  (table.sort nodes)
  (local selected [])
  (local sel (and app app.graph-view app.graph-view.selection app.graph-view.selection.selected-nodes))
  (when sel
    (each [_ node (ipairs sel)]
      (table.insert selected (or node.label node.key))))
  (table.sort selected)
  {:nodes nodes :selected selected})'

SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH="$(pwd)/assets" \
  ./build/space -m tools.remote-control-client:main -- --endpoint "$endpoint" -c "$code"
