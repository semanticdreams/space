(fn main []
  (local http-server-mod (require :http_server))
  (local MCPHTTPServer (require :mcp/server-http))
  (local callbacks (require :callbacks))

  (local tools (and _G.app _G.app.mcp-tools))
  (assert tools "tools.mcp-remote-server requires app.mcp-tools from app bootstrap")

  (local srv (MCPHTTPServer {:http-server (http-server-mod.HttpServer) :tools tools :force-sse true}))
  (local port (srv:start "127.0.0.1" 0))
  (print (.. "MCP_PORT=" port)) (io.stdout:flush)

  (callbacks.run-loop {:poll-http true :sleep-ms 10}))

{:main main}
