;; ToolAdapterRegistry — maps stable capability IDs to runtime MCP tool definitions.
;; Adapters are registered once. resolve() creates full MCP defs (including :run closure) at sync time.

(fn validate-adapter [adapter]
  (assert (= (type adapter) "table") "adapter must be a table")
  (assert (= (type adapter.id) "string") "adapter must have a string id")
  (assert (> (# adapter.id) 0) "adapter id must not be empty")
  (assert (= (type adapter.mcp-name) "string") "adapter must have a string mcp-name")
  (assert (= (string.sub adapter.mcp-name 1 6) "space_")
          (.. "adapter '" adapter.id "' mcp-name must start with 'space_'"))
  (assert (= (type adapter.description) "string") "adapter must have a string description")
  (assert (= (type adapter.inputSchema) "table") "adapter must have an inputSchema table")
  (assert (= (type adapter.make-run) "function") "adapter must have a make-run function")
  true)

(fn ToolAdapterRegistry [opts]
  (local options (or opts {}))
  (var adapters {})
  (var listeners [])

  (fn fire-change []
    (each [_ cb (ipairs listeners)]
      (cb)))

  (fn register [self adapter]
    (validate-adapter adapter)
    (when (. adapters adapter.id)
      (error (.. "duplicate adapter id: " adapter.id)))
    (tset adapters adapter.id adapter)
    (fire-change)
    self)

  (fn get [self tool-id]
    (. adapters tool-id))

  (fn resolve [self tool-id app]
    (local adapter (. adapters tool-id))
    (when (not adapter)
      (error (.. "unknown tool adapter: " tool-id)))
    (local resolved {:name adapter.mcp-name
                     :description adapter.description
                     :inputSchema adapter.inputSchema
                     :run (adapter.make-run app)
                     :managed-owner "agent-presets"
                     :managed-source tool-id})
    resolved)

  (fn add-on-change [self cb]
    (table.insert listeners cb)
    cb)

  (fn remove-on-change [self cb]
    (for [i (# listeners) 1 -1]
      (when (= (. listeners i) cb)
        (table.remove listeners i))))

  {:register register
   :get get
   :resolve resolve
   :add-on-change add-on-change
   :remove-on-change remove-on-change})

{:ToolAdapterRegistry ToolAdapterRegistry}
