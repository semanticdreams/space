;; OpenCode stream normalization for Space Agent.
;; Converts OpenCode SSE payloads into provider-neutral agent stream events.

(local json (require :json))

(fn event-payload [event]
  (or (and event event.payload) event))

(fn event-properties [payload]
  (or (and payload payload.properties) payload))

(fn event-type [payload]
  (or (and payload payload.type)
      (and payload payload._event_type)))

(fn message-id [part fallback]
  (or part.messageID
      part.messageId
      part.message_id
      part.message-id
      fallback))

(fn session-id [part]
  (or part.sessionID
      part.sessionId
      part.session_id
      part.session-id))

(fn part-id [part fallback]
  (or part.partID
      part.partId
      part.part_id
      part.part-id
      part.id
      fallback))

(fn message-role [source]
  (or (and source source.role)
      (and source source.messageRole)
      (and source source.message_role)
      (and source source.message-role)
      (and source source.info source.info.role)
      (and source source.message source.message.role)
      (and source source.message source.message.info source.message.info.role)))

(fn user-message-part? [part event-role]
  (= (or (message-role part) event-role) "user"))

(fn call-id [part fallback]
  (or part.callID
      part.callId
      part.call_id
      part.call-id
      part.id
      fallback))

(fn terminal-tool-status? [status]
  (or (= status "completed")
      (= status "error")
      (= status "failed")))

(fn stringify-value [value]
  (if (= value nil)
      ""
      (= (type value) "string")
      value
      (json.dumps value)))

(fn tool-arguments-json [part]
  (local state (or part.state {}))
  (local args (or part.input part.args part.arguments part.parameters state.input {}))
  (if (= (type args) "string")
      args
      (json.dumps args)))

(fn tool-result-output [part]
  (local state (or part.state {}))
  (var value state.output)
  (when (= value nil)
    (set value state.error))
  (when (= value nil)
    (set value state.message))
  (stringify-value value))

(fn part-complete? [part]
  (not (= (and part.time part.time.end) nil)))

(fn normalize-tool-part [part]
  (local mid (message-id part "opencode-live-message"))
  (local cid (call-id part (.. "opencode-tool:" mid ":" (part-id part "tool-part"))))
  (local state (or part.state {}))
  (local status state.status)
  (local events
    [{:type :tool-call
      :provider :opencode
      :session-id (session-id part)
      :message-id mid
      :part-id (part-id part cid)
      :call-id cid
      :item-id (.. "itm-tool-call-" cid)
      :name (or part.tool (error "OpenCode stream tool part missing tool name"))
      :arguments (tool-arguments-json part)
      :status status}])
  (when (terminal-tool-status? status)
    (table.insert events
      {:type :tool-result
       :provider :opencode
       :session-id (session-id part)
       :message-id mid
       :part-id (part-id part cid)
       :call-id cid
       :item-id (.. "itm-tool-result-" cid)
       :name (or part.tool (error "OpenCode stream tool part missing tool name"))
       :output (tool-result-output part)
       :is-error (not (= status "completed"))}))
  events)

(fn normalize-text-part [part event-role]
  (if (user-message-part? part event-role)
      []
      (do
        (local mid (message-id part "opencode-live-message"))
        [{:type :assistant-message
          :provider :opencode
          :session-id (session-id part)
          :message-id mid
          :part-id (part-id part mid)
          :item-id (.. "itm-assistant-" mid)
          :content (or part.text "")
          :status (if (part-complete? part) :complete :streaming)
          :replace true}])))

(fn normalize-reasoning-part [part]
  (local mid (message-id part "opencode-live-message"))
  (local pid (part-id part mid))
  [{:type :reasoning
    :provider :opencode
    :session-id (session-id part)
    :message-id mid
    :part-id pid
    :item-id (.. "itm-reasoning-" pid)
    :content (or part.text "")
    :status (if (part-complete? part) :complete :streaming)
    :replace true}])

(fn normalize-part-updated [props]
  (local part (or (and props props.part) props))
  (local event-role (message-role props))
  (if (not part)
      []
      (= part.type "tool")
      (normalize-tool-part part)
      (= part.type "text")
      (normalize-text-part part event-role)
      (= part.type "reasoning")
      (normalize-reasoning-part part)
      []))

(fn normalize-part-delta [props]
  (local pid (part-id props nil))
  (if (not pid)
      []
      [{:type :part-delta
        :provider :opencode
        :session-id (session-id props)
        :message-id (message-id props "opencode-live-message")
        :part-id pid
        :field props.field
        :delta (or props.delta "")}]))

(fn normalize [event]
  (local payload (event-payload event))
  (local props (event-properties payload))
  (local typ (event-type payload))
  (if (= typ "message.part.updated")
      (normalize-part-updated (or props payload))
      (= typ "message.part.delta")
      (normalize-part-delta props)
      []))

{:normalize normalize
 :message-id message-id
 :message-role message-role
 :session-id session-id
 :part-id part-id
 :call-id call-id
 :terminal-tool-status? terminal-tool-status?}
