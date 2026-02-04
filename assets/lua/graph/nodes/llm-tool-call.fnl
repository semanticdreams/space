(local glm (require :glm))
(local {:GraphNode GraphNode} (require :graph/node-base))
(local LlmToolCallView (require :graph/view/views/llm-tool-call))
(local Signal (require :signal))
(local LlmStore (require :llm/store))
(local LlmTools (require :llm/tools/init))
(local LlmConversationUtils (require :graph/nodes/llm-conversation-utils))
(local json (require :json))

(fn resolve-tool-registry [convo opts]
    (local options (or opts {}))
    (or (and options options.tool-registry)
        (and convo convo.tool-registry)
        LlmTools))

(fn parse-arguments [args-str]
    (var args {})
    (var err nil)
    (when (> (length args-str) 0)
        (local (ok parsed) (pcall json.loads args-str))
        (if ok
            (set args parsed)
            (set err (.. "Failed to parse tool arguments: " (tostring parsed)))))
    {:args args
     :error err})

(fn format-tool-output [result]
    (if (= (type result) :string)
        result
        (if (= (type result) :table)
            (json.dumps result)
            (tostring result))))

(fn resolve-tool-ctx [options convo convo-id]
    (or (and options options.tool-ctx)
        {:conversation_id convo-id
         :cwd (and convo convo.cwd)}))

(fn run-tool-call [tool-registry name args ctx]
    (local (ok result) (pcall tool-registry.call name args ctx))
    (if ok
        (format-tool-output result)
        (.. "Tool call failed: " (tostring result))))

(fn sync-from-store [node record]
    (when (and node record)
        (set node.name record.name)
        (set node.arguments record.arguments)
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

(fn LlmToolCallNode [opts]
    (local options (or opts {}))
    (local store (or options.store (LlmStore.get-default)))
    (local record (and options.llm-id (store:get-item options.llm-id)))
    (local key (or options.key (if record (.. "llm-tool-call:" record.id) "llm-tool-call")))
    (local label (or options.label (or (and record record.label) "llm tool call")))
    (local node (GraphNode {:key key
                                :label label
                                :color (glm.vec4 0.2 0.7 0.6 1)
                                :sub-color (glm.vec4 0.1 0.6 0.5 1)
                                :view LlmToolCallView}))
    (set node.kind "llm-tool-call")
    (set node.llm-id (or (and record record.id) options.llm-id))
    (set node.store store)
    (set node.name (or (and record record.name) options.name))
    (set node.arguments (or (and record record.arguments) options.arguments))
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
             (assert convo "LlmToolCallNode requires a conversation ancestor")
             (local active-store (or self.store (and convo convo.store)))
             (assert active-store "LlmToolCallNode requires an llm store")
             (local convo-id (or convo.llm-id convo.id))
             (local tool-registry (resolve-tool-registry convo options))
             (local args-str (or self.arguments ""))
             (local parsed (parse-arguments args-str))
             (var output (. parsed :error))
             (when (not output)
                 (if (not tool-registry)
                     (set output "Llm tool registry missing")
                     (if (not tool-registry.call)
                         (set output "Llm tool registry missing call")
                         (do
                             (local ctx (resolve-tool-ctx options convo convo-id))
                             (set output (run-tool-call tool-registry self.name (. parsed :args) ctx))))))
             (when (not output)
                 (set output "Tool call failed: unknown error"))
             (local record
                 (active-store:add-tool-result convo-id
                                               {:name self.name
                                                :output output
                                                :call-id self.call-id
                                                :parent-id self.llm-id}))
             (when (and options options.on-item)
                 (options.on-item record))
             true))
    (set node.drop
         (fn [self]
             (each [_ handler (ipairs (or self.handlers []))]
                 (when (and handler handler.signal handler.handler)
                     (handler.signal:disconnect handler.handler true)))
             (when self.changed
                 (self.changed:clear))))
    node)

LlmToolCallNode
