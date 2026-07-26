;; External Unit MCP Server — standalone entrypoint that boots an isolated
;; loopback MCP server exposing external unit development tools.
;; Usage: ./build/space -m tools.external-unit-mcp-server:main

(fn main []
  (global app (or app {}))
  (local fs (require :fs))
  (local EngineModule (require :engine))

  ;; Install headless engine before any require that may auto-create one.
  ;; `main.fnl` auto-creates app.engine with Engine {} when absent, so we
  ;; must ensure the headless flag is already set before requiring :main.
  (when (not app.engine)
    (set app.engine (EngineModule.Engine {:headless true})))

  (local appdirs (require :appdirs))
  (local UnitManager (require :unit-manager))
  (local tempfile (require :tempfile))
  (local callbacks (require :callbacks))
  (local ExternalUnitMcpTools (require :llm/external-unit-mcp/tools))
  (local ExternalUnitService (require :llm/external-unit-mcp/service))
  (local ExternalUnitMcpBridge (require :llm/external-unit-mcp/bridge))
  (local Main (require :main))

  ;; Initialize app dirs
  (local data-dir (appdirs.user-data-dir "space"))
  (set app.user-data-dir data-dir)
  (set app.code-dir (fs.join-path data-dir "code"))

  ;; Ensure unit manager
  (when (not app.unit-manager)
    (set app.unit-manager (UnitManager {})))

  ;; Load user code units
  (Main.ensure-user-code-units!)

  ;; Create the service and tool registry
  (local service (ExternalUnitService.ExternalUnitService {:app app}))
  (local registry (ExternalUnitMcpTools.make-tool-registry {:app app}))
  (ExternalUnitMcpTools.register-tools registry service)

  ;; Create a temporary data directory for the bridge's isolated OpenCode config
  (local temp-handle (tempfile.TemporaryDirectory {:prefix "ext-unit-mcp-server-"}))
  (local bridge-data-dir temp-handle.path)

  ;; Create and start the bridge
  (local bridge (ExternalUnitMcpBridge.ExternalUnitMcpBridge
                  {:tools registry
                   :data-dir bridge-data-dir}))
  (bridge:start)

  (local status (bridge:status))
  (local env (bridge:opencode-env))

  (print (.. "MCP_URL=" status.url))
  (print (.. "OPENCODE_XDG_CONFIG_HOME=" env.XDG_CONFIG_HOME))
  (io.stdout:flush)

  ;; Run the event loop — this blocks indefinitely
  (callbacks.run-loop {:poll-http true :sleep-ms 10}))

{:main main}
