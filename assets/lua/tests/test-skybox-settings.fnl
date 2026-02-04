(local tests [])
(local AppBootstrap (require :app-bootstrap))
(local package package)

(global app (or _G.app {}))

(fn with-renderers-mock [cb]
  (local previous (. package.loaded :renderers))
  (local calls {:skybox-path nil})
  (tset package.loaded :renderers
        (fn []
          {:skybox {:set-skybox (fn [_self path]
                                  (set calls.skybox-path path))}
           :on-viewport-changed (fn [_self _viewport] nil)}))
  (local (ok result) (pcall cb calls))
  (tset package.loaded :renderers previous)
  (if ok
      result
      (error result)))

(fn with-settings [value f]
  (local previous app.settings)
  (set app.settings
       {:get-value (fn [key fallback]
                     (if (= key "ui.skybox") value fallback))})
  (local result (f))
  (set app.settings previous)
  result)

(fn init-renderers-applies-skybox []
  (local previous app.renderers)
  (with-renderers-mock
    (fn [calls]
      (with-settings
        "lake"
        (fn []
          (AppBootstrap.init-renderers {})
          (assert (= calls.skybox-path "skyboxes/lake"))
          true))))
  (set app.renderers previous))

(table.insert tests {:name "Init renderers uses stored skybox setting"
                     :fn init-renderers-applies-skybox})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "skybox-settings"
                       :tests tests})))

{:name "skybox-settings"
 :tests tests
 :main main}
