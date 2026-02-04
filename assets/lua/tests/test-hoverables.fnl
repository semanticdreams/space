(local glm (require :glm))
(local _ (require :main))
(local Hoverables (require :hoverables))

(local tests [])

(fn with-ray-stub [body]
  (local original app.screen-pos-ray)
  (set app.screen-pos-ray
       (fn [pointer]
         {:pointer pointer
          :origin (glm.vec3 0 0 0)
          :direction (glm.vec3 0 0 1)}))
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
       :direction (glm.vec3 0 0 1)
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

(fn make-hoverable [match-x]
  (local state {:hovered false :events []})
  (local obj {:match-x match-x :state state})
  (set obj.intersect
       (fn [self ray]
         (if (and ray.pointer (= ray.pointer.x self.match-x))
             (values true nil 0.5)
             (values false nil nil))))
  (set obj.on-hovered
       (fn [_self entered]
         (set state.hovered entered)
         (table.insert state.events entered)))
  {:object obj :state state})

(fn make-pointer-target-hoverable [target distance]
  (local state {:hovered false})
  (local obj {:pointer-target target})
  (set obj.intersect
       (fn [_self ray]
         (if (= ray.target target)
             (values true nil distance)
             (values false nil nil))))
  (set obj.on-hovered
       (fn [_self entered]
         (set state.hovered entered)))
  {:object obj :state state})

(fn hoverables-dispatch-enter-exit []
  (with-ray-stub
    (fn []
      (local hoverables (Hoverables))
      (local target (make-hoverable 10))
      (hoverables:register target.object)
      (hoverables:on-mouse-motion {:x 10 :y 0})
      (assert target.state.hovered)
      (hoverables:on-mouse-motion {:x 20 :y 0})
      (assert (not target.state.hovered)))))

(fn hoverables-reenter-after-leave []
  (with-ray-stub
    (fn []
      (local hoverables (Hoverables))
      (local target (make-hoverable 12))
      (hoverables:register target.object)
      (hoverables:on-mouse-motion {:x 12 :y 0})
      (hoverables:on-leave)
      (assert (not target.state.hovered))
      (hoverables:on-enter)
      (assert target.state.hovered))))

(fn unregistering-active-stops-hover []
  (with-ray-stub
    (fn []
      (local hoverables (Hoverables))
      (local target (make-hoverable 7))
      (hoverables:register target.object)
      (hoverables:on-mouse-motion {:x 7 :y 0})
      (hoverables:unregister target.object)
      (assert (not target.state.hovered))
      (assert (= hoverables.active-entry nil)))))

(fn hoverables-dont-repeat-enter []
  (with-ray-stub
    (fn []
      (local hoverables (Hoverables))
      (local target (make-hoverable 5))
      (hoverables:register target.object)
      (hoverables:on-mouse-motion {:x 5 :y 0})
      (hoverables:on-mouse-motion {:x 5 :y 1})
      (hoverables:on-mouse-motion {:x 5 :y 2})
      (assert (= (# target.state.events) 1) "should only emit enter once while hovering")
      (assert target.state.hovered)
      (hoverables:on-mouse-motion {:x 8 :y 2})
      (assert (= (# target.state.events) 2) "should record single leave event")
      (assert (not target.state.hovered)))))

(fn hoverables-prefer-hud-intersection []
  (with-pointer-target-rays
    (fn []
      (local hoverables (Hoverables))
      (local hud (make-pointer-target-hoverable app.hud 10))
      (local scene (make-pointer-target-hoverable app.scene 1))
      (hoverables:register hud.object)
      (hoverables:register scene.object)
      (hoverables:on-mouse-motion {:x 0 :y 0})
      (assert hud.state.hovered "hud target should win hover selection")
      (assert (not scene.state.hovered) "scene target should not hover when hud hit"))))

(table.insert tests {:name "Hoverables dispatch enter/exit" :fn hoverables-dispatch-enter-exit})
(table.insert tests {:name "Hoverables reapply pointer on enter" :fn hoverables-reenter-after-leave})
(table.insert tests {:name "Hoverables clear active when unregistering" :fn unregistering-active-stops-hover})
(table.insert tests {:name "Hoverables emit enter once" :fn hoverables-dont-repeat-enter})
(table.insert tests {:name "Hoverables prioritize HUD intersections" :fn hoverables-prefer-hud-intersection})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "hoverables"
                       :tests tests})))

{:name "hoverables"
 :tests tests
 :main main}
