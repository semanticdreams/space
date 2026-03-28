(local json (require :json))

(fn collect-output-message [response]
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

(fn message-content [message]
  (assert message "ZAI message content requires message")
  (local content (or (and message message.content) ""))
  (local reasoning-content (or (and message message.reasoning_content) ""))
  (if (and (= (type content) :string) (> (length content) 0))
      content
      (if (and (= (type reasoning-content) :string) (> (length reasoning-content) 0))
          reasoning-content
          (if (= (type content) :string) content (tostring content)))))

(fn tool-call-arguments->json [args]
  (if (= (type args) :table)
      (json.dumps args)
      (if (= (type args) :string)
          args
          (json.dumps {:value (tostring args)}))))

(fn normalize-tool [tool]
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

(fn normalize-tools [tools]
  (if (not tools)
      nil
      (do
        (local out [])
        (each [_ entry (ipairs tools)]
          (table.insert out (normalize-tool entry)))
        out)))

(fn apply-response [store conversation-id response opts]
  (local response-id (and response response.id))
  (local message (collect-output-message response))
  (var head nil)
  (var parent-id (and opts opts.parent-id))
  (local tool-calls [])
  (local assistant
    (store:add-message conversation-id
                       {:role message.role
                        :content (message-content message)
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
    (local args-json (tool-call-arguments->json (and function-info function-info.arguments)))
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

(fn tool-call-from-record [record]
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

(fn build-messages [store conversation-id up-to-id]
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
                    (table.insert last-message.tool_calls (tool-call-from-record record)))
                  (table.insert pending-tool-calls (tool-call-from-record record))))
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

(fn resolve-client [options conversation]
  (or (and options options.zai)
      (and conversation conversation.zai)
      (do
        (local Zai (require :llm/providers/zai))
        (Zai (or (and options options.zai-opts) {})))))

(fn resolve-model [options _conversation]
  (when (and (not (= options.model nil)) (not (= (tostring options.model) "glm-4.7")))
    (error (.. "Unsupported ZAI model: " (tostring options.model))))
  "glm-4.7")

(fn resolve-tools [options _conversation _tool-registry]
  (if (or (= options.tools false) (= options.tools nil))
      nil
      (normalize-tools options.tools)))

(fn build-request-body [store conversation-id up-to-id options]
  (if (= (type options.messages) :function)
      (options.messages)
      (or options.messages
          (if (= (type options.input-items) :function)
              (options.input-items)
              (or options.input-items
                  (build-messages store conversation-id up-to-id))))))

(fn build-payload [conversation options _model tools messages]
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

(fn submit [client payload callback]
  (client.create-chat-completion payload {:callback callback}))

(fn validate-response [response]
  (if (not response)
      "ZAI create-chat-completion returned nil"
      (not response.ok) (or response.error "ZAI request failed")
      (not response.data) "ZAI response missing data"
      (not (= (type response.data) :table)) "ZAI response is not JSON"
      nil))

(fn response-model [_response-data _fallback-model]
  "glm-4.7")

(fn context-window [_response-data _fallback-model]
  nil)

{:resolve-client resolve-client
 :resolve-model resolve-model
 :resolve-tools resolve-tools
 :build-request-body build-request-body
 :build-payload build-payload
 :submit submit
 :validate-response validate-response
 :apply-response apply-response
 :response-model response-model
 :context-window context-window}
