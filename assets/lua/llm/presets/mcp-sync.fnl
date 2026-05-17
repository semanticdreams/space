;; PresetMcpSync — synchronizes PresetManager resolved tools into an MCP ToolRegistry.
;; Tracks managed tools and only unregisters tools it owns. Never touches unrelated tools.

(fn PresetMcpSync [opts]
  (local manager opts.manager)
  (local tool-registry opts.tool-registry)
  (local owner opts.owner)
  (assert manager "PresetMcpSync requires :manager")
  (assert tool-registry "PresetMcpSync requires :tool-registry")
  (assert (= (type tool-registry.register) "function") "tool-registry must have :register")
  (assert (= (type tool-registry.unregister) "function") "tool-registry must have :unregister")
  (assert (= (type tool-registry.list) "function") "tool-registry must have :list")
  (assert (= (type tool-registry.add-on-change) "function") "tool-registry must have :add-on-change")
  (assert (= (type tool-registry.remove-on-change) "function") "tool-registry must have :remove-on-change")
  (local self-owner (or owner "agent-presets"))

  (var manager-change-token nil)
  (var started? false)
  (var managed-tools {})  ;; mcp-name -> {:source tool-id :def resolved-def}

  (fn sync [self]
    (local new-defs (manager:get-tool-defs))
    (local new-managed {})

    ;; Validate no name collisions with unmanaged tools
    (local existing-tools (tool-registry:list))
    (local existing-names {})
    (each [_ t (ipairs existing-tools)]
      (tset existing-names t.name true))

    (each [_ def (ipairs new-defs)]
      (when (and (. existing-names def.name)
                 (not (. managed-tools def.name)))
        (error (.. "MCP tool name collision: '" def.name "' already exists and is not managed by " self-owner))))

    ;; Register new/changed tools
    (each [_ def (ipairs new-defs)]
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

    ;; Unregister removed tools
    (each [name entry (pairs managed-tools)]
      (when (not (. new-managed name))
        (tool-registry:unregister name)))

    (set managed-tools new-managed)
    self)

  (fn start [self]
    (when started?
      (error "PresetMcpSync already started"))
    (set started? true)
    (set manager-change-token
         (manager:add-on-change (fn [] (self:sync))))
    (local (ok err) (pcall (fn [] (self:sync))))
    (when (not ok)
      (when manager-change-token
        (manager:remove-on-change manager-change-token)
        (set manager-change-token nil))
      (set managed-tools {})
      (set started? false)
      (error err))
    self)

  (fn stop [self]
    (when manager-change-token
      (manager:remove-on-change manager-change-token)
      (set manager-change-token nil))
    (each [name _entry (pairs managed-tools)]
      (tool-registry:unregister name))
    (set managed-tools {})
    (set started? false)
    self)

  (fn status [self]
    (var count 0)
    (each [_ _v (pairs managed-tools)]
      (set count (+ count 1)))
    {:started? started?
     :owner self-owner
     :managed-tool-count count
     :managed-names (icollect [name _v (pairs managed-tools)] name)})

  {:start start
   :sync sync
   :stop stop
   :status status})

{:PresetMcpSync PresetMcpSync}
