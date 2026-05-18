;; OpenCode MCP bridge — owns the loopback MCP HTTP server and isolated OpenCode config.

(local fs (require :fs))
(local JsonUtils (require :json-utils))

(fn ensure-dir! [path]
  (when (not (fs.exists path))
    (fs.create-dirs path)))

(fn remote-url [host port]
  (.. "http://" host ":" (tostring port) "/mcp"))

(fn config-path [config-root]
  (fs.join-path (fs.join-path config-root "opencode") "opencode.json"))

(fn write-opencode-config! [config-root url]
  (local opencode-dir (fs.join-path config-root "opencode"))
  (ensure-dir! opencode-dir)
  (JsonUtils.write-json!
    (config-path config-root)
    {:mcp {:space {:type "remote"
                   :url url
                   :enabled true}}}))

(fn AgentOpencodeMcpBridge [opts]
  (local tools (or opts.tools (error "AgentOpencodeMcpBridge requires :tools")))
  (local data-dir (or opts.data-dir (error "AgentOpencodeMcpBridge requires :data-dir")))
  (local host (or opts.host "127.0.0.1"))
  (local http-server-factory (or opts.http-server-factory
                                 (fn []
                                   (local http-server-mod (require :http_server))
                                   (http-server-mod.HttpServer))))
  (local mcp-server-factory (or opts.mcp-server-factory
                                (fn [http-server]
                                  (local MCPHTTPServer (require :mcp/server-http))
                                  (MCPHTTPServer {:http-server http-server
                                                  :tools tools
                                                  :force-sse true}))))

  (var server nil)
  (var config-root nil)
  (var port nil)
  (var url nil)
  (var started? false)

  (fn start [self]
    (when started?
      (error "AgentOpencodeMcpBridge already started"))
    (ensure-dir! data-dir)
    (set config-root (fs.join-path data-dir "opencode-mcp-config"))
    (ensure-dir! config-root)
    (set server (mcp-server-factory (http-server-factory)))
    (local (ok result) (pcall (fn []
                                (set port (server:start host 0))
                                (when (not (> port 0))
                                  (error (.. "AgentOpencodeMcpBridge got invalid MCP port: "
                                             (tostring port))))
                                (set url (remote-url host port))
                                (write-opencode-config! config-root url))))
    (when (not ok)
      (when server
        (pcall (fn [] (server:stop))))
      (set server nil)
      (set port nil)
      (set url nil)
      (set config-root nil)
      (error result))
    (set started? true)
    self)

  (fn stop [self]
    (when server
      (server:stop))
    (set server nil)
    (set port nil)
    (set url nil)
    (set started? false)
    self)

  (fn opencode-env [self]
    (when (not started?)
      (error "AgentOpencodeMcpBridge must be started before building OpenCode env"))
    {:XDG_CONFIG_HOME config-root})

  (fn status [self]
    {:started? started?
     :host host
     :port port
     :url url
     :config-root config-root
     :config-path (and config-root (config-path config-root))})

  {:start start
   :stop stop
   :opencode-env opencode-env
   :status status})

{:AgentOpencodeMcpBridge AgentOpencodeMcpBridge}
