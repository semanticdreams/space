(local Graph (require :graph/init))
(local LlmStore (require :llm/store))
(local LlmConversationNode (require :graph/nodes/llm-conversation))
(local LlmConversationsNode (require :graph/nodes/llm-conversations))
(local LlmMessageNode (require :graph/nodes/llm-message))
(local LlmToolNode (require :graph/nodes/llm-tool))
(local LlmRequests (require :llm/requests))
(local {:GraphEdge GraphEdge} (require :graph/edge))
(local fixtures (require :tests/http-fixtures))
(local fs (require :fs))

(local tests [])

(fn wait-until [pred poll-fn timeout-secs]
    (local deadline (+ (os.clock) (or timeout-secs 2)))
    (while (and (not (pred)) (< (os.clock) deadline))
        (poll-fn 0))
    (pred))

(fn finalize-openai-client [install client ok result]
    (when client
        (client.drop))
    (install.restore)
    (if ok
        result
        (error result)))

(fn with-openai-client [fixture cb]
    (local install (fixtures.install-mock fixture))
    (var client nil)
    (local (ok result)
        (pcall
            (fn []
                (local OpenAI (require :openai))
                (set client (OpenAI {:api_key "offline-key"
                                     :user_agent "space-openai-offline/1.0"
                                     :http install.mock.binding}))
                (cb client install.mock))))
    (finalize-openai-client install client ok result))

(fn with-openai-fixture [fixture-path cb]
    (local fixture (fixtures.read-json fixture-path))
    (with-openai-client fixture cb))

(fn with-zai-fixture [fixture-path cb]
    (local fixture (fixtures.read-json fixture-path))
    (local install (fixtures.install-mock fixture))
    (local (ok result)
        (pcall (fn []
                 (cb install.mock))))
    (install.restore)
    (if ok
        result
        (error result)))

(fn count-requests [requests key method]
    (var count 0)
    (each [_ req (ipairs requests)]
        (when (and (= req.key key) (= req.method method))
            (set count (+ count 1))))
    count)

(fn find-parent [graph node]
    (var parent nil)
    (each [_ edge (ipairs graph.edges)]
        (when (= edge.target node)
            (if parent
                (error (.. "Node has multiple parents: " (tostring node.key)))
                (set parent edge.source))))
    parent)

(fn find-node [graph predicate]
    (var found nil)
    (each [_ node (pairs graph.nodes)]
        (when (and (not found) (predicate node))
            (set found node)))
    found)

(fn assert-parent [graph node expected message]
    (assert (= (find-parent graph node) expected) message))

(fn lookup-message [graph id]
    (graph:lookup (.. "llm-message:" (tostring id))))

(var temp-counter 0)
(local temp-root (fs.join-path "/tmp/space/tests" "llm-graph"))

(fn make-temp-dir []
    (set temp-counter (+ temp-counter 1))
    (fs.join-path temp-root (.. "llm-" (os.time) "-" temp-counter)))

(fn with-temp-dir [f]
    (local dir (make-temp-dir))
    (when (fs.exists dir)
        (fs.remove-all dir))
    (fs.create-dirs dir)
    (local (ok result) (pcall f dir))
    (fs.remove-all dir)
    (if ok
        result
        (error result)))

(fn with-temp-store [f]
    (with-temp-dir
        (fn [root]
            (local store (LlmStore.Store {:base-dir root}))
            (f store root))))

(fn with-graph [f]
    (local graph (Graph {:with-start false}))
    (local (ok result) (pcall f graph))
    (graph:drop)
    (if ok
        result
        (error result)))

(fn assert-branch-graph [store root left right]
    (with-graph
        (fn [graph]
            (local browser (LlmConversationsNode {:store store}))
            (graph:add-node browser)
            (local items (browser:build-items))
            (local convo-node (browser:open-entry (. items 1)))
            (assert convo-node "Conversation node should exist")
            (convo-node:expand)
            (local root-node (lookup-message graph root.id))
            (local left-node (lookup-message graph left.id))
            (local right-node (lookup-message graph right.id))
            (assert root-node "Root message should exist")
            (assert left-node "Left child should exist")
            (assert right-node "Right child should exist")
            (assert-parent graph root-node convo-node
                           "Root message should attach to conversation")
            (assert-parent graph left-node root-node
                           "Left child should attach to root")
            (assert-parent graph right-node root-node
                           "Right child should attach to root"))))

(fn llm-message-run-adds-assistant []
    (with-temp-store
        (fn [store _root]
            (local fixture-path (app.engine.get-asset-path "lua/tests/data/openai-fixture.json"))
            (with-openai-fixture fixture-path
                (fn [client mock]
                    (with-graph
                        (fn [graph]
                            (local conversation (LlmConversationNode {:label "conversation"
                                                                      :store store}))
                            (graph:add-node conversation)
                            (local message (conversation:add-message {:role "user"
                                                                      :content "hello"}))
                            (var done nil)
                            (local handler
                                (message.request-finished:connect
                                    (fn [payload]
                                        (set done payload))))
                            (message:run-request {:openai client
                                                  :tools false})
                            (local ok (wait-until (fn [] done) mock.binding.poll))
                            (message.request-finished:disconnect handler true)
                            (assert ok "OpenAI request should finish")
                            (assert done.ok "OpenAI request should succeed")
                            (local assistant
                                (find-node graph
                                           (fn [node]
                                               (and (= node.kind "llm-message")
                                                    (= node.role "assistant")))))
                            (assert assistant "Assistant message node should exist")
                            (local assistant-parent (find-parent graph assistant))
                            (assert (= assistant-parent message)
                                    "Assistant message should be parented to the request message")
                            (local usage (. assistant :last-usage))
                            (assert usage "Assistant message should record token usage")
                            (assert (= usage.total_tokens 21.0)
                                    "Assistant usage should include total tokens")
                            (assert (= (. assistant :last-context-window) 128000)
                                    "Assistant usage should include context window")
                            (assert (= assistant.content "Hello! How can I assist you today?")
                                    "Assistant message should use OpenAI output content"))))))))

(fn llm-zai-request-adds-assistant []
    (with-temp-store
        (fn [store _root]
            (local fixture-path (app.engine.get-asset-path "lua/tests/data/zai-fixture.json"))
            (with-zai-fixture fixture-path
                (fn [mock]
                    (local conversation
                        (store:create-conversation {:provider "zai"}))
                    (store:add-message conversation.id {:role "user"
                                                        :content "hello from offline fixture"})
                    (var done nil)
                    (LlmRequests.run-request store conversation.id
                                             {:provider "zai"
                                              :zai-opts {:api_key "offline-key"
                                                         :http mock.binding
                                                         :base_url "https://api.z.ai"}
                                              :tools false
                                              :on-finish (fn [payload]
                                                           (set done payload))})
                    (local ok (wait-until (fn [] done) mock.binding.poll))
                    (assert ok "ZAI request should finish")
                    (assert done.ok "ZAI request should succeed")
                    (assert (= (count-requests (mock.requests) "api/paas/v4/chat/completions" "POST") 1)
                            "ZAI request should issue one chat completion request")
                    (local items (store:list-conversation-items conversation.id))
                    (assert (= (length items) 2) "ZAI request should append one assistant message")
                    (local assistant (. items 2))
                    (assert (= assistant.role "assistant") "Assistant message should have assistant role")
                    (assert (= assistant.content "Hello from ZAI fixture")
                            "Assistant message should use ZAI output content")
                    (local stored (store:get-item assistant.id))
                    (local usage (and stored stored.last_usage))
                    (assert usage "Assistant message should record token usage")
                    (assert (= usage.input_tokens 5.0) "ZAI usage should include prompt tokens")
                    (assert (= usage.output_tokens 6.0) "ZAI usage should include completion tokens")
                    (assert (= usage.total_tokens 11.0) "ZAI usage should include total tokens"))))))

(fn llm-zai-payload-includes-chat-completion-options []
    (with-temp-store
        (fn [store _root]
            (local conversation
                (store:create-conversation {:provider "zai"
                                            :temperature 0.4}))
            (store:add-message conversation.id {:role "user"
                                                :content "hello"})
            (var captured nil)
            (local zai {})
            (set zai.create-chat-completion
                 (fn [payload opts]
                     (set captured payload)
                     (local cb (and opts opts.callback))
                     (when cb
                         (cb {:ok true
                              :status 200
                              :data {:id "zai_payload_test"
                                     :model payload.model
                                     :choices [{:message {:role "assistant"
                                                         :content "ok"}}]
                                     :usage {:prompt_tokens 1.0
                                             :completion_tokens 1.0
                                             :total_tokens 2.0}}}))
                     "req_test"))
            (var finished nil)
            (LlmRequests.run-request store conversation.id
                                     {:provider "zai"
                                      :zai zai
                                      :tools false
                                      :top-p 0.7
                                      :max-tokens 123
                                      :request-id "req-id"
                                      :user-id "user-id"
                                      :do-sample true
                                      :thinking {:type "enabled"
                                                 :clear_thinking true}
                                      :response-format {:type "json_object"}
                                      :stop ["STOP"]
                                      :on-finish (fn [payload]
                                                   (set finished payload))})
            (assert finished "ZAI request should finish")
            (assert captured "ZAI payload should be captured")
            (assert (= captured.model "glm-4.7") "ZAI payload should pin the model")
            (assert (= captured.stream false) "ZAI payload should disable streaming")
            (assert (= captured.temperature 0.4) "ZAI payload should include temperature")
            (assert (= captured.top_p 0.7) "ZAI payload should include top_p")
            (assert (= captured.max_tokens 123) "ZAI payload should include max_tokens")
            (assert (= captured.request_id "req-id") "ZAI payload should include request_id")
            (assert (= captured.user_id "user-id") "ZAI payload should include user_id")
            (assert (= captured.do_sample true) "ZAI payload should include do_sample")
            (assert (= (and captured.thinking captured.thinking.type) "enabled")
                    "ZAI payload should include thinking.type")
            (assert (= (and captured.thinking captured.thinking.clear_thinking) true)
                    "ZAI payload should include thinking.clear_thinking")
            (assert (= (and captured.response_format captured.response_format.type) "json_object")
                    "ZAI payload should include response_format.type")
            (assert (and captured.stop (= (length captured.stop) 1) (= (. captured.stop 1) "STOP"))
                    "ZAI payload should include stop"))))

(fn llm-zai-tool-flow-executes []
    (with-temp-store
        (fn [store _root]
            (local conversation
                (store:create-conversation {:provider "zai"}))
            (store:add-message conversation.id {:role "user"
                                                :content "hello"})
            (local tool-registry
                {:tools [{:type "function"
                          :name "local_uppercase"
                          :description "Uppercase the provided text."
                          :parameters {:type "object"
                                       :properties {:text {:type "string"}}
                                       :required ["text"]
                                       :additionalProperties false}}]
                 :call (fn [name args _ctx]
                           (assert (= name "local_uppercase") "Unexpected tool name")
                           (string.upper (or args.text "")))})
            (var call-count 0)
            (local zai {})
            (set zai.create-chat-completion
                 (fn [payload opts]
                     (set call-count (+ call-count 1))
                     (local cb (and opts opts.callback))
                     (if (= call-count 1)
                         (do
                             (assert payload.tools "ZAI payload should include tools")
                             (local first-tool (. payload.tools 1))
                             (local function-info (and first-tool (. first-tool :function)))
                             (local function-name (and function-info (. function-info :name)))
                             (assert (= function-name "local_uppercase")
                                     "ZAI payload should normalize tools into tool.function")
                             (when cb
                                 (cb {:ok true
                                      :status 200
                                      :data {:id "zai_tool_1"
                                             :model payload.model
                                             :choices [{:message {:role "assistant"
                                                                 :content ""
                                                                 :tool_calls [{:id "call_1"
                                                                               :type "function"
                                                                               :function {:name "local_uppercase"
                                                                                          :arguments {:text "hello"}}}]}
                                                        :finish_reason "tool_calls"}]
                                             :usage {:prompt_tokens 1.0
                                                     :completion_tokens 1.0
                                                     :total_tokens 2.0}}}))
                             "req_tool_1")
                         (do
                             (var found-tool? false)
                             (each [_ msg (ipairs (or payload.messages []))]
                                 (when (and (= msg.role "tool")
                                            (= msg.tool_call_id "call_1")
                                            (= msg.content "HELLO"))
                                     (set found-tool? true)))
                             (assert found-tool? "ZAI follow-up payload should include tool output message")
                             (when cb
                                 (cb {:ok true
                                      :status 200
                                      :data {:id "zai_tool_2"
                                             :model payload.model
                                             :choices [{:message {:role "assistant"
                                                                 :content "Done"}}]
                                             :usage {:prompt_tokens 1.0
                                                     :completion_tokens 1.0
                                                     :total_tokens 2.0}}}))
                             "req_tool_2"))))
            (var done nil)
            (LlmRequests.run-request store conversation.id
                                     {:provider "zai"
                                      :zai zai
                                      :tool-registry tool-registry
                                      :tools tool-registry.tools
                                      :max-tool-rounds 2
                                      :on-finish (fn [payload]
                                                   (set done payload))})
            (assert done "ZAI tool flow should finish")
            (assert done.ok "ZAI tool flow should succeed")
            (assert (= call-count 2) "ZAI tool flow should issue two requests")
            (local items (store:list-conversation-items conversation.id))
            (var tool-call-count 0)
            (var tool-result-count 0)
            (var assistant-count 0)
            (each [_ item (ipairs items)]
                (when (= item.type "tool-call")
                    (set tool-call-count (+ tool-call-count 1)))
                (when (= item.type "tool-result")
                    (set tool-result-count (+ tool-result-count 1)))
                (when (and (= item.type "message") (= item.role "assistant"))
                    (set assistant-count (+ assistant-count 1))))
            (assert (= tool-call-count 1) "Store should contain one tool call")
            (assert (= tool-result-count 1) "Store should contain one tool result")
            (assert (= assistant-count 2) "Store should contain two assistant messages"))))

(fn llm-message-tool-flow-executes []
    (with-temp-store
        (fn [store _root]
            (local fixture-path (app.engine.get-asset-path "lua/tests/data/openai-tools-fixture.json"))
            (local tool-registry
                {:openai-tools (fn []
                                   [{:type "function"
                                     :name "local_uppercase"
                                     :description "Uppercase the provided text."
                                     :parameters {:type "object"
                                                  :properties {:text {:type "string"}}
                                                  :required ["text"]
                                                  :additionalProperties false}
                                     :strict true}])
                 :call (fn [name args _ctx]
                           (assert (= name "local_uppercase") "Unexpected tool name")
                           (string.upper (or args.text "")))})
            (with-openai-fixture fixture-path
                (fn [client mock]
                    (with-graph
                        (fn [graph]
                            (local conversation (LlmConversationNode {:label "conversation"
                                                                      :store store}))
                            (graph:add-node conversation)
                            (local message (conversation:add-message {:role "user"
                                                                      :content "space missions"}))
                            (var done nil)
                            (local handler
                                (message.request-finished:connect
                                    (fn [payload]
                                        (set done payload))))
                            (message:run-request {:openai client
                                                  :tool-registry tool-registry
                                                  :max-tool-rounds 2})
                            (local ok (wait-until (fn [] done) mock.binding.poll))
                            (message.request-finished:disconnect handler true)
                            (assert ok "Tool flow should finish")
                            (assert done.ok "Tool flow should succeed")
                            (local tool-call
                                (find-node graph
                                           (fn [node]
                                               (= node.kind "llm-tool-call"))))
                            (local tool-result
                                (find-node graph
                                           (fn [node]
                                               (= node.kind "llm-tool-result"))))
                            (local assistant
                                (find-node graph
                                           (fn [node]
                                               (and (= node.kind "llm-message")
                                                    (= node.role "assistant")))))
                            (assert tool-call "Tool call node should exist")
                            (assert tool-result "Tool result node should exist")
                            (local tool-call-parent (find-parent graph tool-call))
                            (local tool-result-parent (find-parent graph tool-result))
                            (assert (= tool-call-parent message)
                                    "Tool call should attach to the request message")
                            (assert (= tool-result-parent tool-call)
                                    "Tool result should attach to the tool call")
                            (local tool-usage (. tool-call :last-usage))
                            (assert tool-usage "Tool call should record token usage")
                            (assert (= tool-result.output "SPACE MISSIONS")
                                    "Tool result should match tool output")
                            (assert assistant "Assistant message should exist after tool follow-up")
                            (local assistant-parent (find-parent graph assistant))
                            (assert (= assistant-parent tool-result)
                                    "Assistant follow-up should attach to the tool result")
                            (local assistant-usage (. assistant :last-usage))
                            (assert assistant-usage "Assistant message should record token usage")
                            (assert (= assistant.content "SPACE MISSIONS")
                                    "Assistant message should include tool output response")
                            (assert (= (count-requests (mock.requests) "v1/responses" "POST") 2)
                                    "Tool flow should issue two OpenAI requests"))))))))

(fn llm-conversations-browser-opens-items []
    (with-temp-store
        (fn [store _root]
            (local convo (store:create-conversation {:name "Browser"}))
            (store:add-message convo.id {:role "user"
                                         :content "hello"})
            (store:add-tool-call convo.id {:name "local_uppercase"
                                           :arguments "{\"text\":\"hello\"}"
                                           :call-id "call-1"})
            (store:add-tool-result convo.id {:name "local_uppercase"
                                             :output "HELLO"
                                             :call-id "call-1"})
            (with-graph
                (fn [graph]
                    (local browser (LlmConversationsNode {:store store}))
                    (graph:add-node browser)
                    (local items (browser:build-items))
                    (assert (> (length items) 0) "Conversation browser should list store items")
                    (local convo-node (browser:open-entry (. items 1)))
                    (assert convo-node "Browser should open a conversation node")
                    (local ordered (store:list-conversation-items convo.id))
                    (each [_ record (ipairs ordered)]
                        (local loaded
                            (find-node graph
                                       (fn [entry]
                                           (= entry.llm-id record.id))))
                        (assert (not loaded)
                                "Browser should not load conversation items before expansion"))
                    (convo-node:expand)
                    (var parent convo-node)
                    (each [_ record (ipairs ordered)]
                        (local node
                            (find-node graph
                                       (fn [entry]
                                           (= entry.llm-id record.id))))
                        (assert node "Browser should load conversation items")
                        (local linked-parent (find-parent graph node))
                        (assert (= linked-parent parent)
                                "Conversation items should be chained in order")
                        (set parent node)))))))

(fn llm-conversations-browser-opens-branches []
    (with-temp-store
        (fn [store _root]
            (local convo (store:create-conversation {:name "Branches"}))
            (local root (store:add-message convo.id {:role "user"
                                                     :content "root"}))
            (local left (store:add-message convo.id {:role "assistant"
                                                     :content "left"
                                                     :parent-id root.id}))
            (local right (store:add-message convo.id {:role "assistant"
                                                      :content "right"
                                                      :parent-id root.id}))
            (assert-branch-graph store root left right))))

(fn llm-conversations-refreshes-on-store-change []
    (with-temp-store
        (fn [store _root]
            (with-graph
                (fn [graph]
                    (local node (LlmConversationsNode {:store store}))
                    (graph:add-node node)
                    (var refresh-count 0)
                    (local handler
                        (node.items-changed:connect
                            (fn [_items]
                                (set refresh-count (+ refresh-count 1)))))
                    (local record (store:create-conversation {:name "New"}))
                    (assert (> refresh-count 0)
                            "Browser should refresh when a conversation is created")
                    (set refresh-count 0)
                    (store:update-conversation record.id {:name "Updated"})
                    (assert (> refresh-count 0)
                            "Browser should refresh when a conversation is updated")
                    (node.items-changed:disconnect handler true))))))

(fn llm-conversation-node-attaches-new-items []
    (with-temp-store
        (fn [store _root]
            (with-graph
                (fn [graph]
                    (local convo (store:create-conversation {:name "Auto"}))
                    (local node (LlmConversationNode {:llm-id convo.id
                                                      :store store}))
                    (graph:add-node node)
                    (node:expand)
                    (local first (store:add-message convo.id {:role "user"
                                                              :content "hello"}))
                    (local second (store:add-message convo.id {:role "user"
                                                               :content "again"}))
                    (local first-node (graph:lookup (.. "llm-message:" (tostring first.id))))
                    (local second-node (graph:lookup (.. "llm-message:" (tostring second.id))))
                    (assert first-node "Conversation node should add the first item")
                    (assert second-node "Message node should add follow-on items")
                    (local first-parent (find-parent graph first-node))
                    (local second-parent (find-parent graph second-node))
                    (assert (= first-parent node)
                            "Conversation node should parent the first item")
                    (assert (= second-parent first-node)
                            "Follow-on items should chain under the first item"))))))

(fn llm-conversation-node-contracts-items []
    (fn run [store]
        (with-graph
            (fn [graph]
                (local convo (store:create-conversation {:name "Contract"}))
                (local first (store:add-message convo.id {:role "user"
                                                          :content "hello"}))
                (local second (store:add-message convo.id {:role "assistant"
                                                           :content "world"}))
                (local node (LlmConversationNode {:llm-id convo.id
                                                  :store store}))
                (graph:add-node node)

                (node:expand)
                (assert (graph:lookup (.. "llm-message:" (tostring first.id)))
                        "Expanded conversation should load the first message")
                (assert (graph:lookup (.. "llm-message:" (tostring second.id)))
                        "Expanded conversation should load the second message")

                (node:contract)
                (assert (not (graph:lookup (.. "llm-message:" (tostring first.id))))
                        "Contracted conversation should remove the first message")
                (assert (not (graph:lookup (.. "llm-message:" (tostring second.id))))
                        "Contracted conversation should remove the second message")

                (local third (store:add-message convo.id {:role "user"
                                                          :content "again"}))
                (assert (not (graph:lookup (.. "llm-message:" (tostring third.id))))
                        "Contracted conversation should not auto-add new items")

                (node:expand)
                (assert (graph:lookup (.. "llm-message:" (tostring third.id)))
                        "Expanded conversation should reload items"))))

    (with-temp-store
        (fn [store _root]
            (run store))))

(fn llm-requests-gpt-5-2-includes-reasoning-and-verbosity []
    (with-temp-store
        (fn [store _root]
            (local convo (store:create-conversation {:name "gpt-5.2 payload"
                                                     :model "gpt-5.2"
                                                     :temperature 0.2
                                                     :reasoning_effort "none"
                                                     :text_verbosity "high"}))
            (var captured nil)
            (local openai {})
            (set openai.create-response
                 (fn [payload opts]
                     (set captured payload)
                     (local cb (and opts opts.callback))
                     (when cb
                         (cb {:ok true
                              :status 200
                              :data {:id "resp_test"
                                     :model payload.model
                                     :output []}}))
                     "req_test"))
            (var finished nil)
            (LlmRequests.run-request store convo.id {:openai openai
                                                     :tools false
                                                     :input-items [{:role "user"
                                                                    :content "hello"}]
                                                     :on-finish (fn [payload]
                                                                    (set finished payload))})
            (assert finished "Request should finish")
            (assert captured "OpenAI payload should be captured")
            (assert (= (and captured.reasoning captured.reasoning.effort) "none")
                    "gpt-5.2 payload should include reasoning effort")
            (assert (= (and captured.text captured.text.verbosity) "high")
                    "gpt-5.2 payload should include text verbosity")
            (assert (= captured.temperature 0.2)
                    "gpt-5.2 payload should include temperature when effort is none"))))

(fn llm-requests-gpt-5-2-omits-temperature-when-reasoning-enabled []
    (with-temp-store
        (fn [store _root]
            (local convo (store:create-conversation {:name "gpt-5.2 omit temp"
                                                     :model "gpt-5.2"
                                                     :temperature 0.8
                                                     :reasoning_effort "high"
                                                     :text_verbosity "low"}))
            (var captured nil)
            (local openai {})
            (set openai.create-response
                 (fn [payload opts]
                     (set captured payload)
                     (local cb (and opts opts.callback))
                     (when cb
                         (cb {:ok true
                              :status 200
                              :data {:id "resp_test"
                                     :model payload.model
                                     :output []}}))
                     "req_test"))
            (var finished nil)
            (LlmRequests.run-request store convo.id {:openai openai
                                                     :tools false
                                                     :input-items [{:role "user"
                                                                    :content "hello"}]
                                                     :on-finish (fn [payload]
                                                                    (set finished payload))})
            (assert finished "Request should finish")
            (assert captured "OpenAI payload should be captured")
            (assert (= (and captured.reasoning captured.reasoning.effort) "high")
                    "gpt-5.2 payload should include reasoning effort")
            (assert (= (and captured.text captured.text.verbosity) "low")
                    "gpt-5.2 payload should include text verbosity")
            (assert (= captured.temperature nil)
                    "gpt-5.2 payload should omit temperature when effort is not none"))))

(fn llm-message-node-attaches-new-items []
    (with-temp-store
        (fn [store _root]
            (local convo (store:create-conversation {:name "Auto"}))
            (local record (store:add-message convo.id {:role "user"
                                                       :content "hello"}))
            (with-graph
                (fn [graph]
                    (local node (LlmMessageNode {:llm-id record.id
                                                 :store store}))
                    (graph:add-node node)
                    (local call (store:add-tool-call convo.id {:name "local_uppercase"
                                                               :arguments "{\"text\":\"hello\"}"
                                                               :call-id "call-1"}))
                    (local key (.. "llm-tool-call:" (tostring call.id)))
                    (local child (graph:lookup key))
                    (assert child "Message node should add new tool call nodes")
                    (local parent (find-parent graph child))
                    (assert (= parent node)
                            "Message node should parent new items"))))))

(fn llm-message-collects-attached-tools []
    (with-temp-store
        (fn [store _root]
            (with-graph
                (fn [graph]
                    (local conversation (LlmConversationNode {:label "conversation"
                                                              :store store}))
                    (graph:add-node conversation)
                    (local message (conversation:add-message {:role "user"
                                                              :content "hello"}))
                    (conversation:attach-tools ["list_dir"])
                    (message:attach-tools ["read_file" "list_dir"])
                    (local tools (message:collect-attached-tools {}))
                    (assert tools "Attached tools should be resolved")
                    (local names {})
                    (each [_ tool (ipairs tools)]
                        (tset names tool.name true))
                    (assert (. names "list_dir") "Attached tools should include list_dir")
                    (assert (. names "read_file") "Attached tools should include read_file")
                    (assert (= (length tools) 2) "Attached tools should be deduped by name"))))))

(fn llm-message-run-without-graph []
    (with-temp-store
        (fn [store _root]
            (local fixture-path (app.engine.get-asset-path "lua/tests/data/openai-fixture.json"))
            (with-openai-fixture fixture-path
                (fn [client mock]
                    (local convo (store:create-conversation {:name "Offline"}))
                    (local record (store:add-message convo.id {:role "user"
                                                               :content "hello"}))
                    (local message (LlmMessageNode {:llm-id record.id
                                                    :store store}))
                    (var done nil)
                    (local handler
                        (message.request-finished:connect
                            (fn [payload]
                                (set done payload))))
                    (message:run-request {:openai client
                                          :tools false})
                    (local ok (wait-until (fn [] done) mock.binding.poll))
                    (message.request-finished:disconnect handler true)
                    (assert ok "run-request should finish without a mounted graph")
                    (assert (and done done.ok) "run-request should return ok payload"))))))

(fn llm-message-run-without-conversation []
    (with-temp-store
        (fn [store _root]
            (with-graph
                (fn [graph]
                    (local message (LlmMessageNode {:role "user"
                                                    :content "orphan"
                                                    :store store}))
                    (graph:add-node message)
                    (local (ok err)
                        (pcall (fn [] (message:run-request {:tools false}))))
                    (assert (not ok) "run-request should fail without a conversation"))))))

(fn llm-message-tool-flow-without-graph []
    (with-temp-store
        (fn [store _root]
            (local fixture-path (app.engine.get-asset-path "lua/tests/data/openai-tools-fixture.json"))
            (local tool-registry
                {:openai-tools (fn []
                                   [{:type "function"
                                     :name "local_uppercase"
                                     :description "Uppercase the provided text."
                                     :parameters {:type "object"
                                                  :properties {:text {:type "string"}}
                                                  :required ["text"]
                                                  :additionalProperties false}
                                     :strict true}])
                 :call (fn [name args _ctx]
                           (assert (= name "local_uppercase") "Unexpected tool name")
                           (string.upper (or args.text "")))})
            (with-openai-fixture fixture-path
                (fn [client mock]
                    (local convo (store:create-conversation {:name "Graphless Tools"}))
                    (local record (store:add-message convo.id {:role "user"
                                                               :content "space missions"}))
                    (local message (LlmMessageNode {:llm-id record.id
                                                    :store store}))
                    (var done nil)
                    (local handler
                        (message.request-finished:connect
                            (fn [payload]
                                (set done payload))))
                    (message:run-request {:openai client
                                          :tool-registry tool-registry
                                          :max-tool-rounds 2})
                    (local ok (wait-until (fn [] done) mock.binding.poll))
                    (message.request-finished:disconnect handler true)
                    (assert ok "Tool flow without graph should finish")
                    (assert done.ok "Tool flow without graph should succeed")
                    (local items (store:list-conversation-items convo.id))
                    (var tool-call-count 0)
                    (var tool-result-count 0)
                    (var assistant-count 0)
                    (each [_ item (ipairs items)]
                        (when (= item.type "tool-call")
                            (set tool-call-count (+ tool-call-count 1)))
                        (when (= item.type "tool-result")
                            (set tool-result-count (+ tool-result-count 1)))
                        (when (and (= item.type "message") (= item.role "assistant"))
                            (set assistant-count (+ assistant-count 1))))
                    (assert (= tool-call-count 1) "Store should contain one tool call")
                    (assert (= tool-result-count 1) "Store should contain one tool result")
                    (assert (= assistant-count 1) "Store should contain one assistant response")
                    (assert (= (count-requests (mock.requests) "v1/responses" "POST") 2)
                            "Tool flow without graph should issue two OpenAI requests"))))))

(table.insert tests {:name "llm message runs OpenAI response and adds assistant message"
                     :fn llm-message-run-adds-assistant})
(table.insert tests {:name "llm requests support ZAI provider and adds assistant message"
                     :fn llm-zai-request-adds-assistant})
(table.insert tests {:name "llm ZAI payload includes chat completion options"
                     :fn llm-zai-payload-includes-chat-completion-options})
(table.insert tests {:name "llm ZAI tool flow executes tools"
                     :fn llm-zai-tool-flow-executes})
(table.insert tests {:name "llm message tool flow executes tools and adds follow-up response"
                     :fn llm-message-tool-flow-executes})
(table.insert tests {:name "llm conversation browser opens store items"
                     :fn llm-conversations-browser-opens-items})
(table.insert tests {:name "llm conversation browser opens branches"
                     :fn llm-conversations-browser-opens-branches})
(table.insert tests {:name "llm conversation browser refreshes on store changes"
                     :fn llm-conversations-refreshes-on-store-change})
(table.insert tests {:name "llm conversation node attaches new items"
                     :fn llm-conversation-node-attaches-new-items})
(table.insert tests {:name "llm conversation node contracts items"
                     :fn llm-conversation-node-contracts-items})
(table.insert tests {:name "llm requests gpt-5.2 includes reasoning and verbosity"
                     :fn llm-requests-gpt-5-2-includes-reasoning-and-verbosity})
(table.insert tests {:name "llm requests gpt-5.2 omits temperature when reasoning enabled"
                     :fn llm-requests-gpt-5-2-omits-temperature-when-reasoning-enabled})
(table.insert tests {:name "llm message node attaches new items"
                     :fn llm-message-node-attaches-new-items})
(table.insert tests {:name "llm message collects attached tools"
                     :fn llm-message-collects-attached-tools})
(table.insert tests {:name "llm message runs without a mounted graph"
                     :fn llm-message-run-without-graph})
(table.insert tests {:name "llm message run without conversation errors"
                     :fn llm-message-run-without-conversation})
(table.insert tests {:name "llm message tool flow without graph"
                     :fn llm-message-tool-flow-without-graph})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "llm-graph"
                       :tests tests})))

{:name "llm-graph"
 :tests tests
 :main main}
