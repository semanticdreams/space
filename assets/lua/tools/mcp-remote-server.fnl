(fn main []
  (local http-server-mod (require :http_server))
  (local ToolRegistry (require :mcp/tool-registry))
  (local MCPHTTPServer (require :mcp/server-http))
  (local callbacks (require :callbacks))

  (local tools (ToolRegistry {:namespace-prefix "space_"}))
  (tools:register {:name "space_ping" :description "Ping" :inputSchema {:type "object" :properties {}} :run (fn [] "pong")})
  (tools:register {:name "space_get_time" :description "Time" :inputSchema {:type "object" :properties {}} :run (fn [] (os.date "!%Y-%m-%dT%H:%M:%SZ"))})

  (local srv (MCPHTTPServer {:http-server (http-server-mod.HttpServer) :tools tools :force-sse true}))
  (local port (srv:start "127.0.0.1" 0))
  (print (.. "MCP_PORT=" port)) (io.stdout:flush)

  (callbacks.run-loop {:poll-http true :sleep-ms 10}))

{:main main}
