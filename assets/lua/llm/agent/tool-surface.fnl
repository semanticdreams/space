;; Agent tool surface — preset-backed tool definitions for MCP and client-side providers.
;; Single source of truth for active tools, derived from PresetManager.

(local json (require :json))
(local ApprovalFingerprint (require :llm/agent/approval-fingerprint))

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

  (fn active-tool-defs []
    (local risk-map (active-tool-risks))
    (local result [])
    (each [_ def (ipairs (presets:get-tool-defs))]
      (local risk (tool-risk risk-map def))
      (table.insert result {:def def :risk risk}))
    result)

  (fn active-tool-entry [name]
    (var matched nil)
    (each [_ entry (ipairs (active-tool-defs))]
      (when (= entry.def.name name)
        (set matched entry)))
    matched)

  (fn copy-tool-def [def]
    (local copy {})
    (each [k v (pairs def)]
      (tset copy k v))
    copy)

  (fn approval-reason [name risk]
    (.. name " requested " (tostring risk) " access"))

  (fn approval-context [def args]
    (local fingerprint (ApprovalFingerprint.fingerprint (or args {})))
    {:tool def.name
     :source def.managed-source
     :args_hash fingerprint.hash
     :args_canonical fingerprint.canonical
     :args_preview fingerprint.preview
     :grant-on-approve true})

  (fn matching-request [risk context]
    (var found nil)
    (each [_ request (ipairs (approvals:list-pending))]
      (local request-context (or request.context {}))
      (when (and (not found)
                 (= request.risk risk)
                 (= request-context.tool context.tool)
                 (= request-context.source context.source)
                 (= request-context.args_canonical context.args_canonical)
                 (= request-context.args_hash context.args_hash))
        (set found request)))
    found)

  (fn approval-required-payload [request risk reason context]
    {:status "approval_required"
     :request_id (and request request.id)
     :tool context.tool
     :source context.source
     :risk risk
     :reason reason
     :args_hash context.args_hash
     :args_preview context.args_preview})

  (fn run-with-approval [self def risk args]
    (var approved? false)
    (var denied? false)
    (local tool-args (or args {}))
    (local context (approval-context def tool-args))
    (local reason (approval-reason def.name risk))
    (local result
      (approvals:request-risk risk reason
        {:on-approved (fn [_approval] (set approved? true))
         :on-denied (fn [_approval] (set denied? true))}
        context))
    (if approved?
        (def.run (or args {}))
        denied?
        (error (.. "tool denied by approval policy: " def.name " (" risk ")"))
        (= result false)
        (do
          (local request (matching-request risk context))
          (error (.. "approval_required "
                     (json.dumps (approval-required-payload request risk reason context)))))
        (error (.. "tool approval did not resolve execution state: " def.name))))

  (fn run-with-approval-async [self def risk args on-result cancelled?]
    (local tool-args (or args {}))
    (local context (approval-context def tool-args))
    (local reason (approval-reason def.name risk))
    (local callbacks
      {:on-approved (fn [_approval]
                      (if (and cancelled? (cancelled?))
                          (on-result {:type :error :message (.. "tool cancelled: " def.name)})
                          (do
                            (local (ok result) (pcall #(def.run tool-args)))
                            (if ok
                                (on-result {:type :success :value result})
                                (on-result {:type :error :message (.. "tool execution failed: " (tostring result))})))))
       :on-denied (fn [_approval]
                    (on-result {:type :error
                                :message (.. "tool denied by approval policy: " def.name " (" risk ")")}))})
    (local result (approvals:request-risk risk reason callbacks context))
    (if (= result false)
        {:pending true}
        :completed))

  (fn request-tool-approval [self args]
    (local request-args (or args {}))
    (local tool-name (assert request-args.tool
                             "space_agent_request_tool_approval requires :tool"))
    (assert (= (type tool-name) "string")
            "space_agent_request_tool_approval :tool must be a string")
    (local target (active-tool-entry tool-name))
    (assert target (.. "space_agent_request_tool_approval target tool is not active: " tool-name))
    (local tool-args (or request-args.arguments {}))
    (assert (= (type tool-args) "table")
            "space_agent_request_tool_approval :arguments must be an object")
    (local reason (or request-args.reason (approval-reason target.def.name target.risk)))
    (assert (= (type reason) "string")
            "space_agent_request_tool_approval :reason must be a string")
    (local context (approval-context target.def tool-args))
    (var approved? false)
    (var denied? false)
    (local result
      (approvals:request-risk target.risk reason
        {:on-approved (fn [_approval] (set approved? true))
         :on-denied (fn [_approval] (set denied? true))}
        context))
    (if approved?
        (json.dumps {:status "approved"
                     :tool context.tool
                     :risk target.risk
                     :args_hash context.args_hash})
        denied?
        (json.dumps {:status "denied"
                     :tool context.tool
                     :risk target.risk
                     :args_hash context.args_hash})
        (= result false)
        (do
          (local request (matching-request target.risk context))
          (json.dumps (approval-required-payload request target.risk reason context)))
        (error "space_agent_request_tool_approval did not resolve approval state")))

  (fn call-async [self name args on-result cancelled?]
    (if (= name "space_agent_request_tool_approval")
        (do
          (local (ok result) (pcall #(request-tool-approval self args)))
          (if ok
              (on-result {:type :success :value result})
              (on-result {:type :error :message (.. "approval request failed: " (tostring result))}))
          :completed)
        (do
          (local (ok result)
            (pcall (fn []
                     (local matched (active-tool-entry name))
                     (when (not matched)
                       (error (.. "tool is not active: " name)))
                     (run-with-approval-async self matched.def matched.risk args on-result cancelled?))))
          (if ok result
              (do
                (on-result {:type :error :message (tostring result)})
                :completed)))))

  (fn approval-tool-def [self]
    {:name "space_agent_request_tool_approval"
     :description "Request user approval for one exact Space tool call before running it."
     :managed-source "agent.request-tool-approval"
     :managed-owner "agent-tool-surface"
     :inputSchema {:type "object"
                   :properties {:tool {:type "string"
                                       :description "Exact Space tool name to approve"}
                                :arguments {:type "object"
                                            :description "Exact arguments that will be passed to the target tool"}
                                :reason {:type "string"
                                         :description "Why this tool call is needed"}}
                   :required ["tool" "arguments"]}
     :risk :normal
     :run (fn [args] (self:request-tool-approval args))
     :run-async (fn [args on-result cancelled?] (self:call-async "space_agent_request_tool_approval" args on-result cancelled?))})

  (fn active-presets [self]
    (presets:get-active-presets))

  (fn prompt-fragments [self]
    (presets:get-prompt-fragments))

  (fn mcp-tool-defs [self]
    (local result [(approval-tool-def self)])
    (each [_ entry (ipairs (active-tool-defs))]
      (local raw-def entry.def)
      (local wrapped (copy-tool-def raw-def))
      (set wrapped.risk entry.risk)
      (set wrapped.run
           (fn [args]
             (self:call raw-def.name args)))
      (set wrapped.run-async
           (fn [args on-result cancelled?]
             (self:call-async raw-def.name args on-result cancelled?)))
      (table.insert result wrapped))
    result)

  (fn openai-tools [self]
    "Convert MCP tool defs to OpenAI function tool definitions."
    (local defs (mcp-tool-defs self))
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
    (if (= name "space_agent_request_tool_approval")
        (request-tool-approval self args)
        (do
          (local matched (active-tool-entry name))
          (when (not matched)
            (error (.. "tool is not active for agent surface: " name)))
          (run-with-approval self matched.def matched.risk args))))

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
   :call-async call-async
   :request-tool-approval request-tool-approval
   :require-risk require-risk})

{:AgentToolSurface AgentToolSurface}
