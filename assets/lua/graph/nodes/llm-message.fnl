(local glm (require :glm))
(local {:GraphEdge GraphEdge} (require :graph/edge))
(local {:GraphNode GraphNode} (require :graph/node-base))
(local LlmMessageView (require :graph/view/views/llm-message))
(local LlmTools (require :llm/tools/init))
(local Signal (require :signal))
(local LlmStore (require :llm/store))
(local LlmRequests (require :llm/requests))
(local LlmToolCallNode (require :graph/nodes/llm-tool-call))
(local LlmToolResultNode (require :graph/nodes/llm-tool-result))
(local Utils (require :graph/view/utils))

(var LlmMessageNode nil)

(fn summarize-label [content]
    (if (and content (> (length content) 0))
        (let [first-line (or (string.match content "([^\n\r]+)") "")]
            (if (> (length first-line) 0)
                (Utils.truncate-with-ellipsis first-line 40)
                "llm message"))
        "llm message"))

(fn sync-from-store [node record]
    (when (and node record)
        (set node.role (or record.role node.role))
        (set node.content (or record.content node.content))
        (set (. node :tool-name) (or record.tool_name (. node :tool-name)))
        (set (. node :tool-call-id) (or record.tool_call_id (. node :tool-call-id)))
        (set (. node :tools) (or record.tools []))
        (set (. node :response-id) (or record.response_id (. node :response-id)))
        (set (. node :last-usage) (or record.last_usage (. node :last-usage)))
        (set (. node :last-context-window) (or record.last_context_window (. node :last-context-window)))
        (set (. node :last-model) (or record.last_model (. node :last-model)))
        (set node.created-at (or record.created_at node.created-at))
        (set node.updated-at (or record.updated_at node.updated-at))
        (set node.label (summarize-label (or node.content "")))
        (when node.changed
            (node.changed:emit node))))

(fn add-handler [handlers signal handler]
    (table.insert handlers {:signal signal
                            :handler handler})
    handlers)

(var matches-conversation-change? nil)
(var refresh-children nil)

(fn make-message-changed-handler [node]
    (fn [record]
        (when (and record (= record.id node.llm-id))
            (sync-from-store node record))))

(fn make-conversation-items-handler [node store]
    (fn [payload]
        (when (matches-conversation-change? node store payload)
            (refresh-children node store))))

(fn attach-message-changed-handler [node store handlers]
    (when (and store store.message-changed)
        (local handler (make-message-changed-handler node))
        (store.message-changed:connect handler)
        (add-handler handlers store.message-changed handler))
    handlers)

(fn attach-conversation-items-handler [node store handlers]
    (when (and store store.conversation-items-changed)
        (local handler (make-conversation-items-handler node store))
        (store.conversation-items-changed:connect handler)
        (add-handler handlers store.conversation-items-changed handler))
    handlers)

(fn attach-store-handler [node store]
    (local handlers [])
    (attach-message-changed-handler node store handlers)
    (attach-conversation-items-handler node store handlers)
    handlers)



(fn tool-node-name [node]
    (or (and node node.name)
        (and node (. node :tool-name))
        nil))

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

(fn sync-attached-tools [self merged]
    (set (. self :tools) merged)
    (if (and self.store self.llm-id)
        (do
            (self.store:update-item self.llm-id {:tools merged})
            (sync-from-store self (self.store:get-item self.llm-id)))))

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
    by-name)

(fn build-node-from-record [record store]
    (if (= record.type "tool-call")
        (LlmToolCallNode {:llm-id record.id
                          :store store})
        (if (= record.type "tool-result")
            (LlmToolResultNode {:llm-id record.id
                                :store store})
            (LlmMessageNode {:llm-id record.id
                             :store store}))))

(fn node-key-for-record [record]
    (if (= record.type "tool-call")
        (.. "llm-tool-call:" (tostring record.id))
        (if (= record.type "tool-result")
            (.. "llm-tool-result:" (tostring record.id))
            (.. "llm-message:" (tostring record.id)))))

(fn ensure-items-in-graph [graph parent items store]
    (local by-id {})
    (var has-parent? false)
    (each [_ record (ipairs (or items []))]
        (local key (node-key-for-record record))
        (var node (and key graph.lookup (graph:lookup key)))
        (when (not node)
            (set node (build-node-from-record record store)))
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

(fn resolve-conversation-id [node store]
    (var convo-id nil)
    (when (and node node.graph node.find-conversation)
        (local (ok convo) (pcall (fn [] (node:find-conversation))))
        (when (and ok convo convo.llm-id)
            (set convo-id convo.llm-id)))
    (if convo-id
        convo-id
        (do
            (local convo (and store store.find-conversation-for-item
                              (store:find-conversation-for-item node.llm-id)))
            (and convo convo.id))))

(fn follow-on-items [node store]
    (local convo-id (resolve-conversation-id node store))
    (if (and convo-id store)
        (do
            (local items (store:list-conversation-items convo-id))
            (var has-parent? false)
            (each [_ record (ipairs items)]
                (when record.parent_id
                    (set has-parent? true)))
            (if has-parent?
                (let [by-parent {}]
                    (each [_ record (ipairs items)]
                        (local parent-id (and record.parent_id (tostring record.parent_id)))
                        (when parent-id
                            (when (not (. by-parent parent-id))
                                (set (. by-parent parent-id) []))
                            (table.insert (. by-parent parent-id) record)))
                    (each [_ list (pairs by-parent)]
                        (table.sort list (fn [a b] (< (or a.order 0) (or b.order 0)))))
                    (local result [])
                    (fn walk [parent-id]
                        (each [_ record (ipairs (or (. by-parent parent-id) []))]
                            (table.insert result record)
                            (walk (tostring record.id))))
                    (walk (tostring node.llm-id))
                    result)
                (do
                    (var start nil)
                    (each [idx record (ipairs items)]
                        (when (and (not start) (= record.id node.llm-id))
                            (set start idx)))
                    (if start
                        (do
                            (local result [])
                            (for [i (+ start 1) (length items)]
                                (table.insert result (. items i)))
                            result)
                        []))))
        []))

(set refresh-children
    (fn [node store]
        (local graph node.graph)
        (when (and graph store node.llm-id)
            (local items (follow-on-items node store))
            (ensure-items-in-graph graph node items store))))

(set matches-conversation-change?
    (fn [node store payload]
        (if (and payload payload.conversation_id)
            (do
                (local convo-id (resolve-conversation-id node store))
                (and convo-id
                     (= (tostring convo-id) (tostring payload.conversation_id))))
            false)))

(fn resolve-conversation-record [self opts]
    (local options (or opts {}))
    (if self.graph
        (self:find-conversation)
        (or options.conversation
            (and self.store self.llm-id self.store.find-conversation-for-item
                 (self.store:find-conversation-for-item self.llm-id)))))

(fn make-input-item [node]
    (if (= node.kind "llm-message")
        (do
            (local entry {:role (or node.role "user")
                          :content (or node.content "")})
            (when (. node :tool-call-id)
                (tset entry :tool_call_id (. node :tool-call-id)))
            entry)
        (if (= node.kind "llm-tool-call")
            {:type "function_call"
             :call_id node.call-id
             :name node.name
             :arguments (or node.arguments "")}
            (if (= node.kind "llm-tool-result")
                {:type "function_call_output"
                 :call_id node.call-id
                 :output (or node.output "")}
                (error (.. "Unsupported node kind in input history: " (tostring node.kind)))))))

(fn find-parent-node [graph node]
    (var parent nil)
    (each [_ edge (ipairs graph.edges)]
        (when (= edge.target node)
            (if parent
                (error (.. "Graph node has multiple parents: " (tostring node.key)))
                (set parent edge.source))))
    parent)

(fn collect-lineage-from [graph start-node]
    (var current start-node)
    (var visited {})
    (var convo nil)
    (var lineage [])
    (while current
        (when (rawget visited current)
            (error "Detected a cycle while searching for conversation"))
        (set (. visited current) true)
        (if (= current.kind "llm-conversation")
            (do
                (set convo current)
                (set current nil))
            (do
                (table.insert lineage current)
                (set current (find-parent-node graph current)))))
    (assert convo "Missing conversation root for message lineage")
    (local ordered [])
    (for [i (length lineage) 1 -1]
        (table.insert ordered (. lineage i)))
    {:conversation convo
     :nodes ordered})

(fn run-llm-request [self opts]
    (local options (or opts {}))
    (local graph self.graph)
    (local convo (resolve-conversation-record self options))
    (assert convo "LlmMessageNode requires a conversation ancestor")
    (local store (or self.store (and convo convo.store)))
    (assert store "LlmMessageNode requires an llm store")
    (local provider
        (or (and options options.provider)
            (and convo convo.provider)
            "openai"))
    (local openai (if (= provider "openai")
                      (self:resolve-openai convo options)
                      nil))
    (local tool-registry (self:resolve-tools convo options))
    (local model (self:resolve-model convo options))
    (local max-tool-rounds (or options.max-tool-rounds
                               (and convo (. convo :max-tool-rounds))))
    (local tools-enabled? (not (= options.tools false)))
    (local tools
        (if (not tools-enabled?)
            nil
            (if (not (= options.tools nil))
                options.tools
                (self:collect-attached-tools {:conversation convo}))))
    (local conversation-id (or convo.llm-id convo.id))

    (when self.request-started
        (self.request-started:emit {:node self}))

    (fn build-request-opts [parent-id on-item on-finish]
        {:provider provider
         :openai openai
         :zai options.zai
         :zai-opts options.zai-opts
         :tool-registry tool-registry
         :model model
         :temperature options.temperature
         :top-p options.top-p
         :max-tokens options.max-tokens
         :stream options.stream
         :request-id options.request-id
         :user-id options.user-id
         :do-sample options.do-sample
         :thinking options.thinking
         :tool-stream options.tool-stream
         :stop options.stop
         :response-format options.response-format
         :reasoning-effort (. options :reasoning-effort)
         :text-verbosity (. options :text-verbosity)
         :tools tools
         :tool-choice options.tool-choice
         :parallel-tool-calls options.parallel-tool-calls
         :max-tool-rounds max-tool-rounds
         :parent-id parent-id
         :up-to-id self.llm-id
         :on-item on-item
         :on-finish on-finish})

    (if graph
        (do
            (var current-head self)
            (var last-node self)
            (fn attach-node [record]
                (local node (build-node-from-record record store))
                (graph:add-node node)
                (graph:add-edge (GraphEdge {:source current-head
                                            :target node}))
                (set current-head node)
                (set last-node node))
            (LlmRequests.run-request store conversation-id
                                     (build-request-opts
                                         (and current-head current-head.llm-id)
                                         attach-node
                                         (fn [payload]
                                             (set (. payload :node) self)
                                             (set (. payload :head) last-node)
                                             (when self.request-finished
                                                 (self.request-finished:emit payload))))))
        (do
            (var last-record nil)
            (fn record-item [record]
                (set last-record record))
            (LlmRequests.run-request store conversation-id
                                     (build-request-opts
                                         self.llm-id
                                         record-item
                                         (fn [payload]
                                             (set (. payload :node) self)
                                             (set (. payload :head) last-record)
                                             (when self.request-finished
                                                 (self.request-finished:emit payload)))))))
    true)

(set LlmMessageNode
    (fn [opts]
    (local options (or opts {}))
    (local store (or options.store (LlmStore.get-default)))
    (local record (and options.llm-id (store:get-item options.llm-id)))
    (local key
         (or options.key
             (if record
                 (.. "llm-message:" record.id)
                 "llm-message")))
    (local label (summarize-label (or (and record record.content) options.content options.label)))
    (local node (GraphNode {:key key
                                :label label
                                :color (glm.vec4 0.2 0.7 0.6 1)
                                :sub-color (glm.vec4 0.1 0.6 0.5 1)
                                :view LlmMessageView}))
    (set node.kind "llm-message")
    (set node.llm-id (or (and record record.id) options.llm-id))
    (set node.store store)
    (set node.role (or (and record record.role) options.role "user"))
    (set node.content (or (and record record.content) options.content ""))
    (set node.created-at (or (and record record.created_at) options.created-at (os.time)))
    (set node.updated-at (or (and record record.updated_at) options.updated-at node.created-at))
    (set (. node :tool-name) (or (and record record.tool_name) (. options :tool-name)))
    (set (. node :tool-call-id) (or (and record record.tool_call_id) (. options :tool-call-id)))
    (set (. node :tools) (or (and record record.tools) options.tools []))
    (set (. node :response-id) (or (and record record.response_id) (. options :response-id)))
    (set (. node :last-usage) (or (and record record.last_usage) (. options :last-usage)))
    (set (. node :last-context-window) (or (and record record.last_context_window) (. options :last-context-window)))
    (set (. node :last-model) (or (and record record.last_model) (. options :last-model)))
    (set node.changed (Signal))
    (set node.request-started (Signal))
    (set node.request-finished (Signal))
    (set node.handlers (attach-store-handler node store))
    (when record
        (sync-from-store node record))

    (set node.find-parent
         (fn [self]
             (local graph self.graph)
             (assert graph "LlmMessageNode requires a mounted graph")
             (find-parent-node graph self)))

    (set node.find-conversation
         (fn [self]
             (local graph self.graph)
             (assert graph "LlmMessageNode requires a mounted graph")
             (local lineage (collect-lineage-from graph self))
             lineage.conversation))

    (set node.collect-lineage
         (fn [self]
             (local graph self.graph)
             (assert graph "LlmMessageNode requires a mounted graph")
             (collect-lineage-from graph self)))

    (set node.build-input
         (fn [self start-node]
             (local graph self.graph)
             (assert graph "LlmMessageNode requires a mounted graph")
             (local lineage (collect-lineage-from graph (or start-node self)))
             (local nodes lineage.nodes)
             (local items [])
             (each [_ entry (ipairs nodes)]
                 (table.insert items (make-input-item entry)))
             {:conversation lineage.conversation
              :items items}))

    (set node.touch
         (fn [self]
             (local store self.store)
             (local payload {:type "message"
                             :role self.role
                             :content self.content
                             :tool-name (. self :tool-name)
                             :tool-call-id (. self :tool-call-id)
                             :response-id (. self :response-id)
                             :last-usage (. self :last-usage)
                             :last-context-window (. self :last-context-window)
                             :last-model (. self :last-model)
                             :tools (. self :tools)})
             (if (and store self.llm-id)
                 (store:update-item self.llm-id payload)
                 (when store
                     (local record (store:create-item payload))
                     (set self.llm-id record.id)))
             (when (and store self.llm-id)
                 (sync-from-store self (store:get-item self.llm-id)))
             (local (ok convo) (pcall (fn [] (self:find-conversation))))
             (when (and ok convo convo.touch)
                 (convo:touch))))

    (set node.resolve-openai
         (fn [self convo opts]
             (or (and opts opts.openai)
                 self.openai
                 (and convo convo.openai)
                 (do
                     (local OpenAI (require :openai))
                     (OpenAI (or (and opts opts.openai-opts) {}))))))

    (set node.resolve-tools
         (fn [_self convo opts]
             (or (and opts opts.tool-registry)
                 (and convo convo.tool-registry)
                 LlmTools)))

    (set node.collect-attached-tools
         (fn [self opts]
             (local options (or opts {}))
             (local convo (resolve-conversation-record self options))
             (local tool-registry (self:resolve-tools convo options))
             (local merged (collect-attached-tools tool-registry (and convo convo.tools)))
             (local message-tools (collect-attached-tools tool-registry (. self :tools)))
             (each [name tool (pairs message-tools)]
                 (tset merged name tool))
             (local result [])
             (each [_ tool (pairs merged)]
                 (table.insert result tool))
             (if (> (length result) 0)
                 result
                 nil)))

    (set node.attach-tools
         (fn [self tools]
             (local merged (merge-tool-names (. self :tools) tools))
             (sync-attached-tools self merged)))

    (set node.resolve-model
         (fn [self convo opts]
             (or (and opts opts.model)
                 self.model
                 (and convo convo.model)
                 "gpt-4o-mini")))

    (set node.set-content
         (fn [self value]
             (set self.content value)
             (set self.label (summarize-label value))))

    (set node.run-request run-llm-request)

    (set node.drop
         (fn [self]
             (each [_ record (ipairs (or self.handlers []))]
                 (when (and record record.signal record.handler)
                     (record.signal:disconnect record.handler true)))
             (when self.changed
                 (self.changed:clear))
             (when self.request-started
                 (self.request-started:clear))
             (when self.request-finished
                 (self.request-finished:clear))))
    node))

LlmMessageNode
