(local glm (require :glm))
(local {:GraphNode GraphNode} (require :graph/node-base))
(local LlmToolResultView (require :graph/view/views/llm-tool-result))
(local Signal (require :signal))
(local LlmStore (require :llm/store))
(local LlmRequests (require :llm/requests))
(local LlmTools (require :llm/tools/init))
(local LlmConversationUtils (require :graph/nodes/llm-conversation-utils))

(fn resolve-tool [tool-registry name]
    (or (and tool-registry tool-registry.get (tool-registry.get name))
        (and tool-registry tool-registry.tool-map (. tool-registry.tool-map name))
        (and LlmTools LlmTools.get (LlmTools.get name))))

(fn resolve-tool-definition [tool-registry tool]
    (local mapper (or (and tool-registry tool-registry.to-openai)
                      (and LlmTools LlmTools.to-openai)))
    (if mapper
        (mapper tool)
        {:type "function"
         :name tool.name
         :description tool.description
         :parameters tool.parameters
         :strict (if (not (= tool.strict nil)) tool.strict true)}))

(fn attached-tool-name [entry]
    (if (= (type entry) "table")
        (or entry.name (. entry :name))
        entry))

(fn attach-tool-definition [by-name tool-registry name]
    (local tool (resolve-tool tool-registry name))
    (when tool
        (set (. by-name tool.name) (resolve-tool-definition tool-registry tool))))

(fn collect-attached-tools [tool-registry tool-names]
    (local by-name {})
    (each [_ entry (ipairs (or tool-names []))]
        (local name (attached-tool-name entry))
        (when name
            (attach-tool-definition by-name tool-registry name)))
    (local result [])
    (each [_ tool (pairs by-name)]
        (table.insert result tool))
    (if (> (length result) 0)
        result
        nil))

(fn resolve-tool-registry [convo opts]
    (local options (or opts {}))
    (or (and options options.tool-registry)
        (and convo convo.tool-registry)
        LlmTools))

(fn sync-from-store [node record]
    (when (and node record)
        (set node.name record.name)
        (set node.output record.output)
        (set node.call-id record.call_id)
        (set (. node :last-usage) (or record.last_usage (. node :last-usage)))
        (set (. node :last-context-window) (or record.last_context_window (. node :last-context-window)))
        (set (. node :last-model) (or record.last_model (. node :last-model)))
        (set node.created-at (or record.created_at node.created-at))
        (set node.updated-at (or record.updated_at node.updated-at))
        (when node.changed
            (node.changed:emit node))))

(fn attach-store-handler [node store]
    (local handlers [])
    (when (and store store.message-changed)
        (local handler
            (store.message-changed:connect
                (fn [record]
                    (when (and record (= record.id node.llm-id))
                        (sync-from-store node record)))))
        (table.insert handlers {:signal store.message-changed
                                :handler handler}))
    handlers)

(fn LlmToolResultNode [opts]
    (local options (or opts {}))
    (local store (or options.store (LlmStore.get-default)))
    (local record (and options.llm-id (store:get-item options.llm-id)))
    (local key (or options.key (if record (.. "llm-tool-result:" record.id) "llm-tool-result")))
    (local label (or options.label (or (and record record.label) "llm tool result")))
    (local node (GraphNode {:key key
                                :label label
                                :color (glm.vec4 0.2 0.7 0.6 1)
                                :sub-color (glm.vec4 0.1 0.6 0.5 1)
                                :view LlmToolResultView}))
    (set node.kind "llm-tool-result")
    (set node.llm-id (or (and record record.id) options.llm-id))
    (set node.store store)
    (set node.name (or (and record record.name) options.name))
    (set node.output (or (and record record.output) options.output))
    (set node.call-id (or (and record record.call_id) options.call-id))
    (set (. node :last-usage) (or (and record record.last_usage) (. options :last-usage)))
    (set (. node :last-context-window) (or (and record record.last_context_window) (. options :last-context-window)))
    (set (. node :last-model) (or (and record record.last_model) (. options :last-model)))
    (set node.created-at (or (and record record.created_at) options.created-at))
    (set node.updated-at (or (and record record.updated_at) options.updated-at))
    (set node.changed (Signal))
    (set node.handlers (attach-store-handler node store))
    (when record
        (sync-from-store node record))
    (set node.run-request
         (fn [self opts]
             (local options (or opts {}))
             (local convo (LlmConversationUtils.resolve-conversation-record self options))
             (assert convo "LlmToolResultNode requires a conversation ancestor")
             (local active-store (or self.store (and convo convo.store)))
             (assert active-store "LlmToolResultNode requires an llm store")
             (local convo-id (or convo.llm-id convo.id))
             (local tool-registry (resolve-tool-registry convo options))
             (local max-tool-rounds (or options.max-tool-rounds
                                        (and convo (. convo :max-tool-rounds))))
             (local tools
                 (if (not (= options.tools nil))
                     options.tools
                     (collect-attached-tools tool-registry (and convo convo.tools))))
             (LlmRequests.run-request active-store convo-id
                                      {:tool-registry tool-registry
                                       :tools tools
                                       :tool-choice options.tool-choice
                                       :parallel-tool-calls options.parallel-tool-calls
                                       :max-tool-rounds max-tool-rounds
                                       :temperature options.temperature
                                       :reasoning-effort (. options :reasoning-effort)
                                       :text-verbosity (. options :text-verbosity)
                                       :parent-id self.llm-id
                                       :up-to-id self.llm-id
                                       :cwd (and convo convo.cwd)
                                       :on-item (and options options.on-item)
                                       :on-finish (and options options.on-finish)})
             true))
    (set node.drop
         (fn [self]
             (each [_ handler (ipairs (or self.handlers []))]
                 (when (and handler handler.signal handler.handler)
                     (handler.signal:disconnect handler.handler true)))
             (when self.changed
                 (self.changed:clear))))
    node)

LlmToolResultNode
