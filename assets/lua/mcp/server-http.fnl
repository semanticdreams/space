;; MCP HTTP+SSE transport server (2024-11-05 protocol).
;; GET /mcp opens SSE stream, pushes endpoint event, stays alive for session.
;; POST /mcp processes JSON-RPC, pushes response via active SSE stream, returns 202.
;; Server->client notifications (list_changed) flow through the same SSE stream.

(local MCPHTTPHandler (require :mcp/handler))
(local Uuid (require :uuid))
(local json (require :json))
(local logging (require :logging))

(local log (logging.get "mcp"))

(fn push-sse [stream body]
  (stream:send (.. "event: message\ndata: " body "\n\n")))

(fn push-list-changed [stream]
  (stream:send "event: message\ndata: {\"jsonrpc\":\"2.0\",\"method\":\"notifications/tools/list_changed\"}\n\n"))

(fn loopback-host? [hostname]
  (or (= hostname "127.0.0.1")
      (= hostname "localhost")
      (= hostname "::1")))

(fn request-method [req]
  (local (ok parsed) (pcall json.loads (or req.body "")))
  (if (and ok (= (type parsed) "table"))
      parsed.method
      nil))

(fn MCPHTTPServer [opts]
  (local http-server (or opts.http-server (error "MCPHTTPServer requires :http-server")))
  (local tools (or opts.tools (error "MCPHTTPServer requires :tools")))
  (local handler (MCPHTTPHandler {:tools tools}))
  (var server-port nil)
  (var running false)
  (var active-stream nil)
  (var change-token nil)
  (local force-sse (if (= opts.force-sse nil) false opts.force-sse))
  (local status {:running false
                 :hostname nil
                 :port nil
                 :force-sse force-sse
                 :sse-connected false
                 :active-session-id nil
                 :sse-connect-count 0
                 :sse-reconnect-count 0
                 :post-count 0
                 :initialize-count 0
                 :tools-list-count 0
                 :tools-call-count 0
                 :list-changed-count 0
                 :last-list-changed-at nil
                 :last-method nil
                 :last-error nil})

  (fn mark-list-changed []
    (tset status :list-changed-count (+ status.list-changed-count 1))
    (tset status :last-list-changed-at (os.time)))

  (fn send-list-changed []
    (when active-stream
      (mark-list-changed)
      (push-list-changed active-stream)
      (log.info {:event "list_changed" :count status.list-changed-count}
                "sent MCP tools/list_changed")))

  (fn clear-active-stream [stream session-id]
    (when (= active-stream stream)
      (set active-stream nil)
      (tset status :sse-connected false)
      (tset status :active-session-id nil)
      (when change-token
        (tools:remove-on-change change-token)
        (set change-token nil))
      (log.info {:event "sse_disconnected" :session-id session-id}
                "MCP SSE disconnected")))

  ;; Routes must be registered BEFORE listen for httplib compatibility.
  ;; POST must be registered BEFORE SSE (httplib method-order constraint).

  (http-server:route "POST" "/mcp"
    (fn [req]
      (if (and force-sse (not active-stream))
          (do
            (tset status :last-error "Use SSE transport")
            (log.warn {:event "force_sse_reject"} "rejecting Streamable HTTP probe")
            {:status 500 :body "Use SSE transport" :headers {:content-type "text/plain"}})
          (do
            (tset status :post-count (+ status.post-count 1))
            (local method (request-method req))
            (tset status :last-method method)
            (if (= method "initialize")
                (tset status :initialize-count (+ status.initialize-count 1))
                (= method "tools/list")
                (tset status :tools-list-count (+ status.tools-list-count 1))
                (= method "tools/call")
                (tset status :tools-call-count (+ status.tools-call-count 1)))
            (log.info {:event "post" :method (or method "unknown") :sse (not= active-stream nil)}
                      "handling MCP POST")
            (local result (handler.handle-post req))
            (if (>= (or result.status 200) 400)
                (tset status :last-error result.body)
                (tset status :last-error nil))
            (if active-stream
                (do
                  (when (and result.body (> (# result.body) 0))
                    (push-sse active-stream result.body))
                  {:status 202 :body "" :headers result.headers})
                result)))))

  (when force-sse
    (http-server:route_sse "/mcp"
      (fn [req]
        (local stream req.stream)
        (local reconnecting (not= active-stream nil))
        (when change-token
          (tools:remove-on-change change-token)
          (set change-token nil))
        (when active-stream
          (pcall active-stream.close active-stream))
        (local session-id (Uuid.v4))
        (stream:on-close
          (fn []
            (clear-active-stream stream session-id)))
        (set active-stream stream)
        (tset status :sse-connected true)
        (tset status :active-session-id session-id)
        (tset status :sse-connect-count (+ status.sse-connect-count 1))
        (when reconnecting
          (tset status :sse-reconnect-count (+ status.sse-reconnect-count 1)))
        (log.info {:event "sse_connected"
                   :session-id session-id
                   :reconnect reconnecting}
                  "MCP SSE connected")
        (stream:send (.. "event: endpoint\ndata: /mcp?sessionId=" session-id "\n\n"))
        (send-list-changed)
        (set change-token
          (tools:add-on-change
            (fn []
              (send-list-changed)))))))

  (fn start [_self hostname port]
    (local bind-host (or hostname "127.0.0.1"))
    (when (and (not opts.allow-non-loopback) (not (loopback-host? bind-host)))
      (error (.. "MCPHTTPServer refuses non-loopback host by default: " bind-host)))
    (set server-port (http-server:listen bind-host (or port 0)))
    (set running true)
    (tset status :running true)
    (tset status :hostname bind-host)
    (tset status :port server-port)
    (log.info {:event "started" :host bind-host :port server-port :force-sse force-sse}
              "MCP HTTP server started")
    (when opts.on-started
      (opts.on-started server-port))
    server-port)

  (fn stop [_self]
    (when running
      (set running false)
      (when change-token
        (tools:remove-on-change change-token)
        (set change-token nil))
      (when active-stream
        (pcall active-stream.close active-stream)
        (set active-stream nil))
      (tset status :running false)
      (tset status :sse-connected false)
      (tset status :active-session-id nil)
      (log.info {:event "stopped"} "MCP HTTP server stopped")
      (http-server:stop)))

  (fn get-port [_self]
    server-port)

  (fn get-status [_self]
    (local tool-status (if tools.status (tools:status) {}))
    {:running status.running
     :hostname status.hostname
     :port status.port
     :force-sse status.force-sse
     :sse-connected status.sse-connected
     :active-session-id status.active-session-id
     :sse-connect-count status.sse-connect-count
     :sse-reconnect-count status.sse-reconnect-count
     :post-count status.post-count
     :initialize-count status.initialize-count
     :tools-list-count status.tools-list-count
     :tools-call-count status.tools-call-count
     :list-changed-count status.list-changed-count
     :last-list-changed-at status.last-list-changed-at
     :last-method status.last-method
     :last-error status.last-error
     :tool-count tool-status.tool-count
     :tool-change-count tool-status.change-count
     :tool-namespace-prefix tool-status.namespace-prefix})

  {:start start
   :stop stop
   :http-server http-server
   :port get-port
   :status get-status})
