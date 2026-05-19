;; AgentPanelController — bridges AgentRunner/session events into a view model.
;; The controller owns state and runner interactions; widgets render state and emit user intents.

(local Signal (require :signal))

(fn AgentPanelController [opts]
  (assert opts.runner "AgentPanelController requires :runner")
  (assert opts.registry "AgentPanelController requires :registry")
  (assert opts.approvals "AgentPanelController requires :approvals")

  (local runner opts.runner)
  (local registry opts.registry)
  (local approvals opts.approvals)

  (var state {:agents []
              :active-agent-id nil
              :sessions []
              :active-session-id nil
              :items []
              :active-turn nil
              :expanded-items {}
              :pending-approval nil
              :last-error nil})

  (var change-signal (Signal))
  (var approval-change-signal (Signal))
  (var approval-request-listener nil)

  (fn notify []
    (change-signal:emit state))

  (fn set-pending-approval [self request]
    (set state.pending-approval request)
    (approval-change-signal:emit request)
    (self:notify))

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
                      (self:load-session-items))
           :on-update (fn [_item-id _updates]
                        (self:notify))
           :on-status (fn [status-info]
                        (set state.active-turn status-info)
                        (self:notify))
           :on-complete (fn [_result-info]
                          (set state.active-turn nil)
                          (self:load-session-items))
           :on-error (fn [error-info]
                       (set state.active-turn nil)
                       (set state.last-error error-info.error)
                       (self:load-session-items))}))
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

  (fn approve-pending [self]
    (local request state.pending-approval)
    (when request
      (if request.approve
          (request:approve)
          (when approvals.record-decision
            (approvals:record-decision {:risk request.risk
                                        :reason request.reason
                                        :decision :approved
                                        :request-id request.id})))
      (self:set-pending-approval nil)))

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
    (set state {:agents []
                :active-agent-id nil
                :sessions []
                :active-session-id nil
                :items []
                :active-turn nil
                :expanded-items {}
                :pending-approval nil
                :last-error nil})
    (change-signal:clear)
    (approval-change-signal:clear))

  (fn init [self]
    (self:attach-approval-listener)
    (self:load-agents)
    (self:load-sessions)
    (self:ensure-first-session)
    (self:sync-pending-approval nil))

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
     :select-agent select-agent
     :select-session select-session
     :new-session new-session
     :send send
     :stop stop
     :retry retry
     :approve-pending approve-pending
     :deny-pending deny-pending
     :toggle-expanded toggle-expanded
     :is-expanded? is-expanded?
     :get-active-agent get-active-agent
     :get-active-session get-active-session
     :drop drop})

  controller)

{:AgentPanelController AgentPanelController}
