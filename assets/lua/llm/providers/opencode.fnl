(local Client (require :llm/providers/opencode/client))
(local Server (require :llm/providers/opencode/server))
(local Session (require :llm/providers/opencode/session))
(local Events (require :llm/providers/opencode/events))
(local Config (require :llm/providers/opencode/config))
(local Project (require :llm/providers/opencode/project))
(local File (require :llm/providers/opencode/file))
(local Find (require :llm/providers/opencode/find))
(local Global (require :llm/providers/opencode/global))

(fn build-namespaces [client]
  {:client client
   :session (Session client)
   :events (Events client)
   :config (Config client)
   :project (Project client)
   :file (File client)
   :find (Find client)
   :global (Global client)})

(fn Opencode [opts]
  "Create an OpenCode SDK instance that starts a server and builds a client.
  opts: {:hostname :port :opencode-path :timeout-ms :config :env :clear-env :cwd
         :base-url (for client-only, omit server)}
  Returns {:client :server :session :events :config :project :file :find :global :close}."
  (local options {})
  (each [k v (pairs (or opts {}))]
    (tset options k v))

  (var server nil)
  (if options.base-url
      (assert (not (or options.hostname options.port options.opencode-path
                       options.config options.env options.clear-env options.cwd))
              "Opencode: base-url and server options (hostname, port, opencode-path, config, env, clear-env, cwd) are mutually exclusive")
      (do
        (set server (Server options))
        (server.start)
        (set options.base-url (server.url))))

  (local namespaces (build-namespaces (Client options)))

  {:client namespaces.client
   :server server
   :session namespaces.session
   :events namespaces.events
   :config namespaces.config
   :project namespaces.project
   :file namespaces.file
   :find namespaces.find
   :global namespaces.global
   :close (fn []
            (when server
              (server.stop)))})

(fn OpencodeClient [opts]
  "Create a client-only OpenCode SDK instance connecting to an existing server.
  opts: {:base-url (required) :timeout-ms :user-agent}
  Returns {:client :session :events :config :project :file :find :global :close}."
  (local options {})
  (each [k v (pairs (or opts {}))]
    (tset options k v))
  (assert options.base-url "OpencodeClient requires base-url")

  (local namespaces (build-namespaces (Client options)))
  {:client namespaces.client
   :session namespaces.session
   :events namespaces.events
   :config namespaces.config
   :project namespaces.project
   :file namespaces.file
   :find namespaces.find
   :global namespaces.global
   :close (fn [] nil)})

{:Opencode Opencode
 :OpencodeClient OpencodeClient}
