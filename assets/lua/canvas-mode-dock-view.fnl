(local glm (require :glm))
(local {: Layout} (require :layout))
(local Rectangle (require :rectangle))
(local Padding (require :padding))
(local Stack (require :stack))
(local {: Flex : FlexChild} (require :flex))
(local Button (require :button))
(local CanvasModes (require :canvas-modes))
(local {: adjust} (require :widget-theme-utils))

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
  (Button {:padding [0.4 0.25]
           :focusable? false
           :icon icon
           :icon-style {:scale 3.2}
           :name name
           :focus-name label
           :on-click (fn [button event]
                       (when (not active?)
                         (on-click button event)))
           :variant (if active? :primary :secondary)}))

(fn panel-background [theme kind]
  (local card-theme (and theme theme.card))
  (local base (or (and card-theme card-theme.background)
                  (if (= kind :rail)
                      (glm.vec4 0.08 0.1 0.14 0.96)
                      (glm.vec4 0.12 0.14 0.18 0.96))))
  (if (= kind :rail)
      (adjust base (if (and theme (= theme.name :light)) -0.06 -0.04))
      (adjust base (if (and theme (= theme.name :light)) -0.03 0.0))))

(fn CanvasModeDockView [_opts]
  (local build
    (fn [ctx]
    (var root-layout nil)
    (var content-entity nil)
    (var active-dock-entity nil)
    (var pending-rebuild? true)
    (var shell-changed-handler nil)
    (var modes-changed-handler nil)
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
      app.canvas-mode-left-dock-builder)

    (fn build-feature-rail []
      (local feature-children [])
      (each [_ mode-spec (ipairs (CanvasModes.sidebar-mode-specs))]
        (table.insert feature-children
                      (FlexChild
                        (fn [child-ctx]
                          ((feature-button (. mode-spec :icon)
                                           (. mode-spec :button-name)
                                           (. mode-spec :label)
                                           (CanvasModes.matches-id? app.active-canvas-mode
                                                                   (. mode-spec :id))
                                           (fn [_button _event]
                                             (assert app.set-active-canvas-mode
                                                     "CanvasModeDockView requires app.set-active-canvas-mode")
                                             (app.set-active-canvas-mode (. mode-spec :id))))
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
      (local show-dock?
        (and app.canvas
             (= app.active-interaction-surface :canvas)
             (= app.canvas-visible? true)))
      (if (not show-dock?)
          nil
          (do
            (local builders [(FlexChild (build-feature-rail) 0)])
            (local left-dock-builder (current-left-dock-builder))
            (when left-dock-builder
              (set active-dock-entity (left-dock-builder ctx))
              (when active-dock-entity
                (table.insert builders
                              (FlexChild
                                (fn [_inner-ctx]
                                  active-dock-entity)
                                0))))
            ((Flex {:axis 1
                    :spacing 0
                    :yalign :stretch
                    :children builders})
             ctx))))

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
        (content-entity.layout:layouter)))

    (set root-layout
         (Layout {:name "canvas-mode-dock"
                  :measurer measurer
                  :layouter layouter
                  :children []}))

    (when app.canvas-shell-changed
      (set shell-changed-handler
           (app.canvas-shell-changed:connect
             (fn [_payload]
               (request-rebuild!)))))
    (when app.canvas-modes-changed
      (set modes-changed-handler
           (app.canvas-modes-changed:connect
             (fn [_payload]
               (request-rebuild!)))))

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
     :drop (fn [_self]
             (when shell-changed-handler
               (app.canvas-shell-changed:disconnect shell-changed-handler true)
               (set shell-changed-handler nil))
             (when modes-changed-handler
               (app.canvas-modes-changed:disconnect modes-changed-handler true)
               (set modes-changed-handler nil))
             (drop-content!)
             (root-layout:drop))}))

  build)

CanvasModeDockView
