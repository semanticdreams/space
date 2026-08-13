(local Boundary (require :activity-surface-boundary))
(local glm (require :glm))
(local Camera (require :camera))
(local Canvas (require :canvas))
(local Scene (require :scene))
(local {: FocusManager} (require :focus))

(local tests [])

(fn snapshot-app-fields [keys]
  (local snapshot {:keys keys
                   :values {}})
  (each [_ key (ipairs keys)]
    (set (. snapshot.values key) (. app key)))
  snapshot)

(fn restore-app-fields! [snapshot]
  (each [_ key (ipairs snapshot.keys)]
    (set (. app key) (. snapshot.values key)))
  true)

(fn with-boundary-app [fields f]
  (local snapshot (snapshot-app-fields [:active-activity-id
                                        :activity-registry
                                        :active-world-runtime]))
  (set app.active-activity-id fields.active-activity-id)
  (set app.activity-registry fields.activity-registry)
  (set app.active-world-runtime fields.active-world-runtime)
  (local (ok result) (pcall f))
  (restore-app-fields! snapshot)
  (if ok
      result
      (error result)))

(fn expect-foreign-slot-denied []
  (Boundary.assert-slot-owner! :canvas "set-camera" "graph" {}))

(fn expect-empty-direct-ray-denied []
  (Boundary.assert-screen-ray-authorized! :canvas "screen-pos-ray" {} nil))

(fn assert-error-contains [err fragments]
  (local message (tostring err))
  (each [_ fragment (ipairs fragments)]
    (assert (string.find message fragment 1 true)
            (.. "Expected error to contain `" fragment "`, got: " message))))

(fn with-surfaces [f]
  (local snapshot (snapshot-app-fields [:viewport]))
  (local focus-manager (FocusManager {:root-name "activity-boundary-test-focus"}))
  (local canvas-camera (Camera {:position (glm.vec3 0 0 10)}))
  (local scene-camera (Camera {:position (glm.vec3 0 0 10)}))
  (local canvas (Canvas {:camera canvas-camera :focus-manager focus-manager}))
  (local scene (Scene {:camera scene-camera :focus-manager focus-manager}))
  (set app.viewport {:x 0 :y 0 :width 100 :height 100})
  (canvas:on-viewport-changed app.viewport)
  (scene:on-viewport-changed app.viewport)
  (local (ok result) (pcall f {:canvas canvas
                               :scene scene
                               :canvas-camera canvas-camera
                               :scene-camera scene-camera
                               :focus-manager focus-manager}))
  (pcall (fn [] (canvas:drop)))
  (pcall (fn [] (scene:drop)))
  (pcall (fn [] (canvas-camera:drop)))
  (pcall (fn [] (scene-camera:drop)))
  (pcall (fn [] (focus-manager:drop)))
  (restore-app-fields! snapshot)
  (if ok
      result
      (error result)))

(fn with-active-bubbles-surfaces [f]
  (with-boundary-app
    {:activity-registry {:active-activity-id "bubbles"}}
    (fn []
      (with-surfaces f))))

(fn camera-at-z [z]
  (Camera {:position (glm.vec3 0 0 z)}))

(fn assert-denied-boundary-error [ok err fragments assertion]
  (assert (not ok) assertion)
  (assert-error-contains err fragments))

(fn matching-owner-can-mutate-slot []
  (with-boundary-app
    {:activity-registry {:active-activity-id "bubbles"}}
    (fn []
      (assert (= (Boundary.assert-slot-owner! :canvas "set-camera" "bubbles" {}) true)))))

(fn runtime-active-owner-fallback-authorizes-slot []
  (with-boundary-app
    {:activity-registry {}
     :active-world-runtime {:active-activity-id "bubbles"}}
    (fn []
      (assert (= (Boundary.active-owner-id) "bubbles"))
      (assert (= (Boundary.assert-slot-owner! :canvas "set-camera" "bubbles" {}) true)))))

(fn app-active-owner-fallback-authorizes-slot []
  (with-boundary-app
    {:activity-registry {}
     :active-world-runtime {}
     :active-activity-id "bubbles"}
    (fn []
      (assert (= (Boundary.active-owner-id) "bubbles"))
      (assert (= (Boundary.assert-slot-owner! :canvas "set-camera" "bubbles" {}) true)))))

(fn runtime-activating-owner-takes-priority []
  (with-boundary-app
    {:activity-registry {:active-activity-id "graph"}
     :active-world-runtime {:activating-activity-id "bubbles"}}
    (fn []
      (assert (= (Boundary.activating-owner-id) "bubbles"))
      (assert (= (Boundary.expected-owner-id) "bubbles"))
      (assert (= (Boundary.assert-slot-owner! :canvas "set-camera" "bubbles" {}) true)))))

(fn foreign-owner-cannot-mutate-slot []
  (with-boundary-app
    {:activity-registry {:active-activity-id "bubbles"}}
    (fn []
      (local (ok err) (pcall expect-foreign-slot-denied))
      (assert (not ok) "Foreign activity slot mutation must fail")
      (assert-error-contains err ["activity surface boundary denied"
                                  "canvas"
                                  "set-camera"
                                  "graph"
                                  "bubbles"]))))

(fn explicit-matrix-ray-opts-are-authorized []
  (with-boundary-app
    {:activity-registry {:active-activity-id "bubbles"}}
    (fn []
      (assert (= (Boundary.assert-screen-ray-authorized! :canvas "screen-pos-ray"
                                                         {:view :view-matrix
                                                          :projection :projection-matrix}
                                                         nil)
                 true)))))

(fn empty-direct-ray-opts-fail-in-active-context []
  (with-boundary-app
    {:activity-registry {:active-activity-id "bubbles"}}
    (fn []
      (local (ok err) (pcall expect-empty-direct-ray-denied))
      (assert (not ok) "Ambiguous direct ray must fail in active activity context")
      (assert-error-contains err ["ambiguous direct screen ray"
                                  "presentation target/helper"]))))

(fn active-activity-slot-authorizes-ray []
  (with-boundary-app
    {:activity-registry {:active-activity-id "bubbles"}}
    (fn []
      (assert (= (Boundary.assert-screen-ray-authorized! :canvas "screen-pos-ray"
                                                         {:activity-slot {:activity-id "bubbles"}}
                                                         nil)
                 true)))))

(fn target-ownership-requires-active-slot-in-active-context []
  (with-boundary-app
    {:activity-registry {:active-activity-id "bubbles"}}
    (fn []
      (assert (Boundary.target-owned-by-active? {:kind :hud})
              "Non-scene/canvas targets without slots should stay authorized")
      (assert (Boundary.target-owned-by-active? {:kind :canvas
                                                :slot {:activity-id "bubbles"}})
              "Scene/canvas targets owned by the active slot should be authorized")
      (assert (not (Boundary.target-owned-by-active? {:kind :canvas}))
              "Scene/canvas targets without slots should not be active-owned")
      (assert (not (Boundary.target-owned-by-active? {:kind :scene
                                                     :slot {:activity-id "graph"}}))
              "Foreign scene/canvas targets should not be active-owned"))))

(fn foreign-pointer-target-is-not-active-owned []
  (with-boundary-app
    {:activity-registry {:active-activity-id "bubbles"}}
    (fn []
      (assert (Boundary.target-owned-by-active? {:interaction-surface :canvas
                                                :activity-slot {:activity-id "bubbles"}})
              "Active canvas pointer targets should be authorized")
      (assert (not (Boundary.target-owned-by-active? {:interaction-surface :canvas
                                                     :activity-slot {:activity-id "graph"}}))
              "Foreign canvas pointer targets should not be active-owned"))))

(fn deactivate-foreign-slots-preserves-active-slot []
  (local calls [])
  (local bubbles-slot {:activity-id "bubbles"
                       :visible? true
                       :interactive? true})
  (local graph-slot {:activity-id "graph"
                     :visible? true
                     :interactive? true})
  (local surface
    {:activity-slots {:bubbles bubbles-slot
                      :graph graph-slot}
     :active-activity-slot graph-slot
     :active-activity-slot-id "graph"
     :deactivate-activity-slot (fn [self activity-id opts]
                                 (table.insert calls {:activity-id activity-id
                                                      :opts opts})
                                 (local slot (. self.activity-slots activity-id))
                                 (when slot
                                   (set slot.visible? false)
                                   (set slot.interactive? false))
                                 slot)})
  (local count (Boundary.deactivate-foreign-slots! surface "bubbles"))
  (assert (= count 1))
  (assert (= (length calls) 1))
  (assert (= (. (. calls 1) :activity-id) "graph"))
  (assert (= (. (. (. calls 1) :opts) :boundary-internal?) true))
  (assert (not graph-slot.visible?))
  (assert (not graph-slot.interactive?))
  (assert bubbles-slot.visible?)
  (assert bubbles-slot.interactive?)
  (assert (= surface.active-activity-slot nil))
  (assert (= surface.active-activity-slot-id nil)))

(fn exercise-canvas-foreign-slot-denial [ctx]
  (local camera (camera-at-z 20))
  (local (ok err) (pcall (fn []
                           (ctx.canvas:ensure-activity-slot "graph" {:camera camera}))))
  (pcall (fn [] (camera:drop)))
  (assert-denied-boundary-error ok err ["activity surface boundary denied"
                                        "canvas"
                                        "ensure-activity-slot"
                                        "graph"
                                        "bubbles"]
                                "Canvas must reject foreign activity slots"))

(fn canvas-rejects-foreign-activity-slot []
  (with-active-bubbles-surfaces exercise-canvas-foreign-slot-denial))

(fn exercise-canvas-active-slot-allowed [ctx]
  (local camera (camera-at-z 20))
  (local slot (ctx.canvas:ensure-activity-slot "bubbles" {:camera camera}))
  (assert slot "Canvas should return the active activity slot")
  (assert (= slot.activity-id "bubbles"))
  (pcall (fn [] (camera:drop))))

(fn canvas-allows-active-activity-slot []
  (with-active-bubbles-surfaces exercise-canvas-active-slot-allowed))

(fn exercise-scene-foreign-slot-denial [ctx]
  (local camera (camera-at-z 20))
  (local (ok err) (pcall (fn []
                           (ctx.scene:ensure-activity-slot "sandbox" {:camera camera}))))
  (pcall (fn [] (camera:drop)))
  (assert-denied-boundary-error ok err ["activity surface boundary denied"
                                        "scene"
                                        "ensure-activity-slot"
                                        "sandbox"
                                        "bubbles"]
                                "Scene must reject foreign activity slots"))

(fn scene-rejects-foreign-activity-slot []
  (with-active-bubbles-surfaces exercise-scene-foreign-slot-denial))

(fn expose-active-bubbles-slots! [ctx canvas-camera scene-camera]
  (local canvas-slot (ctx.canvas:ensure-activity-slot "bubbles" {:camera canvas-camera}))
  (local scene-slot (ctx.scene:ensure-activity-slot "bubbles" {:camera scene-camera}))
  (ctx.canvas:activate-activity-slot "bubbles")
  (ctx.scene:activate-activity-slot "bubbles")
  (canvas-slot:expose-render-target! {})
  (scene-slot:expose-render-target! {}))

(fn exercise-direct-surface-ray-denial [ctx]
  (local canvas-camera (camera-at-z 20))
  (local scene-camera (camera-at-z 20))
  (expose-active-bubbles-slots! ctx canvas-camera scene-camera)
  (local (canvas-ok canvas-err) (pcall (fn []
                                         (ctx.canvas:screen-pos-ray {:x 1 :y 1}))))
  (local (scene-ok scene-err) (pcall (fn []
                                       (ctx.scene:screen-pos-ray {:x 1 :y 1}))))
  (pcall (fn [] (canvas-camera:drop)))
  (pcall (fn [] (scene-camera:drop)))
  (assert-denied-boundary-error canvas-ok canvas-err ["ambiguous direct screen ray" "canvas"]
                                "Bare Canvas screen-pos-ray must fail in active contexts")
  (assert-denied-boundary-error scene-ok scene-err ["ambiguous direct screen ray" "scene"]
                                "Bare Scene screen-pos-ray must fail in active contexts"))

(fn direct-surface-rays-fail-when-active-slot-exists []
  (with-active-bubbles-surfaces exercise-direct-surface-ray-denial))

(fn exercise-canvas-presentation-target-ray [ctx]
  (local camera (camera-at-z 20))
  (local slot (ctx.canvas:ensure-activity-slot "bubbles" {:camera camera}))
  (ctx.canvas:activate-activity-slot "bubbles")
  (slot:expose-render-target! {})
  (local target (ctx.canvas:presentation-target))
  (assert target "Canvas active slot should expose a presentation target")
  (local ray (target:screen-pos-ray {:x 1 :y 1} {}))
  (assert ray.origin "Presentation target ray should include an origin")
  (assert ray.direction "Presentation target ray should include a direction")
  (pcall (fn [] (camera:drop))))

(fn canvas-presentation-target-ray-still-works []
  (with-active-bubbles-surfaces exercise-canvas-presentation-target-ray))

(table.insert tests {:name "matching owner can mutate an activity slot"
                     :fn matching-owner-can-mutate-slot})
(table.insert tests {:name "runtime active owner fallback authorizes slots"
                     :fn runtime-active-owner-fallback-authorizes-slot})
(table.insert tests {:name "app active owner fallback authorizes slots"
                     :fn app-active-owner-fallback-authorizes-slot})
(table.insert tests {:name "runtime activating owner takes priority"
                     :fn runtime-activating-owner-takes-priority})
(table.insert tests {:name "foreign owner cannot mutate an activity slot"
                     :fn foreign-owner-cannot-mutate-slot})
(table.insert tests {:name "explicit matrix direct ray options are authorized"
                     :fn explicit-matrix-ray-opts-are-authorized})
(table.insert tests {:name "empty direct ray options fail in active contexts"
                     :fn empty-direct-ray-opts-fail-in-active-context})
(table.insert tests {:name "active activity slot authorizes a direct ray"
                     :fn active-activity-slot-authorizes-ray})
(table.insert tests {:name "target ownership requires active scene/canvas slots"
                     :fn target-ownership-requires-active-slot-in-active-context})
(table.insert tests {:name "foreign pointer target is not active owned"
                     :fn foreign-pointer-target-is-not-active-owned})
(table.insert tests {:name "deactivate foreign slots preserves the active slot"
                      :fn deactivate-foreign-slots-preserves-active-slot})
(table.insert tests {:name "Canvas rejects foreign activity slot creation"
                     :fn canvas-rejects-foreign-activity-slot})
(table.insert tests {:name "Canvas allows active activity slot creation"
                     :fn canvas-allows-active-activity-slot})
(table.insert tests {:name "Scene rejects foreign activity slot creation"
                     :fn scene-rejects-foreign-activity-slot})
(table.insert tests {:name "direct surface rays fail when an active slot exists"
                     :fn direct-surface-rays-fail-when-active-slot-exists})
(table.insert tests {:name "Canvas presentation target ray still works"
                     :fn canvas-presentation-target-ray-still-works})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "activity-surface-boundary"
                       :tests tests})))

{:name "activity-surface-boundary"
 :tests tests
 :main main}
