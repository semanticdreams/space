(local glm (require :glm))
(local {: Layout} (require :layout))
(local Rectangle (require :rectangle))
(local Stack (require :stack))
(local {: Flex : FlexChild} (require :flex))
(local Button (require :button))
(local {: adjust} (require :widget-theme-utils))

(local rail-width 6)
(local panel-width 38)

(fn panel-background [theme kind]
  (local card-theme (and theme theme.card))
  (local base (or (and card-theme card-theme.background)
                  (if (= kind :rail)
                      (glm.vec4 0.08 0.1 0.14 0.96)
                      (glm.vec4 0.12 0.14 0.18 0.96))))
  (if (= kind :rail)
      (adjust base (if (and theme (= theme.name :light)) -0.06 -0.04))
      (adjust base (if (and theme (= theme.name :light)) -0.03 0.0))))

(fn HudExtendedSidebarView [sidebar]
  (assert sidebar "HudExtendedSidebarView requires sidebar")
  (fn build [ctx]
    (local theme (and ctx ctx.theme))
    (var root-layout nil)
    (var rail-entity nil)
    (var active-panel-entity nil)
    (var cached-panels {})
    (var pending-rebuild? true)
    (var changed-handler nil)

    (fn drop-rail! []
      (when rail-entity
        (rail-entity:drop)
        (set rail-entity nil)))

    (fn drop-all-panels! []
      (each [_ cached-panel (pairs cached-panels)]
        (cached-panel:drop))
      (set cached-panels {}))

    (fn ensure-panel-built [id]
      (when (not (. cached-panels id))
        (local entry (sidebar:get-entry id))
        (when entry
          (set (. cached-panels id) (entry.build-panel ctx))))
      (. cached-panels id))

    (fn deactivate-current-panel! []
      (when active-panel-entity
        (active-panel-entity.layout:set-self-culled true)
        (set active-panel-entity nil)))

    (fn activate-panel! [id]
      (deactivate-current-panel!)
      (when id
        (local panel (ensure-panel-built id))
        (when panel
          (set active-panel-entity panel)
          (panel.layout:set-self-culled false))))

    (fn build-rail []
      (local rail-children [])
      (each [_ id (ipairs sidebar.entry-ids)]
        (local entry (. sidebar.entries id))
        (table.insert rail-children
                      (FlexChild
                        (fn [child-ctx]
                          ((Button {:padding [0.4 0.2]
                                    :focusable? false
                                    :icon entry.icon
                                    :icon-style {:scale 2.4}
                                    :name (.. "extended-sidebar-" id)
                                    :focus-name entry.label
                                    :on-click (fn [_button _event]
                                                (sidebar:entry-clicked id))
                                    :variant (if (= sidebar.active-id id) :primary :secondary)})
                           child-ctx))
                        0)))
      ((Stack {:children [(fn [inner-ctx]
                            ((Rectangle {:color (panel-background theme :rail)})
                             inner-ctx))
                          (fn [inner-ctx]
                            ((Flex {:axis 2
                                    :xalign :stretch
                                    :spacing 0
                                    :yalign :start
                                    :children rail-children})
                             inner-ctx))]})
       ctx))

    (fn clear-focus-on-culled! []
      (when (and ctx.focus ctx.focus.manager)
        (local node (ctx.focus.manager:get-focused-node))
        (when (and node node.layout (node.layout:effective-culled?))
          (ctx.focus.manager:clear-focus))))

    (fn rebuild-children! []
      (drop-rail!)
      (if (and sidebar.expanded? sidebar.active-id)
          (activate-panel! sidebar.active-id)
          (deactivate-current-panel!))
      (set rail-entity (build-rail))
      (root-layout:clear-children)
      (each [_ panel (pairs cached-panels)]
        (root-layout:add-child panel.layout))
      (root-layout:add-child rail-entity.layout)
      (clear-focus-on-culled!)
      (root-layout:mark-measure-dirty)
      (root-layout:mark-layout-dirty))

    (fn measurer [self]
      (each [_ child (ipairs (or self.children []))]
        (child:measurer))
      (local total-width (if (and sidebar.expanded? sidebar.active-id active-panel-entity)
                             (+ rail-width panel-width)
                             rail-width))
      (set self.measure (glm.vec3 total-width 0 0)))

    (fn layouter [self]
      (local base-position self.position)
      (local base-rotation self.rotation)
      (local base-depth (or self.depth-offset-index 0))
      (local height (or (and self.size self.size.y) 0))
      (when active-panel-entity
        (set active-panel-entity.layout.position (glm.vec3 (- base-position.x panel-width) base-position.y base-position.z))
        (set active-panel-entity.layout.size (glm.vec3 panel-width height 0))
        (set active-panel-entity.layout.rotation base-rotation)
        (set active-panel-entity.layout.clip-region self.clip-region)
        (set active-panel-entity.layout.depth-offset-index (+ base-depth 1))
        (active-panel-entity.layout:layouter))
      (when rail-entity
        (set rail-entity.layout.position (glm.vec3 base-position.x base-position.y base-position.z))
        (set rail-entity.layout.size (glm.vec3 rail-width height 0))
        (set rail-entity.layout.rotation base-rotation)
        (set rail-entity.layout.clip-region self.clip-region)
        (set rail-entity.layout.depth-offset-index (+ base-depth 1))
        (rail-entity.layout:layouter)))

    (set root-layout
         (Layout {:name "hud-extended-sidebar"
                  :measurer measurer
                  :layouter layouter
                  :children []}))

    (set changed-handler
         (sidebar.changed:connect
           (fn [_payload]
             (set pending-rebuild? true))))

    (rebuild-children!)
    (set pending-rebuild? false)

    {:layout root-layout
     :update (fn [_self]
               (when pending-rebuild?
                 (set pending-rebuild? false)
                 (rebuild-children!)
                 (root-layout:mark-measure-dirty)
                 (root-layout:mark-layout-dirty))
               (when (and active-panel-entity active-panel-entity.update)
                 (active-panel-entity:update)))
     :drop (fn [_self]
             (when changed-handler
               (sidebar.changed:disconnect changed-handler true)
               (set changed-handler nil))
             (drop-rail!)
             (set active-panel-entity nil)
             (drop-all-panels!)
             (root-layout:drop))}))
  HudExtendedSidebarView
