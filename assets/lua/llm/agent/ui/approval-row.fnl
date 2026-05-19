;; Approval row — inline approval prompt for high-risk tool calls.

(local glm (require :glm))
(local Rectangle (require :rectangle))
(local Text (require :text))
(local TextStyle (require :text-style))
(local Padding (require :padding))
(local {: Flex : FlexChild} (require :flex))
(local Button (require :button))
(local Stack (require :stack))

(fn ApprovalRow [opts]
  (assert opts.approval "ApprovalRow requires :approval")
  (local on-approve (or opts.on-approve nil))
  (local on-deny (or opts.on-deny nil))

  (fn build [ctx]
    (local approval opts.approval)
    (local bg ((Rectangle {:color (glm.vec4 0.22 0.17 0.05 1)}) ctx))

    (local title
      ((Text {:text "Approval Needed"
              :style (TextStyle {:color (glm.vec4 0.95 0.73 0.31 1)
                                 :weight :bold
                                 :scale 1.3})})
       ctx))
    (local reason
      ((Text {:text (.. (or approval.reason approval.tool "tool") " · " (or approval.risk ""))
              :style (TextStyle {:color (glm.vec4 0.92 0.88 0.75 1)
                                 :scale 1.2})})
       ctx))

    (local approve-btn
      ((Button {:text "Approve once"
                :variant :success
                :padding [0.3 0.5]
                :on-click (fn [_btn _evt]
                            (when on-approve
                              (on-approve approval)))})
       ctx))
    (local deny-btn
      ((Button {:text "Deny"
                :variant :danger
                :padding [0.3 0.5]
                :on-click (fn [_btn _evt]
                            (when on-deny
                              (on-deny approval)))})
       ctx))

    (local info-flex
      ((Flex {:axis 2
              :yspacing 0.1
              :children [(FlexChild (fn [_ctx] title))
                         (FlexChild (fn [_ctx] reason))]})
       ctx))
    (local buttons-flex
      ((Flex {:axis 1
              :xspacing 0.3
              :children [(FlexChild (fn [_ctx] deny-btn))
                         (FlexChild (fn [_ctx] approve-btn))]})
       ctx))
    (local padded
      ((Padding {:edge-insets [0.4 0.45]
                 :child (fn [_ctx]
                          ((Flex {:axis 2
                                  :yspacing 0.3
                                  :children [(FlexChild (fn [_ctx] info-flex))
                                             (FlexChild (fn [_ctx] buttons-flex))]})
                           _ctx))})
       ctx))
    (local stack
      ((Stack {:children [(fn [_ctx] bg) (fn [_ctx] padded)]})
       ctx))

    (fn drop [self]
      (self.layout:drop)
      (stack:drop))

    {:layout stack.layout
     :drop drop}))

ApprovalRow
