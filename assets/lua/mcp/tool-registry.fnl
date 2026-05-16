;; Mutable tool registry for MCP.
;; Supports runtime register/unregister, emits on-change for list_changed notifications.
;; Multiple listeners via add-on-change / remove-on-change.

(fn starts-with? [value prefix]
  (= (string.sub value 1 (# prefix)) prefix))

(fn validate-tool-def [def options]
  "Validate a tool definition. Returns nil on success, error string on failure."
  (if (not (= (type def) "table"))
      "tool definition must be a table"
      (not (= (type def.name) "string"))
      "tool definition must have a string name"
      (= (# def.name) 0)
      "tool name must not be empty"
      (not (string.match def.name "^[%w_.-]+$"))
      (.. "tool '" def.name "' must contain only letters, digits, underscore, dot, or dash")
      (and options.namespace-prefix
           (not (starts-with? def.name options.namespace-prefix)))
      (.. "tool '" def.name "' must use namespace prefix '" options.namespace-prefix "'")
      (not (= (type def.description) "string"))
      (.. "tool '" def.name "' must have a string description")
      (= (# def.description) 0)
      (.. "tool '" def.name "' description must not be empty")
      (not (= (type def.inputSchema) "table"))
      (.. "tool '" def.name "' must have an inputSchema table")
      (and def.inputSchema.type (not (= def.inputSchema.type "object")))
      (.. "tool '" def.name "' inputSchema.type must be \"object\" when provided")
      (not (= (type def.run) "function"))
      (.. "tool '" def.name "' must have a run function")
      nil))

(fn ToolRegistry [opts]
  (local options (or opts {}))
  (var tools {})
  (var listeners [])
  (var change-count 0)
  (var last-change nil)

  (fn fire-change []
    (set change-count (+ change-count 1))
    (set last-change (os.time))
    (each [_ cb (ipairs listeners)]
      (cb)))

  (fn register [self def]
    (local err (validate-tool-def def options))
    (if err
        (error err))
    (tset tools def.name def)
    (fire-change)
    self)

  (fn unregister [self name]
    (tset tools name nil)
    (fire-change)
    self)

  (fn list [self]
    "Return tools in MCP tools/list response format."
    (local names [])
    (each [name _tool (pairs tools)]
      (table.insert names name))
    (table.sort names)
    (local result [])
    (each [_ name (ipairs names)]
      (local tool (. tools name))
      ;; Clone inputSchema and strip empty properties to avoid {} vs [] serialization issue
      (local schema {})
      (each [k v (pairs tool.inputSchema)]
        (if (and (= k :properties) (= (type v) "table") (= (next v) nil))
            nil ;; skip empty properties — JSON Schema allows omitting it
            (tset schema k v)))
      (table.insert result
        {:name tool.name
         :description tool.description
         :inputSchema schema}))
    result)

  (fn call [self name args]
    "Execute a tool by name. Returns result table for MCP tools/call response content."
    (local tool (. tools name))
    (if (not tool)
        (error (.. "Unknown tool: " name)))
    (local (ok result-or-err) (pcall tool.run (or args {})))
    (if ok
        {:content [{:type "text" :text (if (= (type result-or-err) "string")
                                            result-or-err
                                            (tostring result-or-err))}]
         :isError false}
        {:content [{:type "text" :text (.. "Tool execution error: " (tostring result-or-err))}]
         :isError true}))

  (fn add-on-change [self callback]
    "Add a listener that fires when tools are registered or unregistered.
    Returns a token that can be passed to remove-on-change."
    (table.insert listeners callback)
    callback)

  (fn remove-on-change [self callback]
    "Remove a previously added on-change listener."
    (for [i (# listeners) 1 -1]
      (when (= (. listeners i) callback)
        (table.remove listeners i))))

  (fn status [self]
    {:tool-count (# (self:list))
     :listener-count (# listeners)
     :change-count change-count
     :last-change last-change
     :namespace-prefix options.namespace-prefix})

  {:register register
   :unregister unregister
   :list list
   :call call
   :add-on-change add-on-change
   :remove-on-change remove-on-change
   :status status})
