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

(fn env-enabled? [name]
  (= (os.getenv name) "1"))

(local windows-default-skip-modules
  {:tests.test-terminal true
   :tests.test-terminal-widget true
   :tests.test-terminal-renderer true
   :tests.test-terminal-scrollback true
   :tests.test-external-editor true
   :tests.test-ripgrep true
   :tests.test-ripgrep-view true
   :tests.test-flamegraph true
   :tests.test-llm-tools true})

(fn apply-module-overrides [modules]
  (var result (copy-array modules))
  (var platform-os nil)
  (local (sys-ok sysinfo-or-err) (pcall (fn []
                                          (require :sysinfo))))
  (when sys-ok
    (local platform (sysinfo-or-err.platform))
    (when (and platform platform.os)
      (set platform-os platform.os)))

  (when (= platform-os "windows")
    ;; Keep Windows/Wine test filtering explicit and centralized.
    ;; `lua "return true"` per-test skips remain valid for feature-level gates.
    (local excluded {})
    (each [module-name enabled? (pairs windows-default-skip-modules)]
      (when enabled?
        (set (. excluded module-name) true)))
    (local (terminal-ok _terminal) (pcall (fn []
                                            (require :terminal))))
    (when terminal-ok
      (set (. excluded :tests.test-terminal) nil)
      (set (. excluded :tests.test-terminal-widget) nil)
      (set (. excluded :tests.test-terminal-renderer) nil)
      (set (. excluded :tests.test-terminal-scrollback) nil))
    (local filtered [])
    (each [_ module-name (ipairs result)]
      (when (not (. excluded module-name))
        (table.insert filtered module-name)))
    (set result filtered))

  (when (env-enabled? "SPACE_MATRIX_TEST")
    (table.insert result :tests.test-matrix))
  (when (env-enabled? "SKIP_KEYRING_TESTS")
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
  (local Runtime (require :state-runtime))
  (when test-verbose
    (log-line "[BOOT] require :textures"))
  (local textures (require :textures))
  (when test-verbose
    (log-line "[BOOT] test runner"))

  (global reset-engine-events
    (fn []
      (assert (and app.engine app.engine.events) "app.engine.events missing in tests")
      (each [_ signal (pairs app.engine.events)]
        (signal:clear))
      (Runtime.reset)))

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
      (set tex.allocate
           (fn [_self width height _channels]
             (set tex.width width)
             (set tex.height height)
             (set tex.ready true)))
      (set tex.update-full
           (fn [_self _bytes]
             (set tex.ready true)))
      (tset tex "update-full" tex.update-full)
      (set tex.update-sub-rect
           (fn [_self _x _y _width _height _bytes]
             (set tex.ready true)))
      (tset tex "update-sub-rect" tex.update-sub-rect)
      (set (. loaded name) tex)
      tex))
  (set textures.load-texture stub)
  (set textures.load-texture-async stub)
  (set textures.load-texture-from-bytes
       (fn [name _bytes]
         (stub name "<bytes>")))
  (set textures.load-texture-from-bytes-async textures.load-texture-from-bytes)
  (set textures.load-texture-from-pixels
       (fn [name width height _channels _bytes]
         (local tex (stub name "<pixels>"))
         (set tex.width width)
         (set tex.height height)
         tex))
  (set textures.allocate-texture
       (fn [name width height channels]
         (local tex (stub name "<allocated>"))
         (tex:allocate width height channels)
         tex))
  (tset textures "allocate-texture" textures.allocate-texture)
  (set textures.get-texture
       (fn [name]
         (or (. loaded name)
             (stub name "<lazy>"))))
  (set textures.drop-texture
       (fn [name]
         (if (. loaded name)
             (do
               (set (. loaded name) nil)
               true)
             false)))
  (tset textures "drop-texture" textures.drop-texture)
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
           (stub name path)))
    (set textures.load-texture-async textures.load-texture)
    (set textures.load-texture-from-bytes
         (fn [name _bytes]
           (textures.load-texture name "<bytes>")))
    (set textures.load-texture-from-bytes-async textures.load-texture-from-bytes)
    (set textures.load-texture-from-pixels
         (fn [name width height _channels _bytes]
           (local tex (stub name "<pixels>"))
           (set tex.width width)
           (set tex.height height)
           tex))
    (set textures.allocate-texture
         (fn [name width height channels]
           (local tex (stub name "<allocated>"))
           (tex:allocate width height channels)
           tex))
    (tset textures "allocate-texture" textures.allocate-texture)
    (set textures.get-texture
         (fn [name]
           (or (. loaded name)
               (stub name "<lazy>"))))
    (set textures.drop-texture
         (fn [name]
           (if (. loaded name)
               (do
                 (set (. loaded name) nil)
                 true)
               false)))
    (tset textures "drop-texture" textures.drop-texture)
    (when (not textures.load-cubemap)
      (set textures.load-cubemap (fn [_files] {:id 1}))
      (set textures.load-cubemap-async textures.load-cubemap)))

  (when (not (and app.themes app.themes.get-active-theme))
    (set app.themes ((require :themes)))
    (app.themes.add-theme :dark (require :dark-theme))
    (app.themes.add-theme :light (require :light-theme))
    (app.themes.set-theme :dark))
  (when (not app.lights)
    (local {:LightSystem LightSystem} (require :light-system))
    (set app.lights (LightSystem {})))
  )

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
