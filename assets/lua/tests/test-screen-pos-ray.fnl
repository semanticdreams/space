(local tests [])

(fn screen-ray-delegates-to-presentation []
  (local Main (require :main))
  (Main.install-app-shell!)
  (local original-runtime app.active-world-runtime)
  (var called-pos nil)
  (local expected-ray {:origin "o" :direction "d"})
  (set app.active-world-runtime
       {:presentation {:screen-pos-ray (fn [_self pos _opts]
                                         (set called-pos pos)
                                         expected-ray)}})
  (local ray (app.screen-pos-ray {:x 0.5 :y 0.5} {}))
  (assert (= ray expected-ray)
          "screen-pos-ray must delegate to presentation provider")
  (assert called-pos "screen-pos-ray must pass pos to provider")
  (set app.active-world-runtime original-runtime))

(table.insert tests {:name "screen_pos_ray delegates to presentation provider" :fn screen-ray-delegates-to-presentation})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "screen-pos-ray"
                       :tests tests})))

{:name "screen-pos-ray"
 :tests tests
 :main main}
