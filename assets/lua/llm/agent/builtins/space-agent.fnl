;; SpaceAgent — the initial drawing/scene/graph/app assistant using OpenCode.
;; Creates one OpenCode session per turn (or reuses from session.data).

(local Uuid (require :uuid))
(local json (require :json))
(local logging (require :logging))
(local OpencodeStream (require :llm/agent/opencode-stream))

(fn new-item-id []
  (.. "itm-" (Uuid.v4)))

(fn now []
  (os.time))

(fn resolve-opencode [ctx]
  (local providers (or ctx.providers (error "SpaceAgent requires ctx.providers")))
  (if providers.opencode
      providers.opencode
      (. providers :opencode-factory)
      (do
        (local provider ((. providers :opencode-factory)))
        (when (not provider)
          (error "SpaceAgent opencode factory returned nil"))
        (tset providers :opencode provider)
        provider)
      (error "SpaceAgent requires ctx.providers.opencode or ctx.providers.opencode-factory")))

(fn response-error [resp fallback]
  (or (and resp resp.error) fallback))

(fn response-data [resp]
  (or (and resp resp.data) resp))

(fn opencode-message-id [message fallback]
  (or (and message message.info message.info.id)
      message.id
      fallback))

(fn tool-call-id [message part index]
  (or part.callID
      part.callId
      part.call_id
      part.call-id
      part.id
      (.. "opencode-tool:" (opencode-message-id message "message") ":" (tostring index))))

(fn tool-call-item-id [call-id]
  (.. "itm-tool-call-" call-id))

(fn tool-result-item-id [call-id]
  (.. "itm-tool-result-" call-id))

(fn tool-arguments-json [part]
  (local state (or part.state {}))
  (local args (or part.input part.args part.arguments part.parameters state.input {}))
  (if (= (type args) "string")
      args
      (json.dumps args)))

(fn stringify-tool-value [value]
  (if (= value nil)
      ""
      (= (type value) "string")
      value
      (json.dumps value)))

(fn terminal-tool-status? [status]
  (or (= status "completed")
      (= status "error")
      (= status "failed")))

(fn tool-result-output [part]
  (local state (or part.state {}))
  (var value state.output)
  (when (= value nil)
    (set value state.error))
  (when (= value nil)
    (set value state.message))
  (stringify-tool-value value))

(fn collect-existing-tool-item-keys [session]
  (local existing {})
  (each [_ item (ipairs (or session.items []))]
    (local call-id (or item.call-id item.call_id))
    (when call-id
      (tset existing (.. item.type ":" call-id) item.id)))
  existing)

(fn append-tool-call-item [ctx existing message message-index part part-index]
  (local tool-name (or part.tool (error "OpenCode tool part missing tool name")))
  (local call-id (tool-call-id message part part-index))
  (local call-key (.. "tool-call:" call-id))
  (if (. existing call-key)
      (do
        (ctx.turn:update-item (. existing call-key)
          {:arguments (tool-arguments-json part)
           :status (and part.state part.state.status)
           :updated-at (now)})
        0)
      (do
        (ctx.turn:append-item
          {:id (tool-call-item-id call-id)
           :type "tool-call"
           :name tool-name
           :arguments (tool-arguments-json part)
           :call-id call-id
           :parent-id (opencode-message-id message (.. "opencode-message-" message-index))
           :provider "opencode"
           :status (and part.state part.state.status)
           :created-at (now)})
        (tset existing call-key (tool-call-item-id call-id))
        1)))

(fn append-tool-result-item [ctx existing part part-index message]
  (if (not (and part.state (terminal-tool-status? part.state.status)))
      0
      (do
        (local tool-name (or part.tool (error "OpenCode tool part missing tool name")))
        (local call-id (tool-call-id message part part-index))
        (local result-key (.. "tool-result:" call-id))
        (if (. existing result-key)
            (do
              (ctx.turn:update-item (. existing result-key)
                {:output (tool-result-output part)
                 :is-error (not (= part.state.status "completed"))
                 :updated-at (now)})
              0)
            (do
              (ctx.turn:append-item
                {:id (tool-result-item-id call-id)
                 :type "tool-result"
                 :name tool-name
                 :output (tool-result-output part)
                 :call-id call-id
                 :parent-id call-id
                 :provider "opencode"
                 :is-error (not (= part.state.status "completed"))
                 :created-at (now)})
              (tset existing result-key (tool-result-item-id call-id))
              1)))))

(fn append-tool-audit-items [ctx session messages]
  (local existing (collect-existing-tool-item-keys session))
  (var appended 0)
  (each [message-index message (ipairs (or messages []))]
    (each [part-index part (ipairs (or message.parts []))]
      (when (= part.type "tool")
        (set appended (+ appended
                         (append-tool-call-item ctx existing message message-index part part-index)))
        (set appended (+ appended
                         (append-tool-result-item ctx existing part part-index message))))))
  appended)

(fn new-stream-state [input-text]
  {:text-parts {}
   :text-order {}
   :part-meta {}
   :pending-deltas {}
   :ignored-message-ids {}
   :input-text input-text
   :assistant-message-ids []})

(fn ensure-subtable [root key]
  (when (not (. root key))
    (tset root key {}))
  (. root key))

(fn contains-value? [items value]
  (var found false)
  (each [_ item (ipairs (or items []))]
    (when (= item value)
      (set found true)))
  found)

(fn stream-part-key [message-id part-id]
  (.. (or message-id "opencode-live-message") ":" (or part-id "part")))

(fn remember-assistant-message-id [stream-state message-id]
  (when (and message-id (not (contains-value? stream-state.assistant-message-ids message-id)))
    (table.insert stream-state.assistant-message-ids message-id)))

(fn ignore-message-id! [stream-state message-id]
  (when message-id
    (tset stream-state.ignored-message-ids message-id true)))

(fn ignored-stream-event? [stream-state event]
  (and event.message-id
       (. stream-state.ignored-message-ids event.message-id)))

(fn input-echo-stream-event? [stream-state event]
  (and (= event.type :assistant-message)
       (= event.content stream-state.input-text)))

(fn skip-unstructured-input-echo-event? [stream-state event]
  (and (input-echo-stream-event? stream-state event)
       (= (length stream-state.assistant-message-ids) 0)))

(fn single-streamed-assistant-message-id [stream-state]
  (when (= (length stream-state.assistant-message-ids) 1)
    (. stream-state.assistant-message-ids 1)))

(fn ensure-text-part [stream-state message-id part-id]
  (local message-parts (ensure-subtable stream-state.text-parts message-id))
  (local message-order (ensure-subtable stream-state.text-order message-id))
  (when (not (contains-value? message-order part-id))
    (table.insert message-order part-id))
  message-parts)

(fn text-message-content [stream-state message-id]
  (local message-parts (. stream-state.text-parts message-id))
  (local message-order (. stream-state.text-order message-id))
  (local chunks [])
  (each [_ part-id (ipairs (or message-order []))]
    (table.insert chunks (or (and message-parts (. message-parts part-id)) "")))
  (table.concat chunks ""))

(fn remember-part-kind [stream-state part-id event-type message-id item-id]
  (tset stream-state.part-meta (stream-part-key message-id part-id)
        {:type event-type
         :message-id message-id
         :item-id item-id}))

(fn pop-pending-deltas [stream-state message-id part-id]
  (local key (stream-part-key message-id part-id))
  (local pending (. stream-state.pending-deltas key))
  (tset stream-state.pending-deltas key nil)
  (or pending []))

(fn buffer-delta [stream-state event]
  (local pending (ensure-subtable stream-state.pending-deltas (stream-part-key event.message-id event.part-id)))
  (table.insert pending event))

(fn upsert-assistant-message [ctx stream-state event]
  (remember-assistant-message-id stream-state event.message-id)
  (remember-part-kind stream-state event.part-id :assistant-message event.message-id event.item-id)
  (local message-parts (ensure-text-part stream-state event.message-id event.part-id))
  (when event.replace
    (tset message-parts event.part-id event.content))
  (each [_ delta (ipairs (pop-pending-deltas stream-state event.message-id event.part-id))]
    (when (= delta.field "text")
      (tset message-parts event.part-id
            (.. (or (. message-parts event.part-id) "") delta.delta))))
  (ctx.turn:upsert-item
    {:id event.item-id
     :type :message
     :role :assistant
     :content (text-message-content stream-state event.message-id)
     :parent-id event.message-id
     :provider event.provider
     :model "opencode"
     :stream-status event.status
     :updated-at (now)}))

(fn upsert-reasoning [ctx stream-state event]
  (remember-part-kind stream-state event.part-id :reasoning event.message-id event.item-id)
  (var content event.content)
  (each [_ delta (ipairs (pop-pending-deltas stream-state event.message-id event.part-id))]
    (when (= delta.field "text")
      (set content (.. content delta.delta))))
  (ctx.turn:upsert-item
    {:id event.item-id
     :type :reasoning
     :content content
     :parent-id event.message-id
     :provider event.provider
     :stream-status event.status
     :updated-at (now)}))

(fn apply-part-delta [ctx stream-state event]
  (local meta (. stream-state.part-meta (stream-part-key event.message-id event.part-id)))
  (if (not meta)
      (buffer-delta stream-state event)
      (= meta.type :assistant-message)
      (do
        (local message-parts (ensure-text-part stream-state meta.message-id event.part-id))
        (when (= event.field "text")
          (tset message-parts event.part-id
                (.. (or (. message-parts event.part-id) "") event.delta))
          (ctx.turn:update-item meta.item-id
            {:content (text-message-content stream-state meta.message-id)
             :stream-status :streaming
             :updated-at (now)})))
      (= meta.type :reasoning)
      (when (= event.field "text")
        (local item-id meta.item-id)
        (var existing-content "")
        (each [_ item (ipairs (or ctx.session.items []))]
          (when (= item.id item-id)
            (set existing-content (or item.content ""))))
        (ctx.turn:update-item item-id
          {:content (.. existing-content event.delta)
           :stream-status :streaming
           :updated-at (now)}))))

(fn upsert-tool-call [ctx event]
  (ctx.turn:upsert-item
    {:id event.item-id
     :type :tool-call
     :name event.name
     :arguments event.arguments
     :call-id event.call-id
     :parent-id event.message-id
     :provider event.provider
     :status event.status
     :updated-at (now)}))

(fn upsert-tool-result [ctx event]
  (ctx.turn:upsert-item
    {:id event.item-id
     :type :tool-result
     :name event.name
     :output event.output
     :call-id event.call-id
     :parent-id event.call-id
     :provider event.provider
     :is-error event.is-error
     :updated-at (now)}))

(fn apply-stream-event [ctx stream-state event]
  (if (= event.type :assistant-message)
      (upsert-assistant-message ctx stream-state event)
      (= event.type :reasoning)
      (upsert-reasoning ctx stream-state event)
      (= event.type :part-delta)
      (apply-part-delta ctx stream-state event)
      (= event.type :tool-call)
      (upsert-tool-call ctx event)
      (= event.type :tool-result)
      (upsert-tool-result ctx event)))

(fn handle-live-stream-event [ctx stream-state opencode-session-id event]
  (local events (OpencodeStream.normalize event))
  (each [_ normalized (ipairs events)]
    (when (and (or (not normalized.session-id)
                   (= normalized.session-id opencode-session-id))
               (not (ctx.turn:cancelled?)))
      (if (ignored-stream-event? stream-state normalized)
          nil
          (skip-unstructured-input-echo-event? stream-state normalized)
          nil
          (apply-stream-event ctx stream-state normalized)))))

(fn subscribe-live-events [opencode ctx session opencode-session-id stream-state on-fatal]
  (when (and opencode.events opencode.events.subscribe)
    (logging.info "[space-agent] subscribing to OpenCode live event stream")
    (opencode.events.subscribe
      (fn [event]
        (local (ok err)
          (pcall handle-live-stream-event
                 ctx
                 stream-state
                 opencode-session-id
                 event))
        (when (not ok)
          (on-fatal (.. "OpenCode live event handling failed: " (tostring err))))))))

(fn final-response-content [message]
  (local parts (or message.parts []))
  (var content "")
  (each [_ part (ipairs parts)]
    (when (= part.type "text")
      (set content (.. content part.text))))
  content)

(fn message-role [message]
  (or (and message message.info message.info.role)
      (and message message.role)))

(fn assistant-message? [message]
  (= (message-role message) "assistant"))

(fn latest-assistant-message [messages]
  (var found nil)
  (each [_ message (ipairs (or messages []))]
    (when (assistant-message? message)
      (set found message)))
  found)

(fn prompt-assistant-message [resp]
  (local message (response-data resp))
  (when (not (= (message-role message) "user"))
    message))

(fn response-message-id [message]
  (or (and message message.info message.info.id)
      (and message message.id)))

(fn append-assistant-response [ctx stream-state turn-msg-id message prompt-resp requested-model]
  (local prompt-message (response-data prompt-resp))
  (local info (or (and message message.info) (and prompt-message prompt-message.info) {}))
  (local streamed-message-id (single-streamed-assistant-message-id stream-state))
  (local message-id (or (response-message-id message)
                        streamed-message-id
                        (and message turn-msg-id)))
  (var content (if message (final-response-content message) ""))
  (when (and (= content "") streamed-message-id)
    (local streamed (text-message-content stream-state streamed-message-id))
    (when (> (length streamed) 0)
      (set content streamed)))
  (when message-id
    (local item-id (.. "itm-assistant-" message-id))
    (ctx.turn:upsert-item
      {:id item-id
       :type :message
       :role :assistant
       :content content
       :parent-id turn-msg-id
       :provider :opencode
       :model (or (and info.model info.model.modelID)
                  (and requested-model requested-model.modelID)
                  "opencode")
       :usage (or (and message message.usage) (and prompt-message prompt-message.usage) {})
       :stream-status :complete
       :updated-at (now)}))
  (ctx.turn:finish {:content content}))

(fn handle-messages-response [ctx session stream-state turn-msg-id prompt-resp requested-model fail messages-resp]
  (if (ctx.turn:cancelled?)
      nil
      (not (and messages-resp messages-resp.ok))
      (fail (.. "OpenCode messages fetch failed: "
                (response-error messages-resp "unknown error")))
      (do
        (local (ok err)
          (pcall (fn []
                   (local messages (response-data messages-resp))
                   (append-tool-audit-items ctx session messages)
                   (local assistant-message (or (latest-assistant-message messages)
                                                (prompt-assistant-message prompt-resp)))
                   (append-assistant-response ctx stream-state turn-msg-id assistant-message prompt-resp requested-model))))
        (when (not ok)
          (fail (.. "OpenCode message audit persistence failed: " (tostring err)))))))

(fn append-audit-then-assistant [opencode ctx session stream-state session-id turn-msg-id resp requested-model fail]
  (if (not opencode.session.messages)
      (fail "OpenCode provider missing session.messages for agent audit persistence")
      (do
        (local (ok err)
          (pcall opencode.session.messages session-id
                 (fn [messages-resp]
                   (handle-messages-response ctx session stream-state turn-msg-id resp requested-model fail messages-resp))))
        (when (not ok)
          (fail (.. "OpenCode messages fetch submit failed: " (tostring err)))))))

(fn format-capability-guidance [tools]
  (assert tools "SpaceAgent requires ctx.tools")
  (assert (= (type tools.prompt-fragments) "function")
          "SpaceAgent requires ctx.tools:prompt-fragments")
  (local prompt-fragments (tools:prompt-fragments))
  (if (= (length prompt-fragments) 0)
      "No additional capability guidance."
      (do
        (local fragments [])
        (each [_ fragment (ipairs prompt-fragments)]
          (local prompt (or fragment.prompt
                            (error "agent prompt fragment missing :prompt")))
          (table.insert fragments prompt))
        (table.concat fragments "\n"))))

(fn build-agent [deps]
  ;; Return a plain table with :id, :name, and :run.
  ;; The :run method is defined as a named function for scoping clarity.
  (local model deps.model)
  (fn run [self_ input session ctx]
    (local PromptUtils (require :llm/agent/prompt-utils))
    (local opencode (resolve-opencode ctx))
    (var live-events nil)
    (local stream-state (new-stream-state input))

    (fn close-live-events []
      (when live-events
        (when live-events.unsubscribe
          (live-events.unsubscribe))
        (logging.info "[space-agent] unsubscribed from OpenCode live event stream")
        (set live-events nil)))

    ;; Build system prompt
    (local context-block (PromptUtils.format-context ctx))
    (local preset-block (PromptUtils.format-presets ctx.presets))
    (local capability-guidance (format-capability-guidance ctx.tools))
    (local system-prompt
      (PromptUtils.assemble-blocks
        [{:name "Instructions"
          :content (table.concat
                     ["You are Space Agent. Help with drawing, graph, scene, and app tasks using only approved available tools."
                      "For tools that may require approval, call space_agent_request_tool_approval first with the exact tool name and exact arguments you intend to use."
                      "After approval is granted, call the approved tool with exactly those arguments. If approval is denied, do not retry that tool call."]
                     "\n")}
         {:name "Context" :content context-block}
         {:name "Available Capabilities" :content preset-block}
         {:name "Capability Guidance" :content capability-guidance}]))

    (fn fail [message]
      (close-live-events)
      (ctx.turn:fail message))

    (fn send-prompt [opencode-session]
      (local session-id opencode-session.id)
      (if (not session-id)
          (fail "OpenCode session response missing id")
          (do
            (local turn-msg-id (.. "oc-msg-" (Uuid.v4)))
            (ignore-message-id! stream-state turn-msg-id)
            (ctx.turn:set-cancel
              (fn []
                (close-live-events)
                (opencode.session.abort session-id
                  (fn [_resp] nil))))
            (if (ctx.turn:cancelled?)
                (fail "turn cancelled")
                (do
                  (set live-events (subscribe-live-events opencode ctx session session-id stream-state fail))
                  (local prompt-body {:parts [{:type "text" :text input}]
                                      :system system-prompt
                                      :messageId turn-msg-id})
                  (when model
                    (tset prompt-body :model model))
                  (local (ok err)
                    (pcall opencode.session.prompt session-id prompt-body
                           (fn [resp]
                             (if (ctx.turn:cancelled?)
                                 nil
                                 (not (and resp resp.ok))
                                 (fail (.. "OpenCode prompt failed: " (response-error resp "unknown error")))
                                 (do
                                   (close-live-events)
                                   (append-audit-then-assistant opencode ctx session stream-state session-id turn-msg-id resp model fail))))))
                  (when (not ok)
                    (fail (.. "OpenCode prompt submit failed: " (tostring err)))))))))

    (fn create-session []
      (local (ok err)
        (pcall opencode.session.create
               {:title (.. "Agent turn " (os.time))}
               (fn [resp]
                 (if (not (and resp resp.ok))
                     (fail (.. "Failed to create OpenCode session: "
                               (response-error resp "session creation failed")))
                     (do
                       (local created (response-data resp))
                       (if (not created.id)
                           (fail "OpenCode create response missing session id")
                           (do
                             (tset session.data :opencode-session-id created.id)
                             (send-prompt created))))))))
      (when (not ok)
        (fail (.. "OpenCode session create submit failed: " (tostring err)))))

    (fn resolve-session []
      (local opencode-session-id (. session.data :opencode-session-id))
      (if opencode-session-id
          (do
            (local (ok err)
              (pcall opencode.session.get opencode-session-id
                     (fn [resp]
                       (if (and resp resp.ok)
                           (send-prompt (response-data resp))
                           (do
                             (tset session.data :opencode-session-id nil)
                             (create-session))))))
            (when (not ok)
              (fail (.. "OpenCode session get submit failed: " (tostring err)))))
          (create-session)))

    (resolve-session))

  {:id "space-agent"
   :name "Space Agent"
   :run run})

(fn register [registry deps]
  (registry:register "space-agent" (fn [_registry-deps] (build-agent deps))))

{:SpaceAgent build-agent
 :register register}
