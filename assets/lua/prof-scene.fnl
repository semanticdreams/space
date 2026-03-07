(global app {})
(local EngineModule (require :engine))
(local os os)
(local string string)
(local debug debug)
(local package package)
(local logging (require :logging))
(local ProfOutputPath (require :prof-output-path))

(fn install-fake-renderers []
  (fn FakeRenderers []
    (fn consume-vector [vector]
      (when (and vector vector.length)
        (vector:length)))

    (fn consume-draw-list [entries]
      (when entries
        (each [_ entry (ipairs entries)]
          (consume-vector (and entry entry.vector))
          (consume-vector (and entry entry.clip-vector))
          (consume-vector (and entry entry.clip-group-vector))
          (consume-vector (and entry entry.glyph-vector))
          (consume-vector (and entry entry.glyph-group-vector))
          (consume-vector (and entry entry.group-vector))
          (consume-vector (and entry entry.group-clip-index-vector))
          (consume-vector (and entry entry.group-depth-index-vector)))))

    (fn draw-target [_self target]
      (when (and target target.get-triangle-vector)
        (consume-vector (target:get-triangle-vector))
        (when target.get-quad-draw-list
          (consume-draw-list (target:get-quad-draw-list)))
        (when target.get-text-ssbo-draw-list
          (consume-draw-list (target:get-text-ssbo-draw-list)))))

    (fn update [self]
      (when app.scene
        (self:draw-target app.scene))
      (when app.hud
        (self:draw-target app.hud)))

    {:update update
     :draw-target draw-target
     :on-viewport-changed (fn [_ _] nil)
     :drop (fn [_] nil)})

  (set (. package.preload "renderers") (fn [] FakeRenderers))
  (set (. package.loaded "renderers") FakeRenderers))

(fn install-fake-font []
  (fn FakeFont [_opts]
    (local glyph {:advance 1.0
                  :planeBounds {:left 0 :bottom 0 :right 1 :top 1}
                  :atlasBounds {:left 0 :bottom 0 :right 1 :top 1}})
    {:metadata {:metrics {:lineHeight 1.0
                          :ascender 0.5
                          :descender -0.5}
                :atlas {:width 1 :height 1}}
     :glyph-map {32 glyph
                 63 glyph
                 65533 glyph}
     :advance 1.0})
  (set (. package.preload "font") (fn [] FakeFont))
  (set (. package.loaded "font") nil))

(install-fake-renderers)
(install-fake-font)

(local MockOpenGL (require :mock-opengl))
(local global-mock (MockOpenGL))
(global-mock:install)

(set app.disable_font_textures false)

(local FlamegraphProfiler (require :flamegraph-profiler))

(set app.engine (EngineModule.Engine {:headless true}))

(local _ (require :main))
(app.engine:start)

(local default-output-path "prof/space-scene-profile.folded")
(local viewport {:width 450 :height 680})
(local frame-delta (/ 1.0 60.0))

(local output-path (ProfOutputPath.resolve default-output-path))

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
