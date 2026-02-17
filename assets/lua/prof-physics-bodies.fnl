(global app {})
(local EngineModule (require :engine))
(local glm (require :glm))
(local os os)
(local string string)
(local package package)
(local debug debug)
(local logging (require :logging))
(var textures (require :textures))

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
  (set (. package.preload "font") (fn [] FakeFont)))

(install-fake-renderers)
(install-fake-font)

(set app.disable_font_textures false)
(when (not textures)
  (set textures {}))
(when (not textures.load-texture-async)
  (local stub (fn [name path]
                {:id (tonumber (tostring (string.byte name 1) 10))
                 :name name
                 :path path
                 :ready true
                 :width 1
                 :height 1}))
  (set textures.load-texture stub)
  (set textures.load-texture-async stub))
(when (not textures.load-cubemap)
  (local cube-stub (fn [_files] {:id 1 :ready true}))
  (set textures.load-cubemap cube-stub)
  (set textures.load-cubemap-async cube-stub))

(local MockOpenGL (require :mock-opengl))
(local global-mock (MockOpenGL))
(global-mock:install)

(local FlamegraphProfiler (require :flamegraph-profiler))

(set app.engine (EngineModule.Engine {:headless true}))

(local _ (require :main))
(local Container (require :container))
(app.engine:start)

(local default-output-path "prof/physics-bodies.folded")
(local viewport {:width 960 :height 640})
(local frame-delta (/ 1.0 60.0))
(local spawn-count (or (tonumber (os.getenv "SPACE_PROF_CUBOID_SPAWN_COUNT")) 24))
(local warmup-frames (or (tonumber (os.getenv "SPACE_PROF_CUBOID_WARMUP_FRAMES")) 10))
(local profiled-frames (or (tonumber (os.getenv "SPACE_PROF_CUBOID_PROFILE_FRAMES")) 90))

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
  (logging.info "SPACE_FENNEL_FLAMEGRAPH disabled; not recording physics-bodies profile.")
  (os.exit 0))

(local profiler (FlamegraphProfiler {:output-path output-path}))

(fn emit-initial-viewport []
  (local payload {:width viewport.width :height viewport.height :timestamp 0})
  (if (and app.engine.events app.engine.events.window-resized)
      (app.engine.events.window-resized.emit payload)
      (do
        (app.set-viewport {:width viewport.width :height viewport.height})
        (app.reset-projection))))

(fn spawn-physics-bodies []
  (local cols 8)
  (local rows 5)
  (local spacing 6)
  (local base-height 12)
  (local layer-step 5)
  (for [idx 0 (- spawn-count 1)]
    (local col (% idx cols))
    (local row (% (math.floor (/ idx cols)) rows))
    (local layer (math.floor (/ idx (* cols rows))))
    (local x (* (- col (/ (- cols 1) 2)) spacing))
    (local z (* (- row (/ (- rows 1) 2)) spacing))
    (local y (+ base-height (* layer layer-step)))
    (app.scene:add-physics-body {:position (glm.vec3 x y z)
                                   :size (glm.vec3 4 4 4)})))

(fn run-frames [count]
  (for [_ 1 count]
    (app.update frame-delta)))

(fn rebuild-empty-scene []
  (app.scene:build (fn [ctx]
                     ((Container {:children []}) ctx))))

(fn profile-physics-bodies []
  (app.init)
  (emit-initial-viewport)
  (rebuild-empty-scene)
  (run-frames warmup-frames)
  (profiler.start)
  (spawn-physics-bodies)
  (run-frames profiled-frames))

(local call-result (table.pack (xpcall profile-physics-bodies debug.traceback)))
(local ok (. call-result 1))
(local err (. call-result 2))
(profiler.stop_and_flush)
(when (and app.drop app.hoverables)
  (app.drop))

(app.engine:shutdown)

(if ok
    (logging.info (.. "Physics bodies profile written to " output-path))
    (error err))

true
