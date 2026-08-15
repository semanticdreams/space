(local WorkflowEvents (require :llm/agent/workflow-events))
(local WorkflowTemplate (require :llm/agent/workflow-template))
(local TurnMod (require :llm/agent/turn))
(local Uuid (require :uuid))
(local fs (require :fs))

(fn now []
  (os.time))

(fn new-item-id []
  (.. "itm-" (Uuid.v4)))

(fn table-or-empty [value]
  (if (= value nil) {} value))

(fn array-or-empty [value]
  (if (= value nil) [] value))

(fn bridge-status [deps]
  (when deps.opencode-mcp-bridge
    (deps.opencode-mcp-bridge:status)))

(fn copy-table [value]
  (if (not (= (type value) "table"))
      value
      (do
        (local out {})
        (each [k v (pairs value)]
          (tset out k (copy-table v)))
        out)))

(fn merge-runtime-context [run-id artifact-root deps]
  (local existing (copy-table (table-or-empty deps.runtime-context)))
  (local status (bridge-status deps))
  (local artifact-dir (fs.join-path artifact-root run-id))
  (local report-path (fs.join-path artifact-dir "report.md"))
  (when (not (fs.exists artifact-dir))
    (fs.create-dirs artifact-dir))
  {:agent-session-id run-id
   :artifact-dir artifact-dir
   :report-path report-path
   :mcp-endpoint (if (and status status.url) status.url existing.mcp-endpoint)
   :opencode-server-url existing.opencode-server-url
   :opencode-session-id existing.opencode-session-id
   :last-live-connection-at existing.last-live-connection-at
   :validation-mode (if existing.validation-mode existing.validation-mode "disk-only")})

(fn session-data [run-id artifact-root deps]
  {:runtime-context (merge-runtime-context run-id artifact-root deps)})

(fn projected-session [store run]
  (when (and run
             run.context
             run.context.agent-session?
             (not run.context.agent-session-deleted?))
    (WorkflowEvents.project-session run)))

(fn summary-sort [a b]
  (local a-updated (if a.updated-at a.updated-at 0))
  (local b-updated (if b.updated-at b.updated-at 0))
  (if (= a-updated b-updated)
      (< a.id b.id)
      (> a-updated b-updated)))

(fn resolve-agent [self agent-id]
  (if self.get-agent
      (self.get-agent agent-id)
      (and self.registry self.registry.get (self.registry:get agent-id))))

(fn append-status! [self run-id status]
  (WorkflowEvents.append-status self.workflow-store run-id status {})
  (local run (self.workflow-store:get-run run-id))
  (local context (table-or-empty run.context))
  (tset context :status status)
  (self.workflow-store:update-run run-id {:context context})
  status)

(fn persist-session-data! [self session-id session]
  (local data (copy-table (table-or-empty session.data)))
  (WorkflowEvents.append-session-data-updated self.workflow-store session-id data)
  (local run (assert (self.workflow-store:get-run session-id) (.. "session not found: " session-id)))
  (local context (copy-table (table-or-empty run.context)))
  (tset context :data data)
  (self.workflow-store:update-run session-id {:context context})
  data)

(fn update-context! [self run-id updates]
  (local run (assert (self.workflow-store:get-run run-id) (.. "session not found: " run-id)))
  (local context (copy-table (table-or-empty run.context)))
  (each [k v (pairs (table-or-empty updates))]
    (tset context k v))
  (self.workflow-store:update-run run-id {:context context}))

(fn ensure-artifact-root [self]
  (when (not (fs.exists self.artifact-root))
    (fs.create-dirs self.artifact-root)))

(fn get-session [self session-id]
  (assert (= (type session-id) "string") "session id must be a string")
  (projected-session self.workflow-store (self.workflow-store:get-run session-id)))

(fn cancel-active-turn [self session-id]
  (local active (. self.active-turns session-id))
  (when active
    (active.handle:cancel)
    (tset self.active-turns session-id nil)))

(fn build-agent-context [self session controller]
  (local deps self.deps)
  {:app deps.app
   :presets deps.presets
   :tools deps.tools
   :approvals deps.approvals
   :agents deps.agents
   :providers deps.providers
   :callbacks {:on-item deps.on-item
               :on-finish deps.on-finish
               :on-error deps.on-error}
   :turn controller
   :session session
   :session-id session.id
   :artifacts {:root self.artifact-root
               :session-dir session.data.runtime-context.artifact-dir
               :report-path session.data.runtime-context.report-path}
   :runtime-context session.data.runtime-context
   :data-dir self.artifact-root})

(fn runtime-cancel-agent-turn [runtime _ctx _state]
  (cancel-active-turn runtime.runner runtime.session-id))

(fn run-agent-turn [runtime ctx wait-result _state]
  (local self runtime.runner)
  (local input (assert wait-result.input "agent user input resume requires :input"))
  (local session-id ctx.run-id)
  (local session (assert (get-session self session-id) (.. "session not found: " session-id)))
  (local agent (assert (resolve-agent self session.agent-id) (.. "agent not found: " (tostring session.agent-id))))
  (local active (assert (. self.active-turns session-id) "active turn missing during workflow resume"))
  (tset active :session session)
  (local agent-ctx (build-agent-context self session active.controller))
  (local (ok err) (pcall agent.run agent input session agent-ctx))
  (when (not ok)
    (active.controller:fail (tostring err)))
  (ctx:wait :agent-user-input {:agent-id session.agent-id}))

(fn item-exists? [session item-id]
  (var existed false)
  (each [_ existing (ipairs (if session session.items []))]
    (when (= existing.id item-id)
      (set existed true)))
  existed)

(fn make-turn-pair [self session-id session user-callbacks]
  (TurnMod.TurnPair session-id
    {:on-item (fn [item]
                (WorkflowEvents.append-item self.workflow-store session-id item)
                (when user-callbacks.on-item
                  (user-callbacks.on-item item)))
     :on-upsert (fn [item]
                  (local existed (item-exists? (get-session self session-id) item.id))
                  (WorkflowEvents.append-upsert self.workflow-store session-id item)
                  (if existed
                      (when user-callbacks.on-update
                        (user-callbacks.on-update item.id item))
                      (when user-callbacks.on-item
                        (user-callbacks.on-item item))))
     :on-update (fn [item-id updates]
                  (WorkflowEvents.append-update self.workflow-store session-id item-id updates)
                  (when user-callbacks.on-update
                    (user-callbacks.on-update item-id updates)))
     :on-status (fn [status-info]
                  (append-status! self session-id :running)
                  (when user-callbacks.on-status
                    (user-callbacks.on-status status-info)))
     :on-complete (fn [result-info]
                    (append-status! self session-id :idle)
                    (tset self.active-turns session-id nil)
                    (when user-callbacks.on-complete
                      (user-callbacks.on-complete result-info)))
     :on-error (fn [error-info]
                 (WorkflowEvents.append-item self.workflow-store session-id
                   {:id (new-item-id)
                    :type :error
                    :error error-info.error
                    :created-at (now)})
                 (append-status! self session-id :idle)
                 (tset self.active-turns session-id nil)
                 (when user-callbacks.on-error
                   (user-callbacks.on-error error-info)))
      :persist (fn []
                 (local active (. self.active-turns session-id))
                 (persist-session-data! self session-id (if active active.session session)))}))

(fn create-session [self agent-id]
  (assert (= (type agent-id) "string") "agent-id must be a string")
  (ensure-artifact-root self)
  (WorkflowTemplate.ensure-definition {:workflow-store self.workflow-store
                                       :code-store self.code-store
                                       :agent-id agent-id})
  (local run (self.workflow-runner:start-run WorkflowTemplate.definition-id {} {:agent-session? true
                                                                                :agent-id agent-id
                                                                                :status :idle
                                                                                :data {}}))
  (local data (session-data run.id self.artifact-root self.deps))
  (update-context! self run.id {:data data})
  (WorkflowEvents.append-session-created self.workflow-store run.id {:agent-id agent-id
                                                                     :data data})
  (append-status! self run.id :idle)
  (self.workflow-runner:tick-run run.id {:max-steps 1})
  (assert (get-session self run.id) "created workflow session should project"))

(fn list-sessions [self]
  (local summaries [])
  (each [_ run (ipairs (self.workflow-store:list-runs {:definition-id WorkflowTemplate.definition-id}))]
    (local session (projected-session self.workflow-store run))
    (when session
      (table.insert summaries (WorkflowEvents.session-summary session))))
  (table.sort summaries summary-sort)
  summaries)

(fn run-turn [self session-id input callbacks]
  (assert (= (type session-id) "string") "session-id must be a string")
  (assert (= (type input) "string") "input must be a string")
  (local session (assert (get-session self session-id) (.. "session not found: " session-id)))
  (assert (resolve-agent self session.agent-id) (.. "agent not found: " session.agent-id))
  (cancel-active-turn self session-id)
  (WorkflowEvents.append-item self.workflow-store session-id {:id (new-item-id)
                                                             :type :message
                                                             :role :user
                                                             :content input
                                                             :created-at (now)})
  (local user-callbacks (table-or-empty callbacks))
  (local (handle controller) (make-turn-pair self session-id session user-callbacks))
  (tset self.active-turns session-id {:handle handle :controller controller})
  (handle:start)
  (local runtime {:runner self
                  :session-id session-id
                  :run-agent-turn run-agent-turn
                  :cancel-agent-turn runtime-cancel-agent-turn})
  (local (resume-ok resume-err)
    (pcall self.workflow-runner.resume-step self.workflow-runner session-id WorkflowTemplate.step-id {:kind :agent-user-input :input input} {:runtime runtime}))
  (when (not resume-ok)
    (controller:fail (tostring resume-err)))
  handle)

(fn cancel-turn [self session-id]
  (assert (= (type session-id) "string") "session-id must be a string")
  (cancel-active-turn self session-id)
  true)

(fn delete-session [self session-id]
  (assert (= (type session-id) "string") "session-id must be a string")
  (cancel-active-turn self session-id)
  (local run (self.workflow-store:get-run session-id))
  (when run
    (local context (copy-table (table-or-empty run.context)))
    (tset context :agent-session-deleted? true)
    (self.workflow-store:update-run session-id {:context context}))
  nil)

(fn flush [_self]
  nil)

(fn drop [self]
  (each [session-id _active (pairs self.active-turns)]
    (cancel-active-turn self session-id))
  (set self.active-turns {})
  nil)

(fn WorkflowAgentRunner [opts]
  (local options (table-or-empty opts))
  (local workflow-store (assert options.workflow-store "WorkflowAgentRunner requires :workflow-store"))
  (local workflow-runner (assert options.workflow-runner "WorkflowAgentRunner requires :workflow-runner"))
  (local code-store (assert options.code-store "WorkflowAgentRunner requires :code-store"))
  (local registry options.registry)
  (local get-agent options.get-agent)
  (assert (or registry get-agent) "WorkflowAgentRunner requires :registry or :get-agent")
  (local artifact-root (assert options.artifact-root "WorkflowAgentRunner requires :artifact-root"))
  (local deps (assert options.deps "WorkflowAgentRunner requires :deps"))
  (assert deps.app "WorkflowAgentRunner requires deps.app")
  (assert deps.presets "WorkflowAgentRunner requires deps.presets")
  (assert deps.tools "WorkflowAgentRunner requires deps.tools")
  (assert deps.approvals "WorkflowAgentRunner requires deps.approvals")
  (assert deps.agents "WorkflowAgentRunner requires deps.agents")
  (assert deps.providers "WorkflowAgentRunner requires deps.providers")
  {:workflow-store workflow-store
   :workflow-runner workflow-runner
   :code-store code-store
   :registry registry
   :get-agent get-agent
   :artifact-root artifact-root
   :deps deps
   :active-turns {}
   :create-session create-session
   :get-session get-session
   :list-sessions list-sessions
   :run-turn run-turn
   :cancel-turn cancel-turn
   :delete-session delete-session
   :flush flush
   :drop drop})

{:WorkflowAgentRunner WorkflowAgentRunner}
