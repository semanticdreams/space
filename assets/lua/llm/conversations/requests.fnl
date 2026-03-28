(local json (require :json))
(local logging (require :logging))
(local LlmTools (require :llm/tools/init))
(local Providers (require :llm/conversations/providers))

(fn merge-tables [t1 t2]
  (local out (or t1 {}))
  (each [k v (pairs (or t2 {}))]
    (tset out k v))
  out)

(fn extract-usage [response]
  (local usage (and response response.data response.data.usage))
  (if (not usage)
      nil
      (do
        (local input-tokens (or usage.input_tokens usage.prompt_tokens))
        (local output-tokens (or usage.output_tokens usage.completion_tokens))
        (local total-tokens
          (or usage.total_tokens
              (and input-tokens output-tokens (+ input-tokens output-tokens))))
        {:input_tokens input-tokens
         :output_tokens output-tokens
         :total_tokens total-tokens})))

(fn resolve-tools [options conversation]
  (or (and options options.tool-registry)
      (and conversation conversation.tool-registry)
      LlmTools))

(fn execute-tools [store conversation-id tool-registry tool-calls opts]
  (local executed [])
  (each [_ call (ipairs tool-calls)]
    (local args-str (or call.arguments ""))
    (var args {})
    (when (> (length args-str) 0)
      (local (ok parsed) (pcall json.loads args-str))
      (if ok
          (set args parsed)
          (error (.. "Failed to parse tool arguments: " parsed))))
    (assert tool-registry "Llm request missing tool registry")
    (assert tool-registry.call "Llm tool registry missing call")
    (local ctx (or (and opts opts.tool-ctx)
                   {:conversation_id conversation-id
                    :cwd (and opts opts.cwd)}))
    (local result (tool-registry.call call.name args ctx))
    (local output
      (if (= (type result) :string)
          result
          (if (= (type result) :table)
              (json.dumps result)
              (tostring result))))
    (local result-node
      (store:add-tool-result conversation-id
                             {:name call.name
                              :output output
                              :call-id call.call_id
                              :parent-id call.id}))
    (when (and opts opts.on-item)
      (opts.on-item result-node))
    (table.insert executed result-node))
  executed)

(fn run-request [store conversation-id opts]
  (local options (or opts {}))
  (local conversation (store:get-conversation conversation-id))
  (assert conversation "Llm request missing conversation")
  (local provider-id (Providers.resolve-provider-id options conversation))
  (local provider (Providers.get-provider provider-id))
  (local client (provider.resolve-client options conversation))
  (local tool-registry (resolve-tools options conversation))
  (local model (provider.resolve-model options conversation))
  (local tools (provider.resolve-tools options conversation tool-registry))
  (local max-rounds (or options.max-tool-rounds 3))
  (var round 1)
  (var finished? false)
  (var initial-id nil)
  (var parent-id (and options options.parent-id))
  (var handle-round nil)

  (fn finish [payload]
    (when (not finished?)
      (set finished? true)
      (when options.on-finish
        (options.on-finish payload))))

  (fn handle-error [message response]
    (logging.warn (.. "Llm request failed: " (tostring message)))
    (finish {:ok false
             :error message
             :response response}))

  (fn handle-tool-round [tool-calls response]
    (if (and tool-calls (> (length tool-calls) 0))
        (do
          (local executed (execute-tools store conversation-id tool-registry tool-calls
                                         (merge-tables options {:cwd (and conversation conversation.cwd)})))
          (when (> (length executed) 0)
            (local last-executed (. executed (length executed)))
            (when last-executed
              (set parent-id last-executed.id)))
          (set round (+ round 1))
          (if (<= round max-rounds)
              (handle-round)
              (handle-error "LLM tool loop exceeded max rounds" response)))
        (finish {:ok true
                 :response response})))

  (fn handle-provider-response [response]
    (local validation-error (provider.validate-response response))
    (if validation-error
        (handle-error validation-error response)
        (do
          (local usage (extract-usage response))
          (local response-model (provider.response-model response.data model))
          (local applied
            (provider.apply-response store conversation-id response.data
                                     {:usage usage
                                      :on-item options.on-item
                                      :model response-model
                                      :context-window (provider.context-window response.data model)
                                      :parent-id parent-id}))
          (when (and applied applied.head applied.head.id)
            (set parent-id applied.head.id))
          (handle-tool-round applied.tool-calls response))))

  (set handle-round
       (fn []
         (local up-to-id (if (= round 1) options.up-to-id nil))
         (local request-body (provider.build-request-body store conversation-id up-to-id options))
         (local payload (provider.build-payload conversation options model tools request-body))
         (local request-id (provider.submit client payload handle-provider-response))
         (when (not initial-id)
           (set initial-id request-id))))

  (when options.on-start
    (options.on-start {:conversation_id conversation-id}))
  (handle-round)
  initial-id)

{:run-request run-request}
