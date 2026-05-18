;; Agent runner — owns session lifecycle, active-turn bookkeeping, persistence, and callback delivery.

(local SessionMod (require :llm/agent/session))
(local TurnMod (require :llm/agent/turn))
(local Uuid (require :uuid))
(local fs (require :fs))

(fn new-item-id []
  (.. "itm-" (Uuid.v4)))

(fn now []
  (os.time))

(fn AgentRunner [opts]
  (local data-dir (or opts.data-dir (error "AgentRunner requires :data-dir")))
  (local registry (or opts.registry (error "AgentRunner requires :registry")))
  (local deps (or opts.deps (error "AgentRunner requires :deps")))

  (assert (= (type data-dir) "string") "data-dir must be a string")

  (var active-turns {})  ;; session-id -> {:handle :controller}

  (fn ensure-data-dir []
    (when (not (fs.exists data-dir))
      (fs.create-dirs data-dir)))

  (fn create-session [self agent-id]
    (assert (= (type agent-id) "string") "agent-id must be a string")
    (ensure-data-dir)
    (SessionMod.create-session agent-id data-dir))

  (fn get-session [self id]
    (assert (= (type id) "string") "session id must be a string")
    (SessionMod.load-session id data-dir))

  (fn cancel-active-turn [self session-id]
    (local active (. active-turns session-id))
    (when active
      (active.handle:cancel)
      (tset active-turns session-id nil)))

  (fn build-context [self session]
    (do
      (local callbacks {:on-item (or deps.on-item nil)
                        :on-finish (or deps.on-finish nil)
                        :on-error (or deps.on-error nil)})
      {:app deps.app
       :presets deps.presets
       :tools deps.tools
       :approvals deps.approvals
       :agents deps.agents
       :providers deps.providers
       :callbacks callbacks
       :turn nil  ;; set after TurnPair creation
       :session-id session.id
       :data-dir data-dir}))

  (fn run-turn [self session-id input callbacks]
    (assert (= (type session-id) "string") "session-id must be a string")
    (assert (= (type input) "string") "input must be a string")
    (local user-callbacks (or callbacks {}))
    (ensure-data-dir)

    ;; 1. Load session
    (local session (SessionMod.load-session session-id data-dir))
    (assert session (.. "session not found: " session-id))

    ;; 2. Resolve agent
    (local agent (registry:get session.agent-id))
    (assert agent (.. "agent not found: " session.agent-id))

    ;; 3. Cancel existing active turn
    (cancel-active-turn self session-id)

    ;; 4. Append and persist user message item
    (local user-item {:id (new-item-id)
                      :type :message
                      :role :user
                      :content input
                      :created-at (now)})
    (SessionMod.append-item session user-item)
    (SessionMod.save-session session data-dir)

    ;; 5. Create turn pair
    (local (handle controller)
      (TurnMod.TurnPair session.id
        {:on-item (fn [item]
                    (SessionMod.append-item session item)
                    (SessionMod.save-session session data-dir)
                    (when user-callbacks.on-item
                      (user-callbacks.on-item item)))
         :on-update (fn [item-id updates]
                      (when user-callbacks.on-update
                        (user-callbacks.on-update item-id updates)))
         :on-status (fn [status-info]
                      (set session.status :running)
                      (SessionMod.save-session session data-dir)
                      (when user-callbacks.on-status
                        (user-callbacks.on-status status-info)))
         :on-complete (fn [result-info]
                        (set session.status :idle)
                        (SessionMod.save-session session data-dir)
                        (tset active-turns session-id nil)
                        (when user-callbacks.on-complete
                          (user-callbacks.on-complete result-info)))
         :on-error (fn [error-info]
                     (set session.status :idle)
                     (SessionMod.append-item session
                       {:id (new-item-id)
                        :type :error
                        :error error-info.error
                        :created-at (now)})
                     (SessionMod.save-session session data-dir)
                     (tset active-turns session-id nil)
                     (when user-callbacks.on-error
                       (user-callbacks.on-error error-info)))
         :persist (fn []
                    (SessionMod.save-session session data-dir))}))

    ;; 6. Store active turn
    (tset active-turns session-id {:handle handle :controller controller})

    ;; 7. Build context
    (local ctx (build-context self session))
    (tset ctx :turn controller)

    ;; 8. Call agent:run
    (handle:start)
    (local (ok err) (pcall agent.run agent input session ctx))
    (when (not ok)
      (controller:fail (tostring err)))

    ;; 9. Return handle immediately
    handle)

  (fn cancel-turn [self session-id]
    (cancel-active-turn self session-id)
    true)

  (fn delete-session [self id]
    (cancel-active-turn self id)
    (SessionMod.delete-session id data-dir))

  (fn list-sessions [self]
    (SessionMod.list-sessions data-dir))

  (fn flush [self]
    ;; No-op in v1 — sessions are saved eagerly
    nil)

  (fn drop [self]
    ;; Cancel all active turns
    (each [session-id _active (pairs active-turns)]
      (cancel-active-turn self session-id))
    (set active-turns {}))

  {:create-session create-session
   :get-session get-session
   :run-turn run-turn
   :cancel-turn cancel-turn
   :delete-session delete-session
   :list-sessions list-sessions
   :flush flush
   :drop drop})

{:AgentRunner AgentRunner}
