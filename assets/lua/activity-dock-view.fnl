(local glm (require :glm))
(local {: Layout} (require :layout))
(local Rectangle (require :rectangle))
(local Padding (require :padding))
(local Stack (require :stack))
(local {: Flex : FlexChild} (require :flex))
(local Button (require :button))
(local Activities (require :activities))
(local {: resolve-chrome-background} (require :widget-theme-utils))
(local HudChromeMetrics (require :hud-chrome-metrics))

(fn panel-shell [content-builder background-color opts]
  (local options (or opts {}))
  (local body-padding
    (if (= options.padding false)
        nil
        (or options.padding [0.45 0.45])))
  (Stack {:children [(fn [_ctx] ((Rectangle {:color background-color}) _ctx))
                     (if body-padding
                         (Padding {:edge-insets body-padding
                                   :child content-builder})
                         content-builder)]}))

(fn feature-button [icon name label active? on-click]
  (assert on-click "feature-button requires on-click")
  (Button {:padding HudChromeMetrics.rail-button-padding
           :focusable? false
           :icon icon
           :icon-style HudChromeMetrics.rail-button-icon-style
           :name name
           :focus-name label
           :on-click (fn [button event]
                       (when (not active?)
                         (on-click button event)))
           :variant (if active? :primary :secondary)}))

(fn panel-background [theme kind]
  (resolve-chrome-background theme kind))








(fn ActivityDockView [opts]
  (local options (or opts {}))
  (fn top-reserve-height []
    (local provider (and options options.top-reserve-height-provider))
    (if provider
        (math.max 0 (provider))
        0))
  (local build
    (fn [ctx]
    (var root-layout nil)
    (var content-entity nil)
    (var active-dock-entity nil)
    (var pending-rebuild? true)
    (var workspace-shell-changed-handler nil)
    (var activities-changed-handler nil) (var activity-dock-changed-handler nil)
    (local theme (and ctx ctx.theme))

    (fn drop-content! []
      (when (and root-layout content-entity content-entity.layout)
        (var removed? false)
        (each [idx child (ipairs root-layout.children)]
          (when (and (not removed?)
                     (= child content-entity.layout))
            (set removed? true)
            (root-layout:remove-child idx))))
      (when active-dock-entity
        (active-dock-entity:drop)
        (set active-dock-entity nil))
      (when content-entity
        (content-entity:drop)
        (set content-entity nil))
      true)

    (fn current-left-dock-builder []
      app.activity-left-dock-builder)

    (fn build-feature-rail []
      (local feature-children [])
      (each [_ activity-spec (ipairs (Activities.switcher-activity-specs))]
        (table.insert feature-children
                      (FlexChild
                        (fn [child-ctx]
                          ((feature-button (. activity-spec :icon)
                                           (. activity-spec :button-name)
                                           (. activity-spec :label)
                                           (Activities.matches-id? app.active-activity-id
                                                                   (. activity-spec :id))
                                           (fn [_button _event]
                                             (assert app.set-active-activity
                                                     "ActivityDockView requires app.set-active-activity")
                                             (app.set-active-activity (. activity-spec :id))))
                           child-ctx))
                        0)))
      (panel-shell
        (fn [inner-ctx]
          ((Flex {:axis 2
                  :xalign :stretch
                  :spacing 0
                  :children feature-children})
           inner-ctx))
        (panel-background theme :rail)
        {:padding false}))

    (fn build-content []
      (local builders [(FlexChild (build-feature-rail) 0)])
      (local show-activity-panel?
        (and app.canvas
             (= app.active-interaction-surface :canvas)
             (= app.canvas-visible? true)))
      (when show-activity-panel?
        (local left-dock-builder (current-left-dock-builder))
        (when left-dock-builder
          (set active-dock-entity (left-dock-builder ctx))
          (when active-dock-entity
            (table.insert builders
                          (FlexChild
                            (fn [_inner-ctx]
                              active-dock-entity)
                            0)))))
      ((Flex {:axis 1
              :spacing 0
              :yalign :stretch
              :children builders})
       ctx))

    (fn rebuild-children! []
      (drop-content!)
      (set content-entity (build-content))
      (when content-entity
        (root-layout:add-child content-entity.layout))
      (when root-layout
        (root-layout:mark-measure-dirty)
        (root-layout:mark-layout-dirty)))

    (fn request-rebuild! []
      (set pending-rebuild? true)
      true)

    (fn measurer [self]
      (if content-entity
          (do
            (content-entity.layout:measurer)
            (set self.measure content-entity.layout.measure))
          (set self.measure (glm.vec3 0 0 0))))

    (fn layouter [self]
      (local allocated-size
        (glm.vec3 (math.max self.measure.x (or self.size.x 0))
                  (math.max self.measure.y (or self.size.y 0))
                  (math.max self.measure.z (or self.size.z 0))))
      (set self.size allocated-size)
      (when content-entity
        (set content-entity.layout.position self.position)
        (set content-entity.layout.size allocated-size)
        (set content-entity.layout.rotation self.rotation)
        (set content-entity.layout.clip-region self.clip-region)
        (set content-entity.layout.depth-offset-index self.depth-offset-index)
        (content-entity.layout:layouter)
        (when active-dock-entity
          (local reserve (top-reserve-height))
          (when (> reserve 0)
            (local entity-layout active-dock-entity.layout)
            (local current-y (or entity-layout.position.y 0))
            (local current-h (or entity-layout.size.y 0))
            (set entity-layout.position.y (+ current-y reserve))
            (set entity-layout.size.y (math.max 0 (- current-h reserve)))
            (entity-layout:layouter)))))

    (set root-layout
         (Layout {:name "activity-dock"
                  :measurer measurer
                  :layouter layouter
                  :children []}))

    (when app.workspace-shell-changed
      (set workspace-shell-changed-handler
           (app.workspace-shell-changed:connect
             (fn [_payload]
               (request-rebuild!)))))
    (when app.activities-changed
      (set activities-changed-handler
           (app.activities-changed:connect
             (fn [_payload]
               (request-rebuild!))))) (when app.activity-dock-changed (set activity-dock-changed-handler (app.activity-dock-changed:connect (fn [_payload] (request-rebuild!)))))

    (rebuild-children!)
    (set pending-rebuild? false)

    {:layout root-layout
     :update (fn [_self]
               (when pending-rebuild?
                 (set pending-rebuild? false)
                 (rebuild-children!)
                 (when root-layout
                  (root-layout:mark-measure-dirty)))
                (when (and active-dock-entity active-dock-entity.update)
                  (active-dock-entity:update)))
      :active-dock-entity (fn [_self] active-dock-entity) :drop (fn [_self]
              (when workspace-shell-changed-handler
                (app.workspace-shell-changed:disconnect workspace-shell-changed-handler true)
                (set workspace-shell-changed-handler nil))
              (when activities-changed-handler
                (app.activities-changed:disconnect activities-changed-handler true)
                (set activities-changed-handler nil)) (when activity-dock-changed-handler (app.activity-dock-changed:disconnect activity-dock-changed-handler true) (set activity-dock-changed-handler nil))
              (drop-content!)
              (root-layout:drop))}))

  build)

ActivityDockView
