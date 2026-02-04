(local glm (require :glm))
(local {:GraphEdge GraphEdge} (require :graph/edge))
(local {:GraphNode GraphNode} (require :graph/node-base))
(local LlmConversationView (require :graph/view/views/llm-conversation))
(local LlmMessageNode (require :graph/nodes/llm-message))
(local LlmToolCallNode (require :graph/nodes/llm-tool-call))
(local LlmToolResultNode (require :graph/nodes/llm-tool-result))
(local Signal (require :signal))
(local LlmStore (require :llm/store))
(local fs (require :fs))
(local Utils (require :graph/view/utils))

(fn conversation-label [record]
  (local name (or (and record record.name) ""))
  (if (> (length name) 0)
      (Utils.truncate-with-ellipsis name 40)
      (Utils.truncate-with-ellipsis (tostring (or (and record record.id) "")) 40)))

(fn conversation-key [id]
  (.. "llm-conversation:" (tostring id)))

(fn merge-tool-names [current additions]
  (local seen {})
  (each [_ entry (ipairs (or current []))]
    (when entry
      (tset seen (tostring entry) true)))
  (each [_ entry (ipairs (or additions []))]
    (when entry
      (tset seen (tostring entry) true)))
  (local merged [])
  (each [name _ (pairs seen)]
    (table.insert merged name))
  (table.sort merged)
  merged)

(fn build-message-node [record store]
  (LlmMessageNode {:llm-id record.id
                   :role record.role
                   :content record.content
                   :tool-name record.tool_name
                   :tool-call-id record.tool_call_id
                   :response-id record.response_id
                   :last-usage record.last_usage
                   :last-context-window record.last_context_window
                   :last-model record.last_model
                   :created-at record.created_at
                   :updated-at record.updated_at
                   :store store}))

(fn build-tool-call-node [record store]
  (LlmToolCallNode {:llm-id record.id
                    :label (or record.label "llm tool call")
                    :name record.name
                    :arguments record.arguments
                    :call-id record.call_id
                    :created-at record.created_at
                    :updated-at record.updated_at
                    :store store}))

(fn build-tool-result-node [record store]
  (LlmToolResultNode {:llm-id record.id
                      :label (or record.label "llm tool result")
                      :name record.name
                      :output record.output
                      :call-id record.call_id
                      :created-at record.created_at
                      :updated-at record.updated_at
                      :store store}))

(fn node-key-for-record [record]
  (if (= record.type "tool-call")
      (.. "llm-tool-call:" (tostring record.id))
      (if (= record.type "tool-result")
          (.. "llm-tool-result:" (tostring record.id))
          (.. "llm-message:" (tostring record.id)))))

(fn build-node-for-record [record store]
  (if (= record.type "tool-call")
      (build-tool-call-node record store)
      (if (= record.type "tool-result")
          (build-tool-result-node record store)
          (build-message-node record store))))

(fn collect-loaded-item-nodes [graph items]
  (local loaded [])
  (each [_ record (ipairs (or items []))]
    (local key (node-key-for-record record))
    (local node (and key graph.lookup (graph:lookup key)))
    (when node
      (table.insert loaded node)))
  loaded)

(fn ensure-items-in-graph [graph parent items store]
  (local by-id {})
  (var has-parent? false)
  (each [_ record (ipairs (or items []))]
    (local key (node-key-for-record record))
    (var node (and key graph.lookup (graph:lookup key)))
    (when (not node)
      (set node (build-node-for-record record store)))
    (graph:add-node node)
    (set (. by-id (tostring record.id)) node)
    (when record.parent_id
      (set has-parent? true)))
  (if has-parent?
      (each [_ record (ipairs (or items []))]
        (local node (. by-id (tostring record.id)))
        (local parent-id (and record.parent_id (tostring record.parent_id)))
        (local parent-node (and parent-id (. by-id parent-id)))
        (graph:add-edge (GraphEdge {:source (or parent-node parent)
                                    :target node})))
      (do
        (var current parent)
        (each [_ record (ipairs (or items []))]
          (local node (. by-id (tostring record.id)))
          (graph:add-edge (GraphEdge {:source current
                                      :target node}))
          (set current node)))))

(fn refresh-children [node store]
  (local graph node.graph)
  (when (and graph store node.llm-id node.expanded)
    (local items (store:list-conversation-items node.llm-id))
    (when (and items (> (length items) 0))
      (ensure-items-in-graph graph node items store))))

(fn sync-conversation [node record]
  (when (and node record)
    (set node.name (or record.name ""))
    (set node.provider (or record.provider "openai"))
    (set node.model (or record.model "gpt-4o-mini"))
    (set node.temperature (if (not (= record.temperature nil)) record.temperature 0))
    (set (. node :reasoning-effort) (or record.reasoning_effort "none"))
    (set (. node :text-verbosity) (or record.text_verbosity "medium"))
    (set node.tools (or record.tools []))
    (set node.cwd (or record.cwd (fs.cwd))) ; Fallback to process CWD if missing in record
    (set (. node :max-tool-rounds) record.max_tool_rounds)
    (set node.created-at (or record.created_at node.created-at))
    (set node.updated-at (or record.updated_at node.updated-at))
    (set node.label (conversation-label record))
    (when node.changed
      (node.changed:emit node))))

(fn attach-store-handlers [node store]
  (local handlers [])
  (when (and store store.conversation-changed)
    (local handler
      (store.conversation-changed:connect
        (fn [record]
          (when (and record (= record.id node.llm-id))
            (sync-conversation node record)))))
    (table.insert handlers {:signal store.conversation-changed
                            :handler handler}))
  (when (and store store.conversation-items-changed)
    (local handler
      (store.conversation-items-changed:connect
        (fn [payload]
          (when (and payload (= payload.conversation_id node.llm-id))
            (refresh-children node store)))))
    (table.insert handlers {:signal store.conversation-items-changed
                            :handler handler}))
  handlers)

(fn LlmConversationNode [opts]
  (local options (or opts {}))
  (local store (or options.store (LlmStore.get-default)))
  (local max-tool-rounds (or (. options :max-tool-rounds)
                             (. options :max_tool_rounds)))
  (local reasoning-effort (or (. options :reasoning-effort)
                              (. options :reasoning_effort)))
  (local text-verbosity (or (. options :text-verbosity)
                            (. options :text_verbosity)))
  (local convo-id (or options.llm-id options.conversation-id))
  (local record
    (if convo-id
        (store:ensure-conversation convo-id {:name options.name
                                             :provider options.provider
                                             :model options.model
                                             :temperature options.temperature
                                             :reasoning_effort reasoning-effort
                                             :text_verbosity text-verbosity
                                             :max_tool_rounds max-tool-rounds
                                             :tools options.tools})
        (store:create-conversation {:name options.name
                                    :provider options.provider
                                    :model options.model
                                    :temperature options.temperature
                                    :reasoning_effort reasoning-effort
                                    :text_verbosity text-verbosity
                                    :max_tool_rounds max-tool-rounds
                                    :tools options.tools
                                    :cwd options.cwd})))
  (local id (or (and record record.id) convo-id))
  (local key (or options.key (conversation-key id)))
  (local label (conversation-label record))
  (local node (GraphNode {:key key
                          :label label
                          :color (glm.vec4 0.2 0.7 0.6 1)
                          :sub-color (glm.vec4 0.1 0.6 0.5 1)
                          :view LlmConversationView}))
  (set node.kind "llm-conversation")
  (set node.llm-id id)
  (set node.store store)
  (set node.tools (or (and record record.tools) options.tools []))
  (set node.cwd (or (and record record.cwd) options.cwd))
  (set (. node :max-tool-rounds) (and record record.max_tool_rounds))
  (set node.changed (Signal))
  (set node.handlers [])
  (set node.expanded (or options.expanded false))

  (sync-conversation node record)
  (set node.handlers (attach-store-handlers node store))

  (set node.set-name
       (fn [self value]
         (set self.name (or value ""))
         (store:update-conversation self.llm-id {:name self.name})
         (set self.label (conversation-label (store:get-conversation self.llm-id)))))

  (set node.set-provider
       (fn [self value]
         (local provider (or value "openai"))
         (set self.provider provider)
         (when (= provider "zai")
           (set self.model "glm-4.7"))
         (when (and (= provider "openai") (= self.model "glm-4.7"))
           (set self.model "gpt-4o-mini"))
         (store:update-conversation self.llm-id {:provider self.provider
                                                 :model self.model})))

  (set node.set-cwd
       (fn [self value]
         (set self.cwd value)
         (store:update-conversation self.llm-id {:cwd self.cwd})))

  (set node.set-reasoning-effort
       (fn [self value]
         (set (. self :reasoning-effort) (or value "none"))
         (store:update-conversation self.llm-id {:reasoning_effort (. self :reasoning-effort)})))

  (set node.set-text-verbosity
       (fn [self value]
         (set (. self :text-verbosity) (or value "medium"))
         (store:update-conversation self.llm-id {:text_verbosity (. self :text-verbosity)})))

  (set node.touch
       (fn [self]
         (store:update-conversation self.llm-id {:name self.name
                                                 :provider self.provider
                                                 :model self.model
                                                 :temperature self.temperature
                                                 :reasoning_effort (. self :reasoning-effort)
                                                 :text_verbosity (. self :text-verbosity)
                                                 :max_tool_rounds (. self :max-tool-rounds)
                                                 :tools self.tools
                                                 :cwd self.cwd})
         (sync-conversation self (store:get-conversation self.llm-id))))

  (set node.attach-tools
       (fn [self tools]
         (local merged (merge-tool-names self.tools tools))
         (set self.tools merged)
         (store:update-conversation self.llm-id {:tools merged})
         (sync-conversation self (store:get-conversation self.llm-id))))

  (set node.add-message
       (fn [self opts parent]
         (local graph self.graph)
         (assert graph "LlmConversationNode requires a mounted graph")
         (local record
           (store:add-message self.llm-id
                              {:role (or (and opts opts.role) "user")
                               :content (or (and opts opts.content) "")
                               :tool-name (and opts (. opts :tool-name))
                               :tool-call-id (and opts (. opts :tool-call-id))
                               :response-id (and opts (. opts :response-id))
                               :parent-id (and parent parent.llm-id)}))
         (local message (build-message-node record store))
         (graph:add-node message)
         (graph:add-edge (GraphEdge {:source (or parent self)
                                     :target message}))
         (self:touch)
         message))

  (set node.add-tool-call
       (fn [self opts parent]
         (local graph self.graph)
         (assert graph "LlmConversationNode requires a mounted graph")
         (local record
           (store:add-tool-call self.llm-id
                                {:name (and opts opts.name)
                                 :arguments (and opts opts.arguments)
                                 :call-id (and opts (. opts :call-id))
                                 :parent-id (and parent parent.llm-id)}))
         (local call (build-tool-call-node record store))
         (graph:add-node call)
         (graph:add-edge (GraphEdge {:source (or parent self)
                                     :target call}))
         (self:touch)
         call))

  (set node.add-tool-result
       (fn [self opts parent]
         (local graph self.graph)
         (assert graph "LlmConversationNode requires a mounted graph")
         (local record
           (store:add-tool-result self.llm-id
                                  {:name (and opts opts.name)
                                   :output (and opts opts.output)
                                   :call-id (and opts (. opts :call-id))
                                   :parent-id (and parent parent.llm-id)}))
         (local result (build-tool-result-node record store))
         (graph:add-node result)
         (graph:add-edge (GraphEdge {:source (or parent self)
                                     :target result}))
         (self:touch)
         result))

  (set node.expand
       (fn [self]
         (local graph self.graph)
         (assert graph "LlmConversationNode requires a mounted graph")
         (set self.expanded true)
         (when self.changed
           (self.changed:emit self))
         (refresh-children self store)))

  (set node.contract
       (fn [self]
         (local graph self.graph)
         (assert graph "LlmConversationNode requires a mounted graph")
         (set self.expanded false)
         (local items (store:list-conversation-items self.llm-id))
         (local nodes-to-remove (collect-loaded-item-nodes graph items))
         (graph:remove-nodes nodes-to-remove)
         (when self.changed
           (self.changed:emit self))))

  (set node.delete
       (fn [self]
         (local graph self.graph)
         (local items (store:list-conversation-items self.llm-id))
         (when graph
           (local nodes-to-remove (collect-loaded-item-nodes graph items))
           (table.insert nodes-to-remove self)
           (graph:remove-nodes nodes-to-remove))
         (store:delete-conversation self.llm-id)))

  (set node.drop
       (fn [self]
         (each [_ record (ipairs self.handlers)]
           (when (and record record.signal record.handler)
             (record.signal:disconnect record.handler true)))
         (when self.changed
           (self.changed:clear))))

  node)

LlmConversationNode
