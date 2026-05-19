;; Session list — composes ListView with a session row builder.

(local ListView (require :list-view))
(local StatusBadge (require :status-badge))
(local Padding (require :padding))
(local Text (require :text))
(local TextStyle (require :text-style))
(local {: Flex : FlexChild} (require :flex))
(local Stack (require :stack))
(local Rectangle (require :rectangle))
(local glm (require :glm))

(fn status-tone [status]
  (if (= status :running) :info
      (= status :error) :danger
      :neutral))

(fn session-title [session]
  (or session.title
      (and session.id (session.id:sub 1 16))
      "Session"))

(fn format-timestamp [ts]
  (if ts (os.date "%H:%M" ts) ""))

(fn AgentSessionList [controller]
  (fn build [ctx]
    (local clickables (assert ctx.clickables "SessionList requires ctx.clickables"))

    (fn make-row [session child-ctx]
      (local selected? (= session.id controller.state.active-session-id))
      (local bg-rect
        ((Rectangle {:color (if selected?
                                (glm.vec4 0.18 0.22 0.34 1)
                                (glm.vec4 0 0 0 0))})
         child-ctx))
      (local badge
        ((StatusBadge {:text session.status
                       :tone (status-tone session.status)
                       :scale 1.0
                       :padding [0.2 0.1]})
         child-ctx))
      (local title-text
        ((Text {:text (session-title session)
                :style (TextStyle {:color (glm.vec4 0.9 0.92 0.97 1)
                                   :scale 1.3})})
         child-ctx))
      (local time-text
        ((Text {:text (format-timestamp session.updated-at)
                :style (TextStyle {:color (glm.vec4 0.55 0.58 0.64 1)
                                   :scale 1.0})})
         child-ctx))
      (local padded
        ((Padding {:edge-insets [0.35 0.25]
                   :child (fn [inner-ctx]
                            ((Flex {:axis 1
                                    :xspacing 0.4
                                    :yalign :center
                                    :children [(FlexChild (fn [_ctx] badge))
                                               (FlexChild (fn [_ctx] title-text) 1)
                                               (FlexChild (fn [_ctx] time-text))]})
                             inner-ctx))})
         child-ctx))
      (local stack
        ((Stack {:children [(fn [_ctx] bg-rect) (fn [_ctx] padded)]})
         child-ctx))
      (local row
        {:layout stack.layout
         :pointer-target (and child-ctx child-ctx.pointer-target)})
      (set row.intersect
           (fn [self ray]
             (self.layout:intersect ray)))
      (set row.on-click
           (fn [_self _event]
             (controller:select-session session.id)))
      (set row.drop
           (fn [self]
             (clickables:unregister self)
             (stack:drop)))
      (clickables:register row)
      row)

    (local list-view
      ((ListView {:items controller.state.sessions
                  :builder make-row
                  :show-head? false
                  :item-spacing 0.1
                  :scrollbar-policy :as-needed
                  :scrollbar-width 0.4
                  :name "agent-session-list"})
       ctx))

    (fn refresh [self]
      (when (and list-view list-view.set-items)
        (list-view:set-items controller.state.sessions)))

    (fn drop [self]
      (self.layout:drop)
      (list-view:drop))

    {:layout list-view.layout
     :drop drop
     :refresh refresh
     :list-view list-view}))

{:AgentSessionList AgentSessionList}
