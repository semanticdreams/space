(global app (or app {}))

(local trace-require (os.getenv "SPACE_TRACE_REQUIRE"))
(when trace-require
  (local original-require require)
  (set _G.require
       (fn [name]
         (io.stderr:write (string.format "[require] %s\n" name))
         (io.stderr:flush)
         (original-require name))))

(local EngineModule (require :engine))
(local AppConfig (require :app-config))
(local CliArgs (require :cli-args))

(when (not app.engine)
  (set app.engine (EngineModule.Engine {})))

(local glm (require :glm))
(global fennel (require :fennel))
(local runtime (require :runtime))
(local logging (require :logging))

(set fennel.macro-path runtime.fennel-path)

(global pp (fn [x] (logging.debug (fennel.view x))))

(local IoUtils (require :io-utils))
(global read-file IoUtils.read-file)

(global one (fn [val] (assert (= (length val) 1) val) (. val 1)))

(local DebugLog (require :debug-log))
(DebugLog.reset-log!)
(local fs (require :fs))
(local appdirs (require :appdirs))
(local log-dir
  (or (os.getenv "SPACE_LOG_DIR")
      (appdirs.user-log-dir "space")))
(when (and log-dir fs fs.create-dirs)
  (fs.create-dirs log-dir))
(local log-path (fs.join-path log-dir "space.log"))
(logging.init {:path log-path})
(logging.set-level "shader" "warn")
(logging.set-level "window" "warn")
(local audio (require :audio))
(local _input-state-binding (require :input-state))
(local Settings (require :settings))
(local VolumeControl (require :volume-control))
(local MenuManager (require :menu-manager))
(local WalletManager (require :wallet-manager))
(local MathUtils (require :math-utils))

(local vec3->array (. MathUtils :vec3->array))
(local quat->array (. MathUtils :quat->array))
(local array->vec3 (. MathUtils :array->vec3))
(local array->quat (. MathUtils :array->quat))

(var fennel-cache-dir nil)
(local bytecode-enabled
  (do
    (local flag (os.getenv "SPACE_FENNEL_BYTECODE"))
    (if flag
        (not (or (= flag "0")
                 (= (string.lower flag) "false")
                 (= (string.lower flag) "off")))
        true)))

(fn sanitize-cache-name [name]
  (string.gsub (or name "") "[^%w%._-]" "_"))

(fn read-file-raw [path]
  (local file (io.open path "rb"))
  (if file
      (do
        (local content (file:read "*all"))
        (file:close)
        content)
      (error (.. "Could not open file: " path))))

(fn write-cache-file [path content]
  (when (and path content)
    (local file (io.open path "wb"))
    (when file
      (file:write content)
      (file:close))))

(fn loadfile-with-env [path mode]
  (local legacy? (or (= _VERSION "Lua 5.1") (string.find _VERSION "LuaJIT")))
  (local setfenv-fn (rawget _G "setfenv"))
  (if legacy?
      (do
        (local (ok result) (pcall loadfile path))
        (if ok
            (do
              (when setfenv-fn
                (setfenv-fn result _G))
              result)
            (do
              (logging.warn (string.format "[space] fennel cache load failed: %s" result))
              nil)))
      (do
        (local (ok result) (pcall loadfile path mode _G))
        (if ok
            result
            (do
              (logging.warn (string.format "[space] fennel cache load failed: %s" result))
              nil)))))

(fn cache-stem [module-path module-name]
  (when (and fennel-cache-dir module-path module-name)
    (local stat (fs.stat module-path))
    (local modified (and stat stat.modified))
    (local size (and stat stat.size))
    (local version (sanitize-cache-name (or fennel.version "unknown")))
    (local lua-version (sanitize-cache-name (or _VERSION "lua")))
    (local correlate-flag "c1")
    (when (and modified size)
      (fs.join-path fennel-cache-dir
                    (.. (sanitize-cache-name module-name)
                        "_" version "_" lua-version "_" correlate-flag
                        "_" modified "_" size)))))

(fn cache-path-source [module-path module-name]
  (local stem (cache-stem module-path module-name))
  (and stem (.. stem ".lua")))

(fn cache-path-bytecode [module-path module-name]
  (local stem (cache-stem module-path module-name))
  (and stem (.. stem ".luac")))

(fn load-from-cache [cache-file mode]
  (when cache-file
    (local cache-stat (fs.stat cache-file))
    (when (and cache-stat cache-stat.exists cache-stat.is-file)
      (loadfile-with-env cache-file mode))))

(fn write-bytecode-cache [cache-file loader]
  (when (and bytecode-enabled cache-file loader)
    (local (ok dumped-or-error) (pcall string.dump loader))
    (if ok
        (write-cache-file cache-file dumped-or-error)
        (logging.warn (string.format "[space] fennel bytecode disabled: %s" dumped-or-error)))))

(fn compile-fennel-module [module-name module-path source-cache bytecode-cache]
  (local source (read-file-raw module-path))
  (local compile (. fennel :compile-string))
  (local load-code (. fennel :load-code))
  (local lua-source (compile source {:filename module-path
                                     :module-name module-name
                                     :correlate true}))
  (write-cache-file source-cache lua-source)
  (local loader (load-code lua-source _G (.. "@" module-path)))
  (write-bytecode-cache bytecode-cache loader)
  (loader))

(fn load-fennel-module [module-name module-path]
  (local source-cache (cache-path-source module-path module-name))
  (local bytecode-cache (cache-path-bytecode module-path module-name))
  (if bytecode-enabled
      (do
        (local loader (load-from-cache bytecode-cache "b"))
        (if loader
            (loader)
            (do
              (local source-loader (load-from-cache source-cache "t"))
              (if source-loader
                  (source-loader)
                  (compile-fennel-module module-name module-path source-cache bytecode-cache)))))
      (do
        (local source-loader (load-from-cache source-cache "t"))
        (if source-loader
            (source-loader)
            (compile-fennel-module module-name module-path source-cache bytecode-cache)))))

(fn make-fennel-loader [module-name module-path]
  (fn []
    (load-fennel-module module-name module-path)))

(fn fennel-cache-searcher [module-name]
  (local module-path ((. fennel :search-module) module-name))
  (if module-path
      (make-fennel-loader module-name module-path)
      nil))

(when (and fs appdirs)
  (local cache-root (appdirs.user-cache-dir "space"))
  (when cache-root
    (local target (fs.join-path cache-root "fennel"))
    (local (ok err)
           (pcall
             (fn []
               (when (and fs fs.create-dirs)
                 (fs.create-dirs target)))))
    (if ok
        (do
          (set fennel-cache-dir target)
          (table.insert package.searchers 1 fennel-cache-searcher))
        (logging.warn (string.format "[space] fennel cache disabled: %s" err)))))

(fn init-app-dirs []
(when (and app.engine appdirs)
    (local data-dir (appdirs.user-data-dir "space"))
    (assert data-dir "appdirs.user-data-dir must return a directory")
    (local apps-dir (fs.join-path data-dir "apps"))
    (when (and fs fs.create-dirs)
      (fs.create-dirs apps-dir))
    (set app.get-app-dir
         (fn [name]
           (assert (and name (> (string.len name) 0)) "app.get-app-dir requires a name")
           (assert (not (string.find name "/" 1 true)) "app.get-app-dir name cannot include /")
           (assert (not (string.find name "\\" 1 true)) "app.get-app-dir name cannot include \\")
           (local target (fs.join-path apps-dir name))
           (when (and fs fs.create-dirs)
             (fs.create-dirs target))
           target))))

(fn disconnect-volume-settings []
  (when (and app.volume-settings-handler VolumeControl.volume-settings-changed-debounced)
    (VolumeControl.volume-settings-changed-debounced:disconnect app.volume-settings-handler true)
    (set app.volume-settings-handler nil)))

(fn disconnect-camera-settings []
  (when (and app.camera-settings-handler app.camera app.camera.debounced-changed)
    (app.camera.debounced-changed:disconnect app.camera-settings-handler true)
    (set app.camera-settings-handler nil)))

(fn connect-volume-settings []
  (when VolumeControl.volume-settings-changed-debounced
    (set app.volume-settings-handler
         (VolumeControl.volume-settings-changed-debounced:connect
           (fn [_settings]
             (when (and app.settings app.settings.set-value app.settings.save)
               (local volume (VolumeControl.get-stored-volume))
               (local muted? (VolumeControl.get-muted?))
               (when (not (= volume nil))
                 (app.settings.set-value "audio.volume" volume {:save? false}))
               (app.settings.set-value "audio.muted" muted? {:save? false})
               (app.settings.save)))))))

(fn connect-camera-settings []
  (when (and app.camera app.camera.debounced-changed)
    (set app.camera-settings-handler
         (app.camera.debounced-changed:connect
           (fn [_payload]
             (when (and app.settings app.settings.set-value app.settings.save)
               (local position (vec3->array app.camera.position))
               (local rotation (quat->array app.camera.rotation))
               (app.settings.set-value "camera.position" position {:save? false})
               (app.settings.set-value "camera.rotation" rotation {:save? false})
               (app.settings.save)))))))

(fn init-settings []
  (when (and app.settings app.settings.drop)
    (app.settings.drop))
  (set app.settings (Settings {:app-name "space"}))
  (local stored-volume (app.settings.get-value "audio.volume" nil))
  (local stored-muted (app.settings.get-value "audio.muted" nil))
  (when (or (not (= stored-volume nil)) (not (= stored-muted nil)))
    (VolumeControl.apply-settings {:volume stored-volume :muted? stored-muted}))
  (disconnect-volume-settings)
  (disconnect-camera-settings)
  (connect-volume-settings))

(fn matches-filters? [target filters]
  (or
    (= filters nil)
    (each [k v (pairs filters)]
      (when (not (= (. target k) v))
        (lua "return false")))
    true))

(local Camera (require :camera))
(local {:to-table viewport->table :to-glm-vec4 viewport->glm-vec4} (require :viewport-utils))
(local Scene (require :scene))
(local Hud (require :hud))
(local {: FirstPersonControls} (require :first-person-controls))
(local AppViewport (require :app-viewport))
(local AppProjection (require :app-projection))
(local {: FocusManager} (require :focus))
(local Graph (require :graph/init))
(local GraphView (require :graph/view))
(local GraphKeyLoaders (require :graph/key-loaders))
(local ObjectSelector (require :object-selector))
(local Tray (require :tray-manager))
(local Notify (require :notify-manager))
(local AppBootstrap (require :app-bootstrap))

(local FrameProfiler (require :frame-profiler))

(local number-or
  (fn [value fallback]
    (if (not (= value nil)) value fallback)))

(set app.set-viewport AppViewport.set-viewport)
(set app.create-default-projection AppProjection.create-default-projection)

(fn app.reset-projection []
  (if app.scene
      (app.scene:reset-projection)
      (set app.projection (app.create-default-projection)))
  (when app.scene
    (set app.projection app.scene.projection))
  (when app.hud
    (app.hud:reset-projection)))

(fn app.screen-pos-ray [pos opts]
  (fn finite-number? [value]
    (and (= (type value) :number)
         (= value value)
         (not (= value math.huge))
         (not (= value (- math.huge)))))
  (fn assert-finite-vec3 [vec label]
    (when (or (not vec)
              (not (finite-number? vec.x))
              (not (finite-number? vec.y))
              (not (finite-number? vec.z)))
      (error (.. "app.screen-pos-ray produced non-finite " label))))
  (if (and app.scene app.scene.screen-pos-ray)
      (let [options (if opts
                      (let [copy {}]
                        (each [k v (pairs opts)]
                          (set (. copy k) v))
                        copy)
                      {})]
        (when (and (not options.projection) app.projection)
          (set options.projection app.projection))
        (app.scene:screen-pos-ray pos options))
      (let [options (or opts {})
            viewport (viewport->table (or options.viewport app.viewport))
            view (or options.view
                     (and app.camera (app.camera:get-view-matrix)))
            projection (or options.projection app.projection)]
        (assert view "app.screen-pos-ray requires a view matrix")
        (assert projection "app.screen-pos-ray requires a projection matrix")
        (local sample-pos (or pos
                              {:x (+ viewport.x (/ viewport.width 2))
                               :y (+ viewport.y (/ viewport.height 2))}))
        (local px (number-or sample-pos.x viewport.x))
        (local py (number-or sample-pos.y viewport.y))
        (local inverted-y (- (+ viewport.height viewport.y) py))
        (local viewport-vec (viewport->glm-vec4 viewport))
        (local near (glm.unproject (glm.vec3 px inverted-y 0.0) view projection viewport-vec))
        (local far (glm.unproject (glm.vec3 px inverted-y 1.0) view projection viewport-vec))
        (local direction (glm.normalize (- far near)))
        (assert-finite-vec3 near "near")
        (assert-finite-vec3 far "far")
        (assert-finite-vec3 direction "direction")
        {:origin near :direction direction})))

(set app.layout-root nil)
(set app.viewport nil)
(app.set-viewport {:width 0 :height 0})
(set app.camera nil)
(set app.projection nil)
(set app.scene nil)
(set app.hud nil)
(set app.profiler nil)
(set app.movables nil)
(set app.focus nil)
(set app.scene-focus-scope nil)
(set app.hud-focus-scope nil)
(set app.graph-view nil)
(set app.tray-manager nil)
(set app.menu-manager nil)
(set app.notify nil)
(set app.settings nil)
(set app.volume-settings-handler nil)
(set app.camera-settings-handler nil)
(set app.window-resized-handler nil)
(set app.update-handler nil)
(set app.remote-control nil)
(set app.remote-control-endpoint nil)
(set app.next-frame-queue [])
(set app.next-frame-pending [])

(fn app.next-frame [cb]
  (assert cb "app.next-frame requires callback")
  (table.insert app.next-frame-queue cb))

(fn run-next-frame []
  (local pending app.next-frame-pending)
  (set app.next-frame-pending [])
  (each [_ cb (ipairs pending)]
    (cb)))

(fn collect-cli-args []
  (local args [])
  (when _G.arg
    (var i 1)
    (while (<= i (# _G.arg))
      (table.insert args (. _G.arg i))
      (set i (+ i 1))))
  args)

(fn parse-remote-control-endpoint []
  (local spec {:name "space"
               :allow-unknown? true
               :add-help? false
               :options [{:key "remote-control"
                          :long "remote-control"
                          :takes-value? true}]})
  (local result (CliArgs.parse spec (collect-cli-args)))
  (if result.ok
      (. result.values "remote-control")
      (do
        (local message (or result.error "invalid remote control args"))
        (error (.. "[space] " message "\n" result.usage)))))

(set app.remote-control-endpoint (parse-remote-control-endpoint))

(fn app.init []
  (local init-start (os.clock))
  (assert (and app.engine app.engine.events) "app.engine.events missing; load engine-events before app.init")
  (init-app-dirs)
  (init-settings)
  (app.reset-projection)
  (when (and app.window-resized-handler app.engine.events app.engine.events.window-resized)
    (app.engine.events.window-resized:disconnect app.window-resized-handler true)
    (set app.window-resized-handler nil))
  (when (and app.engine.events app.engine.events.window-resized)
    (set app.window-resized-handler
         (app.engine.events.window-resized:connect
           (fn [e]
             (app.set-viewport {:width e.width :height e.height})
             (app.reset-projection)))))
  (when (and app.update-handler app.engine.events app.engine.events.updated)
    (app.engine.events.updated:disconnect app.update-handler true)
    (set app.update-handler nil))
  (when (and app.engine.events app.engine.events.updated)
    (set app.update-handler (app.engine.events.updated:connect app.update)))

  (when app.remote-control
    (app.remote-control:drop)
    (set app.remote-control nil))
  (when app.remote-control-endpoint
    (local RemoteControl (require :remote-control))
    (set app.remote-control (RemoteControl {:endpoint app.remote-control-endpoint})))

  (AppBootstrap.init-themes)

  (set app.camera (Camera {:position (glm.vec3 0 0 30)}))
  (when (and app.settings app.camera)
    (local stored-position (app.settings.get-value "camera.position" nil))
    (local stored-rotation (app.settings.get-value "camera.rotation" nil))
    (local pos (array->vec3 stored-position))
    (local rot (array->quat stored-rotation))
    (when pos
      (app.camera:set-position pos))
    (when rot
      (app.camera:set-rotation rot)))
  (disconnect-camera-settings)
  (connect-camera-settings)
  (set app.first-person-controls (FirstPersonControls {:camera app.camera}))
  (AppBootstrap.init-input-systems)
  (AppBootstrap.init-renderers {:viewport app.viewport})
  (AppBootstrap.init-icons)
  (local profiler-env (os.getenv "SPACE_FENNEL_PROFILE"))
  (local profiler-enabled
    (and profiler-env
         (not (or (= profiler-env "0")
                  (= (string.lower profiler-env) "false")
                  (= (string.lower profiler-env) "off")))))
  (set app.profiler (and profiler-enabled
                           (FrameProfiler {:threshold-ms 20.0
                                           :log-interval 0
                                           :enabled true})))

  (AppBootstrap.init-states)

  (when app.focus
    (app.focus:drop))
  (set app.focus (FocusManager {:root-name "space-focus"}))
  (local focus-manager app.focus)
  (local focus-root (focus-manager:get-root-scope))
  (local scene-scope (focus-manager:create-scope {:name "scene"
                                                  :directional-traversal-boundary? true}))
  (focus-manager:attach scene-scope focus-root)
  (local hud-scope (focus-manager:create-scope {:name "hud"
                                                :directional-traversal-boundary? true}))
  (focus-manager:attach hud-scope focus-root)
  (set app.scene-focus-scope scene-scope)
  (set app.hud-focus-scope hud-scope)
  (when app.clickables
    (when app.focus-void-callback
      (app.clickables:unregister-left-click-void-callback app.focus-void-callback)
      (set app.focus-void-callback nil))
    (set app.focus-void-callback
         (fn [_event]
             (when app.focus
               (app.focus:clear-focus))))
    (app.clickables:register-left-click-void-callback app.focus-void-callback))

  (set app.scene (Scene {:focus-manager focus-manager
                           :focus-scope scene-scope
                           :icons app.icons
                           :states app.states
                           :movables app.movables}))
  (set app.hud (Hud {:scene app.scene
                       :focus-manager focus-manager
                       :focus-scope hud-scope
                       :icons app.icons
                       :states app.states
                       :movables app.movables}))
  (when app.object-selector
    (app.object-selector:drop)
    (set app.object-selector nil))
  (set app.object-selector
       (ObjectSelector {:ctx (and app.hud app.hud.build-context)
                        :enabled? true}))
  (when (and app.scene app.scene.build-context)
    (set app.scene.build-context.object-selector app.object-selector))
  (when (and app.hud app.hud.build-context)
    (set app.hud.build-context.object-selector app.object-selector))
  (when app.graph
    (app.graph:drop)
    (set app.graph nil))
  (set app.graph (Graph {}))
  (GraphKeyLoaders.register app.graph)
  (when app.graph-view
    (app.graph-view:drop)
    (set app.graph-view nil))
  (set app.graph-view (GraphView {:graph app.graph
                                  :ctx (and app.scene app.scene.build-context)
                                  :movables app.movables
                                  :selector app.object-selector
                                  :view-target app.hud
                                  :camera app.camera
                                  :pointer-target app.scene}))
  (set app.layout-root (and app.scene app.scene.layout-root))
  (when (and app.scene app.scene.build-context)
    (set app.scene.build-context.layout-root app.layout-root))
  (when (and app.hud app.hud.build-context)
    (set app.hud.build-context.layout-root app.layout-root))

  (app.reset-projection)

  (when app.scene
    (app.scene:build-default))
  (when app.hud
    (app.hud:build-default))
  (when app.menu-manager
    (app.menu-manager:drop)
    (set app.menu-manager nil))
  (set app.menu-manager (MenuManager))

  (when app.system-cursors
    (app.system-cursors:reset))
  (when app.tray-manager
    (app.tray-manager.drop)
    (set app.tray-manager nil))
  (set app.tray-manager (Tray))
  (when app.tray-manager
    (app.tray-manager.setup))
  (set app.notify (Notify))
  (when app.wallet
    (set app.wallet nil))
  (set app.wallet (WalletManager {}))
  (app.wallet:load-active)

  (local init-end (os.clock))
  (local elapsed-ms (* (- init-end init-start) 1000.0))
  (logging.info (string.format "[space] init completed in %.2fms" elapsed-ms))

  (app.update 0)
  (local first-update-ms (* (- (os.clock) init-end) 1000.0))
  (logging.info (string.format "[space] first update completed in %.2fms"
                               first-update-ms))
  )

(fn app.update [delta]
  (local profiler app.profiler)
  (fn run-section [label cb]
    (if profiler
        (profiler.measure label cb)
        (cb)))
  (local pending app.next-frame-queue)
  (set app.next-frame-queue [])
  (set app.next-frame-pending pending)
  (when profiler
    (profiler.begin-frame delta))
  (when app.remote-control
    (app.remote-control:tick))
  (when (and app.engine.audio app.camera)
    (local cam app.camera)
    (local forward (cam:get-forward))
    (local up (cam:get-up))
    (app.engine.audio:setListenerPosition cam.position)
    (app.engine.audio:setListenerOrientation forward up))
  (when app.scene
    (run-section "scene" (fn [] (app.scene:update))))
  (when app.hud
    (run-section "hud" (fn [] (app.hud:update))))
  (when app.renderers
    (run-section "renderers" (fn [] (app.renderers:update))))
  (run-next-frame)
  (when app.tray-manager
    (app.tray-manager.loop))
  (when profiler
    (profiler.end-frame))
  )

(fn app.drop []
  (set (. package.loaded "renderers") nil)
  (when (and app.update-handler app.engine.events app.engine.events.updated)
    (app.engine.events.updated:disconnect app.update-handler true)
    (set app.update-handler nil))
  (when (and app.window-resized-handler app.engine.events app.engine.events.window-resized)
    (app.engine.events.window-resized:disconnect app.window-resized-handler true)
    (set app.window-resized-handler nil))
  (when app.first-person-controls
    (app.first-person-controls:drop)
    (set app.first-person-controls nil))
  (when app.camera
    (app.camera:drop)
    (set app.camera nil))
  (app.hoverables:drop)
  (set app.hoverables nil)
  (when app.movables
    (app.movables:drop)
    (set app.movables nil))
  (when app.resizables
    (app.resizables:drop)
    (set app.resizables nil))
  (when app.intersectables
    (app.intersectables:drop)
    (set app.intersectables nil))
  (when app.graph-view
    (app.graph-view:drop)
    (set app.graph-view nil))
  (when app.object-selector
    (app.object-selector:drop)
    (set app.object-selector nil))
  (when app.system-cursors
    (app.system-cursors:drop)
    (set app.system-cursors nil))
  (when app.scene
    (app.scene:drop)
    (set app.scene nil))
  (when app.hud
    (app.hud:drop)
    (set app.hud nil))
  (when app.graph
    (app.graph:drop)
    (set app.graph nil))
  (when app.renderers
    (app.renderers:drop)
    (set app.renderers nil))
  (when app.menu-manager
    (app.menu-manager:drop)
    (set app.menu-manager nil))
  (when (and app.focus-void-callback app.clickables)
    (app.clickables:unregister-left-click-void-callback app.focus-void-callback)
    (set app.focus-void-callback nil))
  (when app.focus
    (app.focus:drop)
    (set app.focus nil))
  (set app.scene-focus-scope nil)
  (set app.hud-focus-scope nil)
  (when app.profiler
    (app.profiler.set_enabled false)
    (set app.profiler nil))
  (when app.remote-control
    (app.remote-control:drop)
    (set app.remote-control nil))
  (set app.next-frame-queue [])
  (set app.next-frame-pending [])
  (set app.projection nil)
  (set app.layout-root nil)
  (when app.tray-manager
    (app.tray-manager.drop)
    (set app.tray-manager nil))
  (set app.notify nil)
  (when (and app.volume-settings-handler VolumeControl.volume-settings-changed-debounced)
    (VolumeControl.volume-settings-changed-debounced:disconnect app.volume-settings-handler true)
    (set app.volume-settings-handler nil))
  (when (and app.settings app.settings.drop)
    (app.settings.drop)
    (set app.settings nil))
  )

(when (and app.engine AppConfig.run-main)
  (when (not (app.engine:start))
    (error "[space] engine failed to start (window/GL init failed)"))
  (app.init)
  (app.engine:run)
  (app.drop)
  (app.engine:shutdown))
