;; MCP-over-HTTP integration tests.
;; Starts an HTTP MCP server, sends protocol requests via HTTP client, verifies responses.
;; Run: SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tests.test-mcp-http:main

(local tests [])
(local http-server-mod (require :http_server))
(local http (require :http))
(local json (require :json))
(local ToolRegistry (require :mcp/tool-registry))
(local MCPHTTPServer (require :mcp/server-http))
(local callbacks (require :callbacks))
(local sysinfo (require :sysinfo))

(fn poll-all []
  (callbacks.run-loop {:poll-http true :sleep-ms 5 :timeout-ms 50}))

(fn wait-for [pred timeout-ms]
  (local deadline (+ (sysinfo.now-ms) (or timeout-ms 5000)))
  (var result nil)
  (while (and (not result) (< (sysinfo.now-ms) deadline))
    (poll-all)
    (local (ok val) (pcall pred))
    (when ok (set result val)))
  (assert result (.. "timeout after " (or timeout-ms 5000) "ms")))

(fn stream-body [chunks]
  (var body "")
  (each [_ item (ipairs chunks)]
    (when item.chunk
      (set body (.. body item.chunk))))
  body)

;; ── Setup ──

(fn test-initialize-handshake []
  (local tools (ToolRegistry))
  (tools:register {:name "ping"
                   :description "Ping"
                   :inputSchema {:type "object" :properties {}}
                   :run (fn [] "pong")})

  (local srv (MCPHTTPServer {:http-server (http-server-mod.HttpServer)
                             :tools tools}))
  (srv:start "127.0.0.1" 0)

  (var response nil)
  (http.request
    {:method "POST"
     :url (.. "http://127.0.0.1:" (srv:port) "/mcp")
     :headers {:Content-Type "application/json"}
     :body (json.dumps {:jsonrpc "2.0" :id 1 :method "initialize"
                        :params {:protocolVersion "2025-03-26"
                                 :capabilities {}
                                 :clientInfo {:name "test" :version "1.0"}}})
     :callback (fn [res] (set response res))})

  (wait-for #response)

  (assert (= response.status 200)
          (.. "initialize should return 200, got " (tostring response.status)
              " error: " (tostring response.error)
              " body: " (tostring response.body)))
  (local data (json.loads response.body))
  (assert (= data.jsonrpc "2.0") "should be jsonrpc 2.0")
  (assert (= data.id 1) "id should match")
  (assert data.result "should have result")
  (assert (= data.result.protocolVersion "2025-03-26") "protocol version should match")
  (assert data.result.capabilities.tools "should have tools capability")
  (assert data.result.serverInfo "should have serverInfo")

  ;; Verify session id header is present
  (var session-id nil)
  (each [_ h (ipairs (or response.headers []))]
    (when (= (. h 1) "mcp-session-id")
      (set session-id (. h 2))))
  (assert session-id "should have mcp-session-id header")

  (srv:stop))

(table.insert tests {:name "mcp-http: initialize handshake with session" :fn test-initialize-handshake})

(fn test-tools-list []
  (local tools (ToolRegistry))
  (tools:register {:name "ping"
                   :description "Ping tool"
                   :inputSchema {:type "object" :properties {}}
                   :run (fn [] "pong")})
  (tools:register {:name "echo"
                   :description "Echo tool"
                   :inputSchema {:type "object" :properties {:msg {:type "string"}}}
                   :run (fn [args] (or args.msg "no message"))})

  (local srv (MCPHTTPServer {:http-server (http-server-mod.HttpServer)
                             :tools tools}))
  (srv:start "127.0.0.1" 0)
  (local port (srv:port))

  ;; Initialize first
  (var session-id nil)
  (var init-resp nil)
  (http.request
    {:method "POST"
     :url (.. "http://127.0.0.1:" port "/mcp")
     :headers {:Content-Type "application/json"}
     :body (json.dumps {:jsonrpc "2.0" :id 1 :method "initialize"
                        :params {:protocolVersion "2025-03-26"
                                 :capabilities {}
                                 :clientInfo {:name "test" :version "1.0"}}})
     :callback (fn [res]
                 (set init-resp res)
                 (each [_ h (ipairs (or res.headers []))]
                   (when (= (. h 1) "mcp-session-id")
                     (set session-id (. h 2)))))})
  (wait-for #session-id)

  ;; Now send tools/list with session header
  (var list-resp nil)
  (http.request
    {:method "POST"
     :url (.. "http://127.0.0.1:" port "/mcp")
     :headers {:Content-Type "application/json"
               :Mcp-Session-Id session-id}
     :body (json.dumps {:jsonrpc "2.0" :id 2 :method "tools/list"})
     :callback (fn [res] (set list-resp res))})
  (wait-for #list-resp)

  (assert (= list-resp.status 200) "tools/list should return 200")
  (local data (json.loads list-resp.body))
  (assert data.result "should have result")
  (assert data.result.tools "should have tools")
  (assert (= (# data.result.tools) 2) "should have 2 tools")

  ;; Verify tool names in any order
  (var names {})
  (each [_ t (ipairs data.result.tools)]
    (tset names t.name true))
  (assert names.ping "should have ping")
  (assert names.echo "should have echo")

  (srv:stop))

(table.insert tests {:name "mcp-http: tools/list with session header" :fn test-tools-list})

(fn test-tools-call []
  (local tools (ToolRegistry))
  (tools:register {:name "ping"
                   :description "Ping"
                   :inputSchema {:type "object" :properties {}}
                   :run (fn [] "pong")})

  (local srv (MCPHTTPServer {:http-server (http-server-mod.HttpServer)
                             :tools tools}))
  (srv:start "127.0.0.1" 0)
  (local port (srv:port))

  ;; Initialize
  (var session-id nil)
  (var init-resp nil)
  (http.request
    {:method "POST"
     :url (.. "http://127.0.0.1:" port "/mcp")
     :headers {:Content-Type "application/json"}
     :body (json.dumps {:jsonrpc "2.0" :id 1 :method "initialize"
                        :params {:protocolVersion "2025-03-26"
                                 :capabilities {}
                                 :clientInfo {:name "test" :version "1.0"}}})
     :callback (fn [res]
                 (each [_ h (ipairs (or res.headers []))]
                   (when (= (. h 1) "mcp-session-id")
                     (set session-id (. h 2)))))})
  (wait-for #session-id)

  ;; Call ping tool
  (var call-resp nil)
  (http.request
    {:method "POST"
     :url (.. "http://127.0.0.1:" port "/mcp")
     :headers {:Content-Type "application/json"
               :Mcp-Session-Id session-id}
     :body (json.dumps {:jsonrpc "2.0" :id 2 :method "tools/call"
                        :params {:name "ping" :arguments {}}})
     :callback (fn [res] (set call-resp res))})
  (wait-for #call-resp)

  (assert (= call-resp.status 200) "tools/call should return 200")
  (local data (json.loads call-resp.body))
  (assert data.result "should have result")
  (assert data.result.content "should have content")
  (assert (= data.result.isError false) "should not be error")

  ;; Call unknown tool
  (var err-resp nil)
  (http.request
    {:method "POST"
     :url (.. "http://127.0.0.1:" port "/mcp")
     :headers {:Content-Type "application/json"
               :Mcp-Session-Id session-id}
     :body (json.dumps {:jsonrpc "2.0" :id 3 :method "tools/call"
                        :params {:name "nonexistent" :arguments {}}})
     :callback (fn [res] (set err-resp res))})
  (wait-for #err-resp)

  (local err-data (json.loads err-resp.body))
  (assert err-data.error "unknown tool should return error")
  (assert (= err-data.error.code -32602) "should be INVALID_PARAMS")

  (srv:stop))

(table.insert tests {:name "mcp-http: tools/call with session" :fn test-tools-call})

(fn test-missing-session-header []
  (local tools (ToolRegistry))
  (local srv (MCPHTTPServer {:http-server (http-server-mod.HttpServer)
                             :tools tools}))
  (srv:start "127.0.0.1" 0)
  (local port (srv:port))

  ;; Send tools/list without session header
  (var resp nil)
  (http.request
    {:method "POST"
     :url (.. "http://127.0.0.1:" port "/mcp")
     :headers {:Content-Type "application/json"}
     :body (json.dumps {:jsonrpc "2.0" :id 1 :method "tools/list"})
     :callback (fn [res] (set resp res))})
  (wait-for #resp)

  (assert (= resp.status 400) "should return 400 for missing session")
  (local data (json.loads resp.body))
  (assert data.error "should have error")
  (assert (= data.error.code -32001) "should be session error code")

  (srv:stop))

(table.insert tests {:name "mcp-http: missing session header returns 400"
                     :fn test-missing-session-header})

(fn test-notification-handling []
  (local tools (ToolRegistry))
  (local srv (MCPHTTPServer {:http-server (http-server-mod.HttpServer)
                             :tools tools}))
  (srv:start "127.0.0.1" 0)
  (local port (srv:port))

  ;; Initialize
  (var session-id nil)
  (http.request
    {:method "POST"
     :url (.. "http://127.0.0.1:" port "/mcp")
     :headers {:Content-Type "application/json"}
     :body (json.dumps {:jsonrpc "2.0" :id 1 :method "initialize"
                        :params {:protocolVersion "2025-03-26"
                                 :capabilities {}
                                 :clientInfo {:name "test" :version "1.0"}}})
     :callback (fn [res]
                 (each [_ h (ipairs (or res.headers []))]
                   (when (= (. h 1) "mcp-session-id")
                     (set session-id (. h 2)))))})
  (wait-for #session-id)

  ;; Send initialized notification
  (var notif-resp nil)
  (http.request
    {:method "POST"
     :url (.. "http://127.0.0.1:" port "/mcp")
     :headers {:Content-Type "application/json"
               :Mcp-Session-Id session-id}
     :body (json.dumps {:jsonrpc "2.0" :method "notifications/initialized"})
     :callback (fn [res] (set notif-resp res))})
  (wait-for #notif-resp)

  (assert (= notif-resp.status 202) "notification should return 202 accepted")

  (srv:stop))

(table.insert tests {:name "mcp-http: notification returns 202" :fn test-notification-handling})

(fn test-force-sse-rejects-before-initialize []
  (local tools (ToolRegistry))
  (local srv (MCPHTTPServer {:http-server (http-server-mod.HttpServer)
                             :tools tools
                             :force-sse true}))
  (srv:start "127.0.0.1" 0)
  (local port (srv:port))

  (var resp nil)
  (http.request
    {:method "POST"
     :url (.. "http://127.0.0.1:" port "/mcp")
     :headers {:Content-Type "application/json"}
     :body (json.dumps {:jsonrpc "2.0" :id 1 :method "initialize"})
     :callback (fn [res] (set resp res))})
  (wait-for #resp)

  (assert (= resp.status 500) "force-sse should reject POST before SSE connects")
  (assert (string.find (or resp.body "") "Use SSE transport" 1 true)
          (.. "force-sse rejection should explain SSE transport, got: " (tostring resp.body)))
  (srv:stop))

(table.insert tests {:name "mcp-http: force-sse rejects pre-stream POST"
                     :fn test-force-sse-rejects-before-initialize})

(fn test-query-session-id []
  (local tools (ToolRegistry))
  (tools:register {:name "ping"
                   :description "Ping"
                   :inputSchema {:type "object" :properties {}}
                   :run (fn [] "pong")})
  (local srv (MCPHTTPServer {:http-server (http-server-mod.HttpServer)
                             :tools tools}))
  (srv:start "127.0.0.1" 0)
  (local port (srv:port))
  (local session-id "test-query-session")

  (var init-resp nil)
  (http.request
    {:method "POST"
     :url (.. "http://127.0.0.1:" port "/mcp?sessionId=" session-id)
     :headers {:Content-Type "application/json"}
     :body (json.dumps {:jsonrpc "2.0" :id 1 :method "initialize"
                        :params {:protocolVersion "2025-03-26"
                                 :capabilities {}
                                 :clientInfo {:name "test" :version "1.0"}}})
     :callback (fn [res] (set init-resp res))})
  (wait-for #init-resp)
  (assert (= init-resp.status 200) "query initialize should return 200")

  (var list-resp nil)
  (http.request
    {:method "POST"
     :url (.. "http://127.0.0.1:" port "/mcp?sessionId=" session-id)
     :headers {:Content-Type "application/json"}
     :body (json.dumps {:jsonrpc "2.0" :id 2 :method "tools/list"})
     :callback (fn [res] (set list-resp res))})
  (wait-for #list-resp)
  (assert (= list-resp.status 200)
          (.. "query session tools/list should return 200, got " list-resp.status
              " body: " (tostring list-resp.body)))
  (local data (json.loads list-resp.body))
  (assert (= (. data.result.tools 1 :name) "ping") "should list query-session tool")
  (srv:stop))

(table.insert tests {:name "mcp-http: query session id works for SSE endpoint"
                     :fn test-query-session-id})

(fn test-server-status []
  (local tools (ToolRegistry {:namespace-prefix "space_"}))
  (tools:register {:name "space_ping"
                   :description "Ping"
                   :inputSchema {:type "object" :properties {}}
                   :run (fn [] "pong")})
  (local srv (MCPHTTPServer {:http-server (http-server-mod.HttpServer)
                             :tools tools
                             :force-sse true}))
  (local port (srv:start "127.0.0.1" 0))
  (local status (srv:status))
  (assert status.running "status should report running")
  (assert (= status.hostname "127.0.0.1") "status should report host")
  (assert (= status.port port) "status should report port")
  (assert (= status.tool-count 1) "status should report tool count")
  (assert (= status.tool-namespace-prefix "space_") "status should report tool namespace")
  (assert (= status.force-sse true) "status should report force-sse")

  (var resp nil)
  (http.request
    {:method "POST"
     :url (.. "http://127.0.0.1:" port "/mcp")
     :headers {:Content-Type "application/json"}
     :body (json.dumps {:jsonrpc "2.0" :id 1 :method "initialize"})
     :callback (fn [res] (set resp res))})
  (wait-for #resp)
  (local rejected-status (srv:status))
  (assert (= rejected-status.last-error "Use SSE transport")
          "status should expose force-sse rejection")
  (srv:stop)
  (local stopped-status (srv:status))
  (assert (not stopped-status.running) "status should report stopped"))

(table.insert tests {:name "mcp-http: server status reports diagnostics"
                     :fn test-server-status})

(fn test-sse-reconnect-status []
  (local tools (ToolRegistry {:namespace-prefix "space_"}))
  (tools:register {:name "space_ping"
                   :description "Ping"
                   :inputSchema {:type "object" :properties {}}
                   :run (fn [] "pong")})
  (local srv (MCPHTTPServer {:http-server (http-server-mod.HttpServer)
                             :tools tools
                             :force-sse true}))
  (local port (srv:start "127.0.0.1" 0))
  (var chunks1 [])
  (var chunks2 [])

  (http.request
    {:method "GET"
     :url (.. "http://127.0.0.1:" port "/mcp")
     :headers {:Accept "text/event-stream"}
     :stream true
     :callback (fn [res] (table.insert chunks1 res))})
  (wait-for (fn []
              (local st (srv:status))
              (and st.sse-connected
                   (string.find (stream-body chunks1) "event: endpoint" 1 true)))
            5000)
  (local first-status (srv:status))
  (assert (= first-status.sse-connect-count 1) "first stream should connect once")
  (assert (= first-status.list-changed-count 1) "first stream should get list_changed")

  (http.request
    {:method "GET"
     :url (.. "http://127.0.0.1:" port "/mcp")
     :headers {:Accept "text/event-stream"}
     :stream true
     :callback (fn [res] (table.insert chunks2 res))})
  (wait-for (fn []
              (local st (srv:status))
              (and (= st.sse-reconnect-count 1)
                   (string.find (stream-body chunks2) "event: endpoint" 1 true)))
            5000)
  (local reconnect-status (srv:status))
  (assert (= reconnect-status.sse-connect-count 2) "reconnect should count second stream")
  (assert (= reconnect-status.list-changed-count 2) "reconnect should resend list_changed")

  (tools:register {:name "space_echo"
                   :description "Echo"
                   :inputSchema {:type "object" :properties {:msg {:type "string"}}}
                   :run (fn [args] (or args.msg ""))})
  (wait-for (fn []
              (local st (srv:status))
              (= st.list-changed-count 3))
            5000)
  (srv:stop))

(table.insert tests {:name "mcp-http: SSE reconnect resends list_changed and updates status"
                     :fn test-sse-reconnect-status})

(fn test-stop-removes-change-listener []
  (local tools (ToolRegistry {:namespace-prefix "space_"}))
  (tools:register {:name "space_ping"
                   :description "Ping"
                   :inputSchema {:type "object" :properties {}}
                   :run (fn [] "pong")})
  (local srv (MCPHTTPServer {:http-server (http-server-mod.HttpServer)
                             :tools tools
                             :force-sse true}))
  (local port (srv:start "127.0.0.1" 0))
  (var chunks [])

  (http.request
    {:method "GET"
     :url (.. "http://127.0.0.1:" port "/mcp")
     :headers {:Accept "text/event-stream"}
     :stream true
     :callback (fn [res] (table.insert chunks res))})
  (wait-for (fn []
              (local st (srv:status))
              (and st.sse-connected
                   (string.find (stream-body chunks) "event: endpoint" 1 true)))
            5000)
  (local connected-status (srv:status))
  (assert (= connected-status.list-changed-count 1)
          "connected stream should receive initial list_changed")

  (srv:stop)
  (local stopped-tool-status (tools:status))
  (assert (= stopped-tool-status.listener-count 0)
          "server stop should remove registry change listener")
  (tools:register {:name "space_echo"
                   :description "Echo"
                   :inputSchema {:type "object" :properties {:msg {:type "string"}}}
                   :run (fn [args] (or args.msg ""))})
  (local stopped-status (srv:status))
  (assert (= stopped-status.list-changed-count 1)
          "registry changes after stop should not publish list_changed"))

(table.insert tests {:name "mcp-http: stop removes change listener before tool mutations"
                     :fn test-stop-removes-change-listener})

(fn test-loopback-only []
  (local tools (ToolRegistry))
  (local srv (MCPHTTPServer {:http-server (http-server-mod.HttpServer)
                             :tools tools}))
  (local (ok err) (pcall srv.start srv "0.0.0.0" 0))
  (assert (not ok) "server should reject non-loopback bind by default")
  (assert (string.find (tostring err) "non-loopback" 1 true)
          "error should mention non-loopback")

  (local srv2 (MCPHTTPServer {:http-server (http-server-mod.HttpServer)
                              :tools tools
                              :allow-non-loopback true}))
  (local port (srv2:start "0.0.0.0" 0))
  (assert (> port 0) "allow-non-loopback should permit explicit bind")
  (srv2:stop))

(table.insert tests {:name "mcp-http: loopback binding enforced by default"
                     :fn test-loopback-only})

(fn main []
  (local runner (require :tests/runner))
  (runner.run-tests {:name "mcp-http" :tests tests}))

{:tests tests
 :main main}
