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

(set app.engine-autocreated false)
(when (not app.engine)
  (set app.engine (EngineModule.Engine {}))
  (set app.engine-autocreated true))

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
(local TerrainIssueLog (require :terrain-issue-log))
(TerrainIssueLog.start-session! "space startup")
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
(local Signal (require :signal))
(local Settings (require :settings))
(local RuntimePerformance (require :runtime-performance))
(local VolumeControl (require :volume-control))
(local MenuManager (require :menu-manager))
(local WalletManager (require :wallet-manager))

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
    (set app.user-data-dir data-dir)
    (local apps-dir (fs.join-path data-dir "apps"))
    (local worlds-dir (fs.join-path data-dir "worlds"))
    (when (and fs fs.create-dirs)
      (fs.create-dirs apps-dir))
    (when (and fs fs.create-dirs)
      (fs.create-dirs worlds-dir))
    (set app.worlds-dir worlds-dir)
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

(fn ensure-runtime-performance-state []
  (if (not app.runtime-performance-state)
      (set app.runtime-performance-state (RuntimePerformance.create-state)))
  app.runtime-performance-state)

(fn wall-now-ms []
  (assert (and app.engine app.engine.now-ms)
          "app.engine.now-ms missing")
  (app.engine:now-ms))

(fn sync-physics-paused-state []
  (when (and app.engine app.engine.set-physics-paused)
    (app.engine.set-physics-paused
      (or (= app.runtime-performance-physics-paused true)
          (not (= app.startup-physics-pause-owner nil)))))
  true)

(fn apply-runtime-performance-settings []
  (if (and app.settings app.engine)
      (do
        (local state (ensure-runtime-performance-state))
        (local prev-control app.runtime-performance-control-mode)
        (local prev-mode app.runtime-performance-active-mode)
        (local prev-fps app.runtime-performance-fps-cap)
        (local prev-physics app.runtime-performance-physics-paused)
        (local prev-input app.runtime-performance-input-paused)
        (local prev-ui app.runtime-performance-ui-paused)
        (local prev-source app.runtime-performance-source)
        (local prev-override app.runtime-performance-active-override)
        (local result (RuntimePerformance.apply-settings app.settings state app.engine))
        (when result
          (set app.runtime-performance-control-mode result.control_mode)
          (set app.runtime-performance-active-mode result.effective_mode)
          (set app.runtime-performance-fps-cap result.fps_cap)
          (set app.runtime-performance-physics-paused result.pause_physics)
          (set app.runtime-performance-input-paused result.pause_input)
          (set app.runtime-performance-ui-paused result.pause_ui)
          (set app.runtime-performance-source result.source)
          (set app.runtime-performance-active-override result.active_override)
          (sync-physics-paused-state)
          (when (or (not (= prev-control result.control_mode))
                    (not (= prev-mode result.effective_mode))
                    (not (= prev-fps result.fps_cap))
                    (not (= prev-physics result.pause_physics))
                    (not (= prev-input result.pause_input))
                    (not (= prev-ui result.pause_ui))
                    (not (= prev-source result.source))
                    (not (= prev-override result.active_override)))
            (logging.info
              (string.format
                "[space] runtime-performance control=%s mode=%s fps=%s physics-paused=%s input-paused=%s ui-paused=%s source=%s override=%s (prev control=%s mode=%s fps=%s physics-paused=%s input-paused=%s ui-paused=%s source=%s override=%s)"
                (tostring result.control_mode)
                (tostring result.effective_mode)
                (tostring result.fps_cap)
                (tostring result.pause_physics)
                (tostring result.pause_input)
                (tostring result.pause_ui)
                (tostring result.source)
                (tostring result.active_override)
                (tostring prev-control)
                (tostring prev-mode)
                (tostring prev-fps)
                (tostring prev-physics)
                (tostring prev-input)
                (tostring prev-ui)
                (tostring prev-source)
                (tostring prev-override))))))))

(fn app.set-startup-physics-paused [owner paused]
  (assert (and (= (type owner) :string) (> (# owner) 0))
          "set-startup-physics-paused requires non-empty string owner")
  (if paused
      (set app.startup-physics-pause-owner owner)
      (when (= app.startup-physics-pause-owner owner)
        (set app.startup-physics-pause-owner nil)))
  (sync-physics-paused-state)
  (= app.startup-physics-pause-owner owner))

(fn app.set-runtime-performance-control-mode [control-mode]
  (assert (and app.settings app.settings.set-value) "settings must be initialized")
  (local normalized (RuntimePerformance.normalize-control-mode control-mode))
  (app.settings.set-value "runtime_performance.control_mode" normalized {:save? true})
  (apply-runtime-performance-settings)
  normalized)

(fn app.set-runtime-performance-manual-mode [mode]
  (assert (and app.settings app.settings.set-value) "settings must be initialized")
  (local normalized (RuntimePerformance.normalize-mode mode))
  (app.settings.set-value "runtime_performance.manual_mode" normalized {:save? true})
  (apply-runtime-performance-settings)
  normalized)

(fn app.activate-runtime-performance-lease [opts]
  (local state (ensure-runtime-performance-state))
  (local lease (RuntimePerformance.activate-lease state opts))
  (apply-runtime-performance-settings)
  lease)

(fn app.clear-runtime-performance-lease [id]
  (local state (ensure-runtime-performance-state))
  (RuntimePerformance.clear-lease state id)
  (apply-runtime-performance-settings)
  true)

(fn app.activate-runtime-performance-gameplay-lease [id]
  (assert (and (= (type id) :string) (> (# id) 0))
          "activate-runtime-performance-gameplay-lease requires non-empty string id")
  (if (not app.settings)
      nil
      (do
  (local state (ensure-runtime-performance-state))
  (local lease (RuntimePerformance.activate-gameplay-lease app.settings state id))
  (apply-runtime-performance-settings)
  lease)))

(fn app.clear-runtime-performance-gameplay-lease [id]
  (assert (and (= (type id) :string) (> (# id) 0))
          "clear-runtime-performance-gameplay-lease requires non-empty string id")
  (local state (ensure-runtime-performance-state))
  (RuntimePerformance.clear-gameplay-lease state id)
  (apply-runtime-performance-settings)
  true)

(fn mark-runtime-performance-input-activity []
  (local state (ensure-runtime-performance-state))
  (local was-idle (RuntimePerformance.note-input state (os.clock)))
  (when was-idle
    (apply-runtime-performance-settings)))

(local runtime-performance-input-signal-names
  ["key-down"
   "key-up"
   "mouse-motion"
   "mouse-button-down"
   "mouse-button-up"
   "mouse-wheel"
   "text-input"
   "text-editing"
   "gamepad-axis-motion"
   "gamepad-button-down"
   "gamepad-button-up"])

(fn disconnect-runtime-performance-input-handlers []
  (when (and app.runtime-performance-input-handlers app.engine.events)
    (each [_ name (ipairs runtime-performance-input-signal-names)]
      (local handler (. app.runtime-performance-input-handlers name))
      (local signal (. app.engine.events name))
      (when (and signal handler)
        (signal:disconnect handler true))))
  (set app.runtime-performance-input-handlers {}))

(fn connect-runtime-performance-input-handlers []
  (set app.runtime-performance-input-handlers {})
  (if (not (and app.engine app.engine.events))
      nil
      (do
        (each [_ name (ipairs runtime-performance-input-signal-names)]
          (local signal (. app.engine.events name))
          (when signal
            (tset app.runtime-performance-input-handlers name
                 (signal:connect
                   (fn [_event]
                     (mark-runtime-performance-input-activity)))))))))

(fn init-settings []
  (when (and app.settings app.settings.drop)
    (app.settings.drop))
  (set app.settings (Settings {:app-name "space"}))
  (if app.runtime-performance-state
      (do
        (RuntimePerformance.set-focused app.runtime-performance-state true)
        (RuntimePerformance.set-minimized app.runtime-performance-state false)
        (RuntimePerformance.set-occluded app.runtime-performance-state false)
        (RuntimePerformance.set-hidden app.runtime-performance-state false)
        (RuntimePerformance.set-suspended app.runtime-performance-state false)
        (RuntimePerformance.set-screen-locked app.runtime-performance-state false)
        (RuntimePerformance.set-on-battery app.runtime-performance-state false)
        (RuntimePerformance.set-video-playback app.runtime-performance-state false))
      (ensure-runtime-performance-state))
  (when app.engine
    (when app.engine.is-on-battery
      (RuntimePerformance.set-on-battery app.runtime-performance-state (not (= (app.engine.is-on-battery) false))))
    (when app.engine.has-active-video-playback
      (RuntimePerformance.set-video-playback
        app.runtime-performance-state
        (not (= (app.engine.has-active-video-playback) false)))))
  (local changed (RuntimePerformance.ensure-settings-defaults app.settings))
  (if (and changed app.settings app.settings.save)
      (do
        (app.settings.save)))
  (RuntimePerformance.note-input app.runtime-performance-state (os.clock))
  (apply-runtime-performance-settings)
  (local stored-volume (app.settings.get-value "audio.volume" nil))
  (local stored-muted (app.settings.get-value "audio.muted" nil))
  (when (or (not (= stored-volume nil)) (not (= stored-muted nil)))
    (VolumeControl.apply-settings {:volume stored-volume :muted? stored-muted}))
  (disconnect-volume-settings)
  (connect-volume-settings))

(fn normalize-window-mode [mode]
  (if (= mode "windowed")
      "windowed"
      (= mode "fullscreen")
      "fullscreen"
      "maximized"))

(fn sanitize-window-dimension [value]
  (if (and (= (type value) :number) (> value 0))
      (math.floor value)
      nil))

(fn load-window-startup-options []
  (local settings (Settings {:app-name "space"}))
  (local mode (normalize-window-mode (settings.get-value "window.mode" "maximized")))
  (local width (sanitize-window-dimension (settings.get-value "window.width" nil)))
  (local height (sanitize-window-dimension (settings.get-value "window.height" nil)))
  (settings.drop)
  (local options {:window-mode mode})
  (when width
    (set (. options :width) width))
  (when height
    (set (. options :height) height))
  options)

(fn schedule-window-settings-save []
  (set app.window-settings-dirty true)
  (set app.window-settings-save-deadline (+ (os.clock) 0.25)))

(fn flush-window-settings-save []
  (when (and app.window-settings-dirty
             app.settings
             app.settings.save
             (>= (os.clock) app.window-settings-save-deadline))
    (app.settings.save)
    (set app.window-settings-dirty false)))

(fn persist-window-size [width height]
  (when (and app.settings app.settings.set-value)
    (local safe-width (sanitize-window-dimension width))
    (local safe-height (sanitize-window-dimension height))
    (when (and safe-width safe-height)
      (app.settings.set-value "window.width" safe-width {:save? false})
      (app.settings.set-value "window.height" safe-height {:save? false})
      (schedule-window-settings-save))))

(fn persist-window-mode [mode]
  (when (and app.settings app.settings.set-value)
    (local safe-mode (normalize-window-mode mode))
    (app.settings.set-value "window.mode" safe-mode {:save? false})
    (if (= safe-mode "windowed")
        (persist-window-size (and app.engine app.engine.width)
                             (and app.engine app.engine.height)))
    (schedule-window-settings-save)))

(fn matches-filters? [target filters]
  (or
    (= filters nil)
    (each [k v (pairs filters)]
      (when (not (= (. target k) v))
        (lua "return false")))
    true))

(local {:to-table viewport->table
        :to-glm-vec4 viewport->glm-vec4
        :input-pos->viewport-pos viewport->input-pos} (require :viewport-utils))
(local Hud (require :hud))
(local AppViewport (require :app-viewport))
(local AppProjection (require :app-projection))
(local {: FocusManager} (require :focus))
(local Tray (require :tray-manager))
(local Notify (require :notify-manager))
(local AppBootstrap (require :app-bootstrap))
(local WorldManager (require :world-manager))
(local WorldTabsWidget (require :world-tabs-widget))
(local InputState (require :input-state-router))
(local Modifiers (require :input-modifiers))

(local FrameProfiler (require :frame-profiler))

(local number-or
  (fn [value fallback]
    (if (not (= value nil)) value fallback)))

(set (. app :set-viewport) (. AppViewport :set-viewport))
(set (. app :create-default-projection) (. AppProjection :create-default-projection))

(fn current-pixel-viewport-size []
  (local pixel-width (or (and app.engine (. app.engine "pixel-width")) 0))
  (local pixel-height (or (and app.engine (. app.engine "pixel-height")) 0))
  (if (and (> pixel-width 0) (> pixel-height 0))
      {:width pixel-width :height pixel-height}
      (let [width (or (and app.engine app.engine.width) 0)
            height (or (and app.engine app.engine.height) 0)]
        {:width width :height height})))

(fn app.reset-projection []
  (if app.scene
      (app.scene:reset-projection)
      (set app.projection (app.create-default-projection)))
  (when app.scene
    (set app.projection app.scene.projection))
  (when app.canvas
    (app.canvas:reset-projection))
  (when app.hud
    (app.hud:reset-projection)))

(fn resolve-screen-ray-target [opts]
  (local options (or opts {}))
  (local explicit-target (or options.target options.pointer-target))
  (if explicit-target
      explicit-target
      (do
        (local explicit-surface options.surface)
        (if (= explicit-surface :canvas)
            app.canvas
            (= explicit-surface :scene)
            app.scene
            (if (and (= app.active-interaction-surface :canvas)
                     app.canvas
                     (= app.canvas-visible? true))
                app.canvas
                app.scene)))))

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
  (local preferred-target (resolve-screen-ray-target opts))
  (if (and preferred-target preferred-target.screen-pos-ray)
      (let [options (if opts
                      (let [copy {}]
                        (each [k v (pairs opts)]
                          (set (. copy k) v))
                        copy)
                      {})]
        (when (and (= preferred-target app.scene)
                   (not options.projection)
                   app.projection)
          (set options.projection app.projection))
        (preferred-target:screen-pos-ray pos options))
      (let [options (or opts {})
            viewport (viewport->table (or options.viewport app.viewport))
            view (or options.view
                     (and app.camera (app.camera:get-view-matrix)))
            projection (or options.projection app.projection)]
        (assert view "app.screen-pos-ray requires a view matrix")
        (assert projection "app.screen-pos-ray requires a projection matrix")
        (local sample-pos (or (viewport->input-pos pos viewport app.engine)
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
(set app.canvas nil)
(set app.hud nil)
(set app.profiler nil)
(set app.movables nil)
(set app.focus nil)
(set app.scene-focus-scope nil)
(set app.canvas-focus-scope nil)
(set app.hud-focus-scope nil)
(set app.canvas-controls nil)
(set app.active-pointer-controls nil)
(set app.preferred-interaction-surface :scene)
(set app.active-interaction-surface :scene)
(set app.active-canvas-feature "graph")
(set app.scene-interactive? true)
(set app.canvas-interactive? false)
(set app.canvas-visible? false)
(set app.graph-view nil)
(set app.tray-manager nil)
(set app.menu-manager nil)
(set app.notify nil)
(set app.kernels nil)
(set app.settings nil)
(set app.volume-settings-handler nil)
(set app.window-resized-handler nil)
(set app.window-pixel-size-handler nil)
(set app.window-mode-handler nil)
(set app.window-focus-handler nil)
(set app.window-minimized-handler nil)
(set app.window-occluded-handler nil)
(set app.window-hidden-handler nil)
(set app.app-suspended-handler nil)
(set app.screen-locked-handler nil)
(set app.runtime-performance-input-handlers {})
(set app.update-handler nil)
(set app.engine-tick-handler nil)
(set app.global-shortcuts-handler nil)
(set app.remote-control nil)
(set app.remote-control-endpoint nil)
(set app.browser-cube-surface nil)
(set app.next-frame-queue [])
(set app.next-frame-pending [])
(set app.window-settings-dirty false)
(set app.window-settings-save-deadline 0)
(set app.runtime-performance-state nil)
(set app.runtime-performance-control-mode nil)
(set app.runtime-performance-active-mode nil)
(set app.runtime-performance-fps-cap nil)
(set app.runtime-performance-physics-paused nil)
(set app.startup-physics-pause-owner nil)
(set app.runtime-performance-input-paused nil)
(set app.runtime-performance-ui-paused nil)
(set app.runtime-performance-source nil)
(set app.runtime-performance-active-override nil)
(set app.world-manager nil)
(set app.world-tabs-builder nil)
(set app.active-world-hud-contrib nil)
(set app.active-world-hud-overlay nil)
(set app.canvas-shell-changed (Signal))

(fn app.next-frame [cb]
  (assert cb "app.next-frame requires callback")
  (table.insert app.next-frame-queue cb))

(fn run-next-ui-frame []
  (local pending app.next-frame-pending)
  (set app.next-frame-pending [])
  (each [_ cb (ipairs pending)]
    (cb)))

(fn canvas-shell-state []
  {:interaction-surface app.active-interaction-surface
   :canvas-feature app.active-canvas-feature
   :canvas-visible? (= app.canvas-visible? true)})

(fn canvas-shell-state= [a b]
  (and a b
       (= a.interaction-surface b.interaction-surface)
       (= a.canvas-feature b.canvas-feature)
       (= a.canvas-visible? b.canvas-visible?)))

(fn emit-canvas-shell-changed [reason previous]
  (local current (canvas-shell-state))
  (when (and app.canvas-shell-changed
             (not (canvas-shell-state= previous current)))
    (app.canvas-shell-changed:emit {:reason reason
                                    :previous previous
                                    :current current}))
  current)

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

(local SDLK_TAB 9)
(local KEY_W_LOWER (string.byte "w"))
(local KEY_W_UPPER (string.byte "W"))
(local KEY_1 (string.byte "1"))
(local KEY_9 (string.byte "9"))

(fn world-tab-status-builder []
  (assert app.world-manager "world-tab-status-builder requires app.world-manager")
  (fn [ctx]
    ((WorldTabsWidget {:world-manager app.world-manager
                       :tab-spacing 0.1}) ctx)))

(fn world-runtime-context []
  {:hud app.hud
   :focus-manager app.focus
   :focus-root (and app.focus (app.focus:get-root-scope))
   :icons app.icons
   :states app.states
   :movables app.movables})

(fn resolve-active-world-hud-contrib []
  (local entry (and app.world-manager (app.world-manager:active-world)))
  (local world (and entry entry.world))
  (if (and world world.get-hud-contrib)
      (or (world:get-hud-contrib) {})
      {}))

(fn clear-active-world-hud-overlay []
  (when (and app.hud app.active-world-hud-overlay)
    (app.hud:remove-overlay-child app.active-world-hud-overlay)
    (set app.active-world-hud-overlay nil)))

(fn apply-active-world-hud-contrib []
  (when app.hud
    (local contrib (resolve-active-world-hud-contrib))
    (set app.active-world-hud-contrib contrib)
    (local control-panel-opts {:status-builder app.world-tabs-builder})
    (local status-panel-opts {})
    (when contrib.control_panel_body
      (set control-panel-opts.body-builder contrib.control_panel_body))
    (when contrib.status_panel_body
      (set status-panel-opts.body-builder contrib.status_panel_body))
    (local hud-opts {:control-panel-opts control-panel-opts})
    (when (or status-panel-opts.body-builder)
      (set hud-opts.status-panel-opts status-panel-opts))
    (when contrib.left_dock_builder
      (set hud-opts.left-dock-builder contrib.left_dock_builder))
    (app.hud:build-default hud-opts)
    (clear-active-world-hud-overlay)
    (when contrib.overlay
      (set app.active-world-hud-overlay
           (app.hud:add-overlay-child {:builder contrib.overlay})))
    (app.reset-projection)))

(set app.apply-active-world-hud-contrib apply-active-world-hud-contrib)

(fn app.request-theme-change [theme-name]
  (assert theme-name "app.request-theme-change requires a theme name")
  ;; Theme changes rebuild scene/HUD shell state. Do not run them directly from
  ;; widget/input callbacks or route them through BucketQueue tolerance hacks.
  ;; Defer to the next UI frame boundary so input dispatch and current layout work
  ;; have fully unwound before the rebuild runs.
  (assert app.next-frame "app.request-theme-change requires app.next-frame")
  (app.next-frame
    (fn []
      (local ThemeActions (require :theme-actions))
      (ThemeActions.apply-theme theme-name)))
  theme-name)

(fn resolve-interaction-surface [surface]
  (if (= surface :canvas)
      (if app.canvas :canvas :scene)
      :scene))

(fn effective-interaction-surface [preferred-surface canvas-visible?]
  (if (and (= preferred-surface :canvas)
           canvas-visible?)
      :canvas
      :scene))

(fn resolve-canvas-feature [feature]
  (local resolved (or feature "graph"))
  (if (= resolved "drawing")
      "drawing"
      "graph"))

(fn mark-active-world-hud-dirty []
  (when (and app.hud app.hud.entity app.hud.entity.layout)
    (app.hud.entity.layout:mark-measure-dirty)
    (app.hud.entity.layout:mark-layout-dirty))
  true)

(set app.mark-active-world-hud-dirty mark-active-world-hud-dirty)

(fn sync-interaction-surface-state [reason previous]
  (local preferred-surface (resolve-interaction-surface app.preferred-interaction-surface))
  (local canvas-visible? (and app.canvas (= app.canvas-visible? true)))
  (local surface (effective-interaction-surface preferred-surface canvas-visible?))
  (set app.preferred-interaction-surface preferred-surface)
  (set app.active-interaction-surface surface)
  (set app.canvas-visible? canvas-visible?)
  (set app.scene-interactive? (= surface :scene))
  (set app.canvas-interactive? (and canvas-visible?
                                     (= surface :canvas)))
  (if app.canvas-interactive?
      (set app.active-pointer-controls app.canvas-controls)
      (set app.active-pointer-controls app.first-person-controls))
  (emit-canvas-shell-changed (or reason "interaction-surface") previous)
  (mark-active-world-hud-dirty)
  surface)

(fn app.set-canvas-visible [visible?]
  (local previous (canvas-shell-state))
  (set app.canvas-visible? (and app.canvas
                                (not (= visible? false))))
  (sync-interaction-surface-state "canvas-visibility" previous))

(fn app.set-active-interaction-surface [surface opts]
  (local options (or opts {}))
  (local previous (canvas-shell-state))
  (set app.preferred-interaction-surface (resolve-interaction-surface surface))
  (when (or (= options.sync-canvas-visibility nil)
            options.sync-canvas-visibility)
    (set app.canvas-visible? (and app.canvas
                                  (= app.preferred-interaction-surface :canvas))))
  (sync-interaction-surface-state "interaction-surface" previous))

(fn app.set-active-canvas-feature [feature]
  (local previous (canvas-shell-state))
  (local resolved (resolve-canvas-feature feature))
  (set app.active-canvas-feature resolved)
  (when app.active-world-runtime
    (set app.active-world-runtime.active-canvas-feature resolved))
  (emit-canvas-shell-changed "canvas-feature" previous)
  (mark-active-world-hud-dirty)
  resolved)

(fn app.toggle-active-interaction-surface []
  (if (not app.canvas)
      false
      (if (= app.active-interaction-surface :canvas)
          (app.set-active-interaction-surface :scene
                                              {:sync-canvas-visibility true})
          (app.set-active-interaction-surface :canvas
                                              {:sync-canvas-visibility true}))))

(fn pointer-target-surface [target]
  (if (or (= target nil)
          (= target app.scene)
          (= (and target target.interaction-surface) :scene))
      :scene
      (if (or (= target app.canvas)
              (= (and target target.interaction-surface) :canvas))
          :canvas
          (if (or (= target app.hud)
                  (= (and target target.interaction-surface) :hud))
              :hud
              nil))))

(fn app.pointer-target-enabled? [target]
  (local surface (pointer-target-surface target))
  (local canvas-feature (and target target.canvas-feature))
  (local canvas-enabled?
    (and (= app.canvas-interactive? true)
         (if canvas-feature
             (= (resolve-canvas-feature canvas-feature) app.active-canvas-feature)
             true)))
  (if (= surface :scene)
      (= app.scene-interactive? true)
      (if (= surface :canvas)
          canvas-enabled?
          true)))

(fn bind-active-world-runtime [entry runtime]
  (set app.active-world-entry entry)
  (set app.active-world-runtime runtime)
  (set app.camera (and runtime runtime.camera))
  (set app.first-person-controls (and runtime runtime.first-person-controls))
  (set app.scene-focus-scope (and runtime runtime.scene-scope))
  (set app.canvas-focus-scope (and runtime runtime.canvas-scope))
  (set app.scene (and runtime runtime.scene))
  (set app.canvas (and runtime runtime.canvas))
  (set app.canvas-controls (and runtime runtime.canvas-controls))
  (set app.object-selector (and runtime runtime.object-selector))
  (set app.terrain-rect-pick-session nil)
  (set app.terrain-rect-pick-previous-state nil)
  (set app.terrain-paint-session nil)
  (set app.terrain-paint-previous-state nil)
  (set app.graph (and runtime runtime.graph))
  (set app.graph-view (and runtime runtime.graph-view))
  (set app.drawing-controller (and runtime runtime.drawing-controller))
  (set app.drawing-render (and runtime runtime.drawing-render))
  (set app.layout-root (and app.scene app.scene.layout-root))
  (when (and app.scene app.scene.set-camera)
    (app.scene:set-camera app.camera))
  (when app.hud
    (set app.hud.scene app.scene)
    (when app.hud.build-context
      (set app.hud.build-context.object-selector app.object-selector)
      (set app.hud.build-context.layout-root app.layout-root)))
  (when (and app.canvas app.canvas.build-context)
    (set app.canvas.build-context.object-selector app.object-selector))
  (when (and app.scene app.scene.build-context)
    (set app.scene.build-context.object-selector app.object-selector)
    (set app.scene.build-context.layout-root app.layout-root))
  (apply-active-world-hud-contrib)
  (when (and runtime runtime.restore-surface-state)
    (runtime:restore-surface-state app.canvas app.hud))
  (app.set-active-canvas-feature (and runtime runtime.active-canvas-feature))
  (app.set-active-interaction-surface app.preferred-interaction-surface
                                      {:sync-canvas-visibility false}))

(local installable-reset-projection app.reset-projection)
(local installable-mark-active-world-hud-dirty app.mark-active-world-hud-dirty)
(local installable-set-canvas-visible app.set-canvas-visible)
(local installable-set-active-interaction-surface app.set-active-interaction-surface)
(local installable-set-active-canvas-feature app.set-active-canvas-feature)
(local installable-toggle-active-interaction-surface app.toggle-active-interaction-surface)
(local installable-pointer-target-enabled? app.pointer-target-enabled?)
(local installable-bind-active-world-runtime bind-active-world-runtime)

(fn install-app-shell! []
  (set app.canvas-shell-changed (or app.canvas-shell-changed (Signal)))
  (set app.reset-projection installable-reset-projection)
  (set app.mark-active-world-hud-dirty installable-mark-active-world-hud-dirty)
  (set app.set-canvas-visible installable-set-canvas-visible)
  (set app.set-active-interaction-surface installable-set-active-interaction-surface)
  (set app.set-active-canvas-feature installable-set-active-canvas-feature)
  (set app.toggle-active-interaction-surface installable-toggle-active-interaction-surface)
  (set app.pointer-target-enabled? installable-pointer-target-enabled?)
  (set app.bind-active-world-runtime installable-bind-active-world-runtime)
  true)

(set app.install-app-shell! install-app-shell!)
(set app.bind-active-world-runtime bind-active-world-runtime)

(fn init-world-manager []
  (when (and app.world-manager app.world-manager.drop)
    (app.world-manager:drop))
  (assert app.worlds-dir "init-world-manager requires app.worlds-dir")
  (set app.world-manager
       (WorldManager {:root-dir app.worlds-dir
                      :asset-path-resolver (and app.engine app.engine.get-asset-path)
                      :context-fn world-runtime-context
                      :on-active-runtime bind-active-world-runtime
                      :on-empty (fn []
                                  (when (and app.engine app.engine.quit)
                                    (app.engine.quit)))
                      :suspend-delay-ms 3000}))
  (set app.world-tabs-builder (world-tab-status-builder))
  app.world-manager)

(fn world-shortcut-conflict? []
  (and InputState InputState.active-input (InputState.active-input)))

(fn handle-global-world-shortcut [payload]
  (if (or (not payload) (not app.world-manager))
      false
      (do
        (local key payload.key)
        (local ctrl? (Modifiers.ctrl-held? payload.mod))
        (local shift? (Modifiers.shift-held? payload.mod))
        (local alt? (Modifiers.alt-held? payload.mod))
        (local tab-shortcut? (and ctrl? (= key SDLK_TAB)))
        (local close-shortcut? (and ctrl? (or (= key KEY_W_LOWER) (= key KEY_W_UPPER))))
        (local alt-number-shortcut?
          (and alt? (= (type key) :number) (>= key KEY_1) (<= key KEY_9)))
        (if (or tab-shortcut? close-shortcut? alt-number-shortcut?)
            (do
              (when (world-shortcut-conflict?)
                (error "World shortcut conflict: input widget has focus"))
              (if tab-shortcut?
                  (if shift?
                      (app.world-manager:activate-previous)
                      (app.world-manager:activate-next))
                  close-shortcut?
                  (app.world-manager:close-active-world)
                  alt-number-shortcut?
                  (app.world-manager:activate-by-tab-number (+ 1 (- key KEY_1)))
                  false)
              true)
            false))))

(fn app.init []
  (local init-start-ms (wall-now-ms))
  (assert (and app.engine app.engine.events) "app.engine.events missing; load engine-events before app.init")
  (set app.startup-physics-pause-owner nil)
  (set app.next-frame-queue [])
  (set app.next-frame-pending [])
  (sync-physics-paused-state)
  (init-app-dirs)
  (init-settings)
  (app.reset-projection)
  (when (and app.window-resized-handler app.engine.events app.engine.events.window-resized)
    (app.engine.events.window-resized:disconnect app.window-resized-handler true)
    (set app.window-resized-handler nil))
  (when (and app.window-pixel-size-handler app.engine.events app.engine.events.window-pixel-size-changed)
    (app.engine.events.window-pixel-size-changed:disconnect app.window-pixel-size-handler true)
    (set app.window-pixel-size-handler nil))
  (when (and app.window-mode-handler app.engine.events app.engine.events.window-mode-changed)
    (app.engine.events.window-mode-changed:disconnect app.window-mode-handler true)
    (set app.window-mode-handler nil))
  (when (and app.window-focus-handler app.engine.events app.engine.events.window-focus-changed)
    (app.engine.events.window-focus-changed:disconnect app.window-focus-handler true)
    (set app.window-focus-handler nil))
  (when (and app.window-minimized-handler app.engine.events app.engine.events.window-minimized-changed)
    (app.engine.events.window-minimized-changed:disconnect app.window-minimized-handler true)
    (set app.window-minimized-handler nil))
  (when (and app.window-occluded-handler app.engine.events app.engine.events.window-occluded-changed)
    (app.engine.events.window-occluded-changed:disconnect app.window-occluded-handler true)
    (set app.window-occluded-handler nil))
  (when (and app.window-hidden-handler app.engine.events app.engine.events.window-hidden-changed)
    (app.engine.events.window-hidden-changed:disconnect app.window-hidden-handler true)
    (set app.window-hidden-handler nil))
  (when (and app.app-suspended-handler app.engine.events app.engine.events.app-suspended-changed)
    (app.engine.events.app-suspended-changed:disconnect app.app-suspended-handler true)
    (set app.app-suspended-handler nil))
  (when (and app.screen-locked-handler app.engine.events app.engine.events.screen-locked-changed)
    (app.engine.events.screen-locked-changed:disconnect app.screen-locked-handler true)
    (set app.screen-locked-handler nil))
  (when (and app.on-battery-handler app.engine.events app.engine.events.on-battery-changed)
    (app.engine.events.on-battery-changed:disconnect app.on-battery-handler true)
    (set app.on-battery-handler nil))
  (when (and app.video-playback-active-handler app.engine.events app.engine.events.video-playback-active-changed)
    (app.engine.events.video-playback-active-changed:disconnect app.video-playback-active-handler true)
    (set app.video-playback-active-handler nil))
  (disconnect-runtime-performance-input-handlers)
  (when (and app.engine.events app.engine.events.window-resized)
    (set app.window-resized-handler
         (app.engine.events.window-resized:connect
           (fn [e]
             (app.set-viewport (current-pixel-viewport-size))
             (app.reset-projection)
             (if (= (normalize-window-mode (and app.engine (. app.engine "window-mode"))) "windowed")
                 (persist-window-size e.width e.height))))))
  (when (and app.engine.events app.engine.events.window-pixel-size-changed)
    (set app.window-pixel-size-handler
         (app.engine.events.window-pixel-size-changed:connect
           (fn [_e]
             (app.set-viewport (current-pixel-viewport-size))
             (app.reset-projection)))))
  (when (and app.engine.events app.engine.events.window-mode-changed)
    (set app.window-mode-handler
         (app.engine.events.window-mode-changed:connect
           (fn [e]
             (when app.engine
               (set (. app.engine "window-mode") (normalize-window-mode e.mode)))
             (persist-window-mode e.mode)))))
  (when (and app.engine.events app.engine.events.window-focus-changed)
    (set app.window-focus-handler
         (app.engine.events.window-focus-changed:connect
           (fn [e]
             (local state (ensure-runtime-performance-state))
             (RuntimePerformance.set-focused state (not (= e.focused false)))
             (apply-runtime-performance-settings)))))
  (when (and app.engine.events app.engine.events.window-minimized-changed)
    (set app.window-minimized-handler
         (app.engine.events.window-minimized-changed:connect
           (fn [e]
             (local state (ensure-runtime-performance-state))
             (RuntimePerformance.set-minimized state (not (= e.minimized false)))
             (apply-runtime-performance-settings)))))
  (when (and app.engine.events app.engine.events.window-occluded-changed)
    (set app.window-occluded-handler
         (app.engine.events.window-occluded-changed:connect
           (fn [e]
             (local state (ensure-runtime-performance-state))
             (RuntimePerformance.set-occluded state (not (= e.occluded false)))
             (apply-runtime-performance-settings)))))
  (when (and app.engine.events app.engine.events.window-hidden-changed)
    (set app.window-hidden-handler
         (app.engine.events.window-hidden-changed:connect
           (fn [e]
             (local state (ensure-runtime-performance-state))
             (RuntimePerformance.set-hidden state (not (= e.hidden false)))
             (apply-runtime-performance-settings)))))
  (when (and app.engine.events app.engine.events.app-suspended-changed)
    (set app.app-suspended-handler
         (app.engine.events.app-suspended-changed:connect
           (fn [e]
             (local state (ensure-runtime-performance-state))
             (RuntimePerformance.set-suspended state (not (= e.suspended false)))
             (apply-runtime-performance-settings)))))
  (when (and app.engine.events app.engine.events.screen-locked-changed)
    (set app.screen-locked-handler
         (app.engine.events.screen-locked-changed:connect
           (fn [e]
             (local state (ensure-runtime-performance-state))
             (RuntimePerformance.set-screen-locked state (not (= e.locked false)))
             (apply-runtime-performance-settings)))))
  (when (and app.engine.events app.engine.events.on-battery-changed)
    (set app.on-battery-handler
         (app.engine.events.on-battery-changed:connect
           (fn [e]
             (local state (ensure-runtime-performance-state))
             (RuntimePerformance.set-on-battery state (not (= e.on_battery false)))
             (apply-runtime-performance-settings)))))
  (when (and app.engine.events app.engine.events.video-playback-active-changed)
    (set app.video-playback-active-handler
         (app.engine.events.video-playback-active-changed:connect
           (fn [e]
             (local state (ensure-runtime-performance-state))
             (RuntimePerformance.set-video-playback state (not (= e.active false)))
             (apply-runtime-performance-settings)))))
  (connect-runtime-performance-input-handlers)
  (when (and app.update-handler app.engine.events app.engine.events.updated)
    (app.engine.events.updated:disconnect app.update-handler true)
    (set app.update-handler nil))
  (when (and app.engine.events app.engine.events.updated)
    (set app.update-handler (app.engine.events.updated:connect app.update)))
  (when (and app.engine-tick-handler app.engine.events app.engine.events.engine-tick)
    (app.engine.events.engine-tick:disconnect app.engine-tick-handler true)
    (set app.engine-tick-handler nil))
  (when (and app.engine.events app.engine.events.engine-tick)
    (set app.engine-tick-handler
         (app.engine.events.engine-tick:connect
           (fn [_payload]
             (when app.remote-control
               (app.remote-control:tick))
             (when (and app.kernels app.kernels.tick)
               (app.kernels:tick))))))
  (when (and app.global-shortcuts-handler app.engine.events app.engine.events.key-down)
    (app.engine.events.key-down:disconnect app.global-shortcuts-handler true)
    (set app.global-shortcuts-handler nil))
  (when (and app.engine.events app.engine.events.key-down)
    (set app.global-shortcuts-handler
         (app.engine.events.key-down:connect handle-global-world-shortcut)))

  (when app.remote-control
    (app.remote-control:drop)
    (set app.remote-control nil))
  (when app.remote-control-endpoint
    (local RemoteControl (require :remote-control))
    (set app.remote-control (RemoteControl {:endpoint app.remote-control-endpoint})))

  (when (and app.kernels app.kernels.drop)
    (app.kernels:drop)
    (set app.kernels nil))
  (local Kernels (require :kernels))
  (set app.kernels (Kernels.get-default))

  (AppBootstrap.init-themes)
  (AppBootstrap.init-lights)
  (AppBootstrap.init-input-systems)
  (local initial-width (or (and app.engine (. app.engine "pixel-width")) (and app.engine app.engine.width) 0))
  (local initial-height (or (and app.engine (. app.engine "pixel-height")) (and app.engine app.engine.height) 0))
  (when (and (> initial-width 0) (> initial-height 0))
    (app.set-viewport {:width initial-width :height initial-height}))
  (AppBootstrap.init-renderers {:viewport app.viewport})
  (AppBootstrap.init-icons)
  (local profiler-env (os.getenv "SPACE_FENNEL_PROFILE"))
  (local profiler-enabled
    (and profiler-env
         (not (or (= profiler-env "0")
                  (= (string.lower profiler-env) "false")
                  (= (string.lower profiler-env) "off")))))
  (set app.profiler (and profiler-enabled
                           (FrameProfiler {:threshold-ms 60.0
                                           :log-interval 0
                                           :enabled true})))

  (AppBootstrap.init-states)

  (when app.focus
    (app.focus:drop))
  (set app.focus (FocusManager {:root-name "space-focus"}))
  (local focus-manager app.focus)
  (local hud-scope (focus-manager:create-scope {:name "hud"
                                                :directional-traversal-boundary? true}))
  (focus-manager:attach hud-scope (focus-manager:get-root-scope))
  (set app.scene-focus-scope nil)
  (set app.canvas-focus-scope nil)
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
  (local focus-manager app.focus)
  (local hud-scope app.hud-focus-scope)
  (set app.scene nil)
  (set app.canvas nil)
  (set app.camera nil)
  (set app.first-person-controls nil)
  (set app.canvas-controls nil)
  (set app.active-pointer-controls nil)
  (set app.preferred-interaction-surface :scene)
  (set app.active-interaction-surface :scene)
  (set app.scene-interactive? true)
  (set app.canvas-interactive? false)
  (set app.canvas-visible? false)
  (set app.graph nil)
  (set app.graph-view nil)
  (set app.object-selector nil)
  (set app.terrain-rect-pick-session nil)
  (set app.terrain-rect-pick-previous-state nil)
  (set app.terrain-paint-session nil)
  (set app.terrain-paint-previous-state nil)
  (set app.layout-root nil)

  (set app.hud (Hud {:scene nil
                     :focus-manager focus-manager
                     :focus-scope hud-scope
                     :icons app.icons
                     :states app.states
                     :movables app.movables}))
  (init-world-manager)
  (when app.world-manager
    (app.world-manager:activate-first))
  (app.reset-projection)
  (local browser-cube-demo-env (os.getenv "SPACE_BROWSER_CUBE_DEMO"))
  (local browser-cube-demo?
    (and browser-cube-demo-env
         (not (or (= browser-cube-demo-env "0")
                  (= (string.lower browser-cube-demo-env) "false")
                  (= (string.lower browser-cube-demo-env) "off")))))
  (when app.browser-cube-surface
    (app.browser-cube-surface:drop)
    (set app.browser-cube-surface nil))
  (when browser-cube-demo?
    (local BrowserCubeSurface (require :browser-cube-surface))
    (set app.browser-cube-surface (BrowserCubeSurface {})))
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

  (local init-end-ms (wall-now-ms))
  (logging.info
    (string.format "[space] init completed in %.2fms"
                   (- init-end-ms init-start-ms)))

  (app.update 0)
  (logging.info (string.format "[space] first update completed in %.2fms"
                               (- (wall-now-ms) init-end-ms)))
  )

(fn app.update [delta]
  (local profiler app.profiler)
  (fn run-section [label cb]
    (if profiler
        (profiler.measure label cb)
        (cb)))
  (local pending app.next-frame-pending)
  (local queued app.next-frame-queue)
  (set app.next-frame-queue [])
  (each [_ cb (ipairs queued)]
    (table.insert pending cb))
  (set app.next-frame-pending pending)
  (when profiler
    (profiler.begin-frame delta))
  (when (and app.settings app.runtime-performance-state)
    (if (RuntimePerformance.update-idle-state app.settings app.runtime-performance-state (os.clock))
        (apply-runtime-performance-settings)))
  (flush-window-settings-save)
  (local ui-paused (= app.runtime-performance-ui-paused true))
  (when (not ui-paused)
    (when (and app.world-manager app.world-manager.update)
      (app.world-manager:update delta))
    (when (and app.engine.audio app.camera)
      (local cam app.camera)
      (local forward (cam:get-forward))
      (local up (cam:get-up))
      (app.engine.audio:setListenerPosition cam.position)
      (app.engine.audio:setListenerOrientation forward up))
    (when app.scene
      (run-section "scene" (fn [] (app.scene:update))))
    (when app.canvas
      (run-section "canvas" (fn [] (app.canvas:update))))
    (when app.hud
      (run-section "hud" (fn [] (app.hud:update))))
    (when app.renderers
      (run-section "renderers" (fn [] (app.renderers:update))))
    (run-next-ui-frame))
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
  (when (and app.engine-tick-handler app.engine.events app.engine.events.engine-tick)
    (app.engine.events.engine-tick:disconnect app.engine-tick-handler true)
    (set app.engine-tick-handler nil))
  (when (and app.window-resized-handler app.engine.events app.engine.events.window-resized)
    (app.engine.events.window-resized:disconnect app.window-resized-handler true)
    (set app.window-resized-handler nil))
  (when (and app.window-pixel-size-handler app.engine.events app.engine.events.window-pixel-size-changed)
    (app.engine.events.window-pixel-size-changed:disconnect app.window-pixel-size-handler true)
    (set app.window-pixel-size-handler nil))
  (when (and app.window-mode-handler app.engine.events app.engine.events.window-mode-changed)
    (app.engine.events.window-mode-changed:disconnect app.window-mode-handler true)
    (set app.window-mode-handler nil))
  (when (and app.window-focus-handler app.engine.events app.engine.events.window-focus-changed)
    (app.engine.events.window-focus-changed:disconnect app.window-focus-handler true)
    (set app.window-focus-handler nil))
  (when (and app.window-minimized-handler app.engine.events app.engine.events.window-minimized-changed)
    (app.engine.events.window-minimized-changed:disconnect app.window-minimized-handler true)
    (set app.window-minimized-handler nil))
  (when (and app.window-occluded-handler app.engine.events app.engine.events.window-occluded-changed)
    (app.engine.events.window-occluded-changed:disconnect app.window-occluded-handler true)
    (set app.window-occluded-handler nil))
  (when (and app.window-hidden-handler app.engine.events app.engine.events.window-hidden-changed)
    (app.engine.events.window-hidden-changed:disconnect app.window-hidden-handler true)
    (set app.window-hidden-handler nil))
  (when (and app.app-suspended-handler app.engine.events app.engine.events.app-suspended-changed)
    (app.engine.events.app-suspended-changed:disconnect app.app-suspended-handler true)
    (set app.app-suspended-handler nil))
  (when (and app.screen-locked-handler app.engine.events app.engine.events.screen-locked-changed)
    (app.engine.events.screen-locked-changed:disconnect app.screen-locked-handler true)
    (set app.screen-locked-handler nil))
  (when (and app.on-battery-handler app.engine.events app.engine.events.on-battery-changed)
    (app.engine.events.on-battery-changed:disconnect app.on-battery-handler true)
    (set app.on-battery-handler nil))
  (when (and app.video-playback-active-handler app.engine.events app.engine.events.video-playback-active-changed)
    (app.engine.events.video-playback-active-changed:disconnect app.video-playback-active-handler true)
    (set app.video-playback-active-handler nil))
  (disconnect-runtime-performance-input-handlers)
  (when (and app.global-shortcuts-handler app.engine.events app.engine.events.key-down)
    (app.engine.events.key-down:disconnect app.global-shortcuts-handler true)
    (set app.global-shortcuts-handler nil))
  (when (and app.world-manager app.world-manager.drop)
    (app.world-manager:drop)
    (set app.world-manager nil))
  (set app.active-world-entry nil)
  (set app.first-person-controls nil)
  (set app.canvas-controls nil)
  (set app.active-pointer-controls nil)
  (set app.camera nil)
  (set app.graph nil)
  (set app.graph-view nil)
  (set app.object-selector nil)
  (set app.terrain-rect-pick-session nil)
  (set app.terrain-rect-pick-previous-state nil)
  (set app.terrain-paint-session nil)
  (set app.terrain-paint-previous-state nil)
  (set app.scene nil)
  (set app.canvas nil)
  (set app.preferred-interaction-surface :scene)
  (set app.active-interaction-surface :scene)
  (set app.scene-interactive? true)
  (set app.canvas-interactive? false)
  (set app.canvas-visible? false)
  (set app.world-tabs-builder nil)
  (set app.active-world-hud-contrib nil)
  (set app.active-world-hud-overlay nil)
  (when app.hoverables
    (app.hoverables:drop)
    (set app.hoverables nil))
  (when app.movables
    (app.movables:drop)
    (set app.movables nil))
  (when app.resizables
    (app.resizables:drop)
    (set app.resizables nil))
  (when app.intersectables
    (app.intersectables:drop)
    (set app.intersectables nil))
  (when app.system-cursors
    (app.system-cursors:drop)
    (set app.system-cursors nil))
  (when app.browser-cube-surface
    (app.browser-cube-surface:drop)
    (set app.browser-cube-surface nil))
  (when app.hud
    (clear-active-world-hud-overlay)
    (app.hud:drop)
    (set app.hud nil))
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
  (set app.canvas-focus-scope nil)
  (set app.hud-focus-scope nil)
  (when app.profiler
    (app.profiler.set_enabled false)
    (set app.profiler nil))
  (when app.remote-control
    (app.remote-control:drop)
    (set app.remote-control nil))
  (when (and app.kernels app.kernels.drop)
    (app.kernels:drop)
    (set app.kernels nil))
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
  (when (and app.window-settings-dirty app.settings app.settings.save)
    (app.settings.save)
    (set app.window-settings-dirty false))
  (when (and app.settings app.settings.drop)
    (app.settings.drop)
    (set app.settings nil))
  (set app.runtime-performance-state nil)
  (set app.runtime-performance-control-mode nil)
  (set app.runtime-performance-active-mode nil)
  (set app.runtime-performance-fps-cap nil)
  (set app.runtime-performance-physics-paused nil)
  (set app.startup-physics-pause-owner nil)
  (set app.runtime-performance-input-paused nil)
  (set app.runtime-performance-ui-paused nil)
  (set app.runtime-performance-source nil)
  (set app.runtime-performance-active-override nil)
  (sync-physics-paused-state)
  )

(when (and app.engine AppConfig.run-main)
  (when app.engine-autocreated
    (set app.engine (EngineModule.Engine (load-window-startup-options)))
    (set app.engine-autocreated false))
  (when (not (app.engine:start))
    (error "[space] engine failed to start (window/GL init failed)"))
  (app.init)
  (app.engine:run)
  (app.drop)
  (app.engine:shutdown))

{:install-app-shell! install-app-shell!
 :bind-active-world-runtime installable-bind-active-world-runtime}
