;; Agent panel tests

(local controller-mod (require :llm/agent/ui/controller))
(local AgentPanelController controller-mod.AgentPanelController)
(local registry-mod (require :llm/agent/registry))
(local AgentRegistry registry-mod.AgentRegistry)
(local approvals-mod (require :llm/agent/approvals))
(local AgentApprovals approvals-mod.AgentApprovals)

(local tests [])

(fn make-test-runner []
  (var sessions {})
  (var session-count 0)
  (var turns [])
  (var cancelled [])

  (fn create-session [self agent-id]
    (set session-count (+ session-count 1))
    (local id (.. "test-ses-" session-count))
    (local session {:id id
                    :agent-id agent-id
                    :status :idle
                    :items []
                    :data {}
                    :created-at (os.time)
                    :updated-at (os.time)})
    (tset sessions id session)
    session)

  (fn get-session [self id]
    (local s (. sessions id))
    (when (not s)
      (. sessions (.. "test-ses-" 1)))
    s)

  (fn list-sessions [self]
    (local result [])
    (each [_ session (pairs sessions)]
      (table.insert result {:id session.id
                            :agent-id session.agent-id
                            :status session.status
                            :item-count (length session.items)
                            :created-at session.created-at
                            :updated-at session.updated-at}))
    result)

  (fn run-turn [self session-id input callbacks]
    (local turn-id (.. "turn-" (length turns)))
    (local session (. sessions session-id))
    (when session
      (table.insert session.items {:id (.. "item-" (+ (length session.items) 1))
                                   :type :message
                                   :role :user
                                   :content input
                                   :created-at (os.time)})
      (set session.updated-at (os.time)))
    (table.insert turns {:session-id session-id :input input :callbacks callbacks})
    (when callbacks.on-status
      (callbacks.on-status {:id turn-id
                            :session-id session-id
                            :status :running}))
    {:id turn-id
     :session-id session-id
     :status (fn [] :running)
     :result (fn [] nil)
     :error (fn [] nil)
     :cancel (fn [] true)
     :running? (fn [] true)
     :wait (fn [] :running)
     :start (fn [] nil)})

  (fn cancel-turn [self session-id]
    (table.insert cancelled session-id)
    true)

  {:create-session create-session
   :get-session get-session
   :list-sessions list-sessions
   :run-turn run-turn
   :cancel-turn cancel-turn})

(fn test-controller-init []
  (local registry (AgentRegistry {:deps {}}))
  (fn make-agent [_deps] {:id "test-agent" :name "Test Agent" :run (fn [] nil)})
  (registry:register "test-agent" make-agent)
  (local approvals (AgentApprovals {:policy {:normal :auto}}))
  (local runner (make-test-runner))
  (local controller (AgentPanelController {:runner runner
                                             :registry registry
                                             :approvals approvals}))
  (controller:init)
  (assert (not (not controller.state.active-agent-id))
          "controller should have active agent after init")
  (assert (= (length controller.state.agents) 1) "should have one agent")
  (assert (= (length controller.state.sessions) 1) "should create first session")
  (assert (not (not controller.state.active-session-id))
          "should have active session"))

(fn test-controller-select-agent []
  (local registry (AgentRegistry {:deps {}}))
  (registry:register "agent-a" (fn [_deps] {:id "agent-a" :name "Agent A" :run (fn [] nil)}))
  (registry:register "agent-b" (fn [_deps] {:id "agent-b" :name "Agent B" :run (fn [] nil)}))
  (local approvals (AgentApprovals {:policy {:normal :auto}}))
  (local runner (make-test-runner))
  (local controller (AgentPanelController {:runner runner
                                             :registry registry
                                             :approvals approvals}))
  (controller:init)
  (assert (not (not controller.state.active-agent-id)) "should auto-select first agent")
  (controller:select-agent "agent-b")
  (assert (= controller.state.active-agent-id "agent-b") "should switch"))

(fn test-controller-send-text []
  (local registry (AgentRegistry {:deps {}}))
  (fn make-agent [_deps] {:id "test-agent" :name "Test Agent" :run (fn [] nil)})
  (registry:register "test-agent" make-agent)
  (local approvals (AgentApprovals {:policy {:normal :auto}}))
  (local runner (make-test-runner))
  (local controller (AgentPanelController {:runner runner
                                             :registry registry
                                             :approvals approvals}))
  (controller:init)
  (local handle (controller:send "draw a circle"))
  (assert handle "send should return a turn handle"))

(fn test-controller-send-loads_user_message []
  (local registry (AgentRegistry {:deps {}}))
  (fn make-agent [_deps] {:id "test-agent" :name "Test Agent" :run (fn [] nil)})
  (registry:register "test-agent" make-agent)
  (local approvals (AgentApprovals {:policy {:normal :auto}}))
  (local runner (make-test-runner))
  (local controller (AgentPanelController {:runner runner
                                             :registry registry
                                             :approvals approvals}))
  (controller:init)
  (controller:send "draw a circle")
  (assert (= (length controller.state.items) 1)
          "send should refresh the appended user message")
  (assert (= (. controller.state.items 1 :content) "draw a circle")
          "send should expose the submitted content")
  (assert controller.state.active-turn
          "send should mark the controller running immediately"))

(fn test-controller-stop []
  (local registry (AgentRegistry {:deps {}}))
  (fn make-agent [_deps] {:id "test-agent" :name "Test Agent" :run (fn [] nil)})
  (registry:register "test-agent" make-agent)
  (local approvals (AgentApprovals {:policy {:normal :auto}}))
  (local runner (make-test-runner))
  (local controller (AgentPanelController {:runner runner
                                             :registry registry
                                             :approvals approvals}))
  (controller:init)
  (controller:stop)
  (assert (not controller.state.active-turn) "stop should clear active turn"))

(fn test-controller-toggle-expanded []
  (local registry (AgentRegistry {:deps {}}))
  (fn make-agent [_deps] {:id "test-agent" :name "Test Agent" :run (fn [] nil)})
  (registry:register "test-agent" make-agent)
  (local approvals (AgentApprovals {:policy {:normal :auto}}))
  (local runner (make-test-runner))
  (local controller (AgentPanelController {:runner runner
                                             :registry registry
                                             :approvals approvals}))
  (controller:init)
  (controller:toggle-expanded "item-1")
  (assert (controller:is-expanded? "item-1") "should expand")
  (controller:toggle-expanded "item-1")
  (assert (not (controller:is-expanded? "item-1")) "should collapse"))

(fn test-controller-get-active-agent []
  (local registry (AgentRegistry {:deps {}}))
  (fn make-agent [_deps] {:id "test-agent" :name "Test Agent" :run (fn [] nil)})
  (registry:register "test-agent" make-agent)
  (local approvals (AgentApprovals {:policy {:normal :auto}}))
  (local runner (make-test-runner))
  (local controller (AgentPanelController {:runner runner
                                             :registry registry
                                             :approvals approvals}))
  (controller:init)
  (local agent (controller:get-active-agent))
  (assert agent "should return active agent")
  (assert (= agent.id "test-agent") "should be correct agent"))

(fn test-controller-get-active-session []
  (local registry (AgentRegistry {:deps {}}))
  (fn make-agent [_deps] {:id "test-agent" :name "Test Agent" :run (fn [] nil)})
  (registry:register "test-agent" make-agent)
  (local approvals (AgentApprovals {:policy {:normal :auto}}))
  (local runner (make-test-runner))
  (local controller (AgentPanelController {:runner runner
                                             :registry registry
                                             :approvals approvals}))
  (controller:init)
  (local session (controller:get-active-session))
  (assert session "should return active session"))

(fn test-controller-new-session []
  (local registry (AgentRegistry {:deps {}}))
  (fn make-agent [_deps] {:id "test-agent" :name "Test Agent" :run (fn [] nil)})
  (registry:register "test-agent" make-agent)
  (local approvals (AgentApprovals {:policy {:normal :auto}}))
  (local runner (make-test-runner))
  (local controller (AgentPanelController {:runner runner
                                             :registry registry
                                             :approvals approvals}))
  (controller:init)
  (local session-count (length controller.state.sessions))
  (controller:new-session)
  (assert (= (length controller.state.sessions) (+ session-count 1))
          "should create new session"))

(fn test-controller-drop-disconnects []
  (local registry (AgentRegistry {:deps {}}))
  (fn make-agent [_deps] {:id "test-agent" :name "Test Agent" :run (fn [] nil)})
  (registry:register "test-agent" make-agent)
  (local approvals (AgentApprovals {:policy {:normal :auto}}))
  (local runner (make-test-runner))
  (local controller (AgentPanelController {:runner runner
                                             :registry registry
                                             :approvals approvals}))
  (controller:init)
  (var signaled? false)
  (controller.change-signal.connect (fn [] (set signaled? true)))
  (controller:drop)
  (set signaled? false)
  (set controller.state.active-agent-id "something")
  (assert (not signaled?) "signal should not fire after drop"))

(fn test-controller-select-session-loads-items []
  (local registry (AgentRegistry {:deps {}}))
  (fn make-agent [_deps] {:id "test-agent" :name "Test Agent" :run (fn [] nil)})
  (registry:register "test-agent" make-agent)
  (local approvals (AgentApprovals {:policy {:normal :auto}}))
  (local runner (make-test-runner))
  (local controller (AgentPanelController {:runner runner
                                             :registry registry
                                             :approvals approvals}))
  (controller:init)
  (assert (= (length controller.state.items) 0) "new session should have no items"))

(fn test-controller-init-selects-existing-session []
  (local registry (AgentRegistry {:deps {}}))
  (fn make-agent [_deps] {:id "test-agent" :name "Test Agent" :run (fn [] nil)})
  (registry:register "test-agent" make-agent)
  (local approvals (AgentApprovals {:policy {:normal :auto}}))
  (local runner (make-test-runner))
  ;; Pre-create a session with items so load-sessions finds it before ensure-first-session.
  (local existing-session (runner:create-session "test-agent"))
  (table.insert existing-session.items {:id "item-1" :type :message :role :user :content "hello" :created-at (os.time)})
  (local controller (AgentPanelController {:runner runner
                                             :registry registry
                                             :approvals approvals}))
  (controller:init)
  (assert (= controller.state.active-session-id existing-session.id)
          "ensure-first-session should select the first existing session instead of creating a new one")
  (assert (= (length controller.state.items) 1)
          "session items should be loaded when existing session is selected"))

(fn test-controller_tracks_pending_approval []
  (local registry (AgentRegistry {:deps {}}))
  (fn make-agent [_deps] {:id "test-agent" :name "Test Agent" :run (fn [] nil)})
  (registry:register "test-agent" make-agent)
  (local approvals (AgentApprovals {:policy {:destructive :ask}}))
  (local runner (make-test-runner))
  (local controller (AgentPanelController {:runner runner
                                             :registry registry
                                             :approvals approvals}))
  (controller:init)
  (var approved-result nil)
  (approvals:request-risk :destructive "delete world"
    {:on-approved (fn [r] (set approved-result r))
     :on-denied (fn [_r] nil)})
  (assert controller.state.pending-approval
          "controller should track pending approval requests")
  (controller:approve-pending)
  (assert approved-result "approve-pending should resolve approval")
  (assert (not controller.state.pending-approval)
          "approve-pending should clear pending approval"))

(fn test-controller_hydrates_existing_pending_approval []
  (local registry (AgentRegistry {:deps {}}))
  (fn make-agent [_deps] {:id "test-agent" :name "Test Agent" :run (fn [] nil)})
  (registry:register "test-agent" make-agent)
  (local approvals (AgentApprovals {:policy {:destructive :ask}}))
  (local runner (make-test-runner))
  (approvals:request-risk :destructive "delete world"
    {:on-approved (fn [_r] nil)
     :on-denied (fn [_r] nil)}
    {:tool "space_delete_world" :grant-on-approve true})
  (local controller (AgentPanelController {:runner runner
                                             :registry registry
                                             :approvals approvals}))
  (controller:init)
  (assert controller.state.pending-approval
          "controller should hydrate approval that existed before listener attach")
  (assert (= controller.state.pending-approval.reason "delete world")
          "hydrated approval should be the pending request"))

(table.insert tests {:name "controller init creates first session"
                     :fn test-controller-init})
(table.insert tests {:name "controller select agent switches active agent"
                     :fn test-controller-select-agent})
(table.insert tests {:name "controller send returns turn handle"
                     :fn test-controller-send-text})
(table.insert tests {:name "controller send loads user message"
                     :fn test-controller-send-loads_user_message})
(table.insert tests {:name "controller stop clears active turn"
                     :fn test-controller-stop})
(table.insert tests {:name "controller toggle expanded toggles expanded state"
                     :fn test-controller-toggle-expanded})
(table.insert tests {:name "controller get-active-agent"
                     :fn test-controller-get-active-agent})
(table.insert tests {:name "controller get-active-session"
                     :fn test-controller-get-active-session})
(table.insert tests {:name "controller new-session creates session"
                     :fn test-controller-new-session})
(table.insert tests {:name "controller drop disconnects signals"
                     :fn test-controller-drop-disconnects})
(table.insert tests {:name "controller select-session loads items"
                     :fn test-controller-select-session-loads-items})
(table.insert tests {:name "controller init selects existing session"
                     :fn test-controller-init-selects-existing-session})
(table.insert tests {:name "controller tracks pending approval"
                     :fn test-controller_tracks_pending_approval})
(table.insert tests {:name "controller hydrates existing pending approval"
                     :fn test-controller_hydrates_existing_pending_approval})

(fn main []
  (local runner (require :tests/runner))
  (runner.run-tests {:name "agent-panel"
                     :tests tests}))

{:tests tests
 :main main}
