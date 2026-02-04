(local glm (require :glm))
(local _ (require :main))
(local NormalState (require :normal-state))
(local Scene (require :scene))
(local Movables (require :movables))
(local Intersectables (require :intersectables))
(local Clickables (require :clickables))
(local Hoverables (require :hoverables))
(local Camera (require :camera))
(local MathUtils (require :math-utils))
(local {: Layout} (require :layout))
(local {: FirstPersonControls} (require :first-person-controls))

(local tests [])

(local approx (. MathUtils :approx))

(fn drag-through-normal-state-moves-scene-entity []
  (local original-scene app.scene)
  (local original-layout-root app.layout-root)
  (local original-movables app.movables)
  (local original-intersectables app.intersectables)
  (local original-camera app.camera)
  (local original-controls app.first-person-controls)
  (local original-hoverables app.hoverables)
  (local original-clickables app.clickables)
  (local original-events app.engine.events)
  (local original-viewport app.viewport)
  (var scene nil)
  (var movables nil)
  (var intersector nil)
  (var clickables nil)
  (var hoverables nil)
  (var camera nil)
  (var controls nil)
  (var state nil)
  (var target-layout nil)

  (fn cleanup []
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
    (set app.viewport original-viewport))

  (let [(ok err)
        (pcall
          (fn []
            (reset-engine-events)
            (set intersector (Intersectables))
            (set clickables (Clickables {:intersectables intersector}))
            (set hoverables (Hoverables {:intersectables intersector}))
            (set movables (Movables {:intersectables intersector}))
            (set camera (Camera {:position (glm.vec3 0 0 10)}))
            (set controls (FirstPersonControls {:camera camera}))
            (set scene (Scene {:position (glm.vec3 0 0 0)
                               :rotation (glm.quat 1 0 0 0)}))
            (set app.intersectables intersector)
            (set app.clickables clickables)
            (set app.hoverables hoverables)
            (set app.movables movables)
            (set app.camera camera)
            (set app.first-person-controls controls)
            (set app.scene scene)
            (set app.layout-root scene.layout-root)
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
                   {:origin (glm.vec3 pointer.x pointer.y 5)
                    :direction (glm.vec3 0 0 -1)}))

            (set state (NormalState))
            (state.on-enter)

            (app.engine.events.mouse-button-down.emit {:button 1 :x 0.25 :y 0.25 :mod 256})
            (app.engine.events.mouse-motion.emit {:x 5.25 :y 5.75})
            (assert (app.movables:drag-active?) "Drag should begin after motion threshold")

            (assert target-layout "Scene should create a target layout")
            (assert (approx target-layout.position.x 5.0) "Drag should update layout X position")
            (assert (approx target-layout.position.y 5.5) "Drag should update layout Y position")
            (assert (approx target-layout.position.z 0.0) "Drag should keep layout on the ground plane")
            (local root scene.layout-root)
            (assert root "Scene should expose a layout root")
            (assert (. root.layout-dirt.lookup target-layout) "Drag should mark layout node dirty")

            (app.engine.events.mouse-button-up.emit {:button 1})
            (assert (not (app.movables:drag-active?)) "Drag should end on mouse-up")))]
    (cleanup)
    (when (not ok)
      (error err))))

(table.insert tests {:name "Normal state drags real scene entity" :fn drag-through-normal-state-moves-scene-entity})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "scene-drag"
                       :tests tests})))

{:name "scene-drag"
 :tests tests
 :main main}
