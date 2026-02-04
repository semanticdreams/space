(global app {})
(local EngineModule (require :engine))
(local os os)
(local string string)
(local debug debug)
(local package package)
(local logging (require :logging))

(fn install-fake-renderers []
  (fn FakeRenderers []
    (fn consume-vector [vector]
      (when (and vector vector.length)
        (vector:length)))

    (fn draw-target [_self target]
      (when (and target target.get-triangle-vector)
        (consume-vector (target:get-triangle-vector))
        (each [_ vector (pairs (target:get-text-vectors))]
          (consume-vector vector))))

    (fn update [self]
      (when app.scene
        (self:draw-target app.scene))
      (when app.hud
        (self:draw-target app.hud)))

    {:update update
     :draw-target draw-target
     :on-viewport-changed (fn [_ _] nil)
     :drop (fn [_] nil)})

  (set (. package.preload "renderers") (fn [] FakeRenderers)))

(install-fake-renderers)

(set app.disable_font_textures true)

(local FlamegraphProfiler (require :flamegraph-profiler))

(set app.engine (EngineModule.Engine {:headless true}))

(local _ (require :main))
(app.engine:start)

(local default-output-path "prof/space-scene-profile.folded")
(local viewport {:width 450 :height 680})
(local frame-delta (/ 1.0 60.0))

(fn to-lower [value]
  (and value (string.lower value)))

(fn use-default-output? [value]
  (local lower (to-lower value))
  (or (= value nil)
      (= value "")
      (= value "1")
      (= lower "true")
      (= lower "on")))

(fn flamegraph-disabled? [value]
  (local lower (to-lower value))
  (and value (or (= value "0")
                 (= lower "false")
                 (= lower "off"))))

(fn resolve-output-path []
  (local env (os.getenv "SPACE_FENNEL_FLAMEGRAPH"))
  (if (flamegraph-disabled? env)
      nil
      (if (use-default-output? env)
          default-output-path
          env)))

(local output-path (resolve-output-path))

(when (not output-path)
  (logging.info "SPACE_FENNEL_FLAMEGRAPH disabled; not recording scene profile.")
  (os.exit 0))

(local profiler (FlamegraphProfiler {:output-path output-path}))

(fn emit-initial-viewport []
  (local payload {:width viewport.width :height viewport.height :timestamp 0})
  (if (and app.engine.events app.engine.events.window-resized)
      (app.engine.events.window-resized.emit payload)
      (do
        (app.set-viewport {:width viewport.width :height viewport.height})
        (app.reset-projection))))

(fn profile-scene []
  (app.init)
  (emit-initial-viewport)
  (app.update frame-delta))

(profiler.start)
(local call-result (table.pack (xpcall profile-scene debug.traceback)))
(local ok (. call-result 1))
(local err (. call-result 2))
(profiler.stop_and_flush)
(app.drop)

(app.engine:shutdown)

(if ok
    (logging.info (.. "Scene profile written to " output-path))
    (error err))

true
