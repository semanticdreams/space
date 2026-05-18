;; Agent tool surface — preset-backed tool definitions for MCP and client-side providers.
;; Single source of truth for active tools, derived from PresetManager.

(fn AgentToolSurface [opts]
  (local presets (or opts.presets (error "AgentToolSurface requires :presets")))
  (local mcp-tools (or opts.mcp-tools (error "AgentToolSurface requires :mcp-tools")))
  (local approvals (or opts.approvals (error "AgentToolSurface requires :approvals")))
  (local risk-ranks {:normal 0
                     :filesystem-read 1
                     :filesystem-write 2
                     :destructive 3
                     :shell 4})

  (fn stricter-risk [left right]
    (if (not left)
        right
        (not right)
        left
        (> (or (. risk-ranks right) -1) (or (. risk-ranks left) -1))
        right
        left))

  (fn preset-tool-ids [active-preset]
    (if active-preset.tool-ids
        active-preset.tool-ids
        (and presets.registry presets.registry.get)
        (do
          (local preset (presets.registry:get active-preset.name))
          (when (not preset)
            (error (.. "active preset not found in registry: " active-preset.name)))
          preset.tool-ids)
        (error (.. "cannot resolve tool ids for active preset: " active-preset.name))))

  (fn active-tool-risks []
    (local risks {})
    (each [_ active-preset (ipairs (presets:get-active-presets))]
      (local risk (or active-preset.risk
                      (error (.. "active preset missing risk: " active-preset.name))))
      (when (not (. risk-ranks risk))
        (error (.. "unknown preset risk: " (tostring risk))))
      (each [_ tool-id (ipairs (preset-tool-ids active-preset))]
        (tset risks tool-id (stricter-risk (. risks tool-id) risk))))
    risks)

  (fn tool-risk [risk-map def]
    (local source (or def.managed-source
                      (error (.. "MCP tool def missing managed-source: " (tostring def.name)))))
    (local risk (. risk-map source))
    (when (not risk)
      (error (.. "no active preset risk found for tool source: " source)))
    risk)

  (fn risk-approved? [def risk]
    (local state (approvals:check-risk risk {:tool def.name :source def.managed-source}))
    (if (= state :approved)
        true
        (or (= state :denied) (= state :needs-approval))
        false
        (error (.. "unknown approval state for tool '" def.name "': " (tostring state)))))

  (fn approved-tool-defs []
    (local risk-map (active-tool-risks))
    (local result [])
    (each [_ def (ipairs (presets:get-tool-defs))]
      (local risk (tool-risk risk-map def))
      (when (risk-approved? def risk)
        (table.insert result def)))
    result)

  (fn active-presets [self]
    (presets:get-active-presets))

  (fn prompt-fragments [self]
    (presets:get-prompt-fragments))

  (fn mcp-tool-defs [self]
    (approved-tool-defs))

  (fn openai-tools [self]
    "Convert MCP tool defs to OpenAI function tool definitions."
    (local defs (self:mcp-tool-defs))
    (local result [])
    (each [_ def (ipairs defs)]
      (when (not def.inputSchema)
        (error (.. "MCP tool def missing inputSchema: " def.name)))
      (table.insert result
        {:type "function"
         :name def.name
         :description def.description
         :parameters def.inputSchema}))
    result)

  (fn call [self name args]
    "Execute a tool by its MCP name through the MCP tool registry."
    (local risk-map (active-tool-risks))
    (var matched nil)
    (var matched-risk nil)
    (each [_ def (ipairs (presets:get-tool-defs))]
      (when (= def.name name)
        (set matched def)
        (set matched-risk (tool-risk risk-map def))))
    (when (not matched)
      (error (.. "tool is not active for agent surface: " name)))
    (when (not (risk-approved? matched matched-risk))
      (error (.. "tool requires approval before execution: " name " (" matched-risk ")")))
    (mcp-tools:call name (or args {})))

  (fn require-risk [self risk reason callbacks]
    (assert (= (type callbacks) "table") "require-risk requires callbacks table")
    (assert (= (type callbacks.on-approved) "function") "require-risk requires on-approved callback")
    (assert (= (type callbacks.on-denied) "function") "require-risk requires on-denied callback")
    (approvals:request-risk risk reason callbacks))

  {:active-presets active-presets
   :prompt-fragments prompt-fragments
   :mcp-tool-defs mcp-tool-defs
   :openai-tools openai-tools
   :call call
   :require-risk require-risk})

{:AgentToolSurface AgentToolSurface}
