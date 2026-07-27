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

(table.insert tests {:name "Provider returns only explicit targets"
                     :fn provider-returns-only-explicit-targets})
(table.insert tests {:name "Provider screen ray requires target"
                     :fn provider-screen-ray-requires-target-camera})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "activity-presentation"
                       :tests tests})))

{:name "activity-presentation"
 :tests tests
 :main main}
