(local os os)
(local string string)
(local glm (require :glm))

(local NextLayout (require :next-app/layout))
(local Node NextLayout.Node)
(local QuadBatcher (require :next-app/quad-batcher))
(local TextSsboBatcher (require :text-ssbo-batcher))

(local x-gap 0.008)
(local y-gap 0.01)
(local columns 100)
(local bench-codepoints [110 111 100 101])

(fn make-bench-font []
  {:metadata {:atlas {:distanceRange 3.5
                      :width 512
                      :height 512}
              :metrics {:ascender 1.0
                        :lineHeight 1.2}}
   :texture {:id 1 :ready true}
   :glyph-map {110 {:planeBounds {:left 0 :right 0.56 :bottom -0.2 :top 0.8}
                    :atlasBounds {:left 0 :right 56 :bottom 0 :top 80}
                    :advance 0.58}
               111 {:planeBounds {:left 0 :right 0.58 :bottom -0.2 :top 0.8}
                    :atlasBounds {:left 56 :right 114 :bottom 0 :top 80}
                    :advance 0.6}
               100 {:planeBounds {:left 0 :right 0.57 :bottom -0.2 :top 0.8}
                    :atlasBounds {:left 114 :right 171 :bottom 0 :top 80}
                    :advance 0.59}
               101 {:planeBounds {:left 0 :right 0.54 :bottom -0.2 :top 0.8}
                    :atlasBounds {:left 171 :right 225 :bottom 0 :top 80}
                    :advance 0.56}
               65533 {:planeBounds {:left 0 :right 0.5 :bottom -0.2 :top 0.8}
                      :atlasBounds {:left 225 :right 275 :bottom 0 :top 80}
                      :advance 0.52}}})

(fn make-leaf [name]
  (var pulse 0.0)
  (var node nil)
  (fn measure-fn [self _mw _mh _md]
    (self:set-measure (+ 0.03 pulse) 0.02 0))
  (fn layout-fn [self width height depth]
    (self:set-size width height depth {:mark-dirty? false}))
  (set node
       (Node.new {:name name
                  :measure-fn measure-fn
                  :layout-fn layout-fn}))
  (set node.set-pulse
       (fn [self value]
         (when (not (= pulse value))
           (set pulse value)
           (self:mark-measure-dirty))))
  node)

(fn make-row [name children]
  (Node.new
    {:name name
     :children children
     :measure-fn (fn [self _mw _mh _md]
                   (var width 0.0)
                   (var height 0.0)
                   (each [i child (ipairs self.children)]
                     (child:run-measure 0 0 0)
                     (set width (+ width child.measured-width))
                     (when (< i (length self.children))
                       (set width (+ width x-gap)))
                     (when (> child.measured-height height)
                       (set height child.measured-height)))
                   (self:set-measure width height 0))
     :layout-fn (fn [self width height depth]
                  (self:set-size width height depth {:mark-dirty? false})
                  (var x 0.0)
                  (each [i child (ipairs self.children)]
                    (child:layout-set-frame x
                                            0
                                            0
                                            child.measured-width
                                            child.measured-height
                                            0
                                            (glm.quat 1 0 0 0))
                    (child:run-layout child.width child.height child.depth)
                    (set x (+ x child.width))
                    (when (< i (length self.children))
                      (set x (+ x x-gap)))))}))

(fn build-scene [widget-count]
  (local rows [])
  (local leaves [])
  (local row-count (math.ceil (/ widget-count columns)))
  (var index 1)
  (for [r 1 row-count]
    (local row-children [])
    (for [_ 1 columns]
      (when (<= index widget-count)
        (local leaf (make-leaf (.. "perf-leaf-" index)))
        (table.insert leaves leaf)
        (table.insert row-children leaf)
        (set index (+ index 1))))
    (table.insert rows (make-row (.. "perf-row-" r) row-children)))
  (local root
    (Node.new
      {:name "perf-root"
       :children rows
       :measure-fn (fn [self _mw _mh _md]
                     (var width 0.0)
                     (var height 0.0)
                     (each [i child (ipairs self.children)]
                       (child:run-measure 0 0 0)
                       (when (> child.measured-width width)
                         (set width child.measured-width))
                       (set height (+ height child.measured-height))
                       (when (< i (length self.children))
                         (set height (+ height y-gap))))
                     (self:set-measure width height 0))
       :layout-fn (fn [self width height depth]
                    (self:set-size width height depth {:mark-dirty? false})
                    (var y 0.0)
                    (each [i child (ipairs self.children)]
                      (child:layout-set-frame 0
                                              y
                                              0
                                              child.measured-width
                                              child.measured-height
                                              0
                                              (glm.quat 1 0 0 0))
                      (child:run-layout child.width child.height child.depth)
                      (set y (+ y child.height))
                      (when (< i (length self.children))
                        (set y (+ y y-gap)))))}))
  (root:set-local-position -0.95 -0.95 0 (glm.quat 1 0 0 0))
  {:root root
   :leaves leaves
   :quad-batcher (QuadBatcher {})
   :text-batcher (TextSsboBatcher {})
   :font (make-bench-font)
   :leaf-set (setmetatable {} {:__mode "k"})})

(fn tick-scene [scene frame]
  (local total (length scene.leaves))
  (for [i 1 64]
    (local index (+ (% (+ frame (* i 17)) total) 1))
    (local leaf (. scene.leaves index))
    (leaf:set-pulse (* (% (+ frame i) 9) 0.0008))))

(fn dirty-leaf-list [scene]
  (local out [])
  (each [_ node (ipairs (NextLayout.collect-submit-nodes scene.root))]
    (when (. scene.leaf-set node)
      (table.insert out node)))
  out)

(fn render-submit [scene leaves]
  (local submit-start (os.clock))
  (scene.quad-batcher:begin-frame)
  (scene.text-batcher:begin-frame)
  (local traversal-start (os.clock))
  (each [_ leaf (ipairs leaves)]
    (scene.quad-batcher:upsert-quad leaf
                                    {:matrix leaf.render-matrix
                                     :color (glm.vec4 0.22 0.47 0.92 1.0)
                                     :depth-offset 0})
    (scene.text-batcher:upsert-text leaf
                                    {:font scene.font
                                     :scale 0.03
                                     :codepoints bench-codepoints
                                     :group-matrix leaf.world-matrix}))
  (local traversal-seconds (- (os.clock) traversal-start))
  (scene.quad-batcher:end-frame)
  (scene.text-batcher:end-frame)
  (local submit-seconds (- (os.clock) submit-start))
  (local quad-stats (scene.quad-batcher:get-last-stats))
  (local text-stats (scene.text-batcher:get-last-stats))
  {:submit-seconds submit-seconds
   :traversal-seconds traversal-seconds
   :write-seconds (+ quad-stats.write-seconds text-stats.write-seconds)
   :quad-write-seconds quad-stats.write-seconds
   :text-write-seconds text-stats.write-seconds
   :quad-upsert-count quad-stats.upsert-count
   :text-upsert-count text-stats.upsert-count})

(fn run-bench [widget-count frames]
  (local scene (build-scene widget-count))
  (each [_ leaf (ipairs scene.leaves)]
    (set (. scene.leaf-set leaf) true))
  (local warmup 30)
  (for [i 1 warmup]
    (tick-scene scene i)
    (NextLayout.run-frame scene.root 2.0 2.0 0)
    (render-submit scene (dirty-leaf-list scene)))

  (var measure-seconds 0.0)
  (var layout-seconds 0.0)
  (var transform-seconds 0.0)
  (var render-seconds 0.0)
  (var render-traversal-seconds 0.0)
  (var render-write-seconds 0.0)
  (var render-quad-write-seconds 0.0)
  (var render-text-write-seconds 0.0)
  (var render-quad-upserts 0.0)
  (var render-text-upserts 0.0)

  (for [i 1 frames]
    (tick-scene scene i)
    (local stats (NextLayout.run-frame-profile scene.root 2.0 2.0 0))
    (set measure-seconds (+ measure-seconds stats.measure-seconds))
    (set layout-seconds (+ layout-seconds stats.layout-seconds))
    (set transform-seconds (+ transform-seconds stats.transform-seconds))
    (local submit-stats (render-submit scene (dirty-leaf-list scene)))
    (set render-seconds (+ render-seconds submit-stats.submit-seconds))
    (set render-traversal-seconds (+ render-traversal-seconds submit-stats.traversal-seconds))
    (set render-write-seconds (+ render-write-seconds submit-stats.write-seconds))
    (set render-quad-write-seconds (+ render-quad-write-seconds submit-stats.quad-write-seconds))
    (set render-text-write-seconds (+ render-text-write-seconds submit-stats.text-write-seconds))
    (set render-quad-upserts (+ render-quad-upserts submit-stats.quad-upsert-count))
    (set render-text-upserts (+ render-text-upserts submit-stats.text-upsert-count)))

  {:widgets widget-count
   :frames frames
   :measure-ms (* (/ measure-seconds frames) 1000.0)
   :layout-ms (* (/ layout-seconds frames) 1000.0)
   :transform-ms (* (/ transform-seconds frames) 1000.0)
   :render-ms (* (/ render-seconds frames) 1000.0)
   :render-traversal-ms (* (/ render-traversal-seconds frames) 1000.0)
   :render-write-ms (* (/ render-write-seconds frames) 1000.0)
   :render-quad-write-ms (* (/ render-quad-write-seconds frames) 1000.0)
   :render-text-write-ms (* (/ render-text-write-seconds frames) 1000.0)
   :render-quad-upserts (/ render-quad-upserts frames)
   :render-text-upserts (/ render-text-upserts frames)
   :render-gl-upload-ms 0.0})

(fn print-result [result]
  (local total (+ result.measure-ms
                  result.layout-ms
                  result.transform-ms
                  result.render-ms))
  (print (.. "next-app-perf widgets=" result.widgets
             " frames=" result.frames
             " layout=v2"))
  (print (.. "  measure_ms=" (string.format "%.4f" result.measure-ms)))
  (print (.. "  layout_ms=" (string.format "%.4f" result.layout-ms)))
  (print (.. "  transform_ms=" (string.format "%.4f" result.transform-ms)))
  (print (.. "  render_submit_ms=" (string.format "%.4f" result.render-ms)))
  (print (.. "    traversal_ms=" (string.format "%.4f" result.render-traversal-ms)))
  (print (.. "    vector_write_ms=" (string.format "%.4f" result.render-write-ms)))
  (print (.. "      quad_write_ms=" (string.format "%.4f" result.render-quad-write-ms)))
  (print (.. "      text_write_ms=" (string.format "%.4f" result.render-text-write-ms)))
  (print (.. "      quad_upserts_per_frame=" (string.format "%.2f" result.render-quad-upserts)))
  (print (.. "      text_upserts_per_frame=" (string.format "%.2f" result.render-text-upserts)))
  (print (.. "    gl_upload_ms=" (string.format "%.4f" result.render-gl-upload-ms)))
  (print (.. "  total_ms=" (string.format "%.4f" total))))

(fn main []
  (local frames 220)
  (each [_ widget-count (ipairs [1000 5000 10000])]
    (print-result (run-bench widget-count frames)))
  true)

{:main main}
