;; AgentPanel — top-level right dock widget that composes the agent UI.

(local glm (require :glm))
(local {: Flex : FlexChild} (require :flex))
(local Padding (require :padding))
(local Card (require :card))
(local Text (require :text))
(local TextStyle (require :text-style))
(local Button (require :button))
(local Input (require :input))
(local ComboBox (require :combo-box))
(local StatusBadge (require :status-badge))
(local {: Layout} (require :layout))
(local agent-ui-controller (require :llm/agent/ui/controller))
(local AgentPanelController agent-ui-controller.AgentPanelController)
(local session-list-mod (require :llm/agent/ui/session-list))
(local AgentSessionList session-list-mod.AgentSessionList)
(local transcript-mod (require :llm/agent/ui/transcript))
(local AgentTranscript transcript-mod.AgentTranscript)
(local ApprovalRow (require :llm/agent/ui/approval-row))

(fn AgentPanel [opts]
  (assert opts.runner "AgentPanel requires :runner")
  (assert opts.registry "AgentPanel requires :registry")
  (assert opts.approvals "AgentPanel requires :approvals")

  (fn build [ctx]
    (assert ctx.clickables "AgentPanel requires ctx.clickables")
    (assert ctx.hoverables "AgentPanel requires ctx.hoverables")

    (local controller
      (AgentPanelController {:runner opts.runner
                             :registry opts.registry
                             :approvals opts.approvals}))

    (local dim-foreground
      (or (and ctx ctx.theme ctx.theme.text ctx.theme.text.dim-foreground)
          (glm.vec4 0.55 0.58 0.64 1)))

    (local agent-label
      ((Text {:text "Agent"
              :style (TextStyle {:color dim-foreground
                                 :scale 1.2})})
       ctx))
    (fn current-agent-items []
      (icollect [_ agent (ipairs controller.state.agents)]
        {:label agent.name :value agent.id}))
    (local combo-box
      ((ComboBox {:items (current-agent-items)
                  :value controller.state.active-agent-id
                  :on-change (fn [_box value]
                               (controller:select-agent value))})
       ctx))
    (local agent-row
      ((Flex {:axis 1
              :xspacing 0.3
              :yalign :center
              :children [(FlexChild (fn [_ctx] agent-label))
                         (FlexChild (fn [_ctx] combo-box) 1)]})
       ctx))
    (local agent-row-padded
      ((Padding {:edge-insets [0.4 0.3 0.2 0.3]
                 :child (fn [_ctx] agent-row)})
       ctx))

    (local status-badge-widget
      ((StatusBadge {:text "idle"
                     :tone :neutral
                     :scale 1.0
                     :padding [0.15 0.1]})
       ctx))
    (local session-title-text
      ((Text {:text ""
               :style (TextStyle {:color dim-foreground
                                  :scale 1.1})})
       ctx))
    (local status-row
      ((Flex {:axis 1
              :xspacing 0.3
              :yalign :center
              :children [(FlexChild (fn [_ctx] status-badge-widget))
                         (FlexChild (fn [_ctx] session-title-text) 1)]})
       ctx))
    (local status-row-padded
      ((Padding {:edge-insets [0 0.3 0.3 0.3]
                 :child (fn [_ctx] status-row)})
       ctx))

    (local session-list (AgentSessionList controller))
    (local session-list-widget (session-list ctx))

    (local transcript (AgentTranscript controller))
    (local transcript-widget (transcript ctx))

    (local input-widget
      ((Input {:placeholder "Type a message..."
               :caret-width 0.04
               :focusable? true
               :focus-name "agent-input"})
       ctx))
    (local send-btn
      ((Button {:icon "send"
                :variant :primary
                :padding [0.3 0.6]
                :on-click (fn [_btn _evt]
                            (local text (input-widget:get-text))
                            (when (> (length text) 0)
                              (controller:send text)
                              (input-widget:set-text "")))})
       ctx))
    (local stop-btn
      ((Button {:icon "stop"
                :variant :danger
                :padding [0.3 0.6]
                :on-click (fn [_btn _evt]
                            (controller:stop))})
       ctx))
    (local retry-btn
      ((Button {:icon "refresh"
                :variant :secondary
                :padding [0.3 0.6]
                :on-click (fn [_btn _evt]
                            (controller:retry))})
       ctx))

    (local input-actions-flex
      ((Flex {:axis 1
              :xspacing 0.3
              :yalign :stretch
              :children [(FlexChild (fn [_ctx] input-widget) 1)
                         (FlexChild (fn [_ctx] retry-btn))
                         (FlexChild (fn [_ctx] stop-btn))
                         (FlexChild (fn [_ctx] send-btn))]})
       ctx))
    (local input-row-padded
      ((Padding {:edge-insets [0.3 0.3]
                 :child (fn [_ctx] input-actions-flex)})
       ctx))

    (var approval-widget nil)
    (var approval-widget-key nil)

    (fn approval-request-key [request]
      (and request
           (or request.id
               (table.concat [(or request.tool "")
                              (or request.source "")
                              (or request.args_hash "")
                              (or request.risk "")
                              (or request.reason "")]
                             "\n"))))
    (fn approval-measurer [self]
      (if approval-widget
          (do
            (approval-widget.layout:measurer)
            (set self.measure approval-widget.layout.measure))
          (set self.measure (glm.vec3 0 0 0))))

    (fn approval-layouter [self]
      (when approval-widget
        (set approval-widget.layout.size self.size)
        (set approval-widget.layout.position self.position)
        (set approval-widget.layout.rotation self.rotation)
        (set approval-widget.layout.depth-offset-index self.depth-offset-index)
        (set approval-widget.layout.clip-region self.clip-region)
        (approval-widget.layout:layouter)))

    (local approval-layout
      (Layout {:name "agent-approval-slot"
               :measurer approval-measurer
               :layouter approval-layouter}))

    (local approval-slot
      {:layout approval-layout
       :drop (fn [self]
               (self.layout:drop)
               (when approval-widget
                 (approval-widget:drop)
                 (set approval-widget nil)))})

    (fn rebuild-approval []
      (local request controller.state.pending-approval)
      (local next-key (approval-request-key request))
      (when (not (= next-key approval-widget-key))
        (when approval-widget
          (approval-widget:drop)
          (set approval-widget nil))
        (set approval-widget-key next-key)
        (if request
            (do
              (set approval-widget
                   ((ApprovalRow {:approval request
                                  :on-approve (fn [_approval]
                                                (controller:approve-pending))
                                  :on-approve-always (fn [_approval]
                                                       (controller:approve-pending-always))
                                  :on-deny (fn [_approval]
                                             (controller:deny-pending))})
                    ctx))
              (approval-layout:set-children [approval-widget.layout]))
            (approval-layout:set-children []))
        (approval-layout:mark-measure-dirty)
        (approval-layout:mark-layout-dirty)))

    (local sections [(FlexChild (fn [_ctx] agent-row-padded))
                     (FlexChild (fn [_ctx] status-row-padded))
                     (FlexChild (fn [_ctx] session-list-widget) 0)
                     (FlexChild (fn [_ctx] transcript-widget) 1)
                     (FlexChild (fn [_ctx] approval-slot))
                     (FlexChild (fn [_ctx] input-row-padded))])

    (local content-flex
      ((Flex {:axis 2
              :xalign :stretch
              :yspacing 0
              :children sections})
       ctx))

    (local root
      ((Card {:child (fn [_ctx] content-flex)})
       ctx))

    (fn refresh-state []
      (combo-box:set-items (current-agent-items))
      (combo-box:sync-value controller.state.active-agent-id)
      (local status-text
        (if controller.state.active-turn "running"
            controller.state.last-error "error"
            controller.state.active-session-id "idle"
            "no session"))
      (local status-tone
        (if controller.state.active-turn :info
            controller.state.last-error :danger
            :neutral))
      (status-badge-widget:set-tone status-tone)
      (status-badge-widget:set-text status-text)
      (local session (controller:get-active-session))
      (session-title-text:set-text
        (if session
            (.. "Session: " (session.id:sub 1 16))
            ""))
      (session-list-widget:refresh)
      (transcript-widget:refresh)
      (rebuild-approval)
      (local is-running? (not (not controller.state.active-turn)))
      (send-btn:set-enabled (not is-running?))
      (retry-btn:set-enabled (not is-running?))
      (stop-btn:set-enabled is-running?)
      (when root.layout
        (root.layout:mark-measure-dirty)))

    (controller.change-signal.connect refresh-state)
    (controller:init)
    (refresh-state)

    (fn drop [self]
      (controller.change-signal:clear)
      (controller.approval-change-signal:clear)
      (controller:drop)
      (self.layout:drop)
      (root:drop))

    {:layout root.layout
     :drop drop
     :controller controller}))

{:AgentPanel AgentPanel}
