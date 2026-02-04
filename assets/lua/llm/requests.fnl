(local json (require :json))
(local logging (require :logging))
(local LlmTools (require :llm/tools/init))
(local Models (require :llm/models))

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

(fn collect-output-text [item]
  (local content (or (and item item.content) ""))
  (if (= (type content) :string)
      content
      (do
        (local parts [])
        (each [_ part (ipairs content)]
          (if (and part (= part.type "output_text"))
              (table.insert parts (or part.text ""))
              (when part.text
                (table.insert parts part.text))))
        (table.concat parts ""))))

(fn make-message-input [record]
  (local entry {:role (or record.role "user")
                :content (or record.content "")})
  (when record.tool_call_id
    (set (. entry :tool_call_id) record.tool_call_id))
  entry)

(fn make-tool-call-input [record]
  {:type "function_call"
   :call_id record.call_id
   :name record.name
   :arguments (or record.arguments "")})

(fn make-tool-result-input [record]
  {:type "function_call_output"
   :call_id record.call_id
   :output (or record.output "")})

(local input-builders {"message" make-message-input
                       "tool-call" make-tool-call-input
                       "tool-result" make-tool-result-input})

(fn make-input-item [record]
  (local builder (. input-builders record.type))
  (if builder
      (builder record)
      (error (.. "Unsupported llm item type: " (tostring record.type)))))

(fn build-input [store conversation-id up-to-id]
  (local records (store:build-input-items conversation-id up-to-id))
  (local items [])
  (each [_ record (ipairs records)]
    (table.insert items (make-input-item record)))
  items)

(fn resolve-openai [options conversation]
  (or (and options options.openai)
      (and conversation conversation.openai)
      (do
        (local OpenAI (require :openai))
        (OpenAI (or (and options options.openai-opts) {})))))

(fn resolve-zai [options conversation]
  (or (and options options.zai)
      (and conversation conversation.zai)
      (do
        (local Zai (require :zai))
        (Zai (or (and options options.zai-opts) {})))))

(fn resolve-provider [options conversation]
  (or (and options options.provider)
      (and conversation conversation.provider)
      "openai"))

(fn resolve-model [options conversation provider]
  (if (= provider "zai")
      "glm-4.7"
      (or (and options options.model)
          (and conversation conversation.model)
          "gpt-4o-mini")))

(fn resolve-tools [options conversation]
  (or (and options options.tool-registry)
      (and conversation conversation.tool-registry)
      LlmTools))

(fn record-output-message [store conversation-id item opts parent-id response-id]
  (local message
    (store:add-message conversation-id
                       {:role item.role
                        :content (collect-output-text item)
                        :response-id response-id
                        :parent-id parent-id}))
  (when (and opts opts.on-item)
    (opts.on-item message))
  message)

(fn record-output-tool-call [store conversation-id item opts parent-id _response-id]
  (local call
    (store:add-tool-call conversation-id
                         {:name item.name
                          :arguments item.arguments
                          :call-id item.call_id
                          :parent-id parent-id}))
  (when (and opts opts.on-item)
    (opts.on-item call))
  call)

(fn record-output-tool-result [store conversation-id item opts parent-id _response-id]
  (local result
    (store:add-tool-result conversation-id
                           {:name item.name
                            :output item.output
                            :call-id item.call_id
                            :parent-id parent-id}))
  (when (and opts opts.on-item)
    (opts.on-item result))
  result)

(fn skip-output-item [_store _conversation-id _item _opts _parent-id _response-id]
  nil)

(local output-builders {"message" record-output-message
                        "function_call" record-output-tool-call
                        "function_call_output" record-output-tool-result
                        "reasoning" skip-output-item})

(fn record-output-item [store conversation-id item opts parent-id response-id]
  (local handler (. output-builders item.type))
  (if handler
      (handler store conversation-id item opts parent-id response-id)
      (do
        (logging.warn (.. "Skipping unsupported OpenAI output item: " (tostring item.type)))
        nil)))

(fn apply-response [store conversation-id response opts]
  (local output (or (and response response.output) []))
  (var head nil)
  (var parent-id (and opts opts.parent-id))
  (local response-id (and response response.id))
  (local tool-calls [])
  (each [_ item (ipairs output)]
    (local record (record-output-item store conversation-id item opts parent-id response-id))
    (when record
      (when (= record.type "tool-call")
        (table.insert tool-calls record))
      (set head record)
      (set parent-id record.id)))
  (when (and head opts opts.usage)
    (store:update-item head.id {:last-usage opts.usage
                                :last-model opts.model
                                :last-context-window opts.context-window}))
  {:head head
   :tool-calls tool-calls})

(fn zai-collect-output-message [response]
  (local choices (or (and response response.choices) []))
  (assert (and choices (> (length choices) 0)) "ZAI response missing choices")
  (local first (. choices 1))
  (local message (and first first.message))
  (assert message "ZAI response missing message")
  (local role (or (and message message.role) "assistant"))
  (local content (or (and message message.content) ""))
  (local reasoning-content (or (and message message.reasoning_content) ""))
  (local tool-calls (or (and message message.tool_calls) []))
  {:role role
   :content (if (= (type content) :string) content (tostring content))
   :reasoning_content (if (= (type reasoning-content) :string) reasoning-content (tostring reasoning-content))
   :tool_calls tool-calls})

(fn zai-message-content [message]
  (assert message "ZAI message content requires message")
  (local content (or (and message message.content) ""))
  (local reasoning-content (or (and message message.reasoning_content) ""))
  (if (and (= (type content) :string) (> (length content) 0))
      content
      (if (and (= (type reasoning-content) :string) (> (length reasoning-content) 0))
          reasoning-content
          (if (= (type content) :string) content (tostring content)))))

(fn zai-tool-call-arguments->json [args]
  (if (= (type args) :table)
      (json.dumps args)
      (if (= (type args) :string)
          args
          (json.dumps {:value (tostring args)}))))

(fn zai-normalize-tool [tool]
  (assert tool "ZAI tool normalization requires a tool")
  (if (and (= (type tool) :table) tool.function)
      tool
      (do
        (local name (or tool.name (. tool :name)))
        (assert name "ZAI tool missing name")
        {:type "function"
         :function {:name name
                    :description (or tool.description (. tool :description) "")
                    :parameters (or tool.parameters (. tool :parameters) {})}})))

(fn zai-normalize-tools [tools]
  (if (not tools)
      nil
      (do
        (local out [])
        (each [_ entry (ipairs tools)]
          (table.insert out (zai-normalize-tool entry)))
        out)))

(fn apply-zai-response [store conversation-id response opts]
  (local response-id (and response response.id))
  (local message (zai-collect-output-message response))
  (var head nil)
  (var parent-id (and opts opts.parent-id))
  (local tool-calls [])
  (local assistant
    (store:add-message conversation-id
                       {:role message.role
                        :content (zai-message-content message)
                        :response-id response-id
                        :parent-id parent-id}))
  (when (and opts opts.on-item)
    (opts.on-item assistant))
  (set head assistant)
  (set parent-id assistant.id)
  (each [_ call (ipairs (or message.tool_calls []))]
    (local call-id (or (and call call.id) (and call call.call_id)))
    (assert call-id "ZAI tool call missing id")
    (local function-info (and call call.function))
    (assert function-info "ZAI tool call missing function")
    (local name (and function-info function-info.name))
    (assert name "ZAI tool call missing function name")
    (local args-json (zai-tool-call-arguments->json (and function-info function-info.arguments)))
    (local record
      (store:add-tool-call conversation-id
                           {:name name
                            :arguments args-json
                            :call-id call-id
                            :parent-id parent-id}))
    (table.insert tool-calls record)
    (set head record)
    (set parent-id record.id)
    (when (and opts opts.on-item)
      (opts.on-item record)))
  (when (and head opts opts.usage)
    (store:update-item head.id {:last-usage opts.usage
                                :last-model opts.model
                                :last-context-window opts.context-window}))
  {:head head
   :tool-calls tool-calls})

(fn zai-tool-call-from-record [record]
  (assert record "ZAI tool call build requires a record")
  (local call-id (or (and record record.call_id) (and record record.call-id)))
  (assert call-id "ZAI tool call record missing call_id")
  (local name (or (and record record.name) (and record record.tool_name) (and record record.tool-name)))
  (assert name "ZAI tool call record missing name")
  (local args-str (or (and record record.arguments) ""))
  (local args
    (if (> (length args-str) 0)
        (do
          (local (ok parsed) (pcall json.loads args-str))
          (if ok
              parsed
              (error (.. "Failed to parse tool arguments JSON: " parsed))))
        {}))
  {:id (tostring call-id)
   :type "function"
   :function {:name (tostring name)
              :arguments args}})

(fn build-zai-messages [store conversation-id up-to-id]
  (local records (store:build-input-items conversation-id up-to-id))
  (local messages [])
  (var pending-tool-calls [])
  (var last-message nil)
  (var last-message-id nil)

  (fn flush-tool-calls []
    (when (> (length pending-tool-calls) 0)
      (table.insert messages {:role "assistant"
                              :content ""
                              :tool_calls pending-tool-calls})
      (set pending-tool-calls [])))

  (each [_ record (ipairs records)]
    (if (= record.type "message")
        (do
          (flush-tool-calls)
          (local entry {:role (or record.role "user")
                        :content (or record.content "")})
          (table.insert messages entry)
          (set last-message entry)
          (set last-message-id record.id))
        (if (= record.type "tool-call")
            (do
              (local parent-id (and record record.parent_id))
              (if (and last-message
                       (= (or last-message.role "user") "assistant")
                       parent-id
                       (= (tostring parent-id) (tostring last-message-id)))
                  (do
                    (when (not last-message.tool_calls)
                      (set last-message.tool_calls []))
                    (table.insert last-message.tool_calls (zai-tool-call-from-record record)))
                  (table.insert pending-tool-calls (zai-tool-call-from-record record))))
            (if (= record.type "tool-result")
                (do
                  (flush-tool-calls)
                  (local call-id (or record.call_id record.call-id))
                  (assert call-id "ZAI tool result record missing call_id")
                  (table.insert messages {:role "tool"
                                          :content (or record.output "")
                                          :tool_call_id (tostring call-id)}))
                (error (.. "ZAI provider does not support item type: " (tostring record.type)))))))
  (flush-tool-calls)
  messages)

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
  (local provider (resolve-provider options conversation))
  (local openai (if (= provider "openai") (resolve-openai options conversation) nil))
  (local zai (if (= provider "zai") (resolve-zai options conversation) nil))
  (local tool-registry (resolve-tools options conversation))
  (local model (resolve-model options conversation provider))
  (local tools-enabled?
    (if (= provider "zai")
        (and (not (= options.tools false)) (not (= options.tools nil)))
        (not (= options.tools false))))
  (local tools
    (if (not tools-enabled?)
        nil
        (if (not (= options.tools nil))
            (if (= provider "zai") (zai-normalize-tools options.tools) options.tools)
            (if (= provider "openai")
                (and tool-registry tool-registry.openai-tools (tool-registry.openai-tools))
                (if (= provider "zai")
                    (zai-normalize-tools (and tool-registry tool-registry.openai-tools (tool-registry.openai-tools)))
                    nil)))))
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

  (fn build-openai-payload [items]
    (local payload {:model model
                    :input items})
    (when tools
      (set (. payload :tools) tools))
    (local base-model (Models.normalize-model-name model))
    (local gpt-5-2? (= base-model "gpt-5.2"))
    (local reasoning-effort
      (if (not gpt-5-2?)
          nil
          (or (. options :reasoning-effort)
              (. options :reasoning_effort)
              (and conversation conversation.reasoning_effort)
              "none")))
    (local text-verbosity
      (if (not gpt-5-2?)
          nil
          (or (. options :text-verbosity)
              (. options :text_verbosity)
              (and conversation conversation.text_verbosity)
              "medium")))
    (when gpt-5-2?
      (local effort-options {:none true
                             :low true
                             :medium true
                             :high true
                             :xhigh true})
      (assert (and reasoning-effort (. effort-options reasoning-effort))
              (.. "Unsupported gpt-5.2 reasoning effort: " (tostring reasoning-effort)))
      (set (. payload :reasoning) {:effort reasoning-effort})

      (local verbosity-options {:low true
                               :medium true
                               :high true})
      (assert (and text-verbosity (. verbosity-options text-verbosity))
              (.. "Unsupported gpt-5.2 text verbosity: " (tostring text-verbosity)))
      (local text
        (if (= (type options.text) :table)
            (merge-tables {} options.text)
            {}))
      (set (. text :verbosity) text-verbosity)
      (set (. payload :text) text))

    (local temperature-supported?
      (or (not gpt-5-2?)
          (= reasoning-effort "none")))
    (when temperature-supported?
      (local temperature
        (if (not (= options.temperature nil))
            options.temperature
            (and conversation conversation.temperature)))
      (when (not (= temperature nil))
        (set (. payload :temperature) temperature)))
    (when (not (= options.tool-choice nil))
      (set (. payload :tool_choice) options.tool-choice))
    (when (not (= options.parallel-tool-calls nil))
      (set (. payload :parallel_tool_calls) options.parallel-tool-calls))
    payload)

  (fn build-zai-payload [messages]
    (when (and (not (= options.model nil)) (not (= (tostring options.model) "glm-4.7")))
      (error (.. "Unsupported ZAI model: " (tostring options.model))))
    (local stream?
      (if (not (= options.stream nil))
          options.stream
          false))
    (when stream?
      (error "Chat completion streaming is not supported; set stream=false or omit"))
    (local payload {:model "glm-4.7"
                    :messages messages
                    :stream false})
    (local temperature
      (if (not (= options.temperature nil))
          options.temperature
          (and conversation conversation.temperature)))
    (when (not (= temperature nil))
      (set (. payload :temperature) temperature))
    (when (not (= options.top-p nil))
      (set (. payload :top_p) options.top-p))
    (when (not (= options.max-tokens nil))
      (set (. payload :max_tokens) options.max-tokens))
    (when (not (= options.request-id nil))
      (set (. payload :request_id) options.request-id))
    (when (not (= options.user-id nil))
      (set (. payload :user_id) options.user-id))
    (when (not (= options.do-sample nil))
      (set (. payload :do_sample) options.do-sample))
    (when (not (= options.thinking nil))
      (set (. payload :thinking) options.thinking))
    (when (not (= options.tool-stream nil))
      (set (. payload :tool_stream) options.tool-stream))
    (when tools
      (set (. payload :tools) tools))
    (when (not (= options.tool-choice nil))
      (set (. payload :tool_choice) options.tool-choice))
    (when (not (= options.stop nil))
      (local stop-value
        (if (= (type options.stop) :string)
            [options.stop]
            options.stop))
      (assert (= (type stop-value) :table) "ZAI stop must be a string or an array")
      (assert (<= (length stop-value) 1) "ZAI stop supports at most one value")
      (set (. payload :stop) stop-value))
    (when (not (= options.response-format nil))
      (set (. payload :response_format) options.response-format))
    payload)

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

  (fn handle-openai-response [response]
    (if (not response)
        (handle-error "OpenAI create-response returned nil" nil)
        (not response.ok) (handle-error (or response.error "OpenAI request failed") response)
        (not response.data) (handle-error "OpenAI response missing data" response)
        (do
          (local usage (extract-usage response))
          (local applied (apply-response store conversation-id response.data
                                         {:usage usage
                                          :on-item options.on-item
                                          :model (or (and response.data response.data.model) model)
                                          :context-window (Models.context-window (or (and response.data response.data.model) model))
                                          :parent-id parent-id}))
          (when (and applied applied.head applied.head.id)
            (set parent-id applied.head.id))
          (handle-tool-round applied.tool-calls response))))

  (fn handle-zai-response [response]
    (if (not response)
        (handle-error "ZAI create-chat-completion returned nil" nil)
        (not response.ok) (handle-error (or response.error "ZAI request failed") response)
        (not response.data) (handle-error "ZAI response missing data" response)
        (not (= (type response.data) :table)) (handle-error "ZAI response is not JSON" response)
        (do
          (local usage (extract-usage response))
          (local applied
            (apply-zai-response store conversation-id response.data
                                {:usage usage
                                 :on-item options.on-item
                                 :model "glm-4.7"
                                 :context-window nil
                                 :parent-id parent-id}))
          (when (and applied applied.head applied.head.id)
            (set parent-id applied.head.id))
          (handle-tool-round applied.tool-calls response))))

  (set handle-round
       (fn []
         (local up-to-id (if (= round 1) options.up-to-id nil))
         (if (= provider "openai")
             (do
               (local items
                 (if (= (type options.input-items) :function)
                     (options.input-items)
                     (or options.input-items (build-input store conversation-id up-to-id))))
               (local payload (build-openai-payload items))
               (local request-id (openai.create-response payload {:callback handle-openai-response}))
               (when (not initial-id)
                 (set initial-id request-id)))
             (= provider "zai")
             (do
               (local messages
                 (if (= (type options.messages) :function)
                     (options.messages)
                     (or options.messages
                         (if (= (type options.input-items) :function)
                             (options.input-items)
                             (or options.input-items (build-zai-messages store conversation-id up-to-id))))))
               (local payload (build-zai-payload messages))
               (local request-id (zai.create-chat-completion payload {:callback handle-zai-response}))
               (when (not initial-id)
                 (set initial-id request-id)))
             (handle-error (.. "Unsupported LLM provider: " (tostring provider)) nil))))

  (when options.on-start
    (options.on-start {:conversation_id conversation-id}))
  (handle-round)
  initial-id)

{:run-request run-request
 :build-input build-input
 :make-input-item make-input-item}
