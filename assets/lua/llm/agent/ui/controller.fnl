;; AgentPanelController — bridges AgentRunner/session events into a view model.
;; The controller owns state and runner interactions; widgets render state and emit user intents.

(local Signal (require :signal))

(fn AgentPanelController [opts]
  (assert opts.runner "AgentPanelController requires :runner")
  (assert opts.registry "AgentPanelController requires :registry")
  (assert opts.approvals "AgentPanelController requires :approvals")
  (assert opts.presets "AgentPanelController requires :presets")

  (local runner opts.runner)
  (local registry opts.registry)
  (local approvals opts.approvals)
  (local presets opts.presets)

  (var state {:agents []
              :active-agent-id nil
              :sessions []
              :active-session-id nil
              :items []
              :active-turn nil
              :expanded-items {}
              :pending-approval nil
              :last-error nil
              :preset-rows []
              :preset-groups []
              :expanded-preset-groups {}
              :expanded-presets {}})

  (var change-signal (Signal))
  (var approval-change-signal (Signal))
  (var approval-request-listener nil)
  (var preset-change-listener nil)
  (var preset-registry-listener nil)

  (fn notify []
    (change-signal:emit state))

  (fn same-approval? [a b]
    (or (= a b)
        (and a b a.id b.id (= a.id b.id))))

  (fn set-pending-approval [self request]
    (when (not (same-approval? state.pending-approval request))
      (set state.pending-approval request)
      (approval-change-signal:emit request)
      (self:notify)))

  (fn sync-pending-approval [self request]
    (if request
        (self:set-pending-approval request)
        (and approvals approvals.list-pending)
        (do
          (local pending (approvals:list-pending))
          (self:set-pending-approval (. pending 1)))
        (self:set-pending-approval nil)))

  (fn attach-approval-listener [self]
    (when (and approvals approvals.requested (not approval-request-listener))
      (set approval-request-listener
           (approvals.requested:connect
             (fn [request]
               (self:sync-pending-approval request))))))

  (fn load-agents [self]
    (local agents (registry:list))
    (set state.agents agents)
    (when (and (not state.active-agent-id) (> (length agents) 0))
      (set state.active-agent-id (. agents 1 :id)))
    (self:notify))

  (fn load-sessions [self]
    (when state.active-agent-id
      (local all-sessions (runner:list-sessions))
      (local filtered [])
      (each [_ s (ipairs all-sessions)]
        (when (= s.agent-id state.active-agent-id)
          (table.insert filtered s)))
      (table.sort filtered (fn [a b] (> (or a.updated-at 0) (or b.updated-at 0))))
      (set state.sessions filtered)
      (self:notify)))

  (fn ensure-first-session [self]
    (when state.active-agent-id
      (if (= (length state.sessions) 0)
          (let [session (runner:create-session state.active-agent-id)]
            (self:load-sessions)
            (self:select-session session.id))
          (not state.active-session-id)
          (let [first-session (. state.sessions 1)]
            (self:select-session first-session.id)))))

  (fn load-session-items [self]
    (when state.active-session-id
      (local session (runner:get-session state.active-session-id))
      (when session
        (set state.items (or session.items []))
        (self:notify))))

  (fn reload-active-session [self]
    (self:load-sessions)
    (self:load-session-items))

  (fn find-state-item [item-id]
    (var found nil)
    (each [_ item (ipairs (or state.items []))]
      (when (= item.id item-id)
        (set found item)))
    found)

  (fn apply-item-update [self item-id updates]
    (local item (find-state-item item-id))
    (if item
        (do
          (each [k v (pairs updates)]
            (tset item k v))
          (self:notify))
        (reload-active-session self)))

  (fn select-agent [self agent-id]
    (set state.active-agent-id agent-id)
    (set state.active-session-id nil)
    (set state.items [])
    (set state.active-turn nil)
    (self:load-sessions)
    (self:ensure-first-session))

  (fn select-session [self session-id]
    (set state.active-session-id session-id)
    (set state.active-turn nil)
    (set state.pending-approval nil)
    (self:load-session-items))

  (fn new-session [self]
    (when state.active-agent-id
      (local session (runner:create-session state.active-agent-id))
      (self:load-sessions)
      (self:select-session session.id)))

  (fn send [self text]
    (when (and state.active-session-id text (> (length text) 0))
      (set state.last-error nil)
      (local handle
        (runner:run-turn state.active-session-id text
          {:on-item (fn [_item]
                      (reload-active-session self))
           :on-update (fn [item-id updates]
                        (self:apply-item-update item-id updates))
           :on-status (fn [status-info]
                         (set state.active-turn status-info)
                         (self:load-sessions))
           :on-complete (fn [_result-info]
                          (set state.active-turn nil)
                          (reload-active-session self))
           :on-error (fn [error-info]
                       (set state.active-turn nil)
                       (set state.last-error error-info.error)
                       (reload-active-session self))}))
      (when handle
        (local status (and handle.status (handle:status)))
        (if (= status :running)
            (set state.active-turn {:id handle.id
                                    :session-id state.active-session-id
                                    :status status})
            (when (not status)
              (set state.active-turn {:id handle.id
                                      :session-id state.active-session-id
                                      :status :running})))
        (self:load-session-items))
      handle))

  (fn stop [self]
    (when state.active-session-id
      (runner:cancel-turn state.active-session-id)
      (set state.active-turn nil)
      (self:notify)))

  (fn retry [self]
    (when (and state.active-session-id state.items)
      (var last-user-input nil)
      (for [i (length state.items) 1 -1]
        (local item (. state.items i))
        (when (and (= item.type :message) (= item.role :user))
          (set last-user-input item.content)
          (lua "break")))
      (when last-user-input
        (self:send last-user-input))))

  (fn approve-pending [self opts]
    (local request state.pending-approval)
    (when request
      (if request.approve
          (request:approve opts)
          (when approvals.record-decision
            (approvals:record-decision {:risk request.risk
                                        :reason request.reason
                                        :decision :approved
                                        :request-id request.id})))
      (self:set-pending-approval nil)))

  (fn approve-pending-always [self]
    (self:approve-pending {:always true}))

  (fn deny-pending [self]
    (local request state.pending-approval)
    (when request
      (if request.deny
          (request:deny)
          (when approvals.record-decision
            (approvals:record-decision {:risk request.risk
                                        :reason request.reason
                                        :decision :denied
                                        :request-id request.id})))
      (self:set-pending-approval nil)))

  (fn toggle-expanded [self item-id]
    (if (. state.expanded-items item-id)
        (tset state.expanded-items item-id nil)
        (tset state.expanded-items item-id true))
    (self:notify))

  (fn is-expanded? [self item-id]
    (not (not (. state.expanded-items item-id))))

  (fn load-presets [self]
    (local all-presets (presets.registry:list))
    (local active-presets (presets:get-active-presets))
    (local overrides (presets:get-overrides))

    (local active-by-name {})
    (each [_ ap (ipairs active-presets)]
      (tset active-by-name ap.name {:active? true :reason ap.reason}))

    (local rows [])
    (local group-names {})
    (each [_ preset (ipairs all-presets)]
      (local group (or preset.group "other"))
      (tset group-names group true)
      (local override (. overrides preset.name))
      (local override-state (or (and override override.state) :auto))
      (local active-info (. active-by-name preset.name))
      (local active? (and active-info active-info.active?))
      (local active-reason (and active-info active-info.reason))
      (table.insert rows
        {:name preset.name
         :group group
         :risk preset.risk
         :default-state preset.default-state
         :contexts preset.contexts
         :tool-ids preset.tool-ids
         :tool-count (length preset.tool-ids)
         :override-state override-state
         :active? active?
         :active-reason active-reason}))

    (local groups [])
    (each [group-name _ (pairs group-names)]
      (table.insert groups group-name))
    (table.sort groups)
    (table.sort rows (fn [a b] (< a.name b.name)))
    (set state.preset-rows rows)
    (set state.preset-groups groups)
    (self:notify))

  (fn set-preset-override [self name state]
    (presets:set-override name state)
    (self:load-presets))

  (fn reset-preset-overrides [self]
    (each [name _override (pairs (presets:get-overrides))]
      (presets:set-override name :auto))
    (self:load-presets))

  (fn get-preset-group-override-state [self group-name]
    (var group-state nil)
    (each [_ row (ipairs state.preset-rows)]
      (when (= row.group group-name)
        (if (= group-state nil)
            (set group-state row.override-state)
            (when (not (= group-state row.override-state))
              (set group-state :mixed)))))
    (or group-state :auto))

  (fn toggle-group-override [self group-name]
    (local all-presets (presets.registry:list))
    (local target-state
      (let [current (self:get-preset-group-override-state group-name)]
        (if (= current :auto) :on
            (= current :on) :off
            :auto)))
    (each [_ preset (ipairs all-presets)]
      (when (= (or preset.group "other") group-name)
        (presets:set-override preset.name target-state)))
    (self:load-presets))

  (fn toggle-preset-group-expanded [self group-name]
    (if (. state.expanded-preset-groups group-name)
        (tset state.expanded-preset-groups group-name nil)
        (tset state.expanded-preset-groups group-name true))
    (self:notify))

  (fn is-preset-group-expanded? [self group-name]
    (not (not (. state.expanded-preset-groups group-name))))

  (fn toggle-preset-expanded [self preset-name]
    (if (. state.expanded-presets preset-name)
        (tset state.expanded-presets preset-name nil)
        (tset state.expanded-presets preset-name true))
    (self:notify))

  (fn is-preset-expanded? [self preset-name]
    (not (not (. state.expanded-presets preset-name))))

  (fn get-active-agent [self]
    (var found nil)
    (each [_ a (ipairs state.agents)]
      (when (= a.id state.active-agent-id)
        (set found a)))
    found)

  (fn get-active-session [self]
    (var found nil)
    (each [_ s (ipairs state.sessions)]
      (when (= s.id state.active-session-id)
        (set found s)))
    found)

  (fn drop [self]
    (when approval-request-listener
      (when (and approvals approvals.requested)
        (approvals.requested:disconnect approval-request-listener true))
      (set approval-request-listener nil))
    (when preset-change-listener
      (presets:remove-on-change preset-change-listener)
      (set preset-change-listener nil))
    (when preset-registry-listener
      (presets.registry:remove-on-change preset-registry-listener)
      (set preset-registry-listener nil))
    (set state {:agents []
                :active-agent-id nil
                :sessions []
                :active-session-id nil
                :items []
                :active-turn nil
                :expanded-items {}
                :pending-approval nil
                :last-error nil
                :preset-rows []
                :preset-groups []
                :expanded-preset-groups {}
                :expanded-presets {}})
    (change-signal:clear)
    (approval-change-signal:clear))

  (fn init [self]
    (self:attach-approval-listener)
    (when (not preset-change-listener)
      (set preset-change-listener
           (presets:add-on-change
             (fn []
               (self:load-presets)))))
    (when (not preset-registry-listener)
      (set preset-registry-listener
           (presets.registry:add-on-change
             (fn []
               (self:load-presets)))))
    (self:load-agents)
    (self:load-sessions)
    (self:ensure-first-session)
    (self:sync-pending-approval nil)
    (self:load-presets))

  (local controller
    {:init init
     :state state
     :change-signal change-signal
     :approval-change-signal approval-change-signal
     :notify notify
     :set-pending-approval set-pending-approval
     :sync-pending-approval sync-pending-approval
     :attach-approval-listener attach-approval-listener
     :load-agents load-agents
     :load-sessions load-sessions
     :ensure-first-session ensure-first-session
     :load-session-items load-session-items
     :apply-item-update apply-item-update
     :select-agent select-agent
     :select-session select-session
     :new-session new-session
     :send send
     :stop stop
     :retry retry
     :approve-pending approve-pending
     :approve-pending-always approve-pending-always
     :deny-pending deny-pending
     :toggle-expanded toggle-expanded
     :is-expanded? is-expanded?
     :load-presets load-presets
     :set-preset-override set-preset-override
     :reset-preset-overrides reset-preset-overrides
     :toggle-group-override toggle-group-override
     :get-preset-group-override-state get-preset-group-override-state
     :toggle-preset-group-expanded toggle-preset-group-expanded
     :is-preset-group-expanded? is-preset-group-expanded?
     :toggle-preset-expanded toggle-preset-expanded
     :is-preset-expanded? is-preset-expanded?
     :get-active-agent get-active-agent
     :get-active-session get-active-session
     :drop drop})

  controller)

{:AgentPanelController AgentPanelController}
