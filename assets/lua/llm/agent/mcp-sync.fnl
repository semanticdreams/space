;; AgentMcpSync — synchronizes AgentToolSurface MCP defs into a ToolRegistry.
;; This is the agent-facing MCP boundary; registered defs are approval-gated by the surface.

(fn AgentMcpSync [opts]
  (local surface (or opts.surface (error "AgentMcpSync requires :surface")))
  (local tool-registry (or opts.tool-registry (error "AgentMcpSync requires :tool-registry")))
  (local change-source (or opts.change-source nil))
  (local self-owner (or opts.owner "agent-tools"))
  (assert (= (type surface.mcp-tool-defs) "function") "surface must have :mcp-tool-defs")
  (assert (= (type tool-registry.register) "function") "tool-registry must have :register")
  (assert (= (type tool-registry.unregister) "function") "tool-registry must have :unregister")
  (assert (= (type tool-registry.list) "function") "tool-registry must have :list")
  (when change-source
    (assert (= (type change-source.add-on-change) "function") "change-source must have :add-on-change")
    (assert (= (type change-source.remove-on-change) "function") "change-source must have :remove-on-change"))

  (var change-token nil)
  (var started? false)
  (var managed-tools {})  ;; mcp-name -> {:source tool-id :def resolved-def}

  (fn register-or-keep [def new-managed]
    (local existing (. managed-tools def.name))
    (if (not existing)
        (do
          (tool-registry:register def)
          (tset new-managed def.name {:source def.managed-source :def def}))
        (not (= existing.source def.managed-source))
        (do
          (tool-registry:register def)
          (tset new-managed def.name {:source def.managed-source :def def}))
        (tset new-managed def.name existing)))

  (fn sync [self]
    (local new-defs (surface:mcp-tool-defs))
    (local new-managed {})
    (local existing-names {})
    (each [_ tool (ipairs (tool-registry:list))]
      (tset existing-names tool.name true))
    (each [_ def (ipairs new-defs)]
      (when (and (. existing-names def.name)
                 (not (. managed-tools def.name)))
        (error (.. "MCP tool name collision: '" def.name "' already exists and is not managed by " self-owner))))
    (each [_ def (ipairs new-defs)]
      (register-or-keep def new-managed))
    (each [name _entry (pairs managed-tools)]
      (when (not (. new-managed name))
        (tool-registry:unregister name)))
    (set managed-tools new-managed)
    self)

  (fn start [self]
    (when started?
      (error "AgentMcpSync already started"))
    (set started? true)
    (when change-source
      (set change-token
           (change-source:add-on-change (fn [] (self:sync)))))
    (local (ok err) (pcall (fn [] (self:sync))))
    (when (not ok)
      (when (and change-source change-token)
        (change-source:remove-on-change change-token)
        (set change-token nil))
      (set managed-tools {})
      (set started? false)
      (error err))
    self)

  (fn stop [self]
    (when (and change-source change-token)
      (change-source:remove-on-change change-token)
      (set change-token nil))
    (each [name _entry (pairs managed-tools)]
      (tool-registry:unregister name))
    (set managed-tools {})
    (set started? false)
    self)

  (fn status [self]
    (var count 0)
    (each [_ _entry (pairs managed-tools)]
      (set count (+ count 1)))
    {:started? started?
     :owner self-owner
     :managed-tool-count count
     :managed-names (icollect [name _entry (pairs managed-tools)] name)})

  {:start start
   :sync sync
   :stop stop
   :status status})

{:AgentMcpSync AgentMcpSync}
