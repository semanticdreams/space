;; SpaceAgent — the initial drawing/scene/graph/app assistant using OpenCode.
;; Creates one OpenCode session per turn (or reuses from session.data).

(local Uuid (require :uuid))
(local json (require :json))

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
      part.call_id
      part.call-id
      part.id
      (.. "opencode-tool:" (opencode-message-id message "message") ":" (tostring index))))

(fn tool-arguments-json [part]
  (local args (or part.input part.args part.arguments part.parameters {}))
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
      (tset existing (.. item.type ":" call-id) true)))
  existing)

(fn append-tool-call-item [ctx existing message message-index part part-index]
  (local tool-name (or part.tool (error "OpenCode tool part missing tool name")))
  (local call-id (tool-call-id message part part-index))
  (local call-key (.. "tool-call:" call-id))
  (if (. existing call-key)
      0
      (do
        (ctx.turn:append-item
          {:id (new-item-id)
           :type "tool-call"
           :name tool-name
           :arguments (tool-arguments-json part)
           :call-id call-id
           :parent-id (opencode-message-id message (.. "opencode-message-" message-index))
           :provider "opencode"
           :created-at (now)})
        (tset existing call-key true)
        1)))

(fn append-tool-result-item [ctx existing part part-index message]
  (if (not (and part.state (terminal-tool-status? part.state.status)))
      0
      (do
        (local tool-name (or part.tool (error "OpenCode tool part missing tool name")))
        (local call-id (tool-call-id message part part-index))
        (local result-key (.. "tool-result:" call-id))
        (if (. existing result-key)
            0
            (do
              (ctx.turn:append-item
                {:id (new-item-id)
                 :type "tool-result"
                 :name tool-name
                 :output (tool-result-output part)
                 :call-id call-id
                 :parent-id call-id
                 :provider "opencode"
                 :is-error (not (= part.state.status "completed"))
                 :created-at (now)})
              (tset existing result-key true)
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

(fn append-assistant-response [ctx turn-msg-id resp requested-model]
  (local message (response-data resp))
  (local info (or message.info {}))
  (local parts (or message.parts []))
  (var content "")
  (each [_ part (ipairs parts)]
    (when (= part.type "text")
      (set content (.. content part.text))))
  (ctx.turn:append-item
    {:id (new-item-id)
     :type :message
     :role :assistant
     :content content
     :parent-id turn-msg-id
     :provider :opencode
     :model (or (and info.model info.model.modelID)
                (and requested-model requested-model.modelID)
                "opencode")
     :usage (or message.usage {})
     :created-at (now)})
  (ctx.turn:finish {:content content}))

(fn handle-messages-response [ctx session turn-msg-id prompt-resp requested-model fail messages-resp]
  (if (ctx.turn:cancelled?)
      nil
      (not (and messages-resp messages-resp.ok))
      (fail (.. "OpenCode messages fetch failed: "
                (response-error messages-resp "unknown error")))
      (do
        (local (ok err)
          (pcall (fn []
                   (append-tool-audit-items ctx session (response-data messages-resp))
                   (append-assistant-response ctx turn-msg-id prompt-resp requested-model))))
        (when (not ok)
          (fail (.. "OpenCode message audit persistence failed: " (tostring err)))))))

(fn append-audit-then-assistant [opencode ctx session session-id turn-msg-id resp requested-model fail]
  (if (not opencode.session.messages)
      (fail "OpenCode provider missing session.messages for agent audit persistence")
      (do
        (local (ok err)
          (pcall opencode.session.messages session-id
                 (fn [messages-resp]
                   (handle-messages-response ctx session turn-msg-id resp requested-model fail messages-resp))))
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

    ;; Build system prompt
    (local context-block (PromptUtils.format-context ctx))
    (local preset-block (PromptUtils.format-presets ctx.presets))
    (local capability-guidance (format-capability-guidance ctx.tools))
    (local system-prompt
      (PromptUtils.assemble-blocks
        [{:name "Instructions"
          :content "You are Space Agent. Help with drawing, graph, scene, and app tasks using only approved available tools."}
         {:name "Context" :content context-block}
         {:name "Available Capabilities" :content preset-block}
         {:name "Capability Guidance" :content capability-guidance}]))

    (fn fail [message]
      (ctx.turn:fail message))

    (fn send-prompt [opencode-session]
      (local session-id opencode-session.id)
      (if (not session-id)
          (fail "OpenCode session response missing id")
          (do
            (local turn-msg-id (.. "oc-msg-" (Uuid.v4)))
            (ctx.turn:set-cancel
              (fn []
                (opencode.session.abort session-id
                  (fn [_resp] nil))))
            (if (ctx.turn:cancelled?)
                (fail "turn cancelled")
                (do
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
                                 (append-audit-then-assistant opencode ctx session session-id turn-msg-id resp model fail)))))
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
