(local os os)
(local string string)
(local glm (require :glm))

(local {: Layout : LayoutRoot} (require :layout))
(local NextLayout (require :next-app/layout))

(local row-count 120)
(local col-count 6)
(local x-gap 0.01)
(local y-gap 0.008)

(fn old-leaf [name]
  (var pulse 0.0)
  (local node
    (Layout {:name name
             :measurer (fn [self]
                         (set self.measure (glm.vec3 (+ 0.06 pulse) 0.032 0)))
             :layouter (fn [self]
                         (set self.size self.measure))}))
  (set node.bump
       (fn [self value]
         (set pulse value)
         (self:mark-measure-dirty)))
  node)

(fn old-row [name children]
  (Layout {:name name
           :children children
           :measurer (fn [self]
                       (var w 0.0)
                       (var h 0.0)
                       (each [i child (ipairs self.children)]
                         (child:measurer)
                         (set w (+ w child.measure.x))
                         (when (< i (length self.children))
                           (set w (+ w x-gap)))
                         (when (> child.measure.y h)
                           (set h child.measure.y)))
                       (set self.measure (glm.vec3 w h 0)))
           :layouter (fn [self]
                       (set self.size self.measure)
                       (var x 0.0)
                       (each [i child (ipairs self.children)]
                         (set child.position (glm.vec3 x 0 0))
                         (child:layouter)
                         (set x (+ x child.size.x))
                         (when (< i (length self.children))
                           (set x (+ x x-gap)))))}))

(fn build-old-tree []
  (local rows [])
  (local leaves [])
  (for [r 1 row-count]
    (local row-children [])
    (for [c 1 col-count]
      (local leaf (old-leaf (.. "old-leaf-" r "-" c)))
      (table.insert leaves leaf)
      (table.insert row-children leaf))
    (table.insert rows (old-row (.. "old-row-" r) row-children)))
  (local root
    (Layout {:name "old-root"
             :children rows
             :measurer (fn [self]
                         (var w 0.0)
                         (var h 0.0)
                         (each [i child (ipairs self.children)]
                           (child:measurer)
                           (when (> child.measure.x w)
                             (set w child.measure.x))
                           (set h (+ h child.measure.y))
                           (when (< i (length self.children))
                             (set h (+ h y-gap))))
                         (set self.measure (glm.vec3 w h 0)))
             :layouter (fn [self]
                         (set self.size self.measure)
                         (var y 0.0)
                         (each [i child (ipairs self.children)]
                           (set child.position (glm.vec3 0 y 0))
                           (child:layouter)
                           (set y (+ y child.size.y))
                           (when (< i (length self.children))
                             (set y (+ y y-gap)))))}))
  (local layout-root (LayoutRoot {:log-dirt? false}))
  (root:set-root layout-root)
  (root:mark-measure-dirty)
  {:root root
   :layout-root layout-root
   :leaves leaves})

(fn node-run-measure [node mw mh md]
  (if node.run-measure-subtree
      (node:run-measure-subtree mw mh md)
      (node:run-measure mw mh md)))

(fn node-run-layout [node w h d]
  (if node.run-layout-subtree
      (node:run-layout-subtree w h d)
      (node:run-layout w h d)))

(fn node-set-frame [node x y z w h d rz]
  (if node.layout-set-frame
      (node:layout-set-frame x y z w h d rz)
      (node:set-frame x y z w h d rz {:mark-dirty? false})))

(fn next-leaf [layout-module name]
  (var pulse 0.0)
  (var node nil)
  (fn measure-fn [self _mw _mh _md]
    (self:set-measure (+ 0.06 pulse) 0.032 0))
  (fn layout-fn [self w h d]
    (self:set-size w h d {:mark-dirty? false}))
  (set node
       (layout-module.Node.new {:name name
                                :measure-fn measure-fn
                                :layout-fn layout-fn}))
  (set node.bump
       (fn [self value]
         (set pulse value)
         (self:mark-measure-dirty)))
  node)

(fn next-row [layout-module name children]
  (layout-module.Node.new
    {:name name
     :children children
     :measure-fn (fn [self _mw _mh _md]
                   (var w 0.0)
                   (var h 0.0)
                   (each [i child (ipairs self.children)]
                     (node-run-measure child 0 0 0)
                     (set w (+ w child.measured-width))
                     (when (< i (length self.children))
                       (set w (+ w x-gap)))
                     (when (> child.measured-height h)
                       (set h child.measured-height)))
                   (self:set-measure w h 0))
     :layout-fn (fn [self w h d]
                  (self:set-size w h d {:mark-dirty? false})
                  (var x 0.0)
                  (each [i child (ipairs self.children)]
                    (node-set-frame child x 0 0 child.measured-width child.measured-height 0 (glm.quat 1 0 0 0))
                    (node-run-layout child child.width child.height child.depth)
                    (set x (+ x child.width))
                    (when (< i (length self.children))
                      (set x (+ x x-gap)))))}))

(fn build-next-tree [layout-module label]
  (local rows [])
  (local leaves [])
  (for [r 1 row-count]
    (local row-children [])
    (for [c 1 col-count]
      (local leaf (next-leaf layout-module (.. label "-next-leaf-" r "-" c)))
      (table.insert leaves leaf)
      (table.insert row-children leaf))
    (table.insert rows (next-row layout-module (.. label "-next-row-" r) row-children)))
  (local root
    (layout-module.Node.new
      {:name (.. label "-next-root")
       :children rows
       :measure-fn (fn [self _mw _mh _md]
                     (var w 0.0)
                     (var h 0.0)
                     (each [i child (ipairs self.children)]
                       (node-run-measure child 0 0 0)
                       (when (> child.measured-width w)
                         (set w child.measured-width))
                       (set h (+ h child.measured-height))
                       (when (< i (length self.children))
                         (set h (+ h y-gap))))
                     (self:set-measure w h 0))
       :layout-fn (fn [self w h d]
                    (self:set-size w h d {:mark-dirty? false})
                    (var y 0.0)
                    (each [i child (ipairs self.children)]
                      (node-set-frame child 0 y 0 child.measured-width child.measured-height 0 (glm.quat 1 0 0 0))
                      (node-run-layout child child.width child.height child.depth)
                      (set y (+ y child.height))
                      (when (< i (length self.children))
                        (set y (+ y y-gap)))))}))
  {:root root
   :leaves leaves})

(fn tick-leaves [leaves frame]
  (local leaf-count (length leaves))
  (for [i 1 24]
    (local index (+ (% (+ frame (* i 19)) leaf-count) 1))
    (local leaf (. leaves index))
    (leaf:bump (* (% (+ frame i) 7) 0.002))))

(fn run-old [scene frames]
  (local warmup 40)
  (for [i 1 warmup]
    (tick-leaves scene.leaves i)
    (scene.layout-root:update))
  (local start (os.clock))
  (for [i 1 frames]
    (tick-leaves scene.leaves i)
    (scene.layout-root:update))
  (- (os.clock) start))

(fn run-next [layout-module scene frames]
  (local warmup 40)
  (for [i 1 warmup]
    (tick-leaves scene.leaves i)
    (layout-module.run-frame scene.root 2.2 2.8 0))
  (local start (os.clock))
  (for [i 1 frames]
    (tick-leaves scene.leaves i)
    (layout-module.run-frame scene.root 2.2 2.8 0))
  (- (os.clock) start))

(fn ms-per-frame [seconds frames]
  (* (/ seconds frames) 1000.0))

(fn main []
  (local frames 360)
  (local old-scene (build-old-tree))
  (local next-scene (build-next-tree NextLayout "next"))

  (local old-seconds (run-old old-scene frames))
  (local next-seconds (run-next NextLayout next-scene frames))
  (local old-ms (ms-per-frame old-seconds frames))
  (local next-ms (ms-per-frame next-seconds frames))
  (local speedup (if (> next-ms 0) (/ old-ms next-ms) 0))

  (print (.. "bench-next-vs-old-layout frames=" frames))
  (print (.. "old_layout_ms_per_frame=" (string.format "%.4f" old-ms)))
  (print (.. "next_layout_ms_per_frame=" (string.format "%.4f" next-ms)))
  (print (.. "speedup_old_over_next=" (string.format "%.3fx" speedup)))
  true)

{:main main}
