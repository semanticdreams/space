(local glm (require :glm))
(local {:GraphNode GraphNode} (require :graph/node-base))
(local Signal (require :signal))
(local HudPanelNodeView (require :graph/view/views/hud-panel))

(local M {})

(fn M.HudPanelNode [opts]
  (local options (or opts {}))
  (local world-id (assert options.world-id "HudPanelNode requires :world-id"))
  (local layer (assert options.layer "HudPanelNode requires :layer"))
  (local panel-index (assert options.panel-index "HudPanelNode requires :panel-index"))
  (local panel (or options.panel {}))
  (local persistence (or panel.persistence {}))
  (local panel-kind (or persistence.kind "unknown"))
  (local key (or options.key (.. "hud-panel:" world-id ":" layer ":" panel-index)))
  (local label (or options.label (.. panel-kind " (" layer ")")))
  (local node (GraphNode {:key key
                           :label label
                           :color (glm.vec4 0.5 0.7 0.6 1)
                           :sub-color (glm.vec4 0.4 0.6 0.5 1)
                           :size 7.0
                           :view HudPanelNodeView}))
  (set node.world-id world-id)
  (set node.layer layer)
  (set node.panel-index panel-index)
  (set node.panel-kind panel-kind)
  (set node.panel panel)
  (set node.changed (Signal))
  (set node.actions
       [{:name "Remove"
         :icon "delete"
         :fn (fn [_button _event]
               (local element (and panel panel.element))
               (when (and element app.hud app.hud.remove-panel-child)
                 (app.hud:remove-panel-child element)))}])
  (set node.drop
       (fn [self]
         (when self.changed
           (self.changed:clear))))
  node)

M
