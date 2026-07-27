(local tests [])
(local Presentation (require :activity-presentation))

(fn provider-returns-only-explicit-targets []
  (var scene-called? false)
  (var canvas-called? false)
  (local scene-target {:kind :scene})
  (local runtime
    {:scene {:presentation-target (fn [_self]
                                    (set scene-called? true)
                                    scene-target)}
     :canvas {:presentation-target (fn [_self]
                                     (set canvas-called? true)
                                     nil)}})
  (local provider (Presentation.for-runtime runtime))
  (local targets (provider:render-targets))
  (assert scene-called?)
  (assert canvas-called?)
  (assert (= (length targets) 1))
  (assert (= (. targets 1) scene-target)))

(fn provider-screen-ray-requires-target-camera []
  (local provider (Presentation.for-runtime {}))
  (local (ok err) (pcall (fn [] (provider:screen-pos-ray {:x 1 :y 2} {}))))
  (assert (not ok))
  (assert (string.find (tostring err) "screen ray target")
          "Missing screen-ray target must fail loudly"))

;; R1-2: opts.surface path must return the matching surface presentation target
(fn provider-default-screen-ray-surface-selects-target []
  (local scene-target {:kind :scene
                       :screen-pos-ray (fn [_self _pos _opts]
                                         "scene-ray")})
  (local canvas-target {:kind :canvas
                        :screen-pos-ray (fn [_self _pos _opts]
                                          "canvas-ray")})
  (local runtime
    {:scene {:presentation-target (fn [_self] scene-target)}
     :canvas {:presentation-target (fn [_self] canvas-target)}})
  (local provider (Presentation.for-runtime runtime))
  (let [scene-result (provider:default-screen-ray-target {:surface :scene})
        canvas-result (provider:default-screen-ray-target {:surface :canvas})]
    (assert (= scene-result scene-target)
            "opts.surface :scene must return scene presentation target")
    (assert (= canvas-result canvas-target)
            "opts.surface :canvas must return canvas presentation target"))
  ;; screen-pos-ray must delegate to surface-matched target
  (let [ray (provider:screen-pos-ray {:x 10 :y 20} {:surface :scene})]
    (assert (= ray "scene-ray")
            (.. "screen-pos-ray via surface must delegate, got " (tostring ray)))))

;; R1-2: fallback must use app.active-interaction-surface (active wins over preferred)
(fn provider-default-screen-ray-fallback-uses-active-interaction-surface []
  (local scene-target {:kind :scene
                       :screen-pos-ray (fn [_self _pos _opts]
                                         "active-scene-ray")})
  (local canvas-target {:kind :canvas
                        :screen-pos-ray (fn [_self _pos _opts]
                                          "active-canvas-ray")})
  ;; runtime prefers scene, but the active interaction surface is canvas
  (local runtime
    {:scene {:presentation-target (fn [_self] scene-target)}
     :canvas {:presentation-target (fn [_self] canvas-target)}
     :preferred-interaction-surface :scene})
  (local provider (Presentation.for-runtime runtime))
  (let [saved-active (and app app.active-interaction-surface)]
    (when app (set app.active-interaction-surface :canvas))
    ;; Active surface (:canvas) must win over runtime preferred (:scene)
    (let [ray (provider:screen-pos-ray {:x 1 :y 2} {})]
      (assert (= ray "active-canvas-ray")
              (.. "screen-pos-ray fallback must use app.active-interaction-surface, got "
                  (tostring ray))))
    (let [target (provider:default-screen-ray-target {})]
      (assert (= target canvas-target)
              "default-screen-ray-target must use app.active-interaction-surface fallback"))
    (when app (set app.active-interaction-surface saved-active))))

;; R1-3: HUD is not included in render targets unless explicitly activity-owned
(fn provider-render-targets-excludes-global-hud []
  ;; Temporarily set app.hud to verify it is NOT included
  (let [saved-hud (and app app.hud)
        scene-target {:kind :scene}
        runtime {:scene {:presentation-target (fn [_self] scene-target)}
                 :canvas {:presentation-target (fn [_self] nil)}}]
    (when app (set app.hud {:kind :hud}))
    (local provider (Presentation.for-runtime runtime))
    (local targets (provider:render-targets))
    (assert (= (length targets) 1)
            (.. "render-targets must not include global app.hud, got " (length targets)
                " targets"))
    (assert (= (. targets 1) scene-target)
            "only explicit runtime-owned scene target must be present")
    (when app (set app.hud saved-hud))))

(table.insert tests {:name "Provider returns only explicit targets"
                     :fn provider-returns-only-explicit-targets})
(table.insert tests {:name "Provider screen ray requires target"
                     :fn provider-screen-ray-requires-target-camera})
(table.insert tests {:name "Provider default-screen-ray-target uses opts.surface"
                     :fn provider-default-screen-ray-surface-selects-target})
(table.insert tests {:name "Provider default-screen-ray-target fallback uses active interaction surface"
                     :fn provider-default-screen-ray-fallback-uses-active-interaction-surface})
(table.insert tests {:name "Provider render-targets excludes global app.hud"
                     :fn provider-render-targets-excludes-global-hud})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "activity-presentation"
                       :tests tests})))

{:name "activity-presentation"
 :tests tests
 :main main}
