(local glm (require :glm))
(local _ (require :main))
(local Movables (require :movables))
(local {: Layout} (require :layout))
(local Intersectables (require :intersectables))
(local Scene (require :scene))
(local MathUtils (require :math-utils))
(local AppProjection (require :app-projection))

(local tests [])

(local approx (. MathUtils :approx))

(fn make-intersector []
  (local stub {:selection-point nil
               :selection-pointer-target nil
               :next-ray nil})
  (set stub.pointer (fn [_ payload]
                      (or payload.pointer payload)))
  (set stub.select-entry
       (fn [self objects pointer opts]
         (set self.last-select {:objects objects :pointer pointer :opts opts})
         (if (and self.selection-point (> (# objects) 0))
             (let [obj (. objects 1)]
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

(fn make-layout []
  (Layout {:name "movable-test"
           :measurer (fn [self]
                       (set self.measure (glm.vec3 1 1 1)))
           :layouter (fn [_self] nil)}))

(fn with-camera [forward body]
  (local original app.camera)
  (set app.camera {:get-forward (fn [_] forward)})
  (let [(ok result) (pcall body)]
    (set app.camera original)
    (when (not ok)
      (error result))
    result))

(fn with-camera-vectors [forward up body]
  (local original app.camera)
  (set app.camera {:get-forward (fn [_] forward)
                   :get-up (fn [_] up)})
  (let [(ok result) (pcall body)]
    (set app.camera original)
    (when (not ok)
      (error result))
    result))

(fn with-screen-ray [ray body]
  (local original app.screen-pos-ray)
  (set app.screen-pos-ray (fn [_pointer _opts] ray))
  (let [(ok result) (pcall body)]
    (set app.screen-pos-ray original)
    (when (not ok)
      (error result))
    result))

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

(fn movables-register-and-unregister []
  (with-camera (glm.vec3 0 0 -1)
    (fn []
      (local intersector (make-intersector))
      (local movables (Movables {:intersectables intersector}))
      (local layout (make-layout))
      (local widget {:layout layout})
      (movables:register widget {:key widget})
      (assert (= (# movables.objects) 1))
      (assert (= (# movables.entries) 1))
      (movables:unregister widget)
      (assert (= (# movables.objects) 0))
      (assert (= (# movables.entries) 0)))))

(fn movables-update-position-while-dragging []
  (with-camera (glm.vec3 0 0 -1)
    (fn []
      (local intersector (make-intersector))
      (local movables (Movables {:intersectables intersector}))
      (local layout (make-layout))
      (set layout.position (glm.vec3 4 5 6))
      (local widget {:layout layout})
      (movables:register widget {:key widget})
      (set intersector.selection-point (glm.vec3 1 2 3))
      (movables:on-mouse-button-down {:button 1 :x 0 :y 0})
      (set intersector.next-ray {:origin (glm.vec3 2 3 10)
                                 :direction (glm.vec3 0 0 -1)})
      (movables:on-mouse-motion {:x 5 :y 6})
      (assert (approx layout.position.x 5))
      (assert (approx layout.position.y 6))
      (assert (approx layout.position.z 6)))))

(fn movables-release-clears-drag []
  (with-camera (glm.vec3 0 0 -1)
    (fn []
      (local intersector (make-intersector))
      (local movables (Movables {:intersectables intersector}))
      (local layout (make-layout))
      (local widget {:layout layout})
      (movables:register widget {:key widget})
      (set intersector.selection-point (glm.vec3 0 0 0))
      (movables:on-mouse-button-down {:button 1 :x 0 :y 0})
      (movables:on-mouse-motion {:x 5 :y 0})
      (assert (movables:drag-active?))
      (movables:on-mouse-button-up {:button 1})
      (assert (not (movables:drag-active?))))))

(fn movables-integrate-with-intersectables []
  (with-camera (glm.vec3 0 0 -1)
    (fn []
      (local intersector (Intersectables))
      (local movables (Movables {:intersectables intersector}))
      (local layout (make-layout))
      (set layout.size (glm.vec3 1 1 1))
      (set layout.position (glm.vec3 0 0 0))
      (local original-scene app.scene)
      (var scene-ray {:origin (glm.vec3 0 0 5) :direction (glm.vec3 0 0 -1)})
      (set app.scene {:screen-pos-ray (fn [_self _pointer _opts] scene-ray)})
      (movables:register {:layout layout})
      (movables:on-mouse-button-down {:button 1 :x 0 :y 0})
      (movables:on-mouse-motion {:x 5 :y 0})
      (assert (movables:drag-active?))
      (set scene-ray {:origin (glm.vec3 1 0 5) :direction (glm.vec3 0 0 -1)})
      (movables:on-mouse-motion {:x 1 :y 0})
      (assert (> layout.position.x 0))
      (set app.scene original-scene))))

(fn scene-registers-simple-entity []
  (local original-scene app.scene)
  (local original-intersectables app.intersectables)
  (local original-movables app.movables)
  (local original-camera app.camera)
  (local original-viewport app.viewport)
  (with-viewport {:x 0 :y 0 :width 640 :height 480}
    (fn []
      (set app.camera {:get-view-matrix (fn [_] (glm.mat4 1))})
      (local intersector (Intersectables))
      (set app.intersectables intersector)
      (local movables (Movables {:intersectables app.intersectables}))
      (set app.movables movables)
      (local scene (Scene {:position (glm.vec3 0 0 0) :rotation (glm.quat 1 0 0 0)}))
      (set app.scene scene)
      (scene:build (fn [_ctx]
                     (local layout
                       (Layout {:name "simple"
                                :measurer (fn [self]
                                            (set self.measure (glm.vec3 1 1 1)))
                                :layouter (fn [self]
                                            (set self.size self.measure))}))
                     {:layout layout
                      :drop (fn [_] (layout:drop))}))
      (scene:update)
      (local entity scene.entity)
      (assert entity "Scene should attach entity")
      (local layout entity.layout)
      (assert layout "Scene entity missing layout")
      (var ray-origin (glm.vec3 0 0 5))
      (set scene.screen-pos-ray
           (fn [_self _pointer _opts]
             {:origin ray-origin :direction (glm.vec3 0 0 -1)}))
      (app.movables:on-mouse-button-down {:button 1 :x 0 :y 0})
      (app.movables:on-mouse-motion {:x 5 :y 0})
      (assert (app.movables:drag-active?))
      (set ray-origin (glm.vec3 1 0 5))
      (app.movables:on-mouse-motion {:x 1 :y 0})
      (assert (> layout.position.x -0.5))
      (app.movables:on-mouse-button-up {:button 1})
      (scene:drop)
      (intersector:drop)
      (movables:drop)
      (set app.scene original-scene)
      (set app.intersectables original-intersectables)
      (set app.movables original-movables)
      (set app.camera original-camera))))

(fn scene-registers-custom-movable-targets []
  (local original-scene app.scene)
  (local original-intersectables app.intersectables)
  (local original-movables app.movables)
  (local original-camera app.camera)
  (local original-viewport app.viewport)
  (with-viewport {:x 0 :y 0 :width 640 :height 480}
    (fn []
      (set app.camera {:get-view-matrix (fn [_] (glm.mat4 1))})
      (local intersector (Intersectables))
      (set app.intersectables intersector)
      (local movables (Movables {:intersectables app.intersectables}))
      (set app.movables movables)
      (local scene (Scene {:position (glm.vec3 0 0 0) :rotation (glm.quat 1 0 0 0)}))
      (set app.scene scene)
      (var first nil)
      (var second nil)
      (var root-layout nil)
      (scene:build (fn [_ctx]
                     (set first
                          (Layout {:name "first"
                                   :measurer (fn [self]
                                               (set self.measure (glm.vec3 1 1 1)))
                                   :layouter (fn [self]
                                               (set self.size self.measure))}))
                     (set second
                          (Layout {:name "second"
                                   :measurer (fn [self]
                                               (set self.measure (glm.vec3 1 1 1)))
                                   :layouter (fn [self]
                                               (set self.size self.measure))}))
                     (set root-layout
                          (Layout {:name "root"
                                   :children [first second]
                                   :measurer (fn [self]
                                               (first:measurer)
                                               (second:measurer)
                                               (set self.measure (glm.vec3 4 1 1)))
                                   :layouter (fn [self]
                                               (set self.size self.measure)
                                               (set first.rotation self.rotation)
                                               (set first.position self.position)
                                               (first:layouter)
                                               (set second.rotation self.rotation)
                                               (set second.position (+ self.position (glm.vec3 2 0 0)))
                                               (second:layouter))}))
                     {:layout root-layout
                      :movables [{:target first :key first}
                                 {:target second :key second}]
                      :drop (fn [_]
                              (root-layout:drop)
                              (first:drop)
                              (second:drop))}))
      (scene:update)
      (assert (> first.measure.x 0.5) "First layout should measure width")
      (assert (> first.size.x 0.5) "First layout should lay out width")
      (assert (> second.measure.x 0.5) "Second layout should measure width")
      (assert (> second.size.x 0.5) "Second layout should lay out width")
      (var ray-origin (glm.vec3 0 0 5))
      (set scene.screen-pos-ray
           (fn [_self _pointer _opts]
             {:origin ray-origin
              :direction (glm.vec3 0 0 -1)}))
      (assert (= (# app.movables.entries) 2)
              "Scene should register provided movable targets")
      (local first-selection (. app.movables.objects 1))
      (local second-selection (. app.movables.objects 2))
      (assert first-selection "First selection object should exist")
      (assert second-selection "Second selection object should exist")
      (assert (= first-selection.pointer-target scene)
              "First selection should target scene")
      (assert (= second-selection.pointer-target scene)
              "Second selection should target scene")
      (set ray-origin (glm.vec3 0.25 0 5))
      (app.movables:on-mouse-button-down {:button 1 :x 0.25 :y 0})
      (set ray-origin (glm.vec3 5 0 5))
      (app.movables:on-mouse-motion {:x 5 :y 0})
      (assert (app.movables:drag-active?)
              "Drag should activate for first movable")
      (set ray-origin (glm.vec3 1.25 0 5))
      (app.movables:on-mouse-motion {:x 1.25 :y 0})
      (assert (> first.position.x 0.75)
              "Drag should update first movable position")
      (assert (< (math.abs (- second.position.x 2)) 1e-4)
              "Second movable should remain stationary")
      (app.movables:on-mouse-button-up {:button 1})
      (assert (not (app.movables:drag-active?))
              "Drag should end after releasing first movable")
      (set ray-origin (glm.vec3 2.25 0 5))
      (app.movables:on-mouse-button-down {:button 1 :x 2.25 :y 0})
      (set ray-origin (glm.vec3 10 0 5))
      (app.movables:on-mouse-motion {:x 10 :y 0})
      (assert (app.movables:drag-active?)
              "Drag should activate for second movable")
      (set ray-origin (glm.vec3 3.25 0 5))
      (app.movables:on-mouse-motion {:x 3.25 :y 0})
      (assert (> second.position.x 2.5)
              "Drag should update second movable position")
      (assert (> first.position.x 0.75)
              "First movable should retain its updated position")
      (app.movables:on-mouse-button-up {:button 1})
      (assert (not (app.movables:drag-active?))
              "Drag should end after releasing second movable")
      (scene:drop)
      (intersector:drop)
      (movables:drop)
      (set app.scene original-scene)
      (set app.intersectables original-intersectables)
      (set app.movables original-movables)
      (set app.camera original-camera))))

(fn movables-fire-drag-hooks []
  (with-camera (glm.vec3 0 0 -1)
    (fn []
      (local intersector (make-intersector))
      (local movables (Movables {:intersectables intersector}))
      (local layout (make-layout))
      (var started false)
      (var ended false)
      (movables:register {:layout layout}
                         {:key layout
                          :on-drag-start (fn [_] (set started true))
                          :on-drag-end (fn [_] (set ended true))})
      (set intersector.selection-point (glm.vec3 0 0 0))
      (movables:on-mouse-button-down {:button 1 :x 0 :y 0})
      (movables:on-mouse-motion {:x 10 :y 0})
      (assert started "Expected on-drag-start to fire")
      (movables:on-mouse-button-up {:button 1})
      (assert ended "Expected on-drag-end to fire"))))

(fn movables-shift-drag-uses-up-plane []
  (with-camera-vectors (glm.vec3 0 0 -1) (glm.vec3 0 1 0)
    (fn []
      (local intersector (make-intersector))
      (local movables (Movables {:intersectables intersector :drag-threshold 0}))
      (local layout (make-layout))
      (set layout.position (glm.vec3 4 5 6))
      (movables:register {:layout layout})
      (set intersector.selection-point (glm.vec3 1 2 3))
      (movables:on-mouse-button-down {:button 1 :x 0 :y 0})
      (set intersector.next-ray {:origin (glm.vec3 2 10 3)
                                 :direction (glm.vec3 0 -1 0)})
      (movables:on-mouse-motion {:x 0 :y 0 :mod 1})
      (assert (approx layout.position.y 5)
              "Shift drag should keep Y constant when using camera up plane")
      (assert (approx layout.position.z 3)
              "Shift drag should move along plane normal to camera up"))))

(fn movables-shift-toggle-restores-forward-plane []
  (with-camera-vectors (glm.vec3 0 0 -1) (glm.vec3 0 1 0)
    (fn []
      (local intersector (make-intersector))
      (local movables (Movables {:intersectables intersector :drag-threshold 0}))
      (local layout (make-layout))
      (set layout.position (glm.vec3 4 5 6))
      (movables:register {:layout layout})
      (set intersector.selection-point (glm.vec3 1 2 3))
      (movables:on-mouse-button-down {:button 1 :x 0 :y 0 :mod 1})
      (set intersector.next-ray {:origin (glm.vec3 2 10 3)
                                 :direction (glm.vec3 0 -1 0)})
      (movables:on-mouse-motion {:x 0 :y 0 :mod 1})
      (local prior-z layout.position.z)
      (set intersector.next-ray {:origin (glm.vec3 8 5 10)
                                 :direction (glm.vec3 0 0 -1)})
      (movables:on-mouse-motion {:x 0 :y 0 :mod 0})
      (assert (approx layout.position.y 5)
              "Forward drag should keep Y stable after shift release")
      (assert (approx layout.position.z prior-z)
              "Forward drag should keep Z on the forward plane"))))

(table.insert tests {:name "Movables register/unregister layouts" :fn movables-register-and-unregister})
(table.insert tests {:name "Movables update layout positions while dragging" :fn movables-update-position-while-dragging})
(table.insert tests {:name "Movables clear drag state on release" :fn movables-release-clears-drag})
(table.insert tests {:name "Movables integrate with Intersectables" :fn movables-integrate-with-intersectables})
(table.insert tests {:name "Scene registers simple entity with Movables" :fn scene-registers-simple-entity})
(table.insert tests {:name "Scene registers explicit movable targets" :fn scene-registers-custom-movable-targets})
(table.insert tests {:name "Movables fire drag start/end hooks" :fn movables-fire-drag-hooks})
(table.insert tests {:name "Movables shift drag uses camera up plane" :fn movables-shift-drag-uses-up-plane})
(table.insert tests {:name "Movables shift toggle restores forward plane" :fn movables-shift-toggle-restores-forward-plane})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "movables"
                       :tests tests})))

{:name "movables"
 :tests tests
 :main main}
