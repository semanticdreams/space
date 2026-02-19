(local MorphView (require :morph-view))

{:name "Morphs"
 :run (fn []
        (assert (and app.hud app.hud.add-panel-child) "Morphs launchable requires app.hud.add-panel-child")
        (app.hud:add-panel-child {:builder (MorphView {})}))}
