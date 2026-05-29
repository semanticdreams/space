;; Preset list — renders preset groups and rows with override controls.

(local ScrollView (require :scroll-view))
(local StatusBadge (require :status-badge))
(local Padding (require :padding))
(local Icon (require :icon-widget))
(local Text (require :text))
(local TextStyle (require :text-style))
(local {: Flex : FlexChild} (require :flex))
(local Stack (require :stack))
(local Rectangle (require :rectangle))
(local Button (require :button))
(local glm (require :glm))
(local {: Layout} (require :layout))

(fn risk-tone [risk]
  (if (= risk :destructive) :danger
      (= risk :shell) :danger
      (= risk :filesystem-write) :warning
      (= risk :filesystem-read) :info
      :neutral))

(fn state-label [row]
  (if (and (= row.override-state :on) row.active?) "pinned on"
      (= row.override-state :off) "forced off"
      row.active? "auto active"
      "auto inactive"))

(fn state-tone [row]
  (if (= row.override-state :on) :info
      (= row.override-state :off) :neutral
      row.active? :success
      :neutral))

(fn AgentPresetList [controller]
  (fn build [ctx]
    (local clickables (assert ctx.clickables "PresetList requires ctx.clickables"))
    (assert ctx.hoverables "PresetList requires ctx.hoverables")
    (assert ctx.icons "PresetList requires ctx.icons")

    (local theme (and ctx ctx.theme))
    (local dim-fg
      (or (and theme theme.text theme.text.dim-foreground)
          (glm.vec4 0.55 0.58 0.64 1)))
    (local item-fg
      (or (and theme theme.text theme.text.foreground)
          (glm.vec4 0.9 0.92 0.97 1)))

    (var inner-flex nil)
    (var last-rows-signature "")

    (fn content-measurer [self]
      (if inner-flex
          (do
            (inner-flex.layout:measurer)
            (set self.measure inner-flex.layout.measure))
          (set self.measure (glm.vec3 0 0 0))))

    (fn content-constrained-measurer [self constraints]
      (if inner-flex
          (do
            (inner-flex.layout:measure-constrained constraints)
            (set self.measure inner-flex.layout.measure))
          (set self.measure (glm.vec3 0 0 0))))

    (fn content-layouter [self]
      (when inner-flex
        (set inner-flex.layout.size self.size)
        (set inner-flex.layout.position self.position)
        (set inner-flex.layout.rotation self.rotation)
        (set inner-flex.layout.depth-offset-index self.depth-offset-index)
        (set inner-flex.layout.clip-region self.clip-region)
        (inner-flex.layout:layouter)))

    (local content-layout
      (Layout {:name "agent-preset-list-content"
               :measurer content-measurer
               :constrained-measurer content-constrained-measurer
               :layouter content-layouter}))

    (local content-root
      {:layout content-layout
       :drop (fn [self]
               (self.layout:drop)
               (when inner-flex
                 (inner-flex:drop)
                 (set inner-flex nil)))})

    (local scroll-view
      ((ScrollView {:child (fn [_ctx] content-root)
                    :scrollbar-policy :as-needed
                    :scrollbar-width 0.5
                    :growth-anchor :top
                    :name "agent-preset-list"})
       ctx))

    (fn build-preset-controls [row child-ctx]
      (local auto-btn
        ((Button {:text "Auto"
                  :variant (if (= row.override-state :auto) :primary :secondary)
                  :scale 0.9
                  :padding [0.1 0.3]
                  :enabled? (not (= row.override-state :auto))
                  :on-click (fn [_btn _evt]
                               (controller:set-preset-override row.name :auto))})
         child-ctx))
      (local on-btn
        ((Button {:text "On"
                  :variant (if (= row.override-state :on) :primary :secondary)
                  :scale 0.9
                  :padding [0.1 0.3]
                  :enabled? (not (= row.override-state :on))
                  :on-click (fn [_btn _evt]
                               (controller:set-preset-override row.name :on))})
         child-ctx))
      (local off-btn
        ((Button {:text "Off"
                  :variant (if (= row.override-state :off) :primary :secondary)
                  :scale 0.9
                  :padding [0.1 0.3]
                  :enabled? (not (= row.override-state :off))
                  :on-click (fn [_btn _evt]
                               (controller:set-preset-override row.name :off))})
         child-ctx))
      ((Flex {:axis 1
              :xspacing 0.15
              :yalign :center
              :children [(FlexChild (fn [_ctx] auto-btn))
                         (FlexChild (fn [_ctx] on-btn))
                         (FlexChild (fn [_ctx] off-btn))]})
       child-ctx))

    (fn build-preset-details [row child-ctx]
      (local tool-id-count (length row.tool-ids))
      (local tool-text
        (if (> tool-id-count 0)
            (.. "Tools: " (table.concat row.tool-ids ", "))
            "No tools"))
      (local context-count (length row.contexts))
      (local context-parts [])
      (each [_ c (ipairs row.contexts)]
        (local parts [])
        (each [k v (pairs c)]
          (table.insert parts (.. k "=" (tostring v))))
        (table.insert context-parts (.. "{" (table.concat parts " ") "}")))
      (local context-text
        (if (> context-count 0)
            (.. "Contexts: " (table.concat context-parts ", "))
            "No contexts"))
      ((Padding {:edge-insets [0.15 0.4 0.25 0.4]
                 :child (fn [inner-ctx]
                          ((Flex {:axis 2
                                  :yspacing 0.15
                                  :children [(FlexChild (fn [_ctx]
                                                          ((Text {:text tool-text
                                                                  :style (TextStyle {:color dim-fg
                                                                                     :scale 1.0})})
                                                           _ctx)))
                                             (FlexChild (fn [_ctx]
                                                          ((Text {:text context-text
                                                                  :style (TextStyle {:color dim-fg
                                                                                     :scale 1.0})})
                                                           _ctx)))]})
                           inner-ctx))})
       child-ctx))

    (fn make-header [child-ctx]
      (local title
        ((Text {:text "Presets"
                :style (TextStyle {:color dim-fg
                                   :scale 1.2})})
         child-ctx))
      (local reset-btn
        ((Button {:text "Reset"
                  :variant :ghost
                  :scale 0.85
                  :padding [0.15 0.3]
                  :on-click (fn [_btn _evt]
                              (controller:reset-preset-overrides))})
         child-ctx))
      ((Padding {:edge-insets [0.2 0.25]
                 :child (fn [inner-ctx]
                          ((Flex {:axis 1
                                  :xspacing 0.3
                                  :yalign :center
                                  :children [(FlexChild (fn [_ctx] title) 1)
                                             (FlexChild (fn [_ctx] reset-btn))]})
                           inner-ctx))})
       child-ctx))

    (fn make-row [row child-ctx]
      (local preset-expanded? (controller:is-preset-expanded? row.name))
      (local row-bg-color
        (if row.active? (glm.vec4 0.15 0.20 0.32 0.9)
            (glm.vec4 0 0 0 0)))
      (local bg-rect
        ((Rectangle {:color row-bg-color})
         child-ctx))

      (local risk-badge
        ((StatusBadge {:text row.risk
                       :tone (risk-tone row.risk)
                       :scale 1.0
                       :padding [0.1 0.1]})
         child-ctx))
      (local state-badge
        ((StatusBadge {:text (state-label row)
                       :tone (state-tone row)
                       :scale 1.0
                       :padding [0.1 0.1]})
         child-ctx))
      (local name-text
        ((Text {:text row.name
                :style (TextStyle {:color item-fg
                                   :scale 1.2})})
         child-ctx))
      (local tool-count-text
        ((Text {:text (.. (tostring row.tool-count) " tools")
                :style (TextStyle {:color dim-fg
                                   :scale 1.0})})
         child-ctx))

      (local row-inner
        ((Flex {:axis 1
                :xspacing 0.4
                :yalign :center
                :children [(FlexChild (fn [_ctx] name-text) 1)
                           (FlexChild (fn [_ctx] state-badge))
                           (FlexChild (fn [_ctx] risk-badge))
                           (FlexChild (fn [_ctx] tool-count-text))]})
         child-ctx))

      (local controls (build-preset-controls row child-ctx))

      (local row-content-children [(FlexChild (fn [_ctx] row-inner))
                                   (FlexChild (fn [_ctx] controls))])
      (when preset-expanded?
        (local details (build-preset-details row child-ctx))
        (table.insert row-content-children (FlexChild (fn [_ctx] details))))

      (local inner-children [(fn [_ctx] bg-rect)
                             (fn [_ctx]
                               ((Padding {:edge-insets [0.3 0.25]
                                          :child (fn [inner-ctx]
                                                  ((Flex {:axis 2
                                                          :yspacing 0.2
                                                          :children row-content-children})
                                                   inner-ctx))})
                               _ctx))])

      (local stack
        ((Stack {:children inner-children})
         child-ctx))

      (local row-widget
        {:layout stack.layout
         :pointer-target (and child-ctx child-ctx.pointer-target)})
      (set row-widget.intersect
           (fn [self ray]
             (self.layout:intersect ray)))
      (set row-widget.on-click
           (fn [_self _event]
             (controller:toggle-preset-expanded row.name)))
      (set row-widget.drop
           (fn [self]
             (clickables:unregister self)
             (stack:drop)))
      (clickables:register row-widget)
      row-widget)

    (fn make-group-header [group-name child-ctx]
      (local group-expanded? (controller:is-preset-group-expanded? group-name))
      (local bg-rect
        ((Rectangle {:color (glm.vec4 0.1 0.12 0.18 1)})
         child-ctx))
      (local indicator
        ((Icon {:icon (if group-expanded? "expand_more" "chevron_right")
                :color dim-fg
                :scale 1.2})
         child-ctx))
      (local group-text
        ((Text {:text group-name
                :style (TextStyle {:color dim-fg
                                   :scale 1.3})})
         child-ctx))
      (local group-override-state (controller:get-preset-group-override-state group-name))
      (local toggle-all-btn
        ((Button {                  :text (if (= group-override-state :mixed) "Mixed" group-override-state)
                  :variant (if (= group-override-state :on) :primary :ghost)
                  :scale 0.85
                  :padding [0.15 0.3]
                  :on-click (fn [_btn _evt]
                              (controller:toggle-group-override group-name))})
         child-ctx))
      (local header-inner
        ((Flex {:axis 1
                :xspacing 0.3
                :yalign :center
                :children [(FlexChild (fn [_ctx] indicator))
                           (FlexChild (fn [_ctx] group-text) 1)
                           (FlexChild (fn [_ctx] toggle-all-btn))]})
         child-ctx))
      (local padded
        ((Padding {:edge-insets [0.25 0.25]
                   :child (fn [_ctx] header-inner)})
         child-ctx))
      (local stack
        ((Stack {:children [(fn [_ctx] bg-rect) (fn [_ctx] padded)]})
         child-ctx))

      (local header-widget
        {:layout stack.layout
         :pointer-target (and child-ctx child-ctx.pointer-target)})
      (set header-widget.intersect
           (fn [self ray]
             (self.layout:intersect ray)))
      (set header-widget.on-click
           (fn [_self _event]
             (controller:toggle-preset-group-expanded group-name)))
      (set header-widget.drop
           (fn [self]
             (clickables:unregister self)
             (stack:drop)))
      (clickables:register header-widget)
      header-widget)

    (fn build-group-header [group-widgets group-name child-ctx]
      (local header (make-group-header group-name child-ctx))
      (table.insert group-widgets header))

    (fn build-group-preset-rows [group-widgets rows child-ctx]
      (each [_ row (ipairs rows)]
        (let [row-widget (make-row row child-ctx)]
          (table.insert group-widgets row-widget))))

    (fn rows-signature [rows]
      (local parts [])
      (each [_ row (ipairs rows)]
        (table.insert parts
          (.. row.name ":override=" (tostring row.override-state)
              ":active=" (tostring row.active?)
              ":expanded=" (tostring (controller:is-preset-expanded? row.name))
              ":group-expanded=" (tostring (controller:is-preset-group-expanded? row.group)))))
      (table.concat parts "|"))

    (fn build-inner-content []
      (local rows controller.state.preset-rows)
      (local groups controller.state.preset-groups)
      (local next-signature (rows-signature rows))

      (when (not (= next-signature last-rows-signature))
        (set last-rows-signature next-signature)
        (when inner-flex
          (inner-flex:drop)
          (set inner-flex nil))

        (local grouped {})
        (each [_ row (ipairs rows)]
          (when (not (. grouped row.group))
            (tset grouped row.group []))
          (table.insert (. grouped row.group) row))

        (local children [(FlexChild make-header 0)])
        (each [_ group-name (ipairs groups)]
          (local group-rows (or (. grouped group-name) []))
          (when (> (length group-rows) 0)
            (let [group-widgets []]
              (build-group-header group-widgets group-name ctx)
              (when (controller:is-preset-group-expanded? group-name)
                (build-group-preset-rows group-widgets group-rows ctx))
              (each [_ w (ipairs group-widgets)]
                (table.insert children (FlexChild (fn [_ctx] w) 0))))))

        (set inner-flex
             ((Flex {:axis 2
                     :xalign :stretch
                     :yspacing 0
                     :children children})
              ctx))
        (content-layout:set-children [inner-flex.layout])
        (content-layout:mark-measure-dirty)
        (content-layout:mark-layout-dirty)
        (when scroll-view.layout
          (scroll-view.layout:mark-measure-dirty))))

    (build-inner-content)

    (fn refresh [self]
      (build-inner-content))

    (fn drop [self]
      (scroll-view:drop))

    {:layout scroll-view.layout
     :drop drop
     :refresh refresh
     :scroll-view scroll-view}))

{:AgentPresetList AgentPresetList}
