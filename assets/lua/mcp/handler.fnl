;; MCP Streamable HTTP handler.
;; Manages sessions and routes JSON-RPC to the tool registry.

(local protocol (require :mcp/protocol))
(local Uuid (require :uuid))

(fn uuid4 []
  (Uuid.v4))

(fn prune-sessions! [sessions ttl-seconds now]
  (when (> ttl-seconds 0)
    (each [session-id session (pairs sessions)]
      (when (> (- now (or session.last-seen session.created 0)) ttl-seconds)
        (tset sessions session-id nil)))))

(fn ok-json [body extra-headers]
  "Return an HTTP 200 JSON response."
  (local headers (or extra-headers {}))
  (tset headers :content-type "application/json")
  {:status 200 :body body :headers headers})

(fn accepted [extra-headers]
  "Return an HTTP 202 Accepted response."
  {:status 202 :body "" :headers (or extra-headers {})})

(fn bad-request [json-body]
  "Return an HTTP 400 JSON error."
  {:status 400 :body json-body :headers {:content-type "application/json"}})

(fn extract-query-session-id [req]
  (or (and req.query_params req.query_params.sessionId)
      (and req.query_params req.query_params.session_id)))

(fn handle-initialize [msg tool-registry sessions req]
  "Process an initialize request, creating a new session."
  (local session-id (or (extract-query-session-id req) (uuid4)))
  (local client-version (or (and msg.params msg.params.protocolVersion) "2025-03-26"))
  (local now (os.time))
  (tset sessions session-id {:created now :last-seen now})
  (ok-json
    (protocol.format-message
      (protocol.response msg.id
      {:protocolVersion client-version
       :capabilities {:tools {:listChanged true}}
       :serverInfo {:name "space-mcp" :version "1.0.0"}}))
    {:mcp-session-id session-id}))

(fn handle-tools-list [msg tool-registry session-id]
  "Respond with the list of available tools."
  (ok-json
    (protocol.format-message
      (protocol.response msg.id {:tools (tool-registry:list)}))
    {:mcp-session-id session-id}))

(fn call-tool-response [msg tool-registry session-id tool-name params]
  (local (ok result-or-err) (pcall tool-registry.call tool-registry tool-name
                                   (or params.arguments {})))
  (if ok
      (ok-json
        (protocol.format-message (protocol.response msg.id result-or-err))
        {:mcp-session-id session-id})
      (ok-json
        (protocol.format-message
          (protocol.error-response msg.id protocol.error-codes.INVALID_PARAMS
            (tostring result-or-err)))
        {:mcp-session-id session-id})))

(fn handle-tools-call [msg tool-registry session-id]
  "Execute a tool call and return the result."
  (local params (or msg.params {}))
  (local tool-name params.name)
  (if (not tool-name)
      (ok-json
        (protocol.format-message
          (protocol.error-response msg.id protocol.error-codes.INVALID_PARAMS
            "Missing required parameter: name"))
        {:mcp-session-id session-id})
      (call-tool-response msg tool-registry session-id tool-name params)))

(fn extract-session-id [req]
  "Extract Mcp-Session-Id from request headers (case-insensitive)."
  (var result nil)
  (when req.headers
    (each [k v (pairs req.headers)]
      (when (and (= (type k) "string") (= (string.lower k) "mcp-session-id"))
        (set result v))))
  (or result (extract-query-session-id req)))

(fn handle-authenticated-request [msg tool-registry sessions req]
  "Route a post-initialize request that has a valid session."
  (local session-id (extract-session-id req))
  (local session (and session-id (. sessions session-id)))
  (if (not session-id)
      (bad-request
        (protocol.format-message
          (protocol.error-response msg.id -32001 "Missing Mcp-Session-Id header")))
      (not session)
      (bad-request
        (protocol.format-message
          (protocol.error-response msg.id -32001 "Session not found")))
      (= msg.method "tools/list")
      (do
        (tset session :last-seen (os.time))
        (handle-tools-list msg tool-registry session-id))
      (= msg.method "tools/call")
      (do
        (tset session :last-seen (os.time))
        (handle-tools-call msg tool-registry session-id))
      (protocol.is-notification msg)
      (do
        (tset session :last-seen (os.time))
        (accepted {:mcp-session-id session-id}))
      msg.id
      (do
        (tset session :last-seen (os.time))
        (ok-json
          (protocol.format-message
            (protocol.error-response msg.id protocol.error-codes.METHOD_NOT_FOUND
              (.. "Method not found: " (tostring msg.method))))
          {:mcp-session-id session-id}))
      (do
        (tset session :last-seen (os.time))
        (accepted {:mcp-session-id session-id}))))

(fn MCPHTTPHandler [opts]
  (local tool-registry (or opts.tools (error "MCPHTTPHandler requires :tools")))
  (local session-ttl-seconds (or opts.session-ttl-seconds 3600))
  (var sessions {})

  (fn handle-post [req]
    (prune-sessions! sessions session-ttl-seconds (os.time))
    (local body (or req.body ""))
    (local (msg parse-err) (protocol.parse-message body))
    (if (not msg)
        (bad-request
          (protocol.format-message
            (protocol.error-response nil protocol.error-codes.PARSE_ERROR
              (or parse-err "Parse error"))))
        (= msg.method "initialize")
        (handle-initialize msg tool-registry sessions req)
        (handle-authenticated-request msg tool-registry sessions req)))

  (fn cleanup-session [session-id]
    (tset sessions session-id nil))

  {:handle-post handle-post
   :cleanup-session cleanup-session})
