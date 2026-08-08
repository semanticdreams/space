(local glm (require :glm))
(local Intersectables (require :intersectables))
(local Movables (require :movables))
(local PointerHandlers (require :state-handlers/pointer))

(local tests [])

(fn canvas-test-ray [_self pointer]
  {:origin (glm.vec3 pointer.x pointer.y 10)
   :direction (glm.vec3 0 0 -1)})

(fn intersect-origin [_self _ray]
  (values true (glm.vec3 0 0 0) 1))

(fn set-position [self position]
  (set self.position position))

(fn no-camera [] nil)

(fn make-target []
  {:position (glm.vec3 0 0 0)
   :set-position set-position})

(fn make-handle [pointer-target]
  {:pointer-target pointer-target
   :intersect intersect-origin})

(fn make-pointer-target []
  {:interaction-surface :canvas
   :screen-pos-ray canvas-test-ray})

(fn app-snapshot []
  {:movables app.movables
   :active-interaction-surface app.active-interaction-surface
   :canvas-interactive? app.canvas-interactive?
   :scene-interactive? app.scene-interactive?
   :activity-object-drag-mode-provider app.activity-object-drag-mode-provider
   :presentation-camera app.presentation-camera})

(fn restore-app! [snapshot]
  (set app.movables snapshot.movables)
  (set app.active-interaction-surface snapshot.active-interaction-surface)
  (set app.canvas-interactive? snapshot.canvas-interactive?)
  (set app.scene-interactive? snapshot.scene-interactive?)
  (set app.activity-object-drag-mode-provider snapshot.activity-object-drag-mode-provider)
  (set app.presentation-camera snapshot.presentation-camera))

(fn route-movable-down [payload]
  (local ctx {:app app
              :event-consumed? (fn [] false)})
  ((. PointerHandlers.MovableMouseButtonDown :mouse-button-down) ctx payload))

(fn with-routing-fixture [surface f]
  (local snapshot (app-snapshot))
  (local intersector (Intersectables))
  (local movables (Movables {:intersectables intersector}))
  (local pointer-target (make-pointer-target))
  (local target (make-target))
  (set app.movables movables)
  (set app.active-interaction-surface surface)
  (set app.canvas-interactive? (= surface :canvas))
  (set app.scene-interactive? (= surface :scene))
  (set app.activity-object-drag-mode-provider nil)
  (set app.presentation-camera no-camera)
  (movables:register (make-handle pointer-target)
                      {:target target
                       :pointer-target pointer-target})
  (local (ok result) (pcall f movables target))
  (movables:drop)
  (restore-app! snapshot)
  (if ok result (error result)))

(fn canvas-alt-left-starts-shared-movable-drag []
  (with-routing-fixture
    :canvas
    (fn [movables target]
      (route-movable-down {:button 1 :x 0 :y 0 :mod 256})
      (movables:on-mouse-motion {:x 20 :y 0 :mod 256})
      (assert (movables:drag-active?)
              "Canvas Alt-left down routed through pointer handler should engage Movables")
      (assert (> target.position.x 1.5)
              "Canvas Alt-left routed drag should move the shared Movables target"))))

(fn scene-alt-left-without-provider-does-not-start-shared-movable-drag []
  (with-routing-fixture
    :scene
    (fn [movables _target]
      (route-movable-down {:button 1 :x 0 :y 0 :mod 256})
      (movables:on-mouse-motion {:x 20 :y 0 :mod 256})
      (assert (not (movables:drag-engaged?))
              "Scene Alt-left down without provider must not engage Movables"))))

(table.insert tests {:name "Canvas Alt-left starts shared Movables through pointer handler"
                     :fn canvas-alt-left-starts-shared-movable-drag})
(table.insert tests {:name "Scene Alt-left without provider is blocked in pointer handler"
                     :fn scene-alt-left-without-provider-does-not-start-shared-movable-drag})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "pointer-routing" :tests tests})))

{:name "pointer-routing"
 :tests tests
 :main main}
