(local GraphViewControlView (require :graph-view-control-view))

{:name "Graph Control"
 :run (fn []
        (assert (and app.hud app.hud.add-panel-child) "Graph Control requires app.hud.add-panel-child")
        (app.hud:add-panel-child {:builder (GraphViewControlView {})}))}
