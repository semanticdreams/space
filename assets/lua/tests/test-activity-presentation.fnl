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

;; R1-1: HUD must be included in render targets in scene/canvas/hud order
(fn provider-render-targets-includes-hud-in-order []
  (let [saved-hud (and app app.hud)
        scene-target {:kind :scene}
        canvas-target {:kind :canvas}
        hud-target-maker (fn [] {:kind :hud :projection true
                                  :get-view-matrix (fn [_t] true)
                                  :get-lighting-view-state (fn [_t] true)
                                  :get-render-contexts (fn [_t] [])})
        hud-target (hud-target-maker)
        runtime {:scene {:presentation-target (fn [_self] scene-target)}
                 :canvas {:presentation-target (fn [_self] canvas-target)}}]
    ;; Set app.hud with presentation-target so the provider can collect it
    (when app (set app.hud {:presentation-target (fn [_self] hud-target)}))
    (local provider (Presentation.for-runtime runtime))
    (local targets (provider:render-targets))
    (assert (= (length targets) 3)
            (.. "render-targets must include scene, canvas, and hud; got " (length targets)
                " targets"))
    (assert (= (. targets 1) scene-target)
            "targets[1] must be scene")
    (assert (= (. targets 2) canvas-target)
            "targets[2] must be canvas")
    (assert (= (. targets 3) hud-target)
            "targets[3] must be hud")
    (when app (set app.hud saved-hud))))
;; Complementary: HUD without presentable projection is not included
(fn provider-render-targets-excludes-empty-hud []
  (let [saved-hud (and app app.hud)
        scene-target {:kind :scene}
        runtime {:scene {:presentation-target (fn [_self] scene-target)}
                 :canvas {:presentation-target (fn [_self] nil)}}]
    (when app (set app.hud {:projection nil ;; without projection, no presentation target
                             :presentation-target (fn [_self] nil)}))
    (local provider (Presentation.for-runtime runtime))
    (local targets (provider:render-targets))
    (assert (= (length targets) 1)
            (.. "render-targets must exclude HUD without projection, got " (length targets)
                " targets"))
    (assert (= (. targets 1) scene-target)
            "only explicit runtime-owned scene target must be present")
    (when app (set app.hud saved-hud))))

;; Task 4: presentation input delegation tests
(fn app-screen-pos-ray-delegates-to-runtime-presentation []
  (local Main (require :main))
  (Main.install-app-shell!)
  (var called-pos nil)
  (local expected-ray {:origin :o :direction :d})
  (local saved-runtime app.active-world-runtime)
  (set app.active-world-runtime
       {:presentation {:screen-pos-ray (fn [_self pos _opts]
                                         (set called-pos pos)
                                         expected-ray)}})
  (local ray (app.screen-pos-ray {:x 4 :y 5} {}))
  (assert (= ray expected-ray))
  (assert (= called-pos.x 4))
  (set app.active-world-runtime saved-runtime))

(fn state-runtime-uses-presentation-controls []
  (local Runtime (require :state-runtime))
  (local controls {:on-mouse-wheel (fn [_self _payload] true)})
  (local saved-runtime app.active-world-runtime)
  (local saved-first-person app.first-person-controls)
  (local saved-active-pointer app.active-pointer-controls)
  (set app.first-person-controls nil)
  (set app.active-pointer-controls nil)
  (set app.active-world-runtime
       {:presentation {:input-controls (fn [_self] controls)}})
  (assert (= (Runtime.active-controls) controls))
  (set app.active-world-runtime saved-runtime)
  (set app.first-person-controls saved-first-person)
  (set app.active-pointer-controls saved-active-pointer))

;; R4-1 fix-round-2: canvas-active input-controls must not fall
;; back to first-person-controls when canvas-controls is missing.
(fn provider-input-controls-no-cross-surface-fallback []
  (local fpc {:kind :fpc})
  (local canvas-ctls {:kind :canvas-controls})
  (local saved-runtime app.active-world-runtime)
  (local saved-canvas-interactive app.canvas-interactive?)
  ;; Scenario A: canvas active with canvas-controls → returns canvas-controls
  (set app.canvas-interactive? true)
  (set app.active-world-runtime
       {:first-person-controls fpc
        :canvas-controls canvas-ctls})
  (local provider-a (Presentation.for-runtime app.active-world-runtime))
  (assert (= (provider-a:input-controls) canvas-ctls)
          "canvas-active + canvas-controls must return canvas-controls")
  ;; Scenario B: canvas active with NO canvas-controls → must return nil, not fpc
  (set app.active-world-runtime
       {:first-person-controls fpc})
  (local provider-b (Presentation.for-runtime app.active-world-runtime))
  (assert (= (provider-b:input-controls) nil)
          "canvas-active + missing canvas-controls must return nil, not fpc")
  ;; Scenario C: scene active → returns first-person-controls (or nil)
  (set app.canvas-interactive? false)
  (set app.active-world-runtime
       {:first-person-controls fpc
        :canvas-controls canvas-ctls})
  (local provider-c (Presentation.for-runtime app.active-world-runtime))
  (assert (= (provider-c:input-controls) fpc)
          "scene-active must return first-person-controls")
  (set app.active-world-runtime saved-runtime)
  (set app.canvas-interactive? saved-canvas-interactive))

;; R4-1 fix-round-2: Common.controls-from must not return legacy
;; app.active-pointer-controls / app.first-person-controls globals
;; when presentation controls are nil.
(fn common-controls-from-rejects-legacy-app-globals []
  (local Common (require :state-handlers/common))
  (local saved-runtime app.active-world-runtime)
  (local saved-fpc app.first-person-controls)
  (local saved-ptr app.active-pointer-controls)
  ;; Set legacy globals to non-nil — they must be ignored
  (set app.first-person-controls {:legacy :fpc})
  (set app.active-pointer-controls {:legacy :ptr})
  ;; Presentation provider exists but returns nil controls
  (set app.active-world-runtime
       {:presentation {:input-controls (fn [_self] nil)}})
  (let [ctx {:app app}]
    (assert (= (Common.controls-from ctx) nil)
            "Common.controls-from must return nil when presentation controls are nil, even with legacy globals set"))
  ;; No presentation provider at all
  (set app.active-world-runtime nil)
  (let [ctx {:app app}]
    (assert (= (Common.controls-from ctx) nil)
            "Common.controls-from must return nil when no presentation provider exists"))
  (set app.active-world-runtime saved-runtime)
  (set app.first-person-controls saved-fpc)
  (set app.active-pointer-controls saved-ptr))

(table.insert tests {:name "Provider returns only explicit targets"
                     :fn provider-returns-only-explicit-targets})
(table.insert tests {:name "Provider screen ray requires target"
                     :fn provider-screen-ray-requires-target-camera})
(table.insert tests {:name "Provider default-screen-ray-target uses opts.surface"
                     :fn provider-default-screen-ray-surface-selects-target})
(table.insert tests {:name "Provider default-screen-ray-target fallback uses active interaction surface"
                     :fn provider-default-screen-ray-fallback-uses-active-interaction-surface})
;; R1-3: app.screen-pos-ray must fail loudly when no provider and no
;; explicit target is supplied.  It must not silently fall back to
;; app.scene or app.canvas.
(fn app-screen-pos-ray-fails-without-provider-or-explicit-target []
  (let [saved-runtime app.active-world-runtime
        Main (require :main)]
    (Main.install-app-shell!)
    ;; No active runtime and no explicit target => must fail
    (set app.active-world-runtime nil)
    (let [(ok err) (pcall (fn [] (app.screen-pos-ray {:x 10 :y 20} {})))]
      (assert (not ok)
              "screen-pos-ray without provider must fail")
      (assert (string.find (tostring err) "presentation provider")
              (.. "error must mention presentation provider, got: " (tostring err))))
    ;; Explicit target must still work even without provider
    (let [explicit-ray "explicit-ray-result"
          fake-target {:screen-pos-ray (fn [_self _pos _opts] explicit-ray)}
          ray (app.screen-pos-ray {:x 1 :y 2} {:target fake-target})]
      (assert (= ray explicit-ray)
              "screen-pos-ray with explicit opts.target must work even without provider"))
    (set app.active-world-runtime saved-runtime)))

(table.insert tests {:name "Provider render-targets includes HUD in scene/canvas/hud order"
                       :fn provider-render-targets-includes-hud-in-order})
(table.insert tests {:name "Provider render-targets excludes empty HUD"
                       :fn provider-render-targets-excludes-empty-hud})
(table.insert tests {:name "app.screen-pos-ray fails without provider or explicit target"
                       :fn app-screen-pos-ray-fails-without-provider-or-explicit-target})
(table.insert tests {:name "app.screen-pos-ray delegates to runtime presentation"
                      :fn app-screen-pos-ray-delegates-to-runtime-presentation})
(table.insert tests {:name "state-runtime uses presentation controls"
                     :fn state-runtime-uses-presentation-controls})
(table.insert tests {:name "provider input-controls has no cross-surface fallback"
                     :fn provider-input-controls-no-cross-surface-fallback})
(table.insert tests {:name "common controls-from rejects legacy app globals"
                     :fn common-controls-from-rejects-legacy-app-globals})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "activity-presentation"
                       :tests tests})))

{:name "activity-presentation"
 :tests tests
 :main main}
