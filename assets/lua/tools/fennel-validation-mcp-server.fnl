;; Standalone loopback MCP server exposing read-only Fennel validation tools.
;; Usage: ./build/space -m tools.fennel-validation-mcp-server:main

(fn main []
  (local tempfile (require :tempfile))
  (local callbacks (require :callbacks))
  (local FennelValidationMcpTools (require :llm/fennel-validation/tools))
  (local FennelValidationService (require :llm/fennel-validation/service))
  (local FennelValidationMcpBridge (require :llm/fennel-validation/bridge))

  (local service (FennelValidationService.FennelValidationService {}))
  (local registry (FennelValidationMcpTools.make-tool-registry {}))
  (FennelValidationMcpTools.register-tools registry service)

  (local temp-handle (tempfile.TemporaryDirectory {:prefix "fennel-validation-mcp-server-"}))
  (local bridge (FennelValidationMcpBridge.FennelValidationMcpBridge
                  {:tools registry
                   :data-dir temp-handle.path}))
  (bridge:start)

  (local status (bridge:status))
  (local env (bridge:opencode-env))
  (print (.. "MCP_URL=" status.url))
  (print (.. "OPENCODE_XDG_CONFIG_HOME=" env.XDG_CONFIG_HOME))
  (io.stdout:flush)

  (callbacks.run-loop {:poll-http true :sleep-ms 10}))

{:main main}
