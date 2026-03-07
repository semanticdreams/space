(global app {})
(local EngineModule (require :engine))
(local glm (require :glm))
(local os os)
(local string string)
(local debug debug)
(local logging (require :logging))
(local FlamegraphProfiler (require :flamegraph-profiler))
(local ClipUtils (require :clip-utils))
(local ProfOutputPath (require :prof-output-path))

(set app.engine (EngineModule.Engine {:headless true}))

(local _ (require :main))
(local BuildContext (require :build-context))
(local RawRectangle (require :raw-rectangle))

(set app.disable_font_textures false)
(app.engine:start)

(local rectangle-count 1400)
(local frame-count 90)
(local default-output-path "prof/rectangles-clipped.folded")
(local output-path (ProfOutputPath.resolve default-output-path))

(when (not output-path)
  (logging.info "SPACE_FENNEL_FLAMEGRAPH disabled; not recording rectangles-clipped profile.")
  (os.exit 0))

(local profiler (FlamegraphProfiler {:output-path output-path}))

(fn make-clip [x y w h]
  {:bounds {:position (glm.vec3 x y 0)
            :rotation (glm.quat 1 0 0 0)
            :size (glm.vec3 w h 1)}})

(fn build-rectangles [ctx]
  (local out [])
  (for [i 1 rectangle-count]
    (local rect ((RawRectangle {}) ctx))
    (local x (* (math.fmod i 56) 0.22))
    (local y (* (math.floor (/ i 56)) 0.18))
    (set rect.position (glm.vec3 x y 0))
    (set rect.size (glm.vec2 0.18 0.12))
    (set rect.depth-offset-index (% i 4))
    (set rect.color (glm.vec4 0.2 (+ 0.1 (* 0.02 (% i 6))) 0.42 1))
    (set rect.clip-region (make-clip (- x 0.04) (- y 0.03) 0.26 0.18))
    (table.insert out rect))
  out)

(fn update-rectangles [rectangles phase]
  (each [i rect (ipairs rectangles)]
    (local clip rect.clip-region)
    (when (and clip clip.bounds)
      (local angle (* 0.0008 (+ phase (% i 17))))
      (set clip.bounds.rotation (glm.quat angle (glm.vec3 0 0 1)))
      (ClipUtils.update-region clip))
    (when (= (% i 7) 0)
      (set rect.position (+ rect.position (glm.vec3 0.0001 (* 0.0002 (math.sin (+ phase rect.position.x))) 0))))
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
  (logging.info (.. "[prof-rectangles-clipped] elapsed-ms=" (string.format "%.3f" elapsed-ms)
                    " rectangles=" rectangle-count
                    " frames=" frame-count))
  elapsed-ms)

(profiler.start)
(local call-result (table.pack (xpcall run-profile debug.traceback)))
(local ok (. call-result 1))
(local value (. call-result 2))
(profiler.stop_and_flush)

(app.engine:shutdown)

(if ok
    (do
      (logging.info (.. "Rectangles-clipped profile written to " output-path))
      true)
    (error value))
