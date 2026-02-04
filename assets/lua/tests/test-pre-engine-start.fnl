(local expect-ray-box-before-engine
  (fn []
    (set (. package.loaded "ray-box") nil)
    (local (ok module) (pcall require :ray-box))
    (assert ok "ray-box module should load before engine start")
    (assert (and module module.ray-box-intersection)
            "ray-box module should expose ray-box-intersection")))

(local tests [{:name "ray-box binding available before engine start"
  :fn expect-ray-box-before-engine}])

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "pre-engine-start"
                       :tests tests})))

{:name "pre-engine-start"
 :tests tests
 :main main}
