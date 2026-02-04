(global app {})
(local EngineModule (require :engine))
(local glm (require :glm))
(local os os)
(local string string)
(local debug debug)
(local package package)
(local math math)
(local logging (require :logging))

(set app.engine (EngineModule.Engine {:headless true}))

(local _ (require :main))
(local DrawBatcher (require :draw-batcher))
(local TerminalRenderer (require :terminal-renderer))
(local FlamegraphProfiler (require :flamegraph-profiler))

(local {:VectorBuffer VectorBuffer :VectorHandle VectorHandle} (require :vector-buffer))
(set app.disable_font_textures false)
(app.engine:start)

(local default-output-path "prof/terminal.folded")
(local rows 60)
(local cols 200)
(local spam-lines 4000)
(local spam-width 120)
(local frame-count 30)
(local frame-delta (/ 1.0 60.0))
(local triangle-vector (VectorBuffer))
(local text-vectors {})

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

(fn make-cell [codepoint]
  {:codepoint codepoint
   :fg-r 200 :fg-g 220 :fg-b 255
   :bg-r 10 :bg-g 10 :bg-b 20
   :bold false :underline false :italic false :reverse false})

(fn build-screen []
  (local rows-data [])
  (for [r 0 (- rows 1)]
    (local line [])
    (for [c 0 (- cols 1)]
      (local cp (+ 33 (math.fmod (+ r c) 90)))
      (table.insert line (make-cell cp)))
    (table.insert rows-data line))
  rows-data)

(fn make-term []
  (local cells (build-screen))
  (var dirty [{:top 0 :left 0 :bottom (- rows 1) :right (- cols 1)}])
  (local term {})
  (set term.get-dirty-regions (fn [] dirty))
  (set term.clear-dirty-regions (fn [] (set dirty [])))
  (set term.get-row
       (fn [_self row]
         (or (. cells (+ row 1)) [])))
  (set term.get-cell
       (fn [_self row col]
         (local line (. cells (+ row 1)))
         (or (and line (. line (+ col 1))) (make-cell 32))))
  (set term.get-cursor (fn [] {:row (- rows 1) :col 0 :visible false :blinking false}))
  (set term.get-size (fn [] {:rows rows :cols cols}))
  (set term.get-scrollback-size (fn [_] 0))
  (set term.get-scrollback-line (fn [_ _] []))
  (set term.update (fn [_] nil))
  (set term.inject-output (fn [_ _] nil))
  (values term (fn [] (set dirty [{:top 0 :left 0 :bottom (- rows 1) :right (- cols 1)}]))))

(fn add-basic-glyphs [font]
  (when font
    (local glyph {:planeBounds {:left 0 :right 1 :top 1 :bottom 0}
                  :atlasBounds {:left 0 :right 1 :top 1 :bottom 0}
                  :advance 1
                  :font font})
    (set (. font.glyph-map (string.byte "A")) glyph)
    (set (. font.glyph-map (string.byte "B")) glyph)
    (set (. font.glyph-map 32) glyph)
    (set (. font.glyph-map 65533) glyph))
  font)

(fn make-font [id atlas-size metrics]
  (add-basic-glyphs
    {:metadata {:atlas {:distanceRange 3.5
                        :width atlas-size
                        :height atlas-size}
                :metrics (or metrics {:ascender 6
                                      :descender -2
                                      :lineHeight 8})}
     :texture {:id id}
     :glyph-map {}}))

(fn make-style []
  (local font (make-font 1 8))
  (add-basic-glyphs font)
  {:color (glm.vec4 1 1 1 1)
   :scale 1
   :font font
   :italic-font font
   :bold-font font
   :bold-italic-font font})

(fn make-context []
  (local text-draw-batchers {})
  {:triangle-vector triangle-vector
   :get-text-vector (fn [_ font]
                      (when (not (. text-vectors font))
                        (set (. text-vectors font) (VectorBuffer)))
                      (when (not (. text-draw-batchers font))
                        (set (. text-draw-batchers font) (DrawBatcher {:stride 10})))
                      (. text-vectors font))
   :untrack-triangle-handle (fn [_ _] nil)
   :untrack-text-handle (fn [_ _ _] nil)})

(fn make-layout []
  (local layout {:position (glm.vec3 0 0 0)
                 :rotation (glm.quat 1 0 0 0)
                 :clip-region nil
                 :depth-offset-index 0})
  (set layout.effective-culled? (fn [_self] false))
  layout)

(fn profile-terminal [profiler]
  (logging.info "[prof-terminal] ctx")
  (io.flush)
  (local ctx (make-context))
  (local style (make-style))
  (logging.info "[prof-terminal] renderer")
  (io.flush)
  (local renderer (TerminalRenderer {:ctx ctx :style style}))
  (local (term reset-dirty) (make-term))
  (renderer:set-term term)
  (renderer:set-grid-size rows cols)
  (renderer:set-layout (make-layout))
  (reset-dirty)
  (renderer:mark-dirty {:full? true})
  (profiler.start)
  (logging.info "[prof-terminal] loop")
  (io.flush)
  (for [i 1 frame-count]
    (term:update)
    (renderer:update frame-delta))
  (profiler.stop_and_flush)
  (renderer:drop)
  (logging.info "[prof-terminal] drop done")
  (io.flush))

(local output-path (resolve-output-path))

(when (not output-path)
  (logging.info "SPACE_FENNEL_FLAMEGRAPH disabled; not recording terminal profile.")
  (os.exit 0))

(local profiler (FlamegraphProfiler {:output-path output-path}))

(local call-result (table.pack (xpcall (fn [] (profile-terminal profiler)) debug.traceback)))
(local ok (. call-result 1))
(local err (. call-result 2))

(app.engine:shutdown)

(if ok
    (logging.info (.. "Terminal profile written to " output-path))
    (error err))

true
