(fn log-line [msg]
  (print msg)
  (io.flush))

(fn protected-call [traceback f]
  (if traceback
      (xpcall f (fn [err]
                  (traceback err 2)))
      (pcall f)))

(fn copy-array [items]
  (local out [])
  (each [_ item (ipairs items)]
    (table.insert out item))
  out)

(fn apply-module-overrides [modules]
  (var result (copy-array modules))
  (when (os.getenv "SPACE_MATRIX_TEST")
    (table.insert result :tests.test-matrix))
  (when (os.getenv "SKIP_KEYRING_TESTS")
    (local filtered [])
    (each [_ module-name (ipairs result)]
      (when (not (= module-name :tests.test-keyring))
        (table.insert filtered module-name)))
    (set result filtered))
  result)

(fn setup-test-env [test-verbose]
  (global app {})
  (set app.testing true)
  (when test-verbose
    (log-line "[BOOT] loading bindings"))
  (when test-verbose
    (log-line "[BOOT] require :engine"))
  (local EngineModule (require :engine))
  (when test-verbose
    (log-line "[BOOT] require :intersectables"))
  (local Intersectables (require :intersectables))
  (when test-verbose
    (log-line "[BOOT] require :clickables"))
  (local Clickables (require :clickables))
  (when test-verbose
    (log-line "[BOOT] require :hoverables"))
  (local Hoverables (require :hoverables))
  (when test-verbose
    (log-line "[BOOT] require :textures"))
  (local textures (require :textures))
  (when test-verbose
    (log-line "[BOOT] test runner"))

  (global reset-engine-events
    (fn []
      (assert (and app.engine app.engine.events) "app.engine.events missing in tests")
      (each [_ signal (pairs app.engine.events)]
        (signal:clear))))

  ;; Ensure font textures and loaders are available during tests; do not fall back to stubs.
  (set app.disable_font_textures false)
  (local loaded {})
  (local stub
    (fn [name path]
      (local tex {:id (tonumber (tostring (string.byte name 1) 10))
                  :name name :path path
                  :ready true
                  :width 1
                  :height 1})
      (set (. loaded name) tex)
      tex))
  (set textures.load-texture stub)
  (set textures.load-texture-async stub)
  (set textures.load-texture-from-bytes
       (fn [name _bytes]
         (stub name "<bytes>")))
  (set textures.load-texture-from-bytes-async textures.load-texture-from-bytes)
  (when (not textures.get-texture)
    (local loaded {})
    (set textures.get-texture
         (fn [_name]
           (error "textures.get_texture not implemented in tests"))))
  (when (not textures.load-cubemap)
    (local cube-stub (fn [_files] {:id 1 :ready true}))
    (set textures.load-cubemap cube-stub)
    (set textures.load-cubemap-async cube-stub))

  (do
    (local MockOpenGL (require :mock-opengl))
    (local global-mock (MockOpenGL))
    (global-mock:install))
  (require :gl)

  (set app.engine (EngineModule.Engine {:headless true}))

  (require :main)

  (app.engine:start)

  (when (not app.intersectables)
    (set app.intersectables (Intersectables)))
  (when (not app.clickables)
    (set app.clickables (Clickables {:intersectables app.intersectables})))
  (when (not app.hoverables)
    (set app.hoverables (Hoverables {:intersectables app.intersectables})))

  ;; Reapply texture stubs in case bindings overwrote them.
  (when textures
    (set textures.load-texture
         (fn [name path]
           {:id (tonumber (tostring (string.byte name 1) 10))
            :name name :path path}))
    (set textures.load-texture-async textures.load-texture)
    (set textures.load-texture-from-bytes
         (fn [name _bytes]
           (textures.load-texture name "<bytes>")))
    (set textures.load-texture-from-bytes-async textures.load-texture-from-bytes)
    (when (not textures.get-texture)
      (set textures.get-texture (fn [_name] (error "textures.get_texture not implemented in tests"))))
    (when (not textures.load-cubemap)
      (set textures.load-cubemap (fn [_files] {:id 1}))
      (set textures.load-cubemap-async textures.load-cubemap)))

  (when (not (and app.themes app.themes.get-active-theme))
    (set app.themes ((require :themes)))
    (app.themes.add-theme :dark (require :dark-theme))
    (app.themes.add-theme :light (require :light-theme))
    (app.themes.set-theme :dark)))
  (when (not app.lights)
    (local LightSystem (require :light-system))
    (local theme (and app.themes app.themes.get-active-theme
                      (app.themes.get-active-theme)))
    (local defaults (and theme theme.lights))
    (local active (and defaults {:ambient defaults.ambient
                                 :directional defaults.directional}))
    (set app.lights (LightSystem {:defaults defaults
                                  :active active}))))

(fn execute-tests [suite test-verbose test-filter traceback]
  (local registered-tests [])
  (each [_ test (ipairs suite.tests)]
    (when (not (= (type test.name) "string"))
      (error "suite test missing name"))
    (when (not (= (type test.fn) "function"))
      (error (.. "suite test " test.name " missing fn")))
    (when (or (not test-filter)
              (string.find test.name test-filter 1 true))
      (table.insert registered-tests test)))

  (var failures 0)
  (each [_ test (ipairs registered-tests)]
    (when test-verbose
      (log-line (.. "[RUN] " test.name)))
    (local (ok err) (protected-call traceback test.fn))
    (if ok
        (log-line (.. "[PASS] " test.name))
        (do
          (log-line (.. "[FAIL] " test.name))
          (log-line (tostring err))
          (set failures (+ failures 1)))))

  (when suite.teardown
    (local (_ok err) (protected-call traceback suite.teardown))
    (when (not _ok)
      (log-line (.. "[FAIL] teardown " (tostring err)))
      (set failures (+ failures 1))))

  (when (> failures 0)
    (error (.. failures " Lua test(s) failed")))

  (log-line (.. "Executed " (# registered-tests) " Lua tests"))

  (app.engine:shutdown)
  suite)

(fn run-tests [suite]
  (assert (and suite suite.tests) "tests.runner: suite missing tests")
  (local test-verbose (os.getenv "TEST_VERBOSE"))
  (local test-filter (os.getenv "TEST_FILTER"))
  (local traceback (and _G.debug _G.debug.traceback))
  (setup-test-env test-verbose)

  (execute-tests suite test-verbose test-filter traceback))

(fn run-modules [suite]
  (assert (and suite suite.modules) "tests.runner: suite missing modules")
  (local test-verbose (os.getenv "TEST_VERBOSE"))
  (local test-filter (os.getenv "TEST_FILTER"))
  (local traceback (and _G.debug _G.debug.traceback))
  (setup-test-env test-verbose)

  (local modules (apply-module-overrides suite.modules))
  (local registered-tests [])

  (fn collect-tests [module-name]
    (when test-verbose
      (log-line (.. "[LOAD] " module-name)))
    (local (ok result)
      (protected-call traceback (fn []
                                  (require module-name))))
    (when (not ok)
      (error (.. "Failed to load " module-name ":\n" (tostring result))))
    (do
      (when (not (= (type result) "table"))
        (error (.. module-name " must return a test suite")))
      (local tests (or (. result :tests) result))
      (each [_ test (ipairs tests)]
        (when (not (= (type test.name) "string"))
          (error (.. module-name " test missing name")))
        (when (not (= (type test.fn) "function"))
          (error (.. module-name " test " test.name " missing fn")))
        (when (or (not test-filter)
                  (string.find test.name test-filter 1 true))
          (table.insert registered-tests test)))))

  (each [_ module-name (ipairs modules)]
    (collect-tests module-name))

  (local suite-tests {:name (or suite.name "suite") :tests registered-tests :teardown suite.teardown})
  (execute-tests suite-tests test-verbose test-filter traceback))

{:run-modules run-modules
 :run-tests run-tests}
