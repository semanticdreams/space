(local glm (require :glm))
(local _ (require :main))
(local Clickables (require :clickables))

(local tests [])

(fn with-pointer-ray [body]
  (local original app.screen-pos-ray)
  (local ray {:origin (glm.vec3 0 0 0) :direction (glm.vec3 0 0 -1)})
  (set app.screen-pos-ray (fn [_pos] ray))
  (let [(ok result) (pcall body)]
    (set app.screen-pos-ray original)
    (when (not ok)
      (error result))
    result))

(fn with-pointer-target-rays [body]
  (local original-scene app.scene)
  (local original-hud app.hud)
  (local original-scene-ray (and original-scene original-scene.screen-pos-ray))
  (local original-hud-ray (and original-hud original-hud.screen-pos-ray))
  (fn make-stub [name]
    (fn [self pointer]
      {:origin pointer
       :direction (glm.vec3 0 0 -1)
       :target self
       :name name}))
  (local scene-target (or original-scene {}))
  (local hud-target (or original-hud {}))
  (set scene-target.screen-pos-ray (make-stub :scene))
  (set hud-target.screen-pos-ray (make-stub :hud))
  (set app.scene scene-target)
  (set app.hud hud-target)
  (let [(ok result) (pcall body)]
    (if original-scene
        (set original-scene.screen-pos-ray original-scene-ray)
        (set app.scene nil))
    (if original-hud
        (set original-hud.screen-pos-ray original-hud-ray)
        (set app.hud nil))
    (when original-scene
      (set app.scene original-scene))
    (when original-hud
      (set app.hud original-hud))
    (when (not ok)
      (error result))
    result))

(fn make-clickable []
  (local state {:clicks 0 :double-clicks 0 :events []})
  (local obj {})
  (set obj.intersect
       (fn [_self _ray]
         (values true (glm.vec3 0 0 0) 5)))
  (set obj.on-click
       (fn [_self event]
         (set state.clicks (+ state.clicks 1))
         (set state.last-event event)))
  (set obj.on-double-click
       (fn [_self event]
         (set state.double-clicks (+ state.double-clicks 1))
         (set state.last-double event)))
  {:object obj :state state})

(fn make-pointer-target-clickable [target distance]
  (local state {:clicks 0})
  (local obj {:pointer-target target})
  (set obj.intersect
       (fn [_self ray]
         (if (= ray.target target)
             (values true (glm.vec3 0 0 0) distance)
             (values false nil nil))))
  (set obj.on-click
       (fn [_self _event]
         (set state.clicks (+ state.clicks 1))))
  {:object obj :state state})

(fn simulate-click [clickables payload]
  (with-pointer-ray
    (fn []
      (clickables:on-mouse-button-down payload)
      (clickables:on-mouse-button-up payload))))

(fn clickables-dispatches-on-click []
  (local clickables (Clickables))
  (local stub (make-clickable))
  (clickables:register stub.object)
  (simulate-click clickables {:button 1 :x 10 :y 12 :timestamp 100})
  (assert (= stub.state.clicks 1))
  (assert stub.state.last-event)
  (assert (= stub.state.last-event.button 1))
  (assert stub.state.last-event.point)
  (assert (= stub.state.last-event.distance 5)))

(fn void-callback-fires-when-no-hit []
  (local clickables (Clickables))
  (var called false)
  (clickables:register-left-click-void-callback
    (fn [_event]
      (set called true)))
  (simulate-click clickables {:button 1 :x 0 :y 0 :timestamp 10})
  (assert called))

(fn double-click-requires-registration []
  (local clickables (Clickables))
  (local stub (make-clickable))
  (clickables:register stub.object)
  (clickables:register-double-click stub.object)
  (simulate-click clickables {:button 1 :x 4 :y 4 :timestamp 10})
  (simulate-click clickables {:button 1 :x 4 :y 4 :timestamp 300})
  (assert (= stub.state.double-clicks 1))
  (assert stub.state.last-double))

(fn clickables-prefer-hud-intersection []
  (with-pointer-target-rays
    (fn []
      (local clickables (Clickables))
      (local hud (make-pointer-target-clickable app.hud 10))
      (local scene (make-pointer-target-clickable app.scene 1))
      (clickables:register hud.object)
      (clickables:register scene.object)
      (simulate-click clickables {:button 1 :x 1 :y 1 :timestamp 42})
      (assert (= hud.state.clicks 1) "hud target should receive click when overlapping scene")
      (assert (= scene.state.clicks 0) "scene target should not receive click when hud hit"))))

(table.insert tests {:name "Clickables send on-click to targets" :fn clickables-dispatches-on-click})
(table.insert tests {:name "Clickables trigger void callback when nothing hit" :fn void-callback-fires-when-no-hit})
(table.insert tests {:name "Clickables detect double clicks for registered widgets" :fn double-click-requires-registration})
(table.insert tests {:name "Clickables prioritize HUD intersections" :fn clickables-prefer-hud-intersection})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "clickables"
                       :tests tests})))

{:name "clickables"
 :tests tests
 :main main}
