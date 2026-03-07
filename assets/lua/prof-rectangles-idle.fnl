(global app {})
(local EngineModule (require :engine))
(local glm (require :glm))
(local os os)
(local string string)
(local debug debug)
(local logging (require :logging))
(local FlamegraphProfiler (require :flamegraph-profiler))
(local ProfOutputPath (require :prof-output-path))

(set app.engine (EngineModule.Engine {:headless true}))

(local _ (require :main))
(local BuildContext (require :build-context))
(local RawRectangle (require :raw-rectangle))

(set app.disable_font_textures false)
(app.engine:start)

(local rectangle-count 2000)
(local frame-count 120)
(local mover-stride 10)
(local default-output-path "prof/rectangles-idle.folded")
(local output-path (ProfOutputPath.resolve default-output-path))

(when (not output-path)
  (logging.info "SPACE_FENNEL_FLAMEGRAPH disabled; not recording rectangles-idle profile.")
  (os.exit 0))

(local profiler (FlamegraphProfiler {:output-path output-path}))

(fn build-rectangles [ctx]
  (local out [])
  (for [i 1 rectangle-count]
    (local rect ((RawRectangle {}) ctx))
    (set rect.position (glm.vec3 (* (math.fmod i 80) 0.16)
                                 (* (math.floor (/ i 80)) 0.14)
                                 0))
    (set rect.size (glm.vec2 0.14 0.11))
    (set rect.depth-offset-index 0)
    (set rect.color (glm.vec4 0.2 0.28 0.42 1))
    (table.insert out rect))
  out)

(fn update-rectangles [rectangles phase]
  (each [i rect (ipairs rectangles)]
    (when (= (% i mover-stride) 0)
      (set rect.position (+ rect.position (glm.vec3 0.0002 (* 0.0004 (math.sin (+ phase rect.position.x))) 0))))
    (rect:update)))

(fn run-profile []
  (local ctx (BuildContext {}))
  (local rectangles (build-rectangles ctx))
  (local t0 (os.clock))
  (for [frame 1 frame-count]
    (update-rectangles rectangles frame))
  (local elapsed-ms (* (- (os.clock) t0) 1000.0))
  (each [_ rect (ipairs rectangles)]
    (rect:drop))
  (logging.info (.. "[prof-rectangles-idle] elapsed-ms=" (string.format "%.3f" elapsed-ms)
                    " rectangles=" rectangle-count
                    " frames=" frame-count
                    " mover-stride=" mover-stride))
  elapsed-ms)

(profiler.start)
(local call-result (table.pack (xpcall run-profile debug.traceback)))
(local ok (. call-result 1))
(local value (. call-result 2))
(profiler.stop_and_flush)

(app.engine:shutdown)

(if ok
    (do
      (logging.info (.. "Rectangles-idle profile written to " output-path))
      true)
    (error value))
