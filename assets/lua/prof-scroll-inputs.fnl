(global app (or app {}))

(local glm (require :glm))
(local os os)
(local math math)
(local string string)
(local debug debug)
(local logging (require :logging))

(local BuildContext (require :build-context))
(local {: Layout : LayoutRoot} (require :layout))
(local ListView (require :list-view))
(local Input (require :input))
(local Sized (require :sized))
(local FlamegraphProfiler (require :flamegraph-profiler))

(local default-output-path "prof/scroll-inputs.folded")
(local input-count 100)
(local lines-per-input 100)
(local line-length 60)
(local scroll-frames 120)
(local viewport-size (glm.vec3 80 40 0))

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

(fn make-font []
  (add-basic-glyphs
    {:metadata {:atlas {:distanceRange 3.5
                        :width 8
                        :height 8}
                :metrics {:ascender 6
                          :descender -2
                          :lineHeight 8}}
     :texture {:id 1}
     :glyph-map {}}))

(fn make-theme []
  (local font (make-font))
  {:name :profiling
   :font font
   :italic-font font
   :bold-font font
   :bold-italic-font font
   :text {:foreground (glm.vec4 0.92 0.94 0.98 1)
          :scale 1.6}
   :input {:background (glm.vec4 0.12 0.15 0.2 0.95)
           :hover-background (glm.vec4 0.16 0.19 0.24 0.95)
           :focused-background (glm.vec4 0.18 0.21 0.28 0.95)
           :foreground (glm.vec4 0.92 0.94 0.97 1)
           :placeholder (glm.vec4 0.58 0.62 0.72 0.85)
           :caret-normal (glm.vec4 0.95 0.73 0.31 1)
           :caret-insert (glm.vec4 0.32 0.69 0.38 1)
           :focus-outline (glm.vec4 0.9 0.52 0.12 0.9)}})

(fn make-clickables-stub []
  (local stub {})
  (set stub.register (fn [_self _obj] nil))
  (set stub.unregister (fn [_self _obj] nil))
  (set stub.register-right-click (fn [_self _obj] nil))
  (set stub.unregister-right-click (fn [_self _obj] nil))
  stub)

(fn make-hoverables-stub []
  (local stub {})
  (set stub.register (fn [_self _obj] nil))
  (set stub.unregister (fn [_self _obj] nil))
  stub)

(fn make-system-cursors-stub []
  (local stub {})
  (set stub.set-cursor (fn [_self _name] nil))
  stub)

(fn random-line [alphabet line-length]
  (local chars [])
  (local count (string.len alphabet))
  (for [i 1 line-length]
    (local idx (math.random count))
    (table.insert chars (string.sub alphabet idx idx)))
  (table.concat chars))

(fn random-text [alphabet line-count line-length]
  (local lines [])
  (for [i 1 line-count]
    (table.insert lines (random-line alphabet line-length)))
  (table.concat lines "\n"))

(fn build-items []
  (math.randomseed 1337)
  (local alphabet "abcdefghijklmnopqrstuvwxyz     ")
  (local items [])
  (for [i 1 input-count]
    (table.insert items (random-text alphabet lines-per-input line-length)))
  items)

(fn build-root-layout [element size]
  (Layout {:name "scroll-profile-root"
           :children [element.layout]
           :measurer (fn [self]
                       (element.layout:measurer)
                       (set self.measure size))
           :layouter (fn [self]
                       (set self.size self.measure)
                       (set element.layout.size self.size)
                       (set element.layout.position self.position)
                       (set element.layout.rotation self.rotation)
                       (set element.layout.depth-offset-index self.depth-offset-index)
                       (set element.layout.clip-region self.clip-region)
                       (element.layout:layouter))}))

(fn build-ui []
  (local theme (make-theme))
  (set app.themes {:get-active-theme (fn [] theme)})
  (local clickables (make-clickables-stub))
  (local hoverables (make-hoverables-stub))
  (local cursors (make-system-cursors-stub))
  (local layout-root (LayoutRoot))
  (local ctx (BuildContext {:theme theme
                            :clickables clickables
                            :hoverables hoverables
                            :system-cursors cursors
                            :layout-root layout-root}))
  (var list nil)
  (local items (build-items))
  (local list-builder
    (ListView {:name "scroll-input-list"
               :scroll true
               :reverse false
               :show-head false
               :items items
               :builder (fn [value child-ctx]
                          ((Input {:text value
                                   :multiline? true})
                           child-ctx))}))
  (local element
    ((Sized {:size viewport-size
             :child (fn [child-ctx]
                      (set list (list-builder child-ctx))
                      list)})
     ctx))
  (local root-layout (build-root-layout element viewport-size))
  (root-layout:set-root layout-root)
  (root-layout:mark-measure-dirty)
  (layout-root:update)
  {:layout-root layout-root
   :root-layout root-layout
   :element element
   :list list})

(fn profile-scroll [profiler]
  (logging.info "[prof-scroll-inputs] build")
  (io.flush)
  (local ui (build-ui))
  (local list ui.list)
  (local layout-root ui.layout-root)
  (when (and list list.set-scroll-offset)
    (list:set-scroll-offset 0))
  (layout-root:update)
  (local max-offset (or (and list list.scroll-view list.scroll-view.state list.scroll-view.state.max-offset) 0))
  (local steps (math.max 1 scroll-frames))
  (local step-size (if (> max-offset 0) (/ max-offset steps) 0))
  (logging.info (.. "[prof-scroll-inputs] max-offset=" (tostring max-offset) " frames=" (tostring steps)))
  (io.flush)
  (profiler.start)
  (for [i 1 steps]
    (when (and list list.set-scroll-offset)
      (list:set-scroll-offset (* step-size i)))
    (layout-root:update))
  (profiler.stop_and_flush)
  (when (and ui.element ui.element.drop)
    (ui.element:drop))
  (when (and ui.root-layout ui.root-layout.drop)
    (ui.root-layout:drop))
  (logging.info "[prof-scroll-inputs] done")
  (io.flush))

(local output-path (resolve-output-path))
(when (not output-path)
  (logging.info "SPACE_FENNEL_FLAMEGRAPH disabled; not recording scroll-inputs profile.")
  (os.exit 0))

(local profiler (FlamegraphProfiler {:output-path output-path}))

(local call-result (table.pack (xpcall (fn [] (profile-scroll profiler)) debug.traceback)))
(local ok (. call-result 1))
(local err (. call-result 2))

(if ok
    (logging.info (.. "Scroll-inputs profile written to " output-path))
    (error err))

true
