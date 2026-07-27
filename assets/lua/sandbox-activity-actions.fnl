;; Sandbox activity Scene root actions.
;; These actions were previously global scene actions attached to
;; every scene-surface right-click.  Task 4 moves them into the
;; Sandbox activity so they are only available when Sandbox is active.

(local Ball (require :ball))
(local SceneTerrainRecovery (require :scene-terrain-recovery))

(fn sandbox-root-actions [context]
  "Return Sandbox-specific root-context-menu actions.
  Operate on the globally available app.scene since Sandbox
  exclusively owns the Scene surface."
  (local scene app.scene)
  (local actions [])
  (table.insert actions
                {:name "Demo Browser"
                 :fn (fn [_button _event]
                       (when (and scene scene.add-demo-browser)
                         (scene:add-demo-browser)))})
  (table.insert actions
                {:name "Demo Video Player"
                 :fn (fn [_button _event]
                       (local launchable (require :launchables/demo-video-cube))
                       (launchable.open-panel {:scene scene}))})
  (table.insert actions
                {:name "add cuboid"
                 :fn (fn [_button _event]
                       (when (and scene scene.add-physics-body)
                         (scene:add-physics-body)))})
  (table.insert actions
                {:name "ball"
                 :fn (fn [_button _event]
                       (when (and scene scene.add-object)
                         (scene:add-object (Ball {}))))})
  (table.insert actions
                {:name "Add light ball"
                 :fn (fn [_button _event]
                       (when (and scene scene.add-light-ball)
                         (scene:add-light-ball {})))})
  (table.insert actions
                {:name "Recover Terrain-Bound Objects"
                 :fn (fn [_button _event]
                       (when scene
                         (SceneTerrainRecovery.recover scene)))})
  actions)

{:sandbox-root-actions sandbox-root-actions}
