(local glm (require :glm))
(local _ (require :main))
(local MathUtils (require :math-utils))
(local AppProjection (require :app-projection))
(local Intersectables (require :intersectables))
(local Resizables (require :resizables))
(local Scene (require :scene))
(local State (require :state))
(local Routes (require :state-routes))
(local HoverHandlers (require :state-handlers/hover))
(local PointerHandlers (require :state-handlers/pointer))
(local {: Layout} (require :layout))

(local tests [])
(local approx (. MathUtils :approx))

(fn make-intersector []
  (local stub {:selection-point nil
               :selection-pointer-target nil
               :next-ray nil})
  (set stub.pointer (fn [_ payload]
                      (or payload.pointer payload)))
  (set stub.select-entry
       (fn [self objects pointer _opts]
         (set self.last-select {:objects objects :pointer pointer})
         (if (and self.selection-point (> (# objects) 0))
             (do
               (local obj (. objects 1))
               (when obj
                 {:object obj
                  :point self.selection-point
                  :pointer-target (or self.selection-pointer-target obj.pointer-target)
                  :distance 0.5}))
             nil)))
  (set stub.resolve-ray
       (fn [self pointer target]
         (set self.last-resolve {:pointer pointer :target target})
         self.next-ray))
  stub)

(fn make-layout [size]
  (local layout
    (Layout {:name "resizable-test"
             :measurer (fn [self]
                         (set self.measure size))
             :layouter (fn [_self] nil)}))
  (set layout.position (glm.vec3 0 0 0))
  (set layout.rotation (glm.quat 1 0 0 0))
  (set layout.size size)
  (set layout.measure size)
  layout)

(fn with-viewport [viewport body]
  (local original-set app.set-viewport)
  (local original-viewport app.viewport)
  (local original-create app.create-default-projection)
  (when (not original-set)
    (set app.set-viewport (fn [value] (set app.viewport value))))
  (when (not original-create)
    (set app.create-default-projection AppProjection.create-default-projection))
  (app.set-viewport viewport)
  (let [(ok result) (pcall body)]
    (set app.set-viewport original-set)
    (set app.viewport original-viewport)
    (set app.create-default-projection original-create)
    (when (not ok)
      (error result))
    result))

(fn resizable-waits-for-threshold []
  (local intersector (make-intersector))
  (local resizables (Resizables {:intersectables intersector}))
  (local layout (make-layout (glm.vec3 10 10 0)))
  (resizables:register layout {:target layout
                               :handle layout
                               :min-size layout.measure})
  (set intersector.selection-point (glm.vec3 9 9 0))
  (resizables:on-mouse-button-down {:button 3 :x 0 :y 0})
  (set intersector.next-ray {:origin (glm.vec3 6 4 5)
                             :direction (glm.vec3 0 0 -1)})
  (resizables:on-mouse-motion {:x 1 :y 0})
  (assert (approx layout.size.x 10) "Resize should wait for drag threshold")
  (assert (approx layout.position.x 0) "Resize should not move until threshold"))

(fn resizable-respects-min-size []
  (local intersector (make-intersector))
  (local resizables (Resizables {:intersectables intersector}))
  (local layout (make-layout (glm.vec3 10 10 0)))
  (resizables:register layout {:target layout
                               :handle layout
                               :min-size (glm.vec3 6 10 0)})
  (set intersector.selection-point (glm.vec3 9 4 0))
  (resizables:on-mouse-button-down {:button 3 :x 0 :y 0})
  (set intersector.next-ray {:origin (glm.vec3 14 4 5)
                             :direction (glm.vec3 0 0 -1)})
  (resizables:on-mouse-motion {:x 14 :y 0})
  (assert (approx layout.size.x 14) "Resize should grow along X")
  (assert (approx layout.size.y 10) "Resize should clamp to min Y")
  (assert (approx layout.position.x 0) "Resize should keep min edge fixed")
  (assert (approx layout.position.y 0) "Resize should keep min edge fixed"))

(fn resizable-fires-hooks []
  (local intersector (make-intersector))
  (local resizables (Resizables {:intersectables intersector}))
  (local layout (make-layout (glm.vec3 10 10 0)))
  (var started false)
  (var ended false)
  (resizables:register layout {:target layout
                               :handle layout
                               :min-size layout.measure
                               :on-resize-start (fn [_entry] (set started true))
                               :on-resize-end (fn [_entry] (set ended true))})
  (set intersector.selection-point (glm.vec3 9 4 0))
  (resizables:on-mouse-button-down {:button 3 :x 0 :y 0})
  (set intersector.next-ray {:origin (glm.vec3 8 4 5)
                             :direction (glm.vec3 0 0 -1)})
  (resizables:on-mouse-motion {:x 10 :y 0})
  (assert started "Resize should fire start hook")
  (resizables:on-mouse-button-up {:button 3 :x 10 :y 0})
  (assert ended "Resize should fire end hook"))

(fn resizable-works-with-intersectables []
  (local intersector (Intersectables))
  (local resizables (Resizables {:intersectables intersector
                                 :drag-threshold 0}))
  (local layout (make-layout (glm.vec3 10 10 0)))
  (local target {:screen-pos-ray (fn [_self pointer]
                                   {:origin (glm.vec3 pointer.x pointer.y 10)
                                    :direction (glm.vec3 0 0 -1)})})
  (resizables:register layout {:target layout
                               :handle layout
                               :pointer-target target
                               :min-size (glm.vec3 0 0 0)})
  (resizables:on-mouse-button-down {:button 3 :x 9 :y 9})
  (resizables:on-mouse-motion {:x 14 :y 14})
  (assert (> layout.size.x 10) "Resize should update size with intersectables")
  (assert (> layout.size.y 10) "Resize should update size with intersectables"))

(fn scene-resizables-use-own-scene-pointer-target-during-registration []
  (local original-scene app.scene)
  (local original-intersectables app.intersectables)
  (local original-resizables app.resizables)
  (local original-camera app.camera)
  (with-viewport {:x 0 :y 0 :width 640 :height 480}
    (fn []
      (set app.camera {:get-view-matrix (fn [_] (glm.mat4 1))})
      (local intersector (make-intersector))
      (set app.intersectables intersector)
      (local resizables (Resizables {:intersectables app.intersectables
                                     :drag-threshold 0}))
      (set app.resizables resizables)
      (local previous-scene {:screen-pos-ray (fn [_self _pointer _opts]
                                               {:origin (glm.vec3 99 99 5)
                                                :direction (glm.vec3 0 0 -1)})})
      (set app.scene previous-scene)
      (local scene (Scene {:position (glm.vec3 0 0 0) :rotation (glm.quat 1 0 0 0)}))
      (scene:build (fn [_ctx]
                     (local root-layout (make-layout (glm.vec3 20 20 0)))
                     (local child-layout (make-layout (glm.vec3 10 10 0)))
                     (root-layout:add-child child-layout)
                     (local child-element {:layout child-layout
                                           :drop (fn [_] nil)})
                     {:layout root-layout
                      :children [{:element child-element}]
                      :scene-children [{:element child-element}]
                      :drop (fn [_] (root-layout:drop))}))
      (scene:update)
      (local entry (. app.resizables.entries 1))
      (assert entry "Scene should register a resizable entry")
      (assert (= entry.pointer-target scene)
              "Scene resizable registration should bind pointer-target to the new scene")
      (scene:drop)
      (resizables:drop)
      (set app.scene original-scene)
      (set app.intersectables original-intersectables)
      (set app.resizables original-resizables)
      (set app.camera original-camera))))

(fn default-state-dispatches-alt-resize []
  (local originals {:resizables app.resizables
                    :clickables app.clickables
                    :movables app.movables})
  (var called false)
  (local resizables {:on-mouse-button-down (fn [_self _payload]
                                             (set called true)
                                             true)
                     :on-mouse-button-up (fn [_self _payload] nil)
                     :on-mouse-motion (fn [_self _payload] nil)
                     :drag-active? (fn [_self] false)
                     :drag-engaged? (fn [_self] false)})
  (local clickables {:on-mouse-button-down (fn [_self _payload] nil)
                     :on-mouse-button-up (fn [_self _payload] nil)
                     :active? false})
  (set app.resizables resizables)
  (set app.clickables clickables)
  (set app.movables nil)
  (local state (State {:name :resizable-test
                       :routes {:mouse-button-down (Routes.Chain [PointerHandlers.InputMouseButtonDownDispatch
                                                                 PointerHandlers.ResizableMouseButtonDown
                                                                 PointerHandlers.ClickableMouseButtonDown
                                                                 PointerHandlers.MovableMouseButtonDown
                                                                 PointerHandlers.SelectionMouseButtonDown
                                                                 PointerHandlers.CameraMouseButtonDown])}
                       :enter [HoverHandlers.HoverLifecycle]
                       :leave [HoverHandlers.HoverLifecycle]}))
  (state.on-mouse-button-down {:button 3 :x 0 :y 0 :mod 256})
  (set app.resizables originals.resizables)
  (set app.clickables originals.clickables)
  (set app.movables originals.movables)
  (assert called "State should forward alt+right click to resizables"))

(table.insert tests {:name "Resizables wait for threshold" :fn resizable-waits-for-threshold})
(table.insert tests {:name "Resizables clamp to min size" :fn resizable-respects-min-size})
(table.insert tests {:name "Resizables fire hooks" :fn resizable-fires-hooks})
(table.insert tests {:name "Resizables integrate with intersectables" :fn resizable-works-with-intersectables})
(table.insert tests {:name "Scene resizables bind pointer target to their own scene"
                     :fn scene-resizables-use-own-scene-pointer-target-during-registration})
(table.insert tests {:name "Default state forwards alt resize" :fn default-state-dispatches-alt-resize})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "resizables"
                       :tests tests})))

{:name "resizables"
 :tests tests
 :main main}
