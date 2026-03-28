(local logging (require :logging))
(local Models (require :llm/conversations/models))

(fn merge-tables [t1 t2]
  (local out (or t1 {}))
  (each [k v (pairs (or t2 {}))]
    (tset out k v))
  out)

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

(fn resolve-client [options conversation]
  (or (and options options.openai)
      (and conversation conversation.openai)
      (do
        (local OpenAI (require :llm/providers/openai))
        (OpenAI (or (and options options.openai-opts) {})))))

(fn resolve-model [options conversation]
  (or (and options options.model)
      (and conversation conversation.model)
      "gpt-4o-mini"))

(fn resolve-tools [options conversation tool-registry]
  (if (= options.tools false)
      nil
      (if (not (= options.tools nil))
          options.tools
          (and tool-registry tool-registry.openai-tools (tool-registry.openai-tools)))))

(fn build-request-body [store conversation-id up-to-id options]
  (if (= (type options.input-items) :function)
      (options.input-items)
      (or options.input-items
          (build-input store conversation-id up-to-id))))

(fn build-payload [conversation options model tools items]
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

(fn submit [client payload callback]
  (client.create-response payload {:callback callback}))

(fn validate-response [response]
  (if (not response)
      "OpenAI create-response returned nil"
      (not response.ok) (or response.error "OpenAI request failed")
      (not response.data) "OpenAI response missing data"
      nil))

(fn response-model [response-data fallback-model]
  (or (and response-data response-data.model) fallback-model))

(fn context-window [response-data fallback-model]
  (Models.context-window (response-model response-data fallback-model)))

{:resolve-client resolve-client
 :resolve-model resolve-model
 :resolve-tools resolve-tools
 :build-request-body build-request-body
 :build-payload build-payload
 :submit submit
 :validate-response validate-response
 :apply-response apply-response
 :response-model response-model
 :context-window context-window
 :build-input build-input
 :make-input-item make-input-item}
