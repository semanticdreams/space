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

(fn normalize-root [path]
  "Normalize an optional root value; nil/empty roots mean that scope is not configured."
  (if (= path nil)
      nil
      (= path "")
      nil
      (if (and (> (string.len path) 1)
               (= (string.sub path -1) "/"))
          (string.sub path 1 (- (string.len path) 1))
          path)))

(fn join-pattern [root suffix]
  (local normalized-root (normalize-root root))
  (assert normalized-root "join-pattern requires a root")
  (if (= (string.sub suffix 1 1) "/")
      (.. normalized-root suffix)
      (.. normalized-root "/" suffix)))

(fn space-owned-roots [opts data-dir]
  "Derive optional bounded roots from explicit Space-owned runtime paths."
  (local space-data-dir (normalize-root opts.space-data-dir))
  (local space-cache-dir (normalize-root opts.space-cache-dir))
  (var code-dir (normalize-root opts.code-dir))
  (when (and (= code-dir nil) space-data-dir)
    (set code-dir (normalize-root (fs.join-path space-data-dir "code"))))
  (var artifact-root (normalize-root opts.artifact-root))
  (when (and (= artifact-root nil) space-data-dir)
    (set artifact-root (normalize-root (fs.join-path space-data-dir "agent-artifacts"))))
  (local allowed [])
  (when space-data-dir
    (table.insert allowed (join-pattern space-data-dir "agent-sessions/**"))
    (table.insert allowed (join-pattern space-data-dir "agent-opencode/**"))
    (table.insert allowed (join-pattern space-data-dir "agent-approvals/**")))
  (when artifact-root
    (table.insert allowed (join-pattern artifact-root "**")))
  (when code-dir
    (table.insert allowed (join-pattern code-dir "**")))
  (when space-cache-dir
    (table.insert allowed (join-pattern space-cache-dir "log/**")))
  {:allowed-patterns allowed
   :artifact-root artifact-root})

(fn secret-deny-patterns [allowed-patterns]
  (local patterns [])
  (each [_ allowed-pattern (ipairs allowed-patterns)]
    (each [_ marker (ipairs ["auth" "token" "secret" "credential" "keyring"])]
      (local pattern (string.gsub allowed-pattern "%*%*$" (.. "*" marker "*")))
      (table.insert patterns pattern)))
  patterns)

(fn bounded-permission-map [allowed-patterns]
  (local permissions {"*" "deny"})
  (each [_ pattern (ipairs allowed-patterns)]
    (tset permissions pattern "allow"))
  (each [_ pattern (ipairs (secret-deny-patterns allowed-patterns))]
    (tset permissions pattern "deny"))
  permissions)

(fn native-tool-permissions [allowed-patterns]
  (local bounded (bounded-permission-map allowed-patterns))
  {:invalid "deny"
   :read bounded
   :write "deny"
   :edit "deny"
   :grep bounded
   :glob bounded
   :list bounded
   :bash "deny"
   :task "deny"
   :external_directory bounded
   :todowrite "deny"
   :webfetch "deny"
   :websearch "deny"
   :lsp "deny"
   :skill "deny"
   :question "deny"})

(fn write-opencode-config! [config-root url allowed-patterns]
  (local opencode-dir (fs.join-path config-root "opencode"))
  (ensure-dir! opencode-dir)
  (JsonUtils.write-json!
    (config-path config-root)
    {:permission (native-tool-permissions allowed-patterns)
      :mcp {:space {:type "remote"
                    :url url
                    :enabled true}}}))

(fn start-server-and-write-config! [server host config-root allowed-roots]
  (local port (server:start host 0))
  (when (not (> port 0))
    (error (.. "AgentOpencodeMcpBridge got invalid MCP port: "
               (tostring port))))
  (local url (remote-url host port))
  (write-opencode-config! config-root url allowed-roots)
  {:port port :url url})

(fn cleanup-failed-start! [server]
  (when server
    (pcall (fn [] (server:stop)))))

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
  (var allowed-roots [])
  (var artifact-root nil)

  (fn start [self]
    (when started?
      (error "AgentOpencodeMcpBridge already started"))
    (ensure-dir! data-dir)
    (local roots (space-owned-roots opts data-dir))
    (set allowed-roots roots.allowed-patterns)
    (set artifact-root roots.artifact-root)
    (when artifact-root
      (ensure-dir! artifact-root))
    (set config-root (fs.join-path data-dir "opencode-mcp-config"))
    (ensure-dir! config-root)
    (set server (mcp-server-factory (http-server-factory)))
    (local (ok result) (pcall start-server-and-write-config! server host config-root allowed-roots))
    (when (not ok)
      (cleanup-failed-start! server)
      (set server nil)
      (set port nil)
      (set url nil)
      (set config-root nil)
      (set allowed-roots [])
      (set artifact-root nil)
      (error result))
    (set port result.port)
    (set url result.url)
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

  (fn refresh-config! [self]
    (when (not started?)
      (error "AgentOpencodeMcpBridge must be started before refreshing OpenCode config"))
    (write-opencode-config! config-root url allowed-roots)
    {:config-path (config-path config-root)
     :url url
     :allowed-roots allowed-roots})

  (fn current-config-path [self]
    (and config-root (config-path config-root)))

  (fn status [self]
    {:started? started?
     :host host
      :port port
      :url url
      :config-root config-root
      :config-path (and config-root (config-path config-root))
      :artifact-root artifact-root
      :allowed-roots allowed-roots})

  {:start start
   :stop stop
   :opencode-env opencode-env
   :refresh-config! refresh-config!
   :config-path current-config-path
   :status status})

{:AgentOpencodeMcpBridge AgentOpencodeMcpBridge}
