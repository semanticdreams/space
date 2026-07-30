(local glm (require :glm))
(local Main (require :main))
(local NormalState (require :normal-state))
(local States (require :states))
(local StateSystemBindings (require :state-system-bindings))
(local Scene (require :scene))
(local Ball (require :ball))
(local Movables (require :movables))
(local Intersectables (require :intersectables))
(local Clickables (require :clickables))
(local Hoverables (require :hoverables))
(local Camera (require :camera))
(local Canvas (require :canvas))
(local CanvasControls (require :canvas-controls))
(local AppProjection (require :app-projection))
(local MathUtils (require :math-utils))
(local {: Layout} (require :layout))
(local {: FirstPersonControls} (require :first-person-controls))

(local tests [])

(local approx (. MathUtils :approx))
 
(local reset-engine-events
  (fn []
    (when _G.reset-engine-events
      (_G.reset-engine-events))))

(fn approx-vec3 [a b]
  (and a b
       (approx a.x b.x)
       (approx a.y b.y)
       (approx a.z b.z)))

(fn command-hints-hud-provider [_self]
  {:command-hints
   {:handle-toggle-key (fn [_manager _payload] true)
    :close-on-handled-event (fn [_manager _route-key _payload] false)}})

(fn bind-normal-state! [state]
  (local states (States {:hud_provider command-hints-hud-provider}))
  (states:add-state :normal state)
  (StateSystemBindings.bind-states-host states)
  (set app.states states)
  states)

(fn restore-states! [states]
  (StateSystemBindings.bind-states-host states)
  (set app.states states))

(fn drag-through-normal-state-moves-scene-entity []
  (local original-scene app.scene)
  (local original-layout-root app.layout-root)
  (local original-movables app.movables)
  (local original-intersectables app.intersectables)
  (local original-camera app.camera)
  (local original-controls app.first-person-controls)
  (local original-hoverables (assert app.hoverables "Scene entity drag test requires app.hoverables"))
  (local original-clickables (assert app.clickables "Scene entity drag test requires app.clickables"))
  (local original-events app.engine.events)
  (local original-states app.states)
  (local original-viewport app.viewport)
  (local original-create-default-projection app.create-default-projection)
  (local original-active-surface app.active-interaction-surface)
  (local original-scene-interactive? app.scene-interactive?)
  (local original-canvas-interactive? app.canvas-interactive?)
  (var scene nil)
  (var movables nil)
  (var intersector nil)
  (var clickables nil)
  (var hoverables nil)
  (var camera nil)
  (var controls nil)
  (var state nil)
  (var target-layout nil)

  (fn cleanup [] (assert app.hoverables "Scene entity drag cleanup requires app.hoverables") (assert app.clickables "Scene entity drag cleanup requires app.clickables")
    (when state
      (state.on-leave)
      (set state nil))
    (when scene
      (scene:drop)
      (set scene nil))
    (when movables
      (movables:drop)
      (set movables nil))
    (when intersector
      (intersector:drop)
      (set intersector nil))
    (when clickables
      (clickables:drop)
      (set clickables nil))
    (when hoverables
      (hoverables:drop)
      (set hoverables nil))
    (when controls
      (controls:drop)
      (set controls nil))
    (when camera
      (camera:drop)
      (set camera nil))
    (set app.scene original-scene)
    (set app.layout-root original-layout-root)
    (set app.movables original-movables)
    (set app.intersectables original-intersectables)
    (set app.camera original-camera)
    (set app.first-person-controls original-controls)
    (set app.hoverables original-hoverables)
    (set app.clickables original-clickables)
    (set app.engine.events original-events)
    (restore-states! original-states)
    (set app.viewport original-viewport)
    (set app.create-default-projection original-create-default-projection)
    (set app.active-interaction-surface original-active-surface)
    (set app.scene-interactive? original-scene-interactive?)
    (set app.canvas-interactive? original-canvas-interactive?))

  (let [(ok err)
        (pcall
          (fn []
            (reset-engine-events)
            (set intersector (Intersectables))
            (set clickables (assert (Clickables {:intersectables intersector}) "Scene entity drag test requires clickables"))
            (set hoverables (assert (Hoverables {:intersectables intersector}) "Scene entity drag test requires hoverables"))
            (set movables (Movables {:intersectables intersector}))
            (set camera (Camera {:position (glm.vec3 0 0 10)}))
            (set controls (FirstPersonControls {:camera camera}))
            (set app.create-default-projection AppProjection.create-default-projection)
            (set scene (Scene {:position (glm.vec3 0 0 0)
                               :rotation (glm.quat 1 0 0 0)
                               :camera camera}))
            (set app.intersectables intersector)
            (set app.clickables clickables)
            (set app.hoverables hoverables)
            (set app.movables movables)
            (set app.camera camera)
            (set app.first-person-controls controls)
            (set app.scene scene)
            (set app.layout-root scene.layout-root)
            (set app.active-interaction-surface :scene)
            (set app.scene-interactive? true)
            (set app.canvas-interactive? false)
            (scene:ensure-activity-slot "sandbox")
            (local sandbox-slot (scene:activate-activity-slot "sandbox"))
            (assert sandbox-slot "Entity drag test requires a valid sandbox slot")
            (scene:build
              (fn [_ctx]
                (set target-layout
                     (Layout {:name "integration-drag-target"
                              :measurer (fn [self]
                                          (set self.measure (glm.vec3 1 1 1)))
                              :layouter (fn [self]
                                          (set self.size self.measure))}))
                {:layout target-layout
                 :drop (fn [_] (target-layout:drop))}))
            (scene:update)
            (set scene.screen-pos-ray
                 (fn [_self pointer _opts]
                   {:origin (glm.vec3 pointer.x pointer.y 10)
                    :direction (glm.vec3 0 0 -1)}))

            (set state (NormalState))
            (bind-normal-state! state)
            (state.on-enter)

            (app.engine.events.mouse-button-down.emit {:button 1 :x 0.25 :y 0.25 :mod 256})
            (app.engine.events.mouse-motion.emit {:x 5.25 :y 5.75})
            (assert (app.movables:drag-active?) "Drag should begin after motion threshold")

            (assert target-layout "Scene should create a target layout")
            (assert (approx target-layout.position.x 5.0) "Drag should update layout X position")
            (assert (approx target-layout.position.y 5.5) "Drag should update layout Y position")
            (assert (approx target-layout.position.z 0.0) "Drag should keep layout on the ground plane")
             (local active-root sandbox-slot.layout-root)
             (assert active-root "Active sandbox slot should expose a layout root")
             (assert (. active-root.layout-dirt.lookup target-layout) "Drag should mark layout node dirty")

            (app.engine.events.mouse-button-up.emit {:button 1})
            (assert (not (app.movables:drag-active?)) "Drag should end on mouse-up")))]
    (cleanup)
    (when (not ok)
      (error err))))

(fn drag-through-normal-state-moves-scene-ball []
  (local original-scene app.scene)
  (local original-layout-root app.layout-root)
  (local original-movables app.movables)
  (local original-intersectables app.intersectables)
  (local original-camera app.camera)
  (local original-controls app.first-person-controls)
  (local original-hoverables (assert app.hoverables "Scene ball drag test requires app.hoverables"))
  (local original-clickables (assert app.clickables "Scene ball drag test requires app.clickables"))
  (local original-events app.engine.events)
  (local original-states app.states)
  (local original-create-default-projection app.create-default-projection)
  (local original-active-surface app.active-interaction-surface)
  (local original-scene-interactive? app.scene-interactive?)
  (local original-canvas-interactive? app.canvas-interactive?)
  (var scene nil)
  (var movables nil)
  (var intersector nil)
  (var clickables nil)
  (var hoverables nil)
  (var camera nil)
  (var controls nil)
  (var state nil)
  (var ball nil)

  (fn cleanup [] (assert app.hoverables "Scene ball drag cleanup requires app.hoverables") (assert app.clickables "Scene ball drag cleanup requires app.clickables")
    (when state
      (state.on-leave)
      (set state nil))
    (when scene
      (scene:drop)
      (set scene nil))
    (when movables
      (movables:drop)
      (set movables nil))
    (when intersector
      (intersector:drop)
      (set intersector nil))
    (when clickables
      (clickables:drop)
      (set clickables nil))
    (when hoverables
      (hoverables:drop)
      (set hoverables nil))
    (when controls
      (controls:drop)
      (set controls nil))
    (when camera
      (camera:drop)
      (set camera nil))
    (set app.scene original-scene)
    (set app.layout-root original-layout-root)
    (set app.movables original-movables)
    (set app.intersectables original-intersectables)
    (set app.camera original-camera)
    (set app.first-person-controls original-controls)
    (set app.hoverables original-hoverables)
    (set app.clickables original-clickables)
    (set app.engine.events original-events)
    (restore-states! original-states)
    (set app.create-default-projection original-create-default-projection)
    (set app.active-interaction-surface original-active-surface)
    (set app.scene-interactive? original-scene-interactive?)
    (set app.canvas-interactive? original-canvas-interactive?))

  (let [(ok err)
        (pcall
          (fn []
            (reset-engine-events)
            (set intersector (Intersectables))
            (set clickables (assert (Clickables {:intersectables intersector}) "Scene ball drag test requires clickables"))
            (set hoverables (assert (Hoverables {:intersectables intersector}) "Scene ball drag test requires hoverables"))
            (set movables (Movables {:intersectables intersector}))
            (set camera (Camera {:position (glm.vec3 0 0 10)}))
            (set controls (FirstPersonControls {:camera camera}))
            (set app.create-default-projection AppProjection.create-default-projection)
            (set scene (Scene {:position (glm.vec3 0 0 0)
                               :rotation (glm.quat 1 0 0 0)
                               :camera camera}))
            (set app.intersectables intersector)
            (set app.clickables clickables)
            (set app.hoverables hoverables)
            (set app.movables movables)
            (set app.camera camera)
            (set app.first-person-controls controls)
            (set app.scene scene)
            (set app.layout-root scene.layout-root)
            (set app.active-interaction-surface :scene)
            (set app.scene-interactive? true)
            (set app.canvas-interactive? false)
             (app.engine.physics:setGravity 0 -25 0)
             (scene:ensure-activity-slot "sandbox")
             (scene:activate-activity-slot "sandbox")
             (scene:build-default {:terrains []})
             (set ball (scene:add-object (Ball {:size (glm.vec3 6 6 6)})
                                        {:position (glm.vec3 0 0 0)}))
            (scene:update)
            (set scene.screen-pos-ray
                 (fn [_self pointer _opts]
                   {:origin (glm.vec3 pointer.x pointer.y 5)
                    :direction (glm.vec3 0 0 -1)}))

            (set state (NormalState))
            (bind-normal-state! state)
            (state.on-enter)

            (app.engine.events.mouse-button-down.emit {:button 1 :x 3.25 :y 3.25 :mod 256})
            (app.engine.events.mouse-motion.emit {:x 7.25 :y 9.25})
            (assert (app.movables:drag-active?) "Ball drag should begin after motion threshold")
            (assert ball.dragging "Ball movable should enter dragging mode")
            (scene:update)

            (assert ball "Scene should create a ball")
            (assert (> ball.layout.position.x 3.5)
                    (string.format
                      "Ball drag should move layout along X (x=%.3f)"
                      ball.layout.position.x))
            (assert (> ball.layout.position.y 5.5)
                    (string.format
                      "Ball drag should move layout along Y (y=%.3f)"
                      ball.layout.position.y))
            (assert (< (math.abs ball.layout.position.z) 1.0)
                    (string.format
                      "Ball drag should keep layout near the drag plane (z=%.3f)"
                      ball.layout.position.z))

            (app.engine.events.mouse-button-up.emit {:button 1})
            (assert (not (app.movables:drag-active?)) "Ball drag should end on mouse-up")))]
    (cleanup)
    (when (not ok)
      (error err))))

(fn drag-through-normal-state-moves-scene-physics-body []
  (local original-scene app.scene)
  (local original-layout-root app.layout-root)
  (local original-movables app.movables)
  (local original-intersectables app.intersectables)
  (local original-camera app.camera)
  (local original-controls app.first-person-controls)
  (local original-hoverables (assert app.hoverables "Scene physics body drag test requires app.hoverables"))
  (local original-clickables (assert app.clickables "Scene physics body drag test requires app.clickables"))
  (local original-events app.engine.events)
  (local original-states app.states)
  (local original-create-default-projection app.create-default-projection)
  (local original-active-surface app.active-interaction-surface)
  (local original-scene-interactive? app.scene-interactive?)
  (local original-canvas-interactive? app.canvas-interactive?)
  (var scene nil)
  (var movables nil)
  (var intersector nil)
  (var clickables nil)
  (var hoverables nil)
  (var camera nil)
  (var controls nil)
  (var state nil)
  (var cuboid nil)

  (fn cleanup [] (assert app.hoverables "Scene physics body drag cleanup requires app.hoverables") (assert app.clickables "Scene physics body drag cleanup requires app.clickables")
    (when state
      (state.on-leave)
      (set state nil))
    (when scene
      (scene:drop)
      (set scene nil))
    (when movables
      (movables:drop)
      (set movables nil))
    (when intersector
      (intersector:drop)
      (set intersector nil))
    (when clickables
      (clickables:drop)
      (set clickables nil))
    (when hoverables
      (hoverables:drop)
      (set hoverables nil))
    (when controls
      (controls:drop)
      (set controls nil))
    (when camera
      (camera:drop)
      (set camera nil))
    (set app.scene original-scene)
    (set app.layout-root original-layout-root)
    (set app.movables original-movables)
    (set app.intersectables original-intersectables)
    (set app.camera original-camera)
    (set app.first-person-controls original-controls)
    (set app.hoverables original-hoverables)
    (set app.clickables original-clickables)
    (set app.engine.events original-events)
    (restore-states! original-states)
    (set app.create-default-projection original-create-default-projection)
    (set app.active-interaction-surface original-active-surface)
    (set app.scene-interactive? original-scene-interactive?)
    (set app.canvas-interactive? original-canvas-interactive?))

  (let [(ok err)
        (pcall
          (fn []
            (reset-engine-events)
            (set intersector (Intersectables))
            (set clickables (assert (Clickables {:intersectables intersector}) "Scene physics body drag test requires clickables"))
            (set hoverables (assert (Hoverables {:intersectables intersector}) "Scene physics body drag test requires hoverables"))
            (set movables (Movables {:intersectables intersector}))
            (set camera (Camera {:position (glm.vec3 0 0 10)}))
            (set controls (FirstPersonControls {:camera camera}))
            (set app.create-default-projection AppProjection.create-default-projection)
            (set scene (Scene {:position (glm.vec3 0 0 0)
                               :rotation (glm.quat 1 0 0 0)
                               :camera camera}))
            (set app.intersectables intersector)
            (set app.clickables clickables)
            (set app.hoverables hoverables)
            (set app.movables movables)
            (set app.camera camera)
            (set app.first-person-controls controls)
            (set app.scene scene)
            (set app.layout-root scene.layout-root)
            (set app.active-interaction-surface :scene)
            (set app.scene-interactive? true)
            (set app.canvas-interactive? false)
             (app.engine.physics:setGravity 0 -25 0)
             (scene:ensure-activity-slot "sandbox")
             (scene:activate-activity-slot "sandbox")
             (scene:build-default {:terrains []})
             (set cuboid (scene:add-physics-body {:position (glm.vec3 0 0 0)
                                                 :size (glm.vec3 6 6 6)}))
            (assert cuboid "Scene should create a runtime physics body")
            (scene:update)
            (set scene.screen-pos-ray
                 (fn [_self pointer _opts]
                   {:origin (glm.vec3 pointer.x pointer.y 5)
                    :direction (glm.vec3 0 0 -1)}))

            (set state (NormalState))
            (bind-normal-state! state)
            (state.on-enter)

            (local initial-selection
              (app.movables.intersector:select-entry app.movables.objects
                                                     {:x 3.25 :y 3.25}
                                                     {:include-point true}))
            (assert initial-selection
                    "Physics body drag test expected a movable selection at the cuboid screen point")
            (local selected-entry (. app.movables.entry-map initial-selection.object))
            (assert (= (and selected-entry selected-entry.target) cuboid.layout)
                    "Physics body drag should select the cuboid movable target")

            (app.engine.events.mouse-button-down.emit {:button 1 :x 3.25 :y 3.25 :mod 256})
            (assert (= (and app.movables.drag app.movables.drag.entry.target) cuboid.layout)
                    "Physics body drag should engage the cuboid movable target on mouse-down")
            (app.engine.events.mouse-motion.emit {:x 8.25 :y 9.25 :mod 256})
            (assert (app.movables:drag-active?)
                    "Physics body drag should begin after motion threshold")
            (local during-motion-x cuboid.layout.position.x)
            (local during-motion-y cuboid.layout.position.y)
            (scene:update)

            (assert (> cuboid.layout.position.x 4.0)
                    (string.format
                      "Physics body drag should move layout along X (during_motion_x=%.3f after_update_x=%.3f)"
                      during-motion-x
                      cuboid.layout.position.x))
            (assert (> cuboid.layout.position.y 5.0)
                    (string.format
                      "Physics body drag should move layout along Y (during_motion_y=%.3f after_update_y=%.3f)"
                      during-motion-y
                      cuboid.layout.position.y))

            (app.engine.events.mouse-button-up.emit {:button 1 :mod 256})
            (scene:update)

            (assert (> cuboid.layout.position.x 4.0)
                    (string.format
                      "Physics body drag should keep X after release (x=%.3f)"
                      cuboid.layout.position.x))
            (assert (> cuboid.layout.position.y 5.0)
                    (string.format
                      "Physics body drag should keep Y after release (y=%.3f)"
                      cuboid.layout.position.y))))]
    (cleanup)
    (when (not ok)
      (error err))))

(fn drag-through-normal-state-moves-scene-entity-when-canvas-hidden []
  (local original-scene app.scene)
  (local original-canvas app.canvas)
  (local original-layout-root app.layout-root)
  (local original-movables app.movables)
  (local original-intersectables app.intersectables)
  (local original-camera app.camera)
  (local original-controls app.first-person-controls)
  (local original-canvas-controls app.canvas-controls)
  (local original-active-pointer-controls app.active-pointer-controls)
  (local original-hoverables (assert app.hoverables "Canvas-hidden scene drag test requires app.hoverables"))
  (local original-clickables (assert app.clickables "Canvas-hidden scene drag test requires app.clickables"))
  (local original-events app.engine.events)
  (local original-states app.states)
  (local original-viewport app.viewport)
  (local original-create-default-projection app.create-default-projection)
  (local original-active-surface app.active-interaction-surface)
  (local original-preferred-surface app.preferred-interaction-surface)
  (local original-scene-interactive? app.scene-interactive?)
  (local original-canvas-interactive? app.canvas-interactive?)
  (local original-canvas-visible? app.canvas-visible?)
  (local original-workspace-shell-changed app.workspace-shell-changed)
  (local original-set-canvas-visible app.set-canvas-visible)
  (local original-set-active-interaction-surface app.set-active-interaction-surface)
  (var scene nil)
  (var canvas nil)
  (var movables nil)
  (var intersector nil)
  (var clickables nil)
  (var hoverables nil)
  (var camera nil)
  (var canvas-camera nil)
  (var controls nil)
  (var canvas-controls nil)
  (var state nil)
  (var target-layout nil)

  (fn cleanup [] (assert app.hoverables "Canvas-hidden scene drag cleanup requires app.hoverables") (assert app.clickables "Canvas-hidden scene drag cleanup requires app.clickables")
    (when state
      (state.on-leave)
      (set state nil))
    (when canvas-controls
      (canvas-controls:drop)
      (set canvas-controls nil))
    (when canvas
      (canvas:drop)
      (set canvas nil))
    (when scene
      (scene:drop)
      (set scene nil))
    (when movables
      (movables:drop)
      (set movables nil))
    (when intersector
      (intersector:drop)
      (set intersector nil))
    (when clickables
      (clickables:drop)
      (set clickables nil))
    (when hoverables
      (hoverables:drop)
      (set hoverables nil))
    (when controls
      (controls:drop)
      (set controls nil))
    (when canvas-camera
      (canvas-camera:drop)
      (set canvas-camera nil))
    (when camera
      (camera:drop)
      (set camera nil))
    (set app.scene original-scene)
    (set app.canvas original-canvas)
    (set app.layout-root original-layout-root)
    (set app.movables original-movables)
    (set app.intersectables original-intersectables)
    (set app.camera original-camera)
    (set app.first-person-controls original-controls)
    (set app.canvas-controls original-canvas-controls)
    (set app.active-pointer-controls original-active-pointer-controls)
    (set app.hoverables original-hoverables)
    (set app.clickables original-clickables)
    (set app.engine.events original-events)
    (restore-states! original-states)
    (set app.viewport original-viewport)
    (set app.create-default-projection original-create-default-projection)
    (set app.active-interaction-surface original-active-surface)
    (set app.preferred-interaction-surface original-preferred-surface)
    (set app.scene-interactive? original-scene-interactive?)
    (set app.canvas-interactive? original-canvas-interactive?)
    (set app.canvas-visible? original-canvas-visible?)
    (set app.workspace-shell-changed original-workspace-shell-changed)
    (set app.set-canvas-visible original-set-canvas-visible)
    (set app.set-active-interaction-surface original-set-active-interaction-surface))

  (local (ok err)
    (pcall
      (fn []
        (reset-engine-events)
        (set intersector (Intersectables))
        (set clickables (assert (Clickables {:intersectables intersector}) "Canvas-hidden scene drag test requires clickables"))
        (set hoverables (assert (Hoverables {:intersectables intersector}) "Canvas-hidden scene drag test requires hoverables"))
        (set movables (Movables {:intersectables intersector}))
        (set app.intersectables intersector)
        (set app.clickables clickables)
        (set app.hoverables hoverables)
        (set app.movables movables)
        (set camera (Camera {:position (glm.vec3 0 0 10)}))
        (set canvas-camera (Camera {:position (glm.vec3 0 0 100)}))
        (set controls (FirstPersonControls {:camera camera}))
        (set app.create-default-projection AppProjection.create-default-projection)
        (set scene (Scene {:position (glm.vec3 0 0 0)
                           :rotation (glm.quat 1 0 0 0)
                           :camera camera}))
        (set canvas (Canvas {:camera canvas-camera
                             :states app.states
                             :movables movables}))
        (set canvas-controls (CanvasControls {:canvas canvas
                                              :camera canvas-camera}))
        (set app.camera camera)
        (set app.first-person-controls controls)
        (set app.canvas-controls canvas-controls)
        (set app.scene scene)
        (set app.canvas canvas)
        (set app.layout-root scene.layout-root)
        (assert Main.install-app-shell!
                "scene drag regression test requires Main.install-app-shell!")
        (Main.install-app-shell!)
        (scene:ensure-activity-slot "sandbox")
        (local sandbox-slot (scene:activate-activity-slot "sandbox"))
        (assert sandbox-slot "Canvas-hidden drag test requires a valid sandbox slot")
        (scene:build
          (fn [_ctx]
            (set target-layout
                 (Layout {:name "integration-drag-target-hidden-canvas"
                          :measurer (fn [self]
                                      (set self.measure (glm.vec3 1 1 1)))
                          :layouter (fn [self]
                                      (set self.size self.measure))}))
            {:layout target-layout
             :drop (fn [_] (target-layout:drop))}))
        (scene:update)
        (set scene.screen-pos-ray
             (fn [_self pointer _opts]
               {:origin (glm.vec3 pointer.x pointer.y 10)
                :direction (glm.vec3 0 0 -1)}))

        (assert app.set-active-interaction-surface
                "scene drag regression test requires app.set-active-interaction-surface")
        (assert app.set-canvas-visible
                "scene drag regression test requires app.set-canvas-visible")
        (app.set-active-interaction-surface :canvas)
        (assert (= app.preferred-interaction-surface :canvas)
                "canvas preference should track explicit canvas activation")
        (assert (= app.active-interaction-surface :canvas)
                "canvas should become active when it is visible")
        (app.set-canvas-visible false)
        (assert (= app.preferred-interaction-surface :canvas)
                "hiding canvas should preserve the preferred surface")
        (assert (= app.active-interaction-surface :scene)
                "hiding canvas should fall back to scene interaction")
        (assert (= app.scene-interactive? true)
                "scene should remain interactive while canvas is hidden")
        (assert (= app.canvas-interactive? false)
                "hidden canvas should not remain interactive")
        (assert (= app.active-pointer-controls app.first-person-controls)
                "scene controls should be restored when canvas is hidden")
        (app.set-canvas-visible true)
        (assert (= app.active-interaction-surface :canvas)
                "restoring canvas visibility should restore the preferred canvas surface")
        (app.set-canvas-visible false)

        (set state (NormalState))
        (bind-normal-state! state)
        (state.on-enter)

        (app.engine.events.mouse-button-down.emit {:button 1 :x 0.25 :y 0.25 :mod 256})
        (app.engine.events.mouse-motion.emit {:x 5.25 :y 5.75})
        (assert (app.movables:drag-active?)
                "Scene drag should still begin when canvas is hidden")

        (assert target-layout "Scene should create a target layout")
        (assert (approx target-layout.position.x 5.0)
                "Hidden canvas should not block scene drag X updates")
        (assert (approx target-layout.position.y 5.5)
                "Hidden canvas should not block scene drag Y updates")
        (assert (approx target-layout.position.z 0.0)
                "Hidden canvas drag should stay on the ground plane")

        (app.engine.events.mouse-button-up.emit {:button 1})
        (assert (not (app.movables:drag-active?))
                "Scene drag should end on mouse-up with hidden canvas"))))
  (cleanup)
  (when (not ok)
    (error err)))

(table.insert tests {:name "Normal state drags real scene entity" :fn drag-through-normal-state-moves-scene-entity})
(table.insert tests {:name "Normal state drags scene ball" :fn drag-through-normal-state-moves-scene-ball})
(table.insert tests {:name "Normal state drags runtime physics body"
                     :fn drag-through-normal-state-moves-scene-physics-body})
(table.insert tests {:name "Normal state keeps scene alt-drag when canvas is hidden"
                     :fn drag-through-normal-state-moves-scene-entity-when-canvas-hidden})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "scene-drag"
                       :tests tests})))

{:name "scene-drag"
 :tests tests
 :main main}
