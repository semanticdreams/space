(local glm (require :glm))
(local {:GraphNode GraphNode} (require :graph/node-base))
(local Signal (require :signal))
(local ScenePanelNodeView (require :graph/view/views/scene-panel))

(local M {})

(fn M.ScenePanelNode [opts]
  (local options (or opts {}))
  (local world-id (assert options.world-id "ScenePanelNode requires :world-id"))
  (local panel-index (assert options.panel-index "ScenePanelNode requires :panel-index"))
  (local panel (or options.panel {}))
  (local persistence (or panel.persistence {}))
  (local panel-kind (or persistence.kind "unknown"))
  (local key (or options.key (.. "scene-panel:" world-id ":" panel-index)))
  (local label (or options.label panel-kind))
  (local node (GraphNode {:key key
                           :label label
                           :color (glm.vec4 0.6 0.5 0.8 1)
                           :sub-color (glm.vec4 0.5 0.4 0.7 1)
                           :size 7.0
                           :view ScenePanelNodeView}))
  (set node.world-id world-id)
  (set node.panel-index panel-index)
  (set node.panel-kind panel-kind)
  (set node.panel panel)
  (set node.changed (Signal))
  (set node.actions
       [{:name "Remove"
         :icon "delete"
         :fn (fn [_button _event]
               (local element (and panel panel.element))
               (when (and element app.scene app.scene.remove-panel-child)
                 (app.scene:remove-panel-child element)))}])
  (set node.drop
       (fn [self]
         (when self.changed
           (self.changed:clear))))
  node)

M
